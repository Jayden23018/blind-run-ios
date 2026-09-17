import AVFoundation
import CallKit
import Foundation
import OSLog
import UIKit

// MARK: - Announcement Priority

/// 播报优先级。设计交接包 `状态清单.md` §全局规则逐字：
/// **紧急求助 > 警示 > 对方操作 > 按需播报 > 每公里播报**。
///
/// `counterpartAction` 是 `VoiceService.speak` 的**默认档**。选它而不是另起一个 `.standard`：
/// 全仓 230 个既有调用点播的都是「刚刚发生了一件事」（状态推进、错误、表单反馈），
/// 语义上就是这一档；多一个只为默认值存在的档位会让「这句该排在哪」多一次没有答案的讨论。
///
/// 🔴 **同档 = 打断，不是排队。** 这是刻意保住的既有行为：
/// `speak` 从来都是先 `stopSpeaking(.immediate)`，230 个调用点全是围着它长起来的
/// （求助倒计时每秒盖掉上一秒那句就直接依赖它，见 `BlindOrderStatusViewModel.beginEmergencyCountdown`）。
/// 同档改成排队会让轮询里反复播的那类调用点堆成一串陈述句，而没有任何用例会红。
/// 排队只发生在**优先级不同**时 —— 那正是这一轮要新增的行为，也只影响显式传了优先级的那十几处。
enum AnnouncementPriority: Int, Comparable, CaseIterable {
    /// 每公里播报。最低档，且是唯一会因为排太久被丢掉的一档。
    case perKilometer
    /// 按需播报：用户自己按了「重复当前状态」/「播报我的位置」/「问一句」。
    case onDemand
    /// 对方操作：状态推进、开跑倒计时。**默认档。**
    case counterpartAction
    /// 警示：走散、陪跑员离线。
    case alert
    /// 紧急求助。
    case emergency

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - Announcement Queue

struct PendingAnnouncement: Equatable {
    let text: String
    let priority: AnnouncementPriority
    let enqueuedAt: Date
}

/// 播报队列的**纯逻辑**部分。不碰合成器、不碰音频会话、不碰时钟 ——
/// 时间一律由调用方传进来。
///
/// 为什么单独抽出来：这一层的每一条规则都只有真机能听，而「听起来对不对」不是可回归的判据。
/// 抽成纯结构之后五条规则各有一条用例（`AnnouncementQueueTests`），
/// 真机那一遍只需要确认「确实出声了、确实是这个顺序」。
struct AnnouncementQueue {
    enum Decision: Equatable {
        /// 立刻播（队列空闲，或来者优先级不低于正在播的那条）。
        case speakNow
        /// 排进队列，等正在播的那条结束。
        case enqueued
        /// 直接丢弃（目前只有「通话中的非警示」走这里）。
        case dropped
    }

    /// 每公里播报排队超过这么久就丢弃。`状态清单.md` §全局规则逐字「每公里播报排队超过 10 秒丢弃」。
    ///
    /// 丢弃在**出队时**判，不另起定时器：队列空闲时这一条本来就立刻播，
    /// 只有「正被更高优先级压着」才会等 —— 那一刻正好就是出队。
    static let perKilometerMaxQueueAge: TimeInterval = 10

    /// 通话中仍然允许播的最低档。`状态清单.md`「通话中只保留警示」。
    static let minimumPriorityDuringCall: AnnouncementPriority = .alert

    /// **每档至多一条。** 同档的新句子替换旧的，不追加。
    ///
    /// 这是「防叠声」最省事的落法：排队等待期间同一档反复发声（轮询、连续两个里程碑）
    /// 只会让用户听到最新那一条，而不是等队列排干时听一串过期的陈述。
    private(set) var pending: [PendingAnnouncement] = []

    static func isAllowedDuringCall(_ priority: AnnouncementPriority) -> Bool {
        priority >= minimumPriorityDuringCall
    }

    /// 新来一条该怎么办。`speaking` 是**正在播的那条**的优先级，`nil` = 此刻没在播。
    mutating func submit(
        _ announcement: PendingAnnouncement,
        speaking: AnnouncementPriority?,
        isCallActive: Bool
    ) -> Decision {
        guard !isCallActive || Self.isAllowedDuringCall(announcement.priority) else {
            return .dropped
        }
        // 「按需播报打断排队中的每公里播报」。用户刚按了按钮，此刻再念一句十秒前的里程
        // 只会让他以为按钮按错了。正在播的那一条不必特判 —— 按需档本来就高于每公里档，
        // 下面那个 `guard` 会让它直接抢过去。
        if announcement.priority == .onDemand {
            pending.removeAll { $0.priority == .perKilometer }
        }
        pending.removeAll { $0.priority == announcement.priority }
        guard let speaking, announcement.priority < speaking else {
            return .speakNow
        }
        pending.append(announcement)
        return .enqueued
    }

