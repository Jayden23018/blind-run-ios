//
//  NotificationCatchUpTests.swift
//  blindRunTests
//
//  重连补读（GET /api/notifications/since）与 APNs 上报接线。
//  契约来源：demo/docs/api_spec.yaml + demo/.claude/rules/notifications-sms.md。
//

import XCTest
@testable import blindRun

/// 记录请求并按路径返回预置结果的桩。
private final class CatchUpAPIClientStub: APIClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [(path: String, query: [String: String]?)] = []
    var requests: [(path: String, query: [String: String]?)] {
        lock.withLock { _requests }
    }

    var missed: [MissedNotificationResponse] = []
    var shouldFail = false

    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        lock.withLock { _requests.append((path, query)) }
        if shouldFail {
            throw APIError.serverError(ErrorResponse(code: "INVALID_TIMESTAMP", message: "after 格式错误"))
        }
        guard let typed = missed as? T else {
            throw APIError.decodingError(
                DecodingError.typeMismatch(
                    T.self,
                    DecodingError.Context(codingPath: [], debugDescription: "unexpected \(path)")
                )
            )
        }
        return typed
    }

    func upload<T: Decodable>(
        path: String,
        query: [String: String]?,
        fields: [String: String]?,
        files: [MultipartFile],
        requiresAuth: Bool
    ) async throws -> T {
        throw APIError.invalidURL
    }
}

@MainActor
final class NotificationCatchUpTests: XCTestCase {

    private func makeMissed(
        id: Int64,
        body: String,
        ttsText: String? = nil,
        priority: String? = "NORMAL",
        sentAt: String?
    ) -> MissedNotificationResponse {
        MissedNotificationResponse(
            id: id,
            eventType: "ORDER_ACCEPTED",
            body: body,
            ttsText: ttsText,
            priority: priority,
            sentAt: sentAt,
            orderId: nil
        )
    }

    // MARK: - ingestCatchUp

