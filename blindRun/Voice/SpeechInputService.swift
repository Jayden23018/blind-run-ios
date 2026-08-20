import AudioToolbox
import AVFoundation
import Combine
import Foundation
import OSLog
import Speech
import UIKit

// MARK: - Speech Audio Session

@MainActor
protocol SpeechAudioSessionManaging: AnyObject {
    var isInputAvailable: Bool { get }
    var inputNumberOfChannels: Int { get }
    var sampleRate: Double { get }

    func requestRecordPermission(_ response: @escaping (Bool) -> Void)
    func configureRecordingCategory() throws
    func activateRecording() throws
    func deactivateRecording() throws
    func configurePlaybackCategory() throws
    func activatePlayback() throws
}

@MainActor
final class SystemSpeechAudioSession: SpeechAudioSessionManaging {
    private let session: AVAudioSession

    init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
    }

    var isInputAvailable: Bool { session.isInputAvailable }
    var inputNumberOfChannels: Int { session.inputNumberOfChannels }
    var sampleRate: Double { session.sampleRate }

    func requestRecordPermission(_ response: @escaping (Bool) -> Void) {
        session.requestRecordPermission(response)
    }

    /// 录音期间的音频分类。**必须是允许播放的那一种。**
    ///
    /// 曾经是 `.record`。那个分类根本不开输出通道，于是 `RecordingCue.begin()`
    /// （在 `markRecognitionStarted()` 里，跑在 `activateRecording()` 之后）放出去的起音提示
    /// 用户一声都听不见 —— 而对全盲用户，那一声是判断「麦克风开没开」的唯一非视觉信号。
    /// 2026-08-06 真机手测报的「没有任何弹出语音的声音提示」就是这条。
    ///
    /// 收音那一端 2026-08-06 已经因为同一个原因修过（`stopAudioRecognition` 把 `RecordingCue.end()`
    /// 推到会话切回播放之后，并留了断言）。起音这一端当时漏了：它不能靠「推到之后」解决 ——
    /// 录音正要开始，没有「之后」可推。所以改的是分类本身。
    ///
    /// `.defaultToSpeaker` 不能省：`.playAndRecord` 默认把输出路由到听筒，
    /// 提示音会小到等于没有。
    static let recordingCategory: AVAudioSession.Category = .playAndRecord
    static let recordingCategoryOptions: AVAudioSession.CategoryOptions = [.duckOthers, .defaultToSpeaker]

    /// 录音期间的 mode。**2026-08-06 由 `.measurement` 改为 `.default`。**
    ///
    /// `.measurement` 是给测量类 App 用的：它把系统的信号处理降到最低，对**只录不放**的
    /// 识别场景确实更准（Apple 的语音识别示例配的就是 `.record` + `.measurement`）。
    /// 但我们已经不是「只录不放」了 —— 起音提示要在录音会话下放出来。`.measurement` 下
    /// 输出增益被压得很低，真机连续两轮都反馈「声音不够响」。
    ///
    /// 取 `.default`：`.playAndRecord` + `.defaultToSpeaker` + `.default` 是同时收放的常规组合。
    /// 代价是输入侧多了一层系统处理，理论上对识别有影响 —— 但**提示音听不见是确定的可用性
    /// 损失，识别精度的变化是推测的**，先保住前者。若真机发现识别变差，再回头考虑
    /// 「提示音改在切录音会话之前放」这条更绕的路。
    static let recordingMode: AVAudioSession.Mode = .default

    func configureRecordingCategory() throws {
        try session.setCategory(
            Self.recordingCategory,
            mode: Self.recordingMode,
            options: Self.recordingCategoryOptions
        )
    }

    func activateRecording() throws {
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    func deactivateRecording() throws {
        try session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    func configurePlaybackCategory() throws {
        try session.setCategory(.playback, mode: .spokenAudio, options: [])
    }

    func activatePlayback() throws {
        try session.setActive(true)
    }
}

// MARK: - Recording Cue

/// 录音起止的**非视觉**提示。
///
/// 这是全盲用户可用性的底线，不是装饰：AppleVis 上对语音类 App「按下之后全程没有任何反馈」
/// 的评测原话是「感觉从没找真实盲人测试过」；另一条对 iMessage 语音消息的抱怨是「打开就开始录，
/// 很难干净地停下来，唯一的反馈是结束时的一声」。屏幕上的波形动画对全盲用户是零价值。
///
/// ~~声音走系统自带的 `begin_record` / `end_record`（1113 / 1114）~~ —— **2026-08-06 真机推翻。**
///
/// `AudioServicesPlaySystemSound` 走的是**响铃 / 系统提示音通道**，受侧面静音拨杆和响铃音量控制；
/// 而 TTS 走**媒体通道**，是另一套独立音量。于是出现了真机上那个现象：合成器念得清清楚楚，
/// 起止提示一声都没有 —— 用户的响铃是静音的，而他没有任何理由知道这件事。
///
/// **对全盲用户，这条提示不是通知，是他判断「麦克风开没开」的唯一非视觉信号，
/// 不能挂在一个他看不见、也想不到要去检查的物理开关上。** 所以改成自己合成一小段纯音、
/// 用 `AVAudioPlayer` 走 App 自己的音频会话播 —— 和 TTS 同一条通道，TTS 听得见它就听得见。
///
/// 两个音高可区分（Alexa 的 attention system 要求起止两个 earcon 音色不同）：起音 880 Hz、
/// 收音 587 Hz，各 120 ms，首尾 8 ms 淡入淡出防爆音。
///
/// 震动是为了戴耳机或环境嘈杂时仍然可感知 —— 两条通道互为备份，不是重复。
/// 触觉的语义按 Apple 文档分工：开始是「此刻发生了一件事」用 impact，结束是「一段过程完成了」
/// 用 notification。
@MainActor
enum RecordingCue {
    enum Kind: Equatable, Hashable { case begin, end }

    /// 播放器必须被持有，否则出了作用域就停 —— 提示音只有 120 ms，丢掉等于没响。
    ///
    /// **而且要按种类各持有一个、创建后永不释放。** 2026-08-16 之前这里是「每次发声 new 一个
    /// `AVAudioPlayer`、覆盖同一个静态槽」：一次提示 0.22 秒，而起听→停听在测试里只隔几微秒，
    /// 于是起音那个播放器在**还在播**的时候就被覆盖释放。音频队列随后把它自己的完成回调
    /// `-[AVAudioPlayer finishedPlaying:]` 派回主线程，打在那块已被复用的内存上 ——
    /// 真机表现是 `-[__NSDictionaryM finishedPlaying:] unrecognized selector` 或 signal segv，
    /// **崩在任意一条与音频无关的用例上**（同命令连跑两次：288 passed / 3 failed，随后 291 passed / 0 failed）。
    /// 生产里就是 App 当场挂掉，而看不见屏幕的用户只会觉得「点了没反应」。
    ///
    /// 常驻两个播放器就没有「播放中被释放」这个状态可言，顺带省掉每次发声的重复解码。
    /// 不变式由 `testRecordingCueReusesOnePlayerPerKind` 钉住。
    private static var players: [Kind: AVAudioPlayer] = [:]

    /// **双音提示，不是单音。** 起音上行（低→高）＝「开始了」，收音下行（高→低）＝「结束了」。
    ///
    /// 这是语音助手普遍的做法，也是调研 §6.1 引 Alexa attention system 的要求：起止两个 earcon
    /// 必须音色可区分。上行/下行比「两个不同音高的单音」好认得多 —— 人对音高**方向**的敏感度
    /// 远高于对绝对音高的记忆，不需要记住「880 是开始、587 是结束」。
    ///
    /// 2026-08-06 第三、四轮真机都反馈「声音不够响，可能会被盲人忽略」。单音正弦在感知响度上
    /// 天生吃亏：能量集中在一个频点，而人耳的响度感知是跨频带累加的。改双音之后每段更短
    /// （各 110 ms）但总时长相当，频谱铺开，同样峰值电平下明显更容易被注意到。
    static let beginToneFrequencies: [Double] = [660, 990]
    static let endToneFrequencies: [Double] = [880, 587]
    /// 单段时长；一次提示是两段，总长约 0.22 秒。
    static let toneSegmentDuration: TimeInterval = 0.11
    static var toneDuration: TimeInterval { toneSegmentDuration * 2 }

    static let beginToneData = ToneSynthesizer.wav(
        frequencies: beginToneFrequencies, segmentDuration: toneSegmentDuration
    )
    static let endToneData = ToneSynthesizer.wav(
        frequencies: endToneFrequencies, segmentDuration: toneSegmentDuration
    )

    #if DEBUG
    /// 测试替身。设了就**接管**发声与震动（跑测时不该真的响、真的震），并记下发生了哪一次。
    ///
    /// 这条接缝存在的理由不是「方便测试」，而是这段代码曾经因为**没有任何断言**被三份文档
    /// 集体误判成「尚未实现」（2026-08-06 订正）。没有守卫的实现，和不存在的实现在下一个人
    /// 眼里是一样的 —— 而对全盲用户，这是判断「麦克风开没开」的唯一非视觉信号。
    static var observerForTesting: ((Kind) -> Void)?
    #endif

    static func begin() { emit(.begin) }

    static func end() { emit(.end) }

    private static func emit(_ kind: Kind) {
        #if DEBUG
        if let observerForTesting {
            observerForTesting(kind)
            return
        }
        #endif
        playTone(kind)
        switch kind {
        case .begin:
            // 不 `prepare()` 的话首次触发常被系统丢掉 —— 而首次正是最要紧的那次：
            // 用户刚进语音下单，还不知道麦克风开没开。
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            generator.impactOccurred()
        case .end:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    /// 提示音放不出来**不该影响录音本身** —— 少一声提示是可用性损失，抛出去会把整条语音路径带崩。
    private static func playTone(_ kind: Kind) {
        do {
            let tonePlayer = try players[kind] ?? makePlayer(kind)
            // 复用同一个播放器，所以要自己回到开头；上一声还没播完时这就是重新触发。
            tonePlayer.currentTime = 0
            tonePlayer.play()
        } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "AidRun", category: "SpeechInput")
                .error("录音提示音播放失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    private static func makePlayer(_ kind: Kind) throws -> AVAudioPlayer {
        let created = try AVAudioPlayer(data: kind == .begin ? beginToneData : endToneData)
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

// MARK: - Tone Synthesizer

/// 就地合成一小段 16-bit 单声道 PCM 纯音，包成 WAV 交给 `AVAudioPlayer`。
///
/// 为什么不打包音频资源：起止两声各 120 ms 的正弦波，合成比维护两个二进制资源更简单，
/// 也不用动 `project.pbxproj`。为什么不用 `AudioServicesPlaySystemSound`：见 `RecordingCue` 的说明，
/// 那条走响铃通道，会被静音拨杆关掉。
enum ToneSynthesizer {
    static let sampleRate = 44_100

    /// 首尾各 8 ms 淡入淡出。直接切方波边缘会有「咔」的爆音，对贴着耳朵听的用户尤其难受。
    static let fadeSeconds = 0.008

    /// 基频 + 一个八度泛音。纯正弦在感知响度上偏「闷」，加谐波能在同样峰值电平下明显更容易被注意到
    /// —— 2026-08-06 真机反馈「声音不大，可能会被盲人忽略」，这是三处调整之一。
    static let overtoneRatio = 0.35

    /// 把若干段等长纯音（各自带八度泛音）首尾相接成一条 WAV。
    /// 两段就是一个上行或下行的「叮咚」，方向本身携带语义。
    static func wav(
        frequencies: [Double],
        segmentDuration: TimeInterval,
        amplitude: Double = 0.95
    ) -> Data {
        var pcm = Data()
        for frequency in frequencies {
            pcm.append(segment(frequency: frequency, duration: segmentDuration, amplitude: amplitude))
        }
        return container(pcm: pcm)
    }

    private static func segment(frequency: Double, duration: TimeInterval, amplitude: Double) -> Data {
        let frameCount = Int(Double(sampleRate) * duration)
        var pcm = Data(capacity: frameCount * 2)
        // 基频与八度加在一起会超过 1，先归一化再乘振幅，否则削顶会变成刺耳的失真。
        let normalizer = 1 + overtoneRatio
        for frame in 0..<frameCount {
            let time = Double(frame) / Double(sampleRate)
            // 每段自己淡入淡出：段与段之间不做淡化的话，频率突变处会有一声「咔」。
            let envelope = max(0, min(min(time, duration - time) / fadeSeconds, 1))
            let fundamental = sin(2 * .pi * frequency * time)
            let overtone = sin(2 * .pi * frequency * 2 * time) * overtoneRatio
            let value = (fundamental + overtone) / normalizer * envelope * amplitude
            var sample = Int16(max(-1, min(1, value)) * Double(Int16.max))
            withUnsafeBytes(of: &sample) { pcm.append(contentsOf: $0) }
        }
        return pcm
    }

    private static func container(pcm: Data, channels: Int = 1, bitsPerSample: Int = 16) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + pcm.count))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))
        append(UInt16(1)) // PCM
        append(UInt16(channels))
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * channels * bitsPerSample / 8))
        append(UInt16(channels * bitsPerSample / 8))
        append(UInt16(bitsPerSample))
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(pcm.count))
        data.append(pcm)
        return data
    }
}