    /// 上一条播完了，下一条是谁。没有就返回 `nil`。
    mutating func next(now: Date, isCallActive: Bool) -> PendingAnnouncement? {
        pending.removeAll {
            $0.priority == .perKilometer
                && now.timeIntervalSince($0.enqueuedAt) > Self.perKilometerMaxQueueAge
        }
        if isCallActive {
            pending.removeAll { !Self.isAllowedDuringCall($0.priority) }
        }
        guard let best = pending.max(by: { $0.priority < $1.priority }) else { return nil }
        pending.removeAll { $0.priority == best.priority }
        return best
    }

    mutating func removeAll() {
        pending.removeAll()
    }

    /// VoiceOver 通告（`announce`）走不走得出去。
    ///
    /// 通告没有「播完了」这个回调，所以它**进不了上面那个队列** —— 排进去就再也出不来。
    /// 但它仍然要认优先级：开跑倒计时那三拍就是通告
    /// （`状态清单.md` §2 逐字「数字走 announcement 通道播报，不插入遍历顺序、不移动焦点」），
    /// 而它们不该盖掉此刻正在播的求助或警示。所以规则收成一条：**比正在播的那条低就不发**。
    static func allowsAnnouncement(
        _ priority: AnnouncementPriority,
        speaking: AnnouncementPriority?,
        isCallActive: Bool
    ) -> Bool {
        guard !isCallActive || isAllowedDuringCall(priority) else { return false }
        guard let speaking else { return true }
        return priority >= speaking
    }
}

// MARK: - Call State

/// 「此刻是不是在通话中」。
///
/// 用 CallKit 的 `CXCallObserver` 而不是 `AVAudioSession.isOtherAudioPlaying`：后者在放音乐时
/// 同样为真，而这两件事在本规则里的处置**正好相反** —— 音乐只压低（照播），通话只保留警示。
///
/// 观察器必须被持有，否则回调源随对象一起没了；这里挂在单例上，`calls` 每次现读。
/// 拿不到（某些地区 / 权限受限）时返回空数组 ⇒ 判「不在通话中」⇒ 照常播报，
/// 也就是**退回本次改动之前的行为**，不会静默丢掉一句播报。
final class CallStateMonitor: @unchecked Sendable {
    static let shared = CallStateMonitor()

    private let observer = CXCallObserver()

    private init() {}

    var hasActiveCall: Bool {
        observer.calls.contains { !$0.hasEnded }
    }
}

// MARK: - Announcement Cues

/// 播报的三种提示音。第四种（紧急倒计时音）早就有了，在 `EmergencyAlarm.countdownTick`。
///
/// **复用 `ToneSynthesizer`，不打包音频资源**，理由与 `RecordingCue` / `EmergencyAlarm` 同源。
/// 播放器按种类各持有一个、创建后永不释放 —— 这条不是优化而是防崩：播放中被释放会让
/// `AVAudioPlayer` 自己的完成回调 `finishedPlaying:` 打在已被复用的内存上，
/// 表现是**崩在任意一条与音频无关的用例上**（见 `RecordingCue.players` 的说明）。
///
/// 频率刻意避开已在用的四组（录音起 660/990、录音止 880/587、倒计时 1318.5/987.8、
/// 警报 740/988）：同一个 App 里两种提示音听混，等于两条都失效。
enum AnnouncementCue {
    enum Kind: Equatable, Hashable, CaseIterable {
        /// 前置音：单声 0.3 秒。每公里与按需播报前。
        case leadIn
        /// 注意音：两声短音，**无震动**。电量提醒用。
        ///
        /// ponytail: 本轮**没有调用点** —— 电量自播是阶段 4（§2-G 已批准走本机
        /// `UIDevice.batteryLevel`）。这里先把音色定下来，是因为四种提示音必须彼此可分辨，
        /// 而「可分辨」只有四个都在同一处定义时才判得了。接线一行：
        /// `speak(text:priority:)` 之前调 `AnnouncementCue.play(.attention)`。
        case attention
        /// 警示音：三连音 + 强震。走散 / 陪跑员离线用。
        case alert
    }

