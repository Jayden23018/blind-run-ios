import XCTest
@testable import blindRun

/// 「志愿者在跑途中取消了」（后端 2026-08-15 新增 eventType `REMATCHING_MID_RUN`，`priority=HIGH`）。
///
/// 后端把同一件事拆成了两个紧急档，判据是**志愿者出没出门**：
///
/// | 取消发生在 | eventType | 后端 priority | 盲人此刻 |
/// |---|---|---|---|
/// | `PENDING_ACCEPT` | `REMATCHING` | `NORMAL` | 人还没出门 |
/// | `DRIVER_EN_ROUTE` / `DRIVER_ARRIVED` / `IN_PROGRESS` | `REMATCHING_MID_RUN` | `HIGH` | **很可能正独自在户外** |
///
/// 取消那一瞬间 `order.volunteer` 被置空、状态转 `REMATCHING`，而 `REMATCHING` 不推位置
/// ⇒ 走散检测与信号缺失兜底整体停摆。也就是说这条通知播出去之前，盲人身边有没有人这件事
/// 在系统里是没有信号的 —— 他只能靠听。
@MainActor
final class RematchingMidRunNotificationTests: XCTestCase {

    /// 🔴 **本文件最重要的一条**：它绝不能被 `shouldSuppressLifecycleNotification` 吃掉。
    ///
    /// 那个函数的第一条规则是「有活跃订单 ⇒ 抑制」（`AppRealtimeCoordinator.swift`
    /// `if !activeOrderIDs.isEmpty { return true }`），而这条通知**必然**在有活跃订单时到达。
    /// 所以只要有人「顺手」把 `REMATCHING_MID_RUN` 加进 `lifecycleStatus(forEventType:)` 那张表
    /// —— 一个看起来完全合理的补全动作 —— 最危险的那一档就变成 100% 静默吞掉。
    ///
    /// 这条用例在真实场景（已注册活跃订单）下跑，而不是只调判定函数：
    /// 抑制发生在两者的组合上，只钉判定函数看不住它。
    func testMidRunAlertIsSpokenEvenWhileAnOrderIsActive() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)
        coordinator.registerActiveOrder(42)

        service.simulateIncomingEventForTesting(.notification(makeMidRunRematch()))
        await Task.yield()

        XCTAssertEqual(
            coordinator.currentNotification?.displayText,
            Self.backendBody,
            "有活跃订单就被抑制 = 盲人独自在户外，而这件事一个字都没播出去"
        )
        XCTAssertFalse(
            coordinator.currentNotification?.speechText.isEmpty ?? true,
            "speechText 为空 = 只剩一条盲人看不见的横幅"
        )
    }

    /// 直接钉判定表本身，错误信息比上面那条端到端用例指得更准。
    func testMidRunAlertIsNotALifecycleTemplate() {
        XCTAssertNil(
            AppRealtimeCoordinator.lifecycleStatus(forEventType: "REMATCHING_MID_RUN"),
            "进了这张表就会被『有活跃订单 ⇒ 抑制』吃掉"
        )
    }

    /// 它要按安全提醒呈现：队列裁剪时最后被丢，且能抢占正在显示的 NORMAL 横幅。
    ///
    /// 后端把 `priority` 给到 HIGH 就到边界了（2026-08-15 原话「具体做成什么样是你们的决定，
    /// 我们不越界」），呈现强度是端上的事。接收场景是「人在户外、屏幕看不见、可能戴着耳机在跑」。
    func testMidRunAlertIsPresentedAsASafetyEvent() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)

        service.simulateIncomingEventForTesting(.notification(makeMidRunRematch()))
        await Task.yield()

        XCTAssertEqual(coordinator.currentNotification?.isSafetyEvent, true)
        XCTAssertEqual(coordinator.currentNotification?.priority, .high)
    }

    /// 但它**不是求助事件** —— 不该驱动求助 UI，也不该落 `latestSafetyEvent`。
    /// 志愿者取消服务是订单事件，不是有人按了求助；混进那条链路会让盲人以为求救已经发出。
    func testMidRunAlertIsNotAnEmergency() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)

        service.simulateIncomingEventForTesting(.notification(makeMidRunRematch()))
        await Task.yield()

        XCTAssertNil(AppRealtimeCoordinator.emergencyKind(forEventType: "REMATCHING_MID_RUN"))
        XCTAssertNil(coordinator.latestSafetyEvent, "它不是求助事件，不得驱动求助 UI")
    }

    /// 另一档（派单等待期取消）必须**保持原样**：仍然是生命周期模板、仍然不是安全事件。
    ///
    /// 两档一起提上来就没有分档的意义了 —— 后端拆开的理由正是「噪音会让真正紧急的那条被忽略」。
    func testPlainRematchingKeepsItsOrdinaryPresentation() {
        XCTAssertEqual(
            AppRealtimeCoordinator.lifecycleStatus(forEventType: "REMATCHING"),
            .rematching,
            "普通那档仍然是生命周期通知，订单页已经在显示同一件事时该被抑制"
        )
        XCTAssertFalse(AppRealtimeCoordinator.isSafetyEventType("REMATCHING"))
        XCTAssertTrue(AppRealtimeCoordinator.isSafetyEventType("REMATCHING_MID_RUN"))
    }

    /// 断线期间错过的这一条，补读回来时同样要按安全提醒呈现。
    ///
    /// 这是最该被听见的补读项：它意味着盲人在断线的那段时间里已经独自在户外，而他到现在都不知道。
    func testCatchUpKeepsTheSafetyPresentation() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)

        coordinator.ingestCatchUp([
            MissedNotificationResponse(
                id: 9001,
                eventType: "REMATCHING_MID_RUN",
                body: Self.backendBody,
                ttsText: Self.backendBody,
                priority: "HIGH",
                sentAt: "2026-08-15T12:00:00Z",
                orderId: 42
            )
        ])
        await Task.yield()

        XCTAssertEqual(coordinator.currentNotification?.isSafetyEvent, true)
        XCTAssertEqual(coordinator.currentNotification?.displayText, Self.backendBody)
    }

    /// 文案原样播后端的，客户端不加工。
    ///
    /// 这句是**行动指令**（「请先停下来，走到安全的地方等候」），改一个字都可能改掉它的可执行性。
    /// 紧急短信那套本地覆盖不套用在这条上 —— 那套存在的理由是后端 body 用了完成时态且会说谎
    /// （「联系人已收到短信」），这条没有那个问题。
    func testCopyIsPassedThroughUnmodified() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)

        service.simulateIncomingEventForTesting(.notification(makeMidRunRematch()))
        await Task.yield()

        XCTAssertEqual(coordinator.currentNotification?.speechText, Self.backendBody)
        XCTAssertTrue(
            coordinator.currentNotification?.speechText.contains("请先停下来") ?? false,
            "行动指令被裁掉的话，这条通知就只剩一个坏消息"
        )
    }

    private static let backendBody =
        "您的陪跑志愿者已取消服务，现在只有您一个人。请先停下来，走到安全的地方等候，系统正在为您重新匹配志愿者。"

    private func makeMidRunRematch(messageID: String = "mid-run-1") -> WSAppNotification {
        WSAppNotification(
            type: WSMessageType.appNotification.rawValue,
            eventId: nil,
            messageId: messageID,
            eventType: "REMATCHING_MID_RUN",
            title: "重新匹配中",
            body: Self.backendBody,
            ttsText: Self.backendBody,
            priority: "HIGH",
            timestamp: "2026-08-15T12:00:00Z"
        )
    }
}
