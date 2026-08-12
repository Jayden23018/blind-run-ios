import XCTest
@testable import blindRun

/// `GET /api/emergency/active` 的解码。
///
/// 单独拎出来是因为它踩在 `URLSessionAPIClient` 那条「先试信封、拿不到 `data` 再裸解」的策略上：
/// 事件存在时 `data` 是一个 `EmergencyEventResponse`，没有事件时 `data` 是 `null`，而两种都要用同一个
/// Swift 类型接住。`EmergencyActiveEnvelope.success` 之所以是**非可选**，正是为了在有事件时让内层解码
/// 失败、从而落到裸解那一步 —— 这个机制靠读代码推不出来，必须真的解一遍。
///
/// 它守的是 SOS 冷启动/重连恢复：解错的表现是「明明有进行中的求助，界面说没有」。
final class EmergencyActiveDecodingTests: XCTestCase {

    private let decoder = JSONDecoder()

    private func decode(_ json: String) throws -> EmergencyActiveEnvelope {
        try APIPayloadDecoder.decodePayload(
            EmergencyActiveEnvelope.self,
            from: Data(json.utf8),
            decoder: decoder
        )
    }

    /// 没有未终态事件：`data: null`，不得抛错，也不得被当成「有事件」。
    func testNullDataDecodesAsNoActiveEvent() throws {
        let envelope = try decode(#"{"success":true,"code":200,"message":null,"data":null}"#)

        XCTAssertTrue(envelope.success)
        XCTAssertNil(envelope.data)
    }

    /// 有事件：字段要落到正确的位置，尤其 `userId` 是**受助者**而不是触发者。
    func testEventPayloadDecodesThroughTheBareFallback() throws {
        let envelope = try decode("""
        {
          "success": true,
          "code": 200,
          "data": {
            "id": 9001,
            "orderId": 42,
            "userId": 7,
            "triggeredAt": "2026-08-01T10:00:00",
            "triggerType": "VOLUNTEER_BUTTON",
            "status": "CONTACT_NOTIFIED",
            "hasGpsLocation": true,
            "gpsLat": null,
            "gpsLng": null,
            "volunteerNotifiedAt": "2026-08-01T10:00:01",
            "volunteerConfirmedAt": null,
            "volunteerAction": null
          }
        }
        """)

        let event = try XCTUnwrap(envelope.data)
        XCTAssertEqual(event.id, 9001)
        XCTAssertEqual(event.orderId, 42)
        XCTAssertEqual(event.userId, 7, "userId 是受助者，志愿者代触发时仍是盲人")
        XCTAssertEqual(event.eventStatus, .contactNotified)
        XCTAssertEqual(event.triggerType, "VOLUNTEER_BUTTON")
        XCTAssertEqual(event.hasGpsLocation, true)
    }

    /// 后端以后加字段不能把这个端点解崩 —— 恢复通道解不出等于求助状态凭空消失。
    func testUnknownFieldsAndUnknownStatusDoNotBreakRecovery() throws {
        let envelope = try decode("""
        {
          "success": true,
          "data": { "id": 9002, "status": "SOMETHING_NEW", "somethingElse": 1 }
        }
        """)

        let event = try XCTUnwrap(envelope.data)
        XCTAssertEqual(event.id, 9002)
        // 未知状态退化成 `unknown`，而不是让整条恢复链路抛错。
        XCTAssertEqual(event.eventStatus, .unknown)
        XCTAssertNil(event.orderId)
        XCTAssertFalse(event.eventStatus.isTerminal, "认不出的状态不得被当成已结束")
    }

    /// 已终态的事件仍然会被解出来 —— 由 `EmergencyCoordinator` 判 `isTerminal` 后清本地状态，
    /// 解码层不做业务判断。
    func testTerminalEventStillDecodes() throws {
        let envelope = try decode(#"{"success":true,"data":{"id":9003,"status":"FALSE_ALARM"}}"#)

        XCTAssertEqual(envelope.data?.eventStatus, .falseAlarm)
        XCTAssertTrue(try XCTUnwrap(envelope.data).eventStatus.isTerminal)
    }

    /// 顺带锁住策略本身：字段全可选的模型不能被信封根对象「解成功但全是 nil」。
    /// 这是信封优先顺序存在的原因，改顺序会让一批 profile 类响应静默变空。
    func testEnvelopeIsPreferredOverBareDecodeForAllOptionalModels() throws {
        struct AllOptional: Decodable, Equatable {
            let name: String?
            let age: Int?
        }

        let payload = try APIPayloadDecoder.decodePayload(
            AllOptional.self,
            from: Data(#"{"success":true,"code":200,"data":{"name":"张三","age":30}}"#.utf8),
            decoder: decoder
        )

        XCTAssertEqual(payload, AllOptional(name: "张三", age: 30))
    }
}
