import Foundation

// MARK: - 四步骨架

/// 设计稿 `design-reference/order-flow/` 的四个步骤：匹配 → 约好 → 出发 → 汇合。
///
/// **它不是订单状态的别名。** 后端有 11 个状态（客户端 12 个，含 `.unknown`），
/// 而这一屏只有 4 格。映射在 `RunOrderStatus.blindOrderFlowStep` 上，写成穷举 switch。
enum BlindOrderFlowStep: Int, CaseIterable, Equatable {
    case matching = 0
    case booked = 1
    case departed = 2
    case metUp = 3

    /// 进度条上那四个字。顺序即 `allCases`。
    var title: String {
        switch self {
        case .matching: return "匹配"
        case .booked: return "约好"
        case .departed: return "出发"
        case .metUp: return "汇合"
        }
    }

    static var allTitles: [String] { allCases.map(\.title) }
}

extension RunOrderStatus {
    /// 这一态落在四步骨架的哪一格。`nil` = **不走这个骨架**。
    ///
    /// 走不走骨架的判据与 `blindRunnerRoute` 对齐：`.tracking` 那七态走，其余不走
    /// （`IN_PROGRESS` 走执行屏 `BlindActiveRunView`，`COMPLETED` 走完成/评价页，
    /// 其余终态走只读终态卡）。**刻意不复用 `blindRunnerRoute` 直接派生** ——
    /// 那个枚举回答的是「去哪一页」，这个回答的是「在这一页的第几格」，
    /// 两个问题同源但不同步：后端加状态时两处都要各做一次决策。
    ///
    /// 穷举 switch 而不是集合字面量：集合会把新状态默默判成 `nil`，
    /// 而那表现为「订单页整屏空白」—— 对盲人端「点了没反应」就是事故（`AGENTS.md` §硬约束）。
    var blindOrderFlowStep: BlindOrderFlowStep? {
        switch self {
        // `PENDING_INTRO_CALL` 归**匹配**格：这一态后端 `order.volunteer` 恒为 null，
        // 还没有志愿者接单（`AGENTS.md` §5）。进度条上显示成「约好」会是假信息。
        // 通话本身在 `BlindIntroCallView` 全屏里，这一页只是它的底稿。
        case .pendingMatch, .pendingIntroCall, .rematching:
            return .matching
        // `SCHEDULED_CONFIRMED` 与 `PENDING_ACCEPT` 同格：对盲人这两态的事实都是
        // **人已经定了**（`displayName` 分别是「已约好」「待出发」），区别只在志愿者
        // 临期确认那一下 —— 那是后端的内部机制，不该在进度条上占一格。
        case .scheduledConfirmed, .pendingAccept:
            return .booked
        case .driverEnRoute:
            return .departed
        case .driverArrived:
            return .metUp
        // 走执行屏，不走这个骨架。
        case .inProgress:
            return nil
        // 终态：完成/评价页与只读终态卡，都不是四步骨架。
        case .completed, .cancelled, .noVolunteer:
            return nil
        // 落 `nil` ⇒ 退回改版前那条只读滚动列表（`blindRunnerRoute` 把 `.unknown`
        // 也归到 `.tracking` 的只读落点）。**不要让它落进 `.matching`**：
        // 「我不认识后端给的状态」和「正在匹配」是两件事，把未知态画成匹配中
        // 会让盲人以为系统在替他找人。
        case .unknown:
            return nil
        }
    }
}

// MARK: - 一屏的全部可渲染内容

/// 订单页四态那一屏要显示的东西，**全部**。
///
/// 做成纯值类型而不是散在 view 里的一堆计算属性，理由有三条，第三条最重要：
///
/// 1. 视图只按它渲染，不再自己判状态 —— 设计稿要求「页面骨架固定，状态变化只换内容」，
///    而骨架固定的前提是内容由一处算出来。
/// 2. 它能被单测穷举（`BlindOrderFlowPresentationTests`）。这一屏的错误形态全是**静默**的：
///    文案说错一态、按钮在不该出现的态出现，屏幕上都不会报错。
/// 3. 🔴 **文案一律取既有的常量，这个类型不新造一句话。** `blindRunnerDescription`
///    每一条上都记着不许说的东西 —— 通话态不提「第几位」（无声拒绝）、远期预约不提
///    临期闸门、不写具体提前量（那是后端配置，写死就是编一个数字念给盲人听）。
///    设计稿的副标题恰好违反最后一条（它写「请提前 10 分钟到达」），所以这里用既有文案。
struct BlindOrderFlowPresentation: Equatable {
    let step: BlindOrderFlowStep
    /// 视觉区画什么。纯装饰，对读屏隐藏。
    let visual: Visual
    /// 34pt 的状态标题。
    let title: String
    /// 状态副标题。
    let subtitle: String
    /// 信息列表最后一行的文案。
    let lastRowTitle: String
    /// 底部主按钮。`nil` = 这一态没有主动作（设计稿的匹配态就是空的）。
    let primaryAction: PrimaryAction?
    /// 副标题下方那行警示。**只在异常时出现**，正常状态恒为 `nil` ——
    /// 设计稿明确不要「定位正常」这类反向提示。
    let warning: String?

