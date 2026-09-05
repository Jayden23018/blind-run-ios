import Foundation
import CoreLocation
import SwiftUI

// MARK: - Order Display Helpers

/// 以下每个 `case .unknown` 都对应「后端新增了本客户端不认识的订单状态」。
/// 一律走中性、只读、不下结论的分支：让订单继续留在列表里可被刷新，
/// 好过把它当成已结束而从界面上抹掉。
extension RunOrderStatus {
    var isActiveForBlindRunner: Bool {
        switch self {
        case .pendingMatch, .pendingIntroCall, .scheduledConfirmed, .pendingAccept, .inProgress, .driverEnRoute, .driverArrived, .rematching:
            return true
        case .completed, .cancelled, .noVolunteer:
            return false
        case .unknown:
            return true
        }
    }

    /// `.pendingIntroCall` 判 true 而 `.pendingMatch` 判 false：这一态订单**已经锁给了
    /// 这一位志愿者**（后端 `dispatchCurrentVolunteerId`），他有一件必须做的事（表态）。
    ///
    /// ⚠️ 眼下这个分支实际走不到 —— 志愿者在通话期取不到 `OrderDetailResponse`
    /// （`OrderQueryService.getOrder` 只认 `order.volunteer`，通话期恒为 null → 403），
    /// 所以 `activeOrder` 永远不会是这一态，通话页吃的是派单载荷。
    /// 判 true 是取**不把订单从界面上抹掉**这个保守方向，与 `.unknown` 那条同源；
    /// 后端哪天让志愿者读得到这一态的订单详情，这里不必再改一次。
    /// 🚩 `.scheduledConfirmed` 判 **true**：这一态他已经接了单（后端 `occupiesVolunteer()` 也判 true），
    /// 而且有一件**必须做**的事 —— 临期确认「我还会去」。判 false 的直接后果是那张单在志愿者端
    /// 一个入口都没有，60 分钟后被判未确认、订单转走，而他并没有拒绝过。
    ///
    /// ⚠️ 但**这条判 true 不等于首页就看得见它**：首页的 `activeOrder` 来自
    /// `dispatch-summary.activeOrders`，而后端 `VolunteerService.loadActiveOrders` 的白名单只有
    /// `IN_PROGRESS` / `DRIVER_EN_ROUTE` / `DRIVER_ARRIVED`。预约单的可见性由
    /// `VolunteerHomeViewModel.scheduledOrders`（单独打 `GET /api/orders/mine`）承担，
    /// 不要以为改了这个谓词就够了。
    var isActiveForVolunteer: Bool {
        switch self {
        case .pendingIntroCall, .scheduledConfirmed, .pendingAccept, .driverEnRoute, .driverArrived, .inProgress:
            return true
        case .pendingMatch, .completed, .cancelled, .rematching, .noVolunteer:
            return false
        case .unknown:
            return true
        }
    }

    /// 志愿者能否看到盲人填的**自由文本**（`specialNotes` 特殊说明 / `routeNotes` 路线备注）。
    ///
    /// `AGENTS.md §8`：**接单前隐藏盲人的敏感健康信息。** 自由文本取值空间开放、敏感度无法预判，
    /// 语音下单落地后它装的就是用户原话（「我有低血糖，如果我说头晕请马上停下来」）。
    /// 派单是串行的，接单前展示等于把它交给这一单碰到过的每一个志愿者，包括最后拒单的那些。
    ///
    /// `routeNotes` 2026-08-07 一并收进来（后端已拍板同口径并在适配）。它的产品用途看着无害
    /// （「沿湖边跑道」），但字段类型决定风险、用途不决定：同一个输入框里写「我住院刚出来，
    /// 只能走平路」是完全自然的事，而客户端无法在展示前判断用户写了哪一种。
    ///
    /// 刻意写成穷举 switch 而不是 `!= .pendingMatch`，为的是两件事：
    /// - `.rematching` —— 原志愿者取消后订单回到重新派单，**那个人已经不是参与者了**，
    ///   简写的 `!=` 会把他判成可见。
    /// - `.unknown` —— 后端新增状态时必须**默认不公开**。这一族的其他 helper 对未知值取
    ///   「保守地当作进行中」，那是为了不让订单从界面上消失；隐私边界的保守方向相反，是关。
    ///
    /// `.pendingAccept` 判为可见，因为它已经在接单**之后**：盲人端该状态的文案是
    /// 「志愿者已接单」，且志愿者此时才拥有取消权（`AGENTS.md §5`）。
    /// 派单弹窗那一刻订单还是 `PENDING_MATCH`。
    ///
    /// 结构化条件（配速 / 路线偏好 / 导盲犬）**不走这条闸**：取值空间封闭（枚举 / 布尔），
    /// 且它们是志愿者判断「我接不接得下来」的依据，藏起来只会让人盲接、接了再取消。
    ///
    /// `.pendingIntroCall` 判为**不可见**：通话发生在接单**之前**，而派单是串行的 ——
    /// 一单最多聊 3 位候选人，展示等于把这段自由文本交给这一单碰到的每一个人，包括
    /// 最后没聊成的那些。通话本身就是用来替代文字沟通的，要问什么当面（电话里）问。
    /// `.scheduledConfirmed` 判为**可见**：它在接单**之后**（后端 `order.volunteer` 已落库，
    /// `allowsCounterpartCall()` 已经双向下发明文号），与 `.pendingAccept` 同档。
    /// 判据是「有几个陌生人拿得到」，不是「拿到多少天」—— 这一态志愿者已**唯一确定**，
    /// 与 `.pendingIntroCall`（一单最多聊 3 位候选人）性质不同。
    /// **代价照说**：自由文本的暴露窗口从几小时变成 1–7 天。接受它的前提与后端下发号码同一条：
    /// 订单一终结即失效，且盲人可随时取消把它收回。
    var disclosesBlindRunnerNotesToVolunteer: Bool {
        switch self {
        case .scheduledConfirmed, .pendingAccept, .driverEnRoute, .driverArrived, .inProgress, .completed, .cancelled:
            return true
        case .pendingMatch, .pendingIntroCall, .rematching, .noVolunteer:
            return false
        case .unknown:
            return false
        }
    }

