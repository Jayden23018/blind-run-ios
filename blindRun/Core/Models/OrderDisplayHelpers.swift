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

    /// 这一单**已经动起来了**吗 —— 也就是「计划开始时刻还有没有参考价值」。
    ///
    /// 用途是首页深蓝卡的两处文案（`BlindHomeOrderCard`）：
    /// - 判 false ⇒ 小字念「下一次陪跑，{状态}」，大字念相对日期时间
    /// - 判 true  ⇒ 小字只念状态，大字也只念状态
    ///
    /// **为什么需要这条**：设计稿只画了 `SCHEDULED_CONFIRMED` 一态，而首页那张卡要覆盖
    /// `isActiveForBlindRunner` 的全部 8 个状态。陪跑进行中时念「下一次陪跑，进行中」
    /// 是把正在发生的事说成未来，而 52pt 的大字会显示一个**已经过去**的计划开始时刻
    /// —— 那是这一屏最大的位置，给了一个用户此刻完全不需要的数字。
    ///
    /// 穷举 switch 而不是集合字面量：后端加状态时编译器逼一次决策。
    /// 集合字面量会把新状态默默判成 false，而那正是「把进行中的单说成下一次」的来源。
    var isUnderwayForBlindRunner: Bool {
        switch self {
        // 志愿者真的动身了（`/en-route`，与只回答「你还去吗」的 `/confirm-departure`
        // 不是一回事）之后，这一单就不再是「下一次」了。
        case .driverEnRoute, .driverArrived, .inProgress:
            return true
        // 这几态人还没出发，计划开始时刻仍然是用户最想知道的那个数。
        case .pendingMatch, .pendingIntroCall, .scheduledConfirmed, .pendingAccept, .rematching:
            return false
        // 终态永远到不了这张卡（`isActiveForBlindRunner` 已经把它们排除），
        // 判 false 只是为了让 switch 穷举。
        case .completed, .cancelled, .noVolunteer:
            return false
        // 判 **false**：不知道它是哪一档时，宁可保留时间那一行。
        // 时间是确定有的信息，而「下一次」这个措辞最坏情况只是不精确；
        // 反过来判 true 会把一个还没开始的单的时间从屏幕上抹掉，那是丢信息。
        case .unknown:
            return false
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

    /// 屏幕上**真的有**「继续等待」这个控件吗。
    ///
    /// 🔴 **它与 `offersKeepWaiting` 刻意不同，差的就是 `PENDING_MATCH`。**
    /// 后端两个端点都还在、`PENDING_MATCH` 照样受理 `keepWaiting`（所以
    /// `keepWaitingEndpoint` 一行没改，那条回答的是契约事实）；但项目负责人 2026-09-16
    /// 拍板**删掉 `PENDING_MATCH` 的按钮**：后端 `handleMatchTimeout:578` 每轮超时自己就把
    /// 窗口往后推，客户端一次不调订单寿命相同 —— 一个按了等于没按的按钮，对看不见屏幕的人
    /// 是一次白跑的操作。`REMATCHING` 那一侧保留，它是**真延长**（后端 N62 把
    /// `rematchNotifyAt` 计进 `dispatchDeadline`）。
    ///
    /// 🚩 **凡是「要不要提到这个按钮」的地方都必须读这一条，不许各写一个 `== .rematching`。**
    /// 三处读它：骨架的主按钮、`repeatStatus` 那句附带播报、以及后端
    /// `ORDER_CANCELLATION_WARNING` 正文的客户端覆盖判据。散成三个字面量的下场是
    /// 记忆 `same-name-predicate-different-sets-across-ends`：某一处改了口径，
    /// 另外两处继续念一个不存在的按钮，而那不会有任何东西报错。
    var offersBlindRunnerKeepWaitingControl: Bool {
        keepWaitingEndpoint == .keepRematching
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

    /// 后端**会不会**给这一态下发志愿者位置 —— 也就是「要不要去取」。
    ///
    /// 与后端 `RunOrderStatus.sharesLiveLocation()` 逐态对齐：`DRIVER_EN_ROUTE` /
    /// `DRIVER_ARRIVED` / `IN_PROGRESS`。**这三态不由我们定，是后端定的**，
    /// 所以这条属性的唯一职责就是照抄它，改动前先去看后端那个方法。
    ///
    /// 🚨 **和「念不念距离」是两件事，2026-08-24 后端点名要求拆开**（handoff 08-19 那条）。
    /// 从前合成一个判据，两头都错：
    /// - `PENDING_ACCEPT` 在我们这边判 true ⇒ 订单页每 5 秒轮询就白打一次
    ///   `GET /api/blind/volunteer-location`，而后端在这一态恒不下发。
    /// - `IN_PROGRESS` 在我们这边判 false ⇒ 后端明明给（契约里还有回归门
    ///   `OrderTrackTest#volunteerLocationFallback_worksDuringInProgress`），我们**根本不调**，
    ///   于是陪跑途中 WebSocket 一断，走散检测就没有任何兜底来源。
    ///
    /// 拆成两条之后，后端将来往 `sharesLiveLocation()` 加态时只有这一处要跟，
    /// 播报口径不会被顺带改掉。
    ///
    /// 同族其余判定一样写成穷举 switch：后端加状态时编译器逼一次决策。
    var fetchesVolunteerLocation: Bool {
        switch self {
        case .driverEnRoute, .driverArrived, .inProgress:
            return true
        // 还没有志愿者（派单中 / 通话磨合 / 重新匹配），或那个人已经不是参与者，或已终态。
        // `.scheduledConfirmed` 有志愿者，但后端 `sharesLiveLocation()` 同样不含它 ——
        // 距开跑 1–7 天，那一段没有位置可取，调了只会拿到 404。
        case .pendingMatch, .pendingIntroCall, .pendingAccept, .scheduledConfirmed,
             .rematching, .noVolunteer, .completed, .cancelled:
            return false
        case .unknown:
            return false
        }
    }

    /// 「志愿者离出发地点还有多远」这个数字对本状态有没有意义 —— 也就是「要不要念」。
    ///
    /// 只有**正在赶来**的两态才有：`IN_PROGRESS` 时两人已经在一起，念距离是噪音；
    /// `PENDING_ACCEPT` 时志愿者接了单但还没出发，后端不下发他的位置，
    /// 这条从前判 true 只是让那句话恒定念不出来（`volunteerDistanceToStartText` 恒为 nil）；
    /// 派单中 / 重新匹配根本没有志愿者；终态更没有。
    ///
    /// 语音查距离（`VoiceStatusQuery`）与状态页的距离刷新
    /// （`BlindOrderStatusViewModel.refreshVolunteerDistance`）共用这一处判定。
    ///
    /// 取位置走上面的 `fetchesVolunteerLocation`，**两条不许合回一个**，
    /// 理由写在那条属性的注释里。
    var offersVolunteerDistanceToStart: Bool {
        switch self {
        case .driverEnRoute, .driverArrived:
            return true
        // `.pendingIntroCall` 还没有志愿者接单，后端也不会为这一态下发对方位置。
        // `.pendingAccept` 有志愿者了，但后端 `sharesLiveLocation()` **不含这一态** ——
        // 判 true 的那段时间里客户端每 5 秒白调一次而后端恒 404，念不出任何数字。
        // `.scheduledConfirmed` 同理有志愿者而后端不下发位置：距开跑 1–7 天，
        // 那个距离既无意义、也拿不到数据。判 true 只会念一个永远算不出来的数字。
        case .pendingMatch, .pendingIntroCall, .pendingAccept, .scheduledConfirmed,
             .rematching, .noVolunteer, .inProgress, .completed, .cancelled:
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

    /// 盲人端订单页该不该给出「匹配规则说明」入口。
    ///
    /// 《互联网信息服务算法推荐管理规定》**第十六条**要求「以显著方式告知用户其提供算法推荐服务的情况」。
    /// 告知落在**正在被算法排序的那一刻**：用户此刻正在经历这件事，比塞进设置页深处显著得多。
    ///
    /// 状态集与 `offersKeepWaiting` / `offersWaitedDuration` 恰好相同，**但同样不复用它们**
    /// （理由见上面 `offersWaitedDuration` 那段）：那两条问的是「还能不能延长窗口」「等了多久」，
    /// 这条问的是「此刻有没有算法在替你排序」。合并会让任意一条的口径变化把另外两条一起改掉。
    ///
    /// 同族其余判定一样写成穷举 switch：后端往枚举加值时编译器在这里逼一次决策。
    var offersDispatchAlgorithmNotice: Bool {
        switch self {
        case .pendingMatch, .rematching:
            return true
        // 人已经定下来了，排序在更早的时候就发生完了。此刻再给一个「匹配规则说明」，
        // 对读屏用户是在他该打电话 / 该准备出门的时候多插一条与当下无关的信息。
        case .pendingIntroCall, .scheduledConfirmed, .pendingAccept, .driverEnRoute, .driverArrived, .inProgress:
            return false
        // 终态：这一单的排序已经结束或从未发生，摆着是纯噪音。
        // ⚠️ `.noVolunteer` 也判 false —— 三轮都没人接时用户要的是「接下来怎么办」，
        // 把算法说明摆在这一刻，读起来像在解释为什么没人来，那不是它的用途。
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

    /// 「没有可按的按钮时，还能做什么」。三处共用一句，**不许各写一份**：
    /// 三处说的是同一件事，分开写就会慢慢漂成三种说法，而它们只在等待期被念到，
    /// 谁漂了都没有任何东西会报错。
    static let stillMatchingAdvice = "系统还会继续为你匹配；如果不想再等，可以取消订单后重新预约。"

    /// 上限文案。后端在延长次数用尽后**不再推送** `ORDER_CANCELLATION_WARNING`
    /// （`websocket-protocol.md`：那时文案里的「点击继续等待可延长」已经不成立）。
    /// 客户端对齐同一口径：说清没得延长了，并说明**还能做什么** —— 只说「不能延长」
    /// 会把盲人留在一个没有下一步的地方。
    static let limitReached = "已经到了可以延长的次数上限，不能再延长了。" + stillMatchingAdvice

    /// 后端 `ORDER_CANCELLATION_WARNING` 正文的**客户端替代**。
    ///
    /// 后端模板逐字是「您的订单即将因长时间无人接单被取消，**点击继续等待可延长**」
    /// （`demo/src/main/resources/data.sql:146`）。同一个 eventType 在后端有三个推送点
    /// （`DispatchService:1265` 派单窗口将到、`OrderLifecycleService:573` 匹配超时、
    /// `:526` 重匹超时），覆盖 `PENDING_MATCH` 与 `REMATCHING` 两态 —— 而
    /// `PENDING_MATCH` 那个按钮已按 2026-09-16 的决策删除
    /// （`offersBlindRunnerKeepWaitingControl`）。照播就是让盲人去找一个不存在的控件。
    ///
    /// 🔴 **这一句不提任何按钮。** 它只在「按钮确实不在屏幕上」时替换正文；
    /// `REMATCHING` 那一侧按钮还在，原文准确，一个字不改。
    ///
    /// 🔴 **它必须在 `PENDING_MATCH` 与 `REMATCHING` 两态下都是真话。** 判不出这条预警
    /// 说的是哪一张单（`WSAppNotification` 没有 `orderId`），所以它也会落到
    /// `REMATCHING` 上 —— 而那一态是「有人接过、又取消了，正在重新找」。
    /// 初稿写的「你的订单还没有人接单」在那一态是假的，已改成只说结局不说经过。
    static let cancellationWarningWithoutControl =
        "你的订单可能会因为长时间没有人接单被系统取消。" + stillMatchingAdvice

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

    /// 陪跑员姓名的**朗读版**：去掉掩码星号。
    ///
    /// 后端的 `volunteerName` 是**始终掩码**的（`张*`，`NameMaskUtils.mask()`，
    /// 契约里逐字写明「姓名一律掩码，不存在明文版本」）。原样交给 VoiceOver 会念成
    /// **「张星号」** —— 而这个 App 的读屏是外放的，念出来的东西周围的人都听得到。
    ///
    /// 去掉星号**不泄露任何信息**：掩码之后剩下的本来就只有姓氏，星号只是个占位符号。
    /// 首页那枚头像早就只显示姓氏了（`FlowAvatar`），两处现在口径一致。
    ///
    /// ⚠️ **只用于朗读与读屏标签，视觉上仍然原样显示 `张*`。** 屏幕上去掉星号会让人
    /// 以为拿到了全名，而拨号那条路从来不经过姓名 —— 号码只走 `volunteerPhone`。
    ///
    /// 空名字回退到既有常量「这位志愿者」，不另造第二个占位词。
    ///
    /// 去星号那一步走共享的 `String.unmaskedForSpeech` —— 这条口径在固定搭档列表、
    /// 连续周数条、志愿者端念盲人姓名的那几处都要用，各写一份迟早分叉。
    var volunteerNameForSpeech: String {
        volunteerName?.unmaskedForSpeech.nilIfBlank ?? PartnerStreakCopy.unknownVolunteerName
    }

    /// 跑者姓名的**朗读版**。与 `volunteerNameForSpeech` 完全对称，理由一字不差：
    /// 契约里 `blindName` 也是**始终脱敏**的（`api_spec.yaml` 逐字「姓名没有『拨得通』
    /// 这回事，所以这里就是展示值，不存在明文版本」），原样交给 VoiceOver 念成「张星号」，
    /// 而志愿者端的读屏同样是外放的。
    ///
    /// 空名字回退到既有常量「这位跑者」（`PartnerStreakCopy.unknownBlindName`），
    /// 不另造第二个占位词。
    var blindNameForSpeech: String {
        blindName?.unmaskedForSpeech.nilIfBlank ?? PartnerStreakCopy.unknownBlindName
    }

    /// 陪跑员的经验凭据，**只说后端真的发了的那一项**。
    ///
    /// 设计稿要的是「陪跑 32 次，引导绳经验 2 年」，而后端只有前半句
    /// （`volunteerTotalCompleted`）。引导绳经验年数与「已认证」这两个字段在契约里
    /// 0 命中 ⇒ **不显示**，不填默认值。给盲人印一个凭空生成的经验数字或认证标记，
    /// 正是他在决定要不要把自己交给一个陌生人时唯一能依据的东西。
    var volunteerExperienceText: String? {
        guard let completed = volunteerTotalCompleted, completed > 0 else { return nil }
        return "陪跑 \(completed) 次"
    }

    /// 首页深蓝卡和订单页状态标题上那个大字：「今天 7:00」「明天 7:00」「9月20日 7:00」。
    ///
    /// **与 `plannedStartForAnnouncement` 是两个东西，不要合并。** 那个给**播报**用，
    /// 念的是完整日期（「2026年9月17日 07:00」）—— 听的人没有屏幕可以回看，含糊的相对日期
    /// 反而要他自己换算。这个给**看**用：52pt 的大字放不下完整日期，而看得见屏幕的人
    /// 需要的是「是不是明天」这一个判断。
    ///
    /// 相对日期只做到后天。再往后「第三天」相对哪一天不清楚（同 Mock 语音解析里
    /// 「第三天」被拒的理由），所以退回绝对日期。
    ///
    /// `now` 与 `calendar` 走参数是为了能被单测钉住 —— 跨午夜、跨月、跨年这三个边界
    /// 全都只在特定时刻才走得到，靠真机碰运气验不了。
    func blindRunnerShortStartText(now: Date = Date(), calendar: Calendar = .current) -> String? {
        RunPlanFormat.shortStart(plannedStart, now: now, calendar: calendar)
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
        // 🚩 单独一支而不是落 `default`：这一态对盲人的**全部内容就是「什么时候」**，
        // 而 `status.blindRunnerAnnouncement` 里没有时刻（它是与状态无关的通用句）。
        // 落到 default 的话，跨天单的播报从头到尾不会出现预约时间 ——
        // 而他要在接下来几天里靠这句话安排自己的日程。
        case .scheduledConfirmed:
            guard let plannedStartForAnnouncement else { return status.blindRunnerAnnouncement }
            return "已经为你约好志愿者，时间是\(plannedStartForAnnouncement)，出发地点：\(startAddressForAnnouncement)。到出发前如果计划有变，可以打电话告诉他。"
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

// MARK: - 这一单要跑多远 / 什么配速

/// 「跑多远」与「配速」两行的文字。**一份实现给两个数据源共用** ——
/// 接单前吃派单载荷 `WSNewOrder`，接单后吃 `OrderDetailResponse`，而两边的字段名与语义
/// 逐字相同。各写一份的表现是「邀请屏说 5 公里、订单页说 5.0 公里」，没有任何东西会报警。
///
/// 🔴 **屏幕上和读屏里是同一句中文，不做两套。** 设计稿三格数据里的 `7'00"` 是视觉写法，
/// 而 VoiceOver 念 `'` 和 `"` 只会念出「撇」「引号」—— 对一个可能有低视力志愿者的界面，
/// 用一句两边都成立的中文比省两个字重要。
enum RunPlanFormat {
    /// 那行大字时间：「今天 7:00」「明天 7:00」「9月20日 7:00」。
    ///
    /// 从 `OrderDetailResponse.blindRunnerShortStartText` 提出来，理由与本枚举的其余成员相同：
    /// 陪跑员端的「邀请」屏吃的是派单载荷 `WSNewOrder`（那一刻拿不到 `OrderDetailResponse`，
    /// 后端对未接单的志愿者 `GET /api/orders/{id}` 恒 403），而两处要显示的是同一句话。
    /// 抄第二份的表现是「弹窗说明天 7:00、详情页说 9月18日 07:00」。
    ///
    /// 相对日期只做到后天 —— 再往后「第三天」相对哪一天不清楚，所以退回绝对日期。
    /// `now` 与 `calendar` 走参数是为了能被单测钉住跨午夜 / 跨月 / 跨年三个边界。
    static func shortStart(_ plannedStart: String?, now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let date = plannedStart?.nilIfBlank?.backendTimestamp else { return nil }
        let clock = DateFormatter.aidRunDisplayClock.string(from: date)
        // `dateComponents(_:from:to:)` 传两个**日初**而不是两个时刻：直接算时刻差会让
        // 「今天 23:00 → 明天 01:00」只差 2 小时而被判成同一天。
        let today = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: date)
        guard let dayOffset = calendar.dateComponents([.day], from: today, to: target).day else {
            return "\(DateFormatter.aidRunDisplayMonthDay.string(from: date)) \(clock)"
        }
        switch dayOffset {
        case 0: return "今天 \(clock)"
        case 1: return "明天 \(clock)"
        case 2: return "后天 \(clock)"
        default:
            // 负数（已过去的预约）也走这里。**不说「昨天」** —— 那一态只会出现在
            // 已结束或异常的单上，而相对日期会让人以为还有事要做。
            return "\(DateFormatter.aidRunDisplayMonthDay.string(from: date)) \(clock)"
        }
    }

    /// 「5 公里」/「800 米」。`nil` = 用户没填 ⇒ **整行不渲染**，不写「未填写」。
    static func plannedDistance(meters: Int?) -> String? {
        guard let meters, meters > 0 else { return nil }
        guard meters >= 1000 else { return "\(meters) 米" }
        let km = Double(meters) / 1000
        // 整公里不拖一个 `.0`：「5 公里」而不是「5.0 公里」。
        let rounded = (km * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? "\(Int(rounded)) 公里"
            : String(format: "%.1f 公里", rounded)
    }

    /// 「每公里 6 分 30 秒」/「每公里 5 分 30 秒 到 6 分 30 秒」。
    ///
    /// 区间两端**成对出现或成对缺席**（契约逐字），所以只有两端都在才算数 ——
    /// 只拿到一端时退回定性档位，而不是把一端当成整个区间。
    /// 两者都没有时返回 `nil`：**不拿 `pacePreference` 反推一个秒数区间**，那是编数字。
    static func pace(minSecondsPerKm: Int?, maxSecondsPerKm: Int?, preference: PacePreference?) -> String? {
        if let minSecondsPerKm, let maxSecondsPerKm, minSecondsPerKm > 0, maxSecondsPerKm > 0 {
            let low = clock(seconds: min(minSecondsPerKm, maxSecondsPerKm))
            let high = clock(seconds: max(minSecondsPerKm, maxSecondsPerKm))
            return low == high ? "每公里 \(low)" : "每公里 \(low) 到 \(high)"
        }
        // `.unknown` 与 `.noPreference` 的 `displayName` 都是「无偏好」，而那不是信息 ——
        // 一行「配速：无偏好」只会占掉读屏用户一次划动。
        guard let preference, preference != .noPreference, preference != .unknown else { return nil }
        return preference.displayName
    }

    /// `390` → 「6 分 30 秒」；整分钟不念秒。
    private static func clock(seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0 ? "\(minutes) 分" : "\(minutes) 分 \(remainder) 秒"
    }
}

extension OrderDetailResponse {
    var plannedDistanceText: String? { RunPlanFormat.plannedDistance(meters: plannedDistanceMeters) }

    var plannedPaceText: String? {
        RunPlanFormat.pace(
            minSecondsPerKm: paceMinSecondsPerKm,
            maxSecondsPerKm: paceMaxSecondsPerKm,
            preference: pacePreference
        )
    }
}

extension WSNewOrder {
    var plannedDistanceText: String? { RunPlanFormat.plannedDistance(meters: plannedDistanceMeters) }

    var plannedPaceText: String? {
        RunPlanFormat.pace(
            minSecondsPerKm: paceMinSecondsPerKm,
            maxSecondsPerKm: paceMaxSecondsPerKm,
            preference: pacePreference.flatMap(PacePreference.init(rawValue:))
        )
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

    /// 掩码姓名的**朗读**形态：去掉占位星号。
    ///
    /// 后端下发的姓名一律掩码（`张*`，`NameMaskUtils.mask()`）。原样交给 VoiceOver 或 TTS
    /// 会念成**「张星号」**，而本 App 的读屏是外放的 —— 「星号」还会被听的人当成名字的一部分。
    /// 去掉星号**不泄露任何信息**：掩码之后剩下的本来就只有姓氏，星号只是个占位符号。
    ///
    /// ⚠️ **只用于朗读通道（`accessibilityLabel` / `speak`），屏幕上仍然原样显示 `张*`。**
    /// 可见文字去掉星号会让人以为拿到了全名。同一个字符串既上屏又被念时，要拆成两份
    /// 而不是就地去星号 —— `PartnerRowCard` 与 `BlindFavoriteVolunteersView` 的收藏播报
    /// 都是这么拆的。
    ///
    /// 全角 `＊` 一并去：后端换一次掩码实现就可能换符号，而漏掉的那一半不会有任何东西报警。
    var unmaskedForSpeech: String {
        replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "＊", with: "")
            .trimmed
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

    /// 只有钟点，配 `blindRunnerShortStartText` 的相对日期用。
    ///
    /// `H:mm` 而不是 `HH:mm`：设计稿的大字是「明天 7:00」不是「明天 07:00」。
    /// 补零在 52pt 上多出一个字符宽度，而那一行本来就要和地点行对齐。
    static let aidRunDisplayClock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "H:mm"
        return formatter
    }()

    /// 相对日期做不到时的退路（三天以后 / 已过去）。不含年份 —— 预约最远 7 天
    /// （后端 `APPOINTMENT_TOO_FAR`），跨年只在 12 月末那几天成立，而那时「1月2日」
    /// 也不会被误读成去年。
    static let aidRunDisplayMonthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
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
