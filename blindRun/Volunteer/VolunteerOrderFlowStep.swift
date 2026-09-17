import Foundation

// MARK: - 四步骨架（陪跑员端）

/// 设计交付文档 v3 §5 的四步：邀请 → 约好 → 出发 → 汇合。
///
/// 与跑者端的「匹配 → 约好 → 出发 → 汇合」**一一对应**，只有第 1 步文案不同：
/// 同一件事在盲人那头叫「系统在给我找人」，在陪跑员这头叫「系统在问我去不去」。
/// 所以进度条组件（`FlowStepper`）共用、标题各给一份。
///
/// **它不是订单状态的别名。** 后端 11 个状态（客户端 12 个，含 `.unknown`），这一屏只有 4 格。
enum VolunteerOrderFlowStep: Int, CaseIterable, Equatable {
    case invited = 0
    case booked = 1
    case departed = 2
    case metUp = 3

    var title: String {
        switch self {
        case .invited: return "邀请"
        case .booked: return "约好"
        case .departed: return "出发"
        case .metUp: return "汇合"
        }
    }

    static var allTitles: [String] { allCases.map(\.title) }
}

extension RunOrderStatus {
    /// 这一态落在陪跑员端四步骨架的哪一格。`nil` = **不走这个骨架**。
    ///
    /// 穷举 switch 而不是集合字面量：集合会把后端新加的状态默默判成 `nil`，
    /// 而那表现为「订单页整屏空白」——志愿者看不到任何可做的事，而盲人正在等他。
    ///
    /// 🚩 `PENDING_INTRO_CALL` 归**邀请**格。通话磨合在设计稿的四步里不存在，但它是后端
    /// 强制状态（迁移 `0031`）：这一态 `order.volunteer` 仍为 null，志愿者**还没接单** ——
    /// 放进「约好」格会告诉他一件没发生的事。项目负责人 2026-09-17 拍板：
    /// 藏在「邀请」这一步内部，按钮统一叫「接下这次陪跑」，
    /// 发 `ACCEPT` 还是 `INTERESTED` 只认推送里的 `requiresIntroCall`（客户端不许自己算）。
    ///
    /// `PENDING_MATCH` / `REMATCHING` 同格：对这位志愿者，这两态的事实都是「这一单还没轮到我
    /// 或已经不是我的了」，屏幕上他能做的只有回应一次邀请。
    var volunteerOrderFlowStep: VolunteerOrderFlowStep? {
        switch self {
        case .pendingMatch, .pendingIntroCall, .rematching:
            return .invited
        // 两态同格，但**主按钮不同**：`SCHEDULED_CONFIRMED` 要先回答「你还去吗」
        // （`confirm-departure`），`PENDING_ACCEPT` 才是「我出发了」（`en-route`）。
        // 后端刻意把这两件事分开（`AGENTS.md` §5：合并会让位置互推提前几小时打开），
        // 所以按钮不能按格子发 —— 见 `VolunteerOrderFlowPresentation.primaryAction`。
        case .scheduledConfirmed, .pendingAccept:
            return .booked
        case .driverEnRoute:
            return .departed
        case .driverArrived, .inProgress:
            return .metUp
        case .completed, .cancelled, .noVolunteer:
            return nil
        // 认不出的状态**不落进任何一格**。把未知态画成「邀请」会让志愿者以为有单要接。
        case .unknown:
            return nil
        }
    }
}

// MARK: - 文案

/// 陪跑员端订单页那几句话。**视图里不写中文字面量** ——
/// 同一句话散在视图与用例两处必然漂开，而「按钮上的字改了而断言没改」在屏幕上没有症状。
enum VolunteerOrderFlowCopy {
    static let pageTitle = "陪跑订单"

    // 主按钮。逐字取自设计交付文档 v3 §5 的「陪跑员主按钮」列。
    static let acceptInvite = "接下这次陪跑"
    static let confirmDeparture = "确认我还会去"
    static let enRoute = "我出发了"
    static let arrived = "我已到达集合点"

