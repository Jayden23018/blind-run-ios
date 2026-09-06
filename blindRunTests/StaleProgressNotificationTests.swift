import XCTest
@testable import blindRun

/// 无进展看门狗三条（后端 2026-09-04 新增，架构复核 S-2 / `ISSUES.md` N127 / 迁移 `0038`）。
///
/// | eventType | 收件人 | 触发 |
/// |---|---|---|
/// | `ORDER_DEPARTURE_STALLED` | 盲人 | 志愿者接了单，但计划开始时间过了还没点「出发」⇒ 判失联，订单同时转 `REMATCHING` |
/// | `ORDER_ARRIVAL_STALLED` | **双方各一条** | 志愿者标了「已到达」但迟迟没点「开始服务」 |
/// | `EMERGENCY_UNATTENDED` | 盲人 | SOS 触发后长时间未推进到结案 |
///
/// 三条都是 `APP_NOTIFICATION` 的 `eventType`、都是 `HIGH`（会补发 APNs）。
/// 共同点是**必然在有活跃订单时触发** —— 这正是它们全部的危险来源，见下面第一条用例。
@MainActor
final class StaleProgressNotificationTests: XCTestCase {

    private static let allEventTypes = [
        "ORDER_DEPARTURE_STALLED",
        "ORDER_ARRIVAL_STALLED",
        "EMERGENCY_UNATTENDED"
    ]

    /// 🔴 **本文件最重要的一条。**
    ///
    /// `shouldSuppressLifecycleNotification` 的第一条规则是「有活跃订单 ⇒ 抑制」
    /// （`AppRealtimeCoordinator.swift` 的 `if !activeOrderIDs.isEmpty { return true }`），
    /// 而这三条**必然**在有活跃订单时到达。所以只要有人「顺手」把它们补进
    /// `lifecycleStatus(forEventType:)` 那张表 —— 一个看起来完全合理的补全动作 ——
    /// 就是 100% 静默吞掉，而三条里两条发生时盲人正一个人站在户外。
    func testNoneOfThemIsALifecycleTemplate() {
        for eventType in Self.allEventTypes {
            XCTAssertNil(
                AppRealtimeCoordinator.lifecycleStatus(forEventType: eventType),
                "\(eventType) 进了这张表就会被『有活跃订单 ⇒ 抑制』吃掉"
            )
        }
    }

    /// 上一条钉的是判定表，这一条在真实场景（已注册活跃订单）下端到端跑一遍 ——
    /// 抑制发生在「判定表 + 活跃订单」的组合上，只钉判定函数看不住它。
    func testAllThreeAreStillSpokenWhileAnOrderIsActive() async {
        for eventType in Self.allEventTypes {
            let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
            let service = WebSocketService()
            coordinator.attach(to: service, role: .blind)
            coordinator.registerActiveOrder(42)

            service.simulateIncomingEventForTesting(.notification(makeNotification(eventType: eventType)))
            await Task.yield()

            XCTAssertEqual(
                coordinator.currentNotification?.displayText,
                Self.body(for: eventType),
                "\(eventType) 被抑制 = 这件事一个字都没播出去"
            )
            XCTAssertFalse(
                coordinator.currentNotification?.speechText.isEmpty ?? true,
                "\(eventType) 的 speechText 为空 = 只剩一条盲人看不见的横幅"
            )
        }
    }

    /// 三条都按安全提醒呈现：队列裁剪时最后被丢，且能抢占正在显示的 NORMAL 横幅。
    /// 后端把 `priority` 给到 HIGH 就到边界了，呈现强度是端上的事。
    func testAllThreeArePresentedAsSafetyEvents() async {
        for eventType in Self.allEventTypes {
            let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
            let service = WebSocketService()
            coordinator.attach(to: service, role: .blind)

            service.simulateIncomingEventForTesting(.notification(makeNotification(eventType: eventType)))
            await Task.yield()

            XCTAssertEqual(coordinator.currentNotification?.isSafetyEvent, true, eventType)
            XCTAssertEqual(coordinator.currentNotification?.priority, .high, eventType)
            XCTAssertTrue(AppRealtimeCoordinator.isSafetyEventType(eventType))
        }
    }

    /// 🚨 后端点名的那条：`ORDER_DEPARTURE_STALLED` **不是 `REMATCHING` 的同义词**。
    ///
    /// 两者都以订单转入 `REMATCHING` 收场，所以很容易被当成同一件事，但对用户完全不同：
    /// `REMATCHING` 是志愿者**主动点了取消**（NORMAL，不补 APNs，且订单页已经在说同一件事
    /// ⇒ 该被抑制）；这一条是他**接了单之后再无动静**（HIGH，补 APNs），
    /// 触发的那一刻盲人正站在起跑点等着，App 多半已经退到后台。
    ///
    /// 紧跟着还会来一条 `ORDER_STATUS_CHANGED`(→`REMATCHING`)，而 `.rematching` 的本地播报
    /// 是中性的「正在确认志愿者状态，请稍候」—— 合并分支的话，「为什么没人来」
    /// 就没有任何人告诉他。
    func testDepartureStalledIsNotFoldedIntoPlainRematching() {
        XCTAssertTrue(AppRealtimeCoordinator.isSafetyEventType("ORDER_DEPARTURE_STALLED"))

        // 普通那档必须保持原样，否则分档就没有意义了。
        XCTAssertFalse(AppRealtimeCoordinator.isSafetyEventType("REMATCHING"))
        XCTAssertEqual(
            AppRealtimeCoordinator.lifecycleStatus(forEventType: "REMATCHING"),
            .rematching,
            "普通那档仍然是生命周期通知，订单页已经在显示同一件事时该被抑制"
        )
    }