// MARK: - Speech Input Field

enum SpeechInputField: String, CaseIterable, Identifiable {
    case startPlaceSearch
    case startLocationDescription
    case destinationRoute
    case remark
    case ratingFeedback
    case volunteerServiceSummary
    // 语音下单向导的槽位。与上面的字段听写共用同一套授权/静音超时/最长时长，
    // 区别只在识别结果不回填输入框，而是交给后端解析端点。
    /// 整句下单：用户一次说完时间与时长（地点待后端支持整句抽取后并入，见 `VoiceOrderWizard`）。
    case voiceOrderFreeform
    /// 复述后的指令轮：「确认」或「改地点/改时间/改时长」。只做本地判定，不发任何请求。
    case voiceOrderConfirm
    case voiceOrderStartPlace
    case voiceOrderStartTime
    case voiceOrderDuration
    // 盲人端「问一句」查订单状态。与下单向导共用同一套授权 / 静音超时 / 最长时长，
    // 区别是识别结果完全在本地判（`VoiceStatusQuery`），不发任何请求。
    /// 问题那一轮：「志愿者还有多远」「几点开始」。
    case voiceStatusQuery
    /// 复述号码后的确认那一轮。只做本地判定，判据与下单确认同一张白名单。
    case voiceStatusConfirmCall

