import Foundation

// MARK: - 接单前通话磨合（后端迁移 `0031`）

/// `GET /api/orders/{id}/intro-call` 的响应。
///
/// 🚨 **同一个端点对两种角色返回不同内容，号码是单向的**（后端 `IntroCallView` 的 schema 注释）：
/// - 盲人侧：`counterpartPhone` 是志愿者**能直接拨通的明文号**，`counterpartPhoneMasked` 为 null
/// - 志愿者侧：`counterpartPhone` **恒为 null**，只给 `counterpartPhoneMasked`
///
/// 为什么单向：接单前通话会把号码下发面从「1 个已接单的人」放大到「N 个候选人」，
/// 聊崩 3 次就是 3 个陌生人永久持有对方号码。泄露方向收敛到已实名、已过活体认证的志愿者一侧。
///
/// 🚨 **响应体刻意不含对方的表态、也不含轮次进度**——这不是后端漏了字段。「无声拒绝」要求
/// 任何一方都不知道自己是否被对方拒绝过；「这是第 3 位志愿者」本身就是在告诉盲人前两位没成。
/// 所以客户端也**不许自己算**轮次再显示出来（例如按 `INTRO_CALL_CONTINUE` 收到几次来计数）。
/// 依据：CHI'24 *Help Supporters*（N=20）—— 平台方案降低视障者求助心理成本的机制，
/// 正是明眼人可以 silently decline。
nonisolated struct IntroCallView: Decodable, Sendable, Equatable {
    /// 对方姓名，**双向都掩码**（`张*`）。与电话是两套相反的规则 —— 姓名没有「拨得通」这回事。
    let counterpartName: String?

    /// 对方能直接拨通的**明文号**，**仅盲人侧有值**。
    ///
    /// 与 `OrderDetailResponse.volunteerPhone` 同一条硬不变量：要么明文可拨、要么 null，
    /// 后端**绝不下发掩码串**到这个字段。
    let counterpartPhone: String?

    /// 对方号码的掩码串，**仅志愿者侧有值**，用途只有一个：**认人**（他会接到陌生号码来电）。
    ///
    /// 🚨 **绝不能拿它去拼 `tel:`。** 它是展示字段不是拨号字段：`EmergencyDialer.telURL`
    /// 只取数字位，`138****1234` 会被拨成 `1381234` —— 打成空号，而界面上看不出任何异常。
    /// 这条在本仓库 2026-08-11 报过一次真实缺陷。
    /// 类型上没法拦（两个都是 `String?`），所以拨号入口只认 `dialableCounterpartPhone`。
    let counterpartPhoneMasked: String?

    /// **我自己**的表态，`nil` = 还没表态。**只有自己的，没有对方的**（见类型注释）。
    ///
    /// 解成 `String` 而不是枚举：契约里它是开放枚举（`anyOf: [enum, string]`），
    /// 后端加值时不许把整条响应带崩 —— 与 `RunOrderStatus.unknown` 同一条红线。
    let myDecision: String?

    /// 本轮通话窗口的结束时刻（ISO-8601）。到点双方仍未表完态则本轮作废，换下一个候选人。
    let windowEndsAt: String?

    /// 起跑点文字地址。**双方角色都给** —— 契约逐字：「它是『这一单的信息』不是『对方的信息』」，
    /// 与 `NEW_ORDER` 推送的 `startAddress` 同源，暴露面为零。
    ///
    /// 🚨 **它存在的理由就是冷启动恢复**：志愿者在这一态读不到订单详情
    /// （`order.volunteer` 还是 null ⇒ `GET /api/orders/{id}` 恒 403），杀掉 App 再打开时
    /// 派单推送已经没了 —— 没有这个字段，恢复出来的通话页只有一个号码和三个按钮，
    /// 志愿者无从判断这一单要不要接。
    let startAddress: String?

    /// 计划开始时间。形状是 ISO-8601（`format: date-time`），与 `windowEndsAt` 同档，
    /// 展示走 `String.displayDateTime` —— 它对「无偏移的 LocalDateTime」和「带偏移的 ISO-8601」
    /// 都认（`backendTimestamp` 三种形状依次试），所以与派单推送那条 `plannedStart`
    /// 虽然契约形状不同，展示路径是同一条。
    let plannedStartTime: String?

    /// 计划结束时间。
    ///
    /// ⚠️ 契约在这个字段上钉了一条边界，别越过：**不要往这个 DTO 里加自由文本**
    /// （`specialNotes` / `routeNotes`）—— 通话发生在接单前，`AGENTS.md §8` 那条不变。
    let plannedEndTime: String?

    /// 唯一允许拼 `tel:` 的来源。掩码串永远进不来 —— 它在另一个字段上。
    var dialableCounterpartPhone: String? {
        counterpartPhone?.nilIfBlank
    }

    /// 对方称呼。后端两侧都掩码，直接用；没有就退回中性称呼，不留空。
    func counterpartDisplayName(fallback: String) -> String {
        counterpartName?.nilIfBlank ?? fallback
    }

    var myDecisionValue: IntroCallDecision? {
        myDecision?.nilIfBlank.flatMap(IntroCallDecision.init(rawValue:))
    }

    /// 我已经说过「合适」，正在等对方。**注意这不代表对方还没表态** ——
    /// 我们拿不到、也不该拿到那个信息。
    var isWaitingForCounterpart: Bool {
        myDecisionValue == .accept
    }
}

