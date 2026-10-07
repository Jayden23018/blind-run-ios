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

    // MARK: - 一次性时段（后端 #564 / iOS #353）

    /// 读进来再整体 PUT 回去，一次性时段的 `date` 必须原样带回；过期的不许带回。
    /// 模型不认识 `date` 的旧实现会把 10-10 那段发成一条每周六的时段 —— 静默改数据。
    func testOneOffSlotKeepsItsDateAndExpiredOnesAreDroppedOnSave() async throws {
        let client = ProfileUpdateSpy()
        let appState = AppState(apiClient: client, tokenStore: ScheduleInMemoryTokenStore())
        appState.updateVolunteerProfile(
            VolunteerProfileResponse(
                name: "张伟",
                availableTimeSlots: [
                    VolunteerAvailableTimeSlot(dayOfWeek: "SATURDAY", startTime: "07:00:00", endTime: "09:00:00"),
                    VolunteerAvailableTimeSlot(dayOfWeek: "SATURDAY", startTime: "18:00:00", endTime: "20:00:00", date: "2026-10-10"),
                    // 今天这一天的不算过期（后端按日期自然失效）。
                    VolunteerAvailableTimeSlot(dayOfWeek: "WEDNESDAY", startTime: "06:00:00", endTime: "07:00:00", date: "2026-10-07"),
                    VolunteerAvailableTimeSlot(dayOfWeek: "THURSDAY", startTime: "07:00:00", endTime: "09:00:00", date: "2026-10-01"),
                ]
            )
        )
        client.response = VolunteerProfileResponse(name: "张伟")

        let viewModel = VolunteerAvailabilityScheduleViewModel(today: { "2026-10-07" })
        viewModel.configure(with: appState)
        XCTAssertEqual(viewModel.slots.count, 3, "过期的一次性时段不该出现在列表里")
        XCTAssertEqual(viewModel.slots.map(\.dayText), ["周六", "仅 10月10日（周六）", "仅 10月7日（周三）"])
        await viewModel.save()

        let sent = try XCTUnwrap(client.lastProfileUpdate?.availableTimeSlots)
        XCTAssertEqual(sent.map(\.date), [nil, "2026-10-10", "2026-10-07"])
        XCTAssertEqual(sent.map(\.dayOfWeek), ["SATURDAY", "SATURDAY", "WEDNESDAY"])

        // 每周时段的请求体不带 `date` 键（与改动前逐字相同）；一次性的带。
        let json = String(decoding: try JSONEncoder().encode(sent), as: UTF8.self)
        XCTAssertEqual(json.components(separatedBy: "\"date\"").count - 1, 2, json)
        XCTAssertTrue(json.contains(#""date":"2026-10-10""#), json)
    }

    func testResponseDateDecodesAndExpiryIsByCalendarDay() throws {
        let slot = try JSONDecoder().decode(
            VolunteerAvailableTimeSlot.self,
            from: Data(#"{"dayOfWeek":"SATURDAY","date":"2026-10-03","startTime":"07:00:00","endTime":"09:00:00"}"#.utf8)
        )
        XCTAssertEqual(slot.date, "2026-10-03")
        XCTAssertFalse(slot.isExpired(today: "2026-10-03"))
        XCTAssertTrue(slot.isExpired(today: "2026-10-04"))
        let weekly = VolunteerAvailableTimeSlot(dayOfWeek: "SATURDAY", startTime: "07:00:00", endTime: "09:00:00")
        XCTAssertFalse(weekly.isExpired(today: "2099-01-01"), "每周时段永不过期")
    }

    /// 接单主页那一行：一次性的说日期，不说「周六」（说「周六早」= 告诉他每周六都会被邀请）。
    func testSummaryNamesTheDateForOneOffSlotsAndSkipsExpiredOnes() {
        let slots = [
            VolunteerAvailableTimeSlot(dayOfWeek: "THURSDAY", startTime: "07:00:00", endTime: "09:00:00", date: "2026-10-01"),
            VolunteerAvailableTimeSlot(dayOfWeek: "SATURDAY", startTime: "07:00:00", endTime: "09:00:00", date: "2026-10-10"),
            VolunteerAvailableTimeSlot(dayOfWeek: "WEDNESDAY", startTime: "19:00:00", endTime: "21:00:00"),
        ]
        XCTAssertEqual(VolunteerAvailabilitySlotSummary.text(for: slots, today: "2026-10-07"), "10月10日早、周三晚")
        XCTAssertEqual(VolunteerAvailabilitySlotSummary.fullText(for: slots[1]), "10月10日 07:00 – 09:00")
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
