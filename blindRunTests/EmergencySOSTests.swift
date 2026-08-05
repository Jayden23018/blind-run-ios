import CoreLocation
import XCTest
@testable import blindRun

/// SOS trigger, gating, failure branches, and the truthfulness rules around emergency-contact copy.
@MainActor
final class EmergencySOSTests: XCTestCase {

    // MARK: - Truthfulness regression

    /// The single most important assertion in this file.
    ///
    /// The backend pushes `EMERGENCY_CONTACT_NOTIFIED` synchronously inside the trigger transaction
    /// (`EmergencyService.java:370-373`) while the SMS is only sent afterwards by
    /// `@TransactionalEventListener(AFTER_COMMIT)` + `@Async` (`EmergencyContactNotifier.java:60-62`),
    /// and a send failure is broadcast to CS alone (`:126-135`) — never corrected to the blind
    /// runner. There is therefore no point in *this* branch at which the app knows a contact received
    /// an SMS. A blind user decides whether to seek help another way based on this copy, so claiming
    /// delivery is not a wording preference; it is telling someone in danger that help is coming.
    ///
    /// Since 2026-07-31 exactly one branch is allowed to claim delivery —
    /// `EMERGENCY_CONTACT_SMS_DELIVERED`, which is backed by a carrier receipt. It is asserted
    /// separately below and deliberately excluded here; every other state stays progressive.
    func testNoEmergencyCopyClaimsAnSMSWasDelivered() {
        let forbidden = ["联系人已收到短信", "已收到短信", "已通知家属", "已通知你的联系人", "短信已送达"]
        var allCopy = [
            EmergencySafetyCopy.contactNotified,
            EmergencySafetyCopy.triggeredAcknowledged,
            EmergencySafetyCopy.noContact,
            EmergencySafetyCopy.volunteerTimeout,
            EmergencySafetyCopy.locating,
            EmergencySafetyCopy.submitting,
            EmergencySafetyCopy.locationUnavailable,
            EmergencySafetyCopy.failure(nil),
            EmergencySafetyCopy.cooldown(retryAfterSeconds: 42),
            EmergencySafetyCopy.cooldown(retryAfterSeconds: nil),
            EmergencySafetyCopy.accessibilityLabel,
            EmergencySafetyCopy.accessibilityHint,
            // 2026-07-31 新增的一批，同样受这条红线约束（送达回执那一条除外，见下一个用例）。
            EmergencySafetyCopy.triggeredByVolunteer,
            EmergencySafetyCopy.contactNotifyFailed,
            EmergencySafetyCopy.volunteerAcknowledged,
            EmergencySafetyCopy.cancelOwnerSucceeded,
            EmergencySafetyCopy.cancelOwnerFailed(nil),
            EmergencySafetyCopy.volunteerAlertNotice,
            // 2026-08-04 补：这两条是客服解除/误触收尾，晚于本用例加入，一直没被收进清单。
            // 结果 `closedFalseAlarm` 长期写着「紧急联系人已收到解除通知」—— 解除短信走的是和求助短信
            // 同一条异步路径，没有运营商回执，这就是本红线的同类违规。由 scripts/hooks/guard.mjs 抓出。
            EmergencySafetyCopy.closedResolved,
            EmergencySafetyCopy.closedFalseAlarm
        ]
        allCopy.append(contentsOf: EmergencyEventStatus.allCases.map(EmergencySafetyCopy.submitted))

        for copy in allCopy {
            for claim in forbidden {
                XCTAssertFalse(
                    copy.contains(claim),
                    "SOS copy must never claim SMS delivery — found “\(claim)” in “\(copy)”"
                )
            }
        }
    }

    /// The contact-notified state is progressive tense and explicitly says receipt is unconfirmed.
    func testContactNotifiedCopyStatesReceiptIsUnconfirmed() {
        XCTAssertTrue(EmergencySafetyCopy.contactNotified.contains("正在联系"))
        XCTAssertTrue(EmergencySafetyCopy.contactNotified.contains("尚未确认对方是否收到"))
        XCTAssertTrue(EmergencySafetyCopy.contactNotified.contains("110"))
    }

