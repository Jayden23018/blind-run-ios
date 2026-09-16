import AVFoundation
import Combine
import SwiftUI
import UIKit

// MARK: - Voice Service

/// 集中式 TTS 服务，使用 AVSpeechSynthesizer 播报状态变化和错误提示。
/// 通过记录上次播报状态，避免轮询时重复播报。
final class VoiceService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {

    private nonisolated(unsafe) let synthesizer = AVSpeechSynthesizer()
    @Published private(set) var isSpeaking = false
    @Published private(set) var lastSpokenText: String?
    @Published private(set) var latestRepeatableText: String?
    @Published private(set) var lastVoiceOverAnnouncement: String?
    private(set) var lastSpokenStatus: RunOrderStatus?
    /// 当前正在播的那一条。**代理回调必须拿它对一次身份才能清 `isSpeaking`。**
    ///
    /// `speak(text:)` 是「先 `stopSpeaking(.immediate)` 再播新的」。旧的那条随后会回一次
    /// `didCancel` —— 如果不对身份就清标志，这次迟到的回调会把**新**那条的播放状态抹成「没在播」，
    /// 而 `VoiceOrderWizard` 正靠这个标志决定什么时候开麦：抹掉就等于当场截断读回，
    /// 也就是 2026-08-06 报障的那个现象，只不过变成偶发。
    private nonisolated(unsafe) var currentUtterance: AVSpeechUtterance?

    /// 正在播的那条是哪一档。`nil` = 此刻没在播。与 `currentUtterance` 同生同灭。
    private nonisolated(unsafe) var currentPriority: AnnouncementPriority?

    /// 正在播的那条最晚算到什么时候。
    ///
    /// 🔴 **合成器代理丢事件在这个仓库是见过的真实故障**，不是假想的
    /// —— `VoiceOrderWizard.speechSettleDeadline` 存在的理由逐字就是这一条。
    /// 没有这道兜底的话，一次丢失的 `didFinish` 会让 `currentPriority` 永远停在某一档，
    /// 此后每一条更低档的播报都被静默排队或丢弃，表现是「App 从某一刻起就不说话了」，
    /// 而屏幕上一个字都不会变 —— 正是本仓库反复出事的那种静默降级。
    private nonisolated(unsafe) var currentDeadline: Date?

    /// 排队中的播报。规则全在 `AnnouncementQueue`（纯结构，单测钉着）。
    ///
    /// 与 `currentUtterance` 用同一套 `nonisolated(unsafe)`：`speak` 的调用点散在轮询回调、
    /// WebSocket 回调和 `Task` 里，线程不确定，而合成器代理回调回主线程。
    /// 这是本类既有的做法，不在这一轮里另起一套加锁方案。
    private nonisolated(unsafe) var queue = AnnouncementQueue()

    /// 「此刻是不是在通话中」。默认走 CallKit，**测试可以替换**——
    /// 单测里真的去打一通电话是做不到的，而「通话中只保留警示」是一条必须能回归的规则。
    nonisolated(unsafe) var isCallActive: () -> Bool = { CallStateMonitor.shared.hasActiveCall }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public API

    #if DEBUG
    /// 本实例播过的每一句，按顺序。**只给测试用。**
    ///
    /// 为什么不能拿 `lastSpokenText` 代替：它只是最后一句的快照，而本仓库反复出事的形态是
    /// **同一流程里两处 speak，后说的把先说的从半句切断**。那种回归里最后一句往往是对的，
    /// 于是 `lastSpokenText` 照样等于期望值 —— 断言全绿，用户却听到一句残片加一句正确的。
    /// 要抓它只能看**调用了几次**，所以这里留一条历史。
    private(set) var spokenHistoryForTesting: [String] = []

    func resetSpokenHistoryForTesting() {
        spokenHistoryForTesting = []
    }
    #endif

    /// 播报文本。
    ///
    /// `priority` **带默认值，既有调用点一行都不用改**：全仓 230 个 `speak` / `speakError` /
    /// `announce` 分布在 31 个文件里，改签名会把整个仓库碰一遍。默认档与同档打断的取法
    /// 见 `AnnouncementPriority` —— 不传优先级时的行为与本次改动之前**逐字相同**。
    func speak(text: String, priority: AnnouncementPriority = .counterpartAction) {
        let normalizedText = text.trimmed
        guard !normalizedText.isEmpty else { return }
        clearStaleUtteranceIfNeeded()
        let announcement = PendingAnnouncement(
            text: normalizedText, priority: priority, enqueuedAt: Date()
        )
        switch queue.submit(announcement, speaking: currentPriority, isCallActive: isCallActive()) {
        case .speakNow:
            play(announcement)
        case .enqueued, .dropped:
            break
        }
    }

