import AVFoundation
import CoreHaptics
import OSLog
import UIKit

// MARK: - 紧急倒计时的声音

/// 倒计时那三秒的**非视觉**通道。
///
/// 这个 App 的用户在跑步：手机绑在腰上、戴着骨传导耳机、几乎不看屏幕
/// （Google Project Guideline 的观察，也是本仓库一贯的前提）。屏幕上那个从 3 数到 1 的大圆环
/// 对他们不存在 —— 声音和震动才是倒计时本身。
///
/// **复用 `ToneSynthesizer`，不打包音频资源。** 理由与 `RecordingCue` 同源：几段正弦波
/// 合成比维护二进制资源简单，也不用动 `project.pbxproj`（`AGENTS.md` §9 行级冻结）。
///
/// **不用 `AudioServicesPlaySystemSound`。** 那条走响铃 / 系统提示音通道，会被侧面静音拨杆关掉，
/// 而拨杆是个盲人看不见、也想不到要去检查的物理开关。`AVAudioPlayer` 走 App 自己的会话，
/// 而 App 在启动时就把分类配成了 `.playback`
/// （`SpeechInputService.prepareForPlaybackAtLaunch` → `configurePlaybackCategory`）——
/// 那个分类**静音档照常出声**，TTS 听得见它就听得见。
@MainActor
enum EmergencyAlarm {
    enum Kind: Equatable, Hashable {
        /// 倒计时每秒一声。
        case countdownTick
        /// 求助已发出 / 志愿者收到强提醒时的连续警报。
        case siren
    }

    /// 倒计时那一声：**下行双音**（高→低）。
    ///
    /// 方向本身携带语义，和 `RecordingCue` 用的是同一条道理（人对音高**方向**的敏感度
    /// 远高于对绝对音高的记忆）。这里刻意取下行 = 「在往下数」，而起听提示是上行 ——
    /// 两者在同一个 App 里不会被听混。
    ///
    /// 频率也刻意避开录音起止那两组（660/990、880/587）：`AGENTS.md` 意义上的
    /// 「全 App 独有的警报音，不得复用」说的就是这件事。
    static let countdownTickFrequencies: [Double] = [1318.5, 987.8]
    static let countdownTickSegmentDuration: TimeInterval = 0.085

    /// 连续警报：**四段上行的短促脉冲**，总长约 0.72 秒，循环播放。
    /// 上行 + 密集是警报的普遍形状（人对上行音高的紧迫感反应最强）。
    static let sirenFrequencies: [Double] = [740, 988, 740, 988]
    static let sirenSegmentDuration: TimeInterval = 0.18

