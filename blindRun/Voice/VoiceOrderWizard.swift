import Combine
import CoreLocation
import Foundation

// MARK: - Voice Order Wizard

/// 语音下单的客户端状态机：**一次说完 → 读回整单 → 确认或定点修改**。
///
/// 形态依据（调研 2026-08-03）：跳过确认环节的纯语音执行在盲人场景有已知翻车模式（语音购物研究记录了
/// 「用户说出特定商品、系统用通用确认回应了完全不同商品」的真实案例，根因是设计假设「用户会瞄一眼屏幕
/// 核对」，而这个假设对盲人不成立）；但纯分步表单也不是答案（ACM 研究显示盲人用户偏好连续指令，
/// 反感每一步重新触发）。证据指向的是**一次说完 + 强制语音复述确认**这个混合模式。
///
/// 后端能担什么，是读后端源码定的，不是猜的（`demo/src/main/java/.../VoiceSlotParser.java`）：
/// - **时间 / 时长可以整句抽**：正则用 `Matcher.find()` 搜子串而非全串匹配，且中文数字先归一成阿拉伯
///   数字；正则不中还有 Qwen-Flash 兜底。所以「明天早上八点跑一个小时」这一句能同时喂给两个槽位。
/// - **地点自 2026-08-04 起也能整句抽**：后端 `POST /api/orders/voice/parse` 先抽地名 span 再查高德，
///   不再把整句原样喂正向地理编码（那样要么返空、要么分词命中噪声词给出错地点）。此前那个常闭开关
///   `resolvesPlaceFromFullUtterance` 已随之删除，整句一次拿三个槽位。
///
/// ⚠️ **`missing` 里的 `ADDRESS` 分不出「用户没说地点」和「说了但没抽出」**（已提给后端，handoff
///   2026-08-04）。前者用当前位置是对的，后者静默用当前位置会把人约到错误起点。在后端给出区分之前，
///   靠读回环节念出实际起点兜底 —— 这是本流程目前最薄的一处。
///
/// 表单永远是可用的回退路径：向导随时可以停，停了屏幕上就是原来那张表。
@MainActor
final class VoiceOrderWizard: ObservableObject {

    enum Step: Equatable {
        /// 一次说完。用户在这一轮讲一整句，能抽出什么算什么，抽不出的用默认值补。
        case freeform
        /// 读回整单后等指令：「确认」或「改地点 / 改时间 / 改时长」。
        case confirm
        /// 定点修改。**只有这一轮说的是纯地名**，所以只有这一轮的 geocode 是可靠的。
        case startPlace
        case startTime
        case duration

        var speechField: SpeechInputField? {
            switch self {
            case .freeform: return .voiceOrderFreeform
            case .confirm: return .voiceOrderConfirm
            case .startPlace: return .voiceOrderStartPlace
            case .startTime: return .voiceOrderStartTime
            case .duration: return .voiceOrderDuration
            }
        }

        /// 短句、给例子 —— WCAG 3.3.2 要求对输入格式给出示例，语音场景尤其如此。
        /// `.confirm` 的提问依赖当前整单内容，由 `confirmPrompt(for:)` 拼装，这里只留兜底。
        var prompt: String {
            switch self {
            case .freeform:
                return "请说你想从哪儿出发、什么时候跑、跑多久，比如：明天早上八点从人民广场出发跑一个小时。说完再点一下就好。"
            case .confirm:
                return "说「确认」就下单；要改就说「改地点」「改时间」或者「改时长」。"
            case .startPlace: return "请只说出发地点，比如：人民广场地铁站。"
            case .startTime: return "请说什么时候出发，比如：明天早上八点半。"
            case .duration: return "请说打算跑多久，比如：一个小时。"
            }
        }
    }

    /// `.confirm` 轮的本地指令判定结果。
    enum Command: Equatable {
        case confirm
        case fix(Step)
        case repeatBack
        case unrecognized
    }