    /// 盲人端订单页该不该给出「打电话给志愿者」的主按钮。
    ///
    /// 陪跑没有车牌 / 车型 / 颜色，视障者确认「眼前这个人是不是我的志愿者」的唯一手段就是这通电话
    /// （依据见 `docs/research/blind-ui-visual-benchmark-20260808.md` §3.2）。所以凡是需要**当面汇合**
    /// 的状态都要给，且要给成主按钮而不是一行文字。
    ///
    /// 终态一律不给：订单结束后 `volunteerPhone` 可能还在响应里，但那时候摆一个占半屏的拨号按钮
    /// 是在诱导盲人打一通没有理由的电话。
    ///
    /// 写成穷举 switch 而不是集合字面量：后端往枚举加值时编译器会在这里逼一次决策，
    /// 而集合字面量会默默把新状态判成 false。
    ///
    /// 🚨 `.pendingIntroCall` 判 **false**，尽管那一态盲人确实要打一通电话。
    /// 这条属性控制的是**双向下发号码的老路径**（号码来自 `OrderDetailResponse.volunteerPhone`，
    /// 接单后两边都拿得到对方明文号）。通话磨合走的是**单向**专用接口
    /// `GET /api/orders/{id}/intro-call` —— 只有盲人拿得到能拨通的明文号，志愿者只拿到掩码串。
    /// 混用会让两条路径的号码来源、可见方向和状态集全部搅在一起。
    /// 那一态的拨号入口在 `BlindIntroCallView`（独立页，2026-09-05 从订单状态页提出来）。
    ///
    /// 🚩 `.scheduledConfirmed` 判 **true**，而它并不需要「当面汇合」—— 这是本谓词唯一一处例外，
    /// 与后端 `OrderStatus.allowsCounterpartCall()` 上那段逐字对应：跨天单在开跑前 1–7 天就定了人，
    /// 这期间改期 / 改地点必须联系得上对方，联系不上就只能取消重派，而重派抢不回同一个人。
    /// 泄露面与 `.pendingAccept` 相同（志愿者已唯一确定），订单一终结即失效。
    /// ⚠️ **漏了这一行的症状是跨天单里拨号按钮不出现，且不会有任何报错。**
    var offersVolunteerCall: Bool {
        switch self {
        case .scheduledConfirmed, .pendingAccept, .driverEnRoute, .driverArrived, .inProgress:
            return true
        // 还没有志愿者，或那个志愿者已经不是本单参与者（`REMATCHING` 是他取消后进入的状态）。
        case .pendingMatch, .pendingIntroCall, .rematching, .noVolunteer:
            return false
        case .completed, .cancelled:
            return false
        // 状态未知时落到只读跟踪页，不提供任何会产生外呼的动作。
        case .unknown:
            return false
        }
    }

    /// 盲人端订单页该不该给出「把这次行程告诉家人」。
    ///
    /// United In Stride 把**开始时间 / 集合地点 / 路线 / 结束时间**列为陪跑出发前必须约定的
    /// 四要素（`docs/research/blind-app-feature-landscape-20260812.md` §2.2）。在这条动作
    /// 存在之前，家属唯一会被触达的时机是 SOS 之后 —— 也就是说，跑步正常进行的全程，
    /// 家里人根本不知道这件事在发生。
    ///
    /// **非终态全给**，与后端 `POST /api/orders/{id}/share` 的口径一致
    /// （2026-08-13 后端通报：非终态都允许分享，含 `PENDING_MATCH` —— 家属看到
    /// 「正在找志愿者」也是有意义的）。初版曾把 `PENDING_MATCH` 排除在外，理由是
    /// 「订单可能被自动取消，家属拿到会失效的信息」；那条理由不成立：链接是幂等的，
    /// 订单取消后家属看到的是 `410`（曾经有效但已结束），不是一条无限期的坏链接。
    ///
    /// 终态一律不给，而且是**隐藏不是禁用**：后端对终态返 409
    /// `SHARE_ORDER_ALREADY_FINISHED`，摆一个按下去必然报错的按钮，对读屏用户是纯噪音。
    ///
    /// 状态集与 `offersVolunteerCall` 不同，且是各自独立的产品判断：那条是「要不要当面
    /// 确认志愿者身份」（只在需要汇合的四态），这条是「有没有一个还在进行的行程」。
    /// 合并成一个属性会让将来任一侧改状态集时静默带偏另一侧。
    ///
    /// 同样写成穷举 switch：后端往枚举加值时编译器在这里逼一次决策。
    var offersRunPlanShare: Bool {
        switch self {
        // `.scheduledConfirmed` 在列：非终态，后端 `POST /share` 照常受理。
        // 而且跨天单恰恰是最该告诉家人的一种 —— 那是一件几天后要发生、需要家里人也知道的事。
        case .pendingMatch, .pendingIntroCall, .scheduledConfirmed, .pendingAccept, .driverEnRoute, .driverArrived, .inProgress, .rematching:
            return true
        // 终态：没有还在进行的行程可分享。`NO_VOLUNTEER` 是后端明写的预留终态
        // （`OrderStatus.java:46`），归在这一组。
        case .completed, .cancelled, .noVolunteer:
            return false
        // 未知状态不给：分不清是不是终态，而猜错的代价是让盲人按下一个必然 409 的按钮。
        case .unknown:
            return false
        }
    }

