import XCTest
@testable import blindRun

/// #376：跑步中收到 401 不清会话，保留本地求助，跑完 / 离开订单页 / 主动重新登录时再登出
/// （OpenSpec `defer-session-expiry-during-run`）。
///
/// 「暂缓」与「照旧登出」的分界选在 `IN_PROGRESS` 与 `DRIVER_ARRIVED` 之间：后者同样是陪跑会话里的状态
/// （`isSessionEligible` 为 true），按「会话里就暂缓」写错的实现在那条用例上会红。
@MainActor
final class SessionExpiryDeferralTests: XCTestCase {

    override func setUp() {
        super.setUp()
        EmergencyAlarm.observerForTesting = { _ in }
        EmergencyHaptics.observerForTesting = { _ in }
    }

    // MARK: - 暂缓与照旧登出

    func testUnauthorizedDuringTheRunKeepsTheSession() {
        let appState = Self.loggedInAppState(role: .blind)
        appState.liveEscortCoordinator.updateOwnedOrder(orderID: 42, status: .inProgress)

        XCTAssertTrue(appState.handleAuthenticatedAPIError(.unauthorized), "401 算已处理，调用方不再自己报错")

        XCTAssertEqual(appState.accessToken, "token-7", "跑步中不清会话")
        XCTAssertEqual(appState.activeRole, .blind)
        XCTAssertTrue(appState.isSessionExpiryDeferred)
        XCTAssertNil(appState.consumeSessionExpirationMessage(), "没有退回登录页")
        XCTAssertTrue(appState.emergencyCoordinator.blocksCloudSOSForExpiredSession, "云端求助同时被拦")
    }

    func testUnauthorizedOutsideTheRunStillExpiresTheSession() {
        for status in [RunOrderStatus.driverArrived, .driverEnRoute, .pendingAccept] {
            let appState = Self.loggedInAppState(role: .blind)
            appState.liveEscortCoordinator.updateOwnedOrder(orderID: 42, status: status)

            XCTAssertTrue(appState.handleAuthenticatedAPIError(.unauthorized))

            XCTAssertNil(appState.accessToken, "\(status) 时照旧登出")
            XCTAssertFalse(appState.isSessionExpiryDeferred)
            XCTAssertEqual(appState.consumeSessionExpirationMessage(), "登录已过期，请重新登录。")
        }

        let noOrder = Self.loggedInAppState(role: .volunteer)
        noOrder.handleAuthenticatedAPIError(.unauthorized)
        XCTAssertNil(noOrder.accessToken, "没有订单时照旧登出")
    }

    /// 陪跑员端同一条路径（订单页轮询 401 也走 `handleAuthenticatedAPIError`）。
    func testVolunteerDuringTheRunIsDeferredTooWithItsOwnCopy() {
        let appState = Self.loggedInAppState(role: .volunteer)
        appState.liveEscortCoordinator.updateOwnedOrder(orderID: 43, status: .inProgress)

        appState.handleAuthenticatedAPIError(.unauthorized)

        XCTAssertEqual(appState.accessToken, "token-7")
        let banner = appState.sessionExpiryDeferral?.bannerMessage ?? ""
        XCTAssertTrue(banner.contains("现在重新登录"), "陪跑员结束陪跑要先重新登录：\(banner)")
        XCTAssertTrue(banner.contains("App 不会代你发送求助"))
    }

    // MARK: - 告知

    func testBannerCopyStatesExpiryRunEndAndTheSOSRedLine() {
        let appState = Self.loggedInAppState(role: .blind)
        appState.liveEscortCoordinator.updateOwnedOrder(orderID: 42, status: .inProgress)
        appState.handleAuthenticatedAPIError(.unauthorized)

        let deferral = try? XCTUnwrap(appState.sessionExpiryDeferral)
        let banner = deferral?.bannerMessage ?? ""
        for phrase in ["登录已过期", "跑完后需要重新登录", "App 不会代你发送求助", "120", "110"] {
            XCTAssertTrue(banner.contains(phrase), "缺「\(phrase)」：\(banner)")
        }
        XCTAssertFalse(banner.contains("已发出"), "不许暗示求助已发出")
        XCTAssertEqual(deferral?.spokenMessage, banner, "第一次念横幅全文")
    }

