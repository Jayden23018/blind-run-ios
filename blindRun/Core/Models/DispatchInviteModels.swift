import Foundation

// 派单邀请的载荷：`NEW_ORDER`（推送与待回复列表共用）、撤回、待回复快照。
// 从 `WebSocketModels.swift` 挪出（SwiftLint 棘轮 #488：那个文件只许变短）。

/// New order dispatch (sent to volunteer)
///
/// ⚠️ **刻意不解 `specialNotes`。** 后端的 `NEW_ORDER` 载荷现在仍带这个字段
/// （`websocket-protocol.md:359,376`），这里不声明它 —— `JSONDecoder` 忽略多余的键，
/// 于是那段文本进不了 App 的任何一个类型，也就没有任何视图能把它渲染出来。
///
/// 理由是 `AGENTS.md §8`「接单前隐藏盲人**敏感健康信息**」。派单是串行的，一单会依次推给
/// 多个候选志愿者，而这个弹窗紧挨着「接单 / 拒绝」按钮 —— 也就是接单前。`specialNotes` 是
/// 自由文本，取值空间开放、敏感度无法预判；语音下单落地后它装的就是用户原话
/// （「我有低血糖，如果我说头晕请马上停下来」），等于广播给所有最终拒单的人。
///
/// 只删渲染那几行不够：字段还在类型上，下一个人加回去没有任何东西拦着。删字段才是根因修法，
/// 编译器从此替我们守着。接单后的完整备注走 `OrderDetailResponse.specialNotes`，那条路不变。
///
/// 回归用例 `AppRealtimeCoordinatorTests.testNewOrderCarryingSpecialNotesDecodesButNeverReachesTheClient`
/// （已验红：把字段加回来，该用例立刻失败）。
/// 对照：`pacePreference` / `hasGuideDog` 留着 —— 取值空间封闭（枚举 / 布尔），且它们是志愿者
/// 判断「我接不接得下来」的依据，藏起来只会让人盲接、接了再取消，成本落回盲人身上。
nonisolated struct WSNewOrder: Codable, Sendable {
    /// 可选：`GET /api/volunteer/pending-invites` 的每一项是「`NEW_ORDER` 的全部字段 + `sentAt`」，
    /// **没有 `type` 键**。两路共用这一个模型，必填就会让整个待回复列表解不出来。没有代码读它。
    let type: String?
    let timestamp: String?
    let orderId: Int64
    let startAddress: String?
    let startLatitude: Double?
    let startLongitude: Double?
    let distanceKm: Double?
    let plannedStart: String?
    let plannedEnd: String?
    let dispatchTimeoutSeconds: Int?
    let priority: String?
    let pacePreference: String?
    let hasGuideDog: Bool?

    /// 这一单要不要先通电话磨合。**决定 `/respond` 发哪个 `action`**（见 `dispatchRespondAction`）。
    ///
    /// ⚠️ **契约把它标成「必填」，这里却是 optional —— 是刻意的，不要改成非可选。**
    /// 非可选意味着缺这个键时 `WSNewOrder` 整条解不出来，而
    /// `WebSocketService.decodeTextMessage` 对解不出的**消息**是丢弃：志愿者连派单弹窗都看不到，
    /// 静默退出派单池，而盲人正在等这一轮。缺失时落回的 `INTERESTED` 后端在
    /// `app.intro-call.enabled` 开与关两种情况下都放行（`DispatchService.introCallEnabled`
    /// 的注释：关掉只是不再**强制**），所以降级路径本身是通的 —— 代价只是熟人多打一通电话，
    /// 正是这个字段上线前的既有行为。
    /// 缺失不是静默的：`WebSocketService` 会把 `failedField: "requiresIntroCall"` 记进派单诊断，
    /// 那条诊断渲染在志愿者首页（`VolunteerHomeView` 的「派单诊断：…」）。
    ///
    /// 🚨 **不许在客户端自己推算这个值**（例如拿 `plannedStart - now` 跟 20 分钟比）：
    /// 判断的另一半「这两人磨合成功过没有」客户端根本拿不到，窗口长度又是后端配置
    /// （`app.intro-call.window-minutes`）。自己算必然与后端守卫漂移，
    /// 而漂移的表现是「界面说能直接接、后端回 409」。
    /// 后端已把这个判断收成一份（`DispatchService.introCallWindowFits`），三个消费者共用。
    let requiresIntroCall: Bool?

    /// 配速区间与本次计划里程。契约里从 2026-08-09 就在 `NEW_ORDER` 上
    /// （`websocket-protocol.md` 的 NEW_ORDER 字段表），客户端此前没解码。
    ///
    /// 接进来的理由：设计交付文档 v3 §5 的「邀请」屏要显示「跑多远 / 配速」——
    /// 那是志愿者判断「我跟不跟得下来」的两个量，而定性档位（`pacePreference`）答不了。
    /// 三项**接单前可见**的判据与 `pacePreference` / `hasGuideDog` 一致：取值空间封闭
    /// （数值区间可以逐个判定给陌生人看行不行），自由文本才一律推迟到接单后（`AGENTS.md` §8）。
    ///
    /// ⚠️ 用户没填时后端**整个键不出现**（不发 `null`），所以缺值 = 那一行不渲染，
    /// 不是显示「未填写」。三项声明成 `var` 只为让 memberwise init 自动给 nil 默认值 ——
    /// 用例里的构造点因此不必各加三行，同 `OrderDetailResponse.volunteerId` 那条。
    var paceMinSecondsPerKm: Int?
    var paceMaxSecondsPerKm: Int?
    var plannedDistanceMeters: Int?

    /// 邀请卡跑者行那几项（后端 #306，2026-09-18 起两个入口都有）。前四项档案缺失时**整键不出现**，
    /// 缺 = 那一项不渲染，**不脑补默认值**（把「不知道」显示成「全盲」同样是错的）。
    /// 全部接成 `String?`：开放枚举，认不出的取值由展示层兜底，不许整条派单解不出来。
    var visionLevel: String?
    var tetherPreference: String?
    var chatPreference: String?
    var routePreference: String?
    /// 你和这位盲人一起跑完过几单。契约里**必填、0 也下发**；可选只为缺键时不崩 ——
    /// 缺键 = 什么都不显示，`0` = 「第一次一起跑」，两者在卡片上说的话不同。
    var completedTogetherCount: Int?
    /// 预计时长（#357，2026-09-25 起在推送里）。与 `AvailableOrderResponse` 同名同值。
    var expectedDurationMinutes: Int?

    /// 这条邀请的 id（后端 #371）。**邀请的身份是它，不是 `orderId`**：同一张单的邀请被撤回（`TAKEN`）
    /// 而那轮通话没打成时，会给你同一张单发一张**新的**邀请（新 `inviteId`）。按 `orderId` 去重会把它当重复丢掉。
    /// 可选只为兼容老服务端；缺了就退回按 `orderId` 认。
    var inviteId: Int64?
    /// 回复的最晚时刻（后端 #371，**权威**）。倒计时读它，不拿 `dispatchTimeoutSeconds` 加当前时间推。
    /// WS 这一路整分钟时省掉 `:00`（后端 #542），`backendTimestamp` 两种都认。
    var expiresAt: String?
    /// 邀请发出的时刻。**只有 REST**（`pending-invites`）带，WS 推送里没有。
    var sentAt: String?
    /// 跑者姓名，**已掩码**（`李*`，后端 #357，推送与待回复列表都有）；查不到时键不出现。
    /// 接单前能给看（`AGENTS.md` §8 的判据）：掩码后只剩一个姓，不是跑者写的自由文本；契约也明说它发给所有候选人。
    /// 别直接上屏或朗读，走 `runnerName`。
    var blindName: String?

    /// 收到这条派单时该发的 `action`。「发哪个」只在这里判一次。
    ///
    /// `false` 的三种成因（通话功能整体关闭 / 这两人已磨合成功过 / 距开跑已不够聊一轮）
    /// 客户端**不需要也无法区分**，所以界面上不解释原因，只把主按钮换成「接单」。
    var dispatchRespondAction: OrderRespondAction {
        (requiresIntroCall ?? true) ? .interested : .accept
    }

    /// 邀请上的跑者称呼（DECISIONS-v2 V11）：屏幕那份保留掩码（`李*`），朗读那份去掉星号（「李」），
    /// 否则读屏念「李星号」。去掉星号什么都不剩 = 没有称呼，返回 `nil`，调用方不渲染、不编名字。
    var runnerName: (display: String, spoken: String)? {
        guard let display = blindName?.nilIfBlank, let spoken = display.unmaskedForSpeech.nilIfBlank else { return nil }
        return (display, spoken)
    }
}