    var id: String { rawValue }

    static func isAllowlisted(_ fieldId: String) -> Bool {
        Self(rawValue: fieldId) != nil
    }
}

// MARK: - Speech Input Stop Reason

enum SpeechInputStopReason: Equatable {
    case manual
    case finalResult
    case silenceTimeout(hadDetectedSound: Bool)
    case maxDuration
    case error

    var announcement: String {
        switch self {
        case .manual:
            return "语音输入已关闭。"
        case .finalResult:
            return "语音输入已停止。"
        case .silenceTimeout(let hadDetectedSound):
            return hadDetectedSound ? "语音输入已停止。" : "未检测到声音，已停止语音输入。"
        case .maxDuration:
            return "语音输入已达到最长时间，已停止。"
        case .error:
            return "语音识别失败，请使用键盘输入。"
        }
    }

    var shouldTriggerSearchWithRecognizedText: Bool {
        switch self {
        case .manual, .finalResult, .silenceTimeout(hadDetectedSound: true), .maxDuration:
            return true
        case .silenceTimeout(hadDetectedSound: false), .error:
            return false
        }
    }
}

struct SpeechInputCompletion: Equatable {
    let field: SpeechInputField
    let recognizedText: String
    let reason: SpeechInputStopReason
}

// MARK: - Speech Input Service