    /// 等待期延长窗口该打哪个端点；`nil` 表示本状态没有这个动作。
    ///
    /// 后端在订单长时间无人接单时推 `ORDER_CANCELLATION_WARNING`，正文逐字是
    /// 「您的订单即将因长时间无人接单被取消，**点击继续等待可延长**」。在这条动作存在之前，
    /// 盲人听到那句话、屏幕上没有对应的控件，能做的只有等订单被自动取消再重下一单。
    ///
    /// 两个端点的前置状态**互斥**（后端 `OrderLifecycleService.keepWaiting` 只收 `PENDING_MATCH`，
    /// `keepRematching` 只收 `REMATCHING`，其余一律 409 `ORDER_STATUS_NOT_ALLOWED`）。
    /// 所以这里返回的是「**该打哪一个**」而不是「能不能打」——
    /// 判定与选路合成一处，`offersKeepWaiting` 为真却没有端点这种状态在结构上就不存在。
    ///
    /// 同 `offersVolunteerCall` 写成穷举 switch：后端加状态时编译器逼一次决策，
    /// 集合字面量会把新状态默默判成「没有这个动作」——那正是「点了没反应」的来源。
    var keepWaitingEndpoint: KeepWaitingEndpoint? {
        switch self {
        case .pendingMatch:
            return .keepWaiting
        case .rematching:
            return .keepRematching
        // 已经有志愿者了，等待窗口不再是这一单的问题。
        // `.pendingIntroCall` 同样是 nil，但理由不同：后端 `keepWaiting` 只收 `PENDING_MATCH`、
        // `keepRematching` 只收 `REMATCHING`，通话态两条都会 409；而且通话窗口有自己的
        // 20 分钟计时，不由「继续等待」延长。
        // `.scheduledConfirmed` 同样 nil：那两个端点只收 `PENDING_MATCH` / `REMATCHING`，
        // 而且这一态根本不在等人 —— 志愿者已经定了，等的是时间到。
        case .pendingIntroCall, .scheduledConfirmed, .pendingAccept, .driverEnRoute, .driverArrived, .inProgress:
            return nil
        // `NO_VOLUNTEER` 是**终态**（后端 `OrderStatus.java:46`「预留终态」、
        // `DispatchService.java:574`），两个端点都会拒。可恢复的窗口在走到它**之前**。
        case .completed, .cancelled, .noVolunteer:
            return nil
        case .unknown:
            return nil
        }
    }

    /// 盲人端订单页该不该给出「继续等待」。派生自 `keepWaitingEndpoint`，不另写一遍 switch。
    var offersKeepWaiting: Bool {
        keepWaitingEndpoint != nil
    }
}

/// 两条延长端点。存在的理由是 `scripts/validate-spec-coverage.mjs`：
/// 它扫源码里的接口路径**字符串字面量**，逐条对撞后端契约。若把路径拼成
/// 「订单前缀 + 订单号 + **变量**后缀」，两段插值都会被归一成 `{param}`，
/// 得到一条契约里不存在的路径，于是这两个端点对门禁**彻底隐形** ——
/// 而门禁存在的全部意义就是拦住「前端在调后端没有的路径」。
///
/// 所以完整路径必须在这里写成字面量（连注释里也不能出现示例路径，同样会被扫到）。
/// 两个 case 的 switch 由编译器保证穷举，与上面那个按状态选路的 switch 不会各自漂移。
enum KeepWaitingEndpoint {
    case keepWaiting
    case keepRematching

    /// ⚠️ 这两条都是 `PUT`（`api_spec.yaml:236` / `:256`），
    /// 与其余走 `POST` 的订单状态流转端点不同族。
    func path(orderId: Int64) -> String {
        switch self {
        case .keepWaiting:
            return "/api/orders/\(orderId)/keep-waiting"
        case .keepRematching:
            return "/api/orders/\(orderId)/keep-rematching"
        }
    }
}

extension RunOrderStatus {

