import XCTest
@testable import blindRun

/// 跑后详情页「重试」的任务归 `RunRecordViewModel` 管（#879）。原来两页各持一个 `@State retryTask`。
@MainActor
final class RunRecordRetryTests: XCTestCase {

    func testRetryAfterFailureReadsTheRecordAgain() async {
        let (viewModel, service) = makeViewModel()
        service.results = [.success(record(status: .failed)), .success(record(status: .ready))]
        await viewModel.loadUntilSettled()
        XCTAssertEqual(service.calls, 1)

        await viewModel.startRetry().value

        XCTAssertEqual(service.calls, 2)
        XCTAssertEqual(viewModel.phase.value?.status, .ready)
    }

    func testSecondRetryCancelsTheFirstSoOnlyOnePollRuns() async {
        let (viewModel, service) = makeViewModel()
        service.results = Array(repeating: .success(record(status: .generating)), count: 50)

        let first = viewModel.startRetry()
        let second = viewModel.startRetry()

        XCTAssertTrue(first.isCancelled, "连点两下：第一次的轮询要停")
        XCTAssertFalse(second.isCancelled)
        viewModel.cancelRetry()
        await first.value
        await second.value
    }

    func testLeavingThePageStopsTheRetryPoll() async {
        let (viewModel, service) = makeViewModel()
        // 一直 GENERATING：不取消就会把 50 次读完。
        service.results = Array(repeating: .success(record(status: .generating)), count: 50)

        let task = viewModel.startRetry()
        // 等它真的在轮询（至少读过一次）再离开页面，守的是「轮询中途取消」，不只是「还没开始就取消」。
        for _ in 0..<200 where service.calls == 0 {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertGreaterThan(service.calls, 0, "重试任务没有开始读")
        viewModel.cancelRetry()
        await task.value

        XCTAssertTrue(task.isCancelled)
        XCTAssertLessThan(service.calls, 50, "离开页面后不能接着轮询")
    }

    // MARK: - Helpers

    /// 依赖在构造时传齐（#894），不再要 `AppState`。记录读到后还会查一次订单详情：
    /// `FakeOrderService` 没打桩就抛错，不发任何请求，记录页照常可看。
    private func makeViewModel() -> (RunRecordViewModel, RetryRecordService) {
        let service = RetryRecordService()
        let viewModel = RunRecordViewModel(
            orderId: 7,
            dependencies: .fixed(runRecord: service, orders: FakeOrderService()),
            retryNanoseconds: 1_000_000
        )
        return (viewModel, service)
    }

    private func record(status: RunRecordStatus) -> RunRecordResponse {
        RunRecordResponse(
            orderId: 7, status: status, viewerRole: .volunteer, place: "深圳湾公园",
            blindName: "陈*", volunteerName: "林*",
            runStartedAt: "2026-09-20T08:00:00", runEndedAt: "2026-09-20T08:40:00",
            summary: nil, splits: [], fastestSplitIndex: nil, paceSamples: [], stops: [],
            events: [], sosTriggered: false,
            service: RunService(startedAt: "2026-09-20T08:00:00", completedAt: "2026-09-20T08:45:00", durationMin: 45, volunteerTotalServiceMinutes: 300),
            comparison: nil, messages: [], track: nil
        )
    }
}

/// 按顺序吐结果；吐完再调就抛。
private final class RetryRecordService: RunRecordServing, @unchecked Sendable {
    struct Exhausted: Error {}
    var results: [Result<RunRecordResponse, Error>] = []
    private(set) var calls = 0

    func record(orderId: Int64) async throws -> RunRecordResponse {
        defer { calls += 1 }
        guard calls < results.count else { throw Exhausted() }
        return try results[calls].get()
    }

    func monthlyRecords(year: Int, month: Int) async throws -> RunRecordHistoryResponse { throw Exhausted() }
    func postMessage(orderId: Int64, text: String) async throws -> RunRecordMessageResponse { throw Exhausted() }
}
