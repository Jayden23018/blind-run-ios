import Combine
import CoreLocation
import Foundation

// MARK: - Voice Order Wizard

/// 语音下单的客户端状态机：一次只问一个槽位，问完读回确认，**最后一步不自动提交**。
///
/// 形态依据（见 `plan` 与调研）：VERSE (ASSETS 2019) 对 53 位法定盲人的调查显示，读屏在「多步骤、
/// 后果重、需要核对」的任务上仍然是首选，语音赢在 walk-up 便利；国标也要求不可逆操作满足「动作可逆
/// 或提交前可复核」之一。所以这里是**读屏优先、语音加速**：语音只负责把三个槽位填进既有的
/// `BlindBookingViewModel`，最终仍落到既有的确认步骤，由用户显式提交。向导随时可以中止，
/// 表单永远是可用的回退路径。
///
/// 后端是无状态的：三个端点互不依赖，是「一次只问一个」这个产品选择在客户端实现的
/// （`语音下单交接说明.md` 第五节 FAQ）。
@MainActor
final class VoiceOrderWizard: ObservableObject {

    enum Step: Int, CaseIterable {
        case startPlace
        case startTime
        case duration
        case review

        var speechField: SpeechInputField? {
            switch self {
            case .startPlace: return .voiceOrderStartPlace
            case .startTime: return .voiceOrderStartTime
            case .duration: return .voiceOrderDuration
            case .review: return nil
            }
        }

        /// 每一轮的提问。短句、给例子 —— WCAG 3.3.2 要求对输入格式给出示例，语音场景尤其如此。
        var prompt: String {
            switch self {
            case .startPlace: return "请说出发地点，比如：人民广场地铁站。"
            case .startTime: return "请说什么时候出发，比如：明天早上八点半。"
            case .duration: return "请说打算跑多久，比如：一个小时。"
            case .review: return "三项都记好了。"
            }
        }
    }

    /// 同一个槽位连续听不清多少次就放弃语音。三次之后继续追问只会让人重复喊同一句话，
    /// 交回表单是更快的路。
    static let maximumReasksPerSlot = 3
    /// 等 TTS 播完再开录音的上限：不等的话麦克风会把自己的播报当成用户说话。
    static let speechSettleTimeout: TimeInterval = 8
    /// 单次解析的等待上限。**这是防网络卡死的，不是防解析慢的。**
    ///
    /// 后端建议 3.5 秒（handoff 2026-08-01 ⑤），但那个数说的是服务端解析耗时上限：大模型兜底内部
    /// 3 秒超时后自己降级成 `needReask`。客户端这层包的是整个 HTTP 往返，3.5 秒会把「服务端 3 秒
    /// 兜底成功 + 网络往返」这类**本该成功**的长尾表达判成超时，等于把后端专门为口语化表达做的兜底
    /// 一并废掉 —— 而「明天差不多这个点吧」正是最需要它的说法。
    /// 取 8 秒：留足 3 秒解析 + 弱网往返，同时不至于让人无声地等下去。
    static let parseTimeout: TimeInterval = 8

    @Published private(set) var step: Step = .startPlace
    @Published private(set) var isRunning = false
    @Published private(set) var isParsing = false
    /// 当前这一轮的槽位已经重问了几次。
    @Published private(set) var reaskCount = 0
    /// 语音路径放弃了，请用表单。带上原因，供界面展示与播报。
    @Published private(set) var fallbackMessage: String?
    /// 最近一次播报的文案，供「重复一次」使用。
    @Published private(set) var lastSpokenPrompt: String?

    private weak var bookingViewModel: BlindBookingViewModel?
    private weak var speechService: SpeechService?
    private weak var speechInputService: SpeechInputService?
    private var apiClient: (any APIClientProtocol)?
    private var currentCoordinate: (() -> LocatedCoordinate?)?
    private var parseTask: Task<Void, Never>?

    private enum WizardError: Error { case parseTimedOut }

    // MARK: Wiring

    /// - Parameter currentCoordinate: 当前位置，用于给 `resolve-address` 做就近消歧。
    ///   必须是**后端坐标系（GCJ-02）**的真实采样 —— 传 `LocationService.latestBackendSample()`，
    ///   它在没有真实定位时返回 nil，正好等于「不带这两个字段」。
    func configure(
        bookingViewModel: BlindBookingViewModel,
        speechService: SpeechService,
        speechInputService: SpeechInputService,
        apiClient: any APIClientProtocol,
        currentCoordinate: (() -> LocatedCoordinate?)? = nil
    ) {
        self.bookingViewModel = bookingViewModel
        self.speechService = speechService
        self.speechInputService = speechInputService
        self.apiClient = apiClient
        self.currentCoordinate = currentCoordinate
    }