    /// 「志愿者离出发地点还有多远」这个数字对本状态有没有意义。
    ///
    /// 汇合前的三态才有：`IN_PROGRESS` 时两人已经在一起，念距离是噪音；派单中 / 重新匹配时
    /// 根本没有志愿者；终态更没有。语音查距离（`VoiceStatusQuery`）与状态页的距离刷新
    /// （`BlindOrderStatusViewModel.refreshVolunteerDistance`）共用这一处判定 ——
    /// 此前这个三元组在状态页里抄了两遍，再加语音入口就是第三遍。
    ///
    /// 同 `offersVolunteerCall` 写成穷举 switch：后端加状态时编译器逼一次决策。
    var offersVolunteerDistanceToStart: Bool {
        switch self {
        case .pendingAccept, .driverEnRoute, .driverArrived:
            return true
        // `.pendingIntroCall` 还没有志愿者接单，后端也不会为这一态下发对方位置。
        // `.scheduledConfirmed` 有志愿者但**后端同样不下发位置**（`sharesLiveLocation()` 判 false）：
        // 距开跑 1–7 天，那个距离既无意义、也拿不到数据。判 true 只会念一个永远算不出来的数字。
        case .pendingMatch, .pendingIntroCall, .scheduledConfirmed, .rematching, .noVolunteer, .inProgress, .completed, .cancelled:
            return false
        case .unknown:
            return false
        }
    }

    /// 「已等待 12 分钟」这个数字对本状态有没有意义。
    ///
    /// 状态卡上恒定只给**一个**数字（`docs/research/blind-ui-visual-benchmark-20260808.md` §3.2
    /// 的「一个数字」列）：还在等人时是等了多久，有人了是志愿者距离，跑起来了是约定结束时间。
    /// 三者的状态集互不相交，所以卡上不会同时冒出两个数。
    ///
    /// 状态集与 `offersKeepWaiting` 恰好相同，**但不复用它**：那条问的是「还能不能延长窗口」
    /// （延长次数用完后按钮收起，人却还在等），这条问的是「等了多久」。合成一处会让
    /// 上限逻辑一改就把数字一起弄没 —— 而那正是最该看到自己等了多久的时刻。
    ///
    /// 同族其余判定一样写成穷举 switch：后端往枚举加值时编译器在这里逼一次决策。
    var offersWaitedDuration: Bool {
        switch self {
        case .pendingMatch, .rematching:
            return true
        // 已经有志愿者了，这一格的数字换成距离 / 约定结束时间。
        // `.pendingIntroCall` 也不给：那一刻用户不是在等，是有一件该做的事（打这通电话），
        // 状态卡下面紧跟的就是拨号按钮，再摆一个「已等待 N 分钟」是在催他等。
        // `.scheduledConfirmed` 也不给：人已经定了，「已等待 N 分钟」在这一态是纯噪音，
        // 而且它的锚点是 `createdAt`，跨天单一开口就是「已等待 30 小时」——吓人且不能让人做任何事。
        case .pendingIntroCall, .scheduledConfirmed, .pendingAccept, .driverEnRoute, .driverArrived, .inProgress:
            return false
        // 终态：一个还在走的秒表只会让人以为事情还没结束。
        case .completed, .cancelled, .noVolunteer:
            return false
        case .unknown:
            return false
        }
    }

    var blindRunnerDescription: String {
        switch self {
        case .pendingMatch:
            return "系统正在派单，请稍候。"
        // 🚨 不提「第几位」「换了一位」「重新」——「无声拒绝」要求盲人无从得知自己被谁拒过。
        // 让他看到「第 3 位志愿者拒绝了你」，这个功能就从降低求助心理成本变成制造挫败。
        case .pendingIntroCall:
            return "有位志愿者想陪你跑。先打个电话聊聊，双方都觉得合适就算约好了。"
        // 🚨 **不提临期闸门**：「他要在出发前确认，不确认就换人」是后端的内部机制，
        // 说出来只会让盲人在接下来的几天里替一件自己无法影响的事担心。真换了人他会收到
        // `SCHEDULED_DEPARTURE_GATE_MISSED`，那时再说不迟。
        // 也**不写具体提前多久确认** —— 那是后端配置（`departure-confirm-window-minutes`），
        // 写死就是编一个数字念给盲人听，同 `KeepWaitingCopy` 那条。
        case .scheduledConfirmed:
            return "已经为你约好志愿者。到出发前如果计划有变，可以打电话告诉他。"
        case .pendingAccept:
            return "志愿者已接单，请按预约时间前往或等待在出发地点。"
        case .inProgress:
            return "服务已开始，请注意安全。"
        case .driverEnRoute:
            return "志愿者已出发，正在前往出发地点。"
        case .driverArrived:
            return arrivedWaitingCopy
        case .completed:
            return "服务已完成，感谢使用助盲跑。"
        case .cancelled:
            return "本次预约已取消。"
        case .rematching:
            return "正在确认志愿者状态，请稍候；如需更换志愿者，系统会继续处理。"
        // 终态。这条在语音查询里跟在 `displayName`（「暂无志愿者」）后面念
        // （`VoiceStatusQuery.swift:131`），所以不再重复「没有志愿者」，直接说结果与出路。
        case .noVolunteer:
            return "本次预约已取消，因为没有匹配到可用的志愿者。你可以重新发起一次预约。"
        case .unknown:
            return "订单状态有更新，请刷新页面或稍后重试。"
        }
    }