    enum Visual: Equatable {
        /// 匹配态：雷达。
        case radar
        /// 约好态：头像。
        case avatar
        /// 出发态：头像 + 外圈进度环。
        case avatarWithProgressRing
        /// 汇合态：头像 + 右下角绿色对勾。
        case avatarWithSuccessBadge
    }

    enum PrimaryAction: Equatable {
        /// 打电话给陪跑员。`title` 里带姓氏。
        case callVolunteer(title: String)
        /// 进通话磨合页。**不复用 `callVolunteer`** —— 那个按下去立刻弹系统拨号确认，
        /// 这个只是打开一个页面。对看不见屏幕的人，两件事听起来一样就等于随时可能误拨
        /// （`BlindOrderStatusView.introCallEntrySection` 记着同一条）。
        case openIntroCall(title: String)
        /// 继续等待。只在 `REMATCHING` 出现 —— 项目负责人 2026-09-16 拍板：
        /// `PENDING_MATCH` 删掉（后端 `handleMatchTimeout` 每轮超时自己就把窗口往后推，
        /// 客户端一次不调订单寿命相同），而 `REMATCHING` 那一侧是**真延长**
        /// （后端 N62 把 `rematchNotifyAt` 计进了 `dispatchDeadline`），删了只剩一个
        /// 30 分钟窗口就转 `NO_VOLUNTEER` 终态，而重新下单又要求 ≥30 分钟提前量。
        case keepWaiting(title: String)

        var title: String {
            switch self {
            case .callVolunteer(let title), .openIntroCall(let title), .keepWaiting(let title):
                return title
            }
        }

        /// SF Symbol。设计稿的主按钮带图标（电话 / 跑步）。
        var systemImage: String? {
            switch self {
            case .callVolunteer: return "phone.fill"
            case .openIntroCall: return "phone.bubble.left.fill"
            case .keepWaiting: return nil
            }
        }
    }

    /// 从订单算出这一屏。`nil` = 这一态不走四步骨架。
    ///
    /// - Parameters:
    ///   - distanceText: 志愿者到出发地点的距离文案，取自
    ///     `BlindOrderStatusViewModel.volunteerDistanceToStartText`。
    ///     **刻意从外面传进来而不是在这里算** —— 它依赖 WebSocket 推来的对端坐标与
    ///     新鲜度判定，那是 view model 的活；在这里算会让这个纯类型需要一个时钟和一条网络。
    ///   - canKeepWaiting: 延长次数还没用尽。同样来自 view model（上限由后端 409 告知）。
    ///   - now: 算「已等待」用。走参数是为了让跨小时那条边界能被单测钉住。
    static func make(
        order: OrderDetailResponse,
        distanceText: String?,
        canKeepWaiting: Bool,
        locationWarning: String? = nil,
        now: Date = Date()
    ) -> BlindOrderFlowPresentation? {
        guard let step = order.status.blindOrderFlowStep else { return nil }

        let name = order.volunteerNameForSpeech
        let hasVolunteerName = order.volunteerName?.nilIfBlank != nil

        return BlindOrderFlowPresentation(
            step: step,
            visual: visual(for: step),
            title: title(order: order, step: step, name: name, hasVolunteerName: hasVolunteerName),
            subtitle: subtitle(order: order, distanceText: distanceText, now: now),
            lastRowTitle: lastRowTitle(order: order),
            primaryAction: primaryAction(order: order, name: name, canKeepWaiting: canKeepWaiting),
            warning: locationWarning
        )
    }

    private static func visual(for step: BlindOrderFlowStep) -> Visual {
        switch step {
        case .matching: return .radar
        case .booked: return .avatar
        case .departed: return .avatarWithProgressRing
        case .metUp: return .avatarWithSuccessBadge
        }
    }