/// 通话后的表态。⚠️ **刻意没有 reason 字段** —— 拒绝不需要给理由，系统也不记录理由。
/// 要求填理由等于要求当面说「不」，而这个功能存在的意义正是让拒绝可以是无声的。
///
/// 请求向的枚举保持**闭合**（客户端只发已知值），与响应向的开放枚举规则相反。
nonisolated enum IntroCallDecision: String, Codable, Sendable {
    case accept = "ACCEPT"
    case decline = "DECLINE"
}

nonisolated struct IntroCallDecisionRequest: Codable, Sendable {
    let decision: IntroCallDecision
}

/// 通话磨合的四条端点。
///
/// 写成枚举 + 字面量路径，理由与 `KeepWaitingEndpoint` 完全相同：
/// `scripts/validate-spec-coverage.mjs` 扫的是源码里的路径**字符串字面量**，
/// 把后缀拼成变量会让这几条端点对门禁彻底隐形 —— 而门禁存在的全部意义
/// 就是拦住「前端在调后端没有的路径」。
///
/// 角色不对称是后端定的，不是这里的实现选择：
/// - `unreachable` **仅志愿者**：盲人侧「聊完不合适」与「没打通」结果完全一样（换一位），
///   分成两个按钮只是多一次读屏滑动。后端确实要区分（没接到计 timeout、主动拒绝计 declined，
///   直接进派单评分的 `acceptanceRate`），这个口径由志愿者侧提供。
/// - `notifyIncoming` **仅盲人**：拨号前给志愿者推一条 HIGH 通知，免得陌生号码被当骚扰挂掉。
enum IntroCallEndpoint {
    case view
    case decision
    case unreachable
    case notifyIncoming

    func request(orderId: Int64) -> EndpointRequest {
        switch self {
        case .view:
            return EndpointRequest(.get, "/api/orders/\(orderId)/intro-call")
        case .decision:
            return EndpointRequest(.post, "/api/orders/\(orderId)/intro-call/decision")
        case .unreachable:
            return EndpointRequest(.post, "/api/orders/\(orderId)/intro-call/unreachable")
        case .notifyIncoming:
            return EndpointRequest(.post, "/api/orders/\(orderId)/intro-call/notify-incoming")
        }
    }

    /// 盲人侧那三个调用点还在直接拼路径打 `apiClient`（`BlindOrderStatusView`），
    /// 随订单片一起迁；迁完这个方法就没有调用点了，当场删。
    func path(orderId: Int64) -> String {
        request(orderId: orderId).path
    }
}

// MARK: - 文案

/// 通话磨合的全部对外文案。集中一处是为了让它们能被测试逐条钉住 ——
/// 这里每一句的措辞都有约束（见下面每条的注释），散在 view 里就只能靠人记。
enum IntroCallCopy {

    // MARK: 盲人侧

