import XCTest
@testable import blindRun

/// 「记录」列表按月分节、滑到底加载更早月份、月份栏（#829，负责人 2026-11-07 参考图）。
@MainActor
final class RunRecordHistorySectionsTests: XCTestCase {

    func testOlderMonthsAppendInOrderAndSkipMonthsWithoutRuns() async {
        let (viewModel, appState, records) = makeViewModel(withRuns: [month(2026, 11), month(2026, 9)])
        _ = appState

        await viewModel.load()
        XCTAssertEqual(viewModel.sections.map(\.month), [month(2026, 11)], "加载选中月份时不自动往下请求")

        await viewModel.loadOlderMonths()

        XCTAssertEqual(viewModel.sections.map(\.month), [month(2026, 11), month(2026, 9)], "10 月没跑，不该成节")
        XCTAssertEqual(records.requestedMonths, [month(2026, 11), month(2026, 10), month(2026, 9)])
        XCTAssertEqual(viewModel.olderCursor, month(2026, 8), "接上一节就停，等下次滑到底再请求")
        XCTAssertEqual(viewModel.allItems.count, 2, "转子与焦点用的条目要包含更早月份")
    }

    /// 2025 年 12 月与 11 月之间隔了 10 个空月：没到 12 个，必须接得上；之后连续 12 个空月才停。
    func testStopsOnlyAfterTwelveEmptyMonthsInARow() async {
        let (viewModel, appState, records) = makeViewModel(withRuns: [month(2026, 11), month(2025, 12)])
        _ = appState
        await viewModel.load()

        await viewModel.loadOlderMonths()
        XCTAssertEqual(viewModel.sections.map(\.month), [month(2026, 11), month(2025, 12)])

        await viewModel.loadOlderMonths()
        XCTAssertNil(viewModel.olderCursor, "连续 12 个月没记录就到底")
        XCTAssertEqual(records.requestedMonths.count, 1 + 11 + 12)
        XCTAssertEqual(records.requestedMonths.last, month(2024, 12))

        await viewModel.loadOlderMonths()
        XCTAssertEqual(records.requestedMonths.count, 24, "到底之后不再请求")
    }

    func testSelectedEmptyMonthCountsTowardTheTwelve() async {
        let (viewModel, appState, records) = makeViewModel(withRuns: [])
        _ = appState
        await viewModel.load()

        await viewModel.loadOlderMonths()

        XCTAssertEqual(records.requestedMonths.count, 12)
        XCTAssertTrue(viewModel.sections.isEmpty)
        XCTAssertNil(viewModel.olderCursor)
    }

    func testSwitchingMonthRestartsTheListFromTheNewMonth() async {
        let (viewModel, appState, records) = makeViewModel(withRuns: [month(2026, 11), month(2026, 9), month(2026, 8)])
        _ = appState
        await viewModel.load()
        await viewModel.loadOlderMonths()
        XCTAssertEqual(viewModel.sections.map(\.month), [month(2026, 11), month(2026, 9)])

        await viewModel.jump(to: month(2026, 10))

        XCTAssertEqual(viewModel.month, month(2026, 10))
        XCTAssertTrue(viewModel.sections.isEmpty, "10 月没跑；之前接上的 9 月要清掉，从新月份重新开始")
        XCTAssertEqual(viewModel.olderCursor, month(2026, 9))

        await viewModel.loadOlderMonths()
        XCTAssertEqual(viewModel.sections.map(\.month), [month(2026, 9)])
        XCTAssertEqual(Array(records.requestedMonths.suffix(2)), [month(2026, 10), month(2026, 9)])
    }

    func testCurrentMonthHasNoNextAndTheBarAlwaysShowsTheYear() async {
        let (viewModel, appState, records) = makeViewModel(withRuns: [month(2026, 11)])
        _ = appState
        await viewModel.load()

        XCTAssertFalse(viewModel.canShowNextMonth)
        XCTAssertEqual(viewModel.monthBarTitle, "2026年11月", "月份栏总带年份")
        XCTAssertEqual(viewModel.monthTitle, "11月", "首页汇总句仍是同年不带年份")

        await viewModel.jump(to: month(2026, 12))
        await viewModel.showNextMonth()
        XCTAssertEqual(records.requestedMonths, [month(2026, 11)], "比本月新的月份不请求")

        XCTAssertEqual(viewModel.pickerMonths.first, month(2026, 11))
        XCTAssertEqual(viewModel.pickerMonths.count, RunRecordHistoryViewModel.monthPickerSpan)
        XCTAssertEqual(viewModel.pickerMonths[2], month(2026, 9))
    }

    func testOlderMonthFailureStopsLoadingAndSaysSo() async {
        let (viewModel, appState, records) = makeViewModel(withRuns: [month(2026, 11)])
        _ = appState
        records.failingMonths = [month(2026, 10)]
        await viewModel.load()

        await viewModel.loadOlderMonths()

        XCTAssertNil(viewModel.olderCursor, "出错就别在底部一直转圈")
        XCTAssertNotNil(viewModel.partialFailure, "更早月份失败：已显示的记录留着，失败单独一格")
        XCTAssertNotNil(viewModel.history, "不能因为更早月份失败就把选中月份换成失败")
        XCTAssertEqual(viewModel.sections.map(\.month), [month(2026, 11)], "已显示的月份保留")
    }