/// iOS Speech framework wrapper for text-field dictation only.
/// It is intentionally not used for time parsing or global assistant behavior.
@MainActor
final class SpeechInputService: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var activeField: SpeechInputField?
    @Published private(set) var lastStopReason: SpeechInputStopReason?
    @Published var errorMessage: String?
    @Published private(set) var audioSessionDiagnosticMessage: String?
    /// 语音链路在**启动阶段**就失败过：授权被拒或 recognizer 不可用。
    ///
    /// 供调用方跳过重试循环用。`VoiceOrderWizard` 没有这条信息时只能把「麦克风从来没打开过」
    /// 当成「这次没听清」，于是连问三轮「我再问一次」才降级——对听不见屏幕的人是三轮无意义的等待。
    /// 一旦真的起听成功即复位（授权可能刚被补授）。
    @Published private(set) var isSpeechPathUnavailable = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let audioEngine = AVAudioEngine()
    private let audioSession: any SpeechAudioSessionManaging
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AidRun", category: "SpeechInput")
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionStartTask: Task<Void, Never>?
    private var recognitionSessionID = UUID()
    private var silenceMonitorTask: Task<Void, Never>?
    private var maxDurationTask: Task<Void, Never>?
    private var announcementHandler: ((String) -> Void)?
    private var completionHandler: ((SpeechInputCompletion) -> Void)?
    private var didInstallTap = false
    private var recognitionStartedAt: Date?
    private var lastSoundAt: Date?
    private var hasDetectedSound = false
    private var currentRecognizedText = ""

    static let initialSilenceTimeout: TimeInterval = 8
    static let trailingSilenceTimeout: TimeInterval = 3
    static let maximumRecognitionDuration: TimeInterval = 60
    static let speechPowerThreshold: Float = 0.012
    /// 开麦后忽略音量检测的一小段。挡的是自己放出来的起音提示，见 `markSoundDetectedFromInputLevel()`。
    /// 系统音 1113 约 0.2~0.3 秒，取 0.4 秒留一点余量；这段时间里用户真开口了也不会漏 ——
    /// 首次静音上限是 8 秒，识别结果那一路照常生效。
    static let inputWarmUpWindow: TimeInterval = 0.4
    static let keyboardFallbackErrorMessage = "语音识别失败，请使用键盘输入。"

    init(audioSession: (any SpeechAudioSessionManaging)? = nil) {
        self.audioSession = audioSession ?? SystemSpeechAudioSession()
    }

    /// 启动时就把音频分类定下来。**由 `blindRunApp` 在启动阶段调一次。**
    ///
    /// 在此之前，整个 App **从来没有人配过音频会话** —— `setCategory` 只出现在本类里，
    /// 而它只在第一次开麦时才跑。也就是说冷启动到第一次录音之间，会话一直是系统默认的
    /// `.soloAmbient`，合成器要自己去协商一个会话，第一句话因此有一段可感知的延迟
    /// （2026-08-06 真机报的「点开始约跑之后要等一下才开始读」）。
    ///
    /// **只配分类，不激活**：激活会立刻打断用户正在听的音乐，而这时候我们还没有任何话要说。
    /// 分类本身不打断，只是让随后合成器的隐式激活落在 `.playback` 上，而不是随机的默认值。
    /// 取的值与 `restorePlaybackAudioSession()` 完全一致 —— 冷启动状态和录音结束后的状态
    /// 从此是同一个，少一种需要单独推理的情形。
    ///
    /// 刻意**不放进 `init`**：那会让每一个构造出替身的用例都先记一次会话操作，
    /// 而它们断言的是「录音停下来时依次做了什么」，多一条开头就全错。构造函数做音频 I/O
    /// 本身也是意外行为 —— 启动该做的事就写在启动那一段里。
    func prepareForPlaybackAtLaunch() {
        do {
            try audioSession.configurePlaybackCategory()
        } catch {
            // 配不上不该挡住 App 起来：合成器仍会自己协商一个会话，只是回到从前那样有延迟。
            logger.error("启动时配置播放音频分类失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    var activeFieldId: String? {
        activeField?.rawValue
    }

    /// Returns whether the given field is currently being listened to.
    func isListening(for field: SpeechInputField) -> Bool {
        isListening && activeField == field
    }

    /// Returns whether the given field owns the current recognition session,
    /// including the pending authorization window before recording starts.
    func hasRecognitionSession(for field: SpeechInputField) -> Bool {
        activeField == field
    }

    func startRecognition(
        field: SpeechInputField,
        onTextChanged: @escaping (String) -> Void,
        onAnnouncement: ((String) -> Void)? = nil,
        onCompletion: ((SpeechInputCompletion) -> Void)? = nil
    ) {
        if stopActiveRecognitionIfNeeded(beforeStarting: field) {
            return
        }

        announcementHandler = onAnnouncement
        completionHandler = onCompletion

        recognitionStartTask?.cancel()
        let sessionID = UUID()
        recognitionSessionID = sessionID
        activeField = field
        errorMessage = nil
        lastStopReason = nil
        currentRecognizedText = ""
        recognitionStartTask = Task { [weak self] in
            guard let self else { return }
            let speechAuthorized = await requestSpeechAuthorization()
            guard isCurrentRecognitionSession(sessionID, field: field) else { return }
            guard speechAuthorized else {
                errorMessage = "语音识别不可用，请使用键盘输入。"
                announce(errorMessage)
                clearRecognitionStartState(marking: .error)
                lastStopReason = .error
                return
            }

            let microphoneAuthorized = await requestMicrophoneAuthorization()
            guard isCurrentRecognitionSession(sessionID, field: field) else { return }
            guard microphoneAuthorized else {
                errorMessage = "麦克风不可用，请使用键盘输入。"
                announce(errorMessage)
                clearRecognitionStartState(marking: .error)
                lastStopReason = .error
                return
            }

            guard isCurrentRecognitionSession(sessionID, field: field) else { return }
            beginRecognition(onTextChanged: onTextChanged)
            if recognitionStartTask != nil, recognitionSessionID == sessionID {
                recognitionStartTask = nil
            }
        }
    }

    func stopRecognition() {
        stopAudioRecognition(reason: .manual, clearActiveField: true, announce: true, notifyCompletion: true, clearHandlers: true, invalidateSession: true)
    }

    func cancelRecognitionForLifecycle() {
        stopAudioRecognition(reason: .manual, clearActiveField: true, announce: false, notifyCompletion: false, clearHandlers: true, invalidateSession: true)
    }

    @discardableResult
    private func stopActiveRecognitionIfNeeded(beforeStarting field: SpeechInputField) -> Bool {
        if isListening && activeField == field {
            stopAudioRecognition(reason: .manual, clearActiveField: true, announce: true, notifyCompletion: true, clearHandlers: true)
            return true
        }

        if isListening {
            stopAudioRecognition(reason: .manual, clearActiveField: true, announce: true, notifyCompletion: true, clearHandlers: true)
        }

        return false
    }

    private func stopAudioRecognition(
        reason: SpeechInputStopReason,
        clearActiveField: Bool,
        announce: Bool,
        notifyCompletion: Bool,
        clearHandlers: Bool,
        invalidateSession: Bool = true,
        announcementAfterRestoration: String? = nil
    ) {
        let wasListening = isListening
        let hadAudioRecognitionSession = wasListening
            || audioEngine.isRunning
            || didInstallTap
            || recognitionRequest != nil
            || recognitionTask != nil
        let completedField = activeField
        let completedText = currentRecognizedText
        let completedHandler = completionHandler
        cancelStopTimers()
        if invalidateSession {
            recognitionSessionID = UUID()
            recognitionStartTask?.cancel()
            recognitionStartTask = nil
        }

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if didInstallTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            didInstallTap = false
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        if wasListening || reason == .error || (invalidateSession && completedField != nil) {
            lastStopReason = reason
        }
        recognitionStartedAt = nil
        lastSoundAt = nil
        hasDetectedSound = false
        currentRecognizedText = ""
        if clearActiveField {
            activeField = nil
        }

        if hadAudioRecognitionSession {
            restorePlaybackAudioSession()
        }

        // 结束提示放在音频会话切回播放之后：录音会话下放系统音会被路由到录音链路，用户可能根本听不见。
        if wasListening {
            RecordingCue.end()
        }

        self.announce(announcementAfterRestoration)

        if announce && wasListening {
            self.announce(reason.announcement)
        }

        if notifyCompletion, (wasListening || reason == .error), let completedField {
            completedHandler?(SpeechInputCompletion(
                field: completedField,
                recognizedText: completedText,
                reason: reason
            ))
        }

        if clearHandlers {
            announcementHandler = nil
            completionHandler = nil
        }
    }

    /// 「起听成功」的状态转换 —— 生产路径与测试替身共用的唯一出口。
    ///
    /// 抽出来是因为替身此前**少做了四件事**（`isSpeechPathUnavailable` 复位、两个静音检测游标、
    /// 以及起音提示 `RecordingCue.begin()`），于是「起音提示丢了」这类缺陷在测试里根本看不见。
    /// 与 `clearRecognitionStartState` 是同一个理由：成功与失败各有一个共同出口，
    /// 下一条新增的路径自动受益，而不是每个调用点各补一遍、各漏一遍。
    ///
    /// 计时器**刻意不在其中**：它依赖真实音频轮询，替身起了会在 8 秒后把自己停掉。
    private func markRecognitionStarted() {
        isListening = true
        lastStopReason = nil
        // 真的起听成功了，之前那次「语音链路不可用」的判断作废（授权可能刚被补授、recognizer 可能刚恢复）。
        isSpeechPathUnavailable = false
        recognitionStartedAt = Date()
        lastSoundAt = nil
        hasDetectedSound = false
        currentRecognizedText = ""
        RecordingCue.begin()
    }

    private func isCurrentRecognitionSession(_ sessionID: UUID, field: SpeechInputField) -> Bool {
        recognitionSessionID == sessionID && activeField == field && !Task.isCancelled
    }

    /// 启动阶段失败的共同出口：授权被拒（语音 / 麦克风）、recognizer 不可用都经由这里。
    ///
    /// **必须在清空 handler 之前送出一次终局完成。** 这条路径不经过 `stopAudioRecognition`，
    /// 而调用方只能靠完成回调发现语音这条路断了 —— `VoiceOrderWizard` 漏掉它就会停在
    /// `isRunning = true` 上无限静默等待，而看不见屏幕的人没有任何别的方式察觉。
    /// 修在这个共同出口而不是三个调用点：下一条新增的启动失败路径会自动受益。
    ///
    /// 幂等由「先取引用再置 nil」保证：第二次调用时 `activeField` 与 `completionHandler` 均已为空。
    private func clearRecognitionStartState(marking reason: SpeechInputStopReason) {
        let completedField = activeField
        let completedHandler = completionHandler

        recognitionSessionID = UUID()
        recognitionStartTask = nil
        activeField = nil
        lastStopReason = reason
        isSpeechPathUnavailable = true
        announcementHandler = nil
        completionHandler = nil

        if let completedField {
            completedHandler?(SpeechInputCompletion(
                field: completedField,
                recognizedText: "",
                reason: reason
            ))
        }
    }

    private func beginRecognition(onTextChanged: @escaping (String) -> Void) {
        guard recognizer?.isAvailable == true else {
            errorMessage = "语音识别暂不可用，请使用键盘输入。"
            announce(errorMessage)
            clearRecognitionStartState(marking: .error)
            return
        }

        stopAudioRecognition(reason: .manual, clearActiveField: false, announce: false, notifyCompletion: false, clearHandlers: false, invalidateSession: false)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        do {
            audioSessionDiagnosticMessage = nil
            try audioSession.configureRecordingCategory()
            try audioSession.activateRecording()
        } catch {
            handleRecognitionStartupFailure("语音输入启动失败，请使用键盘输入。")
            return
        }

        guard audioSession.isInputAvailable,
              audioSession.inputNumberOfChannels > 0,
              audioSession.sampleRate > 0 else {
            handleRecognitionStartupFailure("当前运行环境没有可用的麦克风输入，请使用键盘输入。")
            return
        }

        let inputNode = audioEngine.inputNode
        guard let recordingFormat = validRecordingFormat(from: inputNode) else {
            handleRecognitionStartupFailure("当前运行环境没有可用的麦克风输入，请使用键盘输入。")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self, weak request] buffer, _ in
            if SpeechInputService.containsAudibleSpeech(in: buffer) {
                Task { @MainActor in
                    self?.markSoundDetectedFromInputLevel()
                }
            }
            request?.append(buffer)
        }
        didInstallTap = true

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            handleRecognitionStartupFailure("语音输入启动失败，请使用键盘输入。")
            return
        }

        markRecognitionStarted()
        startStopTimers()
        announce("语音输入已开启，请说话。")
        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    let recognizedText = result.bestTranscription.formattedString
                    self.currentRecognizedText = recognizedText
                    onTextChanged(recognizedText)
                    if !recognizedText.trimmed.isEmpty {
                        self.markSoundDetected()
                    }
                    if result.isFinal {
                        self.stopAudioRecognition(reason: .finalResult, clearActiveField: true, announce: true, notifyCompletion: true, clearHandlers: true)
                    }
                }
                if error != nil, self.isListening {
                    self.errorMessage = SpeechInputStopReason.error.announcement
                    self.stopAudioRecognition(reason: .error, clearActiveField: true, announce: true, notifyCompletion: true, clearHandlers: true)
                }
            }
        }
    }

    private func handleRecognitionStartupFailure(_ message: String) {
        errorMessage = message
        stopAudioRecognition(
            reason: .error,
            clearActiveField: true,
            announce: false,
            notifyCompletion: true,
            clearHandlers: true,
            announcementAfterRestoration: message
        )
    }

    private func validRecordingFormat(from inputNode: AVAudioInputNode) -> AVAudioFormat? {
        let outputFormat = inputNode.outputFormat(forBus: 0)
        if outputFormat.hasValidSampleRateAndChannels {
            return outputFormat
        }

        let inputFormat = inputNode.inputFormat(forBus: 0)
        if inputFormat.hasValidSampleRateAndChannels {
            return inputFormat
        }

        return nil
    }

    private func startStopTimers() {
        cancelStopTimers()

        silenceMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                await MainActor.run {
                    self?.stopIfSilent()
                }
            }
        }

        maxDurationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.maximumRecognitionDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.isListening else { return }
                self.stopAudioRecognition(reason: .maxDuration, clearActiveField: true, announce: true, notifyCompletion: true, clearHandlers: true)
            }
        }
    }

    private func cancelStopTimers() {
        silenceMonitorTask?.cancel()
        silenceMonitorTask = nil
        maxDurationTask?.cancel()
        maxDurationTask = nil
    }

    /// 整句下单那一轮的静音阈值。
    ///
    /// 起点是「字段听写的 3 秒是给『说一个地名』定的，组织一整句会中途停顿」，这个判断没错，
    /// 错的是往上调过了头 —— 曾经取 12 秒。
    ///
    /// **12 秒站不住的三个理由**：自发语音的停顿时长呈对数正态，三个峰在 150ms / 500ms / 1500ms，
    /// 第三个峰就是句内最长的那类停顿；Dialogflow 的 no-speech 默认值是 5 秒，12 是它的 2.4 倍；
    /// 而 Nielsen 的 10 秒是「注意力还留在当前操作上」的上限，超过就得给进度反馈。
    /// 看不见屏幕的人对着一个没有任何反应的麦克风等 12 秒，判定不是「系统在等我」而是「死机了」。
    ///
    /// 取 **2 秒**：盖住 1500ms 那个峰再留 500ms 余量，同时远在「以为死机」区之外。
    /// 首次静音（压根没人说话）从 15 秒降到 8 秒，同理。
    ///
    /// 纯静音兜底在任何取值下都会牺牲一部分人，所以显式结束通道必须一直在：
    /// 整块内容区可点（`blindBookingFinishSpeakingSurface`）和 Magic Tap 都直接收音。
    private var activeInitialSilenceTimeout: TimeInterval {
        activeField == .voiceOrderFreeform ? 8 : Self.initialSilenceTimeout
    }

    private var activeTrailingSilenceTimeout: TimeInterval {
        activeField == .voiceOrderFreeform ? 2 : Self.trailingSilenceTimeout
    }

    private func stopIfSilent() {
        guard isListening, let recognitionStartedAt else { return }
        let now = Date()
        if !hasDetectedSound, now.timeIntervalSince(recognitionStartedAt) >= activeInitialSilenceTimeout {
            stopAudioRecognition(
                reason: .silenceTimeout(hadDetectedSound: false),
                clearActiveField: true,
                announce: true,
                notifyCompletion: true,
                clearHandlers: true
            )
            return
        }
        if hasDetectedSound,
           let lastSoundAt,
           now.timeIntervalSince(lastSoundAt) >= activeTrailingSilenceTimeout {
            stopAudioRecognition(
                reason: .silenceTimeout(hadDetectedSound: true),
                clearActiveField: true,
                announce: true,
                notifyCompletion: true,
                clearHandlers: true
            )
        }
    }

    private func markSoundDetected() {
        hasDetectedSound = true
        lastSoundAt = Date()
    }

    /// 音量那一路的入口。**开头一小段要丢掉。**
    ///
    /// 录音分类改成 `.playAndRecord` 之后，起音提示是真的从扬声器放出来的，而 `.measurement` 模式
    /// 没有回声消除 —— 那一声会被自己的麦克风录进来。若把它当成「用户开口了」，静音判定会立刻从
    /// 首次静音（8 秒）切到尾静音（整句轮 2 秒）：一个刚听到提示、正在组织句子的人，会在还没开口时
    /// 就被掐掉一轮，然后听到一整单默认值的读回。**那比原来的缺陷更糟。**
    ///
    /// 只挡音量这一路。识别结果那一路（`!recognizedText.trimmed.isEmpty`）不受影响 ——
    /// 那是真的转出了字，提示音转不出字。
    private func markSoundDetectedFromInputLevel() {
        guard Self.acceptsInputLevelSound(startedAt: recognitionStartedAt, now: Date()) else { return }
        markSoundDetected()
    }

    /// 抽成纯函数是为了能不睡 0.4 秒就断言这条规则。
    /// `startedAt == nil` 表示还没正式起听（`markRecognitionStarted` 未跑），一律不收。
    static func acceptsInputLevelSound(startedAt: Date?, now: Date) -> Bool {
        guard let startedAt else { return false }
        return now.timeIntervalSince(startedAt) >= inputWarmUpWindow
    }

    private func announce(_ message: String?) {
        guard let message, !message.isEmpty else { return }
        announcementHandler?(message)
    }

    private static func containsAudibleSpeech(in buffer: AVAudioPCMBuffer) -> Bool {
        guard let channelData = buffer.floatChannelData, buffer.frameLength > 0 else {
            return false
        }
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard channelCount > 0 else { return false }

        var sum: Float = 0
        for channelIndex in 0..<channelCount {
            let samples = channelData[channelIndex]
            for frameIndex in 0..<frameLength {
                let sample = samples[frameIndex]
                sum += sample * sample
            }
        }
        let meanSquare = sum / Float(frameLength * channelCount)
        return sqrt(meanSquare) >= speechPowerThreshold
    }

    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            audioSession.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func restorePlaybackAudioSession() {
        var recoveryFailures: [String] = []

        do {
            try audioSession.deactivateRecording()
        } catch {
            recoveryFailures.append("deactivate: \(error.localizedDescription)")
        }

        do {
            try audioSession.configurePlaybackCategory()
        } catch {
            recoveryFailures.append("category: \(error.localizedDescription)")
        }

        do {
            try audioSession.activatePlayback()
        } catch {
            recoveryFailures.append("activate: \(error.localizedDescription)")
        }

        guard !recoveryFailures.isEmpty else {
            audioSessionDiagnosticMessage = nil
            return
        }

        let message = "语音输入结束后恢复播放音频会话失败：\(recoveryFailures.joined(separator: "; "))"
        audioSessionDiagnosticMessage = message
        logger.error("\(message, privacy: .public)")
    }

    #if DEBUG
    func startRecognitionForTesting(fieldId: String) {
        guard let field = SpeechInputField(rawValue: fieldId) else {
            errorMessage = Self.keyboardFallbackErrorMessage
            activeField = nil
            isListening = false
            lastStopReason = .error
            return
        }
        startRecognitionForTesting(field: field)
    }

    func startRecognitionForTesting(
        field: SpeechInputField,
        onAnnouncement: ((String) -> Void)? = nil,
        onCompletion: ((SpeechInputCompletion) -> Void)? = nil
    ) {
        if stopActiveRecognitionIfNeeded(beforeStarting: field) {
            return
        }

        recognitionSessionID = UUID()
        activeField = field
        announcementHandler = onAnnouncement
        completionHandler = onCompletion
        markRecognitionStarted()
    }

    func failRecognitionStartupForTesting(_ message: String) {
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        handleRecognitionStartupFailure(message)
    }

    /// 模拟语音 / 麦克风授权被拒，或 recognizer 不可用 —— 三者共用 `clearRecognitionStartState`。
    /// 真实路径依赖系统授权弹窗，单测环境拿不到，所以在这一层开测试接缝。
    func denyAuthorizationForTesting() {
        clearRecognitionStartState(marking: .error)
    }

    @discardableResult
    func startPendingAuthorizationForTesting(
        field: SpeechInputField,
        onCompletion: ((SpeechInputCompletion) -> Void)? = nil
    ) -> UUID {
        if stopActiveRecognitionIfNeeded(beforeStarting: field) {
            recognitionSessionID = UUID()
        }
        let sessionID = UUID()
        recognitionSessionID = sessionID
        activeField = field
        isListening = false
        recognitionStartedAt = nil
        lastStopReason = nil
        currentRecognizedText = ""
        completionHandler = onCompletion
        return sessionID
    }

    func simulateAuthorizationCompletionForTesting(
        sessionID: UUID,
        field: SpeechInputField
    ) {
        guard isCurrentRecognitionSession(sessionID, field: field) else { return }
        markRecognitionStarted()
    }

    func finishRecognitionForTesting(
        text: String,
        reason: SpeechInputStopReason = .finalResult
    ) {
        currentRecognizedText = text
        stopAudioRecognition(reason: reason, clearActiveField: true, announce: false, notifyCompletion: true, clearHandlers: true)
    }

    func simulateRecognitionFailureForTesting(field: SpeechInputField) {
        activeField = field
        isListening = true
        errorMessage = Self.keyboardFallbackErrorMessage
        stopAudioRecognition(reason: .error, clearActiveField: true, announce: false, notifyCompletion: true, clearHandlers: true)
    }

    func triggerSilenceTimeoutForTesting(hadDetectedSound: Bool) {
        hasDetectedSound = hadDetectedSound
        stopAudioRecognition(
            reason: .silenceTimeout(hadDetectedSound: hadDetectedSound),
            clearActiveField: true,
            announce: false,
            notifyCompletion: true,
            clearHandlers: true
        )
    }
    #endif
}

private extension AVAudioFormat {
    var hasValidSampleRateAndChannels: Bool {
        sampleRate > 0 && channelCount > 0
    }
}
