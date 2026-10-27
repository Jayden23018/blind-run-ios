import XCTest
@testable import blindRun

/// 邀请类载荷的解码（后端 #371 / #366）。从 `InviteModelTests` 拆出：那个类的行为用例要留在上限以内（SwiftLint 棘轮 #488）。
final class InviteDecodingTests: XCTestCase {

    /// WS 推送带 `inviteId` / `expiresAt`；整分钟时 `expiresAt` 省掉 `:00`（后端 #542）。
    func testNewOrderDecodesInviteIdentityAndAuthoritativeDeadline() throws {
        let json = #"{"type":"NEW_ORDER","orderId":7,"inviteId":901,"expiresAt":"2026-10-06T10:30","dispatchTimeoutSeconds":900,"requiresIntroCall":false}"#
        let order = try JSONDecoder().decode(WSNewOrder.self, from: Data(json.utf8))
        XCTAssertEqual(order.inviteId, 901)
        XCTAssertEqual(order.expiresAt?.backendTimestamp, "2026-10-06T10:30:00".backendTimestamp)
    }

    /// 待回复列表的每一项**没有 `type`**，多一个 `sentAt`；`distanceKm` 位置未知时是 `null`。
    /// `type` 若还是必填，整个列表都解不出来。
    func testPendingInvitesDecodeWithoutTypeAndWithNullDistance() throws {
        let json = #"""
        {"consecutiveDeclineCount":2,"invites":[
          {"orderId":7,"inviteId":901,"sentAt":"2026-10-06T10:00:00","expiresAt":"2026-10-06T10:15:00",
           "dispatchTimeoutSeconds":900,"distanceKm":null,"requiresIntroCall":true}
        ]}
        """#
        let response = try APIPayloadDecoder.decodePayload(PendingInvitesResponse.self, from: Data(json.utf8), decoder: JSONDecoder())
        XCTAssertEqual(response.consecutiveDeclineCount, 2)
        let invite = try XCTUnwrap(response.invites?.first)
        XCTAssertNil(invite.type)
        XCTAssertNil(invite.distanceKm, "位置未知是 null，不是 0 公里")
        XCTAssertEqual(invite.sentAt, "2026-10-06T10:00:00")
    }

    /// `reason` 是开放枚举：认不出的落 `.other`，不许整条推送解不出来。
    func testWithdrawReasonIsAnOpenEnum() {
        XCTAssertEqual(InviteWithdrawReason(rawValue: "TAKEN"), .taken)
        XCTAssertEqual(InviteWithdrawReason(rawValue: "CONFLICT"), .conflict)
        XCTAssertEqual(InviteWithdrawReason(rawValue: "ORDER_CLOSED"), .orderClosed)
        XCTAssertEqual(InviteWithdrawReason(rawValue: "SOMETHING_NEW"), .other)
        XCTAssertEqual(InviteWithdrawReason(rawValue: nil), .other)
    }
}