/// `INVITE_WITHDRAWN`（后端 #371）。只走 WS，不发 APNs、不能重连补读 —— 重连后以待回复列表为准。
nonisolated struct WSInviteWithdrawn: Codable, Sendable {
    let orderId: Int64
    /// 被撤回的那一张。可选只为容忍缺键；缺了就按 `orderId` 认。
    let inviteId: Int64?
    /// 开放枚举，原样留字符串，见 `InviteWithdrawReason`。
    let reason: String?

    var withdrawReason: InviteWithdrawReason { InviteWithdrawReason(rawValue: reason) }
}

/// 邀请为什么失效。决定那张卡上「这个邀请已失效」下面那一行说什么。
///
/// 前三档来自 `INVITE_WITHDRAWN.reason`（**开放枚举**，认不出的落 `.other`，不许整条崩）；
/// `.noLongerPending` 是客户端自己的：待回复列表里已经没有这一张（离线期间被撤回、被接走或过期，
/// 撤回事件只走 WS 补不回来），说不清是哪一种，就不说是哪一种。
nonisolated enum InviteWithdrawReason: Equatable, Sendable {
    case taken
    case conflict
    case orderClosed
    case noLongerPending
    case other

    init(rawValue: String?) {
        switch rawValue {
        case "TAKEN": self = .taken
        case "CONFLICT": self = .conflict
        case "ORDER_CLOSED": self = .orderClosed
        default: self = .other
        }
    }
}

/// `GET /api/volunteer/pending-invites` 的响应（后端 #366，**裸对象，不在 `{success, data}` 信封里**）。
/// 只含：自己的、待回复、还没过期、订单仍在派单中的邀请，按 `expiresAt` 升序；没有时是空数组。
nonisolated struct PendingInvitesResponse: Decodable, Sendable {
    /// 连续拒绝 / 过期次数（后端计，接单或有意向清零，撤回不计）。本次只解码，接入另见 iOS issue。
    let consecutiveDeclineCount: Int?
    /// 可选只为容忍缺键；缺了当空列表 —— 但**不能**据此把手上的邀请都判成失效，见 `AppState.restorePendingInvites`。
    let invites: [WSNewOrder]?
}

extension WSIncomingEvent {
    /// 邀请类事件（`INVITE_WITHDRAWN`，后端 #371）。不是邀请类的返回 `nil`，由调用方落 `.unknown`。
    nonisolated static func decodeInviteEvent(type: String, from data: Data, using decoder: JSONDecoder) throws -> Self? {
        switch type {
        case WSMessageType.inviteWithdrawn.rawValue:
            return .inviteWithdrawn(try decoder.decode(WSInviteWithdrawn.self, from: data))
        default:
            return nil
        }
    }
}
