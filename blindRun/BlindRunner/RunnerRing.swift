import AVFoundation
import Combine
import OSLog
import SwiftUI
import UIKit

// MARK: - 陪跑员让跑者的手机响起来（`RUNNER_RING`）

/// 视障跑者没法主动找人，但能被声音找到：陪跑员在出发点按「让 TA 的手机响起来」，
/// 后端推 `APP_NOTIFICATION`（`eventType=RUNNER_RING`），信封多带一个 `until`
/// （`websocket-protocol.md` §2.2 / `api_spec.yaml` `ring-runner`）。
/// 跑者这边：先念一句，再循环响铃到 `until`，任意操作即停。
enum RunnerRingCopy {
    static let fallbackSpeech = "你的陪跑员到了，正在找你"
    static let title = "你的陪跑员到了"
    static let detail = "手机正在响，陪跑员会循着声音找到你。"
    static let stopTitle = "停止响铃"
    static let accessibilityLabel = "你的陪跑员到了，手机正在响。停止响铃"
    static let accessibilityHint = "双击屏幕任意位置停止响铃"
}

/// 一次响铃。只由 `make(from:receivedAt:)` 产生 —— 能不能响的判据全在那里。
struct RunnerRingRequest: Equatable, Sendable {
    let id: String
    let orderId: Int64?
    let speechText: String
    let endsAt: Date

    /// 响铃时长上限。后端是「受理 + 10 秒」，这里只防异常值把手机响上几分钟。
    static let maximumDuration: TimeInterval = 30

    /// `nil` = 这一条不该响（缺 `until`、解析不出、或已经过了），调用方按普通通知念一次。
    ///
    /// 时长优先用 `until − timestamp`：两者都是**服务端时钟**，本机时钟偏几秒不影响。
    /// 差值不在 `(0, 60]` 里（`timestamp` 缺失、带了别的时区）才退回 `until − 本机 now`。
    static func make(from message: WSAppNotification, receivedAt: Date) -> RunnerRingRequest? {
        guard let rawUntil = message.until?.nilIfBlank, let until = rawUntil.backendTimestamp else { return nil }
        var duration = message.timestamp?.backendTimestamp.map { until.timeIntervalSince($0) } ?? -1
        if duration <= 0 || duration > 60 {
            duration = until.timeIntervalSince(receivedAt)
        }
        duration = min(duration, maximumDuration)
        guard duration > 0 else { return nil }
        let text = message.ttsText?.nilIfBlank ?? message.body.nilIfBlank ?? RunnerRingCopy.fallbackSpeech
        return RunnerRingRequest(
            id: message.messageId?.nilIfBlank ?? "\(message.orderId ?? 0)-\(rawUntil)",
            orderId: message.orderId,
            // 外放朗读，掩码姓名里的星号不许念出来（`unmaskedForSpeech`）。
            speechText: text.unmaskedForSpeech,
            endsAt: receivedAt.addingTimeInterval(duration)
        )
    }
}

// MARK: - 提示音

/// 响铃用的提示音：下行「叮咚」+ 静音，1 秒一循环。
///
/// 频率避开全 App 已用的各组（录音起止、播报引导、倒计时、求助警报）——
/// 求助警报 740/988 尤其不能复用：「陪跑员到了」听成「有人求救」是事故。
/// 做法照抄 `EmergencyAlarm`：`ToneSynthesizer` 合成、`.playback` 分类下静音拨杆照响、
/// 播放器**创建后常驻不释放**（`finishedPlaying:` 崩溃的教训）。
@MainActor
enum RunnerRingTone {
    /// `0` = 静音段。
    static let frequencies: [Double] = [1568, 1244.5, 0, 0]
    static let segmentDuration: TimeInterval = 0.25

    private static var player: AVAudioPlayer?
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AidRun", category: "RunnerRing")

    #if DEBUG
    /// 测试接缝：设了就接管发声，`true` = 开始，`false` = 停止。
    static var observerForTesting: ((Bool) -> Void)?
    #endif