    /// 「这次去不了」（邀请态）与「我去不了」（已接单三态）。
    ///
    /// 🔴 已接单那三态刻意**不叫「取消订单」**：对志愿者那读起来像在替盲人取消这一单，
    /// 而实际后果是「这一单回到派单池换个人」。设计稿写的是「修改或取消」，
    /// 但后端**没有任何改单端点**（`/api/orders` 下 `put`/`patch` 命中 0）——
    /// 「修改」这个词承诺了一个不存在的功能，所以只留「去不了」这一半。
    static let declineInvite = "这次去不了"
    static let releaseOrder = "我去不了"

    // 信息行标签。
    static let runnerLabel = "跑者"
    static let plannedDistanceLabel = "跑多远"
    static let paceLabel = "配速"
    static let phoneLabel = "电话"
    /// 拨号那一行的读屏标签。**不带号码**，理由见 `phoneRow`。
    static let callRunner = "拨打跑者电话"
    static let meetingPointLabel = "集合点"
    static let navigateLabel = "导航去集合点"
    static let routeNotesLabel = "路线备注"
    static let specialNotesLabel = "特殊说明"

    static let unknownRunnerName = "这位跑者"
    static let meetingPointUnknown = "出发地点待确认"

    // hero。
    static let inviteTitleFallback = "新的陪跑邀请"
    static let bookedSubtitle = "已约好"
    /// 🚨 **不写「距开跑还有 X 小时要确认」**：那个提前量是后端配置
    /// （`app.order.departure-confirm-window-minutes`），客户端读不到，写死就是编一个数字。
    /// 只说清后果 —— 那才是他真正需要知道的。
    static let scheduledSubtitle = "已约好。出发前请确认你还会去，没有确认这一单会转给其他志愿者"
    /// ⚠️ 设计稿这里是「8 分钟后到」。**做不出来** —— 全仓与后端契约都没有 ETA
    /// （出发地、交通方式、`etaMinutes` 在 `api_spec.yaml` 与 `websocket-protocol.md` 命中 0）。
    /// 编一个到达时间给正在集合点等人的盲人，比不给更糟。距离进副标题。已投 handoff。
    static let departedTitle = "正在前往集合点"

    static func distanceToStart(kilometers: Double) -> String {
        String(format: "离你约 %.1f 公里", kilometers)
    }

    /// 「还剩 25 秒回复」。
    ///
    /// ⚠️ 设计稿写的是「请在今晚 22:00 前回复」（距开始 >24 小时给 1 小时，否则 15 分钟）。
    /// **后端没有这个期限**：派单是串行瞬时推送 + `dispatchTimeoutSeconds`（默认 30 秒）
    /// 超时自动转下一位。写一个不存在的绝对时间，志愿者会以为还能慢慢想，
    /// 而这一单已经推给下一个人了。已投 handoff。
    static func replyCountdown(seconds: Int) -> String { "还剩 \(max(seconds, 0)) 秒回复" }

    /// 倒计时转「紧迫」的阈值。同时决定颜色和那个感叹号 —— 两处各写一个 10，
    /// 改一处漏一处的表现是「图标出现了但字还是蓝的」。
    static let urgentCountdownSeconds = 10