    var blindRunnerAnnouncement: String {
        switch self {
        case .pendingMatch:
            return "订单提交成功，系统正在为你派单。"
        // 与 `blindRunnerDescription` 同一条无声拒绝口径：不出现轮次、不出现「换」。
        case .pendingIntroCall:
            return "有位志愿者想陪你跑，可以打个电话聊聊。"
        // 与 `blindRunnerDescription` 同一条口径：不提闸门、不写具体提前量。
        case .scheduledConfirmed:
            return "已经为你约好志愿者。到出发前如果计划有变，可以打电话告诉他。"
        case .pendingAccept:
            return "志愿者已接单，请前往或等待在预约出发地点。"
        case .inProgress:
            return "服务已开始，请注意安全。"
        case .driverEnRoute:
            return "志愿者已出发，正在前往出发地点。"
        case .driverArrived:
            return "志愿者已到达约定地点，等待志愿者开始服务。"
        case .completed:
            return "服务已完成，感谢使用助盲跑。"
        case .cancelled:
            return "本次预约已取消。"
        case .rematching:
            return "正在确认志愿者状态，请稍候。"
        // 与 `SpeechService.statusAnnouncement` 逐字相同 —— 两者都是「状态刚变成这个」时的
        // 独立播报，语境没有区别（同 `.rematching` / `.cancelled` 等状态的既有写法）。
        case .noVolunteer:
            return "没有匹配到志愿者，本次预约已取消，你可以重新发起一次。"
        case .unknown:
            return "订单状态有更新，请刷新页面或稍后重试。"
        }
    }

    var statusSymbolName: String {
        switch self {
        case .pendingMatch:
            return "clock.arrow.circlepath"
        case .pendingIntroCall:
            return "phone.circle.fill"
        // `calendar.badge.clock` 是 iOS 15.0+，部署目标 16 够用，不需要 `#available`。
        case .scheduledConfirmed:
            return "calendar.badge.clock"
        case .pendingAccept:
            return "person.crop.circle.badge.questionmark"
        case .inProgress:
            return "checkmark.circle.fill"
        case .driverEnRoute:
            return "figure.walk.circle.fill"
        case .driverArrived:
            return "bell.circle.fill"
        case .completed:
            return "checkmark.seal.fill"
        case .cancelled:
            return "xmark.circle.fill"
        case .rematching:
            return "arrow.triangle.2.circlepath"
        case .noVolunteer:
            return "person.slash.fill"
        case .unknown:
            return "questionmark.circle"
        }
    }

    var statusColor: Color {
        switch self {
        // `.scheduledConfirmed` 与 `.pendingAccept` 同档：两者对盲人是同一件事 ——
        // 人已经定了、在等一个约定的时刻到来。给 `primary`（那一档的含义是「等着用户做一件事」）
        // 会误导盲人以为自己有待办，而这一态他什么都不用做。
        case .pendingMatch, .scheduledConfirmed, .pendingAccept, .rematching:
            return AppColors.warning
        case .inProgress, .driverEnRoute, .completed:
            return AppColors.success
        // 与 `.driverArrived` 同一档：这两态的共同点是**等着用户做一件事**，
        // 而不是等系统。等待色（warning）会让人以为还是干等着。
        case .pendingIntroCall, .driverArrived:
            return AppColors.primary
        case .cancelled, .noVolunteer:
            return AppColors.textSecondary
        case .unknown:
            return AppColors.textSecondary
        }
    }
}

// MARK: - Keep Waiting Copy

/// 「继续等待」的全部对外文案。集中一处是为了让它们能被测试逐条钉住 ——
/// 这里每一句的措辞都有约束，散在 view 和 view model 里就只能靠人记。
enum KeepWaitingCopy {
    static let buttonTitle = "继续等待"
    static let accessibilityHint = "告诉系统你还想继续等，避免订单因为长时间没人接单被自动取消"

    /// 成功文案。两条硬约束：
    ///
    /// 1. **进行时，不是完成时。** 后端 200 只回 `{"success": true}`，订单状态不变
    ///    （`PENDING_MATCH` 还是 `PENDING_MATCH`），所以用户唯一的反馈就是这句话。
    /// 2. **不许出现具体时长。** 窗口长度是后端配置（`app.match.max-keep-waiting-count`
    ///    和对应的超时值），客户端读不到。写「已为你延长 10 分钟」就是编一个数字念给盲人听
    ///    —— 与 SOS 那条「不得宣称短信已送达」同一个道理。
    ///    `KeepWaitingCopyTests` 断言本串不含任何阿拉伯数字。
    static let success = "已经告诉系统继续等待，正在继续为你寻找志愿者。"

    /// 上限文案。后端在延长次数用尽后**不再推送** `ORDER_CANCELLATION_WARNING`
    /// （`websocket-protocol.md`：那时文案里的「点击继续等待可延长」已经不成立）。
    /// 客户端对齐同一口径：说清没得延长了，并说明**还能做什么** —— 只说「不能延长」
    /// 会把盲人留在一个没有下一步的地方。
    static let limitReached = "已经到了可以延长的次数上限，不能再延长了。系统还会继续为你匹配；如果不想再等，可以取消订单后重新预约。"

    /// 「重复当前状态」里附带的一句。看不见屏幕的人靠这句发现这个动作存在。
    static let repeatStatusSuffix = "如果还想继续等，可以点继续等待。"
}

// MARK: - Order Detail Helpers

