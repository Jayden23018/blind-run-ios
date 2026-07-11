//
//  blindRunTests.swift
//  blindRunTests
//
//  Created by Jerry on 5/18/26.
//

import XCTest
import AMapSearchKit
import CoreLocation
@testable import blindRun

@MainActor
private final class MockSpeechAudioSession: SpeechAudioSessionManaging {
    enum FailurePoint {
        case none
        case deactivate
        case playbackCategory
        case playbackActivation
    }

    var isInputAvailable = true
    var inputNumberOfChannels = 1
    var sampleRate = 44_100.0
    var operations: [String] = []
    var failurePoint: FailurePoint = .none

    func requestRecordPermission(_ response: @escaping (Bool) -> Void) {
        response(true)
    }

    func configureRecordingCategory() throws {
        operations.append("configureRecording")
    }

    func activateRecording() throws {
        operations.append("activateRecording")
    }

    func deactivateRecording() throws {
        operations.append("deactivateRecording")
        if failurePoint == .deactivate { throw MockAudioSessionError.expected }
    }

    func configurePlaybackCategory() throws {
        operations.append("configurePlayback")
        if failurePoint == .playbackCategory { throw MockAudioSessionError.expected }
    }

    func activatePlayback() throws {
        operations.append("activatePlayback")
        if failurePoint == .playbackActivation { throw MockAudioSessionError.expected }
    }
}

private enum MockAudioSessionError: Error {
    case expected
}

@MainActor
final class blindRunTests: XCTestCase {

    func testSendCodeRequestUsesOpenAPICamelCaseKeys() throws {
        let request = SendCodeRequest(phone: "13800138000")
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(json["phone"], "13800138000")
    }

    func testSendCodeResponseIgnoresNumericBusinessCodeZero() throws {
        let data = #"{"success":true,"message":"验证码已发送","code":0}"#.data(using: .utf8)!

        let response = try JSONDecoder().decode(SendCodeResponse.self, from: data)

        XCTAssertTrue(response.success == true)
        XCTAssertEqual(response.message, "验证码已发送")
        XCTAssertNil(response.resolvedVerificationCode)
    }

    func testSendCodeResponseIgnoresStringBusinessCode() throws {
        let data = #"{"success":true,"message":"验证码已发送","code":"654321"}"#.data(using: .utf8)!

        let response = try JSONDecoder().decode(SendCodeResponse.self, from: data)

        XCTAssertEqual(response.code, "654321")
        XCTAssertNil(response.resolvedVerificationCode)
    }

    func testSendCodeResponseUsesExplicitSixDigitVerificationFields() throws {
        let data = #"{"success":true,"message":"验证码已发送","verificationCode":" 123456 ","smsCode":"789012"}"#.data(using: .utf8)!

        let response = try JSONDecoder().decode(SendCodeResponse.self, from: data)

        XCTAssertEqual(response.resolvedVerificationCode, "123456")
    }

    func testSendCodeResponseIgnoresMalformedExplicitVerificationFields() throws {
        let data = #"{"success":true,"message":"验证码已发送","verificationCode":"SUCCESS","smsCode":"12345"}"#.data(using: .utf8)!

        let response = try JSONDecoder().decode(SendCodeResponse.self, from: data)

        XCTAssertNil(response.resolvedVerificationCode)
    }

    func testVerifyCodeRequestUsesOpenAPICamelCaseKeys() throws {
        let request = VerifyCodeRequest(phone: "13800138000", code: AppConstants.Auth.demoVerificationCode)
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(json["phone"], "13800138000")
        XCTAssertEqual(json["code"], "000000")
    }

    func testDemoVerificationCodeMatchesCloudContract() {
        XCTAssertEqual(AppConstants.Auth.demoVerificationCode, "000000")
    }

    func testOrderRespondRequestEncodesAcceptAction() throws {
        let request = OrderRespondRequest(action: .accept)
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(json["action"], "ACCEPT")
    }

    func testVolunteerLocationReporterSendsAuthorizedCloudLocation() {
        var sentCoordinates: [(Double, Double)] = []
        let didReport = VolunteerLocationReporter.reportIfNeeded(
            currentLocation: CLLocationCoordinate2D(latitude: 39.905, longitude: 116.408),
            locationAuthorized: true,
            shouldReportToCloud: true,
            send: { sentCoordinates.append(($0, $1)) }
        )

        XCTAssertTrue(didReport)
        XCTAssertEqual(sentCoordinates.count, 1)
        XCTAssertEqual(sentCoordinates[0].0, 39.905, accuracy: 0.000001)
        XCTAssertEqual(sentCoordinates[0].1, 116.408, accuracy: 0.000001)
    }

    func testVolunteerLocationReporterSkipsUnauthorizedOrMockLocation() {
        var sendCount = 0
        let coordinate = CLLocationCoordinate2D(latitude: 39.905, longitude: 116.408)

        XCTAssertFalse(VolunteerLocationReporter.reportIfNeeded(
            currentLocation: coordinate,
            locationAuthorized: false,
            shouldReportToCloud: true,
            send: { _, _ in sendCount += 1 }
        ))
        XCTAssertFalse(VolunteerLocationReporter.reportIfNeeded(
            currentLocation: coordinate,
            locationAuthorized: true,
            shouldReportToCloud: false,
            send: { _, _ in sendCount += 1 }
        ))
        XCTAssertFalse(VolunteerLocationReporter.reportIfNeeded(
            currentLocation: nil,
            locationAuthorized: true,
            shouldReportToCloud: true,
            send: { _, _ in sendCount += 1 }
        ))
        XCTAssertEqual(sendCount, 0)
    }

    func testAcceptingDispatchPublishesNavigationOrderId() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        appState.updateVolunteerProfile(makeApprovedVolunteerProfile())
        let speechService = SpeechService()
        let viewModel = VolunteerHomeViewModel()
        viewModel.configure(with: appState, speechService: speechService)
        viewModel.incomingOrder = makeDispatchOrder(orderId: 1)
        viewModel.dispatchCountdown = 30

        viewModel.respondToDispatch(
            accept: true,
            currentLocation: CLLocationCoordinate2D(latitude: 39.905, longitude: 116.408),
            locationAuthorized: true
        )

