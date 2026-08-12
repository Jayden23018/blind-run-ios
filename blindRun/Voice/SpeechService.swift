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

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public API

    /// 播报文本
    func speak(text: String) {
        let normalizedText = text.trimmed
        guard !normalizedText.isEmpty else { return }
        lastSpokenText = normalizedText
        latestRepeatableText = normalizedText
        // ⚠️ VoiceOver 开着时这一句会同时走无障碍通告和合成器，听感上可能是念两遍。
        // 2026-08-01 曾改成「VoiceOver 运行时只留合成器」，当天回退：
        // 两条通道各有不可替代的性质 —— 通告走 VoiceOver 自己的语速与队列（读屏用户常把语速调到
        // 14~16 字/秒，合成器这边是写死的默认语速），而合成器不会像通告那样在 VoiceOver 忙时被丢弃，
        // 这一点对 SOS 是硬要求。砍掉任何一条都有真实代价，而**双重播报本身还没在真机上确认过**。
        // 结论：不靠读代码拍板。真机听过之后再定，届时可能的方案是通告 + 按 VoiceOver 语速合成。
        postVoiceOverAnnouncement(normalizedText)
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: normalizedText)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        currentUtterance = utterance
        synthesizer.speak(utterance)
        // 入队即置位，**不等 `didStart` 代理**。代理是 `DispatchQueue.main.async` 派发的，
        // 而 `VoiceOrderWizard.listen` 紧接着 `speak` 就开始轮询 `isSpeaking`：等代理的话，
        // 第一次检查读到的还是 false，等待循环当场放行，麦克风在一个字都没念出来时就打开了。
        // `stop()` 那端本来就是同步置 false，两端对称。
        markSpeaking(true)
    }

    /// 兼容既有调用点的短方法名。
    func speak(_ text: String) {
        speak(text: text)
    }

    /// VoiceOver-only announcement for transient UI state such as search results.
    func announce(_ text: String) {
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
    func speakError(_ message: String) {
        speak(text: message)
        HapticFeedback.play(.error)
    }

    /// 停止播报
    func stop() {
        currentUtterance = nil
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
        case .noVolunteer:
            return "暂无可用志愿者，请稍后再试。"
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
    private func finish(_ utterance: AVSpeechUtterance) {
        guard utterance === currentUtterance else { return }
        currentUtterance = nil
        markSpeaking(false)
    }
}

/// 兼容仓库中已按 docs/09 命名接入的调用点。
typealias SpeechService = VoiceService