    /// 同一轮连续听不清多少次就放弃语音。三次之后继续追问只会让人重复喊同一句话。
    static let maximumReasksPerSlot = 3
    /// 等 TTS 播完再开录音的上限：不等的话麦克风会把自己的播报当成用户说话。
    ///
    /// **这是上限，不是等待时长** —— 播完就立刻放行。它存在只是为了在合成器代理丢事件时不至于
    /// 无限等下去。
    ///
    /// 曾经写死 8 秒，而读回整单在默认语速下要 15~25 秒（见 `finishSpeakingOrSkipPrompt` 的说明），
    /// 于是**每一次读回都必被截断**：上限一到就开麦，而开麦会把音频会话切成允许录音的分类，
    /// 正在播的 `AVSpeechSynthesizer` 当场断掉。2026-08-06 真机手测报的「读到一半自动截断然后开始
    /// 录音」就是这条。修法不是把 8 调大一个拍脑袋的数，而是让上限跟着要念的字数走。
    ///
    /// 系数 0.35 秒/字：中文合成在 `AVSpeechUtteranceDefaultSpeechRate` 下约 3~5 字/秒，取慢的那端
    /// 再加 6 秒起步余量。下限 8 秒保持不变（短提示的行为不变），上限 45 秒防止异常长文本把人吊死。
    static func settleTimeout(forCharacterCount count: Int) -> TimeInterval {
        min(45, max(8, Double(count) * 0.35 + 6))
    }
    /// 单次解析的等待上限。**这是防网络卡死的，不是防解析慢的。**
    ///
    /// 后端建议 3.5 秒（handoff 2026-08-01 ⑤），但那个数说的是服务端解析耗时上限：大模型兜底内部
    /// 3 秒超时后自己降级成 `needReask`。客户端这层包的是整个 HTTP 往返，3.5 秒会把「服务端 3 秒
    /// 兜底成功 + 网络往返」这类**本该成功**的长尾表达判成超时，等于把后端专门为口语化表达做的兜底
    /// 一并废掉 —— 而「明天差不多这个点吧」正是最需要它的说法。
    /// 取 8 秒：留足 3 秒解析 + 弱网往返，同时不至于让人无声地等下去。
    static let parseTimeout: TimeInterval = 8

    @Published private(set) var step: Step = .freeform
    @Published private(set) var isRunning = false
    @Published private(set) var isParsing = false
    /// 当前这一轮已经重问了几次。
    @Published private(set) var reaskCount = 0
    /// 语音路径放弃了，请用表单。带上原因，供界面展示与播报。
    @Published private(set) var fallbackMessage: String?
    /// 最近一次播报的文案，供「重复一次」使用。
    @Published private(set) var lastSpokenPrompt: String?
    /// 边说边更新的识别文本。**只用于屏幕显示，不播报** —— 一边说一边念会和用户自己的声音打架。
    @Published private(set) var partialTranscript = ""
    /// 用户在 `.freeform` 那一轮说的原话，读回时先念它，再念解析结果。
    /// 念原话是为了让用户能分辨「我说错了」和「它听错了」——只念解析结果的话这两者无从区分。
    @Published private(set) var lastUtterance: String?
    /// 下单成功后创建出的订单。视图订阅它去走既有的 `onOrderCreated` 出口，
    /// 这样语音提交和按钮提交落到同一条跳转路径上。
    @Published private(set) var createdOrder: OrderResponse?

    private weak var bookingViewModel: BlindBookingViewModel?
    private weak var speechService: SpeechService?
    private weak var speechInputService: SpeechInputService?
    private var apiClient: (any APIClientProtocol)?
    private var currentCoordinate: (() -> LocatedCoordinate?)?
    private var parseTask: Task<Void, Never>?
    /// 下一次读回前要先说的一句话（目前只有时长取整）。拼进读回而不是单独播一次，见 `moveToConfirm`。
    private var pendingNotice: String?
    /// 当前这一句最晚等到什么时候就强行开麦。由 `speak(_:)` 按字数定，见 `settleTimeout(forCharacterCount:)`。
    private var speechSettleDeadline: Date?

