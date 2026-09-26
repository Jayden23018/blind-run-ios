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
    /// 约好页、还没到 `primaryActionUnlockAt` 时的白色次要按钮（交付包 D4）。
    /// 按下去是同一个 `en-route`；早于开跑前那道闸会 409 `DEPARTURE_TOO_EARLY`。
    static let alreadyDeparted = "我已经出发了"
    /// 等满时限后，「开始跑步」原地换成它（后端 #362，`earliestEndWaitAt`）。
    static let endWaiting = "结束等待"
    /// 「结束等待」上方那行小字。**「不算你的取消」是这一刻陪跑员最想知道的**（交付包 ④b）。
    static let endWaitingCaption = "结束后不算你的取消，时长不计入"
    static let arrived = "我已到达集合点"
    static let startRun = "开始跑步"
    /// 主按钮上方那行小字。**逐字取自设计交付文档 v3 §5 的「陪跑员主按钮」列。**
    static let startRunCaption = "见面并握好引导绳后再按"
    static let doneReviewing = "完成"
    static let backToHome = "回到首页"

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
    /// 「跑多久」。**与它并排的是「跑多远」，所以不叫「预计时长」**（盲人端订单信息卡里那一行
    /// 用的是后者，两页不相邻，各自读得顺比字面统一重要）。项目负责人 2026-09-18 指定。
    static let plannedDurationLabel = "跑多久"
    static let paceLabel = "配速"
    static let phoneLabel = "电话"
    /// 拨号那一行的读屏标签。**不带号码**，理由见 `phoneRow`。
    static let callRunner = "拨打跑者电话"
    /// 汇合那一屏的拨号行标题。
    ///
    /// ⚠️ 设计稿写的是「打电话给**李明**」，而后端的姓名**一律带掩码**（`李*`，契约逐字
    /// 「不存在明文版本」）。「打电话给李\*」在屏幕上是个错字，去掉星号的「打电话给李」
    /// 在中文里也不成句 —— 所以这一行用角色词。跑者是谁在同屏的状态卡里已经说过了。
    static let callRunnerRow = "打电话给跑者"
    static let cannotFindRunner = "找不到对方"
    static let meetingPointLabel = "集合点"
    static let plannedTimeLabel = "时间"
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

    // MARK: 汇合

    /// 「李在约 40 米外」。`distance` 已经格式化好（`DistanceCalculator.formattedDistance`）。
    static func metUpTitle(name: String, distance: String) -> String { "\(name)在约 \(distance)外" }

    /// 收不到跑者位置时的降级句。**不摆一个上次的距离** —— 那会让陪跑员朝着一个
    /// 几分钟前的方向走。
    ///
    /// 设计交付文档 v3 §5 的实现要点逐字：「跑者位置超过 60 秒未更新时，改为显示
    /// 『李明的位置暂时没有更新』」。60 秒这个阈值不在这里重写 ——
    /// 客户端只认 `LiveEscortSessionCoordinator.peerFreshness` 那一个新鲜度判据。
    static func metUpStaleTitle(name: String) -> String { "\(name)的位置暂时没有更新" }
    static let metUpStaleSubtitle = "到集合点附近后，先打个电话"

    // MARK: 已完成

    static let completedTitle = "陪跑完成"
    static let viewRunRecord = "查看跑步记录"
    static let reportIssue = "上报问题"

    /// 「和李跑了 5.12 公里，用时 39 分 20 秒」。两个数**各自可缺**，缺的那半句整段不出现。
    ///
    /// 🔴 **这不是「本次志愿服务时长」。** 设计稿在这一屏还要一张
    /// 「本次志愿服务时长 0.7 小时 · 待认证」的卡，本轮**整块不做**：后端没有按单的服务时长
    /// （只有累计的 `totalServiceMinutes`，口径是「点开始服务 → 订单完成」），
    /// 而这里这个 `actualDurationSeconds` 是**轨迹首末点的时间差** —— 两者在集合点多站
    /// 五分钟就分叉。拿跑步耗时冒充服务时长，志愿者拿去对组织的记录时会发现对不上。已投 handoff。
    static func completedSummary(name: String, distanceMeters: Int?, durationSeconds: Int?) -> String? {
        let distance = (distanceMeters ?? 0) > 0
            ? String(format: "%.2f 公里", Double(distanceMeters ?? 0) / 1000)
            : nil
        let duration = (durationSeconds ?? 0) > 0
            ? spokenDuration(seconds: durationSeconds ?? 0)
            : nil
        switch (distance, duration) {
        case let (.some(distance), .some(duration)):
            return "和\(name)跑了 \(distance)，用时 \(duration)"
        case let (.some(distance), .none):
            return "和\(name)跑了 \(distance)"
        // 只有耗时那一档也要带人名 —— 否则读屏念出来是一句没有主语的「用时 39 分」。
        case let (.none, .some(duration)):
            return "和\(name)跑了 \(duration)"
        case (.none, .none):
            return nil
        }
    }

    /// 「39 分 20 秒」/「1 小时 2 分 3 秒」。零的那一位不出现 ——
    /// 「0 小时 39 分」会让读屏用户多听一个没有信息量的词。
    static func spokenDuration(seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) 小时") }
        if minutes > 0 { parts.append("\(minutes) 分") }
        // 分和秒都是 0 时保留「0 秒」，否则整句变成空串。
        if secs > 0 || parts.isEmpty { parts.append("\(secs) 秒") }
        return parts.joined(separator: " ")
    }

    // MARK: 跑者已取消

    static func runnerCancelledTitle(name: String) -> String { "\(name)取消了这次陪跑" }
    /// 逐字取自设计交付文档 v3 §5。**「不算你的取消」是这一屏唯一重要的一句话** ——
    /// 志愿者第一反应是「这会不会记在我头上」。
    static let runnerCancelledSubtitle = "不算你的取消，不需要做什么"

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
    /// 返回结构体而不是在 `confirmationDialog` 里写四个三元表达式：那样写会把 SwiftUI 的
    /// 类型检查器拖到超时。
    ///
    /// 🚩 2026-09-17 第二次改这段：确认层从 `confirmationDialog` 换成设计交付文档 v3 的
    /// **底部弹层**，措辞随之换成设计稿原词（「取消这次陪跑？/ 保留这次陪跑 / 仍然取消」）。
    /// 上一版刻意避开「取消」二字，理由是它读起来像在替盲人销单 —— 那个理由没错，
    /// 但弹层里那句「系统会马上为李明重新找人」已经把真实后果说清楚了，
    /// 再造一套只有本 App 用的词反而让人猜。项目负责人 2026-09-17 拍板按设计稿。
    ///
    /// 🔴 **12 小时那一段只说「会马上重新找人」，不提任何取消记录。**
    /// 设计稿原文还有「会记一次临时取消」「30 天内满 3 次，接下来 14 天不会收到邀请」——
    /// 后端**零实现**：`api_spec.yaml` 与 `websocket-protocol.md` 里
    /// `lateCancel` / `cancellationCount` / 临时取消 / cancelPolicy 全部命中 0，
    /// 取消端点本身连请求体都没有。向志愿者宣布一套不存在的处罚规则，
    /// 而他正要据此决定去不去，比不说更糟。已投 handoff。
    static func cancelSheet(
        for status: RunOrderStatus?,
        plannedStart: Date?,
        now: Date = Date()
    ) -> CancelSheetCopy {
        CancelSheetCopy(
            title: "取消这次陪跑？",
            lateNotice: isWithinLateCancelWindow(plannedStart: plannedStart, now: now)
                ? "离开始不到 \(lateCancelWindowHours) 小时。现在取消，系统会马上为跑者重新找人。"
                : nil,
            message: status == .scheduledConfirmed || status == .pendingAccept || status == .driverEnRoute
                ? "这一单会转给其他志愿者，之后不一定还能接回来。"
                : "这一单会转给其他志愿者。",
            keep: "保留这次陪跑",
            cancel: "仍然取消"
        )
    }

    /// ⚠️ **这个 12 是客户端的，不是后端配置。** 设计交付文档 v3 §10 明写「规则参数后端可配置，
    /// 前端不写死」，而后端至今没有这个参数 —— 契约里搜不到任何取消政策。
    /// 它只决定「多不多显示一句话」，不参与任何判罚，所以暂时留在客户端是安全的；
    /// 后端一旦给出配置就改读配置。已投 handoff。
    static let lateCancelWindowHours = 12

    private static func isWithinLateCancelWindow(plannedStart: Date?, now: Date) -> Bool {
        guard let plannedStart else { return false }
        let remaining = plannedStart.timeIntervalSince(now)
        // 已经过了开跑时间也算「不足 12 小时」—— 那一刻盲人多半已经在集合点了。
        return remaining < Double(lateCancelWindowHours) * 3600
    }

    struct CancelSheetCopy: Equatable {
        let title: String
        /// 距开跑不足 12 小时时多出来的那一段。`nil` = 不显示。
        let lateNotice: String?
        let message: String
        /// 黄色主按钮**是「保留」**：这一屏的默认动作是不取消。
        let keep: String
        /// 灰色文字按钮。**不用红色** —— 红在本 App 里只给紧急求助（设计交付文档 v3 §1.2）。
        let cancel: String
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
    /// `nil` = **这一屏不画进度条**。设计交付文档 v3 的「已完成」与「跑者取消」两屏上
    /// 本来就没有那四格 —— 四步讲的是「这一单走到哪了」，而这两屏讲的是「它结束了」，
    /// 再画一条进度条只会让人以为还有下一步。
    let step: VolunteerOrderFlowStep?
    let visual: Visual
    /// 那行大字。
    let title: String
    /// 读屏念的那行大字。`nil` = 与 `title` 相同。
    ///
    /// 🔴 **存在的唯一理由是掩码姓名**：后端的姓名一律带掩码（`李*`），原样交给 VoiceOver
    /// 会念成「李星号在约 40 米外」。屏幕上必须保留星号（那是隐私口径），读屏必须去掉
    /// —— 两个要求方向相反，所以只能是两个字符串。去星走 `blindNameForSpeech`。
    let titleSpoken: String?
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
    /// 右上角「求助」按下去去哪。**每一屏都有这枚胶囊**（交付包 D1）。
    ///
    /// 🔄 2026-09-26 改口径：此前这里是 `showsSafetyHub: Bool`，前三态一律 `false`
    /// （项目负责人 2026-09-17：云端 SOS 关着，摆一个按下去无事发生的入口比没有更糟）。
    /// 陪跑员订单页 v2 把它换成**全页显示、非跑步中降级为本地拨号**（项目负责人 2026-09-26 拍板）——
    /// 「按下去无事发生」这个顾虑由本地拨号解决：按下去一定有 120 / 110 可拨，
    /// 而文案说清 App 不会代你发送求助。判据只在 `VolunteerOrderSOSMode.resolve`。
    let helpMode: VolunteerOrderSOSMode

    enum Visual: Equatable {
        /// 头像。拿不到姓名时圆里是「跑」。
        case avatar
        /// 头像 + 外圈进度环（出发态）。
        case avatarWithProgressRing
        /// 绿色对勾（已完成）。这一屏没有「谁」可展示了，展示的是「这件事成了」。
        case successCheck
        /// 中性灰头像（跑者已取消）。
        ///
        /// ⚠️ 设计稿用的是**整块信息卡压淡**来表达「结束了」。这里只把头像转灰、
        /// 正文对比度一个字都不降 —— 压淡打的正好是低视力志愿者，
        /// 而「这单没了」这件事用一句话说清就够，不需要靠看不清来表达。
        case mutedAvatar
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
        /// 汇合态的「找不到对方」。打开一层本地说明 + 拨号入口。
        /// **不调任何端点** —— 契约里没有「我找不到他」这个动作。
        case cannotFindRunner
        /// 已完成态的「查看跑步记录」：进既有的轨迹回放页。
        case viewRunRecord
        /// 已完成态与「找不到对方」层里的「上报问题」：`POST /api/support/tickets`。
        case reportIssue
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
        /// 「开始跑步」。**两端都能按，先按的生效**（设计交付文档 v3 §5），
        /// 客户端不判谁先 —— 后端以先到的请求为准，后到的一方由轮询/推送切到跑步中。
        case startRun
        /// 约好页、还没到解锁时刻：白色次要按钮「我已经出发了」，按下去同样是 `en-route`。
        case alreadyDeparted
        /// 等满时限后替换「开始跑步」：`POST /api/orders/{id}/end-waiting`。
        case endWaiting
        /// 已完成那一屏的「完成」。**纯粹是关掉这一页**，不发任何请求。
        case doneReviewing
        /// 跑者已取消那一屏的「回到首页」。同样只是关掉这一页。
        case backToHome

        var title: String {
            switch self {
            case .acceptInvite: return VolunteerOrderFlowCopy.acceptInvite
            case .confirmDeparture: return VolunteerOrderFlowCopy.confirmDeparture
            case .enRoute: return VolunteerOrderFlowCopy.enRoute
            case .arrived: return VolunteerOrderFlowCopy.arrived
            case .startRun: return VolunteerOrderFlowCopy.startRun
            case .alreadyDeparted: return VolunteerOrderFlowCopy.alreadyDeparted
            case .endWaiting: return VolunteerOrderFlowCopy.endWaiting
            case .doneReviewing: return VolunteerOrderFlowCopy.doneReviewing
            case .backToHome: return VolunteerOrderFlowCopy.backToHome
            }
        }

        /// 按钮**上方**那行小字。走 `OrderFlowPrimaryAction.caption`：它同时进
        /// `accessibilityHint`，不另做一个读屏元素（否则 VoiceOver 会念两遍）。
        var caption: String? {
            switch self {
            // 「握好引导绳再按」是这一句话唯一能起作用的时刻 —— 按下去之后计时就开始了，
            // 而对盲人来说「跑步已开始」意味着他可以迈步。
            case .startRun: return VolunteerOrderFlowCopy.startRunCaption
            case .endWaiting: return VolunteerOrderFlowCopy.endWaitingCaption
            case .acceptInvite, .confirmDeparture, .enRoute, .alreadyDeparted, .arrived, .doneReviewing, .backToHome:
                return nil
            }
        }

        /// SF Symbol。一律 SF Symbols，不移植 HTML 原型里那些手绘 SVG 占位图。
        var systemImage: String? {
            switch self {
            // 接单与确认刻意**不给图标**：这两枚按钮按下去是一个承诺，
            // 加个勾会让它看起来像一次勾选。
            case .acceptInvite, .confirmDeparture: return nil
            case .enRoute, .alreadyDeparted: return "arrow.up.right"
            case .endWaiting: return nil
            case .arrived: return "mappin.and.ellipse"
            case .startRun: return "figure.run"
            // 「完成」与「回到首页」只是关掉页面，给图标会让它看起来像还要做点什么。
            case .doneReviewing, .backToHome: return nil
            }
        }
    }

    // MARK: 从派单推送算这一屏（邀请态）

    /// 志愿者**还没接单**那一刻的唯一数据源。
    ///
    /// 这一态他拿不到 `OrderDetailResponse`：后端 `OrderQueryService.getOrder` 只认
    /// `order.volunteer`，而接单前（含通话磨合期）它恒为 null ⇒ `GET /api/orders/{id}` 恒 403。
    ///
    /// 🔴 **姓氏这里仍然拿不到**（`NEW_ORDER` 与 `AvailableOrderResponse` 都没有 `blindName`），
    /// 所以头像圆里是「跑」，**不编一个名字**。已投 handoff。
    ///
    /// 视力情况与引导方式从 2026-09-18 起有了：`supplement` 由 `GET /api/orders/available`
    /// 补进来（见 `VolunteerInviteSupplement`）。**`nil` = 补不到 ⇒ 那两行不渲染** ——
    /// 给还没见面的志愿者印一个猜的视力程度，见面第一下就会抓错人。
    ///
    /// 参数放在末尾且有默认值：既有调用点（用例）因此不必各补一行。
    static func make(
        dispatch: WSNewOrder,
        remainingSeconds: Int,
        now: Date = Date(),
        supplement: VolunteerInviteSupplement? = nil
    ) -> Self {
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

        // 「跑多久」。项目负责人 2026-09-18 点名要，且**只放这一页**：
        // 邀请卡那三格是稿子写死的 3 列（离你 / 跑多远 / 配速），塞第四格会把 grid 改成两行。
        if let duration = supplement?.durationText {
            rows.append(
                Row(
                    id: "duration",
                    label: VolunteerOrderFlowCopy.plannedDurationLabel,
                    value: duration,
                    detail: nil,
                    action: nil,
                    accessibilityLabel: "\(VolunteerOrderFlowCopy.plannedDurationLabel)，\(duration)",
                    accessibilityHint: nil
                )
            )
        }

        // 导盲犬来自派单载荷，视力 / 引导方式来自 `available` 补数 —— **两个数据源，一份渲染**。
        rows.append(contentsOf: escortRows(dispatch.escortNeeds + (supplement?.escortNeeds ?? [])))
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
            titleSpoken: nil,
            subtitle: subtitleParts.joined(separator: "　"),
            replyNotice: VolunteerOrderFlowCopy.replyCountdown(seconds: remainingSeconds),
            isReplyUrgent: remainingSeconds <= VolunteerOrderFlowCopy.urgentCountdownSeconds,
            rows: rows,
            primaryAction: .acceptInvite(respond: dispatch.dispatchRespondAction),
            helpMode: .localCall
        )
    }

    // MARK: 从订单详情算这一屏

    /// `nil` = 这一态**不走这个页面**。当前只剩两类：跑步中（`IN_PROGRESS` 有自己的
    /// `VolunteerRunningPage`）与认不出的状态。
    ///
    /// - Parameter distanceText: 本机到**出发地点**的距离文案（出发态用）。
    /// - Parameter peerDistanceText: 本机到**跑者**的距离文案（汇合态用，来自
    ///   `BLIND_LOCATION_UPDATE` 的最新样本）。两个都由视图算好传进来 ——
    ///   **刻意不在这里算**：它们各要一个坐标和一次权限判定，那是视图的活；
    ///   在这里算会让这个纯类型需要一条定位。
    static func make(
        order: OrderDetailResponse,
        distanceText: String?,
        peerDistanceText: String? = nil,
        now: Date = Date()
    ) -> Self? {
        // 两个终态先分流：它们不落进四步里的任何一格（`volunteerOrderFlowStep` 判 nil），
        // 而设计稿给了它们各自一整屏。
        switch order.status {
        case .completed: return completed(order: order)
        case .cancelled: return cancelledByRunner(order: order, now: now)
        default: break
        }

        guard let step = order.status.volunteerOrderFlowStep else { return nil }
        if step == .metUp {
            // `IN_PROGRESS` 与 `DRIVER_ARRIVED` 同属「汇合」格，但跑起来之后换成跑步中页
            // （`VolunteerRunningPage`，#218），不走这一套。**显式挡在这里**，见 `VolunteerInServiceView`。
            guard order.status == .driverArrived else { return nil }
            return metUp(order: order, peerDistanceText: peerDistanceText, now: now)
        }
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
            titleSpoken: nil,
            subtitle: subtitle(order: order, step: step, distanceText: distanceText),
            replyNotice: nil,
            isReplyUrgent: false,
            rows: rows,
            primaryAction: primaryAction(for: order, now: now),
            helpMode: VolunteerOrderSOSMode.resolve(status: order.status)
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
    ///
    /// `PENDING_ACCEPT` 再按 `primaryActionUnlockAt` 分两种外观（交付包 D4）：到点前是白色次要按钮
    /// 「我已经出发了」，到点后是黄色主按钮「我出发了」—— 两者按下去是同一个 `en-route`。
    private static func primaryAction(for order: OrderDetailResponse, now: Date) -> PrimaryAction? {
        switch order.status {
        case .scheduledConfirmed: return .confirmDeparture
        case .pendingAccept:
            return VolunteerOrderPhase.resolve(order: order, now: now) == .agreedSoon ? .enRoute : .alreadyDeparted
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
    ///
    /// - Parameter asAction: 汇合那一屏把它渲染成一行动作（「打电话给跑者」，掩码号退到下面那行
    ///   小字）——设计稿在那一屏要的是「现在就打给他」，而不是一条查阅用的资料行。
    ///   两种形态共用这一个函数，是因为上面那三条约束**一条都不能漏**，
    ///   而抄第二份的代价正好是漏掉其中一条。
    static func phoneRow(order: OrderDetailResponse, asAction: Bool = false) -> Row? {
        guard let phone = order.blindPhone?.nilIfBlank,
              EmergencyDialer.telURL(for: phone) != nil else { return nil }
        let masked = EmergencyContactResponse.maskPhone(phone) ?? phone
        return Row(
            id: "phone",
            label: asAction ? nil : VolunteerOrderFlowCopy.phoneLabel,
            value: asAction ? VolunteerOrderFlowCopy.callRunnerRow : masked,
            detail: asAction ? masked : nil,
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
