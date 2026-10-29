import XCTest
@testable import blindRun

/// 邀请上的跑者称呼（#339，后端 #357 起 `NEW_ORDER` 与待回复列表带掩码 `blindName`）。
///
/// 两条都会静默出错：屏幕上把掩码去掉（看起来像拿到了全名），或读屏念出星号（「李星号」）。
/// 取值挑的是能把这两种错误实现分开的：掩码名同时检查屏幕版**带**星号、朗读版**不带**。
final class InviteRunnerNameTests: XCTestCase {

    func testPushCarriesTheMaskedName() throws {
        let json = #"{"type":"NEW_ORDER","orderId":7,"inviteId":901,"blindName":"李*","requiresIntroCall":false}"#
        let order = try JSONDecoder().decode(WSNewOrder.self, from: Data(json.utf8))
        XCTAssertEqual(order.blindName, "李*")
        XCTAssertEqual(order.runnerName?.display, "李*", "屏幕上保留掩码")
        XCTAssertEqual(order.runnerName?.spoken, "李", "读屏去掉星号")
    }

    func testPendingInvitesCarryTheMaskedName() throws {
        let json = #"{"consecutiveDeclineCount":0,"invites":[{"orderId":7,"inviteId":901,"blindName":"王＊"}]}"#
        let response = try JSONDecoder().decode(PendingInvitesResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.invites?.first?.runnerName?.spoken, "王", "全角星号同样去掉")
    }

    /// 键不出现（用户已注销）、空串、只剩星号：都是「没有称呼」，不渲染、不编名字。
    func testMissingOrEmptyNameMeansNoName() {
        for raw in [nil, "", "  ", "*", "＊"] as [String?] {
            var order = OrderDetailResponse.previewDispatch()
            order.blindName = raw
            XCTAssertNil(order.runnerName, "blindName = \(String(describing: raw)) 不该有称呼")
        }
    }

    func testInvitePageShowsTheRunnerRowOnlyWhenTheNameIsKnown() throws {
        var dispatch = OrderDetailResponse.previewDispatch()
        dispatch.blindName = "李*"
        let withName = VolunteerOrderFlowPresentation.make(dispatch: dispatch, remainingSeconds: 600)
        let row = try XCTUnwrap(withName.rows.first { $0.id == "runner" })
        XCTAssertEqual(row.value, "李*")
        XCTAssertEqual(row.accessibilityLabel, "跑者李")

        dispatch.blindName = nil
        let withoutName = VolunteerOrderFlowPresentation.make(dispatch: dispatch, remainingSeconds: 600)
        XCTAssertFalse(withoutName.rows.contains { $0.id == "runner" }, "没给姓名就不出这一行")
    }

    /// 邀请卡跑者行（复核 A）：屏幕保留掩码、头像取姓、读屏去星号。把 `display` 与 `spoken` 用反的实现在这里红。
    func testInviteCardRunnerRowKeepsTheMaskOnScreenAndDropsItForSpeech() throws {
        var order = OrderDetailResponse.previewDispatch()
        order.blindName = "李*"
        let row = try XCTUnwrap(VolunteerInviteRunnerRow(order: order, summary: "全盲，牵引绳", together: "一起跑过 3 次"))
        XCTAssertEqual(row.title, "跑者李*")
        XCTAssertEqual(row.avatarName, "李")
        XCTAssertEqual(row.spokenLabel, "跑者李，全盲，牵引绳，一起跑过 3 次")
    }

    /// 没有称呼：屏幕「跑者」、头像占位「跑」；三样都没有时整行不渲染。
    func testInviteCardRunnerRowWithoutANameFallsBackWithoutInventingOne() throws {
        let order = OrderDetailResponse.previewDispatch()
        let row = try XCTUnwrap(VolunteerInviteRunnerRow(order: order, summary: "全盲", together: nil))
        XCTAssertEqual(row.title, "跑者")
        XCTAssertNil(row.avatarName)
        XCTAssertEqual(row.spokenLabel, "跑者，全盲")
        XCTAssertNil(VolunteerInviteRunnerRow(order: order, summary: nil, together: nil))
    }
}
