import CoreLocation
import EventKit
import UIKit
import XCTest
@testable import blindRun

/// #660 约跑前后的七条（OpenSpec `close-blind-pre-run-gaps`）：评分默认值、等待播报、
/// 开跑提醒与日历、出发地点提醒、低电量。B-13 没有代码改动，不在这里。
@MainActor
final class BlindPreRunGapsTests: XCTestCase {

    // MARK: - B-5（「记录」里的「待进行的预约」11-07 按负责人要求删了，#823 第二轮）

    /// 两张进行中的预约既不进「未完成的预约」，加载播报也不再提（旧实现以「有 2 张待进行的预约」开头）。
    /// 首页多张预约另立 #825。
    func testRunnerRecordsNeitherListNorAnnounceActiveBookings() async {
        let orders = FakeOrderService()
        orders.myOrdersResult = .success(Self.page([
            Self.order(id: 7, status: .scheduledConfirmed, start: "2026-11-06T07:00:00"),
            Self.order(id: 8, status: .pendingMatch, start: "2026-11-07T07:00:00"),
        ]))
        let appState = AppState(orders: orders, tokenStore: PreRunInMemoryTokenStore())
        let viewModel = RunRecordHistoryViewModel(role: .runner)
        viewModel.configure(with: appState, speechService: SpeechService(), runRecord: PreRunEmptyRunRecords())

        await viewModel.load()

        XCTAssertTrue(viewModel.unfinished.isEmpty, "进行中的预约不是「未完成的预约」")
        XCTAssertFalse(viewModel.loadedAnnouncement.contains("待进行的预约"), viewModel.loadedAnnouncement)
    }

    /// 默认每页 10 条时，活跃单可能被后来下又取消的单挤到第二页。
    func testMyOrdersAsksForAPageLargeEnoughForEveryActiveOrder() async throws {
        let transport = RecordingTransport()
        transport.nextResponse = Self.page([])

        _ = try await OrderService(transport: transport).myOrders()

        let recorded = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(recorded.path, "/api/orders/mine")
        XCTAssertEqual(recorded.query?["size"], "50")
    }

    // MARK: - B-30 评分默认不选

    func testRatingStartsUnselectedAndSubmittingWithoutAChoiceIsRefusedAloud() async {
        let orders = FakeOrderService()
        let appState = AppState(orders: orders, tokenStore: PreRunInMemoryTokenStore())
        let speech = SpeechService()
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: speech)
        viewModel.order = Self.order(id: 9, status: .completed, start: nil)

        XCTAssertNil(viewModel.reviewRating, "默认不选：默认「很顺利」会让直接提交的差评被盖掉")
        await viewModel.submitReview()