        let didNavigate = await waitUntil { viewModel.acceptedDispatchOrderId == 1 }
        XCTAssertTrue(didNavigate)
        XCTAssertEqual(viewModel.acceptedDispatchOrderId, 1)
        XCTAssertEqual(viewModel.acceptedDispatchInitialOrder?.orderId, 1)
        XCTAssertEqual(viewModel.acceptedDispatchInitialOrder?.status, .pendingAccept)
        XCTAssertEqual(viewModel.activeOrder?.orderId, 1)
        XCTAssertEqual(viewModel.activeOrder?.status, .pendingAccept)
        XCTAssertNil(viewModel.incomingOrder)
        XCTAssertEqual(viewModel.dispatchCountdown, 0)
        XCTAssertFalse(viewModel.isRespondingToDispatch)
        XCTAssertEqual(speechService.lastSpokenText, "已接受订单")
    }

    func testAcceptingDispatchFailureDoesNotPublishNavigationOrderId() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        appState.updateVolunteerProfile(makeApprovedVolunteerProfile())
        let viewModel = VolunteerHomeViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())
        viewModel.incomingOrder = makeDispatchOrder(orderId: 999)
        viewModel.dispatchCountdown = 30

        viewModel.respondToDispatch(
            accept: true,
            currentLocation: CLLocationCoordinate2D(latitude: 39.905, longitude: 116.408),
            locationAuthorized: true
        )

        let didFail = await waitUntil { viewModel.errorMessage != nil }
        XCTAssertTrue(didFail)
        XCTAssertNil(viewModel.acceptedDispatchOrderId)
        XCTAssertNotNil(viewModel.incomingOrder)
        XCTAssertEqual(viewModel.dispatchCountdown, 30)
        XCTAssertFalse(viewModel.isRespondingToDispatch)
    }

    func testAcceptingDispatchRequiresReadinessAndLocation() async throws {
        let unavailableState = AppState()
        unavailableState.currentEnvironment = .mock
        unavailableState.updateVolunteerProfile(makeApprovedVolunteerProfile(isAvailable: false))
        let unavailableViewModel = VolunteerHomeViewModel()
        unavailableViewModel.configure(with: unavailableState, speechService: SpeechService())
        unavailableViewModel.incomingOrder = makeDispatchOrder(orderId: 1)

        unavailableViewModel.respondToDispatch(
            accept: true,
            currentLocation: CLLocationCoordinate2D(latitude: 39.905, longitude: 116.408),
            locationAuthorized: true
        )

        XCTAssertEqual(unavailableViewModel.errorMessage, "请先开启可服务状态")
        XCTAssertNil(unavailableViewModel.acceptedDispatchOrderId)
        XCTAssertNotNil(unavailableViewModel.incomingOrder)

        let noLocationState = AppState()
        noLocationState.currentEnvironment = .mock
        noLocationState.updateVolunteerProfile(makeApprovedVolunteerProfile())
        let noLocationViewModel = VolunteerHomeViewModel()
        noLocationViewModel.configure(with: noLocationState, speechService: SpeechService())
        noLocationViewModel.incomingOrder = makeDispatchOrder(orderId: 1)

        noLocationViewModel.respondToDispatch(
            accept: true,
            currentLocation: nil,
            locationAuthorized: false
        )

        XCTAssertEqual(noLocationViewModel.errorMessage, "需要开启定位权限才能接单")
        XCTAssertNil(noLocationViewModel.acceptedDispatchOrderId)
        XCTAssertNotNil(noLocationViewModel.incomingOrder)
    }

    func testDecliningDispatchDoesNotPublishNavigationOrderId() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = VolunteerHomeViewModel()
        viewModel.configure(with: appState, speechService: speechService)
        viewModel.incomingOrder = makeDispatchOrder(orderId: 1)
        viewModel.dispatchCountdown = 30

        viewModel.respondToDispatch(
            accept: false,
            currentLocation: nil,
            locationAuthorized: false
        )

        let didDecline = await waitUntil { viewModel.incomingOrder == nil }
        XCTAssertTrue(didDecline)
        XCTAssertNil(viewModel.acceptedDispatchOrderId)
        XCTAssertEqual(viewModel.dispatchCountdown, 0)
        XCTAssertFalse(viewModel.isRespondingToDispatch)
        XCTAssertEqual(speechService.lastSpokenText, "已拒绝订单")
    }

    func testVolunteerHomeReceivesDispatchWhenWebSocketIsAssignedAfterConfigure() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = VolunteerHomeViewModel()

        viewModel.configure(with: appState, speechService: speechService)

        let webSocketService = WebSocketService()
        appState.webSocketService = webSocketService
        webSocketService.simulateIncomingEventForTesting(.newOrder(makeDispatchOrder(orderId: 42)))

        let didReceive = await waitUntil { viewModel.incomingOrder?.orderId == 42 }
        XCTAssertTrue(didReceive)
        XCTAssertEqual(viewModel.dispatchCountdown, 30)
        XCTAssertEqual(speechService.lastSpokenText, "新订单到达，请在30秒内响应")
    }

    func testVolunteerHomeResubscribesWhenWebSocketServiceIsReplaced() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        appState.updateVolunteerProfile(makeApprovedVolunteerProfile())
        let viewModel = VolunteerHomeViewModel()

        viewModel.configure(with: appState, speechService: SpeechService())

        let firstWebSocketService = WebSocketService()
        appState.webSocketService = firstWebSocketService
        firstWebSocketService.simulateIncomingEventForTesting(.newOrder(makeDispatchOrder(orderId: 41)))

        let didReceiveInitialEvent = await waitUntil { viewModel.incomingOrder?.orderId == 41 }
        XCTAssertTrue(didReceiveInitialEvent)
        viewModel.dismissDispatch()

        let replacementWebSocketService = WebSocketService()
        appState.webSocketService = replacementWebSocketService
        firstWebSocketService.simulateIncomingEventForTesting(.newOrder(makeDispatchOrder(orderId: 40)))

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(viewModel.incomingOrder)

        replacementWebSocketService.simulateIncomingEventForTesting(.newOrder(makeDispatchOrder(orderId: 43)))

        let didReceiveReplacementEvent = await waitUntil { viewModel.incomingOrder?.orderId == 43 }
        XCTAssertTrue(didReceiveReplacementEvent)
    }

    func testVolunteerHomeActiveOrderFiltersVolunteerServiceStatuses() throws {
        let activeOrder = try XCTUnwrap(VolunteerHomeViewModel.activeVolunteerOrder(from: [
            makeOrder(orderId: 1, status: .pendingMatch, createdAt: "2026-06-25T10:00:00Z"),
            makeOrder(orderId: 2, status: .pendingAccept, createdAt: "2026-06-25T11:00:00Z"),
            makeOrder(orderId: 3, status: .driverEnRoute, createdAt: "2026-06-25T12:00:00Z"),
            makeOrder(orderId: 4, status: .completed, createdAt: "2026-06-25T13:00:00Z"),
            makeOrder(orderId: 5, status: .cancelled, createdAt: "2026-06-25T14:00:00Z")
        ]))

        XCTAssertEqual(activeOrder.orderId, 3)
    }

    func testVolunteerHomeActiveOrderIgnoresTerminalOrders() {
        let activeOrder = VolunteerHomeViewModel.activeVolunteerOrder(from: [
            makeOrder(orderId: 1, status: .pendingMatch),
            makeOrder(orderId: 2, status: .completed),
            makeOrder(orderId: 3, status: .cancelled),
            makeOrder(orderId: 4, status: .noVolunteer)
        ])

        XCTAssertNil(activeOrder)
    }

    func testVolunteerHomeLoadShowsAcceptedOrderAsActiveOrder() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let viewModel = VolunteerHomeViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())

        await viewModel.load(currentLocation: nil, locationAuthorized: false)
        XCTAssertNil(viewModel.activeOrder)

        appState.updateVolunteerProfile(makeApprovedVolunteerProfile())
        viewModel.incomingOrder = makeDispatchOrder(orderId: 1)
        viewModel.respondToDispatch(
            accept: true,
            currentLocation: CLLocationCoordinate2D(latitude: 39.905, longitude: 116.408),
            locationAuthorized: true
        )

        let didAccept = await waitUntil { viewModel.acceptedDispatchOrderId == 1 }
        XCTAssertTrue(didAccept)

        await viewModel.load(currentLocation: nil, locationAuthorized: false)

        XCTAssertEqual(viewModel.activeOrder?.orderId, 1)
        XCTAssertEqual(viewModel.activeOrder?.status, .pendingAccept)
    }

    func testVolunteerDemandPanelDetentHeightsAndNearestSnap() {
        let viewportHeight: CGFloat = 1_000
        let topContentBottom: CGFloat = 180
        let compactHeight = VolunteerDemandPanelDetent.compact.height(
            viewportHeight: viewportHeight,
            topContentBottom: topContentBottom
        )
        let mediumHeight = VolunteerDemandPanelDetent.medium.height(
            viewportHeight: viewportHeight,
            topContentBottom: topContentBottom
        )
        let expandedHeight = VolunteerDemandPanelDetent.expanded.height(
            viewportHeight: viewportHeight,
            topContentBottom: topContentBottom
        )

        XCTAssertLessThan(compactHeight, mediumHeight)
        XCTAssertLessThan(mediumHeight, expandedHeight)
        XCTAssertEqual(
            VolunteerDemandPanelDetent.nearest(
                to: compactHeight + 4,
                viewportHeight: viewportHeight,
                topContentBottom: topContentBottom
            ),
            .compact
        )
        XCTAssertEqual(
            VolunteerDemandPanelDetent.nearest(
                to: expandedHeight - 4,
                viewportHeight: viewportHeight,
                topContentBottom: topContentBottom
            ),
            .expanded
        )
    }

    func testVolunteerHomeMapAnchorUsesVisibleAreaAndClampsExtremes() {
        let normalAnchor = VolunteerHomeMapLayout.screenAnchorY(
            viewportHeight: 1_000,
            topContentBottom: 160,
            demandPanelTop: 580
        )
        XCTAssertEqual(normalAnchor, 0.37, accuracy: 0.0001)

        let highAnchor = VolunteerHomeMapLayout.screenAnchorY(
            viewportHeight: 1_000,
            topContentBottom: -500,
            demandPanelTop: -200
        )
        XCTAssertEqual(highAnchor, 0.18, accuracy: 0.0001)

        let lowAnchor = VolunteerHomeMapLayout.screenAnchorY(
            viewportHeight: 1_000,
            topContentBottom: 1_600,
            demandPanelTop: 1_700
        )
        XCTAssertEqual(lowAnchor, 0.82, accuracy: 0.0001)
    }

    func testVolunteerHomeLayoutHelpersNeverReturnInvalidFrameDimensions() {
        let invalidValues: [CGFloat] = [
            0,
            -40,
            .nan,
            .infinity,
            -.infinity
        ]

        for viewportHeight in invalidValues {
            for topContentBottom in invalidValues {
                for detent in VolunteerDemandPanelDetent.allCases {
                    let height = detent.height(
                        viewportHeight: viewportHeight,
                        topContentBottom: topContentBottom
                    )

                    XCTAssertTrue(height.isFinite)
                    XCTAssertGreaterThan(height, 0)
                }

                let clampedHeight = VolunteerDemandPanelDetent.clampedHeight(
                    .nan,
                    viewportHeight: viewportHeight,
                    topContentBottom: topContentBottom
                )
                XCTAssertTrue(clampedHeight.isFinite)
                XCTAssertGreaterThan(clampedHeight, 0)

                let anchor = VolunteerHomeMapLayout.screenAnchorY(
                    viewportHeight: viewportHeight,
                    topContentBottom: topContentBottom,
                    demandPanelTop: .nan
                )
                XCTAssertTrue(anchor.isFinite)
                XCTAssertGreaterThanOrEqual(anchor, 0.18)
                XCTAssertLessThanOrEqual(anchor, 0.82)
            }
        }
    }

    func testFlexibleErrorEnvelopeUsesBusinessErrorCode() throws {
        let data = #"{"errorCode":"VOLUNTEER_NOT_AVAILABLE","code":403,"success":false,"message":"未开启接单"}"#.data(using: .utf8)!
        let payload = try JSONDecoder().decode(APIErrorEnvelope.self, from: data)
        let response = try XCTUnwrap(payload.resolvedErrorResponse(statusCode: 403))

        XCTAssertEqual(response.code, "VOLUNTEER_NOT_AVAILABLE")
        XCTAssertEqual(response.message, "未开启接单")
    }

    func testFlexibleErrorEnvelopeUsesLegacyErrorMessage() throws {
        let data = #"{"error":"验证码错误或已过期"}"#.data(using: .utf8)!
        let payload = try JSONDecoder().decode(APIErrorEnvelope.self, from: data)
        let response = try XCTUnwrap(payload.resolvedErrorResponse(statusCode: 400))

        XCTAssertEqual(response.code, "HTTP_400")
        XCTAssertEqual(response.message, "验证码错误或已过期")
    }

    func testEmptyResponseDecodesEmptyObjectsAndEnvelopePayloads() throws {
        XCTAssertNoThrow(try JSONDecoder().decode(EmptyResponse.self, from: #"{}"#.data(using: .utf8)!))
        XCTAssertNoThrow(try JSONDecoder().decode(EmptyResponse.self, from: #"{"success":true}"#.data(using: .utf8)!))

        let envelope = try JSONDecoder().decode(
            APIEnvelopeResponse<EmptyResponse>.self,
            from: #"{"success":true,"data":{}}"#.data(using: .utf8)!
        )
        XCTAssertNotNil(envelope.data)
    }

    func testMockOrderActionsSupportEmptyResponseAndFetchDetailAfterwards() async throws {
        let client = MockAPIClient()
        let available: PagedOrderResponse = try await client.get("/api/orders/available")
        let order = try XCTUnwrap(available.content.first)

        let _: EmptyResponse = try await client.post(
            "/api/orders/\(order.orderId)/respond",
            body: OrderRespondRequest(action: .accept)
        )
        var detail: OrderDetailResponse = try await client.get("/api/orders/\(order.orderId)")
        XCTAssertEqual(detail.status, .pendingAccept)

        let _: EmptyResponse = try await client.post("/api/orders/\(order.orderId)/en-route")
        detail = try await client.get("/api/orders/\(order.orderId)")
        XCTAssertEqual(detail.status, .driverEnRoute)

        let _: EmptyResponse = try await client.post("/api/orders/\(order.orderId)/arrived")
        detail = try await client.get("/api/orders/\(order.orderId)")
        XCTAssertEqual(detail.status, .driverArrived)

        do {
            let _: EmptyResponse = try await client.post("/api/orders/\(order.orderId)/finish")
            XCTFail("Mock should reject finish before IN_PROGRESS")
        } catch let error as APIError {
            guard case .serverError(let response) = error else {
                return XCTFail("Expected serverError, got \(error)")
            }
            XCTAssertEqual(response.code, "INVALID_ORDER_STATUS")
        }

        let _: EmptyResponse = try await client.post("/api/orders/\(order.orderId)/start-service")
        detail = try await client.get("/api/orders/\(order.orderId)")
        XCTAssertEqual(detail.status, .inProgress)

        let _: EmptyResponse = try await client.post("/api/orders/\(order.orderId)/finish")
        detail = try await client.get("/api/orders/\(order.orderId)")
        XCTAssertEqual(detail.status, .completed)
    }

    func testMockEmergencyContactUpdateSupportsBlindProfileEditSave() async throws {
        let client = MockAPIClient()
        let contacts: [EmergencyContactResponse] = try await client.get("/api/users/1/emergency-contacts")
        let contact = try XCTUnwrap(contacts.first)

        let updated: EmergencyContactResponse = try await client.put(
            "/api/users/1/emergency-contacts/\(contact.id)",
            body: EmergencyContactRequest(
                name: "一个人",
                phone: "13888888888",
                relationship: nil,
                isPrimary: true
            )
        )

        XCTAssertEqual(updated.id, contact.id)
        XCTAssertEqual(updated.name, "一个人")
        XCTAssertEqual(updated.phone, "13888888888")
        XCTAssertEqual(updated.isPrimary, true)

        let refreshedContacts: [EmergencyContactResponse] = try await client.get("/api/users/1/emergency-contacts")
        let refreshedContact = try XCTUnwrap(refreshedContacts.first(where: { $0.id == contact.id }))
        XCTAssertEqual(refreshedContact.name, "一个人")
        XCTAssertEqual(refreshedContact.phone, "13888888888")
    }

    func testMockVolunteerDispatchSummaryReflectsDispatchStatusAndActiveOrder() async throws {
        let client = MockAPIClient()

        let initialSummary: VolunteerDispatchSummaryResponse = try await client.get("/api/volunteer/dispatch-summary")
        XCTAssertFalse(initialSummary.canDispatch ?? true)
        XCTAssertEqual(initialSummary.notAvailableReasons, [.dispatchDisabled])
        XCTAssertEqual(initialSummary.completedCount, 1)
        XCTAssertEqual(initialSummary.resolvedPointsBalance, 100)

        let _: EmptyResponse = try await client.put(
            "/api/volunteer/dispatch-status",
            body: DispatchStatusRequest(wantsDispatch: true)
        )
        let enabledSummary: VolunteerDispatchSummaryResponse = try await client.get("/api/volunteer/dispatch-summary")
        XCTAssertTrue(enabledSummary.canDispatch ?? false)
        XCTAssertTrue(enabledSummary.activeOrders?.isEmpty ?? false)

        let _: EmptyResponse = try await client.post(
            "/api/orders/1/respond",
            body: OrderRespondRequest(action: .accept)
        )
        let activeSummary: VolunteerDispatchSummaryResponse = try await client.get("/api/volunteer/dispatch-summary")
        XCTAssertFalse(activeSummary.canDispatch ?? true)
        XCTAssertEqual(activeSummary.notAvailableReasons, [.activeOrder])
        let activeOrder = try XCTUnwrap(activeSummary.activeOrders?.first)
        XCTAssertEqual(activeOrder.orderId, 1)
        XCTAssertEqual(try XCTUnwrap(activeOrder.startLatitude), 39.9342, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(activeOrder.startLongitude), 116.4740, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(activeOrder.orderDetail.startLatitude), 39.9342, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(activeOrder.orderDetail.startLongitude), 116.4740, accuracy: 0.000001)
        XCTAssertEqual(activeSummary.recentOrders?.first?.startAddress, "朝阳公园南门")
    }

    func testVolunteerDispatchSummaryActiveOrderDecodesAndPreservesCoordinatesInOrderDetail() throws {
        let json = """
        {
          "orderId": 42,
          "status": "PENDING_ACCEPT",
          "plannedStartTime": "2026-07-02T21:10:00",
          "plannedEndTime": "2026-07-02T22:10:00",
          "startAddress": "云南省昆明市西山区福海街道庾园路五家堆湿地公园",
          "startLatitude": 25.02712,
          "startLongitude": 102.68742,
          "blindName": "盲人跑者",
          "blindPhoneMasked": "138****0002",
          "acceptedAt": "2026-07-02T20:32:00"
        }
        """.data(using: .utf8)!

        let activeOrder = try JSONDecoder().decode(VolunteerDispatchSummaryActiveOrder.self, from: json)

        XCTAssertEqual(try XCTUnwrap(activeOrder.startLatitude), 25.02712, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(activeOrder.startLongitude), 102.68742, accuracy: 0.000001)
        XCTAssertEqual(activeOrder.orderDetail.startAddress, "云南省昆明市西山区福海街道庾园路五家堆湿地公园")
        XCTAssertEqual(try XCTUnwrap(activeOrder.orderDetail.startLatitude), 25.02712, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(activeOrder.orderDetail.startLongitude), 102.68742, accuracy: 0.000001)
    }

    func testMockFormalTwoRoleHappyPathThroughReview() async throws {
        let client = MockAPIClient()
        let plannedStart = Date().addingTimeInterval(45 * 60)
        let plannedEnd = plannedStart.addingTimeInterval(60 * 60)
        let createResponse: OrderResponse = try await client.post(
            "/api/orders",
            body: CreateOrderRequest(
                startLatitude: 39.9342,
                startLongitude: 116.4740,
                startAddress: "朝阳公园南门",
                plannedStartTime: DateFormatter.aidRunBackendLocalDateTime.string(from: plannedStart),
                plannedEndTime: DateFormatter.aidRunBackendLocalDateTime.string(from: plannedEnd),
                expectedDurationMinutes: 60,
                pacePreference: .moderate,
                routePreference: .parkTrail,
                routeNotes: nil,
                hasGuideDogThisRun: false,
                specialNotes: nil
            )
        )
        let orderId = try XCTUnwrap(createResponse.id)
        XCTAssertEqual(createResponse.status, .pendingMatch)

        let _: EmptyResponse = try await client.put(
            "/api/volunteer/dispatch-status",
            body: DispatchStatusRequest(wantsDispatch: true)
        )
        let _: EmptyResponse = try await client.post(
            "/api/orders/\(orderId)/respond",
            body: OrderRespondRequest(action: .accept)
        )
        var detail: OrderDetailResponse = try await client.get("/api/orders/\(orderId)")
        XCTAssertEqual(detail.status, .pendingAccept)

        let _: EmptyResponse = try await client.post("/api/orders/\(orderId)/en-route")
        let _: EmptyResponse = try await client.post("/api/orders/\(orderId)/arrived")
        detail = try await client.get("/api/orders/\(orderId)")
        XCTAssertEqual(detail.status, .driverArrived)

        let _: EmptyResponse = try await client.post("/api/orders/\(orderId)/start-service")
        let _: EmptyResponse = try await client.post("/api/orders/\(orderId)/finish")
        detail = try await client.get("/api/orders/\(orderId)")
        XCTAssertEqual(detail.status, .completed)

        let _: EmptyResponse = try await client.post(
            "/api/orders/\(orderId)/review",
            body: CreateReviewRequest(rating: 5, comment: "顺利完成")
        )
    }

    func testVolunteerRegistrationCloudAuthPathsUseCloudContract() async throws {
        let client = MockAPIClient()

        let _: EmptyResponse = try await client.upload(
            "/api/volunteer/verification",
            files: [MultipartFile(fieldName: "file", fileName: "cert.jpg", mimeType: "image/jpeg", data: Data([0xFF, 0xD8]))]
        )

        do {
            let _: EmptyResponse = try await client.upload(
                "/api/volunteer/registration/step2/id-card",
                fields: [
                    "idCardName": "测试志愿者",
                    "idCardNumber": "110101199001011234"
                ],
                files: []
            )
            XCTFail("旧身份证照片上传路径不应继续可用")
        } catch {
            // Expected: Step2 ID photo upload was removed from the main registration flow.
        }

        let _: EmptyResponse = try await client.post(
            "/api/volunteer/registration/step1",
            body: BasicInfoRequest(
                name: "测试志愿者",
                phone: "13800000002",
                idCardName: "测试志愿者",
                idCardNumber: "110101199001011234",
                runningExperience: nil,
                hasGuidedBefore: true,
                emergencyExperience: nil
            )
        )
        let initResponse: FaceVerifyInitResponse = try await client.post(
            "/api/volunteer/registration/step3/face-verify/init",
            body: FaceVerifyInitRequest(metaInfo: #"{"mock":true}"#)
        )
        XCTAssertEqual(initResponse.certifyId, "mock-certify-id")

        let result: FaceVerifyResponse = try await client.post(
            "/api/volunteer/registration/step3/face-verify/result",
            body: FaceVerifyResultRequest(certifyId: "mock-certify-id")
        )
        XCTAssertTrue(result.isPassed)
    }

    func testVolunteerRegistrationBasicInfoRequestEncodesIdCardFields() throws {
        let request = BasicInfoRequest(
            name: "赵冉杰",
            phone: "18314551097",
            idCardName: "赵冉杰",
            idCardNumber: "110101199001011234",
            runningExperience: "3年跑步经验",
            hasGuidedBefore: true,
            emergencyExperience: nil
        )

        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["idCardName"] as? String, "赵冉杰")
        XCTAssertEqual(object["idCardNumber"] as? String, "110101199001011234")
    }

    func testVolunteerRegistrationStep1UsesNameAsIdCardName() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let client = BasicInfoStatusAPIClient(
            status: VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true, idVerifyStatus: "APPROVED")
        )
        let viewModel = VolunteerRegistrationViewModel(apiClient: client)
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.name = "赵冉杰"
        viewModel.phone = "13800138000"
        viewModel.idCardName = "不应提交的旧姓名"
        viewModel.idCardNumber = "110101199001011234"

        await viewModel.submitBasicInfo()

        XCTAssertEqual(client.capturedRequest?.name, "赵冉杰")
        XCTAssertEqual(client.capturedRequest?.idCardName, "赵冉杰")
        XCTAssertEqual(client.capturedRequest?.idCardNumber, "110101199001011234")
    }

    func testVolunteerRegistrationStep1AcceptsGenericSuccessResponse() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = VolunteerRegistrationViewModel()
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.name = "测试志愿者"
        viewModel.phone = "13800000002"
        viewModel.idCardName = "测试志愿者"
        viewModel.idCardNumber = "110101199001011234"

        await viewModel.submitBasicInfo()

        XCTAssertEqual(viewModel.currentStep, .faceVerify)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(speechService.lastSpokenText, "身份核验通过，请开始活体认证")
    }

    func testVolunteerRegistrationBasicInfoShowsBlockedReasonForInvalidPhone() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = VolunteerRegistrationViewModel()
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.name = "赵冉杰"
        viewModel.phone = "1831455097"
        viewModel.idCardName = "赵冉杰"
        viewModel.idCardNumber = "110101199001011234"

        XCTAssertFalse(viewModel.canSubmitBasicInfo)
        XCTAssertEqual(viewModel.basicInfoValidationMessage, "请输入 11 位中国大陆手机号")

        await viewModel.submitBasicInfo()

        XCTAssertEqual(viewModel.currentStep, .basicInfo)
        XCTAssertEqual(viewModel.errorMessage, "请输入 11 位中国大陆手机号")
        XCTAssertEqual(speechService.lastSpokenText, "请输入 11 位中国大陆手机号")
    }

    func testVolunteerRegistrationPhoneDirectAssignmentKeepsOnlyFirstElevenDigits() {
        let viewModel = VolunteerRegistrationViewModel()

        viewModel.phone = "13800138000999"

        XCTAssertEqual(viewModel.phone, "13800138000")
    }

    func testVolunteerRegistrationPhoneInputDropsNonDigits() {
        let viewModel = VolunteerRegistrationViewModel()

        viewModel.phone = "abc 138-0013-8000 xyz"

        XCTAssertEqual(viewModel.phone, "13800138000")
    }

    func testVolunteerRegistrationIdCardDirectAssignmentKeepsOnlyFirstEighteenCharacters() {
        let viewModel = VolunteerRegistrationViewModel()

        viewModel.idCardNumber = "1101011990010112345678"

        XCTAssertEqual(viewModel.idCardNumber, "110101199001011234")
    }

    func testVolunteerRegistrationIdCardAllowsLowercaseXCheckDigit() {
        let viewModel = VolunteerRegistrationViewModel()

        viewModel.name = "赵冉杰"
        viewModel.phone = "13800138000"
        viewModel.idCardName = "赵冉杰"
        viewModel.idCardNumber = "11010119900101123x"

        XCTAssertNil(viewModel.identityInfoValidationMessage)
        XCTAssertTrue(viewModel.canSubmitBasicInfo)
    }

    func testVolunteerRegistrationInvalidIdCardNumberBlocksStep1Submit() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = VolunteerRegistrationViewModel()
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.name = "赵冉杰"
        viewModel.phone = "13800138000"
        viewModel.idCardName = "赵冉杰"
        viewModel.idCardNumber = "123"

        XCTAssertFalse(viewModel.canSubmitBasicInfo)
        XCTAssertEqual(viewModel.basicInfoValidationMessage, "请输入18位有效身份证号码")

        await viewModel.submitBasicInfo()

        XCTAssertEqual(viewModel.currentStep, .basicInfo)
        XCTAssertEqual(viewModel.errorMessage, "请输入18位有效身份证号码")
    }

    func testVolunteerRegistrationLoadStatusUnauthorizedExpiresSession() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        appState.accessToken = "expired-token"
        appState.userId = 12
        appState.activeRole = .volunteer
        let speechService = SpeechService()
        let viewModel = VolunteerRegistrationViewModel(apiClient: FailingAPIClient(error: APIError.unauthorized))
        viewModel.currentStep = .faceVerify
        viewModel.configure(appState: appState, speechService: speechService)

        await viewModel.loadStatus()

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(appState.accessToken)
        XCTAssertNil(appState.userId)
        XCTAssertNil(appState.activeRole)
        XCTAssertEqual(appState.consumeSessionExpirationMessage(), "登录已过期，请重新登录。")
    }

    func testVolunteerRegistrationStatusRoutesStringStepToFaceVerify() throws {
        let data = #"{"registrationStep":"STEP_3_FACE_VERIFY","step1Completed":true}"#
            .data(using: .utf8)!
        let status = try JSONDecoder().decode(VolunteerRegistrationStatus.self, from: data)
        let viewModel = VolunteerRegistrationViewModel()

        viewModel.applyRegistrationStatus(status)

        XCTAssertEqual(viewModel.currentStep, .faceVerify)
    }

    func testVolunteerRegistrationLegacyStep2StatusRoutesBackToBasicInfo() throws {
        let data = #"{"registrationStep":"STEP_2_ID_UPLOAD","step1Completed":true,"idVerifyStatus":"PENDING"}"#
            .data(using: .utf8)!
        let status = try JSONDecoder().decode(VolunteerRegistrationStatus.self, from: data)
        let viewModel = VolunteerRegistrationViewModel()

        viewModel.applyRegistrationStatus(status)

        XCTAssertEqual(viewModel.currentStep, .basicInfo)
    }

    func testVolunteerRegistrationStatusDecodesNestedStepDetails() throws {
        let data = """
        {
          "currentStep": "STEP_2_ID_UPLOAD",
          "canAcceptOrders": false,
          "stepDetails": {
            "idVerifyStatus": "REJECTED",
            "faceVerifyStatus": "NONE",
            "totalTrainingMinutes": 0,
            "completedCoursesCount": 0,
            "currentCourseId": null,
            "idVerifyRejectionReason": "照片不清晰"
          }
        }
        """.data(using: .utf8)!

        let status = try JSONDecoder().decode(VolunteerRegistrationStatus.self, from: data)
        let viewModel = VolunteerRegistrationViewModel()
        viewModel.applyRegistrationStatus(status)

        XCTAssertEqual(status.currentStepCode, "STEP_2_ID_UPLOAD")
        XCTAssertEqual(status.idVerifyStatus, "REJECTED")
        XCTAssertEqual(status.stepDetails?.idVerifyRejectionReason, "照片不清晰")
        XCTAssertFalse(status.isRegistrationComplete)
        XCTAssertEqual(viewModel.currentStep, .basicInfo)
    }

    func testVolunteerRegistrationStep1TwoFactorFailureStaysOnBasicInfo() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let client = BasicInfoFailingAPIClient(
            error: APIError.serverError(ErrorResponse(code: "ID_CARD_CHECK_FAILED", message: "身份证二要素核验未通过，请更新身份证信息"))
        )
        let viewModel = VolunteerRegistrationViewModel(apiClient: client)
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.name = "赵冉杰"
        viewModel.phone = "13800138000"
        viewModel.idCardName = "赵冉杰"
        viewModel.idCardNumber = "110101199001011234"

        await viewModel.submitBasicInfo()

        XCTAssertEqual(viewModel.currentStep, .basicInfo)
        XCTAssertEqual(viewModel.errorMessage, "身份证二要素核验未通过，请更新身份证信息")
        XCTAssertEqual(speechService.lastSpokenText, "身份证二要素核验未通过，请更新身份证信息")
    }

    func testVolunteerRegistrationStep1SuccessRefreshesToFaceVerifyStatus() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let client = BasicInfoStatusAPIClient(
            status: VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true, idVerifyStatus: "APPROVED")
        )
        let viewModel = VolunteerRegistrationViewModel(apiClient: client)
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.name = "赵冉杰"
        viewModel.phone = "13800138000"
        viewModel.idCardName = "赵冉杰"
        viewModel.idCardNumber = "110101199001011234"

        await viewModel.submitBasicInfo()

        XCTAssertEqual(client.submitCount, 1)
        XCTAssertEqual(client.statusRefreshCount, 1)
        XCTAssertEqual(viewModel.currentStep, .faceVerify)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(speechService.lastSpokenText, "身份核验通过，请开始活体认证")
    }

    func testVolunteerFaceVerifyInitPostsMetaInfoAndStartsNativeSDK() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let verifier = CloudAuthVerifierSpy(outcome: .cancelled)
        let client = FaceVerifyFlowAPIClient(
            initResponse: FaceVerifyInitResponse(
                certifyId: "cert-1",
                status: "PENDING",
                message: "请完成活体认证"
            ),
            resultResponses: []
        )
        let viewModel = VolunteerRegistrationViewModel(
            apiClient: client,
            metaInfoProvider: FixedCloudAuthMetaInfoProvider(metaInfo: #"{"device":"test"}"#),
            cloudAuthVerifier: verifier
        )
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true))

        await viewModel.startFaceVerify()

        XCTAssertEqual(client.initCount, 1)
        XCTAssertEqual(client.capturedMetaInfo, #"{"device":"test"}"#)
        XCTAssertEqual(verifier.receivedCertifyIds, ["cert-1"])
        XCTAssertEqual(verifier.receivedEnvironments, [.mock])
        XCTAssertNil(viewModel.activeCertifyId)
        XCTAssertEqual(viewModel.errorMessage, "已取消活体认证，可重新开始")
        XCTAssertTrue(viewModel.canStartFaceVerify)
        XCTAssertEqual(client.resultCount, 0)
    }

    func testCloudAuthMetaInfoSerializerEncodesAliyunDictionary() throws {
        let metaInfo: [AnyHashable: Any] = [
            "apdidToken": "token-123",
            "sdkVersion": "2.3.50",
            "device": [
                "platform": "ios",
                "features": ["camera", "liveness"]
            ]
        ]

        let json = try DefaultCloudAuthMetaInfoProvider.serializedMetaInfo(from: metaInfo)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let device = try XCTUnwrap(object["device"] as? [String: Any])
        let features = try XCTUnwrap(device["features"] as? [String])

        XCTAssertEqual(object["apdidToken"] as? String, "token-123")
        XCTAssertEqual(object["sdkVersion"] as? String, "2.3.50")
        XCTAssertEqual(device["platform"] as? String, "ios")
        XCTAssertEqual(features, ["camera", "liveness"])
    }

    func testCloudAuthRequiredResourcesAreBundled() throws {
        let requiredBundles = [
            "APBToygerFacade",
            "APBToygerFacadeSuitable",
            "BioAuthEngine",
            "ToygerService"
        ]

        for bundleName in requiredBundles {
            XCTAssertNotNil(
                Bundle.main.url(forResource: bundleName, withExtension: "bundle"),
                "Missing required CloudAuth resource bundle: \(bundleName).bundle"
            )
        }

        let toygerBundleURL = try XCTUnwrap(
            Bundle.main.url(forResource: "ToygerService", withExtension: "bundle")
        )
        let modelURL = toygerBundleURL.appendingPathComponent("toyger.face.dat")
        let attributes = try FileManager.default.attributesOfItem(atPath: modelURL.path)
        let modelSize = try XCTUnwrap(attributes[.size] as? NSNumber)

        XCTAssertGreaterThan(modelSize.intValue, 0, "CloudAuth face model must not be empty")
    }

    func testCloudAuthUnusedOptionalModulesAreExcluded() {
#if canImport(OCRDetectSDKForTech)
        XCTFail("OCR CloudAuth module must remain excluded from the ID_PRO-only target")
#endif
#if canImport(DTFNFCIdentityManager)
        XCTFail("NFC CloudAuth module must remain excluded from the ID_PRO-only target")
#endif
#if canImport(MultiFactorFacade)
        XCTFail("MultiFactor CloudAuth module must remain excluded from the ID_PRO-only target")
#endif
#if canImport(DTFBeauty)
        XCTFail("Beauty CloudAuth module must remain excluded from the ID_PRO-only target")
#endif
    }

    func testCloudAuthMetaInfoSerializerRejectsEmptyDictionary() {
        XCTAssertThrowsError(try DefaultCloudAuthMetaInfoProvider.serializedMetaInfo(from: [:])) { error in
            guard let metaInfoError = error as? CloudAuthMetaInfoError else {
                return XCTFail("Expected CloudAuthMetaInfoError")
            }
            XCTAssertEqual(metaInfoError.localizedDescription, "活体认证 SDK 初始化失败，请重试")
        }
    }

    func testDefaultCloudAuthVerifierMapsSDKCompletionCodes() {
        XCTAssertEqual(DefaultCloudAuthVerifier.outcome(forSDKCode: 1000), .submitted)
        XCTAssertEqual(DefaultCloudAuthVerifier.outcome(forSDKCode: 2006), .submitted)
        XCTAssertEqual(DefaultCloudAuthVerifier.outcome(forSDKCode: 1003), .cancelled)
        XCTAssertEqual(failureKind(for: DefaultCloudAuthVerifier.outcome(forSDKCode: 1001)), .internalError)
        XCTAssertEqual(failureKind(for: DefaultCloudAuthVerifier.outcome(forSDKCode: 2002)), .networkError)
        XCTAssertEqual(failureKind(for: DefaultCloudAuthVerifier.outcome(forSDKCode: 2003)), .deviceTimeError)
        XCTAssertEqual(failureKind(for: DefaultCloudAuthVerifier.outcome(forSDKCode: 9999)), .unknown(code: 9999))
    }

    func testCloudAuthDiagnosticsKeepOnlyBoundedTechnicalFields() {
        let diagnostics = CloudAuthSDKDiagnostics(
            code: 1001,
            retCode: 1001,
            retCodeSub: " z1014 ",
            retMessageSub: "raw-message-must-not-be-logged",
            sdkVersion: "2.3.50"
        )

        XCTAssertEqual(diagnostics.retCodeSub, "Z1014")
        XCTAssertTrue(diagnostics.retMessageSubPresent)
        XCTAssertEqual(diagnostics.retMessageSubLength, 30)
        XCTAssertEqual(diagnostics.sdkVersion, "2.3.50")
        XCTAssertTrue(diagnostics.debugSummary.contains("retCodeSub=Z1014"))
        XCTAssertTrue(diagnostics.debugSummary.contains("retMessageSubLength=30"))
        XCTAssertFalse(diagnostics.debugSummary.contains("raw-message"))
    }

    func testCloudAuthDiagnosticsRejectUnsafeSubcodeAndVersion() {
        let diagnostics = CloudAuthSDKDiagnostics(
            code: 1001,
            retCode: 1001,
            retCodeSub: "Z1014 certify-secret",
            retMessageSub: nil,
            sdkVersion: "2.3.50 secret"
        )

        XCTAssertNil(diagnostics.retCodeSub)
        XCTAssertNil(diagnostics.sdkVersion)
        XCTAssertFalse(diagnostics.retMessageSubPresent)
        XCTAssertEqual(diagnostics.retMessageSubLength, 0)
        XCTAssertFalse(diagnostics.debugSummary.contains("secret"))
    }

    func testDefaultCloudAuthVerifierMapsDetailedSubcodes() {
        let mappings: [(String, CloudAuthVerificationFailure.Kind)] = [
            ("Z1014", .internalError),
            ("Z1023", .internalError),
            ("I4001", .moduleIntegration),
            ("Z1010", .businessParameter),
            ("Z1037", .businessParameter),
            ("Z1001", .cameraUnavailable),
            ("Z1002", .cameraUnavailable),
            ("Z1020", .cameraUnavailable),
            ("Z1024", .duplicateFlow)
        ]

        for (subcode, expectedKind) in mappings {
            let diagnostics = CloudAuthSDKDiagnostics(
                code: 1001,
                retCode: 1001,
                retCodeSub: subcode,
                retMessageSub: "not retained",
                sdkVersion: "2.3.50"
            )
            let outcome = DefaultCloudAuthVerifier.outcome(for: diagnostics)
            XCTAssertEqual(failureKind(for: outcome), expectedKind, "Unexpected mapping for \(subcode)")
        }
    }

    func testDefaultCloudAuthVerifierTopLevelCodesTakePrecedenceOverDiagnosticSubcodes() {
        func outcome(code: Int) -> CloudAuthVerificationOutcome {
            DefaultCloudAuthVerifier.outcome(for: CloudAuthSDKDiagnostics(
                code: code,
                retCode: code,
                retCodeSub: "Z1014",
                retMessageSub: "not retained",
                sdkVersion: "2.3.50"
            ))
        }

        XCTAssertEqual(outcome(code: 1000), .submitted)
        XCTAssertEqual(outcome(code: 2006), .submitted)
        XCTAssertEqual(outcome(code: 1003), .cancelled)
        XCTAssertEqual(failureKind(for: outcome(code: 2002)), .networkError)
        XCTAssertEqual(failureKind(for: outcome(code: 2003)), .deviceTimeError)
    }

    func testCloudAuthSDKRuntimeInitializesOnlyOnce() {
        var initializeCalls = 0
        var versionCalls = 0
        let runtime = CloudAuthSDKRuntime(
            initializeSDK: { initializeCalls += 1 },
            versionProvider: {
                versionCalls += 1
                return "2.3.50"
            }
        )

        XCTAssertNil(runtime.sdkVersion)
        runtime.initializeIfNeeded()
        runtime.initializeIfNeeded()

        XCTAssertEqual(initializeCalls, 1)
        XCTAssertEqual(runtime.initializationCount, 1)
        XCTAssertEqual(runtime.sdkVersion, "2.3.50")
        XCTAssertEqual(versionCalls, 1)
    }

    func testCloudAuthOneShotGateAcceptsOnlyFirstCallback() {
        let gate = CloudAuthOneShotGate()

        XCTAssertTrue(gate.claim())
        XCTAssertFalse(gate.claim())
    }

    func testVolunteerFaceVerifyMissingCertifyIdDoesNotStartNativeSDK() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let verifier = CloudAuthVerifierSpy(outcome: .submitted)
        let client = FaceVerifyFlowAPIClient(
            initResponse: FaceVerifyInitResponse(certifyId: nil, status: "PENDING", message: nil),
            resultResponses: []
        )
        let viewModel = VolunteerRegistrationViewModel(
            apiClient: client,
            metaInfoProvider: FixedCloudAuthMetaInfoProvider(metaInfo: #"{"device":"test"}"#),
            cloudAuthVerifier: verifier
        )
        viewModel.configure(appState: appState, speechService: SpeechService())
        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true))

        await viewModel.startFaceVerify()

        XCTAssertTrue(verifier.receivedCertifyIds.isEmpty)
        XCTAssertEqual(client.resultCount, 0)
        XCTAssertEqual(viewModel.errorMessage, "活体认证服务返回不完整，请稍后重试")
    }

    func testVolunteerFaceVerifyInitErrorDoesNotPollOrEnterTraining() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let client = FaceVerifyFlowAPIClient(
            initResponse: FaceVerifyInitResponse(certifyId: nil, status: "ERROR", message: "发起失败"),
            resultResponses: []
        )
        let viewModel = VolunteerRegistrationViewModel(
            apiClient: client,
            metaInfoProvider: FixedCloudAuthMetaInfoProvider(metaInfo: #"{"device":"test"}"#)
        )
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true))

        await viewModel.startFaceVerify()

        XCTAssertEqual(viewModel.currentStep, .faceVerify)
        XCTAssertNil(viewModel.activeCertifyId)
        XCTAssertEqual(client.resultCount, 0)
        XCTAssertEqual(viewModel.errorMessage, "发起失败")
    }

    func testVolunteerFaceVerifyIdentityErrorAllowsReturnToBasicInfoEdit() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let client = FaceVerifyFlowAPIClient(
            initResponse: FaceVerifyInitResponse(certifyId: nil, status: "ERROR", message: nil),
            initError: APIError.serverError(ErrorResponse(code: "ID_INFO_INVALID", message: "身份信息格式不正确")),
            resultResponses: [],
            status: VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true)
        )
        let viewModel = VolunteerRegistrationViewModel(
            apiClient: client,
            metaInfoProvider: FixedCloudAuthMetaInfoProvider(metaInfo: #"{"device":"test"}"#)
        )
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true))

        await viewModel.startFaceVerify()

        XCTAssertEqual(client.statusRefreshCount, 1)
        XCTAssertEqual(viewModel.currentStep, .faceVerify)
        XCTAssertNil(viewModel.activeCertifyId)
        XCTAssertTrue(viewModel.canReturnToBasicInfoForIdentityEdit)
        XCTAssertEqual(viewModel.errorMessage, "身份信息格式不正确")

        viewModel.returnToBasicInfoForIdentityEdit()

        XCTAssertEqual(viewModel.currentStep, .basicInfo)
        XCTAssertFalse(viewModel.canReturnToBasicInfoForIdentityEdit)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testVolunteerFaceVerifyPendingResultKeepsWaiting() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let client = FaceVerifyFlowAPIClient(
            initResponse: FaceVerifyInitResponse(certifyId: "cert-1", status: "PENDING", message: nil),
            resultResponses: [FaceVerifyResponse(passed: false, status: "PENDING", message: "结果处理中")]
        )
        let viewModel = VolunteerRegistrationViewModel(
            apiClient: client,
            metaInfoProvider: FixedCloudAuthMetaInfoProvider(metaInfo: #"{"device":"test"}"#)
        )
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true))

        viewModel.activeCertifyId = "cert-1"
        let finished = await viewModel.pollFaceVerifyResultOnce()

        XCTAssertFalse(finished)
        XCTAssertEqual(viewModel.currentStep, .faceVerify)
        XCTAssertEqual(viewModel.activeCertifyId, "cert-1")
        XCTAssertEqual(viewModel.faceVerifyMessage, "结果处理中")
    }

    func testVolunteerFaceVerifyRejectedResultAllowsRetry() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let client = FaceVerifyFlowAPIClient(
            initResponse: FaceVerifyInitResponse(certifyId: "cert-1", status: "PENDING", message: nil),
            resultResponses: [FaceVerifyResponse(passed: false, status: "REJECTED", message: "认证未通过")]
        )
        let viewModel = VolunteerRegistrationViewModel(
            apiClient: client,
            metaInfoProvider: FixedCloudAuthMetaInfoProvider(metaInfo: #"{"device":"test"}"#)
        )
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true))

        viewModel.activeCertifyId = "cert-1"
        let finished = await viewModel.pollFaceVerifyResultOnce()

        XCTAssertTrue(finished)
        XCTAssertEqual(viewModel.currentStep, .faceVerify)
        XCTAssertNil(viewModel.activeCertifyId)
        XCTAssertTrue(viewModel.canStartFaceVerify)
        XCTAssertEqual(viewModel.errorMessage, "认证未通过")
    }

    func testVolunteerFaceVerifySubmittedSDKPollsApprovedResultAndEntersTraining() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let verifier = CloudAuthVerifierSpy(outcome: .submitted)
        let client = FaceVerifyFlowAPIClient(
            initResponse: FaceVerifyInitResponse(certifyId: "cert-1", status: "PENDING", message: nil),
            resultResponses: [FaceVerifyResponse(passed: true, status: "APPROVED", message: "认证通过")],
            status: VolunteerRegistrationStatus(currentStepCode: "STEP_4_TRAINING", step1Completed: true, step3Completed: true)
        )
        let viewModel = VolunteerRegistrationViewModel(
            apiClient: client,
            metaInfoProvider: FixedCloudAuthMetaInfoProvider(metaInfo: #"{"device":"test"}"#),
            cloudAuthVerifier: verifier
        )
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true))

        await viewModel.startFaceVerify()

        XCTAssertEqual(verifier.receivedCertifyIds, ["cert-1"])
        XCTAssertEqual(client.resultCount, 1)
        XCTAssertEqual(viewModel.currentStep, .training)
        XCTAssertNil(viewModel.activeCertifyId)
        XCTAssertEqual(client.trainingCoursesCount, 1)
        XCTAssertEqual(client.statusRefreshCount, 1)
        XCTAssertEqual(speechService.lastSpokenText, "认证通过")
    }

    func testVolunteerFaceVerifySDKFailureClearsCertifyIdAndAllowsRetry() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let client = FaceVerifyFlowAPIClient(
            initResponse: FaceVerifyInitResponse(certifyId: "cert-1", status: "PENDING", message: nil),
            resultResponses: []
        )
        let viewModel = VolunteerRegistrationViewModel(
            apiClient: client,
            metaInfoProvider: FixedCloudAuthMetaInfoProvider(metaInfo: #"{"device":"test"}"#),
            cloudAuthVerifier: CloudAuthVerifierSpy(outcome: .failed(.networkError))
        )
        viewModel.configure(appState: appState, speechService: SpeechService())
        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true))

        await viewModel.startFaceVerify()

        XCTAssertNil(viewModel.activeCertifyId)
        XCTAssertTrue(viewModel.canStartFaceVerify)
        XCTAssertEqual(client.resultCount, 0)
        XCTAssertEqual(viewModel.errorMessage, "活体认证网络连接失败，请检查网络后重试")
    }

    func testVolunteerFaceVerifyBusinessParameterSubcodeIsSafeAndRetryable() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let diagnostics = CloudAuthSDKDiagnostics(
            code: 1001,
            retCode: 1001,
            retCodeSub: "Z1010",
            retMessageSub: "certifyId must never be shown",
            sdkVersion: "2.3.50"
        )
        let failure = CloudAuthVerificationFailure(kind: .businessParameter, diagnostics: diagnostics)
        let client = FaceVerifyFlowAPIClient(
            initResponse: FaceVerifyInitResponse(certifyId: "cert-1", status: "PENDING", message: nil),
            resultResponses: []
        )
        let viewModel = VolunteerRegistrationViewModel(
            apiClient: client,
            metaInfoProvider: FixedCloudAuthMetaInfoProvider(metaInfo: #"{"device":"test"}"#),
            cloudAuthVerifier: CloudAuthVerifierSpy(outcome: .failed(failure))
        )
        viewModel.configure(appState: appState, speechService: SpeechService())
        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true))

        await viewModel.startFaceVerify()

        XCTAssertNil(viewModel.activeCertifyId)
        XCTAssertTrue(viewModel.canStartFaceVerify)
        XCTAssertEqual(client.resultCount, 0)
        XCTAssertEqual(viewModel.errorMessage, "活体认证参数或流程配置异常，请重新发起认证（错误码 Z1010）")
        XCTAssertFalse(viewModel.errorMessage?.contains("certifyId") == true)
    }

    func testVolunteerRegistrationRefreshesStatusWhenBasicInfoAlreadyCompleted() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let _: EmptyResponse = try await appState.apiClient.post(
            "/api/volunteer/registration/step1",
            body: BasicInfoRequest(
                name: "赵冉杰",
                phone: "13800138000",
                idCardName: "赵冉杰",
                idCardNumber: "110101199001011234",
                runningExperience: nil,
                hasGuidedBefore: true,
                emergencyExperience: nil
            )
        )
        let viewModel = VolunteerRegistrationViewModel()
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.name = "赵冉杰"
        viewModel.phone = "18314555097"
        viewModel.idCardName = "赵冉杰"
        viewModel.idCardNumber = "110101199001011234"

        await viewModel.submitBasicInfo()

        XCTAssertEqual(viewModel.currentStep, .faceVerify)
        XCTAssertEqual(viewModel.errorMessage, "已同步注册进度，请继续完成活体认证")
        XCTAssertEqual(speechService.lastSpokenText, "已同步注册进度，请继续完成活体认证")
    }

    func testVolunteerFaceCameraPermissionUsageDescriptionIsConfigured() throws {
        let cameraUsageDescription = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String
        )

        XCTAssertFalse(cameraUsageDescription.trimmed.isEmpty)
    }

    func testVolunteerCertificationEntryDoesNotRequireSeparateNicknameSubmit() {
        let appState = AppState()
        appState.currentEnvironment = .demoCloud
        appState.updateVolunteerProfile(makeVolunteerProfile(name: "", verificationStatus: "not_submitted"))
        let viewModel = VolunteerProfileViewModel()

        viewModel.configure(with: appState, speechService: SpeechService())

        XCTAssertEqual(viewModel.certificationButtonTitle, "开始认证")
        XCTAssertEqual(viewModel.certificationAccessibilityHint, "点击后进入志愿者注册认证流程")
        XCTAssertFalse(viewModel.canSubmit)
    }

    func testMaintainedDocsDoNotUseForbiddenLowercaseOrderStatusVocabulary() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let docs = [
            root.appendingPathComponent("docs/01-product-requirements.md"),
            root.appendingPathComponent("docs/02-mvp-scope.md"),
            root.appendingPathComponent("docs/03-user-stories.md"),
            root.appendingPathComponent("docs/04-user-flows-and-state-machine.md"),
            root.appendingPathComponent("docs/05-page-specs.md"),
            root.appendingPathComponent("docs/06-data-model.md"),
            root.appendingPathComponent("docs/07-api-contract.openapi.yaml"),
            root.appendingPathComponent("docs/08-ios-architecture.md"),
            root.appendingPathComponent("docs/09-accessibility-and-voice-guidelines.md"),
            root.appendingPathComponent("docs/10-ai-coding-tasks.md"),
            root.appendingPathComponent("docs/test-accounts.md"),
            root.appendingPathComponent("docs/websocket-protocol.md")
        ]
        let forbiddenFragments = [
            "`matching`",
            "`accepted`",
            "`arrived`",
            "`in_progress`",
            "`completed`",
            "`cancelled`",
            "terminal `emergency`",
            "status: \"matching\"",
            "status: \"accepted\"",
            "status: \"arrived\"",
            "status: \"in_progress\"",
            "status: \"completed\"",
            "status: \"cancelled\"",
            "状态流转为 emergency",
            "`/api/orders/{orderId}/arrive`",
            "`/api/orders/{id}/arrive`"
        ]

        guard FileManager.default.fileExists(atPath: docs[0].path) else {
            throw XCTSkip("Repository docs are not available inside the real-device test sandbox. Run scripts/validate-docs.mjs from the repository root.")
        }

        for doc in docs {
            let text = try String(contentsOf: doc)
            for fragment in forbiddenFragments {
                XCTAssertFalse(text.contains(fragment), "\(doc.lastPathComponent) contains forbidden fragment: \(fragment)")
            }
        }
    }

    func testMaskedEmergencyContactRemainsValidAndIsNotSubmittedAsPhone() {
        let appState = AppState()
        appState.updateBlindProfile(BlindProfileResponse(name: "测试用户"))
        appState.updateEmergencyContacts([
            EmergencyContactResponse(
                id: 1,
                name: "联系人",
                phone: "138****1111",
                relationship: nil,
                isPrimary: true
            )
        ])
        let viewModel = BlindRunnerProfileViewModel()

        viewModel.configure(with: appState, speechService: SpeechService())
        viewModel.sanitizePhoneInput(viewModel.emergencyContactPhone)

        XCTAssertEqual(viewModel.emergencyContactPhone, "138****1111")
        XCTAssertTrue(viewModel.isPhoneValid)
        XCTAssertNil(viewModel.emergencyContactPhoneForRequest)
    }

    func testEmergencyContactPhoneDirectAssignmentKeepsOnlyFirstElevenDigits() {
        let viewModel = BlindRunnerProfileViewModel()

        viewModel.emergencyContactPhone = "13800138000999"

        XCTAssertEqual(viewModel.emergencyContactPhone, "13800138000")
    }

    func testEmergencyContactPhoneSanitizeDropsNonDigitsAndKeepsElevenDigits() {
        let viewModel = BlindRunnerProfileViewModel()

        viewModel.sanitizePhoneInput("abc 138-0013-8000 xyz")

        XCTAssertEqual(viewModel.emergencyContactPhone, "13800138000")
    }

    func testLoginResponseDecodesCorrectly() throws {
        let json = """
        {
          "token": "eyJhbGciOiJIUzI1NiJ9.test",
          "userId": 1,
          "role": "BLIND"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(LoginResponse.self, from: json)

        XCTAssertEqual(response.token, "eyJhbGciOiJIUzI1NiJ9.test")
        XCTAssertEqual(response.userId, 1)
        XCTAssertEqual(response.role, "BLIND")
    }

    func testLoginRoleResolverTreatsUnsetAndMissingRoleAsRoleSelection() {
        XCTAssertNil(AppState.resolvedLoginRole(from: nil))
        XCTAssertNil(AppState.resolvedLoginRole(from: "UNSET"))
        XCTAssertNil(AppState.resolvedLoginRole(from: "UNKNOWN"))
        XCTAssertEqual(AppState.resolvedLoginRole(from: "BLIND"), .blind)
        XCTAssertEqual(AppState.resolvedLoginRole(from: "VOLUNTEER"), .volunteer)
    }

    func testLoginSuccessClearsStaleRoleWhenBackendReturnsNoRole() {
        let appState = AppState()
        appState.currentEnvironment = .mock
        appState.activeRole = .volunteer

        appState.handleLoginSuccess(
            response: LoginResponse(
                token: "token",
                userId: 12,
                role: nil
            )
        )

        XCTAssertEqual(appState.accessToken, "token")
        XCTAssertEqual(appState.userId, 12)
        XCTAssertNil(appState.activeRole)
    }

    func testLoginSuccessClearsUnsetRoleToAvoidBlankRootRoute() {
        let appState = AppState()
        appState.currentEnvironment = .mock

        appState.handleLoginSuccess(
            response: LoginResponse(
                token: "token",
                userId: 12,
                role: "UNSET"
            )
        )

        XCTAssertNil(appState.activeRole)
    }

    func testExpireSessionClearsStateAndProvidesOneTimeLoginMessage() {
        let appState = AppState()
        appState.currentEnvironment = .mock
        appState.accessToken = "expired-token"
        appState.userId = 12
        appState.activeRole = .volunteer
        appState.updateVolunteerProfile(makeApprovedVolunteerProfile())

        appState.expireSession()

        XCTAssertNil(appState.accessToken)
        XCTAssertNil(appState.userId)
        XCTAssertNil(appState.activeRole)
        XCTAssertNil(appState.volunteerProfile)
        XCTAssertEqual(appState.consumeSessionExpirationMessage(), "登录已过期，请重新登录。")
        XCTAssertNil(appState.consumeSessionExpirationMessage())
    }

    func testAuthenticatedUnauthorizedErrorExpiresSession() {
        let appState = AppState()
        appState.currentEnvironment = .mock
        appState.accessToken = "expired-token"
        appState.userId = 12
        appState.activeRole = .blind

        let didExpire = appState.handleAuthenticatedAPIError(.unauthorized)

        XCTAssertTrue(didExpire)
        XCTAssertNil(appState.accessToken)
        XCTAssertNil(appState.userId)
        XCTAssertNil(appState.activeRole)
        XCTAssertEqual(appState.consumeSessionExpirationMessage(), "登录已过期，请重新登录。")
    }

    func testAuthenticatedNonUnauthorizedErrorDoesNotExpireSession() {
        let appState = AppState()
        appState.currentEnvironment = .mock
        appState.accessToken = "valid-token"
        appState.userId = 12
        appState.activeRole = .blind

        let didExpire = appState.handleAuthenticatedAPIError(.networkError(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)
        ))

        XCTAssertFalse(didExpire)
        XCTAssertEqual(appState.accessToken, "valid-token")
        XCTAssertEqual(appState.userId, 12)
        XCTAssertEqual(appState.activeRole, .blind)
        XCTAssertNil(appState.consumeSessionExpirationMessage())
    }

    func testRoleSelectionUnauthorizedExpiresSessionAndReturnsToLogin() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        appState.accessToken = "expired-token"
        appState.userId = 12
        let viewModel = RoleSelectionViewModel(apiClient: FailingAPIClient(error: APIError.unauthorized))
        viewModel.configure(with: appState, speechService: SpeechService())

        viewModel.selectRole(.volunteer)

        let didExpire = await waitUntil {
            appState.accessToken == nil &&
            appState.activeRole == nil &&
            appState.userId == nil &&
            !viewModel.isLoading
        }

        XCTAssertTrue(didExpire)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.showBlockedAlert)
        XCTAssertEqual(appState.consumeSessionExpirationMessage(), "登录已过期，请重新登录。")
    }

    func testLoginViewModelShowsAndConsumesSessionExpirationMessage() {
        let appState = AppState()
        appState.currentEnvironment = .mock
        appState.expireSession()
        let viewModel = LoginViewModel()

        viewModel.configure(with: appState, speechService: SpeechService())

        XCTAssertEqual(viewModel.errorMessage, "登录已过期，请重新登录。")
        XCTAssertNil(appState.consumeSessionExpirationMessage())

        viewModel.sanitizePhoneInput("138")

        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoginPhoneInputKeepsOnlyFirstElevenDigits() {
        let viewModel = LoginViewModel()

        viewModel.sanitizePhoneInput(" 138 0013 8000 999")

        XCTAssertEqual(viewModel.phoneNumber, "13800138000")
    }

    func testLoginPhoneInputDropsNonDigits() {
        let viewModel = LoginViewModel()

        viewModel.sanitizePhoneInput("abc138-0013-8000xyz")

        XCTAssertEqual(viewModel.phoneNumber, "13800138000")
    }

    func testLoginPhoneDirectAssignmentKeepsOnlyFirstElevenDigits() {
        let viewModel = LoginViewModel()

        viewModel.phoneNumber = "13800138000999"

        XCTAssertEqual(viewModel.phoneNumber, "13800138000")
    }

    func testLoginPhoneInputKeepsScreenshotLongValueToElevenDigits() {
        let viewModel = LoginViewModel()

        viewModel.sanitizePhoneInput("13800000001000000")

        XCTAssertEqual(viewModel.phoneNumber, "13800000001")
    }

    func testLoginPhoneSanitizeAlreadyCompleteValueKeepsElevenDigits() {
        let viewModel = LoginViewModel()
        viewModel.phoneNumber = "13800138000"

        viewModel.sanitizePhoneInput("138001380009")

        XCTAssertEqual(viewModel.phoneNumber, "13800138000")
    }

    func testLoginVerificationCodeInputKeepsOnlyFirstSixDigits() {
        let viewModel = LoginViewModel()

        viewModel.sanitizeVerificationCodeInput("000000789")

        XCTAssertEqual(viewModel.verificationCode, "000000")
    }

    func testLoginVerificationCodeInputDropsNonDigits() {
        let viewModel = LoginViewModel()

        viewModel.sanitizeVerificationCodeInput("abc 000-000 xyz")

        XCTAssertEqual(viewModel.verificationCode, "000000")
    }

    func testLoginVerificationCodeDirectAssignmentKeepsOnlyFirstSixDigits() {
        let viewModel = LoginViewModel()

        viewModel.verificationCode = "000000789"

        XCTAssertEqual(viewModel.verificationCode, "000000")
    }

    func testLoginVerificationCodeSanitizeAlreadyCompleteValueKeepsSixDigits() {
        let viewModel = LoginViewModel()
        viewModel.verificationCode = AppConstants.Auth.demoVerificationCode

        viewModel.sanitizeVerificationCodeInput("0000007")

        XCTAssertEqual(viewModel.verificationCode, "000000")
    }

    func testSubmitLoginWithCompleteInputsDoesNotReenterVerificationCodeSetter() {
        let viewModel = LoginViewModel()
        viewModel.phoneNumber = "13800138000"
        viewModel.verificationCode = AppConstants.Auth.demoVerificationCode

        viewModel.submitLogin()

        XCTAssertEqual(viewModel.phoneNumber, "13800138000")
        XCTAssertEqual(viewModel.verificationCode, "000000")
    }

    func testRequestCodeShowsInputOnlyAfterSendCodeSucceeds() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let viewModel = LoginViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())
        viewModel.phoneNumber = "13800138000"

        viewModel.requestCode()

        XCTAssertTrue(viewModel.isSendingCode)
        XCTAssertFalse(viewModel.showCodeInput)
        XCTAssertNil(viewModel.countdown)

        let didSend = await waitUntil {
            viewModel.showCodeInput &&
            viewModel.countdown != nil &&
            !viewModel.isSendingCode
        }

        XCTAssertTrue(didSend)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testRequestCodeFailureDoesNotStartCountdownOrShowInput() async {
        let viewModel = LoginViewModel(apiClient: FailingAPIClient(error: APIError.networkError(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)
        )))
        viewModel.phoneNumber = "13800138000"

        viewModel.requestCode()

        let didFail = await waitUntil {
            viewModel.errorMessage != nil && !viewModel.isSendingCode
        }

        XCTAssertTrue(didFail)
        XCTAssertEqual(viewModel.errorMessage, "网络错误，请重试")
        XCTAssertFalse(viewModel.showCodeInput)
        XCTAssertNil(viewModel.countdown)
    }

    func testTestAccountDoesNotUseSendCodeResponseBusinessCodeWhenEnteringFixedDemoCode() async {
        let client = LoginCodeCaptureAPIClient(sendCodeResponse: SendCodeResponse(
            success: true,
            message: "验证码已发送",
            code: "654321",
            verificationCode: nil,
            smsCode: nil
        ))
        let viewModel = LoginViewModel(apiClient: client)
        viewModel.phoneNumber = "13800000001"

        viewModel.requestCode()
        let didShowInput = await waitUntil { viewModel.showCodeInput }
        XCTAssertTrue(didShowInput)
        viewModel.sanitizeVerificationCodeInput(AppConstants.Auth.demoVerificationCode)

        let didCaptureFixedCode = await waitUntil { client.capturedVerifyCodeRequest?.code == AppConstants.Auth.demoVerificationCode }
        XCTAssertTrue(didCaptureFixedCode)
        XCTAssertEqual(client.capturedVerifyCodeRequest?.phone, "13800000001")
    }

    func testTestAccountUsesVerificationCodeFieldWhenEnteringFixedDemoCode() async {
        let client = LoginCodeCaptureAPIClient(sendCodeResponse: SendCodeResponse(
            success: true,
            message: "验证码已发送",
            code: nil,
            verificationCode: "123456",
            smsCode: nil
        ))
        let viewModel = LoginViewModel(apiClient: client)
        viewModel.phoneNumber = "13800000002"

        viewModel.requestCode()
        let didShowInput = await waitUntil { viewModel.showCodeInput }
        XCTAssertTrue(didShowInput)
        viewModel.sanitizeVerificationCodeInput(AppConstants.Auth.demoVerificationCode)

        let didCaptureHiddenCode = await waitUntil { client.capturedVerifyCodeRequest?.code == "123456" }
        XCTAssertTrue(didCaptureHiddenCode)
    }

    func testTestAccountUsesSMSCodeFieldWhenEnteringFixedDemoCode() async {
        let client = LoginCodeCaptureAPIClient(sendCodeResponse: SendCodeResponse(
            success: true,
            message: "验证码已发送",
            code: nil,
            verificationCode: nil,
            smsCode: "789012"
        ))
        let viewModel = LoginViewModel(apiClient: client)
        viewModel.phoneNumber = "13800000003"

        viewModel.requestCode()
        let didShowInput = await waitUntil { viewModel.showCodeInput }
        XCTAssertTrue(didShowInput)
        viewModel.sanitizeVerificationCodeInput(AppConstants.Auth.demoVerificationCode)

        let didCaptureHiddenCode = await waitUntil { client.capturedVerifyCodeRequest?.code == "789012" }
        XCTAssertTrue(didCaptureHiddenCode)
    }

    func testNonTestAccountDoesNotUseHiddenSendCodeWhenEnteringFixedDemoCode() async {
        let client = LoginCodeCaptureAPIClient(sendCodeResponse: SendCodeResponse(
            success: true,
            message: "验证码已发送",
            code: "654321",
            verificationCode: nil,
            smsCode: nil
        ))
        let viewModel = LoginViewModel(apiClient: client)
        viewModel.phoneNumber = "13800138000"

        viewModel.requestCode()
        let didShowInput = await waitUntil { viewModel.showCodeInput }
        XCTAssertTrue(didShowInput)
        viewModel.sanitizeVerificationCodeInput(AppConstants.Auth.demoVerificationCode)

        let didCaptureFixedCode = await waitUntil { client.capturedVerifyCodeRequest?.code == AppConstants.Auth.demoVerificationCode }
        XCTAssertTrue(didCaptureFixedCode)
    }

    func testTestAccountFallsBackToFixedDemoCodeWhenSendCodeReturnsNoHiddenCode() async {
        let client = LoginCodeCaptureAPIClient(sendCodeResponse: SendCodeResponse(
            success: true,
            message: "验证码已发送",
            code: nil,
            verificationCode: nil,
            smsCode: nil
        ))
        let viewModel = LoginViewModel(apiClient: client)
        viewModel.phoneNumber = "13800000004"

        viewModel.requestCode()
        let didShowInput = await waitUntil { viewModel.showCodeInput }
        XCTAssertTrue(didShowInput)
        viewModel.sanitizeVerificationCodeInput(AppConstants.Auth.demoVerificationCode)

        let didCaptureFixedCode = await waitUntil { client.capturedVerifyCodeRequest?.code == AppConstants.Auth.demoVerificationCode }
        XCTAssertTrue(didCaptureFixedCode)
    }

    func testDevelopmentInitialEnvironmentKeepsSupportedDebugChoices() {
        XCTAssertEqual(AppState.resolvedInitialEnvironment(.mock, channel: .development), .mock)
        XCTAssertEqual(AppState.resolvedInitialEnvironment(.demoCloud, channel: .development), .demoCloud)
    }

    func testDemoReleaseLocksInitialEnvironmentToDemoCloud() {
        XCTAssertEqual(AppState.resolvedInitialEnvironment(.mock, channel: .demo), .demoCloud)
        XCTAssertEqual(AppState.resolvedInitialEnvironment(.demoCloud, channel: .demo), .demoCloud)
    }

    func testProductionReleaseLocksInitialEnvironmentToDemoCloud() {
        XCTAssertEqual(AppState.resolvedInitialEnvironment(.mock, channel: .production), .demoCloud)
        XCTAssertEqual(AppState.resolvedInitialEnvironment(.demoCloud, channel: .production), .demoCloud)
    }

    func testUnknownStoredEnvironmentIsRejected() {
        XCTAssertNil(AppState.storedEnvironment(from: "unsupported"))
    }

    func testDemoCloudBaseURLUsesCurrentDemoIPAddress() {
        XCTAssertEqual(APIEnvironment.demoCloud.baseURL?.absoluteString, "http://47.114.113.171")
    }

    func testWebSocketUsesFixedCloudHost() throws {
        let baseURL = try XCTUnwrap(APIEnvironment.demoCloud.baseURL)
        let webSocketURL = try XCTUnwrap(WebSocketService.connectionURL(baseURL: baseURL, token: "jwt", role: .blind))

        XCTAssertEqual(webSocketURL.scheme, "ws")
        XCTAssertEqual(webSocketURL.host, "47.114.113.171")
        XCTAssertEqual(webSocketURL.path, "/ws/blind")
        XCTAssertTrue(webSocketURL.absoluteString.contains("token=jwt"))
    }

    func testDebugEnvironmentSwitcherCyclesMockAndDemoCloud() {
        let previousEnvironment = UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.apiEnvironment)
        defer {
            if let previousEnvironment {
                UserDefaults.standard.set(previousEnvironment, forKey: AppConstants.UserDefaultsKeys.apiEnvironment)
            } else {
                UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.apiEnvironment)
            }
        }

        UserDefaults.standard.set(APIEnvironment.mock.rawValue, forKey: AppConstants.UserDefaultsKeys.apiEnvironment)
        let appState = AppState()

        XCTAssertEqual(appState.currentEnvironment, .mock)
        appState.switchToNextEnvironmentForTesting()
        XCTAssertEqual(appState.currentEnvironment, .demoCloud)
        appState.switchToNextEnvironmentForTesting()
        XCTAssertEqual(appState.currentEnvironment, .mock)
    }

    func testCreateOrderRequestUsesOpenAPIWireValues() throws {
        let request = CreateOrderRequest(
            startLatitude: 31.2304,
            startLongitude: 121.4737,
            startAddress: "人民广场",
            plannedStartTime: "2026-05-22T09:00:00Z",
            plannedEndTime: "2026-05-22T10:00:00Z",
            expectedDurationMinutes: 60,
            pacePreference: .easy,
            routePreference: .parkTrail,
            routeNotes: "公园慢跑一圈",
            hasGuideDogThisRun: false,
            specialNotes: "请在地铁口见面"
        )

        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["startLatitude"] as? Double, 31.2304)
        XCTAssertEqual(json["startLongitude"] as? Double, 121.4737)
        XCTAssertEqual(json["startAddress"] as? String, "人民广场")
        XCTAssertEqual(json["routeNotes"] as? String, "公园慢跑一圈")
        XCTAssertEqual(json["specialNotes"] as? String, "请在地铁口见面")
        XCTAssertEqual(json["pacePreference"] as? String, "EASY")
        XCTAssertEqual(json["routePreference"] as? String, "PARK_TRAIL")
    }

    func testBlindBookingResolvedStartLocationKeepsCoordinatesAndAppendsManualDescription() {
        let viewModel = BlindBookingViewModel()
        viewModel.currentResolvedPlace = ResolvedPlace(
            id: "current",
            title: "当前位置",
            addressText: "上海市黄浦区人民广场",
            latitude: 31.2304,
            longitude: 121.4737,
            source: .deviceLocation
        )
        viewModel.startLocationDescription = "我在地铁口外侧"

        XCTAssertEqual(viewModel.resolvedStartPlace?.latitude, 31.2304)
        XCTAssertEqual(viewModel.resolvedStartPlace?.longitude, 121.4737)
        XCTAssertEqual(viewModel.resolvedStartPlace?.source, .deviceLocation)
        XCTAssertEqual(viewModel.resolvedStartLocationDescription, "上海市黄浦区人民广场；补充：我在地铁口外侧")
    }

    func testBlindBookingSpeechCompletionAutoSearchesStartPlaceAndAllowsRepeatedKeywordRetry() async {
        let place = ResolvedPlace(
            id: "poi-1",
            title: "大观楼",
            addressText: "大观楼，西山区 大观路284号",
            latitude: 25.024196,
            longitude: 102.673887,
            source: .manual
        )
        let provider = FakePlaceSearchProvider(results: [
            place
        ])
        let speechService = SpeechService()
        let viewModel = BlindBookingViewModel()
        viewModel.configureForTesting(placeSearchProvider: provider, speechService: speechService)

        await viewModel.handlePlaceSearchSpeechCompletion(SpeechInputCompletion(
            field: .startPlaceSearch,
            recognizedText: "大观",
            reason: .silenceTimeout(hadDetectedSound: true)
        ))
        viewModel.selectPlace(place)
        await viewModel.handlePlaceSearchSpeechCompletion(SpeechInputCompletion(
            field: .startPlaceSearch,
            recognizedText: " 大观 ",
            reason: .finalResult
        ))

        XCTAssertEqual(provider.searchKeywords, ["大观", "大观"])
        XCTAssertEqual(viewModel.placeSearchKeyword, "大观")
        XCTAssertEqual(viewModel.placeSearchResults.map(\.title), ["大观楼"])
        XCTAssertEqual(viewModel.searchResultFocusID, "poi-1")
        XCTAssertEqual(speechService.lastVoiceOverAnnouncement, "已找到 1 个地点，第一个是 大观楼。")
    }

    func testBlindBookingSpeechCompletionSkipsErrorAndNoSpeechTimeout() async {
        let provider = FakePlaceSearchProvider(results: [])
        let speechService = SpeechService()
        let viewModel = BlindBookingViewModel()
        viewModel.configureForTesting(placeSearchProvider: provider, speechService: speechService)

        await viewModel.handlePlaceSearchSpeechCompletion(SpeechInputCompletion(
            field: .startPlaceSearch,
            recognizedText: "大观",
            reason: .silenceTimeout(hadDetectedSound: false)
        ))
        await viewModel.handlePlaceSearchSpeechCompletion(SpeechInputCompletion(
            field: .startPlaceSearch,
            recognizedText: "大观",
            reason: .error
        ))

        XCTAssertTrue(provider.searchKeywords.isEmpty)
        XCTAssertTrue(viewModel.placeSearchResults.isEmpty)
    }

    func testResolvedPlaceBookingSearchAccessibilityLabelDoesNotExposeCoordinates() {
        let place = ResolvedPlace(
            id: "poi-1",
            title: "大观楼",
            addressText: "大观楼，西山区 大观路284号",
            latitude: 25.024196,
            longitude: 102.673887,
            source: .manual
        )

        XCTAssertEqual(place.bookingSearchAccessibilityLabel, "选择出发地点，大观楼，大观楼，西山区 大观路284号")
        XCTAssertFalse(place.bookingSearchAccessibilityLabel.contains("纬度"))
        XCTAssertFalse(place.bookingSearchAccessibilityLabel.contains("经度"))
        XCTAssertFalse(place.bookingSearchAccessibilityLabel.contains("25.024196"))
        XCTAssertFalse(place.bookingSearchAccessibilityLabel.contains("102.673887"))
    }

    func testBlindBookingRequiresAppointmentAtLeastThirtyMinutesLater() {
        let viewModel = BlindBookingViewModel()

        viewModel.appointmentTime = Date().addingTimeInterval(10 * 60)

        XCTAssertFalse(viewModel.isAppointmentTimeValid)

        viewModel.appointmentTime = Date().addingTimeInterval(31 * 60)

        XCTAssertTrue(viewModel.isAppointmentTimeValid)
    }

    func testBlindBookingGuidedStepValidationBlocksInvalidAppointmentAndSpeaksReason() {
        let speechService = SpeechService()
        let viewModel = BlindBookingViewModel()
        viewModel.configureForTesting(
            placeSearchProvider: FakePlaceSearchProvider(results: []),
            speechService: speechService
        )
        viewModel.currentStep = .appointmentTime
        viewModel.appointmentTime = Date().addingTimeInterval(10 * 60)

        viewModel.moveToNextStep()

        XCTAssertEqual(viewModel.currentStep, .appointmentTime)
        XCTAssertEqual(viewModel.errorMessage, "预约时间需至少在 30 分钟后。")
        XCTAssertEqual(speechService.lastSpokenText, "预约时间需至少在 30 分钟后。")
        XCTAssertFalse(viewModel.canAdvanceFromCurrentStep)
    }

    func testBlindBookingGuidedStepSummariesOmitEmptyOptionalNeeds() {
        let speechService = SpeechService()
        let viewModel = BlindBookingViewModel()
        viewModel.configureForTesting(
            placeSearchProvider: FakePlaceSearchProvider(results: []),
            speechService: speechService
        )
        viewModel.currentStep = .runningNeeds

        XCTAssertTrue(viewModel.optionalReviewItems.isEmpty)
        XCTAssertEqual(viewModel.optionalNeedsSpeechSummary, "没有填写选填跑步需求。")

        viewModel.routeNotes = "沿公园慢跑一圈"
        viewModel.pacePreference = .easy
        viewModel.specialNotes = "我会带导盲杖"
        viewModel.repeatCurrentStepStatus()

        XCTAssertEqual(viewModel.optionalReviewItems.map(\.title), ["路线备注", "配速偏好", "特殊说明"])
        XCTAssertTrue(speechService.lastSpokenText?.contains("路线备注：沿公园慢跑一圈") == true)
        XCTAssertTrue(speechService.lastSpokenText?.contains("配速偏好：轻松") == true)
        XCTAssertFalse(speechService.lastSpokenText?.contains("预计时长") == true)
        XCTAssertFalse(speechService.lastSpokenText?.contains("路线偏好") == true)
    }

    func testBlindBookingCreateOrderRequestKeepsPayloadFieldsThroughGuidedFlow() throws {
        let viewModel = BlindBookingViewModel()
        viewModel.selectedStartPlace = ResolvedPlace(
            id: "poi-1",
            title: "科技园地铁站",
            addressText: "深圳市南山区科技园地铁站 A 口",
            latitude: 22.5401,
            longitude: 113.9345,
            source: .manual
        )
        viewModel.startLocationDescription = "我在 A 口外侧"
        viewModel.appointmentTime = try XCTUnwrap(DateFormatter.aidRunBackendLocalDateTime.date(from: "2026-07-06T09:30:00"))
        viewModel.duration = .sixty
        viewModel.pacePreference = .moderate
        viewModel.routePreference = .parkTrail
        viewModel.routeNotes = "沿公园慢跑一圈"
        viewModel.hasGuideDogThisRun = true
        viewModel.specialNotes = "我会带导盲杖"

        let request = try XCTUnwrap(viewModel.makeCreateOrderRequest())

        XCTAssertEqual(request.startLatitude, 22.5401, accuracy: 0.000001)
        XCTAssertEqual(request.startLongitude, 113.9345, accuracy: 0.000001)
        XCTAssertEqual(request.startAddress, "深圳市南山区科技园地铁站 A 口；补充：我在 A 口外侧")
        XCTAssertEqual(request.plannedStartTime, "2026-07-06T09:30:00")
        XCTAssertEqual(request.plannedEndTime, "2026-07-06T10:30:00")
        XCTAssertEqual(request.expectedDurationMinutes, 60)
        XCTAssertEqual(request.pacePreference, .moderate)
        XCTAssertEqual(request.routePreference, .parkTrail)
        XCTAssertEqual(request.routeNotes, "沿公园慢跑一圈")
        XCTAssertEqual(request.hasGuideDogThisRun, true)
        XCTAssertEqual(request.specialNotes, "我会带导盲杖")
    }

    func testBlindBookingAuxiliaryMapAccessibilityLabelDoesNotExposeCoordinates() {
        let viewModel = BlindBookingViewModel()
        viewModel.selectedStartPlace = ResolvedPlace(
            id: "poi-1",
            title: "大观楼",
            addressText: "大观楼，西山区 大观路284号",
            latitude: 25.024196,
            longitude: 102.673887,
            source: .manual
        )

        XCTAssertTrue(viewModel.auxiliaryMapAccessibilityLabel.contains("辅助地图"))
        XCTAssertTrue(viewModel.auxiliaryMapAccessibilityLabel.contains("已选择高德地点"))
        XCTAssertFalse(viewModel.auxiliaryMapAccessibilityLabel.contains("25.024196"))
        XCTAssertFalse(viewModel.auxiliaryMapAccessibilityLabel.contains("102.673887"))
    }

    func testBlindBookingLocationRefreshUpdatesPayloadWhileStabilizingAuxiliaryMapMarker() async throws {
        let locationService = LocationService()
        let initialPlace = ResolvedPlace(
            id: "current-1",
            title: "当前位置",
            addressText: "深圳市南山区科技园",
            latitude: 22.5401,
            longitude: 113.9345,
            source: .deviceLocation
        )
        let smallMovePlace = ResolvedPlace(
            id: "current-2",
            title: "当前位置",
            addressText: "深圳市南山区科技园 A 口",
            latitude: 22.5402,
            longitude: 113.9345,
            source: .deviceLocation
        )
        let largeMovePlace = ResolvedPlace(
            id: "current-3",
            title: "当前位置",
            addressText: "深圳市南山区科技园 B 口",
            latitude: 22.5410,
            longitude: 113.9345,
            source: .deviceLocation
        )
        let provider = FakePlaceSearchProvider(
            results: [],
            reverseGeocodeResults: [initialPlace, smallMovePlace, largeMovePlace]
        )
        let viewModel = BlindBookingViewModel()
        viewModel.configureForTesting(
            placeSearchProvider: provider,
            speechService: SpeechService(),
            locationService: locationService
        )

        await viewModel.refreshCurrentLocation()
        let demoCenter = try XCTUnwrap(viewModel.auxiliaryMapCenter)
        XCTAssertEqual(viewModel.auxiliaryMapPlace?.source, .demoDefault)

        locationService.currentLocation = CLLocationCoordinate2D(latitude: 22.5401, longitude: 113.9345)
        await viewModel.refreshCurrentLocationIfNeeded()
        let initialCenter = try XCTUnwrap(viewModel.auxiliaryMapCenter)
        let initialMapPlace = try XCTUnwrap(viewModel.auxiliaryMapPlace)
        XCTAssertNotEqual(initialCenter.latitude, demoCenter.latitude, accuracy: 0.000001)
        XCTAssertEqual(initialMapPlace.latitude, initialPlace.latitude, accuracy: 0.000001)
        XCTAssertEqual(viewModel.resolvedStartPlace?.addressText, "深圳市南山区科技园")

        locationService.currentLocation = CLLocationCoordinate2D(latitude: 22.5402, longitude: 113.9345)
        await viewModel.refreshCurrentLocationIfNeeded()
        let smallMoveCenter = try XCTUnwrap(viewModel.auxiliaryMapCenter)
        let smallMoveMapPlace = try XCTUnwrap(viewModel.auxiliaryMapPlace)
        let smallMoveRequest = try XCTUnwrap(viewModel.makeCreateOrderRequest())

        XCTAssertEqual(smallMoveCenter.latitude, initialCenter.latitude, accuracy: 0.000001)
        XCTAssertEqual(smallMoveCenter.longitude, initialCenter.longitude, accuracy: 0.000001)
        XCTAssertEqual(smallMoveMapPlace.latitude, initialPlace.latitude, accuracy: 0.000001)
        XCTAssertEqual(smallMoveRequest.startLatitude, smallMovePlace.latitude, accuracy: 0.000001)
        XCTAssertEqual(smallMoveRequest.startAddress, "深圳市南山区科技园 A 口")

        locationService.currentLocation = CLLocationCoordinate2D(latitude: 22.5410, longitude: 113.9345)
        await viewModel.refreshCurrentLocationIfNeeded()
        let largeMoveCenter = try XCTUnwrap(viewModel.auxiliaryMapCenter)
        let largeMoveMapPlace = try XCTUnwrap(viewModel.auxiliaryMapPlace)

        XCTAssertEqual(largeMoveCenter.latitude, initialCenter.latitude, accuracy: 0.000001)
        XCTAssertEqual(largeMoveCenter.longitude, initialCenter.longitude, accuracy: 0.000001)
        XCTAssertEqual(largeMoveMapPlace.latitude, largeMovePlace.latitude, accuracy: 0.000001)
        XCTAssertEqual(viewModel.resolvedStartPlace?.addressText, "深圳市南山区科技园 B 口")

        let selectedPlace = ResolvedPlace(
            id: "poi-2",
            title: "大观楼",
            addressText: "大观楼",
            latitude: 25.024196,
            longitude: 102.673887,
            source: .manual
        )
        viewModel.selectPlace(selectedPlace)
        let selectedCenter = try XCTUnwrap(viewModel.auxiliaryMapCenter)
        let selectedMapPlace = try XCTUnwrap(viewModel.auxiliaryMapPlace)
        let selectedRequest = try XCTUnwrap(viewModel.makeCreateOrderRequest())

        XCTAssertEqual(selectedCenter.latitude, selectedPlace.latitude, accuracy: 0.000001)
        XCTAssertEqual(selectedCenter.longitude, selectedPlace.longitude, accuracy: 0.000001)
        XCTAssertEqual(selectedMapPlace.latitude, selectedPlace.latitude, accuracy: 0.000001)
        XCTAssertEqual(selectedRequest.startLatitude, selectedPlace.latitude, accuracy: 0.000001)

        locationService.currentLocation = CLLocationCoordinate2D(latitude: 22.5500, longitude: 113.9400)
        await viewModel.refreshCurrentLocationIfNeeded()

        XCTAssertEqual(viewModel.resolvedStartPlace?.id, selectedPlace.id)
        XCTAssertEqual(viewModel.auxiliaryMapPlace?.id, selectedPlace.id)
    }

    func testBlindBookingDurationOptions() {
        XCTAssertEqual(BookingDurationOption.sixty.minutes, 60)
        XCTAssertNil(BookingDurationOption.none.minutes)
    }

    func testPacePreferenceDisplayNames() {
        XCTAssertEqual(PacePreference.walkRun.displayName, "走跑结合")
        XCTAssertEqual(PacePreference.easy.displayName, "轻松")
        XCTAssertEqual(PacePreference.moderate.displayName, "中等")
        XCTAssertEqual(PacePreference.fast.displayName, "快速")
        XCTAssertEqual(PacePreference.noPreference.displayName, "无偏好")
    }

    func testRoutePreferenceDisplayNames() {
        XCTAssertEqual(RoutePreference.parkTrail.displayName, "公园步道")
        XCTAssertEqual(RoutePreference.street.displayName, "街道")
        XCTAssertEqual(RoutePreference.track.displayName, "跑道")
        XCTAssertEqual(RoutePreference.noPreference.displayName, "无偏好")
    }

    func testAMapPOIMapsToResolvedPlaceForBookingSearch() throws {
        let poi = AMapPOI()
        poi.uid = "poi-001"
        poi.name = "科技园地铁站"
        poi.district = "南山区"
        poi.address = "A口"
        poi.location = AMapGeoPoint.location(withLatitude: 22.5401, longitude: 113.9345)

        let place = try XCTUnwrap(AMapGeocodingService.resolvedPlace(from: poi))

        XCTAssertEqual(place.id, "poi-001")
        XCTAssertEqual(place.title, "科技园地铁站")
        XCTAssertEqual(place.addressText, "科技园地铁站，南山区 A口")
        XCTAssertEqual(place.latitude, 22.5401, accuracy: 0.000001)
        XCTAssertEqual(place.longitude, 113.9345, accuracy: 0.000001)
        XCTAssertEqual(place.source, .manual)
    }

    func testSpeechInputStopReasonAnnouncements() {
        XCTAssertEqual(SpeechInputStopReason.manual.announcement, "语音输入已关闭。")
        XCTAssertEqual(
            SpeechInputStopReason.silenceTimeout(hadDetectedSound: false).announcement,
            "未检测到声音，已停止语音输入。"
        )
        XCTAssertEqual(
            SpeechInputStopReason.silenceTimeout(hadDetectedSound: true).announcement,
            "语音输入已停止。"
        )
        XCTAssertEqual(SpeechInputStopReason.maxDuration.announcement, "语音输入已达到最长时间，已停止。")
    }

    func testVoiceServiceExposesRequestedAPIAndCompatibilityAlias() {
        let service = VoiceService()
        let legacyService: SpeechService = service

        service.speak(text: " 当前状态 ")
        XCTAssertEqual(service.lastSpokenText, "当前状态")
        XCTAssertEqual(service.latestRepeatableText, "当前状态")
        XCTAssertEqual(service.lastVoiceOverAnnouncement, "当前状态")

        legacyService.repeatCurrentStatus()
        XCTAssertEqual(service.lastSpokenText, "当前状态")

        service.stop()
        XCTAssertFalse(service.isSpeaking)
    }

    func testVoiceServiceCanPostVoiceOverOnlyAnnouncement() {
        let service = VoiceService()

        service.announce(" 已找到 2 个地点 ")

        XCTAssertNil(service.lastSpokenText)
        XCTAssertEqual(service.lastVoiceOverAnnouncement, "已找到 2 个地点")
    }

    func testVoiceServiceStatusAnnouncementsMatchAccessibilityGuidelinesAndDeduplicate() {
        let service = VoiceService()

        XCTAssertEqual(
            VoiceService.statusAnnouncement(for: .pendingMatch),
            "订单提交成功，系统正在为你派单。"
        )
        XCTAssertEqual(
            VoiceService.statusAnnouncement(for: .driverArrived),
            "志愿者已到达，请等待志愿者开始服务。"
        )
        XCTAssertEqual(
            VoiceService.statusAnnouncement(for: .pendingAccept),
            "志愿者已接单，请前往或等待在预约出发地点。"
        )
        XCTAssertEqual(
            VoiceService.statusAnnouncement(for: .driverEnRoute),
            "志愿者已出发，正在前往出发地点。"
        )
        XCTAssertEqual(
            VoiceService.statusAnnouncement(for: .completed),
            "服务已完成，感谢使用助盲跑。"
        )

        XCTAssertTrue(service.speakStatusChange(.pendingMatch))
        XCTAssertFalse(service.speakStatusChange(.pendingMatch))
        XCTAssertTrue(service.speakStatusChange(.pendingAccept))
        XCTAssertEqual(service.lastSpokenStatus, .pendingAccept)

        service.stop()
    }

    func testSpeechInputFieldsAreTextOnlyAllowlist() {
        XCTAssertTrue(SpeechInputField.isAllowlisted(SpeechInputField.startPlaceSearch.rawValue))
        XCTAssertTrue(SpeechInputField.isAllowlisted(SpeechInputField.startLocationDescription.rawValue))
        XCTAssertTrue(SpeechInputField.isAllowlisted(SpeechInputField.destinationRoute.rawValue))
        XCTAssertTrue(SpeechInputField.isAllowlisted(SpeechInputField.remark.rawValue))
        XCTAssertTrue(SpeechInputField.isAllowlisted(SpeechInputField.ratingFeedback.rawValue))
        XCTAssertTrue(SpeechInputField.isAllowlisted(SpeechInputField.volunteerServiceSummary.rawValue))

        XCTAssertFalse(SpeechInputField.isAllowlisted("appointmentTime"))
        XCTAssertFalse(SpeechInputField.isAllowlisted("estimatedDistance"))
        XCTAssertFalse(SpeechInputField.isAllowlisted("pacePreference"))
    }

    func testSpeechInputRejectsNonAllowlistedFieldAndKeepsKeyboardFallback() {
        let service = SpeechInputService()

        service.startRecognitionForTesting(fieldId: "appointmentTime")

        XCTAssertFalse(service.isListening)
        XCTAssertNil(service.activeFieldId)
        XCTAssertEqual(service.lastStopReason, .error)
        XCTAssertEqual(service.errorMessage, SpeechInputService.keyboardFallbackErrorMessage)
    }

    func testSpeechInputFailureShowsKeyboardFallbackError() {
        let service = SpeechInputService()

        service.simulateRecognitionFailureForTesting(field: .remark)

        XCTAssertFalse(service.isListening)
        XCTAssertNil(service.activeFieldId)
        XCTAssertEqual(service.lastStopReason, .error)
        XCTAssertEqual(service.errorMessage, SpeechInputService.keyboardFallbackErrorMessage)
    }

    func testSpeechInputStopRecognitionClearsActiveField() {
        let service = SpeechInputService()

        service.startRecognitionForTesting(fieldId: "remark")
        XCTAssertTrue(service.isListening(for: .remark))

        service.stopRecognition()

        XCTAssertFalse(service.isListening)
        XCTAssertNil(service.activeFieldId)
        XCTAssertEqual(service.lastStopReason, .manual)
    }

    func testSpeechInputRestoresPlaybackBeforeCompletionForEveryStopReason() {
        let reasons: [SpeechInputStopReason] = [
            .manual,
            .finalResult,
            .silenceTimeout(hadDetectedSound: false),
            .silenceTimeout(hadDetectedSound: true),
            .maxDuration,
            .error
        ]

        for reason in reasons {
            let audioSession = MockSpeechAudioSession()
            let service = SpeechInputService(audioSession: audioSession)
            var completionOperations: [String] = []
            service.startRecognitionForTesting(field: .startPlaceSearch) { _ in
                completionOperations = audioSession.operations + ["completion"]
            }

            service.finishRecognitionForTesting(text: "大观楼", reason: reason)

            XCTAssertEqual(
                completionOperations,
                ["deactivateRecording", "configurePlayback", "activatePlayback", "completion"],
                "Unexpected audio restoration order for \(reason)"
            )
        }
    }

    func testSpeechInputLifecycleStopRestoresPlaybackWithoutCompleting() {
        let audioSession = MockSpeechAudioSession()
        let service = SpeechInputService(audioSession: audioSession)
        var didComplete = false
        service.startRecognitionForTesting(field: .remark) { _ in didComplete = true }

        service.cancelRecognitionForLifecycle()

        XCTAssertEqual(audioSession.operations, ["deactivateRecording", "configurePlayback", "activatePlayback"])
        XCTAssertFalse(didComplete)
    }

    func testSpeechInputRepeatedStopDoesNotRepeatAudioSessionCleanup() {
        let audioSession = MockSpeechAudioSession()
        let service = SpeechInputService(audioSession: audioSession)
        service.startRecognitionForTesting(field: .remark)

        service.stopRecognition()
        service.stopRecognition()

        XCTAssertEqual(audioSession.operations, ["deactivateRecording", "configurePlayback", "activatePlayback"])
    }

    func testSpeechInputPlaybackRecoveryFailureKeepsCompletionAndDiagnostics() {
        let failurePoints: [MockSpeechAudioSession.FailurePoint] = [
            .deactivate,
            .playbackCategory,
            .playbackActivation
        ]

        for failurePoint in failurePoints {
            let audioSession = MockSpeechAudioSession()
            audioSession.failurePoint = failurePoint
            let service = SpeechInputService(audioSession: audioSession)
            var completion: SpeechInputCompletion?
            service.startRecognitionForTesting(field: .startPlaceSearch) { completion = $0 }

            service.finishRecognitionForTesting(text: "大观楼")

            XCTAssertEqual(completion?.recognizedText, "大观楼")
            XCTAssertEqual(audioSession.operations, ["deactivateRecording", "configurePlayback", "activatePlayback"])
            XCTAssertNotNil(service.audioSessionDiagnosticMessage)
            XCTAssertNil(service.errorMessage)
        }
    }

    func testSpeechInputStartupFailureRestoresPlaybackBeforeErrorAnnouncement() {
        let audioSession = MockSpeechAudioSession()
        let service = SpeechInputService(audioSession: audioSession)
        var observedOperations: [String] = []
        service.startRecognitionForTesting(field: .remark, onAnnouncement: { message in
            observedOperations = audioSession.operations + ["announce:\(message)"]
        })

        service.failRecognitionStartupForTesting("语音输入启动失败，请使用键盘输入。")

        XCTAssertEqual(
            observedOperations,
            [
                "deactivateRecording",
                "configurePlayback",
                "activatePlayback",
                "announce:语音输入启动失败，请使用键盘输入。"
            ]
        )
        XCTAssertEqual(service.lastStopReason, .error)
    }

    func testSpeechInputLifecycleCancelClearsStateWithoutCompletion() {
        let service = SpeechInputService()
        var completion: SpeechInputCompletion?

        service.startRecognitionForTesting(field: .startPlaceSearch) {
            completion = $0
        }
        service.cancelRecognitionForLifecycle()

        XCTAssertFalse(service.isListening)
        XCTAssertNil(service.activeFieldId)
        XCTAssertEqual(service.lastStopReason, .manual)
        XCTAssertNil(completion)

        service.startRecognitionForTesting(field: .startPlaceSearch) {
            completion = $0
        }
        service.finishRecognitionForTesting(text: "大观楼")

        XCTAssertEqual(completion?.field, .startPlaceSearch)
        XCTAssertEqual(completion?.recognizedText, "大观楼")
        XCTAssertEqual(completion?.reason, .finalResult)
    }

    func testSpeechInputLifecycleCancelInvalidatesPendingAuthorizationSession() {
        let service = SpeechInputService()
        var completion: SpeechInputCompletion?

        let staleSession = service.startPendingAuthorizationForTesting(field: .startPlaceSearch) {
            completion = $0
        }
        service.cancelRecognitionForLifecycle()
        service.simulateAuthorizationCompletionForTesting(sessionID: staleSession, field: .startPlaceSearch)

        XCTAssertFalse(service.isListening)
        XCTAssertNil(service.activeFieldId)
        XCTAssertEqual(service.lastStopReason, .manual)
        XCTAssertNil(completion)

        service.startRecognitionForTesting(field: .startPlaceSearch) {
            completion = $0
        }
        service.finishRecognitionForTesting(text: "大观楼")

        XCTAssertEqual(completion?.field, .startPlaceSearch)
        XCTAssertEqual(completion?.recognizedText, "大观楼")
        XCTAssertEqual(completion?.reason, .finalResult)
    }

    func testSpeechInputPendingAuthorizationOwnsRecognitionSessionBeforeListening() {
        let service = SpeechInputService()

        service.startPendingAuthorizationForTesting(field: .startPlaceSearch)

        XCTAssertFalse(service.isListening(for: .startPlaceSearch))
        XCTAssertTrue(service.hasRecognitionSession(for: .startPlaceSearch))
        XCTAssertFalse(service.hasRecognitionSession(for: .remark))

        service.cancelRecognitionForLifecycle()

        XCTAssertFalse(service.hasRecognitionSession(for: .startPlaceSearch))
    }

    func testSpeechInputCompletionIncludesFieldTextAndStopReason() {
        let service = SpeechInputService()
        var completion: SpeechInputCompletion?

        service.startRecognitionForTesting(field: .startPlaceSearch) {
            completion = $0
        }
        service.finishRecognitionForTesting(
            text: "大观",
            reason: .silenceTimeout(hadDetectedSound: true)
        )

        XCTAssertFalse(service.isListening)
        XCTAssertNil(service.activeFieldId)
        XCTAssertEqual(completion?.field, .startPlaceSearch)
        XCTAssertEqual(completion?.recognizedText, "大观")
        XCTAssertEqual(completion?.reason, .silenceTimeout(hadDetectedSound: true))
        XCTAssertTrue(completion?.reason.shouldTriggerSearchWithRecognizedText == true)
    }

    func testSpeechInputSwitchingFieldsCompletesPreviousFieldBeforeReplacingHandler() {
        let service = SpeechInputService()
        var startPlaceCompletion: SpeechInputCompletion?
        var notesCompletion: SpeechInputCompletion?

        service.startRecognitionForTesting(field: .startPlaceSearch) {
            startPlaceCompletion = $0
        }
        service.finishRecognitionForTesting(
            text: "大观",
            reason: .silenceTimeout(hadDetectedSound: true)
        )
        service.startRecognitionForTesting(field: .startPlaceSearch) {
            startPlaceCompletion = $0
        }
        service.startRecognitionForTesting(field: .startLocationDescription) {
            notesCompletion = $0
        }

        XCTAssertEqual(startPlaceCompletion?.field, .startPlaceSearch)
        XCTAssertEqual(startPlaceCompletion?.recognizedText, "")
        XCTAssertEqual(startPlaceCompletion?.reason, .manual)
        XCTAssertNil(notesCompletion)
        XCTAssertTrue(service.isListening(for: .startLocationDescription))
    }

    func testSpeechInputSilenceTimeoutClearsActiveField() {
        let service = SpeechInputService()

        service.startRecognitionForTesting(field: .startLocationDescription)
        service.triggerSilenceTimeoutForTesting(hadDetectedSound: false)

        XCTAssertFalse(service.isListening)
        XCTAssertNil(service.activeFieldId)
        XCTAssertEqual(service.lastStopReason, .silenceTimeout(hadDetectedSound: false))
    }

    func testEmergencyButtonStatusGate() {
        // Current release hides the emergency affordance until the real safety flow is approved.
        XCTAssertFalse(RunOrderStatus.pendingMatch.canTriggerEmergency)
        XCTAssertFalse(RunOrderStatus.pendingAccept.canTriggerEmergency)
        XCTAssertFalse(RunOrderStatus.driverEnRoute.canTriggerEmergency)
        XCTAssertFalse(RunOrderStatus.driverArrived.canTriggerEmergency)
        XCTAssertFalse(RunOrderStatus.inProgress.canTriggerEmergency)
        XCTAssertFalse(RunOrderStatus.completed.canTriggerEmergency)
        XCTAssertFalse(RunOrderStatus.cancelled.canTriggerEmergency)
        XCTAssertFalse(RunOrderStatus.rematching.canTriggerEmergency)
        XCTAssertFalse(RunOrderStatus.noVolunteer.canTriggerEmergency)
        XCTAssertFalse(RunOrderStatus.inProgress.showsEmergencyPlaceholder)
        XCTAssertFalse(RunOrderStatus.driverEnRoute.showsEmergencyPlaceholder)
        XCTAssertFalse(RunOrderStatus.driverArrived.showsEmergencyPlaceholder)
        XCTAssertFalse(RunOrderStatus.completed.showsEmergencyPlaceholder)
    }

    func testEmergencyConfirmationCopyIsFixed() {
        XCTAssertEqual(
            EmergencySafetyCopy.confirmationMessage,
            "是否确认进入求助状态？确认后，本次服务将标记为异常，系统会记录当前订单状态。"
        )
    }

    func testBlindOrderPollingUsesFiveSecondsAndStopsOnTerminalStates() {
        XCTAssertEqual(AppConstants.Timing.orderPollingInterval, 5.0)
        XCTAssertTrue(RunOrderStatus.pendingMatch.shouldPoll)
        XCTAssertTrue(RunOrderStatus.pendingAccept.shouldPoll)
        XCTAssertTrue(RunOrderStatus.driverEnRoute.shouldPoll)
        XCTAssertTrue(RunOrderStatus.driverArrived.shouldPoll)
        XCTAssertTrue(RunOrderStatus.inProgress.shouldPoll)
        XCTAssertTrue(RunOrderStatus.rematching.shouldPoll)
        XCTAssertFalse(RunOrderStatus.completed.shouldPoll)
        XCTAssertFalse(RunOrderStatus.cancelled.shouldPoll)
        XCTAssertFalse(RunOrderStatus.noVolunteer.shouldPoll)
    }

    func testRematchingCopyKeepsBlindRunnerInStableWaitingState() {
        XCTAssertEqual(
            RunOrderStatus.rematching.blindRunnerDescription,
            "正在确认志愿者状态，请稍候；如需更换志愿者，系统会继续处理。"
        )
        XCTAssertEqual(RunOrderStatus.rematching.blindRunnerAnnouncement, "正在确认志愿者状态，请稍候。")
        XCTAssertEqual(VoiceService.statusAnnouncement(for: .rematching), "正在确认志愿者状态，请稍候。")
    }

    func testOrderStatusTerminalStates() {
        XCTAssertTrue(RunOrderStatus.completed.isTerminal)
        XCTAssertTrue(RunOrderStatus.cancelled.isTerminal)
        XCTAssertTrue(RunOrderStatus.noVolunteer.isTerminal)
        XCTAssertFalse(RunOrderStatus.pendingMatch.isTerminal)
        XCTAssertFalse(RunOrderStatus.inProgress.isTerminal)
    }

    func testOrderStatusCancelability() {
        XCTAssertEqual(RunOrderStatus.pendingAccept.displayName, "待出发")

        XCTAssertTrue(RunOrderStatus.pendingMatch.canCancel)
        XCTAssertTrue(RunOrderStatus.pendingAccept.canCancel)
        XCTAssertTrue(RunOrderStatus.rematching.canCancel)
        XCTAssertFalse(RunOrderStatus.inProgress.canCancel)
        XCTAssertFalse(RunOrderStatus.completed.canCancel)
        XCTAssertFalse(RunOrderStatus.cancelled.canCancel)

        XCTAssertTrue(RunOrderStatus.pendingMatch.canBlindRunnerCancel)
        XCTAssertTrue(RunOrderStatus.pendingAccept.canBlindRunnerCancel)
        XCTAssertTrue(RunOrderStatus.rematching.canBlindRunnerCancel)
        XCTAssertFalse(RunOrderStatus.driverEnRoute.canBlindRunnerCancel)
        XCTAssertFalse(RunOrderStatus.driverArrived.canBlindRunnerCancel)
        XCTAssertFalse(RunOrderStatus.inProgress.canBlindRunnerCancel)

        XCTAssertTrue(RunOrderStatus.pendingAccept.canVolunteerCancel)
        XCTAssertTrue(RunOrderStatus.driverEnRoute.canVolunteerCancel)
        XCTAssertTrue(RunOrderStatus.driverArrived.canVolunteerCancel)
        XCTAssertTrue(RunOrderStatus.inProgress.canVolunteerCancel)
        XCTAssertFalse(RunOrderStatus.pendingMatch.canVolunteerCancel)
        XCTAssertFalse(RunOrderStatus.rematching.canVolunteerCancel)
        XCTAssertFalse(RunOrderStatus.completed.canVolunteerCancel)
        XCTAssertFalse(RunOrderStatus.cancelled.canVolunteerCancel)
        XCTAssertFalse(RunOrderStatus.noVolunteer.canVolunteerCancel)

        XCTAssertTrue(RunOrderStatus.pendingAccept.canCancel(as: .blind))
        XCTAssertTrue(RunOrderStatus.pendingAccept.canCancel(as: .volunteer))
        XCTAssertTrue(RunOrderStatus.rematching.canCancel(as: .blind))
        XCTAssertFalse(RunOrderStatus.rematching.canCancel(as: .volunteer))
        XCTAssertFalse(RunOrderStatus.inProgress.canCancel(as: .blind))
        XCTAssertTrue(RunOrderStatus.inProgress.canCancel(as: .volunteer))
        XCTAssertFalse(RunOrderStatus.pendingAccept.canCancel(as: .unset))
    }

    func testMockCancelUsesRoleSpecificBackendContract() async throws {
        do {
            let appState = AppState()
            appState.currentEnvironment = .mock
            let client = appState.apiClient
            let _: EmptyResponse = try await client.post(
                "/api/orders/1/respond",
                body: OrderRespondRequest(action: .accept)
            )
            try await setMockRole(.blind, appState: appState)

            let _: EmptyResponse = try await client.post("/api/orders/1/cancel")
            let detail: OrderDetailResponse = try await client.get("/api/orders/1")

            XCTAssertEqual(detail.status, .cancelled)
        }

        do {
            let appState = AppState()
            appState.currentEnvironment = .mock
            let client = appState.apiClient
            let _: EmptyResponse = try await client.post(
                "/api/orders/1/respond",
                body: OrderRespondRequest(action: .accept)
            )
            try await setMockRole(.volunteer, appState: appState)

            let _: EmptyResponse = try await client.post("/api/orders/1/cancel")
            let rematchingDetail: OrderDetailResponse = try await client.get("/api/orders/1")
            XCTAssertEqual(rematchingDetail.status, .rematching)

            try await setMockRole(.blind, appState: appState)
            let _: EmptyResponse = try await client.post("/api/orders/1/cancel")
            let cancelledDetail: OrderDetailResponse = try await client.get("/api/orders/1")
            XCTAssertEqual(cancelledDetail.status, .cancelled)
        }
    }

    func testMockCancelUsesAppStateRoleWithoutRoleEndpoint() async throws {
        do {
            let appState = AppState()
            appState.currentEnvironment = .mock
            appState.activeRole = .blind
            let client = appState.apiClient

            let _: EmptyResponse = try await client.post("/api/orders/1/cancel")
            let detail: OrderDetailResponse = try await client.get("/api/orders/1")

            XCTAssertEqual(detail.status, .cancelled)
        }

        do {
            let appState = AppState()
            appState.currentEnvironment = .mock
            appState.activeRole = .volunteer
            let client = appState.apiClient
            let _: EmptyResponse = try await client.post(
                "/api/orders/1/respond",
                body: OrderRespondRequest(action: .accept)
            )

            let _: EmptyResponse = try await client.post("/api/orders/1/cancel")
            let detail: OrderDetailResponse = try await client.get("/api/orders/1")

            XCTAssertEqual(detail.status, .rematching)
        }
    }

    func testMockVolunteerCancelMovesActiveServiceStatesToRematching() async throws {
        for status in [RunOrderStatus.driverEnRoute, .driverArrived, .inProgress] {
            let appState = AppState()
            appState.currentEnvironment = .mock
            let client = appState.apiClient
            try await setMockRole(.volunteer, appState: appState)
            let _: EmptyResponse = try await client.post(
                "/api/orders/1/respond",
                body: OrderRespondRequest(action: .accept)
            )
            if [.driverEnRoute, .driverArrived, .inProgress].contains(status) {
                let _: EmptyResponse = try await client.post("/api/orders/1/en-route")
            }
            if [.driverArrived, .inProgress].contains(status) {
                let _: EmptyResponse = try await client.post("/api/orders/1/arrived")
            }
            if status == .inProgress {
                let _: EmptyResponse = try await client.post("/api/orders/1/start-service")
            }

            let beforeCancel: OrderDetailResponse = try await client.get("/api/orders/1")
            XCTAssertEqual(beforeCancel.status, status)

            let _: EmptyResponse = try await client.post("/api/orders/1/cancel")
            let afterCancel: OrderDetailResponse = try await client.get("/api/orders/1")
            XCTAssertEqual(afterCancel.status, .rematching)
        }
    }

    func testPendingAcceptBlindCopyUsesDepartureLanguageAndOrderDetails() {
        let order = makeOrder(orderId: 1, status: .pendingAccept)
        let announcement = order.blindRunnerAnnouncement()

        XCTAssertEqual(RunOrderStatus.pendingAccept.blindRunnerDescription, "志愿者已接单，请按预约时间前往或等待在出发地点。")
        XCTAssertTrue(announcement.contains("志愿者已接单"))
        XCTAssertTrue(announcement.contains("朝阳公园南门"))
        XCTAssertTrue(announcement.contains("志愿者出发后会继续通知你"))
        XCTAssertFalse(announcement.contains("待确认"))
    }

    func testDisplayDateTimeFormatsBackendLocalDateTimeForSpeech() {
        XCTAssertEqual("2026-07-05T15:18:10".displayDateTime, "2026年7月5日 15:18")
    }

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

    func testBlindOrderStatusViewModelTracksVolunteerDistanceToStart() {
        let viewModel = BlindOrderStatusViewModel()
        viewModel.order = makeOrder(orderId: 1, status: .driverEnRoute)

        viewModel.handleVolunteerLocationUpdate(WSVolunteerLocationUpdate(
            type: WSMessageType.volunteerLocationUpdate.rawValue,
            orderId: 1,
            lat: 39.9342,
            lng: 116.4740,
            timestamp: 1
        ))

        XCTAssertEqual(viewModel.volunteerDistanceToStartText, "距出发地点约 10 米")

        viewModel.handleVolunteerLocationUpdate(WSVolunteerLocationUpdate(
            type: WSMessageType.volunteerLocationUpdate.rawValue,
            orderId: 2,
            lat: 39.9042,
            lng: 116.4074,
            timestamp: 2
        ))

        XCTAssertEqual(viewModel.volunteerDistanceToStartText, "距出发地点约 10 米")
    }

    func testBlindOrderStatusSuppressesLifecycleAppNotificationSpeech() {
        XCTAssertTrue(BlindOrderStatusViewModel.shouldSuppressDirectNotificationSpeech("测试志愿者已到达，距您100米"))
        XCTAssertTrue(BlindOrderStatusViewModel.shouldSuppressDirectNotificationSpeech("志愿者已出发，距您100米"))
        XCTAssertTrue(BlindOrderStatusViewModel.shouldSuppressDirectNotificationSpeech("服务已开始"))
        XCTAssertTrue(BlindOrderStatusViewModel.shouldSuppressDirectNotificationSpeech("订单已完成"))
        XCTAssertTrue(BlindOrderStatusViewModel.shouldSuppressDirectNotificationSpeech("暂时没有可用志愿者，仍在等待"))
        XCTAssertTrue(BlindOrderStatusViewModel.shouldSuppressDirectNotificationSpeech("已为您匹配志愿者张三，他正在确认行程，请稍候"))
        XCTAssertFalse(BlindOrderStatusViewModel.shouldSuppressDirectNotificationSpeech("紧急联系人已通知"))
    }

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

        XCTAssertTrue(speechService.lastSpokenText?.contains("志愿者已接单") == true)
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
        XCTAssertEqual(
            RunOrderStatus.driverArrived.finishBlockedMessage,
            RunOrderStatus.driverArrived.arrivedWaitingCopy
        )
    }

    func testVolunteerAcceptGuardRequiresCompleteProfile() {
        XCTAssertEqual(
            VolunteerOrderActionGuard.acceptBlockMessage(profile: nil),
            "请先完善志愿者资料"
        )

        XCTAssertEqual(
            VolunteerOrderActionGuard.acceptBlockMessage(profile: makeVolunteerProfile(name: "")),
            "请先完善志愿者资料"
        )
    }

    func testVolunteerAcceptGuardRequiresApproval() {
        XCTAssertEqual(
            VolunteerOrderActionGuard.acceptBlockMessage(profile: makeVolunteerProfile()),
            "请先完成志愿者注册流程"
        )

        XCTAssertNil(
            VolunteerOrderActionGuard.acceptBlockMessage(profile: makeApprovedVolunteerProfile())
        )
    }

    func testVolunteerAcceptGuardUsesMainRegistrationStatusBeforeOptionalCertificate() {
        let completedStatus = VolunteerRegistrationStatus(
            currentStepCode: "STEP_4_COMPLETED",
            canAcceptOrders: true
        )

        XCTAssertNil(
            VolunteerOrderActionGuard.acceptBlockMessage(
                profile: makeVolunteerProfile(
                    verificationStatus: "rejected",
                    adminReviewStatus: "pending",
                    isAvailable: true
                ),
                registrationStatus: completedStatus
            )
        )
    }

    func testVolunteerAcceptGuardRequiresLegacyAdminReviewOnlyWithoutRegistrationStatus() {
        XCTAssertEqual(
            VolunteerOrderActionGuard.acceptBlockMessage(
                profile: makeVolunteerProfile(
                    verificationStatus: "approved",
                    adminReviewStatus: "pending",
                    isAvailable: true
                )
            ),
            "请等待管理员审核通过"
        )

        XCTAssertNil(
            VolunteerOrderActionGuard.acceptBlockMessage(
                profile: makeVolunteerProfile(
                    verificationStatus: "approved",
                    adminReviewStatus: nil,
                    isAvailable: true
                )
            )
        )
    }

    func testVolunteerAcceptGuardRequiresAvailability() {
        XCTAssertEqual(
            VolunteerOrderActionGuard.acceptBlockMessage(
                profile: makeApprovedVolunteerProfile(isAvailable: false),
                registrationStatus: VolunteerRegistrationStatus(currentStepCode: "STEP_4_COMPLETED", canAcceptOrders: true)
            ),
            "请先开启可服务状态"
        )
    }

    func testAppStateVolunteerComputedPropertiesRequireCompleteApprovedProfile() {
        let appState = AppState()
        appState.volunteerProfile = nil
        XCTAssertFalse(appState.isVolunteerProfileComplete)
        XCTAssertFalse(appState.isVolunteerProfileApproved)

        appState.volunteerProfile = makeVolunteerProfile(name: "")
        XCTAssertFalse(appState.isVolunteerProfileComplete)
        XCTAssertFalse(appState.isVolunteerProfileApproved)

        appState.volunteerProfile = makeVolunteerProfile()
        XCTAssertTrue(appState.isVolunteerProfileComplete)
        XCTAssertFalse(appState.isVolunteerProfileApproved)

        appState.volunteerProfile = makeApprovedVolunteerProfile()
        XCTAssertTrue(appState.isVolunteerProfileComplete)
        XCTAssertTrue(appState.isVolunteerProfileApproved)

        appState.volunteerProfile = makeVolunteerProfile(
            verificationStatus: "approved",
            adminReviewStatus: "pending",
            isAvailable: true
        )
        XCTAssertTrue(appState.isVolunteerProfileComplete)
        XCTAssertFalse(appState.isVolunteerProfileApproved)
    }

    func testVolunteerProfileDecodesAdminReviewStatus() throws {
        let data = #"{"name":"测试志愿者","verificationStatus":"approved","adminReviewStatus":"approved","wantsDispatch":true}"#
            .data(using: .utf8)!
        let profile = try JSONDecoder().decode(VolunteerProfileResponse.self, from: data)

        XCTAssertEqual(profile.adminReviewStatus, "approved")
        XCTAssertTrue(profile.isCertificationApproved)
        XCTAssertTrue(profile.isAdminReviewApprovedWhenAvailable)
        XCTAssertTrue(profile.hasManualDispatchOptIn)
    }

    func testVolunteerInServiceBlocksFinishBeforeInProgress() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = VolunteerInServiceViewModel()
        viewModel.configure(
            with: appState,
            speechService: speechService,
            initialOrder: makeOrder(orderId: 1, status: .driverArrived)
        )

        await viewModel.complete(summary: "")

        XCTAssertEqual(viewModel.errorMessage, RunOrderStatus.driverArrived.arrivedWaitingCopy)
        XCTAssertEqual(speechService.lastSpokenText, RunOrderStatus.driverArrived.arrivedWaitingCopy)
    }

    func testVolunteerInServiceStartsServiceFromDriverArrived() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let client = appState.apiClient
        try await setMockRole(.volunteer, appState: appState)
        let _: EmptyResponse = try await client.post(
            "/api/orders/1/respond",
            body: OrderRespondRequest(action: .accept)
        )
        let _: EmptyResponse = try await client.post("/api/orders/1/en-route")
        let _: EmptyResponse = try await client.post("/api/orders/1/arrived")
        let detail: OrderDetailResponse = try await client.get("/api/orders/1")

        let viewModel = VolunteerInServiceViewModel()
        viewModel.configure(with: appState, speechService: speechService, initialOrder: detail)

        await viewModel.startService()

        XCTAssertEqual(viewModel.order?.status, .inProgress)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testVolunteerInServiceBlocksStartServiceOutsideDriverArrived() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = VolunteerInServiceViewModel()
        viewModel.configure(
            with: appState,
            speechService: speechService,
            initialOrder: makeOrder(orderId: 1, status: .inProgress)
        )

        await viewModel.startService()

        XCTAssertEqual(viewModel.order?.status, .inProgress)
        XCTAssertEqual(viewModel.errorMessage, RunOrderStatus.inProgress.startServiceBlockedMessage)
        XCTAssertEqual(speechService.lastSpokenText, RunOrderStatus.inProgress.startServiceBlockedMessage)
    }

    func testVolunteerInServiceAllowsFinishFromInProgressAndRefreshesSummary() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let client = appState.apiClient
        try await setMockRole(.volunteer, appState: appState)
        let _: EmptyResponse = try await client.post(
            "/api/orders/1/respond",
            body: OrderRespondRequest(action: .accept)
        )
        let _: EmptyResponse = try await client.post("/api/orders/1/en-route")
        let _: EmptyResponse = try await client.post("/api/orders/1/arrived")
        let _: EmptyResponse = try await client.post("/api/orders/1/start-service")
        let detail: OrderDetailResponse = try await client.get("/api/orders/1")

        let viewModel = VolunteerInServiceViewModel()
        viewModel.configure(with: appState, speechService: speechService, initialOrder: detail)

        await viewModel.complete(summary: "已完成")

        XCTAssertEqual(viewModel.order?.status, .completed)
        XCTAssertEqual(viewModel.dispatchSummary?.completedCount, 2)
        XCTAssertEqual(viewModel.dispatchSummary?.resolvedPointsBalance, 200)
    }

    func testVolunteerInServiceCancelClearsLocalOrderWithoutDetailFetch() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let client = appState.apiClient
        try await setMockRole(.volunteer, appState: appState)
        let _: EmptyResponse = try await client.post(
            "/api/orders/1/respond",
            body: OrderRespondRequest(action: .accept)
        )
        let _: EmptyResponse = try await client.post("/api/orders/1/en-route")
        let _: EmptyResponse = try await client.post("/api/orders/1/arrived")
        let _: EmptyResponse = try await client.post("/api/orders/1/start-service")
        let detail: OrderDetailResponse = try await client.get("/api/orders/1")

        let viewModel = VolunteerInServiceViewModel()
        viewModel.configure(with: appState, speechService: speechService, initialOrder: detail)

        await viewModel.cancel()

        XCTAssertTrue(viewModel.didCancelOrder)
        XCTAssertNil(viewModel.order)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(speechService.lastSpokenText, "订单已取消，系统将为盲人重新匹配。")
    }

    func testVolunteerTravelStageUsesDepartureCopyBeforeArrival() {
        XCTAssertEqual(RunOrderStatus.pendingAccept.serviceStageTitle, "前往出发地点")
        XCTAssertEqual(RunOrderStatus.driverEnRoute.serviceStageTitle, "前往出发地点")
        XCTAssertEqual(RunOrderStatus.driverArrived.serviceStageTitle, "已到达集合地点")
        XCTAssertEqual(RunOrderStatus.inProgress.serviceStageTitle, "服务进行中")
        XCTAssertEqual(
            RunOrderStatus.pendingAccept.serviceStageSubtitle,
            "请确认当前位置和出发地点，可使用外部地图步行导航"
        )
    }

    func testVolunteerServiceActionKindsMatchFormalStateMachine() {
        XCTAssertEqual(
            VolunteerServiceActions.actionKinds(for: .pendingAccept).map(\.title),
            ["导航到出发地点", "我已出发", "取消订单"]
        )
        XCTAssertEqual(
            VolunteerServiceActions.actionKinds(for: .driverEnRoute).map(\.title),
            ["导航到出发地点", "我已到达约定地点", "取消订单"]
        )
        XCTAssertEqual(
            VolunteerServiceActions.actionKinds(for: .driverArrived).map(\.title),
            ["开始服务", "取消订单"]
        )
        XCTAssertEqual(
            VolunteerServiceActions.actionKinds(for: .inProgress).map(\.title),
            ["结束服务", "取消订单"]
        )
    }

    func testVolunteerServicePendingAcceptUsesDepartureCopy() {
        XCTAssertEqual(RunOrderStatus.pendingAccept.volunteerServiceDisplayName, "待出发")
        XCTAssertEqual(RunOrderStatus.driverEnRoute.volunteerServiceDisplayName, "志愿者出发中")
    }

    func testAMapWrappersHideCompassByDefault() {
        let coordinate = CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074)

        XCTAssertFalse(AMapContainer(centerCoordinate: coordinate).showsCompass)
        XCTAssertFalse(MapViewWrapper(centerCoordinate: coordinate).showsCompass)
    }

    func testVolunteerServiceMapAnchorUsesTopVisibleAreaAbovePanel() {
        let anchor = VolunteerServiceMapLayout.screenAnchorY(
            viewportHeight: 852,
            topSafeAreaInset: 47,
            bottomPanelMaxHeight: 852 * 0.62
        )

        XCTAssertLessThan(anchor, 0.3)
        XCTAssertGreaterThan(anchor, 0.18)
        XCTAssertEqual(anchor, 0.2170, accuracy: 0.001)
        XCTAssertEqual(
            VolunteerServiceMapLayout.screenAnchorY(
                viewportHeight: 100,
                topSafeAreaInset: 0,
                bottomPanelMaxHeight: 90
            ),
            0.18,
            accuracy: 0.0001
        )
    }

    func testVolunteerServiceMapPresentationUsesStartMarkerAsPrimaryMarker() {
        let current = CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074)
        let order = makeOrder(orderId: 1, status: .pendingAccept)

        let presentation = VolunteerServiceMapPresentation(
            order: order,
            currentLocation: current,
            locationAuthorized: true,
            fallbackCoordinate: current
        )

        XCTAssertEqual(presentation.annotations.count, 1)
        XCTAssertEqual(presentation.annotations[0].title, "出发地点")
        XCTAssertEqual(presentation.annotations[0].kind, .orderStart)
        XCTAssertTrue(presentation.isCurrentLocationAvailable)
        XCTAssertFalse(presentation.hasCurrentLocationMarker)
        XCTAssertEqual(presentation.centerCoordinate.latitude, 39.9342, accuracy: 0.000001)
        XCTAssertEqual(presentation.centerCoordinate.longitude, 116.4740, accuracy: 0.000001)
    }

    func testVolunteerServiceMapPresentationCanShowCurrentAndStartMarkers() {
        let current = CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074)
        let order = makeOrder(orderId: 1, status: .pendingAccept)

        let presentation = VolunteerServiceMapPresentation(
            order: order,
            currentLocation: current,
            locationAuthorized: true,
            fallbackCoordinate: current,
            includesCurrentLocationMarker: true,
            centersOnCurrentAndStart: true
        )

        XCTAssertEqual(presentation.annotations.count, 2)
        XCTAssertEqual(presentation.annotations[0].kind, .currentLocation)
        XCTAssertEqual(presentation.annotations[1].kind, .orderStart)
        XCTAssertTrue(presentation.hasCurrentLocationMarker)
        XCTAssertEqual(presentation.centerCoordinate.latitude, 39.9192, accuracy: 0.000001)
        XCTAssertEqual(presentation.centerCoordinate.longitude, 116.4407, accuracy: 0.000001)
    }

    func testVolunteerServiceMapPresentationCanPinCenterOnStartWithCurrentMarker() {
        let current = CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074)
        let order = makeOrder(orderId: 1, status: .pendingAccept)

        let presentation = VolunteerServiceMapPresentation(
            order: order,
            currentLocation: current,
            locationAuthorized: true,
            fallbackCoordinate: current,
            includesCurrentLocationMarker: true,
            centersOnCurrentAndStart: false
        )

        XCTAssertEqual(presentation.annotations.count, 2)
        XCTAssertEqual(presentation.annotations[0].kind, .currentLocation)
        XCTAssertEqual(presentation.annotations[1].kind, .orderStart)
        XCTAssertTrue(presentation.hasCurrentLocationMarker)
        XCTAssertEqual(presentation.centerCoordinate.latitude, 39.9342, accuracy: 0.000001)
        XCTAssertEqual(presentation.centerCoordinate.longitude, 116.4740, accuracy: 0.000001)
    }

    func testVolunteerServiceMapPresentationShowsOnlyCurrentLocationWhenOrderCoordinatesMissing() {
        let current = CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074)
        let order = makeOrder(
            orderId: 1,
            status: .pendingAccept,
            startLatitude: nil,
            startLongitude: nil
        )

        let presentation = VolunteerServiceMapPresentation(
            order: order,
            currentLocation: current,
            locationAuthorized: true,
            fallbackCoordinate: current,
            includesCurrentLocationMarker: true,
            centersOnCurrentAndStart: true
        )

        XCTAssertEqual(presentation.annotations.count, 1)
        XCTAssertEqual(presentation.annotations[0].kind, .currentLocation)
        XCTAssertFalse(presentation.annotations.contains { $0.kind == .orderStart })
        XCTAssertEqual(presentation.centerCoordinate.latitude, current.latitude, accuracy: 0.000001)
        XCTAssertEqual(presentation.centerCoordinate.longitude, current.longitude, accuracy: 0.000001)
    }

    func testVolunteerDispatchMapPresentationUsesSystemCurrentLocationLayerAndStartMarker() {
        let current = CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074)
        let order = makeDispatchOrder(orderId: 1)

        let presentation = VolunteerServiceMapPresentation(
            dispatchOrder: order,
            currentLocation: current,
            locationAuthorized: true,
            fallbackCoordinate: current
        )

        XCTAssertEqual(presentation.annotations.count, 1)
        XCTAssertEqual(presentation.annotations[0].title, "出发地点")
        XCTAssertEqual(presentation.annotations[0].kind, .orderStart)
        XCTAssertTrue(presentation.isCurrentLocationAvailable)
        XCTAssertFalse(presentation.hasCurrentLocationMarker)
        XCTAssertEqual(presentation.centerCoordinate.latitude, 39.9342, accuracy: 0.000001)
        XCTAssertEqual(presentation.centerCoordinate.longitude, 116.4740, accuracy: 0.000001)
    }

    func testVolunteerServiceMapPresentationFallsBackToStartMarkerWithoutLocation() {
        let fallback = CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074)
        let order = makeOrder(orderId: 1, status: .driverEnRoute)

        let presentation = VolunteerServiceMapPresentation(
            order: order,
            currentLocation: nil,
            locationAuthorized: false,
            fallbackCoordinate: fallback
        )

        XCTAssertEqual(presentation.annotations.count, 1)
        XCTAssertEqual(presentation.annotations[0].kind, .orderStart)
        XCTAssertFalse(presentation.isCurrentLocationAvailable)
        XCTAssertFalse(presentation.hasCurrentLocationMarker)
        XCTAssertEqual(presentation.centerCoordinate.latitude, 39.9342, accuracy: 0.000001)
        XCTAssertEqual(presentation.centerCoordinate.longitude, 116.4740, accuracy: 0.000001)
    }

    func testExternalMapNavigationAvailabilityFiltersThirdPartySchemes() {
        let providers = ExternalMapNavigationAvailability.availableProviders { url in
            url.scheme == "iosamap"
        }

        XCTAssertEqual(providers, [.amap, .appleMaps])
    }

    func testAMapWalkingURLIncludesOriginDestinationAndWalkingMode() throws {
        let request = makeNavigationRequest()

        let url = try XCTUnwrap(ExternalMapNavigationURLBuilder.amapWalkingURL(request: request))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = try XCTUnwrap(components.queryItems).reduce(into: [String: String]()) { result, item in
            result[item.name] = item.value
        }

        XCTAssertEqual(components.scheme, "iosamap")
        XCTAssertEqual(components.host, "path")
        XCTAssertEqual(query["slat"], "39.904200")
        XCTAssertEqual(query["slon"], "116.407400")
        XCTAssertEqual(query["sname"], "我的位置")
        XCTAssertEqual(query["dlat"], "39.934200")
        XCTAssertEqual(query["dlon"], "116.474000")
        XCTAssertEqual(query["dname"], "朝阳公园南门")
        XCTAssertEqual(query["t"], "2")
        XCTAssertEqual(query["dev"], "0")
    }

    func testBaiduWalkingURLIncludesGCJ02WalkingDirections() throws {
        let request = makeNavigationRequest()

        let url = try XCTUnwrap(ExternalMapNavigationURLBuilder.baiduWalkingURL(request: request))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = try XCTUnwrap(components.queryItems).reduce(into: [String: String]()) { result, item in
            result[item.name] = item.value
        }

        XCTAssertEqual(components.scheme, "baidumap")
        XCTAssertEqual(components.host, "map")
        XCTAssertEqual(components.path, "/direction")
        XCTAssertEqual(query["mode"], "walking")
        XCTAssertEqual(query["coord_type"], "gcj02")
        XCTAssertEqual(query["origin"], "latlng:39.904200,116.407400|name:我的位置")
        XCTAssertEqual(query["destination"], "latlng:39.934200,116.474000|name:朝阳公园南门")
    }

    func testBlindRunnerActiveOrderPollingIntervalStaysFiveSeconds() {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: SpeechService())
        viewModel.order = makeOrder(orderId: 1, status: .inProgress)

        XCTAssertEqual(viewModel.effectivePollingInterval, AppConstants.Timing.orderPollingInterval)
    }

    func testBlindRunnerCompletedOrderSubmitsReviewRequest() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.order = makeOrder(orderId: 2, status: .completed)
        viewModel.reviewRating = 5
        viewModel.reviewComment = "体验很好"

        await viewModel.submitReview()

        XCTAssertTrue(viewModel.didSubmitReview)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(speechService.lastSpokenText, "评价已提交，感谢反馈。")
    }

    func testBlindRunnerRepeatStatusSpeaksInServiceState() {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.order = makeOrder(orderId: 1, status: .inProgress)

        viewModel.repeatStatus()

        XCTAssertEqual(speechService.lastSpokenText, RunOrderStatus.inProgress.blindRunnerAnnouncement)
    }

    // MARK: - Helpers

    private func makeDispatchOrder(orderId: Int64) -> WSNewOrder {
        WSNewOrder(
            type: "NEW_ORDER",
            timestamp: "2026-06-25T19:30:00",
            orderId: orderId,
            startAddress: "朝阳公园南门",
            startLatitude: 39.9342,
            startLongitude: 116.4740,
            distanceKm: 0.1,
            plannedStart: "2026-06-25T20:00:00",
            plannedEnd: "2026-06-25T21:00:00",
            dispatchTimeoutSeconds: 30,
            priority: "HIGH",
            pacePreference: "MODERATE",
            hasGuideDog: false,
            specialNotes: nil
        )
    }

    private func makeOrder(
        orderId: Int64,
        status: RunOrderStatus,
        createdAt: String = "2026-06-25T10:00:00Z",
        startLatitude: Double? = 39.9342,
        startLongitude: Double? = 116.4740
    ) -> OrderDetailResponse {
        OrderDetailResponse(
            orderId: orderId,
            status: status,
            startAddress: "朝阳公园南门",
            startLatitude: startLatitude,
            startLongitude: startLongitude,
            plannedStart: "2026-06-25T20:00:00Z",
            plannedEnd: "2026-06-25T21:00:00Z",
            blindName: "李明",
            blindPhone: status == .pendingMatch ? nil : "13800001001",
            volunteerPhone: status == .pendingMatch ? nil : "13800000002",
            acceptedAt: status == .pendingMatch ? nil : "2026-06-25T19:50:00Z",
            createdAt: createdAt,
            expectedDurationMinutes: 60,
            pacePreference: .moderate,
            routePreference: .parkTrail,
            routeNotes: nil,
            hasGuideDogThisRun: false,
            specialNotes: nil,
            visionLevel: "TOTAL_BLIND",
            tetherPreference: "TETHER_ROPE",
            chatPreference: "PREFER_CHAT"
        )
    }

    private func makeNavigationRequest() -> ExternalMapNavigationRequest {
        ExternalMapNavigationRequest(
            originCoordinate: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074),
            originName: "我的位置",
            destinationCoordinate: CLLocationCoordinate2D(latitude: 39.9342, longitude: 116.4740),
            destinationName: "朝阳公园南门"
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }

    private func setMockRole(_ role: UserRole, appState: AppState) async throws {
        appState.switchRole(to: role)
        let _: SetRoleResponse = try await appState.apiClient.post(
            "/api/user/role",
            body: SetRoleRequest(role: role)
        )
    }

    private final class FailingAPIClient: APIClientProtocol, @unchecked Sendable {
        private let error: Error

        init(error: Error) {
            self.error = error
        }

        func request<T: Decodable>(
            method: HTTPMethod,
            path: String,
            query: [String: String]?,
            body: (any Encodable & Sendable)?,
            requiresAuth: Bool
        ) async throws -> T {
            throw error
        }

        func upload<T: Decodable>(
            path: String,
            query: [String: String]?,
            fields: [String: String]?,
            files: [MultipartFile],
            requiresAuth: Bool
        ) async throws -> T {
            throw error
        }
    }

    private final class LoginCodeCaptureAPIClient: APIClientProtocol, @unchecked Sendable {
        private let sendCodeResponse: SendCodeResponse
        private(set) var capturedVerifyCodeRequest: VerifyCodeRequest?

        init(sendCodeResponse: SendCodeResponse) {
            self.sendCodeResponse = sendCodeResponse
        }

        func request<T: Decodable>(
            method: HTTPMethod,
            path: String,
            query: [String: String]?,
            body: (any Encodable & Sendable)?,
            requiresAuth: Bool
        ) async throws -> T {
            if method == .post, path == "/api/auth/send-code" {
                guard let response = sendCodeResponse as? T else {
                    throw APIError.decodingError(NSError(domain: "LoginCodeCaptureAPIClient", code: 1))
                }
                return response
            }

            if method == .post, path == "/api/auth/verify-code" {
                guard let request = decodeBody(VerifyCodeRequest.self, from: body) else {
                    throw APIError.decodingError(NSError(domain: "LoginCodeCaptureAPIClient", code: 2))
                }
                capturedVerifyCodeRequest = request
                guard let response = LoginResponse(token: "test-token", userId: 1, role: nil) as? T else {
                    throw APIError.decodingError(NSError(domain: "LoginCodeCaptureAPIClient", code: 3))
                }
                return response
            }

            throw APIError.invalidURL
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

        private func decodeBody<T: Decodable>(_ type: T.Type, from body: (any Encodable & Sendable)?) -> T? {
            body as? T
        }
    }

    private final class BasicInfoFailingAPIClient: APIClientProtocol, @unchecked Sendable {
        private let error: APIError

        init(error: APIError) {
            self.error = error
        }

        func request<T: Decodable>(
            method: HTTPMethod,
            path: String,
            query: [String: String]?,
            body: (any Encodable & Sendable)?,
            requiresAuth: Bool
        ) async throws -> T {
            if method == .post, path == "/api/volunteer/registration/step1" {
                throw error
            }
            throw APIError.invalidURL
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

    private final class BasicInfoStatusAPIClient: APIClientProtocol, @unchecked Sendable {
        private let status: VolunteerRegistrationStatus
        private(set) var submitCount = 0
        private(set) var statusRefreshCount = 0
        private(set) var capturedRequest: BasicInfoRequest?

        init(status: VolunteerRegistrationStatus) {
            self.status = status
        }

        func request<T: Decodable>(
            method: HTTPMethod,
            path: String,
            query: [String: String]?,
            body: (any Encodable & Sendable)?,
            requiresAuth: Bool
        ) async throws -> T {
            if method == .post, path == "/api/volunteer/registration/step1" {
                submitCount += 1
                guard let request = body as? BasicInfoRequest else {
                    throw APIError.invalidURL
                }
                capturedRequest = request
                guard let response = EmptyResponse() as? T else {
                    throw APIError.invalidURL
                }
                return response
            }
            if method == .get, path == "/api/volunteer/registration/status" {
                statusRefreshCount += 1
                guard let response = status as? T else {
                    throw APIError.invalidURL
                }
                return response
            }
            throw APIError.invalidURL
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

    private func failureKind(for outcome: CloudAuthVerificationOutcome) -> CloudAuthVerificationFailure.Kind? {
        guard case .failed(let failure) = outcome else { return nil }
        return failure.kind
    }

    private final class CloudAuthVerifierSpy: CloudAuthVerifying, @unchecked Sendable {
        private let outcome: CloudAuthVerificationOutcome
        private(set) var receivedCertifyIds: [String] = []
        private(set) var receivedEnvironments: [APIEnvironment] = []

        init(outcome: CloudAuthVerificationOutcome) {
            self.outcome = outcome
        }

        func verify(certifyId: String, environment: APIEnvironment) async -> CloudAuthVerificationOutcome {
            receivedCertifyIds.append(certifyId)
            receivedEnvironments.append(environment)
            return outcome
        }
    }

    private final class FaceVerifyFlowAPIClient: APIClientProtocol, @unchecked Sendable {
        private let initResponse: FaceVerifyInitResponse
        private let initError: APIError?
        private var resultResponses: [FaceVerifyResponse]
        private let status: VolunteerRegistrationStatus
        private(set) var capturedMetaInfo: String?
        private(set) var initCount = 0
        private(set) var resultCount = 0
        private(set) var statusRefreshCount = 0
        private(set) var trainingCoursesCount = 0

        init(
            initResponse: FaceVerifyInitResponse,
            initError: APIError? = nil,
            resultResponses: [FaceVerifyResponse],
            status: VolunteerRegistrationStatus = VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true)
        ) {
            self.initResponse = initResponse
            self.initError = initError
            self.resultResponses = resultResponses
            self.status = status
        }

        func request<T: Decodable>(
            method: HTTPMethod,
            path: String,
            query: [String: String]?,
            body: (any Encodable & Sendable)?,
            requiresAuth: Bool
        ) async throws -> T {
            if method == .post, path == "/api/volunteer/registration/step3/face-verify/init" {
                initCount += 1
                if let initError {
                    throw initError
                }
                guard let request = body as? FaceVerifyInitRequest,
                      let response = initResponse as? T else {
                    throw APIError.invalidURL
                }
                capturedMetaInfo = request.metaInfo
                return response
            }
            if method == .post, path == "/api/volunteer/registration/step3/face-verify/result" {
                resultCount += 1
                guard let response = (resultResponses.isEmpty ? FaceVerifyResponse(passed: false, status: "PENDING", message: nil) : resultResponses.removeFirst()) as? T else {
                    throw APIError.invalidURL
                }
                return response
            }
            if method == .get, path == "/api/volunteer/registration/training/courses" {
                trainingCoursesCount += 1
                guard let response = [TrainingCourseResponse]() as? T else {
                    throw APIError.invalidURL
                }
                return response
            }
            if method == .get, path == "/api/volunteer/registration/status" {
                statusRefreshCount += 1
                guard let response = status as? T else {
                    throw APIError.invalidURL
                }
                return response
            }
            throw APIError.invalidURL
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
    private final class FakePlaceSearchProvider: PlaceSearchProviding {
        var lastErrorMessage: String?
        var searchKeywords: [String] = []
        private let results: [ResolvedPlace]
        private var reverseGeocodeResults: [ResolvedPlace]

        init(
            results: [ResolvedPlace],
            lastErrorMessage: String? = nil,
            reverseGeocodeResults: [ResolvedPlace] = []
        ) {
            self.results = results
            self.lastErrorMessage = lastErrorMessage
            self.reverseGeocodeResults = reverseGeocodeResults
        }

        func reverseGeocode(coordinate: CLLocationCoordinate2D) async -> ResolvedPlace? {
            guard !reverseGeocodeResults.isEmpty else { return nil }
            return reverseGeocodeResults.removeFirst()
        }

        func searchPlaces(keyword: String, near coordinate: CLLocationCoordinate2D?) async -> [ResolvedPlace] {
            searchKeywords.append(keyword)
            return results
        }
    }

    private func makeVolunteerProfile(
        name: String = "测试志愿者",
        verificationStatus: String = "not_submitted",
        adminReviewStatus: String? = nil,
        isAvailable: Bool = false
    ) -> VolunteerProfileResponse {
        VolunteerProfileResponse(
            name: name,
            verificationStatus: verificationStatus,
            adminReviewStatus: adminReviewStatus,
            isAvailable: isAvailable,
            availableTimeSlots: nil,
            acceptsGuideDog: nil,
            paceRange: nil
        )
    }

    private func makeApprovedVolunteerProfile(isAvailable: Bool = true) -> VolunteerProfileResponse {
        makeVolunteerProfile(
            verificationStatus: "approved",
            isAvailable: isAvailable
        )
    }
}
