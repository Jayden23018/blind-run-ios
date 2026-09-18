import Foundation
import XCTest
@testable import blindRun

/// 保存空闲时间那一次 `PUT /api/volunteer/profile` 的**请求体**。
///
/// 单独一条用例是因为这个坑没有任何界面症状：契约里 `PUT /api/volunteer/profile`
/// **没有写**它是 PATCH 语义还是整体替换（同一份契约的 `EmergencyContactRequest` 是显式
/// 写了 PATCH 的，这条没写）。如果后端是整体替换，而客户端只带 `availableTimeSlots`，
/// 那么志愿者每改一次空闲时间，昵称 / 导盲犬意愿 / 配速偏好就被一起清空一次，
/// 而接口返回 200、界面上什么都不会发生。
@MainActor
final class VolunteerAvailabilityScheduleSaveTests: XCTestCase {

    func testSavingSlotsCarriesTheWholeProfileNotJustTheSlots() async throws {
        let client = ProfileUpdateSpy()
        let appState = AppState(apiClient: client, tokenStore: ScheduleInMemoryTokenStore())
        appState.updateVolunteerProfile(
            VolunteerProfileResponse(
                name: "张伟",
                acceptsGuideDog: true,
                paceRange: .easy
            )
        )
        client.response = VolunteerProfileResponse(name: "张伟", acceptsGuideDog: true, paceRange: .easy)

        let viewModel = VolunteerAvailabilityScheduleViewModel()
        viewModel.configure(with: appState)
        await viewModel.save()

        let sent = try XCTUnwrap(client.lastProfileUpdate, "没有发出 PUT /api/volunteer/profile")
        XCTAssertEqual(client.lastPath, "/api/volunteer/profile")
        XCTAssertEqual(sent.name, "张伟", "只带时间段 —— 整体替换语义下昵称会被清空")
        XCTAssertEqual(sent.acceptsGuideDog, true, "只带时间段 —— 整体替换语义下导盲犬意愿会被清空")
        XCTAssertEqual(sent.paceRange, .easy, "只带时间段 —— 整体替换语义下配速偏好会被清空")
        XCTAssertNil(viewModel.errorMessage)
    }

    /// 非法区间**不发请求**，只在界面上说明。
    ///
    /// 放行的后果是后端拿到一个长度为负的窗口，这一段永不命中，而接口返回 200。
    func testInvalidRangeIsRejectedBeforeItReachesTheNetwork() async {
        let client = ProfileUpdateSpy()
        let appState = AppState(apiClient: client, tokenStore: ScheduleInMemoryTokenStore())
        appState.updateVolunteerProfile(
            VolunteerProfileResponse(
                availableTimeSlots: [
                    // 跨午夜：契约里只有一个 `dayOfWeek`，表达不了。
                    VolunteerAvailableTimeSlot(dayOfWeek: "FRIDAY", startTime: "22:00:00", endTime: "02:00:00")
                ]
            )
        )

        let viewModel = VolunteerAvailabilityScheduleViewModel()
        viewModel.configure(with: appState)
        await viewModel.save()

        XCTAssertNil(client.lastProfileUpdate, "非法区间不该被发到后端")
        XCTAssertEqual(viewModel.errorMessage, VolunteerAvailabilityScheduleEditing.invalidRangeMessage)
    }

    /// 编辑器交回来的草稿：`id` 在列表里就替换，不在就当新增。
    ///
    /// 新增那一半是这条用例的重点。「添加空闲时间」现在先弹编辑器、手上拿的是一个
    /// **还没进列表**的 `makeDefault()` 草稿，点「完成」才交回来；而本函数的前身 `update`
    /// 是 `guard let index … else { return }` —— 照那条路走新增会什么都不发生，
    /// 界面上看是「点了完成没反应」，且没有任何报错。
    func testUpsertReplacesInPlaceAndAppendsDraftsNotInTheListYet() async throws {
        let client = ProfileUpdateSpy()
        client.response = VolunteerProfileResponse(name: "张伟")
        let appState = AppState(apiClient: client, tokenStore: ScheduleInMemoryTokenStore())
        appState.updateVolunteerProfile(
            VolunteerProfileResponse(
                name: "张伟",
                availableTimeSlots: [
                    VolunteerAvailableTimeSlot(dayOfWeek: "SATURDAY", startTime: "09:00:00", endTime: "12:00:00")
                ]
            )
        )

        let viewModel = VolunteerAvailabilityScheduleViewModel()
        viewModel.configure(with: appState)
        XCTAssertEqual(viewModel.slots.count, 1)

        // 改已有那一条 → 原地替换
        var edited = try XCTUnwrap(viewModel.slots.first)
        edited.weekday = "MONDAY"
        viewModel.upsert(edited)
        XCTAssertEqual(viewModel.slots.count, 1, "改一条已有时段不该变成两条")
        XCTAssertEqual(viewModel.slots.first?.weekday, "MONDAY")

        // 编辑器交回一个列表里没有的草稿 → 新增
        viewModel.upsert(.makeDefault())
        XCTAssertEqual(viewModel.slots.count, 2, "「添加」交回的草稿被静默丢掉了")
    }
}

// MARK: - 替身

private final class ProfileUpdateSpy: APIClientProtocol, @unchecked Sendable {
    var response: VolunteerProfileResponse?
    private(set) var lastPath: String?
    private(set) var lastProfileUpdate: VolunteerProfileUpdateRequest?

    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        lastPath = path
        if let update = body as? VolunteerProfileUpdateRequest {
            lastProfileUpdate = update
        }
        guard let typed = response as? T else { throw APIError.unknown(statusCode: -1) }
        return typed
    }

    func upload<T: Decodable>(
        path: String,
        query: [String: String]?,
        fields: [String: String]?,
        files: [MultipartFile],
        requiresAuth: Bool
    ) async throws -> T {
        throw APIError.unknown(statusCode: -1)
    }
}

private final class ScheduleInMemoryTokenStore: TokenStoring {
    private var token: String?
    func save(_ token: String) { self.token = token }
    func read() -> String? { token }
    func delete() { token = nil }
}