        XCTAssertNil(orders.lastReviewRequest, "没选就不许发评价请求")
        XCTAssertFalse(viewModel.didSubmitReview)
        XCTAssertEqual(viewModel.errorMessage, RunExperienceRating.missingSelectionMessage)
        XCTAssertTrue(speech.spokenHistoryForTesting.contains(RunExperienceRating.missingSelectionMessage))
    }

    func testRatingSubmitsTheChosenValue() async {
        let orders = FakeOrderService()
        let appState = AppState(orders: orders, tokenStore: PreRunInMemoryTokenStore())
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: SpeechService())
        viewModel.order = Self.order(id: 9, status: .completed, start: nil)
        viewModel.reviewRating = RunExperienceRating.bad.rawValue

        await viewModel.submitReview()

        XCTAssertEqual(orders.lastReviewRequest?.rating, 2)
    }

    // MARK: - B-26 等待匹配的定时播报

    func testMatchingWaitCueSaysHowLongOnlyWhileStillLooking() {
        let now = Date()
        let placed = DateFormatter.aidRunBackendLocalDateTime.string(from: now.addingTimeInterval(-5 * 60))
        let waiting = Self.order(id: 1, status: .pendingMatch, start: nil, createdAt: placed)

        XCTAssertEqual(MatchingWaitCue.text(for: waiting, now: now), "系统还在为你找陪跑员，已等待 5 分钟。有人接单会马上告诉你。")
        XCTAssertNotNil(MatchingWaitCue.text(for: Self.order(id: 2, status: .rematching, start: nil, createdAt: placed), now: now))
        XCTAssertNil(MatchingWaitCue.text(for: Self.order(id: 3, status: .scheduledConfirmed, start: nil, createdAt: placed), now: now))
        XCTAssertNil(MatchingWaitCue.text(for: Self.order(id: 4, status: .pendingIntroCall, start: nil, createdAt: placed), now: now))
    }

    /// 定时那一句不许切断别的话：状态推进（默认档）、用户按的「重复当前状态」（按需档）正在念时，它只能排队。
    /// 换成默认档的话同档会直接打断（`AnnouncementQueue` 头注释「同档 = 打断」），这条会红。
    func testMatchingWaitCueNeverInterruptsAnotherAnnouncement() {
        for speaking in [AnnouncementPriority.counterpartAction, .onDemand, .alert] {
            var queue = AnnouncementQueue()
            let cue = PendingAnnouncement(text: "还在找", priority: MatchingWaitCue.priority, enqueuedAt: Date())
            XCTAssertEqual(queue.submit(cue, speaking: speaking, isCallActive: false), .enqueued, "\(speaking)")
        }
    }

    // MARK: - F-16 低电量

    func testLowBatteryWarnsAtTwentyPercentNearTheStartOnly() {
        let now = Date()
        let soon = DateFormatter.aidRunBackendLocalDateTime.string(from: now.addingTimeInterval(60 * 60))
        let later = DateFormatter.aidRunBackendLocalDateTime.string(from: now.addingTimeInterval(3 * 60 * 60))
        let confirmedSoon = Self.order(id: 1, status: .scheduledConfirmed, start: soon)
        let running = Self.order(id: 2, status: .inProgress, start: nil)

        XCTAssertEqual(
            LowBatteryCue.warning(level: 0.20, state: .unplugged, order: confirmedSoon, now: now),
            "手机电量只剩百分之20。陪跑时要靠这台手机求助和定位，请尽快充电，或带上充电宝。"
        )
        XCTAssertNil(LowBatteryCue.warning(level: 0.21, state: .unplugged, order: confirmedSoon, now: now), "阈值是 ≤20%")
        XCTAssertNil(LowBatteryCue.warning(level: 0.10, state: .charging, order: running, now: now), "在充电不提醒")
        XCTAssertNil(LowBatteryCue.warning(level: -1, state: .unknown, order: running, now: now), "读不到电量不提醒")
        XCTAssertNotNil(LowBatteryCue.warning(level: 0.15, state: .unplugged, order: running, now: now))
        XCTAssertNil(
            LowBatteryCue.warning(level: 0.15, state: .unplugged, order: Self.order(id: 3, status: .scheduledConfirmed, start: later), now: now),
            "离开始还有 3 小时，现在提醒到出发时电量早变了"
        )
        XCTAssertNil(LowBatteryCue.warning(level: 0.15, state: .unplugged, order: Self.order(id: 4, status: .completed, start: soon), now: now))
    }

    func testLowBatteryWarnsOncePerOrder() {
        let ledger = LowBatteryCueLedger()
        XCTAssertTrue(ledger.claim(orderId: 1))
        XCTAssertFalse(ledger.claim(orderId: 1), "首页与订单页同时活着，靠这本账只念一次")
        XCTAssertTrue(ledger.claim(orderId: 2))
    }

    // MARK: - Fixtures

    static func order(
        id: Int64,
        status: RunOrderStatus,
        start: String?,
        createdAt: String? = "2026-11-04T10:00:00",
        startAddress: String? = "朝阳公园南门"
    ) -> OrderDetailResponse {
        OrderDetailResponse(
            orderId: id, status: status, startAddress: startAddress, startLatitude: 39.9342, startLongitude: 116.4740,
            endAddress: nil, endLatitude: nil, endLongitude: nil, plannedStart: start, plannedEnd: nil,
            blindName: nil, blindPhone: nil, volunteerPhone: nil, acceptedAt: nil, createdAt: createdAt,
            expectedDurationMinutes: 45, pacePreference: nil, routePreference: nil, routeNotes: nil,
            hasGuideDogThisRun: nil, specialNotes: nil, visionLevel: nil, tetherPreference: nil, chatPreference: nil
        )
    }

    static func page(_ orders: [OrderDetailResponse]) -> PagedOrderResponse {
        PagedOrderResponse(
            content: orders, totalElements: Int64(orders.count), totalPages: 1, number: 0,
            size: 50, first: true, last: true, empty: orders.isEmpty
        )
    }
}

