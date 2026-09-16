import ActivityKit
import AppIntents
import AVFoundation
import SwiftUI

// MARK: - 锁屏实时活动：两个 target 共用的那一份
//
// 🔴 **本文件同时属于 `blindRun` 与 `blindRunWidget` 两个 target**（`project.pbxproj` 里
// 两个 Sources 阶段各引用一次）。原因是硬的，不是图省事：
//
// - `AnnounceRunStatsIntent` 必须在 **app target** 里 —— 官方文档
//   （widgetkit/adding-interactivity-to-widgets-and-live-activities）原文：
//   「If you adopt the LiveActivityIntent or AudioPlaybackIntent protocol, the system runs
//   the app intent in the app's process. Make sure to add your custom app intent to your app target.」
// - 同时又必须在 **widget target** 里 —— 否则卡片上那行 `Button(intent:)` 编译不过。
//
// ⛔ 所以这里**不能** `import` 任何只在 app target 里的东西（`AppColors` / `FlowMetrics` /
// `VoiceService` / `TrackStats` 都不行）。取值因此在本文件里各有具名落点，
// 并由 `blindRunTests/RunLiveActivityTests.swift` 逐条钉回 app 侧的唯一源 ——
// 机器对撞代替「记得改两处」，见 `AGENTS.md` §1.2。

/// 这张卡是给谁看的。跑者端多一行顶行与一枚播报按钮，陪跑员端只有三个数字。
///
/// 陪跑员端**不显示对方姓名**（项目负责人 2026-09-16 决定）。因此 `partnerName`
/// 在陪跑员侧恒为 `nil`，卡片也就不需要从陪跑员的 view model 里取任何身份信息 ——
/// 这正是本阶段能零接触 `blindRun/Volunteer/**` 的原因。
enum RunLiveActivitySide: String, Codable, Hashable, Sendable {
    case runner
    case volunteer
}

@available(iOS 16.2, *)
struct RunLiveActivityAttributes: ActivityAttributes, Hashable {

    /// 每次刷新会变的那部分。
    ///
    /// **显示串与播报串都由 app 侧算好后塞进来，widget 不再自己格式化。**
    /// 跑表体例（`3.20` / `21:04` / `6'30"`）与口语体例（`3.20 公里` / `21 分 4 秒` /
    /// `6 分 30 秒每公里`）是两套口径，唯一源是 `TrackStats` 的六个计算属性 ——
    /// 而 `TrackStats` 所在的文件依赖 `RunOrderStatus` 与 `BackendCoordinateNormalizer`，
    /// 整份搬进 widget target 会把半个 App 拖进来。传字符串是这里最便宜的正确做法。
    struct ContentState: Codable, Hashable {
        /// 跑者端顶行的陪跑员姓名；陪跑员端恒为 `nil`。
        ///
        /// 🔴 **这个字段必须待在 `ContentState` 里，不能挪回 `attributes`。**
        /// `attributes` 在 `Activity.request` 之后**永远改不了**（`activity.update(_:)`
        /// 只收 `ContentState`），而姓名是**异步到的**：起卡点不止一个，
        /// `BlindRunnerHomeView` 那两处（`:118` / `:255`）只传订单号与状态、拿不到姓名。
        /// 放 `attributes` 的后果是「从首页起的卡一辈子没有顶行」，而顶行是这张卡上
        /// 唯一渲染 App 名的地方 —— VoiceOver 焦点落上去只剩三个裸数字，
        /// 状态清单 §16 要求的「助盲跑 → 陪跑中 · 张伟 → 里程…」首站整个消失。
        /// 2026-09-16 code review A1。
        var partnerName: String?
        var distanceText: String
        var durationText: String
        var paceText: String
        var spokenDistance: String
        var spokenDuration: String
        var spokenPace: String
    }