    /// `ORDER_ARRIVAL_STALLED` 是**双方各收一条**（后端按 `TargetRole` 分模板，文案不同）。
    /// 志愿者那条同样要按安全提醒呈现 —— 两端都在引导打电话，而 `DRIVER_ARRIVED` 这一态
    /// 两侧都有拨号入口，所以这条通知落地是有动作的。
    func testArrivalStalledReachesTheVolunteerSideToo() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .volunteer)
        coordinator.registerActiveOrder(42)

        let volunteerBody = "你标记了已到达，但服务还没开始"
        service.simulateIncomingEventForTesting(.notification(
            makeNotification(eventType: "ORDER_ARRIVAL_STALLED", body: volunteerBody)
        ))
        await Task.yield()

        XCTAssertEqual(coordinator.currentNotification?.displayText, volunteerBody)
        XCTAssertEqual(coordinator.currentNotification?.isSafetyEvent, true)
    }

    /// `EMERGENCY_UNATTENDED` **不走 `emergencyKind`**，所以不落 `latestSafetyEvent`、
    /// 不驱动 `EmergencyCoordinator` 的求助状态机。
    ///
    /// 理由：它是催办不是新事实 —— 求助的任何状态都没有因为它改变。混进那条链路
    /// 只会让状态机按一条没有权威来源的事件跳档（权威来源是 `GET /api/emergency/active`）。
    /// 它要的是「强提示」，而强提示由上面的 `isSafetyEvent` 给到了。
    func testEmergencyUnattendedDoesNotDriveTheEmergencyStateMachine() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)

        service.simulateIncomingEventForTesting(.notification(
            makeNotification(eventType: "EMERGENCY_UNATTENDED")
        ))
        await Task.yield()

        XCTAssertNil(AppRealtimeCoordinator.emergencyKind(forEventType: "EMERGENCY_UNATTENDED"))
        XCTAssertNil(coordinator.latestSafetyEvent, "它不改变求助状态，不得驱动求助状态机")
        // 但它仍然要以最强的形式播出去 —— 不驱动状态机 ≠ 降级成普通提示。
        XCTAssertEqual(coordinator.currentNotification?.isSafetyEvent, true)
    }

    /// 文案原样播后端的，客户端不加工。
    ///
    /// `EMERGENCY_UNATTENDED` 尤其如此：后端**刻意**没写「有没有人接手」——
    /// 它同时覆盖「真的没人接手」与「客服已接手但迟迟没结案」，写死任一种在另一种下就是假话。
    /// 要说的动作两种情况一样：别再干等，自己拨 120/110。
    func testCopyIsPassedThroughWithoutTheClientInventingWhoIsHandlingIt() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)

        service.simulateIncomingEventForTesting(.notification(
            makeNotification(eventType: "EMERGENCY_UNATTENDED")
        ))
        await Task.yield()

        let spoken = coordinator.currentNotification?.speechText ?? ""
        XCTAssertEqual(spoken, Self.body(for: "EMERGENCY_UNATTENDED"))
        XCTAssertTrue(spoken.contains("110"), "行动指令被裁掉的话，这条通知就只剩一个坏消息")
        XCTAssertFalse(spoken.contains("接手"), "客户端不许自己补「有没有人接手」——两种情况必有一种是假话")
    }

    /// 断线期间错过的这三条，补读回来时同样要按安全提醒呈现。
    func testCatchUpKeepsTheSafetyPresentation() async {
        for (index, eventType) in Self.allEventTypes.enumerated() {
            let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
            let service = WebSocketService()
            coordinator.attach(to: service, role: .blind)

            coordinator.ingestCatchUp([
                MissedNotificationResponse(
                    id: Int64(9100 + index),
                    eventType: eventType,
                    body: Self.body(for: eventType),
                    ttsText: Self.body(for: eventType),
                    priority: "HIGH",
                    sentAt: "2026-09-04T12:00:00Z",
                    orderId: 42
                )
            ])
            await Task.yield()

            XCTAssertEqual(coordinator.currentNotification?.isSafetyEvent, true, eventType)
            XCTAssertEqual(coordinator.currentNotification?.displayText, Self.body(for: eventType), eventType)
        }
    }

    // MARK: - Fixtures（文案取自后端 `migrations/0038_stale_progress_watchdog.sql` 的模板）

    private static func body(for eventType: String) -> String {
        switch eventType {
        case "ORDER_DEPARTURE_STALLED":
            return "志愿者接单后一直没有出发，系统正在为你重新匹配志愿者，请在原地稍候。"
        case "ORDER_ARRIVAL_STALLED":
            return "志愿者标记了已到达，但服务还没有开始。如果还没碰到面，可以打电话联系他。"
        default:
            return "你的求助已经发出一段时间了。如果情况危急，请立即拨打120或110，或者向周围的人求助，不要继续等待。"
        }
    }

    private func makeNotification(eventType: String, body: String? = nil) -> WSAppNotification {
        let text = body ?? Self.body(for: eventType)
        return WSAppNotification(
            type: WSMessageType.appNotification.rawValue,
            eventId: nil,
            messageId: "stale-\(eventType)",
            eventType: eventType,
            title: "安全提醒",
            body: text,
            ttsText: text,
            priority: "HIGH",
            timestamp: "2026-09-04T12:00:00Z"
        )
    }
}
