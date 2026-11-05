import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class ErrorEnvelopeAndMockOrderTests: XCTestCase {
    func testFlexibleErrorEnvelopeUsesBusinessErrorCode() throws {
        let data = #"{"errorCode":"VOLUNTEER_NOT_AVAILABLE","code":403,"success":false,"message":"未开启接单"}"#.data(using: .utf8)!
        let payload = try JSONDecoder().decode(APIErrorEnvelope.self, from: data)
        let response = try XCTUnwrap(payload.resolvedErrorResponse(statusCode: 403))

        XCTAssertEqual(response.code, "VOLUNTEER_NOT_AVAILABLE")
        XCTAssertEqual(response.message, "未开启接单")
    }

    /// 裸 `{"error": ...}` 信封**刻意不再解析** —— 这不是漏了，是 2026-07-31 与后端确认后删的。
    ///
    /// 后端全仓只剩两处产出 `error` 键，客户端都够不到：
    /// - `AuthController:62` 的 401 `{"error":"未登录"}` —— `APIClient` 在 `case 401`
    ///   直接 `throw .unauthorized`，body 根本不解码
    /// - `GlobalExceptionHandler:224` 的 429 —— 那里 `error` 放的是错误码字符串不是文案，
    ///   且同一个 body 恒带 `message`，兜底分支走不到
    ///
    /// 而本用例原来喂的 `{"error":"验证码错误或已过期"}` 是**已下线的旧验证码响应形状**，
    /// 现在统一走 `{success,code,errorCode,message}`。
    func testFlexibleErrorEnvelopeIgnoresLegacyBareErrorKey() throws {
        let data = #"{"error":"验证码错误或已过期"}"#.data(using: .utf8)!
        let payload = try JSONDecoder().decode(APIErrorEnvelope.self, from: data)

        XCTAssertNil(payload.resolvedErrorResponse(statusCode: 400))
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
        // 曾经从 `/api/orders/available` 取种子。那条路由已随公开订单池一起删除
        // （App 走不到，且它的真实形状是 `AvailableOrderResponse` 裸数组，不是分页对象）。
        let mine: PagedOrderResponse = try await client.get("/api/orders/mine")
        let order = try XCTUnwrap(mine.content.first { $0.status == .pendingMatch })

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
            XCTAssertEqual(response.code, "ORDER_STATUS_NOT_ALLOWED")
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
        // 本用例考的是「派单状态 + 在途订单」，与培训无关。
        // Mock 默认「一门必修课都没学」（那个默认是刻意的，见 MockAPIClient.trainingProgress），
        // 不先把培训过掉的话下面每一处 notAvailableReasons 都会多一个 TRAINING_INCOMPLETE，
        // 断言全红 —— 而红的原因与本用例要守的东西无关。
        client.completeAllRequiredTrainingForTesting()

        let initialSummary: VolunteerDispatchSummaryResponse = try await client.get("/api/volunteer/dispatch-summary")
        XCTAssertFalse(initialSummary.canDispatch ?? true)
        // Mock 只在开启接单时上报位置，所以关掉接单时 DISPATCH_DISABLED 与 OFFLINE 同时命中
        // （与后端 getDispatchSummary 的独立评估一致）。
        XCTAssertEqual(initialSummary.notAvailableReasons, [.dispatchDisabled, .offline])
        XCTAssertEqual(initialSummary.completedCount, 1)
        // 此前这里断言 `resolvedPointsBalance == 100`，也就是 `completedCount * 100` ——
        // 后端从来没有 `pointsBalance` 字段，那条断言钉住的是客户端自己编的数。
        // 现在断言真实字段本身，并确认没有任何地方再产出那个合成值。
        XCTAssertEqual(initialSummary.totalCompleted, 1)

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
        // 后端 `VolunteerService.getDispatchSummary` 只评估**四个**独立条件
        // （DISPATCH_DISABLED / NOT_VERIFIED / TRAINING_INCOMPLETE / OFFLINE，
        // 见 `DispatchBlockReason.java`；TRAINING_INCOMPLETE 是 2026-09-09 随迁移 0043 加的）。
        // 在途订单**不**产生 notAvailableReason，也不影响 canDispatch —— 派单入口另行过滤。
        XCTAssertTrue(activeSummary.canDispatch ?? false)
        XCTAssertEqual(activeSummary.notAvailableReasons, [])
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
}