    /// 这张卡属于哪一单。
    ///
    /// 放在 `attributes` 里是因为它**真的不变**，而且这是进程重启后认回旧卡的唯一线索：
    /// 实时活动活在系统进程里，App 被杀/崩溃/上滑退出之后卡片照样留在锁屏上，
    /// 重启后只能靠 `Activity.activities` 找回来，再靠这个字段判断是不是同一单。
    /// 2026-09-16 code review A2。
    var orderID: Int64
    var side: RunLiveActivitySide
}

// MARK: - 文案

/// 锁屏卡上每一处用户可见 / 可听的文字。**只在这里出现字面量。**
enum RunLiveActivityCopy {
    static let appName = "助盲跑"
    static let distanceLabel = "里程（公里）"
    static let durationLabel = "时长"
    static let paceLabel = "配速"
    static let announceButtonTitle = "播报当前数据"

    /// 数字还没到时的占位。**不写 0.00** —— 「跑了 0 公里」和「还没拿到数据」是两件事，
    /// 而锁屏上没有第二处能说明区别。
    static let pendingValue = "--"
    static let pendingSpokenValue = "暂无数据"

    static func partnerHeadline(_ name: String) -> String {
        "陪跑中 · \(name)"
    }

    /// 三个数字**一个都还没到**时念的那一句。
    ///
    /// 逐项占位在**屏幕**上是对的（缺哪个哪个显示 `--`），但拼成一句话就成了
    /// 「暂无数据，用时 暂无数据，配速 暂无数据」—— 一句语法不通、对盲人毫无信息的话。
    /// 窗口虽窄（进 `IN_PROGRESS` 到第一次 `/track` 回来之间），但那一刻卡刚出现，
    /// 正是最可能被按的时候。2026-09-16 code review B4。
    static let announcementWhenNothingYet = "还没有数据，刚开始跑"

    /// 按下「播报当前数据」念的那一句（状态清单 §16：「X.X 公里，用时 X 分钟，配速 X 分 X」）。
    static func announcement(distance: String, duration: String, pace: String) -> String {
        let missing = [distance, duration, pace].allSatisfy { $0 == pendingSpokenValue }
        guard !missing else { return announcementWhenNothingYet }
        return "\(distance)，用时 \(duration)，配速 \(pace)"
    }

    static func distanceAccessibilityLabel(_ spokenDistance: String) -> String {
        "里程 \(spokenDistance)"
    }

    static func durationAccessibilityLabel(_ spokenDuration: String) -> String {
        "\(durationLabel) \(spokenDuration)"
    }

    static func paceAccessibilityLabel(_ spokenPace: String) -> String {
        "\(paceLabel) \(spokenPace)"
    }
}

// MARK: - 尺寸

/// 锁屏卡的尺寸。**与全屏那一套（`FlowMetrics` / `FlowFonts`）刻意不同**：
/// 实时活动有高度上限，全屏的 82 / 36 放进来会把顶行和按钮挤出可见区
/// （2026-09-16 在模拟器 demo 上实测过：按钮拉到 110pt 时顶行当场被裁掉）。
/// 状态清单 §16 给的就是这一套缩小值。
enum RunLiveActivityMetrics {
    /// 里程。卡上最大的数字，等宽。
    static let distanceSize: CGFloat = 56
    /// 时长 / 配速。
    static let metricSize: CGFloat = 24
    /// 顶行「陪跑中 · 张伟」。
    static let headlineSize: CGFloat = 15
    /// 三个数字各自的标签。
    static let labelSize: CGFloat = 13
    /// 顶行左侧那枚小头像，以及里面那个姓氏的字号。
    static let avatarDiameter: CGFloat = 20
    static let avatarInitialSize: CGFloat = 10
    /// 「播报当前数据」四个字。
    static let announceButtonTitleSize: CGFloat = 17