    private enum WizardError: Error { case parseTimedOut, notConfigured }

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

    /// 起步前先跑一遍下单硬门槛。让盲人说完一整句才被服务端 403 拒掉是最坏的顺序 ——
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
        // 语音这条路已经在启动阶段失败过（授权被拒 / recognizer 不可用）：直接交回表单。
        // 明知打不开麦克风还走一遍重问循环，只会让人听三轮「我再问一次」才等到降级。
        if speechInputService?.isSpeechPathUnavailable == true {
            fallBack(reason: "语音输入当前不可用")
            return false
        }
        fallbackMessage = nil
        createdOrder = nil
        lastUtterance = nil
        partialTranscript = ""
        isRunning = true
        step = .freeform
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

    /// 用户主动结束这一轮录音（「再点一下」）。停止会走完成回调，后续解析由 `handle` 接手。
    ///
    /// 与 `stop()` 的区别：`stop()` 是放弃整个语音流程，这里只是「我说完了」。
    func finishSpeaking() {
        guard isRunning, speechInputService?.isListening == true else { return }
        speechInputService?.stopRecognition()
    }

    /// 向导运行期间「屏幕上那一下」的唯一入口：**在录音就是「我说完了」，在播报就是「别念了」。**
    ///
    /// 读回整单（原话 + 三项 + 两条出路）在写死的默认语速下要 15~25 秒，而读屏用户日常把语速调到
    /// 14~16 字/秒。中途没有出路，等于把最熟练的用户按在最慢的一档上听完 —— 熟练用户正是最先弃用的人。
    ///
    /// 停播之后不需要额外做什么：`listen` 里 `waitForSpeechToSettle` 的循环条件自然放行，麦克风随即打开。
    /// 所以这里没有新状态，只是提前结束等待。
    func finishSpeakingOrSkipPrompt() {
        guard isRunning else { return }
        if speechInputService?.isListening == true {
            finishSpeaking()
        } else if speechService?.isSpeaking == true {
            speechService?.stop()
        }
    }

    /// 重复当前这一轮的问题。语音消失得快，重听是基本诉求。
    func repeatCurrentPrompt() {
        speak(lastSpokenPrompt ?? step.prompt)
    }

    // MARK: Asking

    private func askCurrentStep() {
        guard isRunning, let field = step.speechField else { return }
        let prompt: String
        if step == .confirm, let bookingViewModel {
            prompt = confirmPrompt(for: bookingViewModel)
        } else {
            prompt = step.prompt
        }
        speak(prompt)
        listen(for: field)
    }

    /// 读回整单。先念用户原话，再念最终要下的单，最后给出两条出路。
    ///
    /// 三段缺一不可：没有原话，用户分不清是自己说错还是系统听错；没有整单，用户不知道默认值补了什么；
    /// 没有出路，看不见屏幕的人不会自己发现还能说「改时间」。
    private func confirmPrompt(for bookingViewModel: BlindBookingViewModel) -> String {
        var parts: [String] = []
        if let pendingNotice, !pendingNotice.isEmpty {
            parts.append(pendingNotice)
        }
        if let lastUtterance, !lastUtterance.isEmpty {
            parts.append("我听到你说：\(lastUtterance)。")
        }
        parts.append("这次的预约是：")
        parts.append(bookingViewModel.startPointSummary)
        parts.append(bookingViewModel.appointmentSummary)
        parts.append(bookingViewModel.optionalNeedsSpeechSummary)
        parts.append("说「确认」就下单；要改就说「改地点」「改时间」或者「改时长」。")
        return parts.joined()
    }