    /// 暂缓中再收到 401：30 秒内不补念，过了才补念短句。
    func testRepeatedUnauthorizedIsRemindedAtMostEveryThirtySeconds() {
        let appState = Self.loggedInAppState(role: .blind)
        var now = Date(timeIntervalSince1970: 1_000)
        appState.sessionClock = { now }
        appState.liveEscortCoordinator.updateOwnedOrder(orderID: 42, status: .inProgress)

        appState.handleAuthenticatedAPIError(.unauthorized)
        XCTAssertEqual(appState.sessionExpiryDeferral?.announcementSerial, 1)

        now = now.addingTimeInterval(29)
        appState.handleAuthenticatedAPIError(.unauthorized)
        XCTAssertEqual(appState.sessionExpiryDeferral?.announcementSerial, 1, "29 秒：不补念")

        now = now.addingTimeInterval(2)
        appState.handleAuthenticatedAPIError(.unauthorized)
        XCTAssertEqual(appState.sessionExpiryDeferral?.announcementSerial, 2, "31 秒：补念")
        XCTAssertEqual(appState.sessionExpiryDeferral?.spokenMessage, appState.sessionExpiryDeferral?.reminderMessage)
        XCTAssertEqual(appState.accessToken, "token-7", "补念不等于登出")
    }

    // MARK: - 结束暂缓

    func testDeferralEndsWhenTheOwnedOrderLeavesInProgress() {
        let appState = Self.deferredAppState()

        appState.liveEscortCoordinator.updateOwnedOrder(orderID: 42, status: .completed)

        XCTAssertNil(appState.accessToken, "跑完就按原逻辑登出")
        XCTAssertFalse(appState.isSessionExpiryDeferred)
        XCTAssertEqual(appState.consumeSessionExpirationMessage(), "登录已过期，请重新登录。")
    }

    /// 暂缓期间 HTTP 都是 401，跑完往往只能从推送里知道。本地订单记录这里**不动**，只有推送那条订阅能结束暂缓。
    func testDeferralEndsOnARealtimePushThatTheRunFinished() async {
        let appState = Self.deferredAppState()
        let service = WebSocketService()
        appState.realtimeCoordinator.attach(to: service, role: .blind)
        appState.realtimeCoordinator.registerActiveOrder(42, status: .inProgress)

        service.simulateIncomingEventForTesting(.orderStatusChanged(WSOrderStatusChanged(
            type: WSMessageType.orderStatusChanged.rawValue,
            orderId: 42,
            fromStatus: "IN_PROGRESS",
            toStatus: "COMPLETED",
            message: nil,
            ttsText: nil,
            priority: "NORMAL",
            timestamp: "2026-10-09T08:00:00Z"
        )))
        await Task.yield()

        XCTAssertEqual(appState.liveEscortCoordinator.activeStatus, nil, "会话清掉后订单记录随之归零")
        XCTAssertNil(appState.accessToken, "推送说跑完了就登出")
        XCTAssertFalse(appState.isSessionExpiryDeferred)
    }

    /// 「现在重新登录」与跑者退出订单页都走 `endDeferredSessionExpiry`。重入（清会话 → 订单记录归零 →
    /// 订阅再进来）不许把登录页提示清掉或弄出第二次登出。
    func testEndingTheDeferralLogsOutExactlyOnce() {
        let appState = Self.deferredAppState()

        appState.endDeferredSessionExpiry()
        appState.endDeferredSessionExpiry()

        XCTAssertNil(appState.accessToken)
        XCTAssertFalse(appState.isSessionExpiryDeferred)
        XCTAssertFalse(appState.emergencyCoordinator.blocksCloudSOSForExpiredSession, "会话边界把求助闸复位")
        XCTAssertEqual(appState.consumeSessionExpirationMessage(), "登录已过期，请重新登录。")
    }

    func testEndingWithoutADeferralDoesNothing() {
        let appState = Self.loggedInAppState(role: .blind)
        appState.endDeferredSessionExpiry()
        XCTAssertEqual(appState.accessToken, "token-7", "没有暂缓时退出订单页不登出")
    }

    // MARK: - 求助

    /// 兜底：暂缓中任何漏网的云端触发都不发请求，文案守 §6 红线。
    func testCloudSOSIsNotSentWhileTheSessionIsExpired() async {
        let coordinator = EmergencyCoordinator()
        coordinator.blockCloudSOSForExpiredSession()
        let safety = FakeSafetyService()
        safety.triggerEmergencyResult = .success(EmergencyTriggerResponse(success: true, eventId: 1, status: "PENDING"))
        var locateCalls = 0

        let outcome = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { locateCalls += 1; return nil }
        )

