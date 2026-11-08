import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class HomeLoadDeadlineTests: XCTestCase, BlindRunTestSupport {
    func testVolunteerHomeCancellationClearsInitialLoadingState() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let viewModel = VolunteerHomeViewModel(
            dispatchPropagationDelay: 60,
            reportVolunteerLocation: { _, _, _ in true }
        )
        viewModel.configure(with: appState, speechService: SpeechService())

        let loadTask = Task {
            await viewModel.load(
                currentLocation: CLLocationCoordinate2D(latitude: 39.905, longitude: 116.408),
                locationAuthorized: true
            )
        }
        let didBeginLoading = await waitUntil { viewModel.isLoading }
        XCTAssertTrue(didBeginLoading)

        loadTask.cancel()
        await loadTask.value

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testBlindRunnerHomeCancellationClearsLoadingState() async {
        let appState = AppState(apiClient: CancellationSuspendingAPIClient())
        let viewModel = BlindRunnerHomeViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())

        let loadTask = Task { await viewModel.loadActiveOrder() }
        let didBeginLoading = await waitUntil { viewModel.isLoading }
        XCTAssertTrue(didBeginLoading)

        loadTask.cancel()
        await loadTask.value

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    /// #859：被取消的首次加载不得写成「已加载（空订单）」，只回到 `.idle`。
    func testBlindRunnerHomeCancelledInitialLoadReturnsOrderStateToIdle() async {
        let appState = AppState(apiClient: CancellationSuspendingAPIClient())
        let viewModel = BlindRunnerHomeViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())

        let loadTask = Task { await viewModel.loadActiveOrder() }
        let didBeginLoading = await waitUntil { viewModel.orderLoadState.isLoading }
        XCTAssertTrue(didBeginLoading)

        loadTask.cancel()
        await loadTask.value
        // 旧写法把清理放进另一个 Task 排队，给它一拍时间落地，免得断言抢在它前面。
        try? await Task.sleep(nanoseconds: 100_000_000)

        guard case .idle = viewModel.orderLoadState else {
            return XCTFail("Expected .idle after cancellation, got \(viewModel.orderLoadState)")
        }
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    /// #859：被取消的首次加载不得写成「派单状态加载失败」，只回到 `.idle`。
    func testVolunteerHomeCancelledInitialLoadReturnsDispatchStateToIdle() async {
        let appState = AppState(apiClient: CancellationSuspendingAPIClient())
        let viewModel = VolunteerHomeViewModel(
            dispatchPropagationDelay: 60,
            reportVolunteerLocation: { _, _, _ in true }
        )
        viewModel.configure(with: appState, speechService: SpeechService())

        let loadTask = Task { await viewModel.load(currentLocation: nil, locationAuthorized: false) }
        let didBeginLoading = await waitUntil { viewModel.dispatchLoadState.isLoading }
        XCTAssertTrue(didBeginLoading)

        loadTask.cancel()
        await loadTask.value
        try? await Task.sleep(nanoseconds: 100_000_000)

        guard case .idle = viewModel.dispatchLoadState else {
            return XCTFail("Expected .idle after cancellation, got \(viewModel.dispatchLoadState)")
        }
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.dispatchSummaryErrorMessage)
    }

    func testBlindRunnerHomeTimeoutReleasesLoadingAndOffersRetryState() async {
        let client = CancellationSuspendingAPIClient()
        let appState = AppState(apiClient: client)
        let viewModel = BlindRunnerHomeViewModel(loadTimeout: 0.05)
        viewModel.configure(with: appState, speechService: SpeechService())

        let loadTask = Task { await viewModel.loadActiveOrder() }
        let didTimeout = await waitUntil { !viewModel.isLoading && viewModel.errorMessage != nil }
        await loadTask.value

        XCTAssertTrue(didTimeout)
        XCTAssertEqual(viewModel.errorMessage, "加载超过 20 秒，请重试。")
        XCTAssertGreaterThanOrEqual(client.cancellationCount, 1)
    }

    func testHomeLoadCoordinatorCancelsSuspendedRequestAtDeadline() async {
        let client = CancellationSuspendingAPIClient()

        do {
            let _: PagedOrderResponse = try await HomeLoadCoordinator.run(timeout: 0.05) {
                try await client.get("/api/orders/mine")
            }
            XCTFail("Expected the home request to time out")
        } catch HomeLoadCoordinatorError.timedOut {
            await client.awaitCancellation()
            XCTAssertGreaterThanOrEqual(client.cancellationCount, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testHomeLoadCoordinatorReturnsAtDeadlineWhenRequestIgnoresCancellation() async {
        let client = ControlledNonCooperativeAPIClient()
        let startedAt = Date()

        do {
            let _: PagedOrderResponse = try await HomeLoadCoordinator.run(
                timeout: 0.05,
                operationName: "non-cooperative-test"
            ) {
                try await client.get("/api/orders/mine")
            }
            XCTFail("Expected the home request to time out")
        } catch HomeLoadCoordinatorError.timedOut {
            XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.5)
            XCTAssertTrue(client.hasStarted)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        client.release()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(client.didReturnLateResponse)
    }

    func testBlindRunnerHomeDiscardsResponseArrivingAfterDeadline() async {
        let client = ControlledNonCooperativeAPIClient()
        let appState = AppState(apiClient: client)
        let viewModel = BlindRunnerHomeViewModel(loadTimeout: 0.05)
        viewModel.configure(with: appState, speechService: SpeechService())

        await viewModel.loadActiveOrder()
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.errorMessage, "加载超过 20 秒，请重试。")

        client.release()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(viewModel.activeOrder)
        XCTAssertEqual(viewModel.errorMessage, "加载超过 20 秒，请重试。")
    }

    func testBlindRunnerCannotStartBookingBeforeActiveOrderIsConfirmed() {
        let appState = AppState(apiClient: CancellationSuspendingAPIClient())
        let viewModel = BlindRunnerHomeViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())

        XCTAssertFalse(viewModel.canStartNewBooking)
        viewModel.explainBookingUnavailable()
        XCTAssertEqual(viewModel.errorMessage, "订单状态尚未确认，请先重试加载，避免创建重复预约。")
    }

    func testVolunteerHomeTimeoutReleasesLoadingAndOffersRetryState() async {
        let client = CancellationSuspendingAPIClient()
        let appState = AppState(apiClient: client)
        let viewModel = VolunteerHomeViewModel(dispatchPropagationDelay: 0, loadTimeout: 0.05)
        viewModel.configure(with: appState, speechService: SpeechService())

        let loadTask = Task { await viewModel.load(currentLocation: nil, locationAuthorized: false) }
        let didTimeout = await waitUntil { !viewModel.isLoading && viewModel.dispatchSummaryErrorMessage != nil }
        await loadTask.value

        XCTAssertTrue(didTimeout)
        XCTAssertEqual(viewModel.dispatchSummaryErrorMessage, "加载超过 20 秒，请重试。")
        XCTAssertGreaterThanOrEqual(client.cancellationCount, 1)
    }

    func testBlindRunnerHomeCoalescesConcurrentRefreshTriggersWithoutExtendingDeadline() async {
        let client = CancellationSuspendingAPIClient()
        let appState = AppState(apiClient: client)
        let existingOrder = makeOrder(orderId: 701, status: .driverEnRoute)
        let viewModel = BlindRunnerHomeViewModel(loadTimeout: 0.08)
        viewModel.configure(with: appState, speechService: SpeechService())
        viewModel.activeOrder = existingOrder
        let startedAt = Date()

        let lifecycleLoad = Task { await viewModel.loadActiveOrder() }
        let didStart = await waitUntil {
            client.requestCount(for: "/api/orders/active") == 1
        }
        let reconnectLoad = Task { await viewModel.loadActiveOrder() }
        let manualLoad = Task { await viewModel.loadActiveOrder() }
        await lifecycleLoad.value
        await reconnectLoad.value
        await manualLoad.value

        XCTAssertTrue(didStart)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.5)
        XCTAssertEqual(client.requestCount(for: "/api/orders/active"), 1)
        XCTAssertEqual(viewModel.activeOrder?.orderId, existingOrder.orderId)
        XCTAssertEqual(viewModel.activeOrder?.status, .driverEnRoute)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.errorMessage, "加载超过 20 秒，请重试。")
    }

    private final class ControlledNonCooperativeAPIClient: APIClientProtocol, @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: UnsafeContinuation<Void, Never>?
        private var started = false
        private var returnedLateResponse = false

        var hasStarted: Bool {
            lock.withLock { started }
        }

        var didReturnLateResponse: Bool {
            lock.withLock { returnedLateResponse }
        }

        func release() {
            let continuation = lock.withLock { () -> UnsafeContinuation<Void, Never>? in
                defer { self.continuation = nil }
                return self.continuation
            }
            continuation?.resume()
        }

        func request<T: Decodable>(
            method: HTTPMethod,
            path: String,
            query: [String: String]?,
            body: (any Encodable & Sendable)?,
            requiresAuth: Bool
        ) async throws -> T {
            lock.withLock { started = true }
            await withUnsafeContinuation { continuation in
                lock.withLock { self.continuation = continuation }
            }
            lock.withLock { returnedLateResponse = true }
            return try JSONDecoder().decode(T.self, from: Data(#"{"content":[]}"#.utf8))
        }

        func upload<T: Decodable>(
            path: String,
            query: [String: String]?,
            fields: [String: String]?,
            files: [MultipartFile],
            requiresAuth: Bool
        ) async throws -> T {
            throw APIError.invalidURL
        }
    }
}