    /// 「播报当前数据」的高度。
    ///
    /// 🚩 **52 低于本仓库的 64pt 触达下限，是一次有意偏离**，两条理由缺一不可：
    /// ① 实时活动整卡高度上限约 175pt（同上，demo 实测），56 的里程 + 标签 + 64 的按钮放不下；
    /// ② 这不是 App 自己的画布 —— 锁屏上按钮周围一圈是系统的卡片留白，
    ///    实际可点区域比 52 大，而 App 内的 64pt 线针对的是「一屏里挨着好几个控件」。
    /// 项目负责人 2026-09-16 明确要求「播报那个按钮做小一点」。
    static let announceButtonHeight: CGFloat = 52
    static let announceButtonRadius: CGFloat = 14
    static let cardPadding: CGFloat = 14
    static let rowSpacing: CGFloat = 6
    static let columnSpacing: CGFloat = 16
}

// MARK: - 取值

/// 锁屏卡的颜色。**每一个都必须等于 `AppColors.Flow` 对应取值的暗色档** ——
/// 实时活动在锁屏上永远是深色呈现，所以取的是暗色那一档而不是动态色。
/// 对撞在 `RunLiveActivityTests.testPaletteMatchesTheFlowPalette`。
enum RunLiveActivityPalette {
    /// `AppColors.Flow.ctaTone.dark`
    static let cta: UInt32 = 0xF6C343
    /// `AppColors.Flow.onCTATone.dark`
    static let onCTA: UInt32 = 0x111A2E
    /// `AppColors.Flow.surfaceTone.dark`
    static let cardSurface: UInt32 = 0x1C1C1E
    /// `AppColors.Flow.primaryTextTone.dark`
    static let numberInk: UInt32 = 0xFFFFFF
    /// `AppColors.Flow.secondaryTextTone.dark`
    static let labelInk: UInt32 = 0xAEAEB2
    /// `AppColors.Flow.avatarBackgroundTone.dark`
    static let avatarBackground: UInt32 = 0x2A3C78
    /// `AppColors.Flow.avatarInitialTone.dark`。
    ///
    /// **不要就地写 `.white`**：今天这个取值恰好是白，所以写死看不出问题；
    /// 而 `avatarInitialTone` 的暗色档一旦被改（`FlowPaletteContrastTests` 会跟着走），
    /// 锁屏上的姓氏仍是白色，且没有任何东西会红。2026-09-16 code review A4。
    static let avatarInitial: UInt32 = 0xFFFFFF

    /// `0xRRGGBB` → `Color`。
    ///
    /// **刻意不复用 `UIColor(rgb:)`**（`AppColors.swift:122`）：那个扩展只在 app target 里，
    /// 而本文件也要在 widget target 里编译；同名再声明一次会让 app target 重复定义。
    static func color(_ rgb: UInt32) -> Color {
        Color(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

// MARK: - 播报

/// 锁屏按钮按下时说话的那个合成器。
///
/// 2026-09-16 模拟器实测（报告见 `docs/research/ios-live-activity-lock-screen-20260916.md`）：
/// 锁屏上按下按钮 → 系统在 **app 进程**里执行 `perform()`（日志里 bundle 是 app 的），
/// App 不打开、屏幕不亮，`AVAudioSession` 激活成功，`didStart` / `didFinish` 都回调了。
/// **不需要 `UIBackgroundModes: audio`** —— 对照组（删掉该键重装）同样念出来了。
///
/// ponytail: 这里是**第二个** `AVSpeechSynthesizer`（第一个在 `VoiceService`）。
/// 天花板是「App 正在播每公里播报时用户又按了锁屏按钮 ⇒ 两个声音叠在一起」。
/// 升级路径在阶段 2 的播报队列：让 `VoiceService` 与这里共用同一个出口即可，
/// 那一条线正在改 `SpeechService.swift`，本阶段不动它。
@available(iOS 16.2, *)
@MainActor
final class RunLiveActivitySpeaker: NSObject {
    static let shared = RunLiveActivitySpeaker()

    /// 锁屏播报的音频会话配置。
    ///
    /// 🚩 **`AVAudioSession` 是全进程共用的一个对象**，而 App 里本来已经有一个所有者
    /// （`SystemSpeechAudioSession`，`SpeechInputService.swift:86-92`，它用 `options: []`）。
    /// 这里多一个 `.duckOthers` 是**有意的**：设计稿要求「音乐只压低不暂停」，
    /// 而 `.playback + []` 在激活时会直接打断用户正在听的音乐。
    ///
    /// 🔴 **代价必须一起付掉：念完要 `setActive(false)`。** 只激活不释放的话，
    /// ducking 会一直生效 —— 用户按一次播报，音乐就被压低到跑完为止。
    /// 见下面 `speechSynthesizer(_:didFinish:)`。2026-09-16 code review A3。
    static let announceCategory: AVAudioSession.Category = .playback
    static let announceMode: AVAudioSession.Mode = .spokenAudio
    static let announceOptions: AVAudioSession.CategoryOptions = [.duckOthers]

    private let synthesizer = AVSpeechSynthesizer()

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
        activateAudioSession()
        synthesizer.speak(Self.makeUtterance(normalized))
    }

    /// 锁屏按下时 App 多半在后台，会话不是激活态 —— 不激活就没有声音。
    /// 失败**不抛也不播**：这条路径没有界面可以报错，而静默失败的表现和「没按到」一样，
    /// 所以留一条日志给真机排查。
    private func activateAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(Self.announceCategory, mode: Self.announceMode, options: Self.announceOptions)
            try session.setActive(true)
        } catch {
            NSLog("[AidRun] 锁屏播报激活音频会话失败：%@", error.localizedDescription)
        }
    }