    /// 「我去不了」那道二次确认的四句话。
    ///
    /// 🔴 **必须与按钮上的词一致。** 对志愿者「取消订单」读起来像在替盲人取消这一单，
    /// 而实际后果是「这一单回到派单池换个人」。按钮上换成「去不了」、对话框里还写
    /// 「确认取消本次预约？」的话，那次改名等于没做 —— **而对话框才是他真正下决心的那一屏**。
    ///
    /// 抽成静态函数而不是留在 View 的 private 计算属性里：它在那里**测试够不着**，
    /// 于是 `ScheduledOrderTests.testReleaseAndCancelDoNotShareCopy` 曾经绿着、
    /// 而对话框里还写着旧词（那条用例的注释逐字记着这个洞）。
    ///
    /// 走骨架的三态（`SCHEDULED_CONFIRMED` / `PENDING_ACCEPT` / `DRIVER_EN_ROUTE`）都用
    /// 「去不了」：这三态志愿者退出的后果完全相同 —— 转 `REMATCHING`，换个人。
    /// 汇合与跑步中仍走旧面板的「取消订单」，那两态搬过来时一并收口。
    ///
    /// 返回元组而不是在 `confirmationDialog` 里写四个三元表达式：那样写会把 SwiftUI 的
    /// 类型检查器拖到超时。
    static func cancelDialog(
        for status: RunOrderStatus?
    ) -> (title: String, confirm: String, dismiss: String, message: String) {
        switch status {
        case .scheduledConfirmed, .pendingAccept, .driverEnRoute:
            return (
                "确认去不了？",
                "确认去不了",
                "再想想",
                "这一单会转给其他志愿者，之后不一定还能接回来。"
            )
        default:
            return ("取消订单", "确认取消", "不取消", "确认取消本次预约？")
        }
    }
}

// MARK: - 一屏的全部可渲染内容

/// 陪跑员端订单页前三态那一屏要显示的东西，**全部**。
///
/// 做成纯值类型而不是散在视图里的一堆 `if`，理由与跑者端 `BlindOrderFlowPresentation` 同源，
/// 第三条最重要：
///
/// 1. 视图只按它渲染，不再自己判状态 —— 骨架固定的前提是内容由一处算出来；
/// 2. 它能被单测穷举（`VolunteerOrderFlowPresentationTests`）；
/// 3. 🔴 **这一屏的错误形态全是静默的**：文案说错一态、按钮在不该出现的态出现、
///    接单前漏出盲人的自由文本 —— 屏幕上都不会报错。
struct VolunteerOrderFlowPresentation: Equatable {
    let step: VolunteerOrderFlowStep
    let visual: Visual
    /// 那行大字。
    let title: String
    /// 状态副标题。可能是空串。
    let subtitle: String
    /// 回复期限那一行。**只有邀请态有**，而且**刻意不并进 `subtitle`** ——
    /// 它每秒都在变，并进去会让状态卡那个合成的无障碍元素每秒重念一遍。
    let replyNotice: String?
    /// 剩余不足 `urgentCountdownSeconds`。视图据此换色并补一个感叹号形状
    /// （「不使用颜色区分」开启时，只靠蓝变红的转折红绿色觉障碍看不出来）。
    let isReplyUrgent: Bool
    let rows: [Row]
    /// 底部那枚黄按钮。`nil` = 这一态没有主动作。
    let primaryAction: PrimaryAction?
    /// 底部要不要给「求助与安全」。
    ///
    /// 🔴 **前三态一律 `false`，这是产品决策不是遗漏。** 设计稿在「约好」「出发」两屏底部
    /// 都画了它，但陪跑员端没有安全中心（`BlindSafetyHubView` 是盲人专用的：紧急联系人、
    /// 问一句、实时分享），而这三态的云端 SOS 本来就关着（`AGENTS.md` §6：
    /// 两端入口都只在 `IN_PROGRESS` 开放）。摆一个按下去无事发生的紧急入口比没有更糟。
    /// 项目负责人 2026-09-17 拍板单独立项。
    let showsSafetyHub: Bool

    enum Visual: Equatable {
        /// 头像。拿不到姓名时圆里是「跑」。
        case avatar
        /// 头像 + 外圈进度环（出发态）。
        case avatarWithProgressRing
    }

