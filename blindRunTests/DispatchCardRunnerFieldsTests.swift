import XCTest
@testable import blindRun

/// 派单卡片的五个新字段（后端 issue #306）：视力 / 牵引 / 聊天偏好 / 路线偏好 / 一起跑过几次。
final class DispatchCardRunnerFieldsTests: XCTestCase {

    private static let fullPush = """
    {"type":"NEW_ORDER","orderId":123,"startAddress":"朝阳公园南门","startLatitude":39.9,"startLongitude":116.4,
     "distanceKm":2.5,"plannedStart":"2026-05-23T14:00:00","plannedEnd":"2026-05-23T15:00:00",
     "dispatchTimeoutSeconds":30,"priority":"HIGH","hasGuideDog":true,
     "visionLevel":"TOTAL_BLIND","tetherPreference":"TETHER_ROPE","chatPreference":"PREFER_QUIET",
     "routePreference":"PARK_TRAIL","completedTogetherCount":3,"expectedDurationMinutes":60,
     "requiresIntroCall":true}
    """

    private static func push(_ json: String) throws -> WSNewOrder {
        try JSONDecoder().decode(WSNewOrder.self, from: Data(json.utf8))
    }

    func testPushCarriesAllFiveFieldsIntoTheRunnerRow() throws {
        let supplement = try XCTUnwrap(VolunteerInviteSupplement(Self.push(Self.fullPush)))
        XCTAssertEqual(supplement.runnerSummary, "全盲，牵引绳，偏好安静，想跑公园步道")
        XCTAssertEqual(supplement.togetherText, "一起跑过 3 次")
        XCTAssertEqual(supplement.durationText, "60 分钟")
    }

    /// `0` 永远下发，意思是「从没一起跑过」；缺键是「后端没给」—— 两者在卡片上说的话不同。
    func testZeroAndMissingTogetherCountSayDifferentThings() throws {
        let zero = try Self.push(Self.fullPush.replacingOccurrences(of: "\"completedTogetherCount\":3", with: "\"completedTogetherCount\":0"))
        XCTAssertEqual(VolunteerInviteSupplement(zero)?.togetherText, "第一次一起跑")

        let missing = try Self.push(Self.fullPush.replacingOccurrences(of: "\"completedTogetherCount\":3,", with: ""))
        XCTAssertNil(VolunteerInviteSupplement(missing)?.togetherText)
    }

    /// 前四项档案缺失时整键不出现 ⇒ 那一项不渲染，**不脑补默认值**（「不知道」≠「全盲」）。
    func testMissingProfileKeysAreNotFilledIn() throws {
        let bare = try Self.push("""
        {"type":"NEW_ORDER","orderId":1,"completedTogetherCount":0,"requiresIntroCall":false}
        """)
        let supplement = try XCTUnwrap(VolunteerInviteSupplement(bare))
        XCTAssertNil(supplement.runnerSummary, "档案一项都没有，却生出了跑者描述：\(supplement.runnerSummary ?? "")")
        XCTAssertEqual(supplement.togetherText, "第一次一起跑")
    }

    /// 「没有偏好」不占字；`NOT_SPECIFIED` 这类没见过的视力取值落「当面确认」，绝不显示成全盲。
    func testNoPreferenceIsSilentAndUnknownVisionIsNeverShownAsTotalBlind() {
        let supplement = VolunteerInviteSupplement(
            visionLevel: "NOT_SPECIFIED",
            tetherPreference: nil,
            expectedDurationMinutes: nil,
            chatPreference: "NO_PREFERENCE",
            routePreference: "NO_PREFERENCE"
        )
        XCTAssertEqual(supplement.runnerSummary, EscortNeed.confirmInPerson)
        XCTAssertFalse(supplement.runnerSummary?.contains("全盲") ?? false)
    }

    /// 老服务端的推送一项都没有 ⇒ 返回 nil，让 `/api/orders/available` 那条补的路照旧工作。
    func testLegacyPushLeavesTheSupplementToTheAvailableOrdersFetch() throws {
        let legacy = try Self.push("""
        {"type":"NEW_ORDER","orderId":1,"requiresIntroCall":true}
        """)
        XCTAssertNil(VolunteerInviteSupplement(legacy))
    }

    func testAvailableOrdersCarryTheSameThreeNewFields() throws {
        let json = """
        [{"orderId":9,"visionLevel":"LOW_VISION","tetherPreference":"ARM_HOLD","expectedDurationMinutes":45,
          "chatPreference":"PREFER_CHAT","routePreference":"TRACK","completedTogetherCount":1}]
        """
        let orders = try JSONDecoder().decode([AvailableOrderResponse].self, from: Data(json.utf8))
        let supplement = VolunteerInviteSupplement(try XCTUnwrap(orders.first))
        XCTAssertEqual(supplement.runnerSummary, "低视力，搀扶，喜欢聊天，想跑跑道")
        XCTAssertEqual(supplement.togetherText, "一起跑过 1 次")
    }
}