    static let callButtonTitle = "打电话给这位志愿者"
    static let callAgainButtonTitle = "再打一次"

    /// 🚨 **hint 里不许出现号码。**
    ///
    /// 沿用 `BlindOrderStatusView.volunteerCallSection` 已有的教训：VoiceOver 每次焦点落到按钮上
    /// 就会把这句话念出来，而视障跑者在户外常常**不戴耳机**（要听车流）——
    /// 外放等于把志愿者的手机号广播给周围的人。号码对「要不要打这通电话」这个决策没有帮助，
    /// 唯一有用的信息是「会先弹确认」。
    static let callAccessibilityHint = "系统会先弹出拨号确认，确认后才会拨出"

    static let acceptButtonTitle = "聊过了，合适"
    static let acceptAccessibilityHint = "告诉系统你觉得这位志愿者合适。双方都说合适才算约好"

    /// 盲人侧的「不合适」。
    ///
    /// 措辞是「换一位」而不是「拒绝这位志愿者」：后者把一次退出说成一次否定他人，
    /// 而这个功能的全部意义就是让退出不带评判。
    static let declineButtonTitle = "换一位"
    static let declineAccessibilityHint = "结束这次通话确认，系统继续为你寻找陪跑伙伴"

    /// 我已表态、等对方时的进行时文案。
    ///
    /// 🚨 **不许说「对方还没回复」「正在等志愿者确认」**——那等于告诉盲人对方看过了还没答应，
    /// 把压力转嫁回来。而且我们**根本拿不到**对方的表态（响应体里没有）。
    static let waitingForCounterpart = "已经告诉系统你觉得合适，约好之后会通知你。"

    /// 本轮没聊成、退回派单队列时的播报。
    ///
    /// 🚨 逐字取后端 `INTRO_CALL_CONTINUE` 模板正文，与常规等待**读起来完全一样**：
    /// 不许出现「重新」「换一位」「再找一位」这类暗示前面失败过的措辞。
    ///
    /// 存在的理由是 `.pendingMatch` 的常规播报是「订单提交成功，系统正在为你派单」——
    /// 订单是二十分钟前提交的，那句话在这一刻是**错的**。
    static let continuedSearch = "正在为你寻找合适的陪跑伙伴。"

    static func blindCallSectionAnnouncement(counterpartName: String) -> String {
        "\(counterpartName)想陪你跑。先打个电话聊聊，双方都觉得合适就算约好了。"
    }

    // MARK: 盲人侧独立通话页

    /// 订单状态页上那个「进通话页」的按钮。
    ///
    /// 🚨 **不许与 `callButtonTitle`（「打电话给这位志愿者」）用同一句话。** 那个按钮按下去
    /// 立刻弹系统拨号确认，这个只是打开一个页面 —— 对看不见屏幕的人，两件事听起来一样
    /// 就等于随时可能误拨。所以措辞落在「确认」而不是「打电话」上，hint 里再说一遍
    /// 「打开一个页面」。
    static let blindEntryButtonTitle = "和这位志愿者通话确认"
    static let blindEntryAccessibilityHint = "打开通话确认页，在那里拨号并告诉系统合不合适"

    /// 阶段 A 的页面标题。与 `blindCallSectionAnnouncement` 拆成标题 + 副标题两截，
    /// 不是新写一套措辞：整屏只有一件事时，「谁」和「要做什么」该是两个 VoiceOver 焦点，
    /// 用户滑一下就能跳过已经听过的那半句直接到按钮。
    static func blindPageTitle(counterpartName: String) -> String {
        "\(counterpartName)想陪你跑"
    }

    static let blindPageSubtitle = "先打个电话聊聊，双方都觉得合适就算约好了。"

    /// 阶段 B（拨号返回后）的标题。
    ///
    /// 🚩 措辞是**开放式提问**而不是「请确认是否合适」：后者预设了「该说合适」，
    /// 而这一屏的两个出口是平权的 —— 说「换一位」不需要理由，也不该显得像是拒绝了谁。
    static func blindAfterCallTitle(counterpartName: String) -> String {
        "和\(counterpartName)聊得怎么样"
    }