    /// 信息卡里的一行。
    ///
    /// 做成值而不是让视图自己拼：**接单前该不该出现某一行**是这一屏唯一会造成隐私事故的判断，
    /// 而它在视图里是一个 `if`，在这里是一条可以被用例钉住的断言。
    struct Row: Equatable, Identifiable {
        let id: String
        /// `nil` = 整行只有一个值（「我去不了」这类动作行）。
        let label: String?
        let value: String
        /// 值下面那行小字。
        let detail: String?
        let action: Action?
        /// 读屏文本。掩码姓名在这里**去掉星号**（`张*` → 「张」），屏幕上仍显示星号。
        let accessibilityLabel: String
        let accessibilityHint: String?

        var isTappable: Bool { action != nil }
    }

    /// 行点下去做什么。视图不认识业务，只把这个值回调出去。
    enum Action: Equatable {
        /// 打开集合点。**「约好」的「集合点 ›」和「出发」的「导航去集合点 ›」是同一个动作** ——
        /// 两者都跳到外部地图（高德 / 百度 / 苹果），App 内不做地图（设计交付文档 v3）。
        /// 行的标签与提示不同，落点相同；拆成两个 case 只会多一条永远走同一段代码的分支。
        case openMeetingPoint
        /// 拨号给跑者。**号码不在这个值里** —— 掩码串绝不能拼 `tel:`，
        /// 拨号统一走 `EmergencyDialer.telURL`，由视图从订单上取明文号。
        case callRunner
        /// 邀请态的「这次去不了」：直接发 `DECLINE`，不问原因、不计任何记录。
        case declineInvite
        /// 已接单三态的「我去不了」：走取消端点，转 `REMATCHING`。先二次确认。
        case releaseOrder
    }

    enum PrimaryAction: Equatable {
        /// 「接下这次陪跑」。
        ///
        /// 🚨 带的 `OrderRespondAction` 由 `WSNewOrder.dispatchRespondAction` 给出，
        /// **这里一个字节都不推算**：判断的另一半（这两人磨合成功过没有、时间够不够聊一轮）
        /// 在后端库里，自己算必然漂移，而漂移的表现是「界面说能直接接、后端回 409」。
        /// 两种 action 下**按钮文案相同** —— 志愿者要做的决定是同一个，
        /// 「先聊聊还是直接接」是后端的机制，不该变成他要理解的两个按钮。
        case acceptInvite(respond: OrderRespondAction)
        case confirmDeparture
        case enRoute
        case arrived

        var title: String {
            switch self {
            case .acceptInvite: return VolunteerOrderFlowCopy.acceptInvite
            case .confirmDeparture: return VolunteerOrderFlowCopy.confirmDeparture
            case .enRoute: return VolunteerOrderFlowCopy.enRoute
            case .arrived: return VolunteerOrderFlowCopy.arrived
            }
        }

        /// SF Symbol。一律 SF Symbols，不移植 HTML 原型里那些手绘 SVG 占位图。
        var systemImage: String? {
            switch self {
            // 接单与确认刻意**不给图标**：这两枚按钮按下去是一个承诺，
            // 加个勾会让它看起来像一次勾选。
            case .acceptInvite, .confirmDeparture: return nil
            case .enRoute: return "arrow.up.right"
            case .arrived: return "mappin.and.ellipse"
            }
        }
    }

    // MARK: 从派单推送算这一屏（邀请态）