    /// 兼容既有调用点的短方法名。
    func speak(_ text: String, priority: AnnouncementPriority = .counterpartAction) {
        speak(text: text, priority: priority)
    }

    /// 真正把一条送进合成器。**只有这里能写 `lastSpokenText` / `latestRepeatableText`。**
    ///
    /// 🔴 写在这里而不是 `speak` 里：排队中的那条**可能永远不会播**
    /// （每公里档排够 10 秒就丢）。在入队时就记成「说过了」，会让「重复当前状态」
    /// 念出一句用户从来没听到过的话 —— 而那个按钮存在的全部意义就是复述刚才那句。
    private func play(_ announcement: PendingAnnouncement) {
        lastSpokenText = announcement.text
        latestRepeatableText = announcement.text
        #if DEBUG
        spokenHistoryForTesting.append(announcement.text)
        #endif
        // ⚠️ VoiceOver 开着时这一句会同时走无障碍通告和合成器，听感上可能是念两遍。
        // 2026-08-01 曾改成「VoiceOver 运行时只留合成器」，当天回退：
        // 两条通道各有不可替代的性质 —— 通告走 VoiceOver 自己的语速与队列，而合成器不会像通告那样
        // 在 VoiceOver 忙时被丢弃，这一点对 SOS 是硬要求。砍掉任何一条都有真实代价。
        //
        // 两条通道**语速不一致**那一半已由 `makeUtterance` 修掉（见那里）。剩下的
        // 「同一句听感上念两遍」仍未在真机上确认过，要改先听，不靠读代码拍板。
        postVoiceOverAnnouncement(announcement.text)
        synthesizer.stopSpeaking(at: .immediate)
        let cue = AnnouncementCue.leadIn(for: announcement.priority)
        if let cue {
            AnnouncementCue.play(cue)
        }
        let utterance = Self.makeUtterance(
            announcement.text,
            leadInDelay: cue.map(AnnouncementCue.duration) ?? 0
        )
        currentUtterance = utterance
        currentPriority = announcement.priority
        currentDeadline = Date().addingTimeInterval(
            VoiceOrderWizard.settleTimeout(forCharacterCount: announcement.text.count)
        )
        synthesizer.speak(utterance)
        // 入队即置位，**不等 `didStart` 代理**。代理是 `DispatchQueue.main.async` 派发的，
        // 而 `VoiceOrderWizard.listen` 紧接着 `speak` 就开始轮询 `isSpeaking`：等代理的话，
        // 第一次检查读到的还是 false，等待循环当场放行，麦克风在一个字都没念出来时就打开了。
        // `stop()` 那端本来就是同步置 false，两端对称。
        markSpeaking(true)
    }