    private static func title(
        order: OrderDetailResponse,
        step: BlindOrderFlowStep,
        name: String,
        hasVolunteerName: Bool
    ) -> String {
        switch step {
        case .matching:
            // 通话磨合态单独说，否则「正在匹配陪跑员」与状态卡念的
            // 「有位志愿者想陪你跑」自相矛盾。
            if order.status == .pendingIntroCall { return "有位志愿者想陪你跑" }
            if order.status == .rematching { return "正在重新匹配陪跑员" }
            return "正在匹配陪跑员"
        case .booked:
            // 设计稿这一格是那行大字时间。拿不到时间就退回状态名 ——
            // 不摆占位时间，理由同首页深蓝卡。
            return order.blindRunnerShortStartText() ?? order.status.displayName
        case .departed:
            // ⚠️ **设计稿这里是「8 分钟后到」，做不出来。** 全仓与后端契约都没有 ETA
            // （`etaMinutes` / `estimatedArrival` 在 `api_spec.yaml` 命中 0），
            // 而 `VoiceStatusQuery.swift:21` 逐字写着「只念直线距离，**不做 ETA / 路线规划**」。
            // 编一个到达时间给正在集合点等人的盲人，比不给更糟。距离进副标题。
            return hasVolunteerName ? "\(name)正在赶来" : "陪跑员正在赶来"
        case .metUp:
            return hasVolunteerName ? "\(name)已到达" : "陪跑员已到达"
        }
    }

    /// 副标题 = 既有的状态说明 + 这一态那个会变的数字。
    ///
    /// 「已等待」与距离的状态集互不相交（`offersWaitedDuration` / `offersVolunteerDistanceToStart`
    /// 各自的注释里有理由），所以任何时刻最多追加一个数。
    private static func subtitle(
        order: OrderDetailResponse,
        distanceText: String?,
        now: Date
    ) -> String {
        var parts = [order.status.blindRunnerDescription]
        if let waited = order.blindRunnerWaitedText(now: now) {
            parts.append(waited)
        }
        if order.status.offersVolunteerDistanceToStart, let distanceText {
            parts.append(distanceText)
        }
        return parts.joined(separator: "　")
    }

    /// 信息列表最后一行。
    ///
    /// 🔴 **设计稿在出发态写的是「修改或取消预约」，两处都不成立**：
    /// ① 盲人在 `DRIVER_EN_ROUTE` / `DRIVER_ARRIVED` **不能取消**（`AGENTS.md` §5 的
    ///    可取消状态集合里没有这两态，后端会拒）；
    /// ② 后端**没有任何改单端点**（`/api/orders` 下 `put`/`patch` 命中 0）——
    ///    「修改」这个词承诺了一个不存在的功能。
    /// 所以：能取消的态说「取消」，不能取消的态说「遇到问题」。
    private static func lastRowTitle(order: OrderDetailResponse) -> String {
        guard order.status.canBlindRunnerCancel else { return "遇到问题" }
        // 匹配态说「取消匹配」（设计稿原文），其余说「取消预约」——
        // 前者此刻取消的是一次派单，后者取消的是一个已经定下来的约定。
        return order.status.blindOrderFlowStep == .matching ? "取消匹配" : "取消预约"
    }

    private static func primaryAction(
        order: OrderDetailResponse,
        name: String,
        canKeepWaiting: Bool
    ) -> PrimaryAction? {
        // 通话磨合最优先：那一态唯一该做的事就是打这通电话。
        if order.status == .pendingIntroCall {
            return .openIntroCall(title: IntroCallCopy.blindEntryButtonTitle)
        }
        // 判据是「拼不拼得出 tel: URL」而不是「字符串非空」：掩码串 `138****1234`
        // 会被 `telURL` 的掩码闸拦掉（不拦则拼成 `tel://1381234`，一个可能真打给别人的号码）。
        if order.status.offersVolunteerCall,
           EmergencyDialer.telURL(for: order.volunteerPhone?.nilIfBlank) != nil {
            return .callVolunteer(title: "打电话给\(name)")
        }
        // `REMATCHING` 保留延长入口，`PENDING_MATCH` 不保留（见 `PrimaryAction.keepWaiting`）。
        // 判据走 `offersBlindRunnerKeepWaitingControl` 而不是就地写 `== .rematching`：
        // 「哪些态有这个按钮」有三处要问（这里、`repeatStatus` 的附带播报、
        // `ORDER_CANCELLATION_WARNING` 的正文覆盖），各写一份必然漂开。
        if order.status.offersBlindRunnerKeepWaitingControl, canKeepWaiting {
            return .keepWaiting(title: KeepWaitingCopy.buttonTitle)
        }
        // 设计稿的匹配态主按钮位是空的 —— 那一态用户没有该做的事，摆一个按钮
        // 反而会让盲人以为等待期有一件必须完成的操作。
        return nil
    }
}
