import Foundation
@testable import blindRun

/// `IncentiveServing` 的测试替身。规矩照抄 `FakeAuthService` / `FakeSafetyService`：
///
/// 1. **不许含任何业务判定**（`if` / `switch` / 校验 / 状态机）。每个方法只做两件事：
///    记一笔调用、返回构造时注入的罐装值。
/// 2. **默认是失败而不是成功**：没打桩的方法抛 `NotStubbed`。忘了打桩会当场红，
///    而不是拿一个空数组静默走完。
///
/// 建它的直接起因：成就页的 `load()` 从 `VolunteerServiceRecognitionView` 的 body
/// 搬进 `VolunteerAchievementsViewModel` 之后才有测试面，而这一片的端点归激励片
/// （`IncentiveService`）所有 —— 激励片自己的用例打在 `RecordingTransport` 传输层上，
/// 够不到 view model 这一层。
final class FakeIncentiveService: IncentiveServing, @unchecked Sendable {

    struct NotStubbed: Error, CustomStringConvertible {
        let method: String
        var description: String { "FakeIncentiveService.\(method) 没有打桩" }
    }

    /// 调用顺序，元素是 `#function`。断言「只发了一次」这类用。
    private(set) var calls: [String] = []

    var volunteerPointsResult: Result<VolunteerPointsResponse, Error> = .failure(NotStubbed(method: "volunteerPoints"))
    var volunteerAchievementsResult: Result<VolunteerAchievementsResponse, Error> = .failure(NotStubbed(method: "volunteerAchievements"))
    var blindFavoriteVolunteersResult: Result<[FavoriteVolunteerResponse], Error> = .failure(NotStubbed(method: "blindFavoriteVolunteers"))
    var addBlindFavoriteVolunteerResult: Result<Void, Error> = .failure(NotStubbed(method: "addBlindFavoriteVolunteer"))
    var removeBlindFavoriteVolunteerResult: Result<Void, Error> = .failure(NotStubbed(method: "removeBlindFavoriteVolunteer"))
    var blindPartnerStreaksResult: Result<[PartnerStreakResponse], Error> = .failure(NotStubbed(method: "blindPartnerStreaks"))
    var volunteerFavoritedByResult: Result<[VolunteerFavoritedByResponse], Error> = .failure(NotStubbed(method: "volunteerFavoritedBy"))
    var volunteerOptOutOfFavoriteResult: Result<Void, Error> = .failure(NotStubbed(method: "volunteerOptOutOfFavorite"))
    var volunteerPartnerStreaksResult: Result<[PartnerStreakResponse], Error> = .failure(NotStubbed(method: "volunteerPartnerStreaks"))
    var inviteCodeResult: Result<InviteCodeResponse, Error> = .failure(NotStubbed(method: "inviteCode"))

    /// 最后一次收到的参数。断言「传下去的是哪个值」用，不参与任何判定。
    private(set) var lastPage: Int?
    private(set) var lastSize: Int?
    private(set) var lastVolunteerId: Int64?
    private(set) var lastBlindUserId: Int64?

    private func record(_ method: String = #function) {
        calls.append(method)
    }

    func volunteerPoints(page: Int, size: Int) async throws -> VolunteerPointsResponse {
        record()
        lastPage = page
        lastSize = size
        return try volunteerPointsResult.get()
    }

    func volunteerAchievements() async throws -> VolunteerAchievementsResponse {
        record()
        return try volunteerAchievementsResult.get()
    }

    func blindFavoriteVolunteers() async throws -> [FavoriteVolunteerResponse] {
        record()
        return try blindFavoriteVolunteersResult.get()
    }

    func addBlindFavoriteVolunteer(volunteerId: Int64) async throws {
        record()
        lastVolunteerId = volunteerId
        return try addBlindFavoriteVolunteerResult.get()
    }

    func removeBlindFavoriteVolunteer(volunteerId: Int64) async throws {
        record()
        lastVolunteerId = volunteerId
        return try removeBlindFavoriteVolunteerResult.get()
    }

    func blindPartnerStreaks() async throws -> [PartnerStreakResponse] {
        record()
        return try blindPartnerStreaksResult.get()
    }

    func volunteerFavoritedBy() async throws -> [VolunteerFavoritedByResponse] {
        record()
        return try volunteerFavoritedByResult.get()
    }

    func volunteerOptOutOfFavorite(blindUserId: Int64) async throws {
        record()
        lastBlindUserId = blindUserId
        return try volunteerOptOutOfFavoriteResult.get()
    }

    func volunteerPartnerStreaks() async throws -> [PartnerStreakResponse] {
        record()
        return try volunteerPartnerStreaksResult.get()
    }

    func inviteCode() async throws -> InviteCodeResponse {
        record()
        return try inviteCodeResult.get()
    }
}
