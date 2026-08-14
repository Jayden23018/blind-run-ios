import XCTest
@testable import blindRun

/// 约定结束时间与超时告警（功能 6）。
///
/// **背景，别丢**：`ORDER_OVERDUE` 不是新 eventType，模板和 `ttsText` 一直在后端库里，
/// 但它在生产上**一次都没被触发过** —— 两个定时器互相抵消，`OrderTimeoutScheduler` 每 60 秒
/// 把过了 `plannedEndTime` 的订单直接置成 `COMPLETED`，而发告警的任务要求订单在超时 1 小时后
/// **仍是** `IN_PROGRESS`。后端 N63（`918bf01`）已修：`plannedEnd + 15min` 发告警、
/// `+60min` 才自动完成。所以这条分支从今天起真的会走到。
///
/// 这些用例钉三件事：结束时间**取 `plannedEnd` 不是推出来的**、
/// 服务进行中它进主播报而不是躺在折叠区里、`ORDER_OVERDUE` 不排在派单进度后面。
@MainActor
final class PlannedEndAndOverdueTests: XCTestCase {

    // MARK: - 结束时间的来源

    /// **不许用 `plannedStart + expectedDurationMinutes` 推。** 两个数是后端各自算的，
    /// 口径不保证一致。这条用例造一个两者明显对不上的订单：时长写 30 分钟，
    /// 而后端给的 `plannedEnd` 是 2 小时后 —— 显示的必须是后者。
    func testPlannedEndComesFromTheBackendFieldNotFromDuration() throws {
        let order = Self.makeOrder(
            status: .inProgress,
            plannedStart: "2026-08-13T09:00:00",
            plannedEnd: "2026-08-13T11:00:00",
            expectedDurationMinutes: 30
        )

        let text = try XCTUnwrap(order.plannedEndForAnnouncement)
        XCTAssertEqual(text, "2026-08-13T11:00:00".displayDateTime)
        XCTAssertNotEqual(text, "2026-08-13T09:30:00".displayDateTime, "结束时间不该由开始时间加时长推出来")
    }

    /// 缺了就不显示这一行，**不另找一个数顶上**。契约里 `plannedEnd` 是必填，
    /// 这里的宽容只是解码层面的，不是「允许自己算一个」。
    func testMissingPlannedEndHidesTheRowInsteadOfGuessing() {
        let order = Self.makeOrder(
            status: .inProgress,
            plannedStart: "2026-08-13T09:00:00",
            plannedEnd: nil,
            expectedDurationMinutes: 60
        )
        XCTAssertNil(order.plannedEndForAnnouncement)
    }

    // MARK: - 进主播报，不躺在折叠区里

    /// 服务进行中，「重复当前状态」必须念到约定的结束时间。
    ///
    /// 折叠在「预约信息」里等于没有：那是 `DisclosureGroup`，读屏用户跑步途中不会去展开
    /// 一段标着「已确认的信息」的折叠区。而后端在这个时间之后 15 分钟推 `ORDER_OVERDUE` ——
    /// 听不到这个约定，就无从判断那条告警是不是意外。
    func testInProgressAnnouncementSpeaksTheAgreedEndTime() {
        let order = Self.makeOrder(
            status: .inProgress,
            plannedStart: "2026-08-13T09:00:00",
            plannedEnd: "2026-08-13T10:30:00",
            expectedDurationMinutes: 90
        )
        let announcement = order.blindRunnerAnnouncement()

        XCTAssertTrue(announcement.contains("服务已开始"), "状态本身仍要先说")
        XCTAssertTrue(announcement.contains("2026-08-13T10:30:00".displayDateTime))
        XCTAssertTrue(announcement.contains("结束"))
    }

    /// 结束时间缺失时播报退回原样，不留半句「预计 结束」。
    func testInProgressAnnouncementDegradesCleanlyWithoutAnEndTime() {
        let order = Self.makeOrder(
            status: .inProgress,
            plannedStart: "2026-08-13T09:00:00",
            plannedEnd: nil,
            expectedDurationMinutes: 90
        )
        XCTAssertEqual(order.blindRunnerAnnouncement(), RunOrderStatus.inProgress.blindRunnerAnnouncement)
    }