    /// 志愿者**还没接单**那一刻的唯一数据源。
    ///
    /// 这一态他拿不到 `OrderDetailResponse`：后端 `OrderQueryService.getOrder` 只认
    /// `order.volunteer`，而接单前（含通话磨合期）它恒为 null ⇒ `GET /api/orders/{id}` 恒 403。
    ///
    /// 🔴 **姓氏、视力情况、引导方式三项这里拿不到**（`NEW_ORDER` 载荷没有它们，
    /// 而 `AvailableOrderResponse` 有）。设计稿的「李先生 / 全盲，用引导绳」因此整行不渲染 ——
    /// **不编、不占位**：给还没见面的志愿者印一个猜的视力程度，见面第一下就会抓错人。
    /// 已投 handoff 请后端在派单载荷里补齐。
    static func make(dispatch: WSNewOrder, remainingSeconds: Int, now: Date = Date()) -> Self {
        var rows: [Row] = []

        if let distance = dispatch.plannedDistanceText {
            rows.append(
                Row(
                    id: "plannedDistance",
                    label: VolunteerOrderFlowCopy.plannedDistanceLabel,
                    value: distance,
                    detail: dispatch.plannedPaceText,
                    action: nil,
                    accessibilityLabel: [
                        "\(VolunteerOrderFlowCopy.plannedDistanceLabel)，\(distance)",
                        dispatch.plannedPaceText.map { "\(VolunteerOrderFlowCopy.paceLabel)，\($0)" }
                    ].compactMap { $0 }.joined(separator: "，"),
                    accessibilityHint: nil
                )
            )
        } else if let pace = dispatch.plannedPaceText {
            rows.append(
                Row(
                    id: "pace",
                    label: VolunteerOrderFlowCopy.paceLabel,
                    value: pace,
                    detail: nil,
                    action: nil,
                    accessibilityLabel: "\(VolunteerOrderFlowCopy.paceLabel)，\(pace)",
                    accessibilityHint: nil
                )
            )
        }

        rows.append(contentsOf: escortRows(dispatch.escortNeeds))
        rows.append(
            Row(
                id: "decline",
                label: nil,
                value: VolunteerOrderFlowCopy.declineInvite,
                detail: nil,
                action: .declineInvite,
                accessibilityLabel: VolunteerOrderFlowCopy.declineInvite,
                accessibilityHint: "直接回复去不了，不问原因、不计任何记录"
            )
        )

        var subtitleParts: [String] = []
        if let address = dispatch.startAddress?.nilIfBlank { subtitleParts.append(address) }
        if let km = dispatch.distanceKm {
            subtitleParts.append(VolunteerOrderFlowCopy.distanceToStart(kilometers: km))
        }

        return Self(
            step: .invited,
            visual: .avatar,
            title: RunPlanFormat.shortStart(dispatch.plannedStart, now: now)
                ?? VolunteerOrderFlowCopy.inviteTitleFallback,
            subtitle: subtitleParts.joined(separator: "　"),
            replyNotice: VolunteerOrderFlowCopy.replyCountdown(seconds: remainingSeconds),
            isReplyUrgent: remainingSeconds <= VolunteerOrderFlowCopy.urgentCountdownSeconds,
            rows: rows,
            primaryAction: .acceptInvite(respond: dispatch.dispatchRespondAction),
            showsSafetyHub: false
        )
    }

    // MARK: 从订单详情算这一屏（约好 / 出发）