    func testCatchUpNotificationsArePresentedInSentOrder() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)

        coordinator.ingestCatchUp([
            makeMissed(id: 2, body: "后到的通知", sentAt: "2026-07-24T10:05:00"),
            makeMissed(id: 1, body: "先到的通知", sentAt: "2026-07-24T10:01:00")
        ])

        XCTAssertEqual(coordinator.currentNotification?.displayText, "先到的通知")
        coordinator.dismissCurrentNotification()
        XCTAssertEqual(coordinator.currentNotification?.displayText, "后到的通知")
    }

    func testCatchUpPrefersTtsTextForSpeech() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)

        coordinator.ingestCatchUp([
            makeMissed(id: 7, body: "志愿者已接单", ttsText: "志愿者已接单，请在原地等待", sentAt: "2026-07-24T10:01:00")
        ])

        XCTAssertEqual(coordinator.currentNotification?.displayText, "志愿者已接单")
        XCTAssertEqual(coordinator.currentNotification?.speechText, "志愿者已接单，请在原地等待")
    }

    func testCatchUpDeduplicatesRepeatedDatabaseIDs() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let entry = makeMissed(id: 42, body: "重复投递的通知", sentAt: "2026-07-24T10:01:00")

        coordinator.ingestCatchUp([entry])
        coordinator.ingestCatchUp([entry])
        coordinator.dismissCurrentNotification()

        XCTAssertNil(coordinator.currentNotification)
    }

    func testCatchUpSkipsBlankBodiesButStillAdvancesCursor() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)

        coordinator.ingestCatchUp([
            makeMissed(id: 3, body: "   ", sentAt: "2026-07-24T10:09:00")
        ])

        XCTAssertNil(coordinator.currentNotification)
        XCTAssertEqual(coordinator.lastObservedNotificationTimestamp, "2026-07-24T10:09:00")
    }

    func testCursorOnlyMovesForward() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)

        coordinator.ingestCatchUp([
            makeMissed(id: 1, body: "新的", sentAt: "2026-07-24T10:05:00")
        ])
        // 后端补发一条更旧的记录时，游标不能回退，否则下次重连会重复补读整段窗口。
        coordinator.ingestCatchUp([
            makeMissed(id: 2, body: "更旧的", sentAt: "2026-07-24T09:00:00")
        ])

        XCTAssertEqual(coordinator.lastObservedNotificationTimestamp, "2026-07-24T10:05:00")
    }

    func testLiveNotificationAdvancesCatchUpCursor() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)

        service.simulateIncomingEventForTesting(.notification(WSAppNotification(
            type: WSMessageType.appNotification.rawValue,
            eventId: 1,
            eventType: "ORDER_ACCEPTED",
            title: nil,
            body: "实时通知",
            ttsText: "实时通知",
            priority: "NORMAL",
            timestamp: "2026-07-24T11:00:00"
        )))
        await Task.yield()

        XCTAssertEqual(coordinator.lastObservedNotificationTimestamp, "2026-07-24T11:00:00")
    }

    // MARK: - AppState 游标持久化

    func testCatchUpPersistsCursorThroughPersistenceFacadeNotStandardDefaults() async {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        let stub = CatchUpAPIClientStub()
        stub.missed = [makeMissed(id: 5, body: "错过的通知", sentAt: "2026-07-24T12:00:00")]
        let appState = AppState(apiClient: stub, persistence: persistence, tokenStore: InMemoryTokenStore())
        appState.accessToken = "token"
        persistence.set("2026-07-24T10:00:00", forKey: AppConstants.UserDefaultsKeys.lastSeenNotificationTimestamp)
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.lastSeenNotificationTimestamp)

        await appState.catchUpMissedNotifications()

        XCTAssertEqual(stub.requests.map(\.path), ["/api/notifications/since"])
        XCTAssertEqual(stub.requests.first?.query?["after"], "2026-07-24T10:00:00")
        XCTAssertEqual(
            persistence.string(forKey: AppConstants.UserDefaultsKeys.lastSeenNotificationTimestamp),
            "2026-07-24T12:00:00"
        )
        // 测试隔离：绝不能落到 App 的标准域。
        XCTAssertNil(
            UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.lastSeenNotificationTimestamp)
        )
        XCTAssertEqual(appState.realtimeCoordinator.currentNotification?.displayText, "错过的通知")

        persistence.reset()
    }

    func testCatchUpIsSkippedWithoutCursor() async {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        let stub = CatchUpAPIClientStub()
        let appState = AppState(apiClient: stub, persistence: persistence, tokenStore: InMemoryTokenStore())
        appState.accessToken = "token"

        await appState.catchUpMissedNotifications()

        XCTAssertTrue(stub.requests.isEmpty)
        persistence.reset()
    }

    func testCatchUpIsSkippedWhenLoggedOut() async {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        let stub = CatchUpAPIClientStub()
        let appState = AppState(apiClient: stub, persistence: persistence, tokenStore: InMemoryTokenStore())
        persistence.set("2026-07-24T10:00:00", forKey: AppConstants.UserDefaultsKeys.lastSeenNotificationTimestamp)

        await appState.catchUpMissedNotifications()

        XCTAssertTrue(stub.requests.isEmpty)
        persistence.reset()
    }

    func testCatchUpFailureLeavesCursorUnchanged() async {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        let stub = CatchUpAPIClientStub()
        stub.shouldFail = true
        let appState = AppState(apiClient: stub, persistence: persistence, tokenStore: InMemoryTokenStore())
        appState.accessToken = "token"
        persistence.set("2026-07-24T10:00:00", forKey: AppConstants.UserDefaultsKeys.lastSeenNotificationTimestamp)

        await appState.catchUpMissedNotifications()

        XCTAssertEqual(
            persistence.string(forKey: AppConstants.UserDefaultsKeys.lastSeenNotificationTimestamp),
            "2026-07-24T10:00:00"
        )
        persistence.reset()
    }

    // MARK: - APNs

    func testApnsSpeechPrefersTtsTextOverBody() {
        XCTAssertEqual(
            PushNotificationsManager.speechText(userInfo: ["ttsText": "口播版本"], fallbackBody: "横幅正文"),
            "口播版本"
        )
        XCTAssertEqual(
            PushNotificationsManager.speechText(userInfo: ["ttsText": "   "], fallbackBody: "横幅正文"),
            "横幅正文"
        )
        XCTAssertEqual(
            PushNotificationsManager.speechText(userInfo: [:], fallbackBody: "横幅正文"),
            "横幅正文"
        )
    }

    func testApnsTokenRequestEncodesBackendContract() throws {
        let data = try JSONEncoder().encode(ApnsTokenRequest(deviceToken: String(repeating: "a", count: 64)))
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(decoded["deviceToken"] as? String, String(repeating: "a", count: 64))
        XCTAssertEqual(decoded["platform"] as? String, "IOS")
    }

    func testMockRejectsMalformedApnsToken() async throws {
        let mock = MockAPIClient()
        mock.syncSessionFromAppState(token: "mock-token", role: .blind)

        do {
            let _: EmptyResponse = try await mock.post(
                "/api/devices/apns",
                body: ApnsTokenRequest(deviceToken: "not-hex")
            )
            XCTFail("非法 deviceToken 应被 Mock 拒绝")
        } catch let APIError.serverError(response) {
            XCTAssertEqual(response.code, "VALIDATION_ERROR")
        }

        let token = String(repeating: "0a", count: 32)
        let _: EmptyResponse = try await mock.post("/api/devices/apns", body: ApnsTokenRequest(deviceToken: token))
        XCTAssertTrue(mock.registeredApnsTokens.contains(token))
    }

    func testMockRejectsEpochMillisecondAfterParameter() async {
        let mock = MockAPIClient()
        mock.syncSessionFromAppState(token: "mock-token", role: .blind)

        do {
            let _: [MissedNotificationResponse] = try await mock.get(
                "/api/notifications/since",
                query: ["after": "1753344000000"]
            )
            XCTFail("epoch 毫秒应被拒绝：后端 after 只接受 ISO-8601")
        } catch let APIError.serverError(response) {
            XCTAssertEqual(response.code, "INVALID_TIMESTAMP")
        } catch {
            XCTFail("期望 INVALID_TIMESTAMP，实际 \(error)")
        }
    }

    // MARK: - 死消息类型

    func testSeparationAlertMessageTypeIsNotDecoded() {
        // 后端从不下发 type=SEPARATION_ALERT（demo/docs/websocket-protocol.md）。
        // 走散告警只走 APP_NOTIFICATION + eventType，见 LiveEscortTrackTests。
        XCTAssertNil(WSMessageType(rawValue: "SEPARATION_ALERT"))
    }
}
