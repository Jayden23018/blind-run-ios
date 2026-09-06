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
    /// 每页条数。真后端是 50，桩里可调小，好用三五条语料就走到续读那条路。
    var pageSize = 50
    var shouldFail = false
    /// 坏后端：无论还有没有剩余都回 `hasMore = true`，且游标照常前进 ——
    /// 专门用来验循环上限，不是验 `next > cursor` 那道保险。
    var alwaysClaimsHasMore = false

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
        let result = page(after: query?["after"] ?? "", callIndex: requests.count)
        guard let typed = result as? T else {
            throw APIError.decodingError(
                DecodingError.typeMismatch(
                    T.self,
                    DecodingError.Context(codingPath: [], debugDescription: "unexpected \(path)")
                )
            )
        }
        return typed
    }

    /// 照后端行为切页：`sent_at > after`、正序、每页 `pageSize` 条，还有剩就 `hasMore = true`。
    private func page(after: String, callIndex: Int) -> MissedNotificationPage {
        if alwaysClaimsHasMore {
            // 每次给一条更晚的，让游标真的前进 —— 否则 `next > cursor` 会先把循环收掉，
            // 上限就成了永远走不到的死代码。
            let fabricated = MissedNotificationResponse(
                id: Int64(callIndex),
                eventType: "ORDER_ACCEPTED",
                body: "第 \(callIndex) 条",
                ttsText: nil,
                priority: "NORMAL",
                sentAt: String(format: "2026-07-24T%02d:00:00", min(callIndex, 23)),
                orderId: nil
            )
            return MissedNotificationPage(notifications: [fabricated], hasMore: true)
        }
        let window = missed
            .filter { ($0.sentAt ?? "") > after }
            .sorted { ($0.sentAt ?? "") < ($1.sentAt ?? "") }
        let page = Array(window.prefix(pageSize))
        return MissedNotificationPage(notifications: page, hasMore: window.count > page.count)
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

    /// 回前台（`blindRunApp.swift` 的 scenePhase handler）在 WS 重连之外再补读一次。
    /// 补读没有服务端游标，多调一次本身无害 —— 前提是 `missed:{id}` 去重真的挡住重播：
    /// 对盲人来说同一条通知被念第二遍，等于凭空多收到一条消息。
    func testRepeatedCatchUpDoesNotReplayTheSameNotification() async {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        let stub = CatchUpAPIClientStub()
        stub.missed = [makeMissed(id: 5, body: "错过的通知", sentAt: "2026-07-24T12:00:00")]
        let appState = AppState(apiClient: stub, persistence: persistence, tokenStore: InMemoryTokenStore())
        appState.accessToken = "token"
        persistence.set("2026-07-24T10:00:00", forKey: AppConstants.UserDefaultsKeys.lastSeenNotificationTimestamp)

        await appState.catchUpMissedNotifications()  // WS 重连那条路
        await appState.catchUpMissedNotifications()  // 回前台那条路

        // 两次都必须真的发出去：不许为此加节流，否则回前台这条路会被重连那次吃掉。
        XCTAssertEqual(
            stub.requests.map(\.path),
            ["/api/notifications/since", "/api/notifications/since"]
        )
        // 第二次带的是已推进的游标，不会把整段窗口重拉一遍。
        XCTAssertEqual(stub.requests.last?.query?["after"], "2026-07-24T12:00:00")

        XCTAssertEqual(appState.realtimeCoordinator.currentNotification?.displayText, "错过的通知")
        appState.realtimeCoordinator.dismissCurrentNotification()
        XCTAssertNil(appState.realtimeCoordinator.currentNotification, "同一条通知不得被念第二遍")

        persistence.reset()
    }

    // MARK: - hasMore 续读（契约 api_spec.yaml:3329）

    /// 后端每页最多 50 条，只拉第一页会让离线久的盲人静默丢掉其余通知 ——
    /// 而离线越久，漏掉的那批越是最该被听见的。
    func testCatchUpFollowsHasMoreUntilTheWindowIsDrained() async {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        let stub = CatchUpAPIClientStub()
        stub.pageSize = 2
        stub.missed = (1...5).map {
            makeMissed(id: Int64($0), body: "第 \($0) 条", sentAt: String(format: "2026-07-24T10:0%d:00", $0))
        }
        let appState = AppState(apiClient: stub, persistence: persistence, tokenStore: InMemoryTokenStore())
        appState.accessToken = "token"
        persistence.set("2026-07-24T10:00:00", forKey: AppConstants.UserDefaultsKeys.lastSeenNotificationTimestamp)

        await appState.catchUpMissedNotifications()

        // 2 + 2 + 1：末页 hasMore = false，不多发第四次。
        XCTAssertEqual(stub.requests.count, 3)
        // 每一轮都拿上一页最后一条的 sentAt 当新的 after。
        XCTAssertEqual(
            stub.requests.map { $0.query?["after"] },
            ["2026-07-24T10:00:00", "2026-07-24T10:02:00", "2026-07-24T10:04:00"]
        )

        // 5 条全部喂回队列 —— 这才是这条链存在的理由，只数请求次数不算数。
        var delivered: [String] = []
        for _ in 0..<10 {  // 有界，免得队列不清空时整个套件挂在这里
            guard let current = appState.realtimeCoordinator.currentNotification else { break }
            delivered.append(current.displayText)
            appState.realtimeCoordinator.dismissCurrentNotification()
        }
        XCTAssertEqual(delivered, (1...5).map { "第 \($0) 条" })

        XCTAssertEqual(
            persistence.string(forKey: AppConstants.UserDefaultsKeys.lastSeenNotificationTimestamp),
            "2026-07-24T10:05:00"
        )
        persistence.reset()
    }

    /// 反向条件：`hasMore = false` 时**不得**多发一次。多发那次带的是已推进的游标，
    /// 后端每次重连都白跑一趟。
    func testSinglePageCatchUpDoesNotIssueASecondRequest() async {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        let stub = CatchUpAPIClientStub()
        stub.pageSize = 50
        stub.missed = [
            makeMissed(id: 1, body: "第 1 条", sentAt: "2026-07-24T10:01:00"),
            makeMissed(id: 2, body: "第 2 条", sentAt: "2026-07-24T10:02:00")
        ]
        let appState = AppState(apiClient: stub, persistence: persistence, tokenStore: InMemoryTokenStore())
        appState.accessToken = "token"
        persistence.set("2026-07-24T10:00:00", forKey: AppConstants.UserDefaultsKeys.lastSeenNotificationTimestamp)

        await appState.catchUpMissedNotifications()

        XCTAssertEqual(stub.requests.count, 1)
        persistence.reset()
    }

    /// 后端坏成恒回 `hasMore = true` 时循环必须自己停下。
    /// 这条链跑在 WS 重连回调里，转不完就是盲人的手机在原地烧电、后面的实时通知排在它后面。
    func testCatchUpStopsAtThePageLimitWhenBackendNeverSaysDone() async {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        let stub = CatchUpAPIClientStub()
        stub.alwaysClaimsHasMore = true
        let appState = AppState(apiClient: stub, persistence: persistence, tokenStore: InMemoryTokenStore())
        appState.accessToken = "token"
        persistence.set("2026-07-24T00:00:00", forKey: AppConstants.UserDefaultsKeys.lastSeenNotificationTimestamp)

        await appState.catchUpMissedNotifications()

        XCTAssertEqual(stub.requests.count, AppState.catchUpPageLimit)
        persistence.reset()
    }

    /// 空页却说 `hasMore = true` 时同样要停：游标是从本页内容里取的，页里没内容就推不动，
    /// 拿同一个 `after` 一路问到上限才停是白烧十次请求。
    func testCatchUpStopsWhenTheCursorCannotAdvance() async {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        let stub = CatchUpAPIClientStub()
        // pageSize 0 造出「窗口里还有、但本页一条没返回」这个形状：hasMore = true 而游标无从推进。
        stub.pageSize = 0
        stub.missed = [makeMissed(id: 1, body: "还在窗口里", sentAt: "2026-07-24T10:01:00")]
        let appState = AppState(apiClient: stub, persistence: persistence, tokenStore: InMemoryTokenStore())
        appState.accessToken = "token"
        persistence.set("2026-07-24T10:00:00", forKey: AppConstants.UserDefaultsKeys.lastSeenNotificationTimestamp)

        await appState.catchUpMissedNotifications()

        XCTAssertEqual(stub.requests.count, 1)
        persistence.reset()
    }

    /// Mock 必须能演出多页，否则这条路在开发期永远走不到 —— 上线后才发现等于没做。
    func testMockPagesTheCatchUpWindowSoTheLoopIsReachableInDevelopment() async throws {
        let mock = MockAPIClient()
        mock.syncSessionFromAppState(token: "mock-token", role: .blind)
        mock.missedNotifications = (1...5).map {
            MissedNotificationResponse(
                id: Int64($0),
                eventType: "ORDER_ACCEPTED",
                body: "第 \($0) 条",
                ttsText: nil,
                priority: "NORMAL",
                sentAt: String(format: "2026-07-24T10:0%d:00", $0),
                orderId: nil
            )
        }

        let first: MissedNotificationPage = try await mock.get(
            "/api/notifications/since",
            query: ["after": "2026-07-24T10:00:00"]
        )
        XCTAssertEqual(first.hasMore, true, "Mock 页大小照搬 50 的话这里永远是 false")
        let cursor = try XCTUnwrap(first.notifications.compactMap(\.sentAt).max())

        let second: MissedNotificationPage = try await mock.get(
            "/api/notifications/since",
            query: ["after": cursor]
        )
        XCTAssertEqual(second.hasMore, false)
        XCTAssertEqual(
            (first.notifications + second.notifications).map(\.id),
            [1, 2, 3, 4, 5],
            "两页拼起来必须是完整窗口，不能漏也不能重"
        )
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

    /// F4：登出必须解绑本机 token，而且**必须在 `POST /api/auth/logout` 之前**。
    ///
    /// 顺序反了的后果在 Mock 上也是真的：logout 清掉 `mockToken` 之后，解绑会抛 `unauthorized`，
    /// token 留在服务端、绑在旧 userId 上，旧账号的 HIGH 推送继续送到这台手机并被前台**朗读出来**。
    func testLogoutUnbindsTheDeviceTokenBeforeBlacklistingTheJWT() async throws {
        let mock = MockAPIClient()
        mock.syncSessionFromAppState(token: "mock-token", role: .blind)
        let token = String(repeating: "0a", count: 32)
        let _: EmptyResponse = try await mock.post("/api/devices/apns", body: ApnsTokenRequest(deviceToken: token))
        XCTAssertTrue(mock.registeredApnsTokens.contains(token))

        // 正确顺序：先解绑
        let _: EmptyResponse = try await mock.request(
            method: .delete,
            path: "/api/devices/apns",
            query: nil,
            body: ApnsTokenRequest(deviceToken: token),
            requiresAuth: true
        )
        XCTAssertFalse(mock.registeredApnsTokens.contains(token), "解绑之后 token 不该还绑在这个账号上")

        // 幂等：再解绑一次同样成功，所以「失败不阻断登出、下次重试」是安全的。
        let _: EmptyResponse = try await mock.request(
            method: .delete,
            path: "/api/devices/apns",
            query: nil,
            body: ApnsTokenRequest(deviceToken: token),
            requiresAuth: true
        )
    }

    /// 反向条件：顺序反了会 401 —— 这条钉住「为什么解绑必须排在 logout 之前」。
    func testUnbindingAfterLogoutIsRejectedSoTheOrderCannotBeSwapped() async throws {
        let mock = MockAPIClient()
        mock.syncSessionFromAppState(token: "mock-token", role: .blind)
        let token = String(repeating: "0a", count: 32)
        let _: EmptyResponse = try await mock.post("/api/devices/apns", body: ApnsTokenRequest(deviceToken: token))

        mock.syncSessionFromAppState(token: nil, role: nil)  // logout 之后 JWT 已失效

        do {
            let _: EmptyResponse = try await mock.request(
                method: .delete,
                path: "/api/devices/apns",
                query: nil,
                body: ApnsTokenRequest(deviceToken: token),
                requiresAuth: true
            )
            XCTFail("logout 之后解绑必须失败，否则这条顺序约束等于没有")
        } catch APIError.unauthorized {
            XCTAssertTrue(mock.registeredApnsTokens.contains(token), "顺序反了的后果就是 token 删不掉")
        }
    }

    /// APNs 上报的去重键必须带上后端与账号：只比 token 会让切环境 / 换账号后
    /// 同一个 device token 被永久短路，新后端收不到注册，推送静默失效。
    func testApnsReportScopeIsKeyedByEnvironmentAndAccount() {
        let token = String(repeating: "0a", count: 32)
        let reported = PushNotificationsManager.ReportedTokenScope(
            token: token, environment: .mock, userId: 1
        )

        XCTAssertEqual(
            reported,
            PushNotificationsManager.ReportedTokenScope(token: token, environment: .mock, userId: 1),
            "同后端同账号的同一 token 不应重复上报"
        )
        XCTAssertNotEqual(
            reported,
            PushNotificationsManager.ReportedTokenScope(token: token, environment: .demoCloud, userId: 1),
            "切换环境后必须重新上报"
        )
        XCTAssertNotEqual(
            reported,
            PushNotificationsManager.ReportedTokenScope(token: token, environment: .mock, userId: 2),
            "换账号后必须重新上报"
        )
    }

    func testMockRejectsEpochMillisecondAfterParameter() async {
        let mock = MockAPIClient()
        mock.syncSessionFromAppState(token: "mock-token", role: .blind)

        do {
            let _: MissedNotificationPage = try await mock.get(
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