    /// 更早月份的请求还在途时切了月份：旧请求回来要整份丢掉，不能接到新月份下面、也不能接着往下请求。
    func testOlderResultArrivingAfterAMonthSwitchIsDropped() async throws {
        let (viewModel, appState, records) = makeViewModel(withRuns: [month(2026, 11), month(2026, 9)])
        _ = appState
        records.holdFirstRequest(for: month(2026, 10))
        await viewModel.load()

        let older = Task { await viewModel.loadOlderMonths() }
        for _ in 0..<200 where !records.isHolding { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(records.isHolding, "10 月的请求没挂起，用例前提不成立")

        await viewModel.jump(to: month(2026, 10))
        XCTAssertEqual(viewModel.olderCursor, month(2026, 9))
        records.releaseHeld()
        await older.value

        XCTAssertTrue(viewModel.sections.isEmpty, "旧请求的结果不能接到新月份下面")
        XCTAssertFalse(records.requestedMonths.contains(month(2026, 9)), "旧请求作废后不该接着往下请求")
        XCTAssertFalse(viewModel.isLoadingOlder)
        XCTAssertEqual(viewModel.olderCursor, month(2026, 9), "新月份的断点不能被旧请求改掉")
    }

    // MARK: - Helpers

    private func month(_ year: Int, _ month: Int) -> RunRecordMonth {
        RunRecordMonth(year: year, month: month)
    }

    private func makeViewModel(
        withRuns months: Set<RunRecordMonth>
    ) -> (RunRecordHistoryViewModel, AppState, MonthlyRecordsStub) {
        let records = MonthlyRecordsStub(monthsWithRuns: months)
        let orders = FakeOrderService()
        orders.myOrdersResult = .success(PagedOrderResponse(
            content: [], totalElements: 0, totalPages: 1, number: 0, size: 1, first: true, last: true, empty: true
        ))
        // view model 对 AppState 是 weak，调用方必须持有。
        let appState = AppState(orders: orders, tokenStore: SectionsTokenStore())
        appState.userId = 7
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 12))!
        let viewModel = RunRecordHistoryViewModel(role: .runner, now: now)
        viewModel.configure(with: appState, speechService: nil, runRecord: records)
        return (viewModel, appState, records)
    }
}

// MARK: - Stubs

/// 按月份回数据：`monthsWithRuns` 里的月份各有一条记录，其余月份为空。
private final class MonthlyRecordsStub: RunRecordServing, @unchecked Sendable {
    struct NotStubbed: Error {}
    let monthsWithRuns: Set<RunRecordMonth>
    var failingMonths: Set<RunRecordMonth> = []
    private(set) var requestedMonths: [RunRecordMonth] = []
    private let lock = NSLock()
    private var heldMonth: RunRecordMonth?
    private var held: CheckedContinuation<Void, Never>?

    /// 这个月的第一次请求挂起，直到 `releaseHeld()`；之后的请求照常返回。
    func holdFirstRequest(for month: RunRecordMonth) {
        lock.withLock { heldMonth = month }
    }

    var isHolding: Bool { lock.withLock { held != nil } }

    func releaseHeld() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            defer { held = nil }
            return held
        }
        continuation?.resume()
    }

    init(monthsWithRuns: Set<RunRecordMonth>) {
        self.monthsWithRuns = monthsWithRuns
    }

    func record(orderId: Int64) async throws -> RunRecordResponse { throw NotStubbed() }

    func monthlyRecords(year: Int, month: Int) async throws -> RunRecordHistoryResponse {
        let target = RunRecordMonth(year: year, month: month)
        requestedMonths.append(target)
        let shouldHold = lock.withLock { () -> Bool in
            guard heldMonth == target else { return false }
            heldMonth = nil
            return true
        }
        if shouldHold {
            await withCheckedContinuation { continuation in lock.withLock { held = continuation } }
        }
        if failingMonths.contains(target) { throw URLError(.notConnectedToInternet) }
        let items = monthsWithRuns.contains(target)
            ? [RunHistoryItem(
                orderId: Int64(year * 100 + month),
                finishedAt: String(format: "%04d-%02d-06T07:00:00", year, month),
                place: "深圳湾公园",
                partnerName: nil,
                distanceM: 1_040,
                thumbnail: nil
            )]
            : []
        return RunRecordHistoryResponse(
            role: .blind,
            month: String(format: "%04d-%02d", year, month),
            monthSummary: RunMonthSummary(runs: items.count, distanceM: items.isEmpty ? nil : 1_040, serviceMin: nil, topPartner: nil),
            items: items
        )
    }

    func postMessage(orderId: Int64, text: String) async throws -> RunRecordMessageResponse { throw NotStubbed() }
}

private final class SectionsTokenStore: TokenStoring, @unchecked Sendable {
    private var token: String?
    func save(_ token: String) { self.token = token }
    func read() -> String? { token }
    func delete() { token = nil }
}