extension OrderDetailResponse {
    var sortKey: String {
        createdAt ?? plannedStart ?? ""
    }

    var startCoordinate: CLLocationCoordinate2D? {
        guard let startLatitude, let startLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: startLatitude, longitude: startLongitude)
    }

    var startAddressForAnnouncement: String {
        startAddress?.nilIfBlank ?? "预约出发地点"
    }

    /// 「结束地点」那一行要显示的文字；`nil` 表示**整行不渲染**。
    ///
    /// 没有终点时返回 `nil` 而不是「未指定」之类的占位：`endAddress == nil` 的语义是
    /// 「用户没说终点」，**不是**「原路返回起点」。摆一行出来，志愿者就会去跟盲人核对
    /// 一个对方从没说过的地点（后端 `websocket-protocol.md:429` 同一条口径）。
    ///
    /// 查不到坐标时把这件事说出来，是因为它改变志愿者的动作：没有坐标就没法导航，
    /// 只能当面问。不标注的话，那一行看起来和有坐标的完全一样。
    var endAddressForDisplay: String? {
        guard let address = endAddress?.nilIfBlank else { return nil }
        return endLatitude == nil ? "\(address)（未定位到）" : address
    }

    var plannedStartForAnnouncement: String? {
        plannedStart?.nilIfBlank?.displayDateTime
    }

    /// 约定的结束时间。
    ///
    /// **取 `plannedEnd`，不许用 `plannedStart + expectedDurationMinutes` 自己推。**
    /// 两个数是后端各自算的，口径不保证一致；推出来的值与订单详情、与家属分享页显示的
    /// 对不上时，同一趟跑步在三个地方有三个结束时间，而没有任何一处会报错。
    /// 契约里 `plannedEnd` 是 required（`api_spec.yaml` 的 `OrderDetailResponse`），
    /// 这里仍收成 optional 只是解码宽容，不是允许缺失时另找一个数顶上 —— 缺了就不显示这一行。
    var plannedEndForAnnouncement: String? {
        plannedEnd?.nilIfBlank?.displayDateTime
    }

    /// 等待态状态卡上的那个数字：「已等待 12 分钟」。
    ///
    /// 锚点是 `createdAt`（下单时刻），**不是**「本轮匹配开始时刻」—— 后者客户端根本拿不到
    /// （`REMATCHING` 的基准是后端的 `lastRematchAt`，订单详情里没有这个字段）。所以这句话
    /// 回答的是「我下单到现在多久了」，对两个等待态都逐字为真，不需要按状态换算法。
    ///
    /// **不许拿它推「还能等多久」**：放弃时刻是 `plannedStart` 减去一个后端配置，且会被
    /// 「继续等待」往后推（后端 `DispatchService.dispatchDeadline`）。那个配置客户端读不到，
    /// 写死任何窗口长度都是假信息 —— 与 `KeepWaitingCopy` 的进行时口径同一条理由。
    ///
    /// ponytail: 超过 24 小时返回 nil。提前一周下的单在派单期确实等了一周（后端创建后几秒
    /// 就开始派），但「已等待 10080 分钟」既吓人又不能让盲人做出任何动作。上限到了就不说，
    /// 不去猜一个「有效等待时间」——猜出来的数没有任何一处能核对。
    func blindRunnerWaitedText(now: Date = Date()) -> String? {
        guard status.offersWaitedDuration,
              let placedAt = createdAt?.nilIfBlank?.backendTimestamp else { return nil }
        let minutes = Int(now.timeIntervalSince(placedAt) / 60)
        switch minutes {
        case ..<1:
            // 「已等待 0 分钟」是噪音，刚下完单的人知道自己刚下完单。负数同理（设备时钟偏了）。
            return nil
        case ..<60:
            return "已等待 \(minutes) 分钟"
        case ..<(24 * 60):
            // 到小时级时那几分钟不再影响任何决定，念出来只是拉长播报。
            return "已等待 \(minutes / 60) 小时"
        default:
            return nil
        }
    }

    func volunteerDistanceToStartText(from volunteerCoordinate: CLLocationCoordinate2D?) -> String? {
        guard let volunteerCoordinate, let startCoordinate else { return nil }
        let meters = DistanceCalculator.distance(from: volunteerCoordinate, to: startCoordinate)
        return "距出发地点约 \(DistanceCalculator.formattedDistance(meters))"
    }

    /// 服务进行中，把约定的结束时间念进主播报。
    ///
    /// 折叠在「预约信息」里等于没有：那一段是 `DisclosureGroup`，读屏用户要先展开才听得到，
    /// 而跑步途中他不会去展开一段标着「已确认的信息」的折叠区。约定结束时间是这段时间里
    /// **唯一会变成安全问题的数字** —— 后端在它之后 15 分钟推 `ORDER_OVERDUE`，
    /// 用户听不到这个约定，就无从判断那条告警是不是意外。
    ///
    /// 只在 `IN_PROGRESS` 加。派单期、汇合期念它没有用：那时还没开始跑，
    /// 而每多一句都是读屏用户在主路径上多等的时间。
    func blindRunnerAnnouncement(distanceText: String? = nil) -> String {
        let distanceSentence = distanceText.map { "志愿者\($0)。" } ?? ""
        switch status {
        case .inProgress:
            guard let plannedEndForAnnouncement else { return status.blindRunnerAnnouncement }
            return "\(status.blindRunnerAnnouncement)预计\(plannedEndForAnnouncement)结束。"
        case .pendingAccept:
            if let plannedStartForAnnouncement {
                return "志愿者已接单。请在\(plannedStartForAnnouncement)前往或等待在出发地点：\(startAddressForAnnouncement)。\(distanceSentence)志愿者出发后会继续通知你。"
            }
            return "志愿者已接单。请前往或等待在出发地点：\(startAddressForAnnouncement)。\(distanceSentence)志愿者出发后会继续通知你。"
        case .driverEnRoute:
            if let distanceText {
                return "志愿者已出发，正在前往出发地点，\(distanceText)。"
            }
            return "志愿者已出发，正在前往出发地点。"
        case .driverArrived:
            return "\(status.blindRunnerAnnouncement)\(distanceSentence)"
        default:
            return status.blindRunnerAnnouncement
        }
    }
}

