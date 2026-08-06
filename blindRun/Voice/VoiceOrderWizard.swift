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

    /// **只有两轮。** 逐项修改（改地点 / 改时间 / 改时长）已于 2026-08-06 删除，理由见 `Command.restart`。
    enum Step: Equatable {
        /// 一次说完。用户在这一轮讲一整句。
        case freeform
        /// 读回整单后等指令：「确认」或「重说」。
        case confirm

        var speechField: SpeechInputField? {
            switch self {
            case .freeform: return .voiceOrderFreeform
            case .confirm: return .voiceOrderConfirm
            }
        }

        /// 短句、给例子 —— WCAG 3.3.2 要求对输入格式给出示例，语音场景尤其如此。
        /// `.confirm` 的提问依赖当前整单内容，由 `confirmPrompt(for:)` 拼装，这里只留兜底。
        var prompt: String {
            switch self {
            case .freeform:
                return "请说你想从哪儿出发、什么时候跑、跑多久，比如：明天早上八点从人民广场出发跑一个小时。说完再点一下就好。"
            case .confirm:
                return "说「确认」就下单；要重新说一遍就说「重说」。"
            }
        }
    }

    /// `.confirm` 轮的本地指令判定结果。
    ///
    /// **`.restart` 取代了原来的三个 `.fix(...)`**（2026-08-06）。删除逐项修改的直接原因是真机手测：
    /// 用户说「改地点」，识别成同音的「**该地点**」——「该地点」本身就是常用词，屏幕上的字看起来
    /// 几乎一样 —— 整串精确匹配不中，于是人一直卡在读回这一轮，之后说的每个地名对
    /// 「确认 / 改X」这张表都是无效指令，每次都回「没听懂」。用户报的
    /// 「不管我说什么地点他都返回没听懂」就是这个现象。
    ///
    /// 换成「重说」有三个好处，而代价只有「只想改时间也要把整句重说一遍」（约 5 秒）：
    /// - 22 个修改词的整串匹配表整个消失，脆的东西没了
    /// - 三个只在这条路径上存在的向导步骤消失，界面不再在用户脚下换成表单
    /// - 出错时只有一个动作要记，而不是三个 —— 记忆成本对目标用户是最贵的那部分
    enum Command: Equatable {
        case confirm
        case restart
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
    /// 本轮语音**真的抽到了**开始时间。
    ///
    /// 必须与 `bookingViewModel.appointmentTime` 分开记：那个字段的初值是 `Date()`，
    /// 光看它分不出「用户说了个正好是现在的时间」和「压根没抽出来」。而这两者对盲人是天壤之别 ——
    /// 一个是他说的，另一个是系统编的。
    @Published private(set) var didCaptureStartTime = false
    /// 连续多少轮没拿到开始时间。到上限就交回表单，见 `moveToConfirm`。
    private var roundsWithoutStartTime = 0
    /// 最近一次解析失败是「这个接口根本不存在」，而不是「没听懂你说什么」。
    ///
    /// 这两者对用户的**下一步动作完全不同**：前者重说多少遍都不会变好，后者值得再说一次。
    /// 后端把未部署的端点回成带 `NOT_FOUND` 的业务信封（`/api/orders/voice/parse` 生产上
    /// 就是这个状态，见 handoff 2026-08-06），所以客户端分得出来 —— 分得出来就不该混为一谈。
    private var parseIsUnavailable = false

    /// 连着这么多轮拿不到开始时间就不再让人重说。取 2：给一次重说的机会，不给第二次。
    static let maximumRoundsWithoutStartTime = 2

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
        didCaptureStartTime = false
        roundsWithoutStartTime = 0
        parseIsUnavailable = false
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
        // 时间这一项**只在真的抽到时才念具体时刻**。
        //
        // 以前无条件念 `appointmentSummary`，而 `appointmentTime` 的初值是 `Date()` ——
        // 抽不出时间时，读回会念出一个用户从没说过的具体时刻，后面再补一句「需至少在 30 分钟后」。
        // 对听不见屏幕的人，那就是「它念了一张我没说过的单」（2026-08-06 用户原话：
        // 「他也没有经过我的同意」）。没说就说没说，不许编。
        parts.append(didCaptureStartTime ? bookingViewModel.appointmentSummary : "预约时间还没说。")
        parts.append(bookingViewModel.optionalNeedsSpeechSummary)
        parts.append(confirmOutro)
        return parts.joined()
    }

    /// 读回结尾那句出路。缺关键槽位时**不能**教用户说「确认」——
    /// 教了他会说，说了不生效，那是比不教更糟的体验。
    private var confirmOutro: String {
        if let blocked = missingRequiredSlotMessage {
            return blocked
        }
        return "说「确认」就下单；要重新说一遍就说「重说」。"
    }

    /// 关键槽位缺失时的说明。**只有开始时间是关键的**：
    /// 起点缺失有正当默认（当前位置，且读回会念出来）；时长在产品上就是选填，
    /// 读回念「没有填写选填跑步需求」本来就是诚实的，没有编造。
    private var missingRequiredSlotMessage: String? {
        guard !didCaptureStartTime else { return nil }
        return "还没听到你说预约时间，现在不能下单。请说「重说」，然后把出发地点、什么时候跑、跑多久一次说完。"
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
            // ~~整句这一轮什么都没听到：不重问，直接读回默认整单。用户可能就是想「什么都不说，
            // 按默认下单」，重问只会挡着他。~~ **2026-08-06 真机手测推翻这条。**
            //
            // 实际发生的是：用户没听到起音提示（提示音走响铃通道、被静音拨杆关掉，见
            // `RecordingCue`），根本不知道麦克风开了，于是沉默着等提示；8 秒后系统判定
            // 「他想用默认值」，念了一整单他从没说过的预约 —— 时间是 30 分钟后、时长是默认档。
            // 用户的原话是「他也没有经过我的同意」。
            //
            // 「沉默 = 同意默认值」这个假设本身就不成立，对看不见屏幕的人尤其不成立：
            // 沉默的原因绝大多数是**没听见、没听懂、还在想**，而不是「我接受你的默认值」。
            // 而这条路径的下一步就是读回 + 说「确认」成单，把一次没听清放大成一张真实订单。
            //
            // 现在整句轮和别的轮一样重问，共用 `maximumReasksPerSlot`（两次重问后交回表单）。
            // 这也与调研 §6.6 一致：识别为空一律重问、上限 3 次，那一节本来就没有给整句开口子。
            //
            // 注意这**不影响**「说了话但抽不出槽位」那条路径 —— 那时 transcript 非空，
            // 走 `parseFreeform` 用默认值补齐并读回，是对的：用户确实说了，他能在读回里听出来。
            reask(with: silenceReaskMessage(for: completion.reason))
            return
        }

        parseTask?.cancel()
        parseTask = Task { [weak self] in
            await self?.submitTranscript(transcript)
        }
    }

    /// 什么都没听到时说的那句话。
    ///
    /// 整句那一轮**带上例句**：调研 §6.6 引 Google 的错误处理规范 ——「例子比解释有效」，
    /// 而听不见屏幕的人在这里缺的正是「我到底该说什么」，不是「再说一次」这个指令。
    /// 其余轮次的提问本身就短且带例子（见 `Step.prompt`），重复一遍反而拖长。
    private func silenceReaskMessage(for reason: SpeechInputStopReason) -> String {
        if reason == .error {
            return "语音识别没能启动，我再问一次。"
        }
        if step == .freeform {
            return "没有听到你说话。请说你想从哪儿出发、什么时候跑、跑多久，比如：明天早上八点从人民广场出发跑一个小时。"
        }
        return "没有听到你说话，我再问一次。"
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
        parseIsUnavailable = false
        do {
            parsed = try await parseOrderResponse(transcript)
        } catch {
            parseFailed = true
            parseIsUnavailable = Self.isEndpointMissing(error)
        }

        // 端点根本不存在：连一次读回都不做，直接交回表单。
        //
        // 读回在这里没有任何价值 —— 它必然念一整套默认值，而时间抽不到就不许确认，
        // 用户唯一能做的只有重说，重说还是 404。给他一次「听起来像是可以再试试」的读回，
        // 只是把死路包装得像活路。
        if parseIsUnavailable {
            fallBack(reason: Self.parseUnavailableNotice, joinsReasonDirectly: true)
            return
        }

        if let raw = parsed?.plannedStartTime, let date = raw.backendLocalDate {
            bookingViewModel?.appointmentTime = date
            didCaptureStartTime = true
        }
        if let place = parsed?.resolvedStartPlace {
            bookingViewModel?.applyVoiceResolvedStartPlace(
                address: place.address, latitude: place.latitude, longitude: place.longitude
            )
        }

        var notice: String? = parseFailed ? Self.parseFailureNotice : nil
        if let minutes = parsed?.durationMinutes {
            let accepted = Self.acceptedDurationMinutes(minutes)
            bookingViewModel?.exactDurationMinutes = accepted
            notice = Self.durationClampNotice(spokenMinutes: minutes, accepted: accepted)
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

    /// 「这个接口在服务端根本不存在」——**重说多少遍都不会变好**，与「没听懂」必须分开。
    ///
    /// 上面 `parseFailureNotice` 那三条措辞约束（不说网络、不说没听到、不给指令）针对的是
    /// **偶发**失败。端点未部署不是偶发，它是常态，而对它说「下面念的是默认值」等于邀请用户
    /// 再试一次 —— 试一万次也一样。所以这一路单独播、并且直接交回表单。
    static let parseUnavailableNotice = "语音下单暂时用不了，"

    /// 后端把未部署的端点回成 `errorCode: NOT_FOUND` 的业务信封（不是 nginx 裸 404）。
    /// 只认这一种：超时、鉴权过期、5xx 都可能是暂时的，不该被当成「功能不存在」。
    private static func isEndpointMissing(_ error: Error) -> Bool {
        guard case APIError.serverError(let response) = error else { return false }
        return response.code == "NOT_FOUND"
    }

    /// 契约允许的时长区间（`api_spec.yaml:2549`：`minimum: 10` / `maximum: 300`）。
    static let minimumDurationMinutes = 10
    static let maximumDurationMinutes = 300

    /// 语音说的分钟数**原样采用**，只在超出契约区间时夹到边界。
    ///
    /// 2026-08-06 之前这里是「就近 snap 到 6 个枚举档位」，于是「跑三个小时」变成两小时 ——
    /// 枚举存在的理由是选择器需要有限选项，而说话的人不需要选择器。契约本来就收 10–300。
    static func acceptedDurationMinutes(_ spoken: Int) -> Int {
        min(maximumDurationMinutes, max(minimumDurationMinutes, spoken))
    }

    /// 时长被夹到边界时要说的那句话；没动就返回 nil。
    ///
    /// **静默改动对听不见屏幕的人就是篡改**，这条红线不因为改动幅度变小而消失 ——
    /// 现在只有真的超出契约区间才会发生，但发生了就必须说。
    private static func durationClampNotice(spokenMinutes: Int, accepted: Int) -> String? {
        guard accepted != spokenMinutes else { return nil }
        return "你说的是\(spokenMinutes)分钟，超出了可预约范围，本次按\(BlindBookingViewModel.durationText(forMinutes: accepted))预约。"
    }

    /// - Parameter notice: 需要先说一句再读回的话（例如时长被取整）。**必须和读回拼成同一段**，
    ///   分两次 `speak` 会让 `lastSpokenPrompt` 只剩后一句，「重复一遍」就再也念不到取整提示了 ——
    ///   对听不见屏幕的人，念不到等于没发生。
    private func moveToConfirm(notice: String? = nil) {
        reaskCount = 0

        // 连着两轮都没拿到开始时间就交回表单，**不许再让人重说**。
        //
        // 这是「时间抽不出就不许确认」那条规则的必要配套。少了它，只要解析这一环是坏的
        // （例如 `/api/orders/voice/parse` 在生产上恒 404），用户就落进一个没有出口的圈：
        // 说一整句 → 抽不出时间 → 不给确认 → 「请说重说」→ 重说 → 还是抽不出 → 无限循环。
        // 2026-08-06 手测就是这么卡住的：用户第二遍明确说了时间，仍然抽不到。
        //
        // 对看不见屏幕的人，一个没有出口的循环比一条错误信息糟得多 —— 他没有别的方式发现
        // 这条路根本走不通。
        if didCaptureStartTime {
            roundsWithoutStartTime = 0
        } else {
            roundsWithoutStartTime += 1
            if roundsWithoutStartTime >= Self.maximumRoundsWithoutStartTime {
                fallBack(reason: parseIsUnavailable
                         ? "语音下单服务暂时不可用"
                         : "连续两次没听到预约时间")
                return
            }
        }

        step = .confirm
        pendingNotice = notice
        askCurrentStep()
    }

    // MARK: Confirm

    private func handleConfirmCommand(_ transcript: String) async {
        switch Self.command(for: transcript) {
        case .confirm:
            // 缺关键槽位时「确认」不生效 —— 用户没说过时间，不能凭一句「确认」就派单。
            // 读回结尾已经念过原因（`missingRequiredSlotMessage`），这里再说一次是因为
            // 用户可能是听完很久才开的口，中间隔了多少秒我们不知道。
            if let blocked = missingRequiredSlotMessage {
                reask(with: blocked)
                return
            }
            await submitConfirmedBooking()
        case .repeatBack:
            reaskCount = 0
            askCurrentStep()
        case .restart:
            restartFromFreeform()
        case .unrecognized:
            reask(with: "没听懂。说「确认」就下单，或者说「重说」重新说一遍。")
        }
    }

    /// 从头再说一遍。**必须把上一轮抽到的槽位清干净**，否则新的一句没提到的项会留着旧值，
    /// 而读回照样把它念出来 —— 用户会以为那是他这次说的。
    private func restartFromFreeform() {
        reaskCount = 0
        lastUtterance = nil
        pendingNotice = nil
        didCaptureStartTime = false
        bookingViewModel?.resetVoiceFilledSlots()
        step = .freeform
        askCurrentStep()
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

    // MARK: Networking

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
    /// - Parameter joinsReasonDirectly: `reason` 自己已经带了标点、直接拼下一句。
    ///   默认 `false` 时补一个逗号（「连续两次没听到预约时间，已切回表单⋯⋯」）。
    private func fallBack(reason: String, joinsReasonDirectly: Bool = false) {
        isRunning = false
        speechInputService?.stopRecognition()
        let message = joinsReasonDirectly
            ? "\(reason)已切回表单填写，你可以用屏幕上的输入框继续预约。"
            : "\(reason)，已切回表单填写，你可以用屏幕上的输入框继续预约。"
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
    /// - Parameter didCaptureStartTime: 这一轮语音是否真的抽到了开始时间。
    ///   默认 `false`（= 用户还没说过时间），此时「确认」按设计不生效 —— 想验提交路径的用例
    ///   必须显式传 `true`，否则测的是「缺时间被拦住」而不是提交。
    func startForTesting(at step: Step, didCaptureStartTime: Bool = false) {
        isRunning = true
        self.step = step
        reaskCount = 0
        fallbackMessage = nil
        self.didCaptureStartTime = didCaptureStartTime
    }

    /// 把一次录音完成回调直接喂进来，不碰麦克风。
    ///
    /// `submitTranscript` 进不了这条路径：它从**有转录文本**的地方开始，而这里要验的恰恰是
    /// 「一个字都没听到」时的分支 —— 2026-08-06 那张「没经用户同意的默认订单」就出在这里，
    /// 而它此前一条断言都没有。
    func handleCompletionForTesting(_ completion: SpeechInputCompletion) {
        handle(completion)
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

    /// 「重说」的触发词。**这一组用包含匹配，不用整串匹配** —— 与 `affirmatives` 刻意相反。
    ///
    /// 两组的失败方向不对称，所以匹配严格程度也该不一样：
    /// - 把「不是确认的话」误判成确认 → 产生一张用户没打算下的真实订单。必须整串、必须严。
    /// - 把「不是重说的话」误判成重说 → 用户多说一句话。可以松。
    ///
    /// 整串匹配在这一组上已经被真机证伪：用户说「改地点」被识别成同音的「该地点」，整串不中，
    /// 人就卡在读回那一轮出不来。包含匹配对同音字仍然无能为力，所以词表里把
    /// **「重」「从」两种常见误识都收进来**，并且不依赖单个字。
    private static let restartWords: [String] = [
        "重说", "重新说", "从新说", "重新讲", "重来", "重新来", "从头说", "从头再说", "从头来",
        "再说一次", "重新预约", "重新说一遍", "重新来过"
    ]

    /// 「把刚才那段再念给我听」。**注意与 `restartWords` 的语义分界**：
    /// 这一组是「你再念一遍」，那一组是「我再说一遍」。中文里「再说一遍」两种意思都有，
    /// 这里把它划给「重说」（`restartWords` 里），因为读回结尾教的就是「重说」，
    /// 而「重复」「再念一遍」在语义上不可能被理解成「我要重新讲」。
    private static let repeatWords: Set<String> = [
        "重复", "重复一遍", "再念一遍", "没听清", "再念一次", "你再说一遍"
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

    /// 判定顺序有意义：**肯定词先判、且只认整串**，免得「重新确认一下」这种话里的「确认」被包含匹配吃掉。
    static func command(for transcript: String) -> Command {
        let normalized = normalizedCommand(transcript)
        guard !normalized.isEmpty else { return .unrecognized }
        if affirmatives.contains(normalized) { return .confirm }
        if repeatWords.contains(normalized) { return .repeatBack }
        if restartWords.contains(where: { normalized.contains($0) }) { return .restart }
        return .unrecognized
    }

    // MARK: Helpers

    // `durationOption(forMinutes:)`（就近 snap 到 6 个枚举档位）已于 2026-08-06 删除。
    // 语音说多少就是多少，只夹到契约区间，见 `acceptedDurationMinutes(_:)`。
}
