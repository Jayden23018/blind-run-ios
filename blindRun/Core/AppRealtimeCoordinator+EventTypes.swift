import Foundation

// 通知 `eventType` 的静态分类（刷新、优先级、安全、求助、状态宣告）。从 `AppRealtimeCoordinator.swift`
// 原样搬出，行为零改动 —— 那个文件与类体只许变短（SwiftLint 棘轮 #488）。
extension AppRealtimeCoordinator {
    /// 这些通知意味着订单详情里有字段变了、但没有配套的 `ORDER_STATUS_CHANGED`，要重拉一次
    /// （陪跑员订单页 v2）。通知本身照常入队播报 —— 重拉只是让页面上的数据跟上。
    ///
    /// - `DEPART_REMINDER`：出发时刻可能被重算过
    /// - `RUNNER_AT_MEETING_POINT`：`runnerAtMeetingPoint` 变 `true`
    /// - `RUNNER_MESSAGE_UPDATED`：`messageToVolunteer` 变了（正文**不含**留言，只能从详情读）
    /// - `ORDER_WAIT_ENDED`：另有 `ORDER_STATUS_CHANGED`，这里是兜底
    /// - 跑步中四个（DECISIONS-v2 V14–V16，⚠️ V18 的建议名，后端 BE-1/BE-2 合并后核对）：
    ///   `run.lastSignal*` / `run.paused` / `run.runnerBatteryLow` 变了。陪跑员页的「信号到达」
    ///   就是从重拉后 `lastSignalAt` 的变化推出来的，不解析推送载荷。
    static let orderRefreshingEventTypes: Set<String> = [
        "DEPART_REMINDER", "RUNNER_AT_MEETING_POINT", "RUNNER_MESSAGE_UPDATED", "ORDER_WAIT_ENDED",
        "RUN_RHYTHM", "RUN_PAUSED", "RUN_RESUMED", "RUNNER_BATTERY_LOW",
    ]

    /// 只刷新、不进横幅的事件。`RUN_RHYTHM`：跑步页的节奏卡原地变黄就是它的唯一呈现
    /// （交付包 08 §三「不另外弹横幅，同一时刻这个信号只在一处出现」）。
    static let refreshOnlyEventTypes: Set<String> = ["RUN_RHYTHM"]

    /// 展示优先级。默认照后端模板给的 `priority`，**只有一条例外**。
    ///
    /// `ORDER_OVERDUE`（陪跑超过约定结束时间）在后端盲人侧模板里是 `NORMAL`
    /// （`websocket-protocol.md:158`；志愿者侧同一个 eventType 是 `HIGH`，见 `:451`）。
    /// `NORMAL` 在这里的后果是它**排在派单进度那类通知后面**，用蓝色铃铛、不带 header trait。
    /// 而这条告警的语义是「跑者可能失联」—— 后端 N63 的复盘逐字写着：修复前失联和
    /// 「跑完了忘了点结束」在系统里长得一模一样，对看不见屏幕的人是安全缺口不是体验问题。
    ///
    /// 后端 2026-08-13 的通报把这件事划成了我们的边界：「播报文案和打断策略是你们的设计边界，
    /// 不自己改」。所以在这里抬，不去改后端模板。
    ///
    /// ⚠️ **这只影响 App 在前台时的横幅与播报顺序，改不了推送能不能到达。**
    /// 后端只对模板 `priority == HIGH` 的通知补发 APNs（`NotificationService.java:134`），
    /// 判据是模板值不是客户端的展示值 —— 所以盲人端 App 不在前台时**这条告警根本收不到**。
    /// 那一半只能后端把模板提到 HIGH，已投 handoff。别以为抬了这一下就补上了。
    static func clientPriority(forEventType eventType: String, serverPriority: String?) -> RealtimePriority {
        if eventType == "ORDER_OVERDUE" { return .high }
        return RealtimePriority(rawValue: serverPriority)
    }