    /// 送达回执是唯一允许说完成时的一段，而且必须仍然与「已发起」那一段可区分 ——
    /// 两段听起来一样的话，这条回执链路等于没接。
    func testOnlyTheCarrierReceiptBranchMayClaimDelivery() {
        XCTAssertTrue(EmergencySafetyCopy.contactSmsDelivered.contains("已收到"))
        XCTAssertNotEqual(EmergencySafetyCopy.contactSmsDelivered, EmergencySafetyCopy.contactNotified)
        XCTAssertFalse(
            EmergencySafetyCopy.contactSmsDelivered.contains("尚未确认"),
            "运营商已确认送达之后不该再说尚未确认"
        )
        // 投递失败必须说得比「未确认」更重，并直接给出替代求助方式。
        XCTAssertTrue(EmergencySafetyCopy.contactNotifyFailed.contains("没有收到"))
        XCTAssertTrue(EmergencySafetyCopy.contactNotifyFailed.contains("110"))
        XCTAssertTrue(EmergencySOSState.contactNotifyFailed.isFailure)
        XCTAssertFalse(EmergencySOSState.contactSmsDelivered.isFailure)
    }

    /// 后端 2026-07-31 起按订单参与方归属事件，志愿者代触发不再把告警回推给他自己，
    /// 于是志愿者入口可以开 —— 但仍然只在服务进行中，和盲人侧同一个门槛。
    func testVolunteerEmergencyEntryIsEnabledOnlyDuringService() {
        XCTAssertTrue(RunOrderStatus.inProgress.canVolunteerTriggerEmergency)
        XCTAssertTrue(RunOrderStatus.inProgress.canTriggerEmergency(as: .volunteer))
        for status in RunOrderStatus.allCases where status != .inProgress {
            XCTAssertFalse(
                status.canVolunteerTriggerEmergency,
                "\(status) 不该出现志愿者求助入口"
            )
        }
        XCTAssertFalse(RunOrderStatus.inProgress.canTriggerEmergency(as: .unset))
    }

    /// 志愿者只有「确认需要帮助」一个动作。`FALSE_ALARM` 在后端是硬 403，客户端连表达它的类型都不该有。
    func testVolunteerAcknowledgementCopyOffersNoDismissAction() {
        XCTAssertEqual(EmergencySafetyCopy.volunteerNeedHelpButtonTitle, "确认需要帮助")
        XCTAssertFalse(EmergencySafetyCopy.volunteerNeedHelpButtonTitle.contains("误触"))
        XCTAssertEqual(
            ErrorCode.emergencyVolunteerCannotDismiss.localizedMessage,
            "志愿者无权撤销求助，请确认对方是否需要帮助。"
        )
        // 撤销权只在受助者本人手里，且入口文案要说清代价（会给家属补一条解除短信）。
        XCTAssertTrue(EmergencySafetyCopy.cancelOwnerConfirmation.contains("解除短信"))
    }

    /// `POST /api/emergency/trigger` 的回执 status 自 2026-07-31 收敛为两个值；
    /// `VOLUNTEER_NOTIFIED` 不再出现。枚举值保留只为兼容历史数据与未知值兜底。
    func testTriggerReceiptStatusesStillDecodeIncludingRetiredValues() {
        XCTAssertEqual(EmergencyEventStatus(rawValue: "CONTACT_NOTIFIED"), .contactNotified)
        XCTAssertEqual(EmergencyEventStatus(rawValue: "PENDING"), .pending)
        XCTAssertEqual(EmergencyEventStatus(rawValue: "VOLUNTEER_NOTIFIED"), .volunteerNotified)
        XCTAssertNil(EmergencyEventStatus(rawValue: "SOMETHING_NEW"))
        XCTAssertTrue(EmergencyEventStatus.falseAlarm.isTerminal)
    }

    /// Every state that means "help is not on the way yet" must point at 110.
    func testTerminalAndFailureCopyAlwaysOffersTheEmergencyNumber() {
        let states: [EmergencySOSState] = [
            .acknowledged(.volunteerNotified),
            .acknowledged(.contactNotified),
            .acknowledged(.csHandling),
            .acknowledged(.unknown),
            .unsentNoLocation,
            .failed("网络异常"),
            .cooldown(retryAfterSeconds: 30)
        ]
        for state in states {
            XCTAssertTrue(state.message?.contains("110") == true, "missing 110 guidance in \(state)")
        }
    }

