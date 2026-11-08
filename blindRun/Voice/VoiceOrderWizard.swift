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

    /// **只有两轮。** 走「逐项追问」的独立步骤已于 2026-08-06 删除，理由见 `Command.restart`；
    /// 2026-08-10 接入后端 `current` 之后，定点修改**在读回这一轮之内完成**，
    /// 没有再回到多步骤形态 —— 屏幕不会在用户说话的中途换成另一张表单。
    enum Step: Equatable {
        /// 一次说完。用户在这一轮讲一整句。
        case freeform
        /// 起点撞了同名地点，念候选让用户挑一个（后端 2026-08-10 起返回 `candidates`，N48）。
        ///
        /// **这是唯一一个由后端文案驱动的轮次** —— 候选列表只有后端知道
        /// （名称、行政区、距您多少米），客户端拼不出来，所以 `prompt` 直接带着后端的 `ttsText`。
        ///
        /// 为什么值得为它加回一个步骤（2026-08-06 才刚删掉三个步骤）：那三个删掉的是**逐项追问**，
        /// 用户得记住「改地点/改时间/改时长」三个指令；这一轮只要记一个序数，而且刚被念过。
        /// 更重要的是它没有替代品 —— 不挑就只能静默取第一条，而那正是把人约到外省的那条路。
        case disambiguateStart(candidates: [AddressCandidate], prompt: String)
        /// 读回整单后等用户的下一句：确认、改某一项、取消、重听，或整句重说。
        case confirm

        var speechField: SpeechInputField? {
            switch self {
            case .freeform: return .voiceOrderFreeform
            // 复用既有的起点轮字段：逐项追问删掉之后它一直空着，而这一轮问的正是起点。
            // 新加一个枚举值要同步 `isAllowlisted` 的白名单，白拿一处可能漏改的地方。
            case .disambiguateStart: return .voiceOrderStartPlace
            case .confirm: return .voiceOrderConfirm
            }
        }

        /// 短句、给例子 —— WCAG 3.3.2 要求对输入格式给出示例，语音场景尤其如此。
        /// `.confirm` 的提问依赖当前整单内容，由 `confirmPrompt(for:)` 拼装，这里只留兜底。
        var prompt: String {
            switch self {
            case .freeform:
                return "请说你想从哪儿出发、什么时候跑、跑多久，比如：明天早上八点从人民广场出发跑一个小时。说完稍停，会自动结束。"
            case .disambiguateStart(_, let prompt):
                return prompt
            case .confirm:
                return Self.confirmOutroText
            }
        }

        /// 读回结尾那句出路。**三条都要念** —— 看不见屏幕的人不会自己发现「可以只改一项」，
        /// 不教就等于没有这个功能。中间那条是 2026-08-10 接入跨轮修正后加的。
        static let confirmOutroText =
            "说「确认」就下单；要改哪一项直接说，比如「时间改成明天早上九点」；要整句重说就说「重说」。"
    }

    /// `.confirm` 轮**第 1 档**（本地直通）的判定结果。`.unrecognized` 不是终点 ——
    /// 它意味着「本地表接不住，交后端」，见 `handleConfirmCommand`。
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
    /// 曾经写死 8 秒，而读回整单在默认语速下要 15~25 秒（原话 + 三项 + 两条出路），
    /// 于是**每一次读回都必被截断**：上限一到就开麦，而开麦会把音频会话切成允许录音的分类，
    /// 正在播的 `AVSpeechSynthesizer` 当场断掉。2026-08-06 真机手测报的「读到一半自动截断然后开始
    /// 录音」就是这条。修法不是把 8 调大一个拍脑袋的数，而是让上限跟着要念的字数走。
    ///
    /// 系数 0.35 秒/字：中文合成在 `AVSpeechUtteranceDefaultSpeechRate` 下约 3~5 字/秒，取慢的那端
    /// 再加 6 秒起步余量。下限 8 秒保持不变（短提示的行为不变），上限 45 秒防止异常长文本把人吊死。
    /// `nonisolated`：`VoiceService` 不是 `@MainActor`，而它要用同一个上限判「这条是不是卡住了」
    /// （见 `VoiceService.clearStaleUtteranceIfNeeded`）。纯函数，没有可竞争的状态。
    /// 抄一份公式过去是更差的选择 —— 两处上限迟早分叉，而分叉的那一天没有任何东西会报警。
    nonisolated static func settleTimeout(forCharacterCount count: Int) -> TimeInterval {
        min(45, max(8, Double(count) * 0.35 + 6))
    }
    /// 单次解析的等待上限。**这是防网络卡死的，不是防解析慢的。**
    ///
    /// 后端建议 3.5 秒（handoff 2026-08-01 ⑤），但那个数说的是服务端解析耗时上限：大模型兜底内部
    /// 3 秒超时后自己降级成 `needReask`。客户端这层包的是整个 HTTP 往返，3.5 秒会把「服务端 3 秒
    /// 兜底成功 + 网络往返」这类**本该成功**的长尾表达判成超时，等于把后端专门为口语化表达做的兜底
    /// 一并废掉 —— 而「明天差不多这个点吧」正是最需要它的说法。
    /// ~~取 8 秒~~ **2026-08-09 提到 12 秒**：后端接终点（SPEC B1）之后，`/parse` **每次都调大模型**
    /// —— 终点没有正则实现，不调就恒为 null。后端实测 `qwen3.7-plus` + 结构化输出 3.4~4.3 秒，
    /// 服务端自己的兜底超时是 8 秒。8 秒的客户端上限正好卡在服务端兜底的边界上，
    /// 「服务端 8 秒兜底成功 + 网络往返」必然超过它 —— 那是把**本该成功**的响应判成超时，
    /// 与上一段拒绝 3.5 秒是同一个理由。
    ///
    /// 12 秒也必须小于 `APIClient` 的 idle 超时（15 秒），这样先响的是这一层：
    /// 用户听到的才是「这次没能把你说的话转成预约内容」这句人话，而不是一个网络错误。
    static let parseTimeout: TimeInterval = 12

    @Published var step: Step = .freeform
    @Published var isRunning = false
    @Published var isParsing = false
    /// 当前这一轮已经重问了几次。
    @Published var reaskCount = 0
    /// 语音路径放弃了，请用表单。带上原因，供界面展示与播报。
    /// **只用于语音根本没法工作的情况**（权限被拒、端点不存在）—— 重说多少遍都不会好。
    @Published var fallbackMessage: String?
    /// 语音会话已结束、但**仍停在语音面板上**（后端 #502，负责人 2026-10-02 拍板）：
    /// 用户说了「算了」，或连续没听清。全盲用户基本不可能用表单下单，这两种结局不再送去表单。
    /// 非 nil 时 `isRunning` 一定是 false；界面据此保留语音面板、轻点重新开始。
    @Published var endedMessage: String?
    /// 结束态是因为没听清（而不是用户主动取消）。只有这一种才在面板上提供「不用填，直接下单」——
    /// 用户刚说了「算了」，再递一个下单按钮是在跟他唱反调。
    @Published var endedAfterFailure = false
    /// 最近一次空结果是「识别没能启动」（`.error`），不是「没听到」。重问满上限时据此分流：
    /// 识别起不来（首次在系统弹窗里拒了语音 / 麦克风权限就是这条）重说多少遍都不会好，仍交回表单；
    /// 只是没听清才停在语音面板（#502）。不分流的话，拒了权限的人会听到「暂时没听清」并被留在一个用不了的语音页上。
    var lastEmptyCompletionWasStartFailure = false
    /// 最近一次播报的文案，供「重复一次」使用。
    @Published var lastSpokenPrompt: String?
    /// 边说边更新的识别文本。**只用于屏幕显示，不播报** —— 一边说一边念会和用户自己的声音打架。
    @Published var partialTranscript = ""
    /// 用户在 `.freeform` 那一轮说的原话，读回时先念它，再念解析结果。
    /// 念原话是为了让用户能分辨「我说错了」和「它听错了」——只念解析结果的话这两者无从区分。
    @Published var lastUtterance: String?
    /// 下单成功后创建出的订单。视图订阅它去走既有的 `onOrderCreated` 出口，
    /// 这样语音提交和按钮提交落到同一条跳转路径上。
    @Published var createdOrder: OrderResponse?

    weak var bookingViewModel: BlindBookingViewModel?
    weak var speechService: SpeechService?
    weak var speechInputService: SpeechInputService?
    var voiceOrderService: (any VoiceOrderServing)?
    var currentCoordinate: (() -> LocatedCoordinate?)?
    var parseTask: Task<Void, Never>?
    /// 下一次读回前要先说的一句话（目前只有时长取整）。拼进读回而不是单独播一次，见 `moveToConfirm`。
    var pendingNotice: String?
    /// 当前这一句最晚等到什么时候就强行开麦。由 `speak(_:)` 按字数定，见 `settleTimeout(forCharacterCount:)`。
    var speechSettleDeadline: Date?
    /// 本轮语音**真的抽到了**开始时间。
    ///
    /// 必须与 `bookingViewModel.appointmentTime` 分开记：那个字段的初值是 `Date()`，
    /// 光看它分不出「用户说了个正好是现在的时间」和「压根没抽出来」。而这两者对盲人是天壤之别 ——
    /// 一个是他说的，另一个是系统编的。
    @Published var didCaptureStartTime = false
    /// 连续多少轮没拿到开始时间。到上限就交回表单，见 `moveToConfirm`。
    var roundsWithoutStartTime = 0
    /// 最近一次解析失败是「这个接口根本不存在」，而不是「没听懂你说什么」。
    ///
    /// 这两者对用户的**下一步动作完全不同**：前者重说多少遍都不会变好，后者值得再说一次。
    /// 后端把未部署的端点回成带 `NOT_FOUND` 的业务信封（`/api/orders/voice/parse` 生产上
    /// 就是这个状态，见 handoff 2026-08-06），所以客户端分得出来 —— 分得出来就不该混为一谈。
    var parseIsUnavailable = false
    /// 上一次解析的完整结果，确认轮回传给后端当 `current`（跨轮修正的全部前提）。
    ///
    /// **只从响应赋值**，理由见 `ParseVoiceOrderResponse.slotSnapshot`。
    /// `nil` 时确认轮照样发 `/parse`，只是不带 `current` —— 后端行为退回老客户端那一档，
    /// 意图判定仍然可用（`userIntent` 的正则兜底不依赖 `current`）。
    var lastParsed: ParseVoiceOrderResponse?
    /// 最近一次读回念到的起点（只认 id：设备位置的 id 固定，GPS 漂移不算换了起点）。见 `confirmBooking`。
    var readBackStartPlaceID: String?

    /// 连着这么多轮拿不到开始时间就不再让人重说。取 2：给一次重说的机会，不给第二次。
    static let maximumRoundsWithoutStartTime = 2

    enum WizardError: Error { case parseTimedOut, notConfigured }

    // MARK: Wiring

    /// - Parameter currentCoordinate: 当前位置，用于给 `resolve-address` 做就近消歧。
    ///   必须是**后端坐标系（GCJ-02）**的真实采样 —— 传 `LocationService.latestBackendSample()`，
    ///   它在没有真实定位时返回 nil，正好等于「不带这两个字段」。
    func configure(
        bookingViewModel: BlindBookingViewModel,
        speechService: SpeechService,
        speechInputService: SpeechInputService,
        voiceOrderService: any VoiceOrderServing,
        currentCoordinate: (() -> LocatedCoordinate?)? = nil
    ) {
        self.bookingViewModel = bookingViewModel
        self.speechService = speechService
        self.speechInputService = speechInputService
        self.voiceOrderService = voiceOrderService
        self.currentCoordinate = currentCoordinate
    }

    // MARK: Lifecycle

    /// 从「约跑前还差 N 项」补完回到约跑页时调用（#781）。`start()` 被紧急联系人拦下时
    /// 留在屏幕顶上的那句改成还差的下一项，都齐了就撤掉。别的降级原因（语音坏了等）不动。
    /// 不开麦：回来的人可能已经改用表单，要语音就自己按「用语音重新说一次」。
    func refreshSetupGateFallback() {
        guard let current = fallbackMessage, BlindBookingGate.isSetupMessage(current) else { return }
        let gate = bookingViewModel?.firstMissingGate
        fallbackMessage = gate.flatMap { BlindBookingGate.setupGates.contains($0) ? $0.message : nil }
    }

    /// 起步前先跑一遍下单硬门槛。让盲人说完一整句才被服务端 403 拒掉是最坏的顺序 ——
    /// 门槛的唯一真源是 `OrderCreationService.createOrder`，客户端这份只是把同样的顺序提前。
    /// 返回 `false` 表示没有启动，调用方按 `fallbackMessage` 引导用户去补前置项。
    @discardableResult
    func start() -> Bool {
        guard let bookingViewModel else { return false }
        if let gate = bookingViewModel.firstMissingGate, gate != .startPoint, gate != .appointmentTime {
            // 同 `fallBack`：从结束态重开时门槛已失效，要真的换到表单去补前置项。
            endedMessage = nil
            endedAfterFailure = false
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
        endedMessage = nil
        endedAfterFailure = false
        lastEmptyCompletionWasStartFailure = false
        createdOrder = nil
        lastUtterance = nil
        partialTranscript = ""
        didCaptureStartTime = false
        roundsWithoutStartTime = 0
        parseIsUnavailable = false
        lastParsed = nil
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
        // 结束态下按「改用表单」也走这里：清掉它，界面才会真的换成表单。
        endedMessage = nil
        endedAfterFailure = false
    }

    /// 重复当前这一轮的问题。语音消失得快，重听是基本诉求。
    ///
    /// **录音中按它要先停麦再念，念完再重新开麦**（#558 走查卡死 1）。以前直接 `speak`、麦克风照开，
    /// 合成器从扬声器念出的提示会被录进转写 —— 整句轮的提示里有示例句「明天早上八点从人民广场出发」，
    /// 最坏会读回一张用户没说过的单。停麦用 `cancelRecognitionForLifecycle`（不发完成回调）：
    /// 走 `stopRecognition` 会触发一次空转录的 `handle`，被记成一次「没听清」重问。
    func repeatCurrentPrompt() {
        let wasListening = speechInputService?.isListening == true
        if wasListening {
            speechInputService?.cancelRecognitionForLifecycle()
        }
        speak(lastSpokenPrompt ?? step.prompt)
        if wasListening, isRunning, let field = step.speechField {
            listen(for: field)
        }
    }

    #if DEBUG
    /// 只挂 view model，不碰麦克风、网络和 TTS。
    ///
    /// 落槽位那一段（`apply`）不依赖其余三个依赖，而 `configure` 要求四个一起给 ——
    /// 为了验一条赋值规则去造 `SpeechInputService` 是在给测试引入麦克风授权这种真实前置。
    /// ⚠️ `bookingViewModel` 是 `weak`：调用方必须自己持有传进来的那个对象。
    func configureForTesting(bookingViewModel: BlindBookingViewModel) {
        self.bookingViewModel = bookingViewModel
    }

    /// 把一次解析结果直接落进去，跳过网络。
    /// 备注的「是不是用户原话」判定要看 `transcript`，所以它必须由用例给。
    @discardableResult
    func applyForTesting(_ parsed: ParseVoiceOrderResponse, spokenIn transcript: String) -> String? {
        apply(parsed, spokenIn: transcript)
    }

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
        endedMessage = nil
        endedAfterFailure = false
        self.didCaptureStartTime = didCaptureStartTime
        readBackStartPlaceID = bookingViewModel?.resolvedStartPlace?.id // 当作用户已听过当前起点
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

    /// 播报用的序数词，下标即候选下标。与后端 `VoiceOrderService.ORDINALS` 同一套写法。
    static let ordinalWords = ["第一个", "第二个", "第三个"]

    /// ⚠️ 外层顺序即判定优先级，别按字典序重排：「第二个」不含任何 index 0 的写法，
    /// 所以从前往后扫是安全的；但把「第一」放到「第二个」后面就会先命中错的那条。
    static let ordinalForms: [[String]] = [
        ["第一个", "第1个", "第一", "第1", "头一个"],
        ["第二个", "第2个", "第二", "第2"],
        ["第三个", "第3个", "第三", "第3"]
    ]

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
    ///
    /// **2026-08-10 删掉「开始约跑」**：本地直通表必须是后端确定性兜底
    /// （`VoiceSlotParser.INTENT_CONFIRM`）的子集，而后端那条正则里没有任何模式能命中它
    /// （最接近的是「开始吧」）。它也从来没被 `confirmPrompt` 教给用户，删掉零损失。
    static let affirmatives: Set<String> = [
        "确认", "确认下单", "确认预约", "确认提交",
        "没问题", "就这样", "就这么办"
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
    ///
    /// 🔴 **2026-08-10 把「再说一次」移出本组**，它现在归 `repeatWords`。
    /// 逐词对撞后端 `VoiceSlotParser` 时查出这是一处**方向相反**的判定分歧：本地判「重说」会把
    /// 用户刚说完的一整句清空，后端 `INTENT_REPEAT` 判的是「你把刚才那句再念一遍」。
    /// 后端 `INTENT_RESTART` 的注释写得很直白 ——「刻意不收『再说一遍』」，因为判错的代价不对称。
    /// 这一条现在由 `scripts/validate-voice-intent-words.mjs` 钉住，再漂就红。
    static let restartWords: [String] = [
        "重说", "重新说", "从新说", "重新讲", "重来", "重新来", "从头说", "从头再说", "从头来",
        "重新预约", "重新说一遍", "重新来过"
    ]

    /// 「把刚才那段再念给我听」。**注意与 `restartWords` 的语义分界**：
    /// 这一组是「你再念一遍」，那一组是「我再说一遍」。
    ///
    /// 「再说一遍 / 再说一次」中文里两种意思都有。**2026-08-10 从「重说」改判到本组**，
    /// 依据是后端 `VoiceSlotParser.INTENT_REPEAT` 把它们收进了重播，而 `INTENT_RESTART`
    /// 注释里明说「刻意不收」。判反的代价不对称：当成重说会把用户刚说完的一整句清空，
    /// 当成重播最坏只是多念一遍 —— 而这一句正是盲人没听清读回时最自然的说法。
    ///
    /// 长句形式（「再给我念一遍呗」「你刚才说啥来着」）不进本表，交给后端 —— 本地整串表
    /// 接不住方言与长句，那正是第 2 档存在的理由。
    static let repeatWords: Set<String> = [
        "重复", "重复一遍", "再念一遍", "没听清", "再念一次", "你再说一遍",
        "再说一遍", "再说一次"
    ]

    /// 「放弃这一单」。**整串匹配，不做包含** —— 与 `affirmatives` 同口径。
    ///
    /// 「把导盲犬取消」是改一项，不是取消整单；包含匹配会让用户的整单凭空消失
    /// （后端 `VoiceSlotParser.INTENT_CANCEL` 的注释专门讲过，光秃秃的「取消」只在整句就是它时才算）。
    /// 带订单级宾语的长句（「算了，今天不跑了」）本地不接，交后端 `userIntent == CANCEL`。
    ///
    /// ⚠️ **这里写口语原样，查表时两边都过 `normalizedCommand`**：句尾的「了」「吧」会被剥掉，
    /// 「算了」归一化后是「算」。直接拿归一化后的串去对原样词表，「算了」「不下了」「不要了」
    /// 一个都命中不了。原样写在这里是因为 `scripts/validate-voice-intent-words.mjs` 要拿它逐词
    /// 对撞后端的 `INTENT_CANCEL`，本地不得认后端不判成 CANCEL 的词。
    private static let cancelWords: Set<String> = [
        "算了", "不下单", "不下了", "不订了", "不跑了", "不要了", "取消", "取消吧", "放弃"
    ]
    static let normalizedCancelWords = Set(cancelWords.map(normalizedCommand))

    // MARK: Helpers

    // `durationOption(forMinutes:)`（就近 snap 到 6 个枚举档位）已于 2026-08-06 删除。
    // 语音说多少就是多少，只夹到契约区间，见 `acceptedDurationMinutes(_:)`。
}