    /// 该不该按「安全提醒」呈现（队列裁剪时最后被丢、抢占正在显示的 NORMAL 横幅）。
    ///
    /// 这不是求助事件（那条走 `emergencyKind`，还会落 `latestSafetyEvent`、驱动求助 UI），
    /// 只是**呈现强度**。后端把 `priority` 给到 HIGH 就到边界了，剩下的是端上的事
    /// （后端 2026-08-15 原话：「具体做成什么样是你们的决定，我们不越界」）。
    ///
    /// `REMATCHING_MID_RUN`：志愿者在**已经出发之后**取消（`DRIVER_EN_ROUTE` /
    /// `DRIVER_ARRIVED` / `IN_PROGRESS`），盲人很可能正独自在户外，而他看不见身边还有没有人。
    /// 同一件事在派单等待期取消走的是 `REMATCHING`(NORMAL) —— 那时人还没出门，
    /// 一起提上来只会制造噪音，而噪音会让真正紧急的那条被忽略。
    ///
    /// 🔴 **本表里的每一条都绝对不能进 `lifecycleStatus(forEventType:)` 那张表。**
    /// `shouldSuppressLifecycleNotification` 的第一条就是「有活跃订单 ⇒ 抑制」，
    /// 而这些通知发生时**必然**有活跃订单 ⇒ 一旦映射进去就是 100% 静默吞掉，
    /// 恰好是后端拆出这些档想避免的后果。未知 `eventType` 不抑制的默认方向在这里正好是对的，
    /// 所以这里只加呈现强度、不加状态映射。
    ///
    /// 无进展看门狗三条（后端 2026-09-04 新增，架构复核 S-2 / `ISSUES.md` N127 / 迁移 `0038`）：
    ///
    /// - `ORDER_DEPARTURE_STALLED` —— 志愿者接了单，但计划开始时间过了还没点「出发」⇒ 判失联。
    ///   🚨 **不是 `REMATCHING` 的同义词，别合并分支。** 两者都以订单转入 `REMATCHING` 收场，
    ///   但 `REMATCHING` 是志愿者**主动点了取消**（NORMAL，不补 APNs）；这一条是他**接了单之后
    ///   再无动静**（HIGH，补 APNs），触发的那一刻盲人正站在起跑点等着。紧跟着还会来一条
    ///   `ORDER_STATUS_CHANGED`(→`REMATCHING`)，而 `.rematching` 的本地播报是中性的
    ///   「正在确认志愿者状态，请稍候」—— 缺了这一条，「为什么没人来」就没有任何人告诉他。
    /// - `ORDER_ARRIVAL_STALLED` —— 志愿者标了「已到达」却迟迟没点「开始服务」，多半是没碰上头。
    ///   **双方各收一条、文案不同**（后端按 `TargetRole` 分模板），两端都在引导打电话，
    ///   而 `DRIVER_ARRIVED` 这一态两侧都有拨号入口，所以这条通知落地是有动作的。
    /// - `EMERGENCY_UNATTENDED` —— SOS 触发后长时间没推进到结案。要说的是「别再干等，
    ///   自己拨 120/110」，后端点名**不要做成普通提示**。
    /// - `ORDER_VOLUNTEER_LOST`（后端 2026-10-10，#616 M6）—— 志愿者点了「已出发 / 已到达」之后
    ///   失联或迟迟不到，订单转 `REMATCHING`。**双方各收一条、文案不同**。
    ///   🚨 不是 `ORDER_DEPARTURE_STALLED`（他根本没出发）或 `REMATCHING_MID_RUN`（他主动取消）的同义词，
    ///   别合并分支 —— 原因不同、文案不同。
    ///
    /// ⚠️ `EMERGENCY_UNATTENDED` **刻意不走 `emergencyKind`**：那条链路会落 `latestSafetyEvent`
    /// 并驱动 `EmergencyCoordinator.apply` 改求助状态机，而这条事件本身不改变求助的任何状态
    /// （它是催办，不是新事实）。混进去只会让状态机按一条没有权威来源的事件跳档。
    /// 同理它的文案照后端原样播 —— 后端刻意没写「有没有人接手」（它同时覆盖「真的没人接手」
    /// 与「客服已接手但迟迟没结案」，写死任一种在另一种下就是假话），**客户端也不许自己补这句**。
    static func isSafetyEventType(_ eventType: String) -> Bool {
        switch eventType {
        case "REMATCHING_MID_RUN",
             "ORDER_DEPARTURE_STALLED",
             "ORDER_ARRIVAL_STALLED",
             "ORDER_VOLUNTEER_LOST",
             "EMERGENCY_UNATTENDED":
            return true
        default:
            return false
        }
    }

    static func emergencyKind(forEventType eventType: String) -> RealtimeSafetyEvent.Kind? {
        switch eventType {
        case "EMERGENCY_TRIGGERED": return .emergencyTriggered
        case "EMERGENCY_CONTACT_NOTIFIED": return .emergencyContactNotified
        case "EMERGENCY_NO_CONTACT": return .emergencyNoContact
        case "EMERGENCY_VOLUNTEER_TIMEOUT": return .emergencyVolunteerTimeout
        case "EMERGENCY_TRIGGERED_BY_VOLUNTEER": return .emergencyTriggeredByVolunteer
        case "EMERGENCY_CONTACT_SMS_DELIVERED": return .emergencyContactSmsDelivered
        case "EMERGENCY_CONTACT_NOTIFY_FAILED": return .emergencyContactNotifyFailed
        case "EMERGENCY_VOLUNTEER_ACK": return .emergencyVolunteerAck
        case "EMERGENCY_CLOSED_RESOLVED": return .emergencyClosedResolved
        case "EMERGENCY_CLOSED_FALSE_ALARM": return .emergencyClosedFalseAlarm
        default: return nil
        }
    }

