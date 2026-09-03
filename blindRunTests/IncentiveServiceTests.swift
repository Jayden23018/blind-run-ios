import XCTest
@testable import blindRun

/// 激励片的 service 层端点映射。
///
/// 只钉「类型系统钉不住的那几条」—— 编译器已经保证 `inviteCode()` 返回
/// `InviteCodeResponse`，再断言一遍是重复劳动。这里管的是它打错端点也照样编译的那些：
///
/// 1. **收藏 / 取消收藏路径完全相同，只差 method**。调错了 Mock 与后端都不会报错：
///    `PUT` 有门槛判定（400），`DELETE` 恒 204，写反了在开发期表现成「取消收藏永远成功、
///    收藏永远没门槛」，一直到真机联调才炸。
/// 2. **盲人侧与志愿者侧的火花是两条不同路径、同一个返回类型**（`[PartnerStreakResponse]`），
///    互换后类型检查照过。这正是记忆 `same-name-predicate-different-sets-across-ends` 那一类。
/// 3. 分页参数有没有真的传下去。
final class IncentiveServiceTests: XCTestCase {

    // MARK: - 同路径不同 method

    func testAddAndRemoveFavoriteShareOnePathButDifferentMethods() async throws {
        let transport = RecordingTransport()
        transport.nextResponse = EmptyResponse()
        let service = IncentiveService(transport: transport)

        try await service.addBlindFavoriteVolunteer(volunteerId: 9004)
        try await service.removeBlindFavoriteVolunteer(volunteerId: 9004)

        XCTAssertEqual(transport.requests.map(\.path), [
            "/api/blind/favorite-volunteers/9004",
            "/api/blind/favorite-volunteers/9004"
        ])
        XCTAssertEqual(
            transport.requests.map(\.method), [.put, .delete],
            "写反了 Mock 和后端都不会报错：PUT 有门槛判定、DELETE 恒 204"
        )
    }

    /// 志愿者退出固定搭档是**另一条路径**上的 `DELETE`，不是盲人那条。
    func testVolunteerOptOutHitsTheVolunteerPathNotTheBlindOne() async throws {
        let transport = RecordingTransport()
        transport.nextResponse = EmptyResponse()

        try await IncentiveService(transport: transport).volunteerOptOutOfFavorite(blindUserId: 42)

        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(sent.method, .delete)
        XCTAssertEqual(sent.path, "/api/volunteer/favorites/42")
    }

    // MARK: - 两侧同返回类型，只有路径能区分

    func testBlindAndVolunteerStreaksAreTwoDistinctPaths() async throws {
        let transport = RecordingTransport()
        transport.nextResponse = [PartnerStreakResponse]()
        let service = IncentiveService(transport: transport)

        _ = try await service.blindPartnerStreaks()
        _ = try await service.volunteerPartnerStreaks()

        XCTAssertEqual(transport.requests.map(\.path), [
            "/api/blind/partners/streaks",
            "/api/volunteer/partners/streaks"
        ], "两侧返回类型相同，互换后类型检查照过")
    }

    /// 「谁被我收藏」与「谁把我设为固定搭档」是两侧各自的列表端点，返回类型不同但路径易混。
    func testFavoriteListEndpointsAreSidedCorrectly() async throws {
        let blindTransport = RecordingTransport()
        blindTransport.nextResponse = [FavoriteVolunteerResponse]()
        _ = try await IncentiveService(transport: blindTransport).blindFavoriteVolunteers()
        XCTAssertEqual(blindTransport.requests.first?.path, "/api/blind/favorite-volunteers")

        let volunteerTransport = RecordingTransport()
        volunteerTransport.nextResponse = [VolunteerFavoritedByResponse]()
        _ = try await IncentiveService(transport: volunteerTransport).volunteerFavoritedBy()
        XCTAssertEqual(volunteerTransport.requests.first?.path, "/api/volunteer/favorites")
    }

    // MARK: - 分页

    func testPointsPassesPageAndSizeAsQuery() async throws {
        let transport = RecordingTransport()
        transport.nextResponse = VolunteerPointsResponse(
            balance: 0, transactions: [], page: 1, size: 20, totalElements: 0, totalPages: 1
        )

        _ = try await IncentiveService(transport: transport).volunteerPoints(page: 1, size: 20)

        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(sent.method, .get)
        XCTAssertEqual(sent.path, "/api/volunteer/points")
        XCTAssertEqual(sent.query, ["page": "1", "size": "20"], "分页参数丢了就永远只看得到第一页")
    }

    // MARK: - 剩下几条只验路径没打错

    func testRemainingEndpointsMapToTheirContractPaths() async throws {
        let achievements = RecordingTransport()
        achievements.nextResponse = VolunteerAchievementsResponse(
            totalCompleted: 0, totalServiceMinutes: 0, avgRating: nil,
            totalRatings: 0, badges: [], nextBadge: nil, starLevel: nil
        )
        _ = try await IncentiveService(transport: achievements).volunteerAchievements()
        XCTAssertEqual(achievements.requests.first?.path, "/api/volunteer/achievements")

        let invite = RecordingTransport()
        invite.nextResponse = InviteCodeResponse(inviteCode: "ABCD2345", invitedCount: 0, rewardedCount: 0)
        _ = try await IncentiveService(transport: invite).inviteCode()
        XCTAssertEqual(invite.requests.first?.path, "/api/users/me/invite-code")
    }
}