    /// 念完就把会话让出去，音乐随之恢复原音量。
    /// `.notifyOthersOnDeactivation` 是让对方知道可以恢复的那个开关，漏了它音乐不会自己回来。
    private func releaseAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            NSLog("[AidRun] 锁屏播报释放音频会话失败：%@", error.localizedDescription)
        }
    }

    /// **与 `VoiceService.makeUtterance` 同口径。**
    ///
    /// 关键是 `prefersAssistiveTechnologySettings` —— 设计稿要求「合成语音沿用用户 VoiceOver
    /// 的声音与语速设置」，而读屏用户的语速普遍远高于默认值。两处各写一份是因为
    /// `VoiceService` 在 app target 里、够不着（见文件头）；`RunLiveActivityTests`
    /// 会把两者逐属性对撞，改一处漏一处会红。
    static func makeUtterance(_ text: String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.prefersAssistiveTechnologySettings = true
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        return utterance
    }
}

@available(iOS 16.2, *)
extension RunLiveActivitySpeaker: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.releaseAudioSession() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        // 只有「后一次播报打断前一次」会走到这里，而那时新的一句马上要念 ——
        // 立刻释放会把自己刚要用的会话关掉，所以这里**什么都不做**，
        // 交给新那句的 `didFinish`。
    }
}

// MARK: - 锁屏按钮背后的意图

/// 「播报当前数据」。
///
/// 采用 `AudioPlaybackIntent` 而不是裸 `AppIntent`：后者会在 **widget 进程**里执行，
/// 那个进程没有音频会话，按下去不会有任何声音。
@available(iOS 17.0, *)
struct AnnounceRunStatsIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "播报当前数据"

    /// 不打开 App —— 这是这枚按钮存在的全部意义（状态清单 §16：「不必解锁」）。
    static var openAppWhenRun: Bool = false

    /// 要念的那一句。**由 widget 在渲染时算好塞进来**，所以 `perform()` 不需要读任何 App 状态
    /// （被系统冷启动起来的 app 进程里，`AppState` 不保证已经装好）。
    @Parameter(title: "播报内容")
    var spokenText: String

    init() {}

    init(spokenText: String) {
        self.spokenText = spokenText
    }

    func perform() async throws -> some IntentResult {
        await RunLiveActivitySpeaker.shared.speak(spokenText)
        return .result()
    }
}
