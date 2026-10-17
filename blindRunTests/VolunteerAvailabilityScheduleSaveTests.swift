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

    // MARK: - 按日期添加（iOS #455）

    /// 后端规则：给了 `date`，`dayOfWeek` 必须是那天的星期几，否则 400。
    /// 预选值是周六，挑 10-20（周二）就能分出「星期跟着日期走」与「星期停在预选的周六」。
    func testOneOffRequestBodyDerivesDayOfWeekFromTheDate() throws {
        var slot = VolunteerAvailabilityDraftSlot.makeOneOffDefault(today: "2026-10-17")
        XCTAssertEqual(slot.weekday, "SATURDAY", "2026-10-17 是周六")
        slot.setDate("2026-10-20")
        XCTAssertEqual(slot.dayText, "仅 10月20日（周二）")

        let json = String(decoding: try JSONEncoder().encode(slot.payload), as: UTF8.self)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: String], json)
        XCTAssertEqual(body, [
            "dayOfWeek": "TUESDAY",
            "date": "2026-10-20",
            "startTime": "07:00:00",
            "endTime": "09:00:00",
        ])

        // 即使有代码只改了 `date` 没改 `weekday`，发出去的星期仍由日期推出。
        var stale = VolunteerAvailabilityDraftSlot(weekday: "SATURDAY", startMinutes: 420, endMinutes: 540)
        stale.date = "2026-10-19"
        XCTAssertEqual(stale.payload.dayOfWeek, "MONDAY")

        XCTAssertEqual(
            ["2026-10-18", "2026-10-21", "2026-10-22", "2026-10-23", "2026-02-28", "2028-02-29"]
                .map { VolunteerAvailabilityScheduleEditing.weekday(forDate: $0) },
            ["SUNDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "TUESDAY"]
        )
        XCTAssertNil(VolunteerAvailabilityScheduleEditing.weekday(forDate: "2026-02-30"))
        XCTAssertNil(VolunteerAvailabilityScheduleEditing.weekday(forDate: "10/20"))
    }

    /// 能选的日期从今天开始，没有过去的一天；跨月跨年连续。
    func testSelectableDatesStartTodayAndNeverIncludeThePast() {
        let viewModel = VolunteerAvailabilityScheduleViewModel(today: { "2026-12-31" })
        let options = viewModel.selectableOneOffDates()
        XCTAssertEqual(options.count, VolunteerAvailabilityScheduleEditing.oneOffDateWindowDays)
        XCTAssertEqual(options.first, "2026-12-31", "第一个可选日期必须是今天")
        XCTAssertEqual(Array(options.prefix(3)), ["2026-12-31", "2027-01-01", "2027-01-02"])
        XCTAssertEqual(options.last, "2027-01-29")
        XCTAssertTrue(options.allSatisfy { $0 >= "2026-12-31" }, "出现了过去的日期：\(options)")
        XCTAssertEqual(Set(options).count, options.count, "日期有重复")
        XCTAssertEqual(viewModel.makeOneOffDraft().date, "2026-12-31", "预选日期必须在可选范围内")

        XCTAssertEqual(
            VolunteerAvailabilityScheduleEditing.selectableOneOffDates(today: "2028-02-28", count: 3),
            ["2028-02-28", "2028-02-29", "2028-03-01"]
        )
    }

    /// 新增一段一次性时段后整体 PUT：已有的每周 / 一次性时段原样带回，过期的不带。
    func testAddingAOneOffSlotKeepsExistingSlotsIntactOnSave() async throws {
        let client = ProfileUpdateSpy()
        let appState = AppState(apiClient: client, tokenStore: ScheduleInMemoryTokenStore())
        appState.updateVolunteerProfile(
            VolunteerProfileResponse(
                name: "张伟",
                availableTimeSlots: [
                    VolunteerAvailableTimeSlot(dayOfWeek: "SATURDAY", startTime: "07:00:00", endTime: "09:00:00"),
                    VolunteerAvailableTimeSlot(dayOfWeek: "SATURDAY", startTime: "18:00:00", endTime: "20:00:00", date: "2026-10-24"),
                    VolunteerAvailableTimeSlot(dayOfWeek: "THURSDAY", startTime: "07:00:00", endTime: "09:00:00", date: "2026-10-15"),
                ]
            )
        )
        client.response = VolunteerProfileResponse(name: "张伟")

        let viewModel = VolunteerAvailabilityScheduleViewModel(today: { "2026-10-17" })
        viewModel.configure(with: appState)
        var added = viewModel.makeOneOffDraft()
        added.setDate("2026-10-20")
        added.startMinutes = 6 * 60
        added.endMinutes = 7 * 60
        viewModel.add(added)
        await viewModel.save()

        let sent = try XCTUnwrap(client.lastProfileUpdate?.availableTimeSlots)
        XCTAssertEqual(sent.map(\.date), [nil, "2026-10-24", "2026-10-20"])
        XCTAssertEqual(sent.map(\.dayOfWeek), ["SATURDAY", "SATURDAY", "TUESDAY"])
        XCTAssertEqual(sent.map(\.startTime), ["07:00:00", "18:00:00", "06:00:00"])
        XCTAssertEqual(sent.map(\.endTime), ["09:00:00", "20:00:00", "07:00:00"])
        XCTAssertEqual(client.lastProfileUpdate?.name, "张伟")
        XCTAssertEqual(viewModel.slots.map(\.dayText), ["周六", "仅 10月24日（周六）", "仅 10月20日（周二）"])
        XCTAssertNil(viewModel.errorMessage)
    }

    /// 本机日历是佛历 / 日本历时，「今天」仍是公历串 —— 它会被原样当作 `date` 发给后端。
    func testTodayIsAGregorianDayEvenOnANonGregorianDevice() throws {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        // 2026-10-17 01:00 北京时间 = 2026-10-16 17:00 UTC：同时钉住「按本机时区取日」。
        let now = Date(timeIntervalSince1970: 1_792_170_000)
        XCTAssertEqual(VolunteerAvailableTimeSlot.todayString(now: now, calendar: buddhist), "2026-10-17")
        var japanese = Calendar(identifier: .japanese)
        japanese.timeZone = buddhist.timeZone
        XCTAssertEqual(VolunteerAvailableTimeSlot.todayString(now: now, calendar: japanese), "2026-10-17")
    }

    /// 页脚的匹配规则：没有每周时段 = 随时可接（后端 #410），只填了按日期的也一样。
    func testFooterOnlyPromisesNoInvitesOutsideSlotsWhenAWeeklySlotExists() {
        let weekly = VolunteerAvailabilityDraftSlot.makeDefault()
        let oneOff = VolunteerAvailabilityDraftSlot.makeOneOffDefault(today: "2026-10-17")
        let strict = "空闲时间以外不会给你发邀请。"
        XCTAssertTrue(VolunteerAvailabilityScheduleEditing.footerText(for: [weekly, oneOff]).hasPrefix(strict))
        XCTAssertFalse(VolunteerAvailabilityScheduleEditing.footerText(for: [oneOff]).contains(strict))
        XCTAssertFalse(VolunteerAvailabilityScheduleEditing.footerText(for: []).contains(strict))
        XCTAssertTrue(VolunteerAvailabilityScheduleEditing.footerText(for: [oneOff]).contains("任何时间都可能收到邀请"))
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