    /// 播报用的 utterance。**语速跟随用户，不写死默认值。**
    ///
    /// `prefersAssistiveTechnologySettings` 一开，VoiceOver 在跑时系统会拿**用户自己选的音色与语速**
    /// 覆盖下面这三行；VoiceOver 没开时才用下面的值。SDK 头文件原文
    /// （`AVSpeechSynthesis.h`，`API_AVAILABLE(ios(14.0))`，本仓库部署目标 16.0 所以不需要
    /// `#available`）：
    ///
    /// > If an assistive technology is on, like VoiceOver, the user's selected voice, rate and other
    /// > settings will be used for this speech utterance instead of the default values.
    ///
    /// 修的是一个**每一句播报都在犯**的缺陷：读屏用户日常把语速调到远高于默认，而这里此前写死
    /// `AVSpeechUtteranceDefaultSpeechRate`，于是 App 自己的播报比用户习惯的慢一大截 —— 越熟练的
    /// 用户越难受，且和同一句话的 VoiceOver 通告快慢不一，两条通道互相拖。
    ///
    /// 三行属性赋值**刻意保留**：VoiceOver 没开时（低视力用户、明眼陪同者）它们仍是生效值，
    /// 删掉等于把中文音色也一并丢了。
    ///
    /// ⚠️ 头文件同段还写了 `querying the properties will not reflect the user's settings` ——
    /// 读 `utterance.rate` 永远读回我们写进去的值，**测不出实际语速**。所以下面那条用例只能断言
    /// 开关本身，真实听感必须真机开 VoiceOver 人耳验（见记忆 `audio-correctness-needs-real-ears-not-code-reading`）。
    ///
    /// `leadInDelay` 让提示音先响完再开口，交给系统的 `preUtteranceDelay` 执行 ——
    /// 自己起一个 `Task.sleep` 会多一条取消路径，而提示音和第一个字叠在一起是确定的可用性损失。
    static func makeUtterance(_ text: String, leadInDelay: TimeInterval = 0) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.prefersAssistiveTechnologySettings = true
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = leadInDelay
        return utterance
    }

    /// VoiceOver-only announcement for transient UI state such as search results.
    ///
    /// **通告进不了队列**（它没有「播完了」这个回调，排进去就出不来），但它认优先级：
    /// 比正在播的那条低就不发。判据在 `AnnouncementQueue.allowsAnnouncement`。
    ///
    /// 开跑倒计时那三拍走的就是这条路 —— `状态清单.md` §2 逐字要求数字走 announcement 通道
    /// 「不插入遍历顺序、不移动焦点」，所以它不能改走合成器；这一道闸是它认优先级的唯一方式。
    func announce(_ text: String, priority: AnnouncementPriority = .counterpartAction) {
        clearStaleUtteranceIfNeeded()
        guard AnnouncementQueue.allowsAnnouncement(
            priority, speaking: currentPriority, isCallActive: isCallActive()
        ) else { return }
        postVoiceOverAnnouncement(text)
    }

    /// 播报订单状态变化（防重复）
    /// 只在状态真正变化时播报，避免轮询时反复播报同一状态。
    ///
    /// 触觉挂在这里而不是各个业务分支上：这两个重载是**状态变化播报的唯一 funnel**
    /// （`BlindOrderStatusView.apply` 与首页都从这儿过），且防重复的 guard 已经在这一层，
    /// 挂在下游会跟着轮询反复震。触觉是语音的冗余通道，两者必须同生同灭 ——
    /// 单独一下震动没有语义，用户分不出是接单还是取消。见 `HapticFeedback`。
    @discardableResult
    func speakStatusChange(_ status: RunOrderStatus) -> Bool {
        guard status != lastSpokenStatus else { return false }
        lastSpokenStatus = status
        speak(text: Self.statusAnnouncement(for: status))
        status.haptic.map(HapticFeedback.play)
        return true
    }

    @discardableResult
    func speakStatusChange(_ status: RunOrderStatus, text: String) -> Bool {
        guard status != lastSpokenStatus else { return false }
        lastSpokenStatus = status
        speak(text: text)
        status.haptic.map(HapticFeedback.play)
        return true
    }

    /// 重复播报当前状态（"重复当前状态"按钮调用）
    func repeatCurrentStatus() {
        speak(text: latestRepeatableText ?? "当前没有进行中的订单。")
    }

    /// 播报错误信息。
    ///
    /// 触觉的第二个接线点，语义精确到可以直接映射：**App 刚刚念出了一条错误**。
    /// 出错恰恰是最可能漏听的时刻（用户在做别的事、环境吵、耳机在放东西），
    /// 而漏听一条错误的代价通常大于漏听一条进度。
    ///
    /// 求助失败走的就是这里（三个 view model 都是 `outcome.isFailure ? speakError : speak`），
    /// 所以「求助未发出、请自己拨 110」这条会震 `.error` ——
    /// 这是求助路径上最不能被漏掉的一条消息。
    ///
    /// **求助成功刻意不震**：它走的是通用的 `speak(_:)`，在那儿挂触觉等于每一句播报都震一下，
    /// 频繁到失去语义。危险的方向是「以为发出去了其实没有」，那一侧已经被这里盖住。
    ///
    /// 第一版挂在 `EmergencyCoordinator.state` 的 `didSet` 上，覆盖面更全（成功也震）。
    /// 换成这里**不是**因为那样有错 —— 当时误判了一条 flaky 用例的归因，
    /// 复跑后证明与 `didSet` 无关。改用方法 funnel 纯粹因为它更简单：
    /// 不碰属性观察器，且语义正好落在「刚念出一条错误」上，顺带覆盖了求助之外的全部错误播报。
    func speakError(_ message: String, priority: AnnouncementPriority = .counterpartAction) {
        speak(text: message, priority: priority)
        HapticFeedback.play(.error)
    }

    /// 代理没回来、而这条按字数算怎么也该念完了：当成没在播。
    ///
    /// **只清「正在播的那条」，不清队列。** 排着的那条随下一次 `finish` 正常出队；
    /// 每公里那档若已经排过 10 秒会在出队时自己丢掉。在这里顺手清空队列会让一次
    /// 迟到的代理回调变成「静默吞掉一条本该念的播报」，方向正好是这道兜底要防的那一种。
    ///
    /// `now` 带默认值只为**可测**：真机上等 8 秒看队列会不会自愈是测不了的，
    /// 而「这道兜底根本没接上」和「它工作正常」在耳朵里同样是一片安静。不是给生产调用的。
    func clearStaleUtteranceIfNeeded(now: Date = Date()) {
        guard currentPriority != nil, let currentDeadline, now >= currentDeadline else { return }
        currentUtterance = nil
        currentPriority = nil
        self.currentDeadline = nil
    }

    /// 停止播报
    func stop() {
        currentUtterance = nil
        currentPriority = nil
        currentDeadline = nil
        // 排着的也一起清掉。留着的后果是「按了停止，三秒后又自己念起来」——
        // 对看不见屏幕的人，那看起来像 App 不听指挥。
        queue.removeAll()
        synthesizer.stopSpeaking(at: .immediate)
        markSpeaking(false)
    }

    /// 重置最后播报状态（切换订单时调用）
    func resetLastStatus() {
        lastSpokenStatus = nil
        latestRepeatableText = nil
    }

    /// `isSpeaking` 的唯一写入口。主线程上同步写，别的线程派发过去 ——
    /// 与 `postVoiceOverAnnouncement` 同一套线程处理，理由也一样：
    /// 等待方（`VoiceOrderWizard.waitForSpeechToSettle`）在主线程上轮询，异步置位会被它读空。
    private func markSpeaking(_ speaking: Bool) {
        if Thread.isMainThread {
            isSpeaking = speaking
        } else {
            DispatchQueue.main.async { self.isSpeaking = speaking }
        }
    }

    private func postVoiceOverAnnouncement(_ text: String) {
        let normalizedText = text.trimmed
        guard !normalizedText.isEmpty else { return }
        lastVoiceOverAnnouncement = normalizedText
        let post = {
            UIAccessibility.post(notification: .announcement, argument: normalizedText)
        }
        if Thread.isMainThread {
            post()
        } else {
            DispatchQueue.main.async(execute: post)
        }
    }

    // MARK: - Status Copy Mapping (docs/09 section 7)

    static func statusAnnouncement(for status: RunOrderStatus) -> String {
        switch status {
        case .pendingMatch:
            return "订单提交成功，系统正在为你派单。"
        // 与 `RunOrderStatus.blindRunnerAnnouncement` 逐字相同。
        // 🚨 不提轮次、不提「换了一位」——「无声拒绝」要求盲人无从得知自己被谁拒过。
        case .pendingIntroCall:
            return "有位志愿者想陪你跑，可以打个电话聊聊。"
        // 与 `RunOrderStatus.blindRunnerAnnouncement` 逐字相同（同该文件其余各态的既有写法）。
        case .scheduledConfirmed:
            return "已经为你约好志愿者。到出发前如果计划有变，可以打电话告诉他。"
        case .pendingAccept:
            return "志愿者已接单，请前往或等待在预约出发地点。"
        case .driverEnRoute:
            return "志愿者已出发，正在前往出发地点。"
        case .driverArrived:
            return "志愿者已到达，请等待志愿者开始服务。"
        case .inProgress:
            return "服务已开始，请注意安全。"
        case .completed:
            return "服务已完成，感谢使用助盲跑。"
        case .cancelled:
            return "本次预约已取消。"
        case .rematching:
            return "正在确认志愿者状态，请稍候。"
        // `NO_VOLUNTEER` 是**终态**：后端派单彻底失败时订单已经是
        // `NO_VOLUNTEER` + `cancelledBy=SYSTEM`，这一单结束了。
        // 旧文案「暂无可用志愿者，请稍后再试」把它说成还能等 —— 对看不见屏幕的人，
        // 「被告知继续等一件已经结束的事」不是措辞问题，是事故。必须说出终态与出路。
        case .noVolunteer:
            return "没有匹配到志愿者，本次预约已取消，你可以重新发起一次。"
        // 后端新增了本客户端不认识的状态。宁可播一句「请刷新」，也不能因为编不出文案就静默 ——
        // 盲人用户没有别的渠道知道订单变了。
        case .unknown:
            return "订单状态有更新，请刷新页面或稍后重试。"
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        markSpeaking(true)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finish(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finish(utterance)
    }

    /// 只有「正在播的那一条」结束了才算播完 —— 见 `currentUtterance` 的说明。
    ///
    /// 🚩 **有下一条时不置 `isSpeaking = false`。** `VoiceOrderWizard.waitForSpeechToSettle`
    /// 靠这个标志决定什么时候开麦；中间闪一次 false 会让它在队列还没排干时就把麦克风打开。
    private func finish(_ utterance: AVSpeechUtterance) {
        guard utterance === currentUtterance else { return }
        currentUtterance = nil
        currentPriority = nil
        currentDeadline = nil
        if let next = queue.next(now: Date(), isCallActive: isCallActive()) {
            play(next)
        } else {
            markSpeaking(false)
        }
    }
}

/// 兼容仓库中已按 docs/09 命名接入的调用点。
typealias SpeechService = VoiceService