    /// Emergency copy is always the client's own, never the backend's notification body.
    ///
    /// The backend template for `EMERGENCY_CONTACT_NOTIFIED` reads "已通知紧急联系人{contactName}"
    /// / "已通知你的联系人{contactName}，请保持冷静" (`demo/src/main/resources/data.sql:72`). It is
    /// pushed synchronously inside the trigger transaction, strictly before the SMS is handed to
    /// the provider (`EmergencyService.java:370-373` vs `EmergencyContactNotifier.java:60-62`), and
    /// an SMS failure is never corrected back to the blind runner (`:126-135`). Rendering that text
    /// verbatim would tell a blind user their family already knows, which is the one thing the app
    /// must not do. Local progressive-tense copy is substituted for every emergency event type.
    static func emergencyCopy(for kind: RealtimeSafetyEvent.Kind) -> String? {
        switch kind {
        case .emergencyTriggered: return EmergencySafetyCopy.triggeredAcknowledged
        case .emergencyContactNotified: return EmergencySafetyCopy.contactNotified
        case .emergencyNoContact: return EmergencySafetyCopy.noContact
        case .emergencyVolunteerTimeout: return EmergencySafetyCopy.volunteerTimeout
        case .emergencyTriggeredByVolunteer: return EmergencySafetyCopy.triggeredByVolunteer
        // 唯一允许完成时的一句，依据是运营商回执，不是「已发起」。
        case .emergencyContactSmsDelivered: return EmergencySafetyCopy.contactSmsDelivered
        case .emergencyContactNotifyFailed: return EmergencySafetyCopy.contactNotifyFailed
        case .emergencyVolunteerAck: return EmergencySafetyCopy.volunteerAcknowledged
        case .emergencyClosedResolved: return EmergencySafetyCopy.closedResolved
        case .emergencyClosedFalseAlarm: return EmergencySafetyCopy.closedFalseAlarm
        case .emergencyResolved, .emergencyVolunteerAlert: return nil
        }
    }

    /// 通知 `eventType` → 它宣布的订单状态。返回 nil 表示「这条不是状态变化的重复播报」，一律照播。
    ///
    /// 常量取自后端 `docs/websocket-protocol.md` §2.2（盲人端）与 §3.2（志愿者端）事件表 ——
    /// 那份表明写着「不应依赖 body/ttsText 文案匹配」，这里就是照它办。
    ///
    /// **刻意不在表里的，每一条都有理由：**
    /// - `REMATCH_ACCEPTED` —— 状态与 `ORDER_ACCEPTED` 同为 `PENDING_ACCEPT`，但订单页两次念的是
    ///   同一句「志愿者已接单」，既没有「重新」也没有新志愿者的名字。抑制它，用户就分不出
    ///   这是新人还是原来那个 —— 而他刚被告知上一个志愿者取消了。这条**必须播**。
    /// - `DISPATCH_STARTED` / `DISPATCH_EXPANDING` / `REMATCH_TIMEOUT` /
    ///   `ORDER_CANCELLATION_WARNING` / `ORDER_OVERDUE` —— **不改订单状态**，订单页不会播。
    ///   抑制它们等于让派单期（最长 30 分钟、3 轮扩圈）整段静音。
    /// - `ROUTE_CONFIRM_REQUIRED*` / `PROXIMITY_ALERT` / `CERT_*` / `ID_VERIFY_*` ——
    ///   与订单状态无关，本来就不该进这条闸。
    /// - 🔴 **跨天预约那三条一个都不许加**（`SCHEDULED_RUN_REMINDER` / `SCHEDULED_DEPARTURE_CONFIRM_REQUIRED` /
    ///   `SCHEDULED_DEPARTURE_GATE_MISSED`，后端迁移 `0041`）。理由与 `REMATCHING_MID_RUN`
    ///   那条逐字相同：`shouldSuppressLifecycleNotification` 的第一条是「有活跃订单 ⇒ 抑制」，
    ///   而这三条**必然**在有活跃订单时触发 ⇒ 映射进去就是 100% 静默吞掉。
    ///   其中 `SCHEDULED_DEPARTURE_CONFIRM_REQUIRED` 被吞掉的代价最重：志愿者收不到提醒 ⇒
    ///   60 分钟后被判未确认、订单转走，而他并没有拒绝过。
    /// - 🔴 `ORDER_CANCELLED_BY_BLIND_AFTER_ARRIVAL`（后端 #682，HIGH）**不许加**，虽然它也宣布 `CANCELLED`。
    ///   它只发给标了「已到达」的陪跑员 ⇒ 必然有活跃订单 ⇒ 映射进来就是 100% 被吞。而它的 `ttsText`
    ///   带着「你可以离开集合点了」，这一刻人正站在集合点 —— 订单页那句通用状态句不说这个。
    ///   用例 `RealtimeNotificationRoutingTests` 钉住。
    static func lifecycleStatus(forEventType eventType: String) -> RunOrderStatus? {
        switch eventType {
        case "ORDER_ACCEPTED": return .pendingAccept
        case "DRIVER_EN_ROUTE": return .driverEnRoute
        case "DRIVER_ARRIVED": return .driverArrived
        case "ORDER_COMPLETED": return .completed
        case "ORDER_AUTO_CANCELLED", "ORDER_CANCELLED_BY_BLIND": return .cancelled
        case "REMATCHING": return .rematching
        case "NO_VOLUNTEER_AVAILABLE": return .noVolunteer
        default: return nil
        }
    }
}