    /// `nil` = 这一态不走四步骨架前三格（终态、未知态，以及本轮还没搬过来的汇合与跑步中）。
    ///
    /// - Parameter distanceText: 本机到出发地点的距离文案，由视图从 `LocationService` 算好传进来。
    ///   **刻意不在这里算** —— 它要一个坐标和一次权限判定，那是视图的活；
    ///   在这里算会让这个纯类型需要一条定位。
    static func make(order: OrderDetailResponse, distanceText: String?, now: Date = Date()) -> Self? {
        guard let step = order.status.volunteerOrderFlowStep else { return nil }
        // 汇合与跑步中本轮仍走旧的地图面板路径。**显式挡在这里而不是让它渲染半页** ——
        // 调用方据此回退，见 `VolunteerInServiceView`。
        guard step == .booked || step == .departed else { return nil }

        var rows: [Row] = [runnerRow(order: order)]
        if let phoneRow = phoneRow(order: order) { rows.append(phoneRow) }

        if order.status.disclosesBlindRunnerNotesToVolunteer {
            // 🔴 标签保留 `路线备注` / `特殊说明`，**不按设计稿合并成「引导习惯」**。
            // 这两个输入框里躺的可能是「沿湖边跑道」，也可能是「我有低血糖，说头晕请马上停」——
            // 把后者叫「引导习惯」是把一条健康信息改名，而改名之后没人会再想到它该受什么保护。
            if let notes = order.routeNotes?.nilIfBlank {
                rows.append(noteRow(id: "routeNotes", label: VolunteerOrderFlowCopy.routeNotesLabel, value: notes))
            }
            if let notes = order.specialNotes?.nilIfBlank {
                rows.append(noteRow(id: "specialNotes", label: VolunteerOrderFlowCopy.specialNotesLabel, value: notes))
            }
        }

        let place = order.startAddress?.nilIfBlank ?? VolunteerOrderFlowCopy.meetingPointUnknown
        switch step {
        case .booked:
            rows.append(
                Row(
                    id: "meetingPoint",
                    label: VolunteerOrderFlowCopy.meetingPointLabel,
                    value: place,
                    detail: nil,
                    action: .openMeetingPoint,
                    accessibilityLabel: "\(VolunteerOrderFlowCopy.meetingPointLabel)，\(place)",
                    accessibilityHint: "双击查看集合点在地图上的位置"
                )
            )
        case .departed:
            rows.append(
                Row(
                    id: "navigate",
                    label: nil,
                    value: VolunteerOrderFlowCopy.navigateLabel,
                    detail: place,
                    action: .openMeetingPoint,
                    accessibilityLabel: "\(VolunteerOrderFlowCopy.navigateLabel)，\(place)",
                    accessibilityHint: "双击选择高德、百度或苹果地图步行导航"
                )
            )
        case .invited, .metUp:
            break
        }

        rows.append(
            Row(
                id: "release",
                label: nil,
                value: VolunteerOrderFlowCopy.releaseOrder,
                detail: nil,
                action: .releaseOrder,
                accessibilityLabel: VolunteerOrderFlowCopy.releaseOrder,
                accessibilityHint: "双击后会先确认一次。这一单会转给其他志愿者"
            )
        )

        return Self(
            step: step,
            visual: step == .departed ? .avatarWithProgressRing : .avatar,
            title: title(order: order, step: step, now: now),
            subtitle: subtitle(order: order, step: step, distanceText: distanceText),
            replyNotice: nil,
            isReplyUrgent: false,
            rows: rows,
            primaryAction: primaryAction(for: order.status),
            showsSafetyHub: false
        )
    }

    // MARK: 内部

    private static func title(order: OrderDetailResponse, step: VolunteerOrderFlowStep, now: Date) -> String {
        switch step {
        case .departed:
            return VolunteerOrderFlowCopy.departedTitle
        default:
            // 拿不到时间就退回状态名 —— **不摆一个占位时间**。
            return order.blindRunnerShortStartText(now: now) ?? order.status.volunteerServiceDisplayName
        }
    }

    private static func subtitle(
        order: OrderDetailResponse,
        step: VolunteerOrderFlowStep,
        distanceText: String?
    ) -> String {
        switch step {
        case .departed:
            return distanceText ?? ""
        default:
            return order.status == .scheduledConfirmed
                ? VolunteerOrderFlowCopy.scheduledSubtitle
                : VolunteerOrderFlowCopy.bookedSubtitle
        }
    }

    /// 🚩 **按状态发按钮，不按格子发。** `SCHEDULED_CONFIRMED` 与 `PENDING_ACCEPT` 同属
    /// 「约好」格，但前者要先回答「你还去吗」（`confirm-departure`），后者才是「我出发了」
    /// （`en-route`）。合并会让位置互推提前几小时打开（`AGENTS.md` §5）。
    private static func primaryAction(for status: RunOrderStatus) -> PrimaryAction? {
        switch status {
        case .scheduledConfirmed: return .confirmDeparture
        case .pendingAccept: return .enRoute
        case .driverEnRoute: return .arrived
        default: return nil
        }
    }