    /// **只在 `IN_PROGRESS` 念。** 派单期、汇合期还没开始跑，念结束时间没有用；
    /// 每多一句都是读屏用户在主路径上多等的时间。终态更不该念一个「预计」。
    func testOtherStatusesDoNotAnnounceTheEndTime() {
        for status in RunOrderStatus.allCases where status != .inProgress {
            let order = Self.makeOrder(
                status: status,
                plannedStart: "2026-08-13T09:00:00",
                plannedEnd: "2026-08-13T10:30:00",
                expectedDurationMinutes: 90
            )
            XCTAssertFalse(
                order.blindRunnerAnnouncement().contains("2026-08-13T10:30:00".displayDateTime),
                "状态 \(status.rawValue) 不该念结束时间"
            )
        }
    }

    // MARK: - ORDER_OVERDUE 的展示优先级

    /// 后端盲人侧模板给的是 `NORMAL`（`websocket-protocol.md:158`），那会让「跑者可能失联」
    /// 排在派单进度那类通知后面、用蓝色铃铛、不带 header trait。
    /// 打断策略是客户端的设计边界（后端 2026-08-13 通报原话），所以在客户端抬。
    func testOverdueAlertIsElevatedEvenWhenTheServerSaysNormal() {
        XCTAssertEqual(
            AppRealtimeCoordinator.clientPriority(forEventType: "ORDER_OVERDUE", serverPriority: "NORMAL"),
            .high
        )
    }

    /// 志愿者侧后端本来就给 HIGH，抬完仍是 HIGH —— 两端行为一致，不因为来源不同而分叉。
    func testOverdueAlertStaysHighWhenTheServerAlreadySaysSo() {
        XCTAssertEqual(
            AppRealtimeCoordinator.clientPriority(forEventType: "ORDER_OVERDUE", serverPriority: "HIGH"),
            .high
        )
    }

    /// **只抬这一条。** 其余一律照后端模板走 —— 客户端把一堆通知都抬成 HIGH，
    /// 等于把优先级这个机制作废，真正的紧急事件再也抢不到位置。
    func testNoOtherEventTypeIsElevated() {
        for eventType in [
            "DISPATCH_STARTED", "DISPATCH_EXPANDING", "REMATCH_TIMEOUT",
            "ORDER_COMPLETED", "REMATCHING", "PROXIMITY_ALERT", "ORDER_ACCEPTED"
        ] {
            XCTAssertEqual(
                AppRealtimeCoordinator.clientPriority(forEventType: eventType, serverPriority: "NORMAL"),
                .normal,
                "\(eventType) 不该被抬"
            )
        }
        XCTAssertEqual(
            AppRealtimeCoordinator.clientPriority(forEventType: "ORDER_CANCELLATION_WARNING", serverPriority: "HIGH"),
            .high
        )
    }

    /// 未知 eventType 照后端给的走，不猜。
    func testUnknownEventTypeFollowsTheServer() {
        XCTAssertEqual(
            AppRealtimeCoordinator.clientPriority(forEventType: "SOMETHING_NEW", serverPriority: "HIGH"),
            .high
        )
        XCTAssertEqual(
            AppRealtimeCoordinator.clientPriority(forEventType: "SOMETHING_NEW", serverPriority: nil),
            .normal
        )
    }

    /// `ORDER_OVERDUE` **不改订单状态**，所以它不该被「订单页自己会播」那道闸吞掉。
    /// 吞掉的后果是超时告警在有活跃订单时（也就是它唯一会出现的时候）一个字都播不出去。
    func testOverdueAlertIsNotSwallowedByTheLifecycleSuppressionGate() {
        XCTAssertNil(
            AppRealtimeCoordinator.lifecycleStatus(forEventType: "ORDER_OVERDUE"),
            "ORDER_OVERDUE 不宣布任何订单状态，进了这张表就会在有活跃订单时被整条抑制"
        )
    }

    // MARK: - Fixtures

    private static func makeOrder(
        status: RunOrderStatus,
        plannedStart: String?,
        plannedEnd: String?,
        expectedDurationMinutes: Int?
    ) -> OrderDetailResponse {
        OrderDetailResponse(
            orderId: 7001,
            status: status,
            startAddress: "朝阳公园南门",
            startLatitude: 39.9342,
            startLongitude: 116.4740,
            endAddress: nil,
            endLatitude: nil,
            endLongitude: nil,
            plannedStart: plannedStart,
            plannedEnd: plannedEnd,
            blindName: nil,
            blindPhone: nil,
            volunteerPhone: nil,
            acceptedAt: nil,
            createdAt: nil,
            expectedDurationMinutes: expectedDurationMinutes,
            pacePreference: nil,
            routePreference: nil,
            routeNotes: nil,
            hasGuideDogThisRun: nil,
            specialNotes: nil,
            visionLevel: nil,
            tetherPreference: nil,
            chatPreference: nil
        )
    }
}