/// 开跑提醒、日历、出发地点提醒。与上面拆开只为类体长度（SwiftLint `type_body_length`）。
@MainActor
final class BlindPreRunReminderTests: XCTestCase {

    // MARK: - B-18 本机开跑提醒

    func testReminderIsOneHourBeforeAConfirmedFutureStartWithoutTheAddress() throws {
        let now = Date()
        let start = now.addingTimeInterval(3 * 60 * 60)
        let wire = DateFormatter.aidRunBackendLocalDateTime.string(from: start)
        let orders = [
            BlindPreRunGapsTests.order(id: 1, status: .scheduledConfirmed, start: wire),
            BlindPreRunGapsTests.order(id: 2, status: .pendingAccept, start: wire),
            BlindPreRunGapsTests.order(id: 3, status: .pendingMatch, start: wire),
            BlindPreRunGapsTests.order(id: 4, status: .cancelled, start: wire),
            BlindPreRunGapsTests.order(
                id: 5, status: .scheduledConfirmed,
                start: DateFormatter.aidRunBackendLocalDateTime.string(from: now.addingTimeInterval(40 * 60))
            ),
        ]

        let reminders = BlindRunStartReminder.reminders(from: orders, now: now)

        XCTAssertEqual(reminders.map(\.orderId), [1, 2], "还在找人、已取消、提醒时刻已过的都不排")
        let first = try XCTUnwrap(reminders.first)
        let expectedFire = try XCTUnwrap(wire.backendTimestamp).addingTimeInterval(-60 * 60)
        XCTAssertEqual(first.fireDate, expectedFire)
        XCTAssertFalse(first.body.contains("朝阳公园"), "锁屏谁都看得见，正文不写出发地点")
        XCTAssertEqual(first.identifier, "blindRunStartReminder-1")
        XCTAssertTrue(first.body.hasPrefix("1 小时后"), "正文的提前量与触发时刻同源：\(first.body)")
    }

    func testReminderSyncReplacesTheSetAndLeavesItAloneWhenTheListFails() async {
        let orders = FakeOrderService()
        let scheduler = RecordingReminderScheduler()
        let start = DateFormatter.aidRunBackendLocalDateTime.string(from: Date().addingTimeInterval(5 * 60 * 60))
        orders.myOrdersResult = .success(BlindPreRunGapsTests.page([
            BlindPreRunGapsTests.order(id: 1, status: .scheduledConfirmed, start: start),
        ]))

        let synced = await BlindRunStartReminderSync.refresh(using: orders, scheduler: scheduler)
        XCTAssertTrue(synced)
        XCTAssertEqual(scheduler.replacements.map { $0.map(\.orderId) }, [[1]])

        orders.myOrdersResult = .failure(URLError(.notConnectedToInternet))
        let failed = await BlindRunStartReminderSync.refresh(using: orders, scheduler: scheduler)
        XCTAssertFalse(failed, "失败要让调用方知道，首页才不会把这次记成已同步")
        XCTAssertEqual(scheduler.replacements.count, 1, "拉失败不动：撤掉的话网络一抖就把提醒全删了")
    }

    // MARK: - B-18 加入日历