    /// A failure must lead with 未发出: for a blind user the first words decide the next action.
    func testFailureCopyLeadsWithNotSent() {
        XCTAssertTrue(EmergencySafetyCopy.locationUnavailable.hasPrefix("求助未发出"))
        XCTAssertTrue(EmergencySafetyCopy.failure("服务器错误").hasPrefix("求助未发出"))
        XCTAssertTrue(EmergencySafetyCopy.failure(nil).contains("网络异常"))
    }

    func testConfirmationCopyMatchesTheMandatedTextExactly() {
        XCTAssertEqual(
            EmergencySafetyCopy.confirmationMessage,
            "是否确认进入求助状态？确认后，本次服务将标记为异常，系统会记录当前订单状态。"
        )
    }

    // MARK: - Trigger: eligibility

    func testTriggerIsRejectedOutsideInProgress() async {
        let coordinator = EmergencyCoordinator()
        let client = EmergencyAPIClientStub()
        let outcome = await coordinator.trigger(
            order: Self.makeOrder(status: .driverArrived),
            role: .blind,
            userID: 7,
            apiClient: client,
            locate: { Self.coordinate() }
        )
        XCTAssertTrue(outcome.isFailure)
        XCTAssertTrue(client.requests.isEmpty, "no request may be sent outside IN_PROGRESS")
        XCTAssertNil(coordinator.activeEvent)
    }

    /// 2026-08-01 起志愿者可以代盲人发起求助。
    ///
    /// 这条用例原先断言的是「志愿者角色一律拒绝」—— 那是后端把事件挂在**触发者**身上时的止血：
    /// 志愿者按下去，告警回推给他自己、盲人收不到、升级的是志愿者的紧急联系人。后端已改成按订单
    /// 参与方归属事件（handoff 2026-07-31），门槛随之放开，断言跟着改成「服务进行中放行、其余拒绝」。
    /// 留这段说明是因为下一个读到它的人会问「为什么曾经写死拒绝」。
    func testVolunteerMayTriggerDuringServiceButNotOutsideIt() async {
        let coordinator = EmergencyCoordinator()
        let client = EmergencyAPIClientStub()
        client.response = EmergencyTriggerResponse(success: true, eventId: 77, status: "CONTACT_NOTIFIED")

        let allowed = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .volunteer,
            userID: 7,
            apiClient: client,
            locate: { Self.coordinate() }
        )
        XCTAssertFalse(allowed.isFailure)
        XCTAssertEqual(client.requests.count, 1, "服务进行中，志愿者代触发必须真的发出去")
        XCTAssertEqual(coordinator.activeEvent?.eventID, 77)

