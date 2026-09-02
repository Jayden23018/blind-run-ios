//
//  IncentiveService.swift
//  blindRun
//
//  领域 service 层第二片：激励（积分 / 成就 / 固定搭档 / 火花 / 邀请码）。
//  照 `AuthService.swift` 抄，那份是范例。
//

import Foundation

// MARK: - Endpoints

/// 激励片用到的全部端点。
///
/// **一个 case 一条完整字面量路径**，不许拼接 —— `scripts/validate-spec-coverage.mjs`
/// 只认字符串字面量。收藏那两条方法不同、路径相同，仍然各写一遍完整字面量
/// （同 `AuthEndpoint` 的 `registerDeviceToken` / `unregisterDeviceToken`）：
/// 少写一遍换来的是一条拼接路径，扫不到就等于绕过契约门禁。
///
/// 🔴 **勋章阈值不在这里，也不许搬进来。** 它住在后端 `VolunteerBadge.isUnlockedBy` 的
/// 穷举 switch 里，客户端只渲染后端算好的 `badges` / `nextBadge`。
/// `MockAPIClient+Profile.swift` 逐条抄那套阈值是对的（Mock 的职责是像后端），
/// App 抄就成了第二个真相源，后端改一行阈值这边就漂移。理由详见
/// `VolunteerAchievements.swift` 顶部「为什么这个能放在客户端算，而平台勋章的阈值不能」。
enum IncentiveEndpoint {
    case volunteerPoints
    case volunteerAchievements

    // 盲人侧固定搭档
    case blindFavoriteVolunteers
    case addBlindFavoriteVolunteer(volunteerId: Int64)
    case removeBlindFavoriteVolunteer(volunteerId: Int64)
    case blindPartnerStreaks

    // 志愿者侧固定搭档
    case volunteerFavoritedBy
    case volunteerOptOutOfFavorite(blindUserId: Int64)
    case volunteerPartnerStreaks

    case inviteCode

    var request: EndpointRequest {
        switch self {
        case .volunteerPoints:
            return EndpointRequest(.get, "/api/volunteer/points")
        case .volunteerAchievements:
            return EndpointRequest(.get, "/api/volunteer/achievements")
        case .blindFavoriteVolunteers:
            return EndpointRequest(.get, "/api/blind/favorite-volunteers")
        case .addBlindFavoriteVolunteer(let volunteerId):
            return EndpointRequest(.put, "/api/blind/favorite-volunteers/\(volunteerId)")
        case .removeBlindFavoriteVolunteer(let volunteerId):
            return EndpointRequest(.delete, "/api/blind/favorite-volunteers/\(volunteerId)")
        case .blindPartnerStreaks:
            return EndpointRequest(.get, "/api/blind/partners/streaks")
        case .volunteerFavoritedBy:
            return EndpointRequest(.get, "/api/volunteer/favorites")
        case .volunteerOptOutOfFavorite(let blindUserId):
            return EndpointRequest(.delete, "/api/volunteer/favorites/\(blindUserId)")
        case .volunteerPartnerStreaks:
            return EndpointRequest(.get, "/api/volunteer/partners/streaks")
        case .inviteCode:
            return EndpointRequest(.get, "/api/users/me/invite-code")
        }
    }
}

// MARK: - Protocol

/// 激励片对外的全部能力。
///
/// **每个方法都必须有生产调用点**（当前 9 个，与迁移前的 9 个 `apiClient.<verb>` 一一对应）：
/// `PartnerListViews` 6 · `VolunteerPointsView` 1 · `InviteCodeView` 1 ·
/// `VolunteerOrderFlowViews`（成就页）1。没有调用点的方法当场删。
///
/// 错误一律 `throws` 抛出去，**这一层不吞**。这几屏各自把 `APIError.localizedMessage`
/// 画进失败态，盲人侧还要念出来 —— 吞在这里的错误在 UI 上就是「点了没反应」。
protocol IncentiveServing: Sendable {
    func volunteerPoints(page: Int, size: Int) async throws -> VolunteerPointsResponse
    func volunteerAchievements() async throws -> VolunteerAchievementsResponse

    func blindFavoriteVolunteers() async throws -> [FavoriteVolunteerResponse]
    /// 幂等，恒 204；门槛不满足时 400 `FAVORITE_VOLUNTEER_NOT_ELIGIBLE`。
    func addBlindFavoriteVolunteer(volunteerId: Int64) async throws
    /// 幂等，恒 204 —— 没收藏过也返 204。
    func removeBlindFavoriteVolunteer(volunteerId: Int64) async throws
    func blindPartnerStreaks() async throws -> [PartnerStreakResponse]

    func volunteerFavoritedBy() async throws -> [VolunteerFavoritedByResponse]
    /// **恒 204，不区分「改到了」与「没这一行」** —— 区分开这个端点就成了
    /// 「拿任意 userId 试一下看响应差异」的探测器。
    func volunteerOptOutOfFavorite(blindUserId: Int64) async throws
    func volunteerPartnerStreaks() async throws -> [PartnerStreakResponse]

    func inviteCode() async throws -> InviteCodeResponse
}

// MARK: - Implementation

/// 唯一的生产实现。**只做两件事**：选端点、转参数。
///
/// 不做重试、不做缓存、不做错误分类，也不做任何解锁判定 ——
/// 这一层多一个判断，就多一处「Mock 和真实后端行为不一样」的来源。
struct IncentiveService: IncentiveServing {
    let transport: any APIClientProtocol

    init(transport: any APIClientProtocol) {
        self.transport = transport
    }

    func volunteerPoints(page: Int, size: Int) async throws -> VolunteerPointsResponse {
        try await transport.send(
            IncentiveEndpoint.volunteerPoints.request,
            query: ["page": "\(page)", "size": "\(size)"]
        )
    }

    func volunteerAchievements() async throws -> VolunteerAchievementsResponse {
        try await transport.send(IncentiveEndpoint.volunteerAchievements.request)
    }

    func blindFavoriteVolunteers() async throws -> [FavoriteVolunteerResponse] {
        try await transport.send(IncentiveEndpoint.blindFavoriteVolunteers.request)
    }

    func addBlindFavoriteVolunteer(volunteerId: Int64) async throws {
        let _: EmptyResponse = try await transport.send(
            IncentiveEndpoint.addBlindFavoriteVolunteer(volunteerId: volunteerId).request
        )
    }

    func removeBlindFavoriteVolunteer(volunteerId: Int64) async throws {
        let _: EmptyResponse = try await transport.send(
            IncentiveEndpoint.removeBlindFavoriteVolunteer(volunteerId: volunteerId).request
        )
    }

    func blindPartnerStreaks() async throws -> [PartnerStreakResponse] {
        try await transport.send(IncentiveEndpoint.blindPartnerStreaks.request)
    }

    func volunteerFavoritedBy() async throws -> [VolunteerFavoritedByResponse] {
        try await transport.send(IncentiveEndpoint.volunteerFavoritedBy.request)
    }

    func volunteerOptOutOfFavorite(blindUserId: Int64) async throws {
        let _: EmptyResponse = try await transport.send(
            IncentiveEndpoint.volunteerOptOutOfFavorite(blindUserId: blindUserId).request
        )
    }

    func volunteerPartnerStreaks() async throws -> [PartnerStreakResponse] {
        try await transport.send(IncentiveEndpoint.volunteerPartnerStreaks.request)
    }

    func inviteCode() async throws -> InviteCodeResponse {
        try await transport.send(IncentiveEndpoint.inviteCode.request)
    }
}