    static func start() {
        #if DEBUG
        if let observerForTesting { observerForTesting(true); return }
        #endif
        do {
            let player = try player ?? makePlayer()
            player.numberOfLoops = -1
            player.currentTime = 0
            player.play()
        } catch {
            // 响不出来不该让页面跟着出错，朗读那一句已经念过了。
            logger.error("响铃播放失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    static func stop() {
        #if DEBUG
        if let observerForTesting { observerForTesting(false); return }
        #endif
        player?.stop()
    }

    private static func makePlayer() throws -> AVAudioPlayer {
        let created = try AVAudioPlayer(
            data: ToneSynthesizer.wav(frequencies: frequencies, segmentDuration: segmentDuration)
        )
        // App 能给的最大音量。系统音量没有公开 API 可改，这里不去碰。
        created.volume = 1
        created.prepareToPlay()
        player = created
        return created
    }
}

// MARK: - 起止控制

/// 一次响铃的生命周期：念 → 等念完（有上限）→ 循环响 → 到 `endsAt` 或被按停。
@MainActor
final class RunnerRingController: ObservableObject {
    @Published private(set) var active: RunnerRingRequest?

    /// 先念后响的等待上限。同时起的话铃声会盖住那句「你的陪跑员到了」。
    static let speechWaitLimit: TimeInterval = 4

    var speak: (String) -> Void = { _ in }
    var isSpeaking: () -> Bool = { false }
    var startTone: () -> Void = { RunnerRingTone.start() }
    var stopTone: () -> Void = { RunnerRingTone.stop() }
    /// 响完或被按停之后。用来清掉协调器上那一条，免得重新订阅时回放。
    var onFinish: () -> Void = {}

    private let now: () -> Date
    private var handledIDs: Set<String> = []
    private var task: Task<Void, Never>?

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// `@Published` 重新订阅会回放当前值，所以这里自己挡：处理过的 id、已经过点的，都不再响。
    func handle(_ ring: RunnerRingRequest?) {
        guard let ring, !handledIDs.contains(ring.id), ring.endsAt > now() else { return }
        handledIDs.insert(ring.id)
        task?.cancel()
        stopTone()
        active = ring
        task = Task { [weak self] in await self?.run(ring) }
    }

    /// 任意操作即停。
    func stop() {
        guard active != nil else { return }
        finish()
    }

    private func run(_ ring: RunnerRingRequest) async {
        speak(ring.speechText)
        let toneDeadline = min(ring.endsAt, now().addingTimeInterval(Self.speechWaitLimit))
        while isSpeaking(), now() < toneDeadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if Task.isCancelled { return }
        }
        if Task.isCancelled { return }
        let remaining = ring.endsAt.timeIntervalSince(now())
        if remaining > 0 {
            startTone()
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            if Task.isCancelled { return }
        }
        finish()
    }

    private func finish() {
        task?.cancel()
        task = nil
        stopTone()
        active = nil
        onFinish()
    }
}

// MARK: - 遮罩

/// 响铃期间盖住整屏。点任意位置、VoiceOver 双击、magic tap、返回手势都停。
///
/// 🔴 magic tap 必须挂在这一层：`BlindRunnerTabView` 的 TabView 上 magic tap = 求助，
/// 这里不接住的话，读屏用户想停铃会弹出求助确认。
struct RunnerRingOverlay: View {
    let onStop: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "bell.and.waves.left.and.right.fill")
                    .font(.system(size: 56))
                    .foregroundColor(AppColors.primary)
                Text(RunnerRingCopy.title)
                    .font(AppFonts.largeTitle())
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(RunnerRingCopy.detail)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                PrimaryButton(RunnerRingCopy.stopTitle, action: onStop)
            }
            .readableContentColumn()
            .padding(24)
            .padding(.top, 48)
            .frame(maxWidth: .infinity)
        }
        .background(AppColors.background.ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture(perform: onStop)
        // 整屏一个元素：读屏焦点落在哪都能双击停。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RunnerRingCopy.accessibilityLabel)
        .accessibilityHint(RunnerRingCopy.accessibilityHint)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onStop)
        .accessibilityAction(.magicTap, onStop)
        .accessibilityAction(.escape, onStop)
        .accessibilityIdentifier("runnerRingOverlay")
        .onAppear { UIAccessibility.post(notification: .screenChanged, argument: nil) }
    }
}