    // MARK: Lifecycle

    /// 起步前先跑一遍下单硬门槛。让盲人说完三轮才被服务端 403 拒掉是最坏的顺序 ——
    /// 门槛的唯一真源是 `OrderCreationService.createOrder`，客户端这份只是把同样的顺序提前。
    /// 返回 `false` 表示没有启动，调用方按 `fallbackMessage` 引导用户去补前置项。
    @discardableResult
    func start() -> Bool {
        guard let bookingViewModel else { return false }
        if let gate = bookingViewModel.firstMissingGate, gate != .startPoint, gate != .appointmentTime {
            fallbackMessage = gate.message
            speak(gate.message)
            return false
        }
        fallbackMessage = nil
        isRunning = true
        step = .startPlace
        reaskCount = 0
        askCurrentStep()
        return true
    }

    func stop() {
        parseTask?.cancel()
        parseTask = nil
        speechInputService?.stopRecognition()
        isRunning = false
        isParsing = false
    }

    /// 重复当前这一轮的问题。语音消失得快，重听是基本诉求。
    func repeatCurrentPrompt() {
        speak(lastSpokenPrompt ?? step.prompt)
    }

    // MARK: Asking

    private func askCurrentStep() {
        guard isRunning, let field = step.speechField else { return }
        let prompt = step.prompt
        speak(prompt)
        listen(for: field)
    }

    private func listen(for field: SpeechInputField) {
        guard let speechInputService else { return }
        Task { [weak self] in
            await self?.waitForSpeechToSettle()
            guard let self, self.isRunning, self.step.speechField == field else { return }
            speechInputService.startRecognition(
                field: field,
                onTextChanged: { _ in },
                onAnnouncement: nil,
                onCompletion: { [weak self] completion in
                    self?.handle(completion)
                }
            )
        }
    }