// MARK: - Escort Needs（志愿者侧「本单为视障跑者」提示位）

/// 志愿者见面前必须知道的一条陪跑要求。
///
/// 存在理由：`visionLevel` / `tetherPreference` 在契约里躺了很久，志愿者端**一处都没展示**
/// （`hasGuideDogThisRun` 也只有订单信息卡里的一行）。数据早就送到了，是前端没给它版位。
/// 对志愿者来说这三项决定的是见面第一个动作 —— 尤其 `tetherPreference`：
/// 该递牵引绳、该让对方挽住手臂、还是只用口令，抓错方式对盲人是实打实的身体风险。
struct EscortNeed: Equatable, Identifiable {
    enum Kind: String, Hashable {
        case guideDog
        case vision
        case tether
        /// 档案里三项都没填。**不是「无要求」** —— 是「不知道」，得当面问。
        case unstated
    }

    let kind: Kind
    let symbolName: String
    let title: String
    let value: String

    var id: Kind { kind }

    /// 认得出字段、但认不出取值时的落点。
    ///
    /// 不念 rawValue（那是内部标识符），也**不静默丢掉这一行**：丢掉等于告诉志愿者
    /// 「跑者没有偏好」，而真实情况是「跑者填了，只是这个版本的 App 不认识」。
    /// 引导方式认错的后果是见面第一下就抓错人。
    static let confirmInPerson = "请当面与跑者确认"

    /// 导盲犬那一行的唯一构造点。
    ///
    /// 抽出来是因为它有**两个**数据源：接单后的 `OrderDetailResponse.hasGuideDogThisRun`，
    /// 以及接单前的派单载荷 `WSNewOrder.hasGuideDog`（通话磨合期志愿者拿不到订单详情，
    /// 后端 `OrderQueryService.getOrder` 只认 `order.volunteer`，那一态它恒为 null → 403）。
    /// 两处各抄一份文案，改一处必漏一处。
    static let guideDogThisRun = EscortNeed(
        kind: .guideDog,
        symbolName: "pawprint.fill",
        title: "导盲犬",
        value: "本次携带，请预留通行空间"
    )
}

extension Array where Element == EscortNeed {
    /// 提示位合成的一句话。读屏把整块当**一个**焦点读，避免逐行滑过时漏掉其中一条。
    var escortNeedsAnnouncement: String {
        (["本单为视障跑者"] + map { "\($0.title)：\($0.value)" }).joined(separator: "。")
    }
}

extension OrderDetailResponse {
    /// 提示位的内容。**空数组 = 整块不渲染。**
    ///
    /// 可见性逐字段判，不是一刀切：
    /// - `hasGuideDogThisRun` **不走** `disclosesBlindRunnerNotesToVolunteer` 闸 —— 它在
    ///   `AvailableOrderResponse` 与 `WSNewOrder` 里本来就下发给还没接单的志愿者
    ///   （取值空间封闭，且是「我接不接得下来」的判据，见那两处的契约说明）。
    /// - `visionLevel` / `tetherPreference` **走闸**：`AGENTS.md §8` 要求接单前隐藏敏感健康信息，
    ///   而视力程度就是其中最直接的一项。闸的判据（含 `.rematching` 与 `.unknown` 默认关）
    ///   复用 `disclosesBlindRunnerNotesToVolunteer`，不在这里就地写 `!= .pendingMatch`。
    ///
    /// ⚠️ 眼下**接单前拿不到**这两个字段：派单弹窗吃的是 `WSNewOrder`，它只有
    /// `pacePreference` / `hasGuideDog`。所以这道闸此刻拦不到任何东西，它防的是
    /// 「以后有人把一份接单前的 `OrderDetailResponse` 喂进这个视图」。
    /// 让后端在派单载荷里补这两项的请求已进 handoff。
    ///
    /// 通话磨合（`.pendingIntroCall`）同理，且更彻底：那一态志愿者连 `OrderDetailResponse`
    /// 都取不到（`OrderQueryService.getOrder` 只认 `order.volunteer`，通话期它是 null → 403），
    /// 所以志愿者侧通话页走的是 `WSNewOrder.escortNeeds` —— 只剩导盲犬那一行。
    ///
    /// ⚠️ 闸关着时**「跑者没有填写」那条兜底也不会出现**（它在 `guard` 之后）。
    /// 这是有意保留的既有行为：接单前把「后端没给我」说成「跑者没填」是另一种误导，
    /// 而 `EscortNeedsTests.testHidesHealthFieldsAfterTheVolunteerDroppedOut` 逐字钉着空数组。
    var escortNeeds: [EscortNeed] {
        var needs: [EscortNeed] = []

        if hasGuideDogThisRun == true {
            needs.append(.guideDogThisRun)
        }

        guard status.disclosesBlindRunnerNotesToVolunteer else { return needs }

        if let raw = visionLevel?.nilIfBlank {
            needs.append(EscortNeed(
                kind: .vision,
                symbolName: "eye.slash",
                title: "视力情况",
                value: VisionLevel(rawValue: raw)?.displayName ?? EscortNeed.confirmInPerson
            ))
        }

        if let raw = tetherPreference?.nilIfBlank {
            needs.append(EscortNeed(
                kind: .tether,
                symbolName: "link",
                title: "引导方式",
                value: TetherPreference(rawValue: raw)?.displayName ?? EscortNeed.confirmInPerson
            ))
        }

        // 两项都没有 ≠ 没有要求。档案不全时志愿者更需要被提醒去问，而不是看到一片空白
        // 然后自己猜一种带法。
        if !needs.contains(where: { $0.kind == .vision || $0.kind == .tether }) {
            needs.append(EscortNeed(
                kind: .unstated,
                symbolName: "questionmark.circle",
                title: "引导方式",
                value: "跑者没有填写，出发前请当面问清楚怎么带"
            ))
        }

        return needs
    }

