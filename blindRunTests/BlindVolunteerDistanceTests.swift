import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class BlindVolunteerDistanceTests: XCTestCase, BlindRunTestSupport {
    func testBlindVolunteerDistanceUsesVolunteerLocationToStartPoint() {
        let order = makeOrder(orderId: 1, status: .driverEnRoute)
        let volunteerAtStart = CLLocationCoordinate2D(latitude: 39.9342, longitude: 116.4740)

        XCTAssertEqual(order.volunteerDistanceToStartText(from: volunteerAtStart), "距出发地点约 10 米")
        XCTAssertNil(order.volunteerDistanceToStartText(from: nil))

        let noCoordinateOrder = makeOrder(
            orderId: 1,
            status: .driverEnRoute,
            startLatitude: nil,
            startLongitude: nil
        )
        XCTAssertNil(noCoordinateOrder.volunteerDistanceToStartText(from: volunteerAtStart))
    }

    /// WebSocket 断线时的 REST 兜底必须吃得下**真实**后端响应。
    ///
    /// 后端 `GET /api/blind/volunteer-location` 的 `data` 现在是五个键：
    /// `lat` / `lng` / `orderId` / `status` / `updatedAt`（`api_spec.yaml:2352-2362`，
    /// 后端 `119c810` 于 2026-08-20 把 `orderStatus` 改名为 `status` 并补上了时间戳）。
    ///
    /// 这条用例的真正职责是**钉住 JSON 那一层**：上一版这里卡的是
    /// `let updatedAt = data.updatedAt.flatMap(parseISO8601)`，而后端当时压根不发这个字段
    /// ⇒ 兜底 100% 静默失效，「志愿者距出发地点约 X」在断线时永远不出现、一行日志都没有。
    /// 所以断言从「解得出坐标」开始，而不是从构造好的 `VolunteerLocationData` 开始。
    func testVolunteerLocationFallbackAcceptsTheRealBackendPayload() throws {
        let order = makeOrder(orderId: 1, status: .driverEnRoute)
        let capturedAt = Int64(Date().timeIntervalSince1970 * 1_000)
        let response = try JSONDecoder().decode(VolunteerLocationResponse.self, from: Data("""
        {"success":true,"code":200,"message":null,
         "data":{"lat":39.9342,"lng":116.4740,"orderId":1,
                 "status":"DRIVER_EN_ROUTE","updatedAt":\(capturedAt)}}
        """.utf8))

        let data = try XCTUnwrap(response.data)
        XCTAssertEqual(data.status, .driverEnRoute, "键名已从 orderStatus 改成 status，必须解得进来")
        XCTAssertEqual(data.updatedAt, capturedAt, "updatedAt 是 epoch 毫秒整数，不是 ISO-8601 字符串")

        let coordinate = try XCTUnwrap(
            BlindOrderStatusViewModel.volunteerFallbackCoordinate(from: response.data, matching: order),
            "新鲜的真实响应必须解得出坐标"
        )
        XCTAssertEqual(order.volunteerDistanceToStartText(from: coordinate), "距出发地点约 10 米")
    }

    /// 🔴 `status` 与本地不一致时**不得否掉坐标** —— 契约原话「坐标是这个端点存在的唯一理由」
    /// （`api_spec.yaml:2355-2357`）。
    ///
    /// 这条不是假想场景：`status` 与 `GET /api/orders/{id}` 同源、**同一时刻可能领先于**
    /// 客户端上一次轮询到的值，所以「不一致」在正常运行中就会出现。
    /// 而 2026-08-20 之前后端那个键叫 `orderStatus`，这个字段恒为 nil、比较从未真正执行过；
    /// 改名让它第一次生效 —— 把旧写法原样留着，等于在那一刻新增一条会静默吞掉坐标的分支。
    func testVolunteerLocationFallbackKeepsCoordinateWhenStatusDisagrees() throws {
        let order = makeOrder(orderId: 1, status: .driverEnRoute)
        let data = VolunteerLocationData(
            orderId: 1,
            status: .driverArrived,   // 后端已经领先一态
            updatedAt: Int64(Date().timeIntervalSince1970 * 1_000),
            lat: 39.9342,
            lng: 116.4740
        )

        XCTAssertNotNil(
            BlindOrderStatusViewModel.volunteerFallbackCoordinate(from: data, matching: order),
            "状态不一致只说明订单轮询还没跟上，不说明坐标是假的"
        )
    }

    /// `updatedAt` 缺失一律放行 —— 这道闸必须**失败开放**。
    ///
    /// 后端 2026-08-20 才补上这个字段，生产未必已部署；失败闭合就会原地重演它自己修的那个 bug
    /// （字段恒缺 ⇒ 恒 return ⇒ 兜底静默失效）。
    func testVolunteerLocationFallbackAcceptsPayloadWithoutTimestamp() {
        let order = makeOrder(orderId: 1, status: .driverEnRoute)
        let data = VolunteerLocationData(
            orderId: 1, status: nil, updatedAt: nil, lat: 39.9342, lng: 116.4740
        )

        XCTAssertNotNil(
            BlindOrderStatusViewModel.volunteerFallbackCoordinate(from: data, matching: order),
            "没有时间戳 ≠ 位置不可信；新鲜度还有服务端 Redis TTL 兜着"
        )
    }

    /// 有时间戳时才判新鲜度：过期挡掉，落在未来（设备时钟偏差）按「刚采样」放行。
    ///
    /// 未来时间戳放行是刻意的，与 WebSocket 那条 `handleVolunteerLocationUpdate` 的
    /// `max(0, ...)` 同口径 —— 用 `abs()` 的话，设备时钟快一分钟就会让整个兜底再次全灭。
    func testVolunteerLocationFallbackRejectsStaleButAcceptsFutureTimestamp() {
        let order = makeOrder(orderId: 1, status: .driverEnRoute)
        let now = Date()
        let freshness = BlindOrderStatusViewModel.volunteerFallbackFreshness

        func data(offsetSeconds: TimeInterval) -> VolunteerLocationData {
            VolunteerLocationData(
                orderId: 1,
                status: nil,
                updatedAt: Int64(now.addingTimeInterval(offsetSeconds).timeIntervalSince1970 * 1_000),
                lat: 39.9342,
                lng: 116.4740
            )
        }

        XCTAssertNil(
            BlindOrderStatusViewModel.volunteerFallbackCoordinate(
                from: data(offsetSeconds: -(freshness + 5)), matching: order, now: now
            ),
            "超过新鲜度阈值的位置不能再当作志愿者的当前位置"
        )
        XCTAssertNotNil(
            BlindOrderStatusViewModel.volunteerFallbackCoordinate(
                from: data(offsetSeconds: -(freshness - 5)), matching: order, now: now
            ),
            "阈值之内必须放行"
        )
        XCTAssertNotNil(
            BlindOrderStatusViewModel.volunteerFallbackCoordinate(
                from: data(offsetSeconds: 120), matching: order, now: now
            ),
            "时间戳落在未来是时钟偏差，不是位置过期 —— 不得因此丢坐标"
        )
    }

    /// 兜底不是无条件采信：别单的坐标和越界坐标仍要挡掉。
    func testVolunteerLocationFallbackRejectsForeignOrderAndInvalidCoordinate() {
        let order = makeOrder(orderId: 1, status: .driverEnRoute)

        XCTAssertNil(BlindOrderStatusViewModel.volunteerFallbackCoordinate(from: nil, matching: order))
        XCTAssertNil(BlindOrderStatusViewModel.volunteerFallbackCoordinate(
            from: VolunteerLocationData(orderId: 2, status: nil, updatedAt: nil, lat: 39.9342, lng: 116.4740),
            matching: order
        ))
        XCTAssertNil(BlindOrderStatusViewModel.volunteerFallbackCoordinate(
            from: VolunteerLocationData(orderId: 1, status: nil, updatedAt: nil, lat: 91, lng: 116.4740),
            matching: order
        ))
        XCTAssertNil(BlindOrderStatusViewModel.volunteerFallbackCoordinate(
            from: VolunteerLocationData(orderId: 1, status: nil, updatedAt: nil, lat: nil, lng: nil),
            matching: order
        ))
    }

    func testBlindRunnerAnnouncementIncludesDistanceForTrackingStates() {
        let distanceText = "距出发地点约 10 米"
        for status in [RunOrderStatus.pendingAccept, .driverEnRoute, .driverArrived] {
            let announcement = makeOrder(orderId: 1, status: status)
                .blindRunnerAnnouncement(distanceText: distanceText)

            XCTAssertTrue(
                announcement.contains(distanceText),
                "\(status.rawValue) announcement should include volunteer distance to the start point"
            )
            XCTAssertFalse(announcement.contains("距您"))
        }
    }

    // 下面三条 2026-11-08 随 `unify-order-live-tracking` 第 2 批（#887）改写：页面不再自己判新鲜度、
    // 不再排过期任务，样本改经订单跟踪送进来（`OrderLiveTracker.receivePeerLocation`，
    // 与协调器发布点调的是同一个入口）。页面只经 `openOrderTrackIfNeeded` 打开 track、不走 `configure`，
    // 于是 `appState` 为 nil、`loadOrder` 直接返回，轮询不会拿 Mock 详情盖掉用例摆好的订单。

    func testBlindOrderStatusViewModelTracksVolunteerDistanceToStart() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let viewModel = followingOrderPage(orderId: 1, status: .driverEnRoute, appState: appState)
        let tracker = appState.realtimeCoordinator.orderLiveTracker

        tracker.receivePeerLocation(volunteerSample(orderId: 1, latitude: 39.9342, longitude: 116.4740))
        await drainTrackEvents()

        XCTAssertEqual(viewModel.volunteerDistanceToStartText, "距出发地点约 10 米")

        tracker.receivePeerLocation(volunteerSample(orderId: 2, latitude: 39.9042, longitude: 116.4074))
        await drainTrackEvents()

        XCTAssertEqual(viewModel.volunteerDistanceToStartText, "距出发地点约 10 米", "别的单的位置不许改这一单的距离")
    }

    func testBlindPeerSampleExpiryUsesLatestSampleAndIgnoresWrongOrder() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let viewModel = followingOrderPage(orderId: 31, status: .driverEnRoute, appState: appState, peerFreshness: 0.12)
        let tracker = appState.realtimeCoordinator.orderLiveTracker
        tracker.receivePeerLocation(volunteerSample(orderId: 31, latitude: 39.9342, longitude: 116.4740))
        await drainTrackEvents()
        XCTAssertNotNil(viewModel.latestVolunteerSample)

        try await Task.sleep(nanoseconds: 70_000_000)
        let second = volunteerSample(orderId: 31, latitude: 39.9343, longitude: 116.4741)
        tracker.receivePeerLocation(second)
        tracker.receivePeerLocation(volunteerSample(orderId: 99, latitude: 31.2, longitude: 121.5))

        try await Task.sleep(nanoseconds: 70_000_000)
        XCTAssertEqual(
            try XCTUnwrap(viewModel.latestVolunteerSample).coordinate.latitude,
            second.latitude,
            accuracy: 0.000_001
        )

        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertNil(viewModel.latestVolunteerSample)
        XCTAssertNil(viewModel.volunteerDistanceToStartText)
    }

    func testBlindPeerSampleStopCancelsExpiry() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let viewModel = followingOrderPage(orderId: 32, status: .driverArrived, appState: appState, peerFreshness: 0.04)
        let tracker = appState.realtimeCoordinator.orderLiveTracker
        tracker.receivePeerLocation(volunteerSample(orderId: 32, latitude: 39.9342, longitude: 116.4740))
        await drainTrackEvents()
        XCTAssertNotNil(viewModel.latestVolunteerSample)

        viewModel.stopPolling()
        XCTAssertNil(viewModel.latestVolunteerSample, "离页当场清，不等跟踪那边的过期事件")
        tracker.receivePeerLocation(volunteerSample(orderId: 32, latitude: 31.2, longitude: 121.5))
        await drainTrackEvents()

        XCTAssertNil(viewModel.latestVolunteerSample, "离页后的样本不许再落到页面上")
        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertNil(viewModel.latestVolunteerSample)
    }

    private func followingOrderPage(
        orderId: Int64,
        status: RunOrderStatus,
        appState: AppState,
        peerFreshness: TimeInterval = LiveEscortSessionCoordinator.peerFreshness
    ) -> BlindOrderStatusViewModel {
        let viewModel = BlindOrderStatusViewModel(peerFreshness: peerFreshness)
        viewModel.order = makeOrder(orderId: orderId, status: status)
        viewModel.openOrderTrackIfNeeded(appState: appState)
        viewModel.startPolling(orderId: orderId)
        return viewModel
    }

    private func volunteerSample(orderId: Int64, latitude: Double, longitude: Double) -> RealtimePeerLocationSample {
        RealtimePeerLocationSample(
            orderId: orderId,
            ownerRole: .volunteer,
            latitude: latitude,
            longitude: longitude,
            timestampMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000)
        )
    }

    /// 跟踪的事件经 `AsyncStream` 到页面，晚一拍；让消费任务把已入队的事件处理完。
    private func drainTrackEvents() async {
        for _ in 0..<5 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }

    // `testBlindOrderStatusSuppressesLifecycleAppNotificationSpeech` 随被测函数一起删除
    // （2026-08-09）。它是那段死代码唯一的调用者，覆盖的是一条生产上走不到的路径。
    // 抑制行为现在由 `AppRealtimeCoordinatorTests` 的 eventType 用例守着。

    func testBlindRunnerRematchingOrderShowsCancelAction() {
        let statusViewModel = BlindOrderStatusViewModel()
        statusViewModel.order = makeOrder(orderId: 1, status: .rematching)

        XCTAssertTrue(statusViewModel.canShowCancel)

        let homeViewModel = BlindRunnerHomeViewModel()
        homeViewModel.activeOrder = makeOrder(orderId: 1, status: .rematching)

        XCTAssertTrue(homeViewModel.canCancelActiveOrder)
    }

    func testBlindRunnerHomeRepeatStatusIncludesOrderTimeAndLocationContext() {
        let speechService = SpeechService()
        let viewModel = BlindRunnerHomeViewModel()
        viewModel.configure(with: AppState(), speechService: speechService)
        viewModel.activeOrder = makeOrder(orderId: 1, status: .pendingAccept)

        viewModel.repeatCurrentStatus(locationDescription: "订单出发点：朝阳公园南门。当前位置：已获取设备定位。")

        XCTAssertTrue(speechService.lastSpokenText?.contains("陪跑员已接单") == true)
        XCTAssertTrue(speechService.lastSpokenText?.contains("预约时间：") == true)
        XCTAssertTrue(speechService.lastSpokenText?.contains("出发地点：朝阳公园南门") == true)
        XCTAssertTrue(speechService.lastVoiceOverAnnouncement?.contains("出发地点：朝阳公园南门") == true)
    }

    func testBlindRunnerInProgressOrderDoesNotShowCancelAction() {
        let statusViewModel = BlindOrderStatusViewModel()
        statusViewModel.order = makeOrder(orderId: 1, status: .inProgress)

        XCTAssertFalse(statusViewModel.canShowCancel)

        let homeViewModel = BlindRunnerHomeViewModel()
        homeViewModel.activeOrder = makeOrder(orderId: 1, status: .inProgress)

        XCTAssertFalse(homeViewModel.canCancelActiveOrder)
    }

    func testFormalOrderStatusRoutingAndFinishEligibility() {
        XCTAssertEqual(RunOrderStatus.pendingMatch.blindRunnerRoute, .tracking)
        XCTAssertEqual(RunOrderStatus.driverArrived.blindRunnerRoute, .tracking)
        XCTAssertEqual(RunOrderStatus.inProgress.blindRunnerRoute, .inService)
        XCTAssertEqual(RunOrderStatus.completed.blindRunnerRoute, .completion)
        XCTAssertEqual(RunOrderStatus.cancelled.blindRunnerRoute, .terminal)

        XCTAssertFalse(RunOrderStatus.driverArrived.canFinishService)
        XCTAssertTrue(RunOrderStatus.inProgress.canFinishService)
        // 这一句只给陪跑员听：不许再说「请等待志愿者」（原先与盲人端共用一句）。
        XCTAssertTrue(RunOrderStatus.driverArrived.finishBlockedMessage.contains("开始跑步"))
        XCTAssertFalse(RunOrderStatus.driverArrived.finishBlockedMessage.contains("等待志愿者"))
    }
}
