import XCTest
@testable import blindRun

/// #936：约跑提交成功 →「正在匹配中」→ 退回首页，首页必须有这张匹配中的单。
///
/// 负责人 2026-11-11 模拟盲人时报：首页只剩「预约新的陪跑」。根因在客户端：提交后直接推订单页，
/// 首页不重新加载，订单页返回时写回的 `applyOrderDetail` 只认首页已知的单，新单两头对不上就被丢掉。
/// 后端与 Mock 的 `GET /api/orders/active` 都把 `PENDING_MATCH` 算作还没走完，不是根因。
@MainActor
final class BlindHomeNewBookingTests: XCTestCase, BlindRunTestSupport {

    /// 订单页拉到了详情再退回：首页原先没有单，新单要成为首页那一张，状态是匹配中。
    func testOrderPageWriteBackShowsANewMatchingOrderOnAnEmptyHome() async {
        let viewModel = makeLoadedEmptyHome(client: StubClient(active: nil))
        let created = makeOrder(orderId: 936, status: .pendingMatch)

        viewModel.applyOrderDetail(created)

        XCTAssertEqual(viewModel.homeOrders.map(\.orderId), [936], "刚下的单在首页上消失了（#936）")
        XCTAssertEqual(viewModel.homeOrders.first?.status, .pendingMatch)
        XCTAssertEqual(viewModel.activeOrder?.orderId, 936, "唯一的一张要当最早那张，求助与实时推送都跟它")
    }

    /// 首页已经有一张更早的单：新单排进其余几张，不能顶掉 `activeOrder`（求助判据跟它）。
    func testOrderPageWriteBackKeepsTheExistingActiveOrderFirst() async {
        let existing = makeOrder(orderId: 1, status: .scheduledConfirmed)
        let viewModel = makeLoadedEmptyHome(client: StubClient(active: existing))
        await viewModel.loadActiveOrder(announcesStatus: false)
        XCTAssertEqual(viewModel.activeOrder?.orderId, 1)

        viewModel.applyOrderDetail(makeOrder(orderId: 2, status: .pendingMatch))

        XCTAssertEqual(viewModel.homeOrders.map(\.orderId), [1, 2])
    }

    /// 已结束的单不收：写回的是一张首页不认识的终态单时，首页不变。
    func testOrderPageWriteBackIgnoresAnUnknownFinishedOrder() async {
        let viewModel = makeLoadedEmptyHome(client: StubClient(active: nil))

        viewModel.applyOrderDetail(makeOrder(orderId: 7, status: .cancelled))

        XCTAssertTrue(viewModel.homeOrders.isEmpty)
    }

    /// 订单页还没拉到详情就被退出（返回不写回任何东西）：回到首页时向服务端重新要一次。
    func testReturningHomeAfterBookingReloadsTheActiveOrder() async {
        let client = StubClient(active: nil)
        let viewModel = makeLoadedEmptyHome(client: client)
        await viewModel.loadActiveOrder(announcesStatus: false)
        XCTAssertTrue(viewModel.homeOrders.isEmpty)
        client.active = makeOrder(orderId: 936, status: .pendingMatch)

        viewModel.handleOrderCreated(OrderResponse(id: 936, status: .pendingMatch, message: nil, success: true))
        await viewModel.reloadAfterBookingIfNeeded()

        XCTAssertEqual(viewModel.homeOrders.map(\.orderId), [936], "下过单回到首页，首页没有重新加载")
        XCTAssertEqual(viewModel.homeOrders.first?.status, .pendingMatch)
    }

    /// 没下过单就只是看了一眼订单页：返回时不重拉（不多打一次请求、不多念一遍首页状态）。
    func testReturningHomeWithoutBookingDoesNotReload() async {
        let client = StubClient(active: nil)
        let viewModel = makeLoadedEmptyHome(client: client)
        await viewModel.loadActiveOrder(announcesStatus: false)
        let before = client.activeRequestCount

        await viewModel.reloadAfterBookingIfNeeded()

        XCTAssertEqual(client.activeRequestCount, before)
    }

    /// ⚠️ 首页 view model 只 `weak` 持有 `AppState`（`BlindRunnerHomeView.swift:40`）。
    /// 在 helper 里临时建一个、不留引用，它一返回就被释放，`loadActiveOrder` 第一行 `guard let appState` 直接早退：
    /// 一个请求都不发，下面几条「回首页重拉」的用例就假红或假绿（#959 真机实测）。所以由测试实例持有。
    private var retainedAppStates: [AppState] = []

    private func makeLoadedEmptyHome(client: StubClient) -> BlindRunnerHomeViewModel {
        let viewModel = BlindRunnerHomeViewModel()
        let appState = AppState(apiClient: client)
        retainedAppStates.append(appState)
        viewModel.configure(with: appState, speechService: SpeechService())
        return viewModel
    }

    /// 只回 `GET /api/orders/active`；`/mine` 抛错（首页把它当「其余几张没加载出来」，不影响最早那张）。
    private final class StubClient: APIClientProtocol, @unchecked Sendable {
        enum StubError: Error { case unexpectedPath, unexpectedType }

        private let lock = NSLock()
        private var current: OrderDetailResponse?
        private var count = 0

        init(active: OrderDetailResponse?) {
            current = active
        }

        var active: OrderDetailResponse? {
            get { lock.withLock { current } }
            set { lock.withLock { current = newValue } }
        }

        var activeRequestCount: Int { lock.withLock { count } }

        func request<T: Decodable>(
            method: HTTPMethod,
            path: String,
            query: [String: String]?,
            body: (any Encodable & Sendable)?,
            requiresAuth: Bool
        ) async throws -> T {
            guard path == "/api/orders/active", method == .get else { throw StubError.unexpectedPath }
            let envelope = lock.withLock { () -> ActiveOrderEnvelope in
                count += 1
                return ActiveOrderEnvelope(success: true, data: current)
            }
            guard let typed = envelope as? T else { throw StubError.unexpectedType }
            return typed
        }

        func upload<T: Decodable>(
            path: String,
            query: [String: String]?,
            fields: [String: String]?,
            files: [MultipartFile],
            requiresAuth: Bool
        ) async throws -> T {
            throw StubError.unexpectedPath
        }
    }
}