        // 服务之外仍然不放行：与盲人侧同一个 IN_PROGRESS 门槛，不因为角色不同而放宽。
        let blocked = await EmergencyCoordinator().trigger(
            order: Self.makeOrder(status: .driverArrived),
            role: .volunteer,
            userID: 7,
            apiClient: client,
            locate: { Self.coordinate() }
        )
        XCTAssertTrue(blocked.isFailure)
        XCTAssertEqual(client.requests.count, 1, "非服务中状态不得再发一次请求")
    }

    // MARK: - Trigger: GPS gate

    func testStrictGpsGateSendsNothingWithoutACoordinate() async {
        XCTAssertFalse(
            EmergencyCoordinator.allowsSubmissionWithoutLocation,
            "the strict gate is the shipped default until product/safety approve degradation"
        )
        let coordinator = EmergencyCoordinator()
        let client = EmergencyAPIClientStub()
        let outcome = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            apiClient: client,
            locate: { nil }
        )
        XCTAssertEqual(coordinator.state, .unsentNoLocation)
        XCTAssertTrue(outcome.isFailure)
        XCTAssertTrue(client.requests.isEmpty)
        XCTAssertTrue(outcome.message.contains("设置"), "must guide the user to Settings")
    }

    /// A device WGS-84 sample must never be uploaded raw; only the value already normalized at the
    /// single backend boundary is accepted.
    func testUnconvertedDeviceCoordinateIsTreatedAsNoLocation() async {
        let coordinator = EmergencyCoordinator()
        let client = EmergencyAPIClientStub()
        let raw = LocatedCoordinate(
            coordinate: CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4),
            system: .wgs84Device,
            capturedAt: Date()
        )
        _ = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            apiClient: client,
            locate: { raw }
        )
        XCTAssertEqual(coordinator.state, .unsentNoLocation)
        XCTAssertTrue(client.requests.isEmpty)
    }

    func testSuccessfulTriggerSendsOrderAndGcj02Coordinate() async {
        let coordinator = EmergencyCoordinator()
        let client = EmergencyAPIClientStub()
        client.response = EmergencyTriggerResponse(success: true, eventId: 512, status: "VOLUNTEER_NOTIFIED")

        let outcome = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            apiClient: client,
            locate: { Self.coordinate(latitude: 39.915, longitude: 116.404) }
        )

        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(client.requests.first?.path, "/api/emergency/trigger")
        XCTAssertEqual(client.requests.first?.method, .post)
        XCTAssertEqual(client.capturedBody?.orderId, 4242)
        XCTAssertEqual(client.capturedBody?.gpsLat ?? 0, 39.915, accuracy: 0.000001)
        XCTAssertEqual(client.capturedBody?.gpsLng ?? 0, 116.404, accuracy: 0.000001)

        XCTAssertEqual(coordinator.state, .acknowledged(.volunteerNotified))
        XCTAssertEqual(coordinator.activeEvent?.eventID, 512)
        XCTAssertEqual(coordinator.activeEvent?.orderID, 4242)
        XCTAssertEqual(coordinator.activeEvent?.userID, 7)
        XCTAssertFalse(outcome.isFailure)
        XCTAssertFalse(outcome.message.contains("短信"))
    }

    // MARK: - Trigger: result gating

    /// HTTP 200 alone is not an acknowledgement — `success: false` is a failure.
    func testUnsuccessfulStructuredBodyIsAFailure() async {
        let coordinator = EmergencyCoordinator()
        let client = EmergencyAPIClientStub()
        client.response = EmergencyTriggerResponse(success: false, eventId: 1, status: "PENDING")
        let outcome = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            apiClient: client,
            locate: { Self.coordinate() }
        )
        XCTAssertTrue(outcome.isFailure)
        XCTAssertNil(coordinator.activeEvent)
    }

    func testDecodingFailureLeavesSosUnsent() async {
        let coordinator = EmergencyCoordinator()
        let client = EmergencyAPIClientStub()
        client.error = APIError.decodingError(EmergencyAPIClientStub.StubError.decoding)
        let outcome = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            apiClient: client,
            locate: { Self.coordinate() }
        )
        XCTAssertTrue(outcome.isFailure)
        XCTAssertTrue(outcome.message.hasPrefix("求助未发出"))
        XCTAssertNil(coordinator.activeEvent)
    }

    /// Backend cooldown is `RateLimitException(60)` → 429 `TOO_MANY_REQUESTS` with
    /// `retryAfterSeconds` + a `Retry-After` header (`GlobalExceptionHandler.java:218-231`).
    func testCooldownSurfacesTheRetryDelay() async {
        let coordinator = EmergencyCoordinator()
        let client = EmergencyAPIClientStub()
        client.error = APIError.rateLimited(RateLimitInfo(message: "请求过于频繁", retryAfterSeconds: 47))
        let outcome = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            apiClient: client,
            locate: { Self.coordinate() }
        )
        XCTAssertEqual(coordinator.state, .cooldown(retryAfterSeconds: 47))
        XCTAssertTrue(outcome.message.contains("47"))
        XCTAssertNil(coordinator.activeEvent)
    }

    func testConcurrentTapsSendOnlyOneRequest() async {
        let coordinator = EmergencyCoordinator()
        let client = EmergencyAPIClientStub()
        client.response = EmergencyTriggerResponse(success: true, eventId: 1, status: "PENDING")
        client.delayNanoseconds = 200_000_000

        let order = Self.makeOrder(status: .inProgress)
        // A slow fix acquisition is the realistic window for a second tap: the runner hears nothing
        // yet and presses again. The guard must already be armed during `.locating`, not only once
        // the request is in flight.
        async let first = coordinator.trigger(
            order: order,
            role: .blind,
            userID: 7,
            apiClient: client,
            locate: {
                try? await Task.sleep(nanoseconds: 200_000_000)
                return Self.coordinate()
            }
        )
        await Task.yield()
        XCTAssertEqual(coordinator.state, .locating, "the button must show progress while locating")

        let second = await coordinator.trigger(
            order: order, role: .blind, userID: 7, apiClient: client, locate: { Self.coordinate() }
        )
        _ = await first

        XCTAssertEqual(client.requests.count, 1, "a double tap must not send two SOS requests")
        XCTAssertTrue(second.state.isBusy)
    }

    // MARK: - Realtime follow-ups

    func testContactNotifiedEventAdvancesTheActiveEvent() async {
        let coordinator = EmergencyCoordinator()
        let client = EmergencyAPIClientStub()
        client.response = EmergencyTriggerResponse(success: true, eventId: 9, status: "VOLUNTEER_NOTIFIED")
        _ = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            apiClient: client,
            locate: { Self.coordinate() }
        )

        coordinator.apply(Self.safetyEvent(kind: .emergencyContactNotified))

        XCTAssertEqual(coordinator.activeEvent?.status, .contactNotified)
        XCTAssertEqual(coordinator.state, .acknowledged(.contactNotified))
        XCTAssertEqual(coordinator.state.message, EmergencySafetyCopy.contactNotified)
    }

    func testEventForAnotherOrderIsIgnored() async {
        let coordinator = EmergencyCoordinator()
        let client = EmergencyAPIClientStub()
        client.response = EmergencyTriggerResponse(success: true, eventId: 9, status: "VOLUNTEER_NOTIFIED")
        _ = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            apiClient: client,
            locate: { Self.coordinate() }
        )

        coordinator.apply(Self.safetyEvent(kind: .emergencyContactNotified, orderID: 999))

        XCTAssertEqual(coordinator.activeEvent?.status, .volunteerNotified)
    }

    func testSafetyEventWithoutAnActiveEmergencyIsIgnored() {
        let coordinator = EmergencyCoordinator()
        coordinator.apply(Self.safetyEvent(kind: .emergencyContactNotified))
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(coordinator.activeEvent)
    }

    func testResetClearsEverythingAtSessionBoundaries() async {
        let coordinator = EmergencyCoordinator()
        let client = EmergencyAPIClientStub()
        client.response = EmergencyTriggerResponse(success: true, eventId: 9, status: "PENDING")
        _ = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            apiClient: client,
            locate: { Self.coordinate() }
        )
        XCTAssertNotNil(coordinator.activeEvent)

        coordinator.reset()

        XCTAssertNil(coordinator.activeEvent)
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(coordinator.repeatStatusSuffix)
    }

    // MARK: - Backend copy substitution

    /// The backend template body ("已通知紧急联系人{contactName}") must never reach the user.
    func testEmergencyEventTypesMapToLocalCopyNotBackendBody() {
        let mapped: [(String, RealtimeSafetyEvent.Kind, String)] = [
            ("EMERGENCY_TRIGGERED", .emergencyTriggered, EmergencySafetyCopy.triggeredAcknowledged),
            ("EMERGENCY_CONTACT_NOTIFIED", .emergencyContactNotified, EmergencySafetyCopy.contactNotified),
            ("EMERGENCY_NO_CONTACT", .emergencyNoContact, EmergencySafetyCopy.noContact),
            ("EMERGENCY_VOLUNTEER_TIMEOUT", .emergencyVolunteerTimeout, EmergencySafetyCopy.volunteerTimeout)
        ]
        for (eventType, expectedKind, expectedCopy) in mapped {
            XCTAssertEqual(AppRealtimeCoordinator.emergencyKind(forEventType: eventType), expectedKind)
            XCTAssertEqual(AppRealtimeCoordinator.emergencyCopy(for: expectedKind), expectedCopy)
        }
        XCTAssertNil(AppRealtimeCoordinator.emergencyKind(forEventType: "SERVICE_STARTED"))
    }

    // MARK: - Contract shape

    /// Shape comes from `EmergencyController.java:34-38`, which returns a bare `Map` rather than the
    /// usual `ApiResponse` envelope; `api_spec.yaml:1024-1030` only says `type: object`.
    func testTriggerResponseDecodesTheControllerShape() throws {
        let json = Data(#"{"success":true,"eventId":512,"status":"VOLUNTEER_NOTIFIED"}"#.utf8)
        let decoded = try JSONDecoder().decode(EmergencyTriggerResponse.self, from: json)
        XCTAssertEqual(decoded.eventId, 512)
        XCTAssertEqual(decoded.eventStatus, .volunteerNotified)
    }

    /// A status this client cannot name must degrade to `.unknown`, never to a rescue claim.
    func testUnrecognisedStatusDegradesToUnknown() throws {
        let json = Data(#"{"success":true,"eventId":1,"status":"SOMETHING_NEW"}"#.utf8)
        let decoded = try JSONDecoder().decode(EmergencyTriggerResponse.self, from: json)
        XCTAssertEqual(decoded.eventStatus, .unknown)
        XCTAssertFalse(EmergencySafetyCopy.submitted(.unknown).contains("已通知"))
    }

    /// Guards against drift from backend `entity/EmergencyStatus.java`.
    func testEmergencyStatusMirrorsTheBackendEnum() {
        let backendNames: Set<String> = [
            "PENDING", "VOLUNTEER_NOTIFIED", "VOLUNTEER_CONFIRMED",
            "CS_HANDLING", "CONTACT_NOTIFIED", "RESOLVED", "FALSE_ALARM"
        ]
        let clientNames = Set(EmergencyEventStatus.allCases.map(\.rawValue)).subtracting(["UNKNOWN"])
        XCTAssertEqual(clientNames, backendNames)
        XCTAssertTrue(EmergencyEventStatus.resolved.isTerminal)
        XCTAssertTrue(EmergencyEventStatus.falseAlarm.isTerminal)
        XCTAssertFalse(EmergencyEventStatus.contactNotified.isTerminal)
    }

    // MARK: - Fixtures

    /// `nonisolated` so it can be called from the detached `locate` closure in the concurrency test.
    nonisolated private static func coordinate(
        latitude: Double = 39.9,
        longitude: Double = 116.4
    ) -> LocatedCoordinate {
        LocatedCoordinate(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            system: .gcj02Backend,
            capturedAt: Date()
        )
    }

    private static func safetyEvent(
        kind: RealtimeSafetyEvent.Kind,
        orderID: Int64? = nil
    ) -> RealtimeSafetyEvent {
        RealtimeSafetyEvent(
            eventID: "msg-1",
            orderID: orderID,
            kind: kind,
            displayText: "ignored",
            speechText: "ignored",
            timestamp: nil
        )
    }

    private static func makeOrder(status: RunOrderStatus) -> OrderDetailResponse {
        OrderDetailResponse(
            orderId: 4242,
            status: status,
            startAddress: "测试出发点",
            startLatitude: nil,
            startLongitude: nil,
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

// MARK: - Stub

private final class EmergencyAPIClientStub: APIClientProtocol, @unchecked Sendable {
    enum StubError: Error { case decoding, unexpectedType }

    struct RecordedRequest {
        let method: HTTPMethod
        let path: String
    }

    private(set) var requests: [RecordedRequest] = []
    private(set) var capturedBody: EmergencyTriggerRequest?
    var response: EmergencyTriggerResponse?
    var error: APIError?
    var delayNanoseconds: UInt64 = 0

    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        requests.append(RecordedRequest(method: method, path: path))
        capturedBody = body as? EmergencyTriggerRequest
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if let error { throw error }
        guard let response, let typed = response as? T else { throw StubError.unexpectedType }
        return typed
    }

    func upload<T: Decodable>(
        path: String,
        query: [String: String]?,
        fields: [String: String]?,
        files: [MultipartFile],
        requiresAuth: Bool
    ) async throws -> T {
        throw StubError.unexpectedType
    }
}
