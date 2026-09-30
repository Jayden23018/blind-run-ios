import XCTest
@testable import blindRun

/// #236：后端把无偏移的 `LocalDateTime` 一律按北京时间解释，客户端不许跟着设备时区走。
///
/// **每条用例都先把进程时区切到美西**再断言。开发机和真机都在东八区，不切的话，
/// 这些断言在「修了」和「没修」两种实现下都是绿的 —— 用例就分辨不出问题。
/// 时间锚点：`instant` = 2026-09-30 00:00:00 UTC = 北京 08:00 = 美西（PDT）前一天 17:00。
@MainActor
final class BackendTimeZoneTests: XCTestCase {
    private var savedZone: TimeZone!
    private let instant = Date(timeIntervalSince1970: 1_790_726_400)

    override func setUp() {
        super.setUp()
        savedZone = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "America/Los_Angeles")!
    }

    override func tearDown() {
        NSTimeZone.default = savedZone
        super.tearDown()
    }

    func testFormatsAnInstantAsBeijingWallClockWhateverTheDeviceZone() {
        XCTAssertEqual(
            DateFormatter.aidRunBackendLocalDateTime.string(from: instant),
            "2026-09-30T08:00:00"
        )
    }

    func testParsesTheBackendStringAsBeijingWallClockWhateverTheDeviceZone() {
        XCTAssertEqual(DateFormatter.aidRunBackendLocalDateTime.date(from: "2026-09-30T08:00:00"), instant)
        XCTAssertEqual("2026-09-30T08:00:00".backendLocalDate, instant)
    }

    /// 原始现象：美西手机选一个未来的时间，发出去的串在后端看来是十几小时之前，下单回 400。
    func testBookingRequestCarriesBeijingTimeForADeviceInTheUSWest() throws {
        let viewModel = BlindBookingViewModel()
        viewModel.applyVoiceResolvedStartPlace(
            address: "上海市黄浦区人民广场",
            spokenAddress: "人民广场",
            latitude: 31.2304,
            longitude: 121.4737
        )
        viewModel.appointmentTime = instant
        viewModel.duration = .sixty

        let request = try XCTUnwrap(viewModel.makeCreateOrderRequest())

        XCTAssertEqual(request.plannedStartTime, "2026-09-30T08:00:00")
        XCTAssertEqual(request.plannedEndTime, "2026-09-30T09:00:00")
    }

    /// 夜间窗口 `[22:00, 05:00)` 是后端按北京时间的钟点判的。
    /// 北京 15:00–16:00 在美西是 00:00–01:00（夜里）：拿设备日历判会误拒，拿北京日历判才对。
    func testNightWindowIsJudgedOnTheBeijingClockNotTheDeviceClock() {
        let beijing15 = instant.addingTimeInterval(7 * 3600)
        XCTAssertFalse(
            BlindBookingViewModel.overlapsNightWindow(start: beijing15, end: beijing15.addingTimeInterval(3600)),
            "北京下午 3 点不是夜间，不该因为设备在美西（那里是半夜）被拦"
        )
        let beijing21 = instant.addingTimeInterval(13 * 3600)
        XCTAssertTrue(
            BlindBookingViewModel.overlapsNightWindow(start: beijing21, end: beijing21.addingTimeInterval(90 * 60)),
            "北京 21:00–22:30 尾巴进了夜间，在美西设备上也必须拒（与后端一致）"
        )
    }
}
