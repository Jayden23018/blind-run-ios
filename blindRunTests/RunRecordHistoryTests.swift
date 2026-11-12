import XCTest
@testable import blindRun

/// 两端「记录」tab（`RunRecordHistoryViewModel`，OpenSpec `add-run-record-history-tab`）。
///
/// 取代了 `BlindRunHistoryTests`：那一版守的「收全部终态、时间倒序、未知状态不当已结束」
/// 现在只剩「未完成的预约」那一组还从 `/api/orders/mine` 来，对应的断言挪到了下面第一组。
@MainActor
final class RunRecordHistoryTests: XCTestCase {

    // MARK: - 数据来源

    func testUnfinishedGroupKeepsOnlyCancelledAndNoVolunteerNewestFirst() async {
        let (viewModel, appState, _, _) = makeViewModel(orders: [
            makeOrder(orderId: 1, status: .completed, createdAt: "2026-08-01T10:00:00"),
            makeOrder(orderId: 2, status: .cancelled, createdAt: "2026-08-02T10:00:00"),
            makeOrder(orderId: 3, status: .inProgress, createdAt: "2026-08-03T10:00:00"),
            makeOrder(orderId: 4, status: .noVolunteer, createdAt: "2026-08-04T10:00:00"),
            makeOrder(orderId: 9, status: .unknown, createdAt: "2026-08-09T10:00:00"),
        ])
        _ = appState

        await viewModel.load()

        XCTAssertEqual(
            viewModel.unfinished.map(\.orderId), [4, 2],
            "已完成的走月度列表；进行中由首页管；未知状态不能被当成「已经结束了」"
        )
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadAsksForTheCurrentMonthAndKeepsTheBackendOrder() async {
        let (viewModel, appState, records, _) = makeViewModel(
            now: date(2026, 9, 24),
            history: makeHistory(items: [makeItem(orderId: 7), makeItem(orderId: 5)])
        )
        _ = appState

        await viewModel.load()

        XCTAssertEqual(records.requestedMonths, [RunRecordMonth(year: 2026, month: 9)])
        XCTAssertEqual(viewModel.history?.items.map(\.orderId), [7, 5], "后端按完成时间倒序，客户端不再排")
    }

    // MARK: - 月份切换

    func testPreviousMonthCrossesTheYearBoundaryAndLeavesTheUnfinishedGroupAlone() async {
        let (viewModel, appState, records, orders) = makeViewModel(now: date(2026, 1, 10))
        _ = appState
        await viewModel.load()
        XCTAssertFalse(viewModel.canShowNextMonth, "当月之后没有记录可看")

        await viewModel.showPreviousMonth()

        XCTAssertEqual(records.requestedMonths.last, RunRecordMonth(year: 2025, month: 12))
        XCTAssertEqual(viewModel.monthTitle, "2025年12月", "跨年要带年份，否则会被听成今年的 12 月")
        XCTAssertTrue(viewModel.canShowNextMonth)
        XCTAssertEqual(orders.callCount("myOrders()"), 1, "切月份只重读月度列表")

        await viewModel.showNextMonth()
        XCTAssertEqual(records.requestedMonths.last, RunRecordMonth(year: 2026, month: 1))
        XCTAssertEqual(viewModel.monthTitle, "1月")
    }

    func testNextMonthDoesNothingOnTheCurrentMonth() async {
        let (viewModel, appState, records, _) = makeViewModel(now: date(2026, 9, 24))
        _ = appState
        await viewModel.load()

        await viewModel.showNextMonth()

        XCTAssertEqual(records.requestedMonths.count, 1)
        XCTAssertEqual(viewModel.month, RunRecordMonth(year: 2026, month: 9))
    }

    // MARK: - 汇总句

    func testRunnerSummaryDropsTheDistanceClauseWhenDistanceIsNull() async {
        let (viewModel, appState, records, _) = makeViewModel(
            now: date(2026, 9, 24),
            history: makeHistory(runs: 5, distanceM: 22_540)
        )
        _ = appState
        await viewModel.load()
        XCTAssertEqual(viewModel.summaryText(), "9月跑了 5 次，一共 22.5 公里。")
        // 汇总卡的彩色数字格（#823）：跑步 N 次 + 距离。距离与汇总句同一位小数（#846 D8）。
        XCTAssertEqual(viewModel.summaryCells.map(\.label), ["跑步", "距离"])
        XCTAssertEqual(viewModel.summaryCells.map(\.value), ["5", "22.5"])

        records.result = .success(makeHistory(runs: 5, distanceM: nil))
        await viewModel.load()
        XCTAssertEqual(viewModel.summaryText(), "9月跑了 5 次。", "没有数据是整句不说，不是「一共 0.00 公里」")
        XCTAssertEqual(viewModel.summaryCells.map(\.label), ["跑步"], "没有距离那一格整格不出现")
    }

    /// 负责人 11-07：列表不写和谁一起跑 —— 汇总句不再说「其中和陈跑了 3 次」。
    func testVolunteerSummaryReadsServiceTimeButNotThePartner() async {
        let (viewModel, appState, records, _) = makeViewModel(
            role: .volunteer,
            now: date(2026, 9, 24),
            history: makeHistory(runs: 4, distanceM: 18_210, serviceMin: 220, topPartner: RunTopPartner(name: "陈*", runs: 3))
        )
        _ = appState
        await viewModel.load()

        XCTAssertEqual(viewModel.summaryText(), "9月陪跑 4 次，服务 3 小时 40 分钟。")
        XCTAssertEqual(viewModel.summaryText(spoken: true), "9月陪跑 4 次，服务 3 小时 40 分钟。")
        XCTAssertEqual(viewModel.summaryCells.map(\.label), ["陪跑", "距离", "服务"])
        // #981：服务时长拆成「数字大字 / 单位小字」交替的几段，整串用大字时并排放不下会被折成三行。
        let service = viewModel.summaryCells[2].valueRuns
        XCTAssertEqual(service.map(\.text), ["3", "小时", "40", "分钟"])
        XCTAssertEqual(service.map(\.isNumber), [true, false, true, false])
        XCTAssertEqual(viewModel.summaryCells[1].valueRuns.map(\.text), ["18.2"], "公里数是一整段，单位另在 unit 里")

        records.result = .success(makeHistory(runs: 4, distanceM: nil, serviceMin: nil, topPartner: RunTopPartner(name: nil, runs: 3)))
        await viewModel.load()
        XCTAssertEqual(viewModel.summaryText(), "9月陪跑 4 次。", "服务时长为 null、搭档已注销时整段不说")
    }

    func testEmptyMonthSaysSoInTheSummary() async {
        let (viewModel, appState, _, _) = makeViewModel(role: .volunteer, now: date(2026, 9, 24), history: makeHistory(runs: 0))
        _ = appState
        await viewModel.load()
        XCTAssertEqual(viewModel.summaryText(), "9月还没有陪跑记录。")
    }

    // MARK: - 空状态

    func testFirstRunCopyOnlyWhenTheUserHasNeverCompletedAnOrder() async {
        let (never, appState1, _, _) = makeViewModel(orders: [
            makeOrder(orderId: 2, status: .cancelled, createdAt: "2026-08-02T10:00:00"),
        ])
        _ = appState1
        await never.load()
        XCTAssertTrue(never.showsFirstRunEmptyState)
        XCTAssertEqual(never.emptyStateCopy.message, "完成第一次陪跑后，记录会出现在这里。")

        let (returning, appState2, _, _) = makeViewModel(orders: [
            makeOrder(orderId: 1, status: .completed, createdAt: "2026-07-01T10:00:00"),
        ])
        _ = appState2
        await returning.load()
        XCTAssertFalse(returning.showsFirstRunEmptyState, "只是这个月空，不是从没跑过")

        let (unknown, appState3, _, _) = makeViewModel(ordersFailure: APIError.invalidURL)
        _ = appState3
        await unknown.load()
        XCTAssertFalse(unknown.showsFirstRunEmptyState, "订单没读到时不知道跑没跑过，不能把老用户当新人")
    }

    /// 11-04（#685）起陪跑员空状态不再提「开启可服务状态」，两端说同一句。
    func testVolunteerFirstRunCopySaysWhereRecordsAppear() {
        let viewModel = RunRecordHistoryViewModel(role: .volunteer)
        XCTAssertEqual(viewModel.emptyStateCopy.message, "完成第一次陪跑后，记录会出现在这里。")
        XCTAssertEqual(viewModel.loadingLabel, "正在加载陪跑记录")
        XCTAssertEqual(RunRecordHistoryViewModel(role: .runner).loadingLabel, "正在加载跑步记录")
    }

    // MARK: - 失败

    func testMonthlyFailureLeavesAMessageAndKeepsTheUnfinishedGroup() async {
        let (viewModel, appState, _, _) = makeViewModel(
            orders: [makeOrder(orderId: 2, status: .cancelled, createdAt: "2026-08-02T10:00:00")],
            historyFailure: APIError.invalidURL
        )
        _ = appState

        await viewModel.load()

        guard case .failed(let message) = viewModel.historyState else {
            return XCTFail("失败必须留痕 —— 静默空列表看起来就是「你没跑过」；实际 \(viewModel.historyState)")
        }
        XCTAssertTrue(message.hasPrefix("跑步记录没能加载完整。"))
        XCTAssertNil(viewModel.partialFailure, "选中月份的失败只在一处显示和念，两路不能各来一遍")
        XCTAssertEqual(viewModel.unfinished.map(\.orderId), [2], "读到的那一半照常显示")
        XCTAssertFalse(viewModel.historyState.isLoading, "失败后不能卡在加载态")
    }

    /// 订单那一路失败后切月份：不能只清掉错误提示而不重试 —— 否则「未完成的预约」
    /// 看起来像是「没有」，其实请求从没成功过（阶段 3 复核抓到的）。
    func testSwitchingMonthRetriesTheOrdersThatFailedBefore() async {
        let (viewModel, appState, _, orders) = makeViewModel(ordersFailure: APIError.invalidURL)
        _ = appState
        await viewModel.load()
        XCTAssertNotNil(viewModel.partialFailure, "订单那一路失败：记录照常显示，失败单独一格")
        XCTAssertNotNil(viewModel.history)

        orders.myOrdersResult = .success(PagedOrderResponse(
            content: [makeOrder(orderId: 2, status: .cancelled, createdAt: "2026-08-02T10:00:00")],
            totalElements: 1, totalPages: 1, number: 0, size: 1, first: true, last: true, empty: false
        ))
        await viewModel.showPreviousMonth()

        XCTAssertEqual(orders.callCount("myOrders()"), 2, "上次失败了，切月份要顺手重试")
        XCTAssertEqual(viewModel.unfinished.map(\.orderId), [2])
        XCTAssertNil(viewModel.errorMessage)
    }

    func testRunnerAnnouncementCountsUnfinishedBookings() async {
        let (viewModel, appState, _, _) = makeViewModel(
            now: date(2026, 9, 24),
            orders: [
                makeOrder(orderId: 1, status: .completed, createdAt: "2026-09-01T10:00:00"),
                makeOrder(orderId: 2, status: .cancelled, createdAt: "2026-09-02T10:00:00"),
            ],
            history: makeHistory(runs: 1, distanceM: 5_000, items: [makeItem(orderId: 1)])
        )
        _ = appState
        await viewModel.load()
        XCTAssertEqual(viewModel.loadedAnnouncement, "9月跑了 1 次，一共 5 公里。另有 1 条未完成的预约。")
    }

    // MARK: - 行

    func testRunnerRowReadsAsOneSentenceAndDropsNullFields() {
        let full = RunHistoryRowContent(
            item: makeItem(orderId: 1, finishedAt: "2026-09-20T07:15:00", place: "深圳湾公园", partner: "林*", distanceM: 5_210),
            role: .runner
        )
        // 2026-09-20 是周日。原型里的「周六」对应的是 2025 年的样例日期，别照抄。
        XCTAssertEqual(full.dateText, "9月20日 周日")
        // #829 卡片左栏两行「9月20日 / 周日」，中间写地点；负责人 11-07：不写和谁一起跑。
        XCTAssertEqual([full.dayText, full.weekdayText, full.placeText], ["9月20日", "周日", "深圳湾公园"])
        XCTAssertEqual(full.distanceValue, "5.2")
        XCTAssertEqual(full.distanceText, "5.2 公里")
        XCTAssertEqual(full.accessibilityLabel, "9月20日 周日，深圳湾公园，5.2 公里")
        XCTAssertEqual(full.rotorLabel, "9月20日 周日")

        let sparse = RunHistoryRowContent(
            item: makeItem(orderId: 1, finishedAt: "2026-09-20T07:15:00.5", place: nil, partner: nil, distanceM: nil),
            role: .runner
        )
        XCTAssertNil(sparse.placeText, "没有地点整行不出现")
        XCTAssertNil(sparse.distanceText, "没有距离就不显示，不是「0.00 公里」")
        XCTAssertEqual(sparse.accessibilityLabel, "9月20日 周日")
    }

    /// 陪跑员端同款：同样不写陪的是谁（负责人 11-07）。
    func testVolunteerRowDoesNotNameThePartner() {
        let content = RunHistoryRowContent(
            item: makeItem(orderId: 1, finishedAt: "2026-09-06T08:00:00", place: "深圳湾公园", partner: "陈*", distanceM: 5_000),
            role: .volunteer
        )
        XCTAssertEqual(content.placeText, "深圳湾公园")
        XCTAssertEqual(content.distanceText, "5 公里")
        XCTAssertEqual(content.accessibilityLabel, "9月6日 周日，深圳湾公园，5 公里")
    }

    func testNumberFormatting() {
        XCTAssertEqual(RunRecordHistoryViewModel.kilometres(5_000), "5")
        XCTAssertEqual(RunRecordHistoryViewModel.kilometres(5_000, spoken: true), "5")
        XCTAssertEqual(RunRecordHistoryViewModel.kilometres(4_800, spoken: true), "4.8")
        XCTAssertEqual(RunRecordHistoryViewModel.kilometres(5_260, spoken: true), "5.3", "四舍五入到一位，不是截断")
        XCTAssertEqual(RunRecordHistoryViewModel.kilometres(20), "0.1", "大于 0 的距离不写成「0」")
        XCTAssertEqual(RunRecordHistoryViewModel.kilometres(0), "0")
        XCTAssertEqual(RunRecordHistoryViewModel.serviceDuration(45), "45 分钟")
        XCTAssertEqual(RunRecordHistoryViewModel.serviceDuration(120), "2 小时")
        XCTAssertEqual(RunRecordHistoryViewModel.serviceDuration(220), "3 小时 40 分钟")
    }

    // MARK: - Fixtures

    private func makeViewModel(
        role: RunRecordHistoryRole = .runner,
        now: Date = Date(),
        orders: [OrderDetailResponse] = [],
        ordersFailure: Error? = nil,
        history: RunRecordHistoryResponse? = nil,
        historyFailure: Error? = nil
    ) -> (RunRecordHistoryViewModel, AppState, FakeRunRecordService, FakeOrderService) {
        let orderService = FakeOrderService()
        orderService.myOrdersResult = ordersFailure.map { .failure($0) } ?? .success(
            PagedOrderResponse(
                content: orders,
                totalElements: Int64(orders.count),
                totalPages: 1,
                number: 0,
                size: max(orders.count, 1),
                first: true,
                last: true,
                empty: orders.isEmpty
            )
        )
        let records = FakeRunRecordService()
        records.result = historyFailure.map { .failure($0) } ?? .success(history ?? makeHistory(runs: 0))
        // AppState 必须由调用方持有：view model 对它是 weak，传临时对象 load() 会在第一行 guard 返回、断言静默全绿。
        let appState = AppState(orders: orderService, tokenStore: RunHistoryInMemoryTokenStore())
        appState.userId = 7
        let viewModel = RunRecordHistoryViewModel(role: role, now: now)
        viewModel.configure(with: appState, speechService: SpeechService(), runRecord: records)
        return (viewModel, appState, records, orderService)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func makeHistory(
        runs: Int = 0,
        distanceM: Int? = nil,
        serviceMin: Int64? = nil,
        topPartner: RunTopPartner? = nil,
        items: [RunHistoryItem] = []
    ) -> RunRecordHistoryResponse {
        RunRecordHistoryResponse(
            role: .blind,
            month: "2026-09",
            monthSummary: RunMonthSummary(runs: runs, distanceM: distanceM, serviceMin: serviceMin, topPartner: topPartner),
            items: items
        )
    }

    private func makeItem(
        orderId: Int64,
        finishedAt: String = "2026-09-20T07:15:00",
        place: String? = "深圳湾公园",
        partner: String? = "林*",
        distanceM: Int? = 5_210
    ) -> RunHistoryItem {
        RunHistoryItem(orderId: orderId, finishedAt: finishedAt, place: place, partnerName: partner, distanceM: distanceM, thumbnail: nil)
    }

    private func makeOrder(orderId: Int64, status: RunOrderStatus, createdAt: String?) -> OrderDetailResponse {
        OrderDetailResponse(
            orderId: orderId,
            status: status,
            startAddress: "测试出发点",
            startLatitude: nil,
            startLongitude: nil,
            endAddress: nil,
            endLatitude: nil,
            endLongitude: nil,
            plannedStart: nil,
            plannedEnd: nil,
            blindName: nil,
            blindPhone: nil,
            volunteerPhone: nil,
            acceptedAt: nil,
            createdAt: createdAt,
            expectedDurationMinutes: nil,
            pacePreference: nil,
            routePreference: nil,
            routeNotes: nil,
            hasGuideDogThisRun: nil,
            specialNotes: nil,
            visionLevel: nil,
            tetherPreference: nil,
            chatPreference: nil
        )
    }
}

// MARK: - Stubs

/// 只打桩 `monthlyRecords`：本阶段只有它有调用点，另两个方法没打桩就抛，用例会红在「谁调了它」上。
private final class FakeRunRecordService: RunRecordServing, @unchecked Sendable {
    struct NotStubbed: Error {}
    var result: Result<RunRecordHistoryResponse, Error> = .failure(NotStubbed())
    private(set) var requestedMonths: [RunRecordMonth] = []

    func record(orderId: Int64) async throws -> RunRecordResponse { throw NotStubbed() }

    func monthlyRecords(year: Int, month: Int) async throws -> RunRecordHistoryResponse {
        requestedMonths.append(RunRecordMonth(year: year, month: month))
        return try result.get()
    }

    func postMessage(orderId: Int64, text: String) async throws -> RunRecordMessageResponse { throw NotStubbed() }
}

private final class RunHistoryInMemoryTokenStore: TokenStoring, @unchecked Sendable {
    private var token: String?
    func save(_ token: String) { self.token = token }
    func read() -> String? { token }
    func delete() { token = nil }
}