    static let blindAfterCallSubtitle = "双方都说合适才算约好。"

    /// 通话数据还没拉回来时整屏该显示的那句。
    ///
    /// 🚨 这一句是**独立页才需要**的：内嵌 section 时这个状态渲染成空视图没有代价
    /// （页面上还有状态卡和别的内容），而一个整屏空白的页面对读屏用户等同于死机 ——
    /// 他滑不到任何东西，也无从判断是没加载完还是 App 挂了。
    static let blindLoadingNotice = "正在获取这位志愿者的通话信息"

    /// 退回订单页。**不叫「关闭」** —— 盲人需要知道退回去之后到哪儿，
    /// 而不是知道这个动作会让当前这块东西消失。
    static let blindCloseButtonTitle = "返回订单"
    static let blindCloseAccessibilityHint = "回到订单状态页。这通电话还可以再进来打"

    static let blindStartAddressPrefix = "出发地"
    static let blindPlannedTimePrefix = "时间"

    /// 本轮通话窗口还剩多久。
    ///
    /// 🚨 **只讲这一轮的剩余时间，不讲轮次。** 「还剩 18 分钟」与「这是第几位候选人」
    /// 无关，所以它不触碰无声拒绝那条红线；但也正因如此，**不许**由它派生出任何
    /// 「已经聊过 N 位」的展示。
    ///
    /// 三种情况一律返回 nil（不显示这一行），而不是显示一个说不出内容的占位：
    /// - `windowEndsAt` 解析不出来（后端形状变了，或字段本来就是 optional）
    /// - 已经过期。窗口到点后订单转走有延迟，这中间客户端**不替后端宣布结果** ——
    ///   显示「已超时」而后端还在等表态，会让用户以为白打了一通电话。
    /// - 不足 1 分钟。「还剩 0 分钟」既是噪音，又是在催一个正在打电话的人。
    ///
    /// 口径与 `blindRunnerWaitedText` 一致：算不出来就不说这一行，不猜。
    static func blindWindowRemainingText(windowEndsAt: String?, now: Date = Date()) -> String? {
        guard let endsAt = windowEndsAt?.nilIfBlank?.backendTimestamp else { return nil }
        let minutes = Int(endsAt.timeIntervalSince(now) / 60)
        guard minutes >= 1 else { return nil }
        return "这一轮通话还剩 \(minutes) 分钟"
    }

    // MARK: 志愿者侧

    static let volunteerAcceptButtonTitle = "合适，接这一单"
    static let volunteerDeclineButtonTitle = "不合适"

    /// 🚩 **「一直没接到电话」只在志愿者侧**，这处不对称是刻意的（见 `IntroCallEndpoint`）。
    static let volunteerUnreachableButtonTitle = "一直没接到电话"
    static let volunteerUnreachableAccessibilityHint = "告诉系统这通电话没有打通，系统会把这一单派给下一位"

    /// 志愿者侧对号码的唯一说明。**掩码串只用于认人，不是拨号入口。**
    static let volunteerPhoneHint = "跑者会用这个号码打给你，请留意来电"

    /// 本轮结束、但这一单不是你的。中性、不归因 —— 志愿者同样不该被告知自己被拒了。
    static let volunteerRoundClosed = "这一单已经安排好了，感谢你的响应。"

    static let volunteerMatched = "已约好，这一单是你的。"

    // MARK: 两侧共用

    /// 409 `INTRO_CALL_NOT_ACTIVE`。最常见成因不是乱调，而是**窗口超时后客户端才发上来**，
    /// 所以要说清「这一轮已经结束」，不能说成「操作失败」。
    static let roundAlreadyEnded = "这一轮通话已经结束了。"

    /// 通话数据拉不到时**看得见也听得到**的那句。
    ///
    /// 🚩 措辞不许说成「打不通」「对方不在」—— 失败的是我们这次取号码的请求，
    /// 而志愿者那边一切正常。说错方向会让盲人以为该换人，而他只需要重试一下。
    static let loadFailed = "暂时拿不到通话信息，请稍后重试。"

    static let retryButtonTitle = "重新加载"
    static let retryAccessibilityHint = "再取一次这位志愿者的通话信息"
}