    func testCalendarExportOnlyForAConfirmedFutureRunAndFillsTheEvent() throws {
        let now = Date()
        let wire = DateFormatter.aidRunBackendLocalDateTime.string(from: now.addingTimeInterval(24 * 60 * 60))
        let confirmed = BlindPreRunGapsTests.order(id: 1, status: .scheduledConfirmed, start: wire)

        XCTAssertTrue(BlindRunCalendarExport.canExport(confirmed, now: now))
        XCTAssertFalse(BlindRunCalendarExport.canExport(BlindPreRunGapsTests.order(id: 2, status: .pendingMatch, start: wire), now: now))
        XCTAssertFalse(BlindRunCalendarExport.canExport(BlindPreRunGapsTests.order(id: 3, status: .scheduledConfirmed, start: nil), now: now))

        let event = try XCTUnwrap(BlindRunCalendarExport.makeEvent(for: confirmed, in: EKEventStore()))
        let start = try XCTUnwrap(wire.backendTimestamp)
        XCTAssertEqual(event.startDate, start)
        XCTAssertEqual(event.endDate, start.addingTimeInterval(45 * 60), "没有 plannedEnd 时按预计时长")
        XCTAssertEqual(event.location, "朝阳公园南门")
        XCTAssertEqual(event.alarms?.first?.relativeOffset, -60 * 60)
        XCTAssertTrue(event.notes?.contains("不会跟着变") == true, "日程不随订单变，要告诉用户自己删")
    }

    // MARK: - F-14 出发地点提醒

    func testStartPlacePrivacyNoticeOnlyForTheDeviceLocationAndSpokenOnce() async {
        let location = LocationService()
        location.simulateDeviceLocationForTesting(
            CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737), capturedAt: Date(), horizontalAccuracy: 10
        )
        location.simulatePreciseLocationOffForTesting(false)
        let viewModel = BlindBookingViewModel()
        viewModel.configureForTesting(speechService: SpeechService(), locationService: location)
        await viewModel.refreshCurrentLocation()

        XCTAssertEqual(viewModel.resolvedStartPlace?.source, .deviceLocation, "前提：起点来自当前位置")
        XCTAssertEqual(viewModel.startPointPrivacyNotice, "出发地点会发给附近的候选陪跑员，建议约在公共地点，不要约在家门口。")
        XCTAssertEqual(viewModel.consumeStartPointPrivacySpeech(), BlindBookingViewModel.startPointPrivacyNotice)
        XCTAssertEqual(viewModel.consumeStartPointPrivacySpeech(), "", "读回每改一项重念一遍，这句只念第一遍")

        viewModel.selectedStartPlace = ResolvedPlace(
            id: "poi-1", title: "人民广场", addressText: "上海市黄浦区人民广场",
            latitude: 31.2304, longitude: 121.4737, source: .manual
        )
        XCTAssertNil(viewModel.startPointPrivacyNotice, "用户自己挑的地点不再提醒")
    }
}

// MARK: - Stubs

private final class RecordingReminderScheduler: BlindRunStartReminderScheduling {
    private(set) var replacements: [[BlindRunStartReminder]] = []
    func replaceAll(with reminders: [BlindRunStartReminder]) async { replacements.append(reminders) }
}

private final class PreRunEmptyRunRecords: RunRecordServing, @unchecked Sendable {
    struct NotStubbed: Error {}
    func record(orderId: Int64) async throws -> RunRecordResponse { throw NotStubbed() }
    func monthlyRecords(year: Int, month: Int) async throws -> RunRecordHistoryResponse {
        RunRecordHistoryResponse(
            role: .blind, month: "2026-11",
            monthSummary: RunMonthSummary(runs: 0, distanceM: nil, serviceMin: nil, topPartner: nil), items: []
        )
    }
    func postMessage(orderId: Int64, text: String) async throws -> RunRecordMessageResponse { throw NotStubbed() }
}

private final class PreRunInMemoryTokenStore: TokenStoring, @unchecked Sendable {
    private var token: String?
    func save(_ token: String) { self.token = token }
    func read() -> String? { token }
    func delete() { token = nil }
}