    /// 提示位合成的一句话。读屏把整块当**一个**焦点读，避免逐行滑过时漏掉其中一条。
    var escortNeedsAnnouncement: String {
        escortNeeds.escortNeedsAnnouncement
    }
}

extension WSNewOrder {
    /// 接单**前**能给志愿者看的陪跑要求 —— 只有导盲犬那一行。
    ///
    /// 派单载荷刻意只带取值空间封闭的字段（`pacePreference` / `hasGuideDog`），
    /// 自由文本与 `visionLevel` / `tetherPreference` 都不在其中（见 `WSNewOrder` 的类型注释
    /// 与 `AGENTS.md §8`）。所以这里**没有闸可判**：能给的就这一条，判据在数据源上，
    /// 不在状态上。
    ///
    /// 用在通话磨合页（`VolunteerIntroCallView`）：那一刻志愿者取不到 `OrderDetailResponse`
    /// （后端 `OrderQueryService.getOrder` 只认 `order.volunteer`，通话期恒为 null → 403）。
    var escortNeeds: [EscortNeed] {
        hasGuideDog == true ? [.guideDogThisRun] : []
    }
}

// MARK: - String Helpers

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfBlank: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
    }

    /// 后端 `LocalDateTime` 的无时区时间串（`2026-08-04T11:40:42`），**可能带小数秒**
    /// （`2026-08-04T11:40:42.644571`）。凡是取自 `now()` 且没经过 DB round-trip 的字段都会带 ——
    /// 下单回执的 `createdAt` 一定带，`acceptedAt` / `recordedAt` / `triggeredAt` 同理
    /// （handoff 2026-08-04 后端实测）。
    ///
    /// 小数位数不固定（尾零被丢弃），所以不另配一个 `.SSSSSS` 格式器，直接截掉小数部分 ——
    /// 秒以下精度对展示和预约时间都没有意义。**但带时区偏移的串不能这么截**
    /// （`...42.644+08:00` 截完会差好几个小时），所以要求小数点后必须全是数字，
    /// 带偏移的交给调用方的 ISO8601 分支。
    var backendLocalDate: Date? {
        let formatter = DateFormatter.aidRunBackendLocalDateTime
        if let date = formatter.date(from: self) { return date }
        let parts = split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[1].isEmpty, parts[1].allSatisfy(\.isNumber) else { return nil }
        return formatter.date(from: String(parts[0]))
    }

    /// 后端时间戳 → `Date`，三种形状依次试：无偏移的 `LocalDateTime`（后端默认形状）、
    /// 带小数秒的 ISO-8601、不带小数秒的 ISO-8601。
    ///
    /// 抽出来是给**要算时间差**的调用方用的（`blindRunnerWaitedText`）。此前这条链只长在
    /// `displayDateTime` 里，于是任何要算差值的地方都得自己再写一遍解析 ——
    /// `BlindOrderStatusViewModel.parseISO8601` 就是那样来的，它只认第三种形状。
    var backendTimestamp: Date? {
        backendLocalDate
            ?? ISO8601DateFormatter.aidRunFormatter.date(from: self)
            ?? ISO8601DateFormatter().date(from: self)
    }

    var displayDateTime: String {
        guard let date = backendTimestamp else { return self }
        return DateFormatter.aidRunDisplayDateTime.string(from: date)
    }
}

extension ISO8601DateFormatter {
    static let aidRunFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

extension DateFormatter {
    static let aidRunBackendLocalDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    static let aidRunDisplayDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter
    }()

    /// 只到天，用于把列表按日期分节（积分明细）。与上面那个共用一套 locale 与写法，
    /// 不另起一个 `zh_Hans` 之类的标识符 —— 两个格式器给出不同的月份写法会很难发现。
    static let aidRunDisplayDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()
}