        XCTAssertTrue(safety.calls.isEmpty, "一个请求都不许发")
        XCTAssertEqual(locateCalls, 0, "不让人白等定位")
        XCTAssertEqual(coordinator.state, .unsentSessionExpired)
        XCTAssertTrue(outcome.isFailure, "失败态才会带出本地拨号兜底按钮")
        for phrase in ["未发出", "App 不会代你发送求助", "120", "110"] {
            XCTAssertTrue(outcome.message.contains(phrase), "缺「\(phrase)」：\(outcome.message)")
        }
        XCTAssertEqual(EmergencySafetyCopy.screenTitle(for: .unsentSessionExpired, hasActiveEvent: false), "求助未发出")

        coordinator.reset()
        XCTAssertFalse(coordinator.blocksCloudSOSForExpiredSession, "新会话不继承")
    }

    /// 入口：跑步中登录过期时求助条 / 求助中心直接给本地拨号，而且每一句都不说「陪跑还没开始」。
    func testRunnerSOSEntryFallsBackToLocalCallWithRunAwareCopy() {
        let inProgress = Self.makeOrder(status: .inProgress)
        XCTAssertEqual(BlindHomeSOSMode.resolve(order: inProgress, role: .blind), .cloudTrigger)
        XCTAssertEqual(
            BlindHomeSOSMode.resolve(order: inProgress, role: .blind, isSessionExpired: true),
            .localCallSessionExpired
        )
        XCTAssertEqual(
            BlindHomeSOSMode.resolve(order: Self.makeOrder(status: .driverArrived), role: .blind, isSessionExpired: true),
            .localCall,
            "非跑步中本来就是本地拨号那一档"
        )

        let mode = BlindHomeSOSMode.localCallSessionExpired
        let context = EmergencyCallContext.runner(for: mode)
        XCTAssertEqual(context, .runnerSessionExpired)
        XCTAssertTrue(context.appendsNoContactHint, "跑者端照样列主紧急联系人")
        let sentences = [
            context.dialogMessage,
            context.accessibilityHint,
            EmergencySafetyCopy.hubSubtitle(for: mode),
            EmergencySafetyCopy.hubLocalCallNotice(for: mode) ?? ""
        ]
        for sentence in sentences {
            XCTAssertFalse(sentence.contains("还没开始"), sentence)
            XCTAssertFalse(sentence.contains("没有进行中"), sentence)
            XCTAssertFalse(sentence.contains("跑步仍在记录"), sentence)
        }
        XCTAssertTrue(context.dialogMessage.contains("App 不会代你发送求助"))
        XCTAssertTrue(EmergencySafetyCopy.hubLocalCallNotice(for: mode)?.contains("App 不会代你发送求助") == true)
        XCTAssertEqual(EmergencySafetyCopy.hubDismissTitle(for: mode), EmergencySafetyCopy.hubDismissTitle, "仍在跑步，退回跑步页")

        // 原有两档的映射不许被这次改动带偏。
        XCTAssertEqual(EmergencyCallContext.runner(for: .cloudTrigger), .cloudFailed)
        XCTAssertEqual(EmergencyCallContext.runner(for: .localCall), .homeIdle)
    }

    // MARK: - Helpers

    private static func loggedInAppState(role: UserRole) -> AppState {
        let appState = AppState(
            persistence: AppStatePersistenceFactory.makeIsolatedTest(),
            tokenStore: InMemoryTokenStore()
        )
        appState.currentEnvironment = .mock
        appState.accessToken = "token-7"
        appState.userId = 7
        appState.activeRole = role
        return appState
    }

    private static func deferredAppState() -> AppState {
        let appState = loggedInAppState(role: .blind)
        appState.liveEscortCoordinator.updateOwnedOrder(orderID: 42, status: .inProgress)
        appState.handleAuthenticatedAPIError(.unauthorized)
        XCTAssertTrue(appState.isSessionExpiryDeferred, "前提：已进入暂缓")
        return appState
    }

    private static func makeOrder(status: RunOrderStatus) -> OrderDetailResponse {
        OrderDetailResponse(
            orderId: 42,
            status: status,
            startAddress: "测试出发点",
            startLatitude: nil,
            startLongitude: nil,
            endAddress: nil,
            endLatitude: nil,
            endLongitude: nil,
            plannedStart: nil,
            plannedEnd: nil,
            blindName: nil,
            blindPhone: nil,
            volunteerPhone: "13800000000",
            acceptedAt: nil,
            createdAt: nil,
            expectedDurationMinutes: nil,
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