    private func listen(for field: SpeechInputField) {
        guard let speechInputService else { return }
        partialTranscript = ""
        Task { [weak self] in
            await self?.waitForSpeechToSettle()
            guard let self, self.isRunning, self.step.speechField == field else { return }
            speechInputService.startRecognition(
                field: field,
                // 实时文本只写屏，不播报：边说边念会盖住用户自己的声音，识别也会跟着跑偏。
                onTextChanged: { [weak self] text in
                    self?.partialTranscript = text
                },
                // 录音起止的可听提示由 `SpeechInputService` 统一发出，向导转交给 TTS 通道，
                // 免得两边各播一次。
                onAnnouncement: { [weak self] message in
                    self?.speechService?.announce(message)
                },
                onCompletion: { [weak self] completion in
                    self?.handle(completion)
                }
            )
        }
    }

    /// TTS 还在播时开录音，麦克风会先录到系统自己的声音，识别必然跑偏。
    private func waitForSpeechToSettle() async {
        guard let speechService else { return }
        let deadline = speechSettleDeadline
            ?? Date().addingTimeInterval(Self.settleTimeout(forCharacterCount: 0))
        while speechService.isSpeaking && Date() < deadline {
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
    }

    // MARK: Recognition results

    private func handle(_ completion: SpeechInputCompletion) {
        guard isRunning, completion.field == step.speechField else { return }
        let transcript = completion.recognizedText.trimmed
        partialTranscript = ""

        guard completion.reason.shouldTriggerSearchWithRecognizedText, !transcript.isEmpty else {
            // 整句这一轮什么都没听到：不重问，直接读回默认整单让用户确认或修改。
            // 用户可能就是想「什么都不说，按默认下单」，重问只会挡着他。
            guard step != .freeform else {
                lastUtterance = nil
                moveToConfirm()
                return
            }
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

    /// 把一段转录文本交给当前这一轮的处理逻辑。
    ///
    /// 与录音解耦是有意的：麦克风那一段由 `SpeechInputService` 自己的用例覆盖，向导这边真正要锁的是
    /// 「整句抽取落到哪些字段」「非确认绝不提交」「三次降级」，这些不需要真的说话就能验。
    func submitTranscript(_ transcript: String) async {
        switch step {
        case .freeform:
            await parseFreeform(transcript)
        case .confirm:
            await handleConfirmCommand(transcript)
        case .startPlace, .startTime, .duration:
            await parseSingleSlot(transcript)
        }
    }

    // MARK: Freeform

    /// 一整句一次抽三个槽位（起点 / 开始时间 / 时长），抽不出的保留默认值。
    ///
    /// **这一轮不重问、不失败。** 抽出多少算多少，剩下的由读回环节交代清楚，让用户决定要不要改。
    /// 让整句这一轮也走「没听清就重问」，会把用户按在同一句话上反复喊——而他其实只要听一遍
    /// 结果就知道该改哪一项。
    ///
    /// 所以 `missing` / `needReask` / 后端 `ttsText` 三个字段在这一轮**一个都不消费**：
    /// `missing` 等价于「这几项保持默认值」，而后端的 `ttsText` 在 `missing` 非空时是**追问**文案，
    /// 播它就等于把人拉回重问。读回一律用 `confirmPrompt` 自己拼的整单（后端 2026-08-04 确认：
    /// 抽不出的槽位保留什么默认值只有客户端知道，后端拼不出整单）。
    private func parseFreeform(_ transcript: String) async {
        enterParsing(saying: "正在识别，请稍候。")
        defer { isParsing = false }
        lastUtterance = transcript

        // 一次请求拿三个槽位。这一轮**吞掉所有错误**：整句抽不出或网络挂了都不该把用户打回表单，
        // 默认值仍然成单，让读回环节把实际内容念清楚，由用户决定改不改。
        //
        // 但**吞掉不等于不说**：原来这里是 `try?`，失败时一个槽位都不填，读回念的全是默认值，
        // 而用户听不出「语音没在工作」和「语音听懂了但你说的正好是默认值」的区别 ——
        // 没仔细听就下了一张时间地点全错的单。2026-08-06 查实 `/api/orders/voice/parse` 的 handler
        // 只在后端未部署分支上，生产恒 404，这条路径不是偶发而是常态。
        var parsed: ParseVoiceOrderResponse?
        var parseFailed = false
        do {
            parsed = try await parseOrderResponse(transcript)
        } catch {
            parseFailed = true
        }

        if let raw = parsed?.plannedStartTime, let date = raw.backendLocalDate {
            bookingViewModel?.appointmentTime = date
        }
        if let place = parsed?.resolvedStartPlace {
            bookingViewModel?.applyVoiceResolvedStartPlace(
                address: place.address, latitude: place.latitude, longitude: place.longitude
            )
        }

        var notice: String? = parseFailed ? Self.parseFailureNotice : nil
        if let minutes = parsed?.durationMinutes {
            let option = Self.durationOption(forMinutes: minutes)
            bookingViewModel?.duration = option
            notice = Self.durationRoundingNotice(spokenMinutes: minutes, option: option)
        }

        moveToConfirm(notice: notice)
    }

    /// 整句解析失败时先说的那句话。
    ///
    /// 措辞上的三条约束：
    /// - **不说「网络」**。404、超时、鉴权过期表现相同，客户端分不出来，断言原因就是编。
    /// - **不说「没听到」**。ASR 是成功的，紧接着的「我听到你说：⋯⋯」会念出原话，说没听到自相矛盾。
    ///   失败的是把原话转成预约内容这一步。
    /// - **不给指令**。读回结尾那句「要改就说『改地点』⋯⋯」已经把出路说全了，再说一遍只是把
    ///   本就 15~25 秒的读回拖得更长。
    static let parseFailureNotice = "这次没能把你说的话转成预约内容，下面念的是默认值。"

    /// 时长被挪到最近档位时要说的那句话；没挪动就返回 nil。
    ///
    /// 整句轮和定点修改轮共用同一句 —— 此前只有定点修改轮播报，整句轮是静默取整，
    /// 而**静默取整对听不见屏幕的人就是篡改**，同一条红线不该有两种行为。
    private static func durationRoundingNotice(spokenMinutes: Int, option: BookingDurationOption) -> String? {
        guard option.minutes != spokenMinutes else { return nil }
        return "你说的是\(spokenMinutes)分钟，本应用按\(option.displayName)预约。"
    }

    /// - Parameter notice: 需要先说一句再读回的话（例如时长被取整）。**必须和读回拼成同一段**，
    ///   分两次 `speak` 会让 `lastSpokenPrompt` 只剩后一句，「重复一遍」就再也念不到取整提示了 ——
    ///   对听不见屏幕的人，念不到等于没发生。
    private func moveToConfirm(notice: String? = nil) {
        reaskCount = 0
        step = .confirm
        pendingNotice = notice
        askCurrentStep()
    }

    // MARK: Confirm

    private func handleConfirmCommand(_ transcript: String) async {
        switch Self.command(for: transcript) {
        case .confirm:
            await submitConfirmedBooking()
        case .repeatBack:
            reaskCount = 0
            askCurrentStep()
        case .fix(let target):
            reaskCount = 0
            step = target
            askCurrentStep()
        case .unrecognized:
            reask(with: "没听懂。说「确认」就下单，或者说「改地点」「改时间」「改时长」。")
        }
    }

    /// 用户说了「确认」：走既有的提交路径。
    ///
    /// 提交失败时不重来一遍语音 —— `BlindBookingViewModel.submit()` 已经播报并写好了 `errorMessage`，
    /// 把表单停在确认步骤，用户可以听着错误原因手动重试，这比在语音里重放一遍失败更可控。
    private func submitConfirmedBooking() async {
        // 先落 isRunning，再取 viewModel：停止录音的完成回调会再进一次 `handle`，那里靠 isRunning 挡住。
        // 顺序反过来的话，拿不到 viewModel 时向导会一直显示在跑、麦克风也不放。
        isRunning = false
        speechInputService?.stopRecognition()
        guard let bookingViewModel else { return }
        enterParsing(saying: "正在提交订单。")
        defer { isParsing = false }

        if let response = await bookingViewModel.submit() {
            createdOrder = response
        }
    }

    // MARK: Single-slot fix

    /// 定点修改。修好一项就回到读回环节把整单再念一遍 —— 改完不复核，用户无从确认改对了没有。
    private func parseSingleSlot(_ transcript: String) async {
        enterParsing(saying: "正在识别，请稍候。")
        defer { isParsing = false }

        do {
            switch step {
            case .startPlace:
                let response = try await resolveAddressResponse(transcript)
                guard response.isUsable,
                      let latitude = response.latitude,
                      let longitude = response.longitude,
                      let address = response.address else {
                    reask(with: response.ttsText ?? "没听清地点，请再说一次出发地。")
                    return
                }
                bookingViewModel?.applyVoiceResolvedStartPlace(
                    address: address, latitude: latitude, longitude: longitude
                )
                moveToConfirm()

            case .startTime:
                let response = try await parseSlotResponse(transcript, field: .startTime)
                guard response.needReask != true,
                      let raw = response.plannedStartTime,
                      let date = raw.backendLocalDate else {
                    reask(with: response.ttsText ?? "没听清开始时间，请再说一次，比如：明天早上八点。")
                    return
                }
                bookingViewModel?.appointmentTime = date
                moveToConfirm()

            case .duration:
                let response = try await parseSlotResponse(transcript, field: .duration)
                guard response.needReask != true, let minutes = response.durationMinutes else {
                    reask(with: response.ttsText ?? "没听清时长，请再说一次，比如：一个小时。")
                    return
                }
                let option = Self.durationOption(forMinutes: minutes)
                bookingViewModel?.duration = option
                // 只有在真的挪动了用户说的数字时才多说一句 —— 静默取整对听不见屏幕的人就是篡改。
                moveToConfirm(notice: Self.durationRoundingNotice(spokenMinutes: minutes, option: option))

            case .freeform, .confirm:
                return
            }
        } catch is WizardError {
            // 超时不是「没听清」，但对用户来说下一步是一样的：再说一次。计入重问上限，
            // 连续卡三次就交回表单，而不是让人对着麦克风重复到放弃。
            reask(with: "网络有点慢，没能及时听懂，请再说一次。")
        } catch let error as APIError {
            // 接口层面的失败重问多少次都不会变好，直接交回表单。
            fallBack(reason: error.localizedMessage)
        } catch {
            fallBack(reason: "网络异常")
        }
    }

    // MARK: Networking

    private func parseSlotResponse(_ transcript: String, field: VoiceSlotField) async throws -> ParseSlotResponse {
        guard let apiClient else { throw WizardError.notConfigured }
        return try await withParseTimeout {
            let response: ParseSlotResponse = try await apiClient.post(
                VoiceOrderEndpoint.parseSlot,
                body: ParseSlotRequest(transcript: transcript, field: field)
            )
            return response
        }
    }

    /// 整句解析。请求体与 `resolve-address` 完全一致（spec 明说），所以复用同一个类型。
    private func parseOrderResponse(_ transcript: String) async throws -> ParseVoiceOrderResponse {
        guard let apiClient else { throw WizardError.notConfigured }
        let body = disambiguationRequest(transcript: transcript)
        return try await withParseTimeout {
            let response: ParseVoiceOrderResponse = try await apiClient.post(
                VoiceOrderEndpoint.parseOrder,
                body: body
            )
            return response
        }
    }

    private func resolveAddressResponse(_ transcript: String) async throws -> ResolveAddressResponse {
        guard let apiClient else { throw WizardError.notConfigured }
        let body = disambiguationRequest(transcript: transcript)
        return try await withParseTimeout {
            let response: ResolveAddressResponse = try await apiClient.post(
                VoiceOrderEndpoint.resolveAddress,
                body: body
            )
            return response
        }
    }

    /// 带上当前坐标让后端走周边搜索做就近消歧。**拿不到真实定位就不带** —— 宁可退回正向编码，
    /// 也不能拿演示坐标去消歧，那会把人约到另一座城市。
    ///
    /// 两个解析端点共用这一份：这条红线只该有一个出处，复制第二遍迟早有一边忘了判 `system`。
    private func disambiguationRequest(transcript: String) -> ResolveAddressRequest {
        let sample = currentCoordinate?()
        let coordinate = sample?.system == .gcj02Backend ? sample?.coordinate : nil
        return ResolveAddressRequest(
            transcript: transcript,
            latitude: coordinate?.latitude,
            longitude: coordinate?.longitude
        )
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
        // 上限在开口的那一刻按字数定下来。放在这里而不是 `waitForSpeechToSettle` 里，是因为那边
        // 只看得到「还在不在念」，看不到念的是什么。
        speechSettleDeadline = Date().addingTimeInterval(Self.settleTimeout(forCharacterCount: text.count))
        speechService?.speak(text)
    }

    /// 进入一次网络往返，并把这件事说出来。
    ///
    /// 不说的话，全盲用户在结束音之后听到的是长达 `parseTimeout`（8 秒）的绝对静默 —— 这正是
    /// AppleVis 对语音类 App「按下之后全程没有任何反馈」的那条抱怨，和我们用来论证要做
    /// `RecordingCue` 的是同一条依据，只守住起止两端等于只守了一半。
    ///
    /// 刻意**不走** `speak(_:)`：那会把 `lastSpokenPrompt` 顶掉，「重复一遍」就再也念不回刚才的提问。
    /// 也刻意不加触觉：`RecordingCue.end()` 的震动刚在几十毫秒前发生过，再震一次是噪声不是信息。
    /// 结果回来时 `askCurrentStep` 的播报会打断这一句 —— 被打断本身就是「好了」的信号。
    ///
    /// 本地判定那一路（肯定词、定点修改指令）**不经过这里**：它零延迟，没有需要填的静默。
    private func enterParsing(saying notice: String) {
        isParsing = true
        speechService?.speak(notice)
    }

    #if DEBUG
    /// 从任意轮起步，且不碰麦克风。用例要验的是解析与推进，真录音由 `SpeechInputService` 自己的
    /// 用例覆盖（且单测环境拿不到麦克风授权）。
    func startForTesting(at step: Step) {
        isRunning = true
        self.step = step
        reaskCount = 0
        fallbackMessage = nil
    }
    #endif

    // MARK: Command recognition

    /// 「确认」的肯定词。**整串匹配，不做包含匹配。**
    ///
    /// 两个方向的错误代价不对称：把「确认」误判成「非确认」只是让用户多说一轮；把「改时间」误判成
    /// 「确认」会产生一张用户没打算下的订单并触发真实派单。所以这里只认明确的肯定表达。
    ///
    /// 不做包含匹配的直接理由：「不确认」「先别确认」「确认一下时间」都含有「确认」，
    /// 而意思分别是否定、否定、要求复核。
    ///
    /// 刻意不收「嗯」：它做犹豫填充词的次数不比做肯定少，而这里的误判方向是会真下单的那一边。
    ///
    /// **2026-08-05 收窄：单音节高频应答词全部移出。**
    /// 2018 年 Portland 那起 Alexa 事故是这条规则的完整证据链 —— Amazon 官方复盘里，
    /// 助手问 "[名字], right?"，背景对话中的一句 **"right"** 满足了确认，把一段私人录音发了出去。
    /// 中文的「好」「行」「对」「是」与 "right" 完全同构，而陪跑场景还多一个加重因素：
    /// **志愿者可能就站在旁边说话**，这几个字正是中文日常应答里频率最高的。
    ///
    /// 移出的词：好 / 好的 / 行 / 可以 / 对 / 是 / 没错 / 同意 / 确定 / 提交 / 下单。
    /// 前九个是单双音节应答词；「提交」「下单」是名词性动词，会在「我要下单」「帮我提交一下」
    /// 这类叙述里命中。
    ///
    /// 保留「确认」是因为读回的出路那句念的就是「说『确认』就下单」（见 `confirmPrompt`）——
    /// **白名单必须和系统教用户说的话一致**，否则用户照着念却不生效。改任一边都要改另一边。
    ///
    /// 代价是方言与长句表达更容易被判为「非确认」，用户多说一轮。这正是可接受的失败方向。
    private static let affirmatives: Set<String> = [
        "确认", "确认下单", "确认预约", "确认提交",
        "没问题", "就这样", "就这么办", "开始约跑"
    ]

    private static let placeFixWords: Set<String> = [
        "改地点", "修改地点", "换地点", "换个地点", "改出发地", "改出发地点", "地点", "改地址"
    ]

    private static let timeFixWords: Set<String> = [
        "改时间", "修改时间", "换时间", "换个时间", "改出发时间", "时间", "改几点"
    ]

    private static let durationFixWords: Set<String> = [
        "改时长", "修改时长", "换时长", "改跑多久", "时长", "改多久", "改时间长度"
    ]

    private static let repeatWords: Set<String> = [
        "再说一遍", "重复", "重复一遍", "再念一遍", "没听清", "再说一次"
    ]

    /// 句尾语气词不改变语义，剥掉可以显著提高召回而不牺牲安全性（「确认吧」「好的呀」）。
    /// 句首不剥：那会让「不确认」这类否定的判定变得脆弱，而多问一轮是可接受的失败方向。
    private static let trailingParticles: Set<Character> = ["吧", "啊", "呀", "了", "哦", "喔", "嘛", "呗", "咯", "啦"]

    /// ponytail: 本地整串匹配，不接后端。`parse-slot` 没有 confirm 槽位，而这里要的是
    /// 高精度的指令识别、不是意图分类，本地表在这件事上不比大模型差，还省掉网络往返与超时窗口。
    /// 天花板：方言与长句表达会被判为「没听懂」，用户因此多说一轮。等真实使用数据显示误判率
    /// 高到值得处理，再考虑新增后端 confirm 槽位。
    static func normalizedCommand(_ transcript: String) -> String {
        var normalized = transcript.filter { !$0.isWhitespace && !$0.isPunctuation && !$0.isSymbol }
        while let last = normalized.last, trailingParticles.contains(last) {
            normalized.removeLast()
        }
        return normalized
    }

    static func isAffirmative(_ transcript: String) -> Bool {
        let normalized = normalizedCommand(transcript)
        guard !normalized.isEmpty else { return false }
        return affirmatives.contains(normalized)
    }

    static func command(for transcript: String) -> Command {
        let normalized = normalizedCommand(transcript)
        guard !normalized.isEmpty else { return .unrecognized }
        if affirmatives.contains(normalized) { return .confirm }
        if repeatWords.contains(normalized) { return .repeatBack }
        if placeFixWords.contains(normalized) { return .fix(.startPlace) }
        if timeFixWords.contains(normalized) { return .fix(.startTime) }
        if durationFixWords.contains(normalized) { return .fix(.duration) }
        return .unrecognized
    }

    // MARK: Helpers

    /// 后端接受 10~300 的任意分钟数，表单只有 6 个固定档位。就近取一档，
    /// 并在读回确认时明说取整了。
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
