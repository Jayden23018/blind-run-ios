import XCTest
@testable import blindRun

/// `BlindRunHistoryViewModel` 的过滤与排序。
///
/// 合入「我的跑步记录」时这段逻辑一条断言都没有，而它做的两个决定都会被用户看见：
/// **只收 `COMPLETED`**（取消掉的订单看不到，这是刻意的，见 `BlindRunHistoryView.swift:29-30`）
/// 和**时间倒序**（最近一次跑在最上面）。未知状态的处理更要钉住 ——
/// 后端加新状态时把它当「跑过了」是在替用户下结论，而这一页点进去是轨迹回放，没轨迹就是空页。
@MainActor
final class BlindRunHistoryTests: XCTestCase {

    func testOnlyCompletedOrdersAppear() async {
        let (viewModel, appState) = makeViewModel(orders: [
            makeOrder(orderId: 1, status: .completed, createdAt: "2026-08-01T10:00:00"),
            makeOrder(orderId: 2, status: .cancelled, createdAt: "2026-08-02T10:00:00"),
            makeOrder(orderId: 3, status: .inProgress, createdAt: "2026-08-03T10:00:00"),
            makeOrder(orderId: 4, status: .noVolunteer, createdAt: "2026-08-04T10:00:00"),
            makeOrder(orderId: 5, status: .completed, createdAt: "2026-08-05T10:00:00"),
        ])
        _ = appState  // 强引用必须活到 load 结束：view model 对 appState 是 weak

        await viewModel.load()

        XCTAssertEqual(viewModel.records.map(\.orderId), [5, 1], "只有已完成的订单能进跑步记录，且最近的排最前")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testUnknownStatusIsExcludedRatherThanAssumedCompleted() async {
        // 解码遇未知枚举值降级成 .unknown 而不是整条崩（AGENTS 硬约束）。
        // 降级之后这一页要把它**排除**：当成「跑过了」会让用户点进一个没有轨迹的空回放页。
        let (viewModel, appState) = makeViewModel(orders: [
            makeOrder(orderId: 9, status: .unknown, createdAt: "2026-08-09T10:00:00"),
            makeOrder(orderId: 1, status: .completed, createdAt: "2026-08-01T10:00:00"),
        ])
        _ = appState

        await viewModel.load()

        XCTAssertEqual(viewModel.records.map(\.orderId), [1])
    }

    func testFallsBackToPlannedStartWhenCreatedAtIsMissing() async {
        // 后端这两个字段都可空。缺 createdAt 时用 plannedStart 排，否则该单会被甩到最后。
        let (viewModel, appState) = makeViewModel(orders: [
            makeOrder(orderId: 1, status: .completed, createdAt: "2026-08-01T10:00:00"),
            makeOrder(orderId: 2, status: .completed, createdAt: nil, plannedStart: "2026-08-20T10:00:00"),
        ])
        _ = appState

        await viewModel.load()

        XCTAssertEqual(viewModel.records.map(\.orderId), [2, 1], "缺 createdAt 时应回退到 plannedStart 参与排序")
    }

    func testEmptyPageYieldsNoRecordsAndNoError() async {
        let (viewModel, appState) = makeViewModel(orders: [])
        _ = appState

        await viewModel.load()

        XCTAssertTrue(viewModel.records.isEmpty)
        XCTAssertNil(viewModel.errorMessage, "空列表是正常状态，不是错误")
        XCTAssertFalse(viewModel.isLoading)
    }

    func testFailureSurfacesAMessageAndLeavesLoadingOff() async {
        let (viewModel, appState) = makeViewModel(orders: [], failure: APIError.invalidURL)
        _ = appState

        await viewModel.load()

        XCTAssertTrue(viewModel.records.isEmpty)
        XCTAssertNotNil(viewModel.errorMessage, "失败必须留痕 —— 静默空列表看起来就是「你没跑过」")
        XCTAssertFalse(viewModel.isLoading, "失败后不能卡在加载态，否则下拉重试的提示也不会出现")
    }

    // MARK: - Fixtures

    private func makeViewModel(
        orders: [OrderDetailResponse],
        failure: APIError? = nil
    ) -> (BlindRunHistoryViewModel, AppState) {
        let client = RunHistoryAPIClientStub(orders: orders, failure: failure)
        // AppState 必须由调用方持有：`BlindRunHistoryViewModel.appState` 是 weak，
        // 传临时对象等于传 nil，`load()` 会在第一行 guard 直接返回，所有断言静默全绿。
        let appState = AppState(apiClient: client, tokenStore: RunHistoryInMemoryTokenStore())
        appState.userId = 7
        let viewModel = BlindRunHistoryViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())
        return (viewModel, appState)
    }

    private func makeOrder(
        orderId: Int64,
        status: RunOrderStatus,
        createdAt: String?,
        plannedStart: String? = nil
    ) -> OrderDetailResponse {
        OrderDetailResponse(
            orderId: orderId,
            status: status,
            startAddress: "测试出发点",
            startLatitude: nil,
            startLongitude: nil,
            endAddress: nil,
            endLatitude: nil,
            endLongitude: nil,
            plannedStart: plannedStart,
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

private final class RunHistoryAPIClientStub: APIClientProtocol, @unchecked Sendable {
    private let orders: [OrderDetailResponse]
    private let failure: APIError?
    private(set) var requestedPaths: [String] = []

    init(orders: [OrderDetailResponse], failure: APIError?) {
        self.orders = orders
        self.failure = failure
    }

    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        requestedPaths.append(path)
        if let failure { throw failure }
        let page = PagedOrderResponse(
            content: orders,
            totalElements: Int64(orders.count),
            totalPages: 1,
            number: 0,
            size: orders.count,
            first: true,
            last: true,
            empty: orders.isEmpty
        )
        guard let typed = page as? T else {
            throw APIError.invalidURL
        }
        return typed
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

private final class RunHistoryInMemoryTokenStore: TokenStoring, @unchecked Sendable {
    private var token: String?
    func save(_ token: String) { self.token = token }
    func read() -> String? { token }
    func delete() { token = nil }
}
