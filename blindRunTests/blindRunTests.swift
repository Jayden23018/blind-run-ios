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
final class blindRunTests: XCTestCase {

    func testSendCodeRequestUsesOpenAPICamelCaseKeys() throws {
        let request = SendCodeRequest(phone: "13800138000")
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(json["phone"], "13800138000")
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

    func testVolunteerRegistrationUploadPathsUseCloudContract() async throws {
        let client = MockAPIClient()
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xD9])

        let _: EmptyResponse = try await client.upload(
            "/api/volunteer/registration/step2/id-card",
            query: [
                "idCardName": "测试志愿者",
                "idCardNumber": "110101199001011234"
            ],
            files: [
                MultipartFile(fieldName: "frontFile", fileName: "front.jpg", mimeType: "image/jpeg", data: imageData),
                MultipartFile(fieldName: "backFile", fileName: "back.jpg", mimeType: "image/jpeg", data: imageData)
            ]
        )

        let _: EmptyResponse = try await client.upload(
            "/api/volunteer/registration/step3/face-verify",
            files: [
                MultipartFile(fieldName: "facePhoto", fileName: "face.jpg", mimeType: "image/jpeg", data: imageData)
            ]
        )
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
        // Emergency affordance is visible only as a placeholder during active service stages.
        XCTAssertFalse(RunOrderStatus.pendingMatch.canTriggerEmergency)
        XCTAssertFalse(RunOrderStatus.pendingAccept.canTriggerEmergency)
        XCTAssertTrue(RunOrderStatus.driverEnRoute.canTriggerEmergency)
        XCTAssertTrue(RunOrderStatus.driverArrived.canTriggerEmergency)
        XCTAssertTrue(RunOrderStatus.inProgress.canTriggerEmergency)
        XCTAssertFalse(RunOrderStatus.completed.canTriggerEmergency)
        XCTAssertFalse(RunOrderStatus.cancelled.canTriggerEmergency)
        XCTAssertFalse(RunOrderStatus.rematching.canTriggerEmergency)
        XCTAssertFalse(RunOrderStatus.noVolunteer.canTriggerEmergency)
        XCTAssertTrue(RunOrderStatus.inProgress.showsEmergencyPlaceholder)
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
            "请先完成志愿者认证"
        )

        XCTAssertNil(
            VolunteerOrderActionGuard.acceptBlockMessage(profile: makeApprovedVolunteerProfile())
        )
    }

    func testVolunteerAcceptGuardRequiresAdminReviewWhenProvided() {
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
            VolunteerOrderActionGuard.acceptBlockMessage(profile: makeApprovedVolunteerProfile(isAvailable: false)),
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
            files: [MultipartFile],
            requiresAuth: Bool
        ) async throws -> T {
            throw error
        }
    }

    @MainActor
    private final class FakePlaceSearchProvider: PlaceSearchProviding {
        var lastErrorMessage: String?
        var searchKeywords: [String] = []
        private let results: [ResolvedPlace]

        init(results: [ResolvedPlace], lastErrorMessage: String? = nil) {
            self.results = results
            self.lastErrorMessage = lastErrorMessage
        }

        func reverseGeocode(coordinate: CLLocationCoordinate2D) async -> ResolvedPlace? {
            nil
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
