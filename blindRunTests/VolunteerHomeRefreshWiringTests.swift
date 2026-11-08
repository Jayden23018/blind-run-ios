import XCTest
@testable import blindRun

/// 陪跑员首页两个刷新实例的接线（#859）：摘要刷新等整页刷新，切后台两个都停。
@MainActor
final class VolunteerHomeRefreshWiringTests: XCTestCase, BlindRunTestSupport {
    /// #859：整页刷新在跑时，摘要刷新只等它，不另发一条派单摘要请求。
    func testVolunteerSummaryRefreshWaitsForRunningPageRefresh() async {
        let client = CancellationSuspendingAPIClient()
        let appState = AppState(apiClient: client)
        let viewModel = VolunteerHomeViewModel(
            dispatchPropagationDelay: 60,
            reportVolunteerLocation: { _, _, _ in true }
        )
        viewModel.configure(with: appState, speechService: SpeechService())
        let summaryPath = "/api/volunteer/dispatch-summary"

        let loadTask = Task { await viewModel.load(currentLocation: nil, locationAuthorized: false) }
        let didStart = await waitUntil { client.requestCount(for: summaryPath) == 1 }
        XCTAssertTrue(didStart)

        let summaryTask = Task { await viewModel.refreshDispatchSummary() }
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(client.requestCount(for: summaryPath), 1)

        viewModel.cancelLoading()
        await summaryTask.value
        await loadTask.value
        XCTAssertEqual(client.requestCount(for: summaryPath), 1)
    }

    /// #859：切到后台要连摘要刷新一起停，不能等到 20 秒超时。
    func testVolunteerSceneInactiveStopsRunningSummaryRefresh() async {
        let appState = AppState(apiClient: CancellationSuspendingAPIClient())
        let viewModel = VolunteerHomeViewModel(
            dispatchPropagationDelay: 60,
            reportVolunteerLocation: { _, _, _ in true }
        )
        viewModel.configure(with: appState, speechService: SpeechService())

        let summaryTask = Task { await viewModel.refreshDispatchSummary() }
        let didStart = await waitUntil { viewModel.isLoading }
        XCTAssertTrue(didStart)

        let stoppedAt = Date()
        viewModel.setSceneActive(false)
        await summaryTask.value

        XCTAssertLessThan(Date().timeIntervalSince(stoppedAt), 1)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.dispatchSummaryErrorMessage)
    }
}