    /// 跑者行：掩码姓名 + 视力情况 / 引导方式 / 导盲犬。
    ///
    /// 姓名**视觉上保留掩码**（`李*`）、**朗读去掉星号** —— 后端的姓名始终带掩码
    /// （契约逐字「不存在明文版本」），原样交给 VoiceOver 会念成「李星号」，
    /// 而陪跑员端的读屏同样是外放的。设计稿写的「接下后显示李明的全名」做不到。
    private static func runnerRow(order: OrderDetailResponse) -> Row {
        let name = order.blindName?.nilIfBlank ?? VolunteerOrderFlowCopy.unknownRunnerName
        let needs = order.escortNeeds.map(\.value).joined(separator: "，").nilIfBlank
        return Row(
            id: "runner",
            label: VolunteerOrderFlowCopy.runnerLabel,
            value: name,
            detail: needs,
            action: nil,
            accessibilityLabel: [
                "\(VolunteerOrderFlowCopy.runnerLabel)\(order.blindNameForSpeech)",
                needs
            ].compactMap { $0 }.joined(separator: "，"),
            accessibilityHint: nil
        )
    }

    /// 电话行。`nil` = 这一单没有能拨通的号码 ⇒ 整行不渲染。
    ///
    /// 🔴 **这一行不在设计稿里，但它是 `AGENTS.md` §8 的硬规则**：
    /// 「接单后展示掩码号码并给出拨号入口」。设计稿的「约好」屏把联系方式压进了跑者行，
    /// 而陪跑员会接到 / 打出一个陌生号码 —— 屏幕上那串掩码号是他**认人**的唯一依据。
    ///
    /// 三条约束一条都不能少：
    /// - 屏幕上是**掩码**（`EmergencyContactResponse.maskPhone`）；
    /// - 读屏标签里**一个数字都没有** —— VoiceOver 外放等于把跑者的号码广播给周围所有人
    ///   （`f404de2` / 审计 F10）。号码对「要不要打这通电话」没有任何帮助；
    /// - 全号只进 `tel:`，而且判据是「拼不拼得出 URL」不是「字符串非空」——
    ///   掩码串会被 `telURL` 的掩码闸拦掉（不拦则拼成 `tel://1381001`，一个可能真打给别人的号码）。
    private static func phoneRow(order: OrderDetailResponse) -> Row? {
        guard let phone = order.blindPhone?.nilIfBlank,
              EmergencyDialer.telURL(for: phone) != nil else { return nil }
        return Row(
            id: "phone",
            label: VolunteerOrderFlowCopy.phoneLabel,
            value: EmergencyContactResponse.maskPhone(phone) ?? phone,
            detail: nil,
            action: .callRunner,
            accessibilityLabel: VolunteerOrderFlowCopy.callRunner,
            accessibilityHint: "系统会先弹出拨号确认，确认后才会拨出"
        )
    }

    private static func noteRow(id: String, label: String, value: String) -> Row {
        Row(
            id: id,
            label: label,
            value: value,
            detail: nil,
            action: nil,
            accessibilityLabel: "\(label)，\(value)",
            accessibilityHint: nil
        )
    }

    /// 陪跑要求那几行。**内容由数据源决定，不由状态决定** ——
    /// 闸已经做在 `OrderDetailResponse.escortNeeds` / `WSNewOrder.escortNeeds` 上了，
    /// 这里再判一次就是第二个源。
    private static func escortRows(_ needs: [EscortNeed]) -> [Row] {
        needs.map { need in
            Row(
                id: "escort-\(need.kind.rawValue)",
                label: need.title,
                value: need.value,
                detail: nil,
                action: nil,
                accessibilityLabel: "\(need.title)，\(need.value)",
                accessibilityHint: nil
            )
        }
    }
}