    /// TTS 还在播时开录音，麦克风会先录到系统自己的声音，识别必然跑偏。
    private func waitForSpeechToSettle() async {
        guard let speechService else { return }
        let deadline = Date().addingTimeInterval(Self.speechSettleTimeout)
        while speechService.isSpeaking && Date() < deadline {
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
    }

    // MARK: Recognition results

    private func handle(_ completion: SpeechInputCompletion) {
        guard isRunning, completion.field == step.speechField else { return }
        let transcript = completion.recognizedText.trimmed

        guard completion.reason.shouldTriggerSearchWithRecognizedText, !transcript.isEmpty else {
            // 没听到声音或识别本身失败：这不是解析问题，重问一次即可，仍然计入重问上限。
            reask(with: completion.reason == .error
                  ? "语音识别没能启动，我再问一次。"
                  : "没有听到你说话，我再问一次。")
            return
        }

        parseTask?.cancel()
        parseTask = Task { [weak self] in
            await self?.submitTranscript(transcript)
        }
    }

    /// 把一段转录文本喂给当前槽位对应的解析端点。
    ///
    /// 与录音解耦是有意的：麦克风那一段由 `SpeechInputService` 自己的用例覆盖，向导这边真正要锁的是
    /// 「`needReask` 不推进」「三次降级」「解析结果落到哪个字段」，这些不需要真的说话就能验。
    func submitTranscript(_ transcript: String) async {
        guard let apiClient else { return }
        isParsing = true
        defer { isParsing = false }

        do {
            switch step {
            case .startPlace:
                // 带上当前坐标让后端走周边搜索。拿不到真实定位就不带 —— 宁可退回正向编码，
                // 也不能拿演示坐标去消歧，那会把人约到另一座城市。
                let sample = currentCoordinate?()
                let coordinate = sample?.system == .gcj02Backend ? sample?.coordinate : nil
                let response: ResolveAddressResponse = try await withParseTimeout {
                    try await apiClient.post(
                        VoiceOrderEndpoint.resolveAddress,
                        body: ResolveAddressRequest(
                            transcript: transcript,
                            latitude: coordinate?.latitude,
                            longitude: coordinate?.longitude
                        )
                    )
                }
                guard response.isUsable,
                      let latitude = response.latitude,
                      let longitude = response.longitude,
                      let address = response.address else {
                    reask(with: response.ttsText ?? "没听清地点，请再说一次出发地。")
                    return
                }
                bookingViewModel?.applyVoiceResolvedStartPlace(
                    address: address,
                    latitude: latitude,
                    longitude: longitude
                )
                advance(after: response.ttsText ?? "出发地点是\(address)。")

            case .startTime:
                let response: ParseSlotResponse = try await withParseTimeout {
                    try await apiClient.post(
                        VoiceOrderEndpoint.parseSlot,
                        body: ParseSlotRequest(transcript: transcript, field: .startTime)
                    )
                }
                guard response.needReask != true,
                      let raw = response.plannedStartTime,
                      let date = DateFormatter.aidRunBackendLocalDateTime.date(from: raw) else {
                    reask(with: response.ttsText ?? "没听清开始时间，请再说一次，比如：明天早上八点。")
                    return
                }
                bookingViewModel?.appointmentTime = date
                advance(after: response.ttsText ?? "开始时间已记录。")

            case .duration:
                let response: ParseSlotResponse = try await withParseTimeout {
                    try await apiClient.post(
                        VoiceOrderEndpoint.parseSlot,
                        body: ParseSlotRequest(transcript: transcript, field: .duration)
                    )
                }
                guard response.needReask != true, let minutes = response.durationMinutes else {
                    reask(with: response.ttsText ?? "没听清时长，请再说一次，比如：一个小时。")
                    return
                }
                let option = Self.durationOption(forMinutes: minutes)
                bookingViewModel?.duration = option
                // 只有在真的挪动了用户说的数字时才多说一句 —— 静默取整对听不见屏幕的人就是篡改。
                let confirmation = option.minutes == minutes
                    ? (response.ttsText ?? "时长\(minutes)分钟。")
                    : "你说的是\(minutes)分钟，本应用按\(option.displayName)预约。"
                advance(after: confirmation)

            case .review:
                return
            }
        } catch is WizardError {
            // 超时不是「没听清」，但对用户来说下一步是一样的：再说一次。计入重问上限，
            // 连续卡三次就交回表单，而不是让人对着麦克风重复到放弃。
            reask(with: "网络有点慢，没能及时听懂，请再说一次。")
        } catch let error as APIError {
            fallBack(reason: error.localizedMessage)
        } catch {
            fallBack(reason: "网络异常")
        }
    }

    /// 给一次解析请求加超时。后端的模型兜底自己有 3 秒降级，这层防的是网络卡死 ——
    /// 没有它，向导会静默地永远停在「正在识别」，而盲人听不到任何提示。
    private func withParseTimeout<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(Self.parseTimeout * 1_000_000_000))
                throw WizardError.parseTimedOut
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw WizardError.parseTimedOut }
            return result
        }
    }

    // MARK: Transitions

    private func advance(after confirmation: String) {
        reaskCount = 0
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
        guard next != .review else {
            isRunning = false
            speak("\(confirmation) \(bookingViewModel?.reviewSummarySpeech ?? "")请确认后提交预约。")
            return
        }
        speak(confirmation)
        askCurrentStep()
    }

    private func reask(with message: String) {
        reaskCount += 1
        guard reaskCount < Self.maximumReasksPerSlot else {
            fallBack(reason: "连续\(Self.maximumReasksPerSlot)次没听清")
            return
        }
        speak(message)
        guard let field = step.speechField else { return }
        listen(for: field)
    }

    /// 语音路径走不通时**必须**说清楚接下来去哪 —— 看不见屏幕的人没有别的方式发现语音已经停了。
    private func fallBack(reason: String) {
        isRunning = false
        speechInputService?.stopRecognition()
        let message = "\(reason)，已切回表单填写，你可以用屏幕上的输入框继续预约。"
        fallbackMessage = message
        speak(message)
    }

    private func speak(_ text: String) {
        lastSpokenPrompt = text
        speechService?.speak(text)
    }

    #if DEBUG
    /// 从任意槽位起步，且不碰麦克风。用例要验的是解析与推进，真录音由 `SpeechInputService` 自己的
    /// 用例覆盖（且单测环境拿不到麦克风授权）。
    func startForTesting(at step: Step) {
        isRunning = true
        self.step = step
        reaskCount = 0
        fallbackMessage = nil
    }
    #endif

    // MARK: Helpers

    /// 后端接受 10~300 的任意分钟数，表单只有 6 个固定档位。就近取一档，
    /// 并在读回确认时明说取整了（见 `parse` 里的 `confirmation`）。
    ///
    /// ponytail: 取整而不是把 `BookingDurationOption` 改成任意分钟数 —— 后者要动选择器 UI、复核文案和
    /// 既有用例。等产品确定语音要支持任意时长，再把这个枚举换成 `Int?`。
    static func durationOption(forMinutes minutes: Int) -> BookingDurationOption {
        let options = BookingDurationOption.allCases.filter { $0.minutes != nil }
        let nearest = options.min { lhs, rhs in
            abs((lhs.minutes ?? 0) - minutes) < abs((rhs.minutes ?? 0) - minutes)
        }
        return nearest ?? .sixty
    }
}