    /// 播放器**按种类各持有一个、创建后永不释放**。
    ///
    /// 🔴 这不是优化，是防崩：2026-08-16 `RecordingCue` 曾经「每次发声 new 一个播放器、
    /// 覆盖同一个静态槽」，于是上一声还在播时就被释放，音频队列随后把
    /// `-[AVAudioPlayer finishedPlaying:]` 派回主线程、打在已被复用的内存上 ——
    /// 真机表现是**崩在任意一条与音频无关的用例上**
    /// （记忆 `finishedplaying-crash-means-player-freed-not-delegate`）。
    /// 倒计时这一声每秒触发一次、而一声只有 0.17 秒，正是同一个形状。
    private static var players: [Kind: AVAudioPlayer] = [:]

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "AidRun",
        category: "EmergencyAlarm"
    )

    #if DEBUG
    /// 测试替身。设了就**接管**发声与震动，并记下发生了哪一次。
    ///
    /// 这条接缝的理由与 `RecordingCue.observerForTesting` 逐字相同：没有断言的实现，
    /// 和不存在的实现在下一个人眼里是一样的 —— 而这是盲人判断「倒计时开始了没有」的
    /// 唯一非视觉信号。跑测时也不该真的在办公室里拉响警报。
    static var observerForTesting: ((Kind) -> Void)?
    #endif

    /// 倒计时每秒一声。`secondsRemaining` 只用来记日志与测试断言，不改音高 ——
    /// 三个不同音高会让人去听「现在是第几声」，而倒计时要的是「还在数」。
    static func countdownTick() {
        emit(.countdownTick, loops: 0)
    }

    /// 连续警报。**重复调用是幂等的**：已经在响就不重头开始。
    static func startSiren() {
        guard players[.siren]?.isPlaying != true else { return }
        emit(.siren, loops: -1)
    }

    static func stopSiren() {
        players[.siren]?.stop()
    }

    /// 求助流程结束时把所有声音关掉。忘了关的表现是「求助已经撤销了，警报还在响」。
    static func stopAll() {
        players.values.forEach { $0.stop() }
    }

    private static func emit(_ kind: Kind, loops: Int) {
        #if DEBUG
        if let observerForTesting {
            observerForTesting(kind)
            return
        }
        #endif
        // 响不出来**不该影响求助本身** —— 少一声警报是可用性损失，抛出去会把整条求助路径带崩。
        do {
            let player = try players[kind] ?? makePlayer(kind)
            player.numberOfLoops = loops
            // 复用同一个播放器，所以要自己回到开头；上一声还没播完时这就是重新触发。
            player.currentTime = 0
            player.play()
        } catch {
            logger.error("紧急警报音播放失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    private static func makePlayer(_ kind: Kind) throws -> AVAudioPlayer {
        let data: Data
        switch kind {
        case .countdownTick:
            data = ToneSynthesizer.wav(
                frequencies: countdownTickFrequencies,
                segmentDuration: countdownTickSegmentDuration
            )
        case .siren:
            data = ToneSynthesizer.wav(
                frequencies: sirenFrequencies,
                segmentDuration: sirenSegmentDuration
            )
        }
        let created = try AVAudioPlayer(data: data)
        created.volume = 1
        created.prepareToPlay()
        players[kind] = created
        return created
    }

    #if DEBUG
    /// 让测试能对播放器**对身份**——「同一种警报始终是同一个对象」正是防 use-after-free 的不变式。
    static func playerForTesting(_ kind: Kind) -> AVAudioPlayer? { players[kind] }
    #endif
}

// MARK: - 紧急倒计时的震动

/// 倒计时与警报的触觉通道。
///
/// ⚠️ **这是全仓唯一自造波形的地方。** `HapticFeedback`（业务事件那条通道）的类型注释里
/// 写着「只用系统定义的三种语义，不自造波形：Apple 明确要求保持系统一致性，
/// 自造的模式对用户是需要重新学习的噪音」—— 那句话仍然成立，这里是它唯一的例外，
/// 理由是**系统那三种在这里会造成歧义**：
///
/// 长按求助键的进度反馈已经是一串渐强的 `UIImpactFeedbackGenerator`
/// （`SafetyLongPress.hapticRamp`），而长按结束**紧接着**就是倒计时。
/// 倒计时如果也用单脉冲，用户感到的是「7 下差不多的震动」，分不出
/// 「还在按」和「已经在倒数、现在取消还来得及」—— 而那正是这三秒存在的全部意义。
///
/// 所以倒计时用**双击型**（两个间隔 90 ms 的瞬态），与任何单脉冲一听即分。
@MainActor
enum EmergencyHaptics {
    /// 两个瞬态之间的间隔。90 ms 是「能听出是两下、又不散成两次独立震动」的区间。
    static let doubleTapGap: TimeInterval = 0.09

    private static var engine: CHHapticEngine?
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "AidRun",
        category: "EmergencyHaptics"
    )

    #if DEBUG
    /// 与 `EmergencyAlarm.observerForTesting` 同源的接缝。`true` = 走了自造波形，
    /// `false` = 落到了系统降级。跑测时不真的震。
    static var observerForTesting: ((Bool) -> Void)?
    #endif

    /// 倒计时每秒一次。
    static func countdownTick() {
        play(pattern: doubleTapPattern)
    }

    private static func play(pattern: @autoclosure () -> CHHapticPattern?) {
        // 不支持 Core Haptics 的机器（以及模拟器）走系统降级。
        // `.warning` 本身就是个双脉冲，与自造波形的语义最接近 —— 降级不是静默。
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            fallback()
            return
        }
        do {
            let engine = try startedEngine()
            guard let pattern = pattern() else {
                fallback()
                return
            }
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
            #if DEBUG
            observerForTesting?(true)
            #endif
        } catch {
            logger.error("紧急震动失败，降级到系统反馈：\(error.localizedDescription, privacy: .public)")
            fallback()
        }
    }

    private static func fallback() {
        #if DEBUG
        if let observerForTesting {
            observerForTesting(false)
            return
        }
        #endif
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// 引擎**创建一次并持有**。每次触发新建一个引擎的代价是首次震动被吞掉
    /// （引擎启动是异步的），而倒计时只有三次，吞掉第一次等于少三分之一。
    ///
    /// `stoppedHandler` / `resetHandler` 里只把持有的引用清掉，下次触发时重建 ——
    /// 系统会在来电、切后台等场合停掉引擎，不重建的表现是「第一次求助有震动，第二次没有」。
    private static func startedEngine() throws -> CHHapticEngine {
        if let engine { return engine }
        let created = try CHHapticEngine()
        created.isAutoShutdownEnabled = true
        created.stoppedHandler = { _ in Task { @MainActor in engine = nil } }
        created.resetHandler = { Task { @MainActor in engine = nil } }
        try created.start()
        engine = created
        return created
    }

    /// 两个间隔 90 ms 的瞬态。`nil` 表示构造失败，调用方降级。
    private static var doubleTapPattern: CHHapticPattern? {
        let event = { (time: TimeInterval) in
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 1),
                ],
                relativeTime: time
            )
        }
        return try? CHHapticPattern(events: [event(0), event(doubleTapGap)], parameters: [])
    }
}