    static let leadInFrequencies: [Double] = [784]
    static let leadInSegmentDuration: TimeInterval = 0.3

    static let attentionFrequencies: [Double] = [1046.5, 1046.5]
    static let attentionSegmentDuration: TimeInterval = 0.09

    static let alertFrequencies: [Double] = [1174.7, 1174.7, 1174.7]
    static let alertSegmentDuration: TimeInterval = 0.09

    /// 播报要等它响完再开口，否则提示音和第一个字叠在一起，两个都听不清。
    /// 交给 `AVSpeechUtterance.preUtteranceDelay` 执行，不自己起定时器。
    static func duration(_ kind: Kind) -> TimeInterval {
        switch kind {
        case .leadIn: return leadInSegmentDuration * Double(leadInFrequencies.count)
        case .attention: return attentionSegmentDuration * Double(attentionFrequencies.count)
        case .alert: return alertSegmentDuration * Double(alertFrequencies.count)
        }
    }

    /// 哪一档播报带哪一种前置提示音。`nil` = 不加提示音。
    ///
    /// 对方操作与紧急求助刻意不带：前者一天要响几十次，加提示音等于给每一条状态更新配一声「叮」；
    /// 后者自己有 `EmergencyAlarm` 那条更响的通道，再叠一声只会把它盖住。
    static func leadIn(for priority: AnnouncementPriority) -> Kind? {
        switch priority {
        case .perKilometer, .onDemand: return .leadIn
        case .alert: return .alert
        case .counterpartAction, .emergency: return nil
        }
    }

    #if DEBUG
    /// 测试替身。设了就**接管**发声与震动，并记下发生了哪一次。理由同 `RecordingCue.observerForTesting`：
    /// 没有断言的实现和不存在的实现，在下一个人眼里是一样的。
    nonisolated(unsafe) static var observerForTesting: ((Kind) -> Void)?
    #endif

    /// 线程处理与 `HapticFeedback.play` 一致：调用点在轮询回调、WebSocket 回调和合成器代理里，
    /// 线程不确定，而播放器字典与 `UIFeedbackGenerator` 都只该在主线程上碰。
    static func play(_ kind: Kind) {
        let fire = { emit(kind) }
        if Thread.isMainThread {
            fire()
        } else {
            DispatchQueue.main.async(execute: fire)
        }
    }

    private nonisolated(unsafe) static var players: [Kind: AVAudioPlayer] = [:]

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "AidRun",
        category: "AnnouncementCue"
    )

    private static func emit(_ kind: Kind) {
        #if DEBUG
        if let observerForTesting {
            observerForTesting(kind)
            return
        }
        #endif
        // 响不出来**不该影响播报本身** —— 少一声提示是可用性损失，抛出去会把整条播报路径带崩。
        do {
            let player = try players[kind] ?? makePlayer(kind)
            // 复用同一个播放器，所以要自己回到开头。
            player.currentTime = 0
            player.play()
        } catch {
            logger.error("播报提示音播放失败：\(error.localizedDescription, privacy: .public)")
        }
        // 注意音**刻意不震**（`状态清单.md` 逐字「两声短音，无震动」）：电量提醒不值得把手上的
        // 注意力从路面拉走。警示音的「强震」取 `.warning` —— `.error` 在本仓库有确定语义
        // （求助未发出，见 `HapticFeedback.Kind.error`），借过来会把那一档洗掉。
        if kind == .alert {
            HapticFeedback.play(.warning)
        }
    }

    private static func makePlayer(_ kind: Kind) throws -> AVAudioPlayer {
        let data: Data
        switch kind {
        case .leadIn:
            data = ToneSynthesizer.wav(
                frequencies: leadInFrequencies, segmentDuration: leadInSegmentDuration
            )
        case .attention:
            data = ToneSynthesizer.wav(
                frequencies: attentionFrequencies, segmentDuration: attentionSegmentDuration
            )
        case .alert:
            data = ToneSynthesizer.wav(
                frequencies: alertFrequencies, segmentDuration: alertSegmentDuration
            )
        }
        let created = try AVAudioPlayer(data: data)
        created.volume = 1
        created.prepareToPlay()
        players[kind] = created
        return created
    }

    #if DEBUG
    /// 让测试能对播放器**对身份**——「同一种提示音始终是同一个对象」正是防 use-after-free 的不变式。
    static func playerForTesting(_ kind: Kind) -> AVAudioPlayer? { players[kind] }
    #endif
}
