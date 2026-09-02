import Foundation
@testable import blindRun

/// `OrderServing` 的测试替身。形状照 `FakeAuthService`。
///
/// 硬规矩两条，违反了就等于把 `MockAPIClient` 的病搬到新层：
/// 1. **不许含任何业务判定**（校验 / 状态机 / 按参数选返回值）。
///    每个方法只做两件事：记一笔调用、返回注入的罐装值。
/// 2. **默认是失败而不是成功**：没打桩的方法抛 `NotStubbed`，
///    用例因此会明确地红在「你没打这个桩」上，而不是拿到一个凭空捏造的成功值继续跑。
///
/// 比 `FakeAuthService` 多两样东西，两样都不是业务判定：
/// - **队列**（`orderDetailResults` 等）：一串按顺序弹出的罐装值，用来演「第一次和第二次
///   后端回的不一样」。队列空了就退回单值 `xxxResult`，**不看任何入参**。
/// - **闸门**（`orderDetailGate`）：一个可以把调用挂住的 async 钩子，用来演「确认请求还没回来」。
///   它替掉的是 `TransitionConfirmationAPIClient` 里那套 `UnsafeContinuation`。
final class FakeOrderService: OrderServing, @unchecked Sendable {

    struct NotStubbed: Error, CustomStringConvertible {
        let method: String
        var description: String { "FakeOrderService.\(method) 没有打桩" }
    }

    /// 调用顺序，元素是 `#function`（如 `"cancel(orderId:)"`）。
    private(set) var calls: [String] = []

    /// 每个方法各自的调用次数。断言「被打了几次」用。
    private(set) var callCounts: [String: Int] = [:]

    func callCount(_ method: String) -> Int { callCounts[method] ?? 0 }

    // MARK: 罐装返回值

    var createOrderResult: Result<OrderResponse, Error> = .failure(NotStubbed(method: "createOrder"))
    var myOrdersResult: Result<PagedOrderResponse, Error> = .failure(NotStubbed(method: "myOrders"))
    var orderDetailResult: Result<OrderDetailResponse, Error> = .failure(NotStubbed(method: "orderDetail"))
    var cancelResult: Result<Void, Error> = .failure(NotStubbed(method: "cancel"))
    var respondResult: Result<Void, Error> = .failure(NotStubbed(method: "respond"))
    var enRouteResult: Result<Void, Error> = .failure(NotStubbed(method: "enRoute"))
    var arrivedResult: Result<Void, Error> = .failure(NotStubbed(method: "arrived"))
    var startServiceResult: Result<Void, Error> = .failure(NotStubbed(method: "startService"))
    var finishResult: Result<Void, Error> = .failure(NotStubbed(method: "finish"))
    var keepWaitingResult: Result<Void, Error> = .failure(NotStubbed(method: "keepWaiting"))
    var submitReviewResult: Result<Void, Error> = .failure(NotStubbed(method: "submitReview"))
    var reviewsResult: Result<OrderReviewEnvelope, Error> = .failure(NotStubbed(method: "reviews"))
    var statusLogsResult: Result<[OrderStatusLog], Error> = .failure(NotStubbed(method: "statusLogs"))
    var introCallViewResult: Result<IntroCallView, Error> = .failure(NotStubbed(method: "introCallView"))
    var submitIntroCallDecisionResult: Result<Void, Error> = .failure(NotStubbed(method: "submitIntroCallDecision"))
    var notifyIntroCallIncomingResult: Result<Void, Error> = .failure(NotStubbed(method: "notifyIntroCallIncoming"))
    var startLiveShareResult: Result<ShareLinkResponse, Error> = .failure(NotStubbed(method: "startLiveShare"))
    var stopLiveShareResult: Result<Void, Error> = .failure(NotStubbed(method: "stopLiveShare"))
    var volunteerLocationResult: Result<VolunteerLocationResponse, Error> = .failure(NotStubbed(method: "volunteerLocation"))
    var dispatchSummaryResult: Result<VolunteerDispatchSummaryResponse, Error> = .failure(NotStubbed(method: "dispatchSummary"))
    var setDispatchStatusResult: Result<Void, Error> = .failure(NotStubbed(method: "setDispatchStatus"))
    var achievementsResult: Result<VolunteerAchievementsResponse, Error> = .failure(NotStubbed(method: "achievements"))

    // MARK: 按顺序弹出的罐装值（空了退回上面的单值）

    var orderDetailResults: [Result<OrderDetailResponse, Error>] = []
    var dispatchSummaryResults: [Result<VolunteerDispatchSummaryResponse, Error>] = []

    /// 挂住 `orderDetail` 的钩子。设了就在返回罐装值之前 `await` 它一次。
    var orderDetailGate: (@Sendable () async -> Void)?

    // MARK: 最后一次收到的参数（断言「传下去的是哪个值」用，不参与任何判定）

    private(set) var lastCreateOrderRequest: CreateOrderRequest?
    private(set) var lastOrderId: Int64?
    private(set) var lastRespondAction: OrderRespondAction?
    private(set) var lastKeepWaitingEndpoint: KeepWaitingEndpoint?
    private(set) var lastReviewRequest: CreateReviewRequest?
    private(set) var lastIntroCallDecision: IntroCallDecision?
    private(set) var lastWantsDispatch: Bool?

    private func record(_ method: String = #function) {
        calls.append(method)
        callCounts[method, default: 0] += 1
    }

    private func next<T>(_ queue: inout [Result<T, Error>], fallback: Result<T, Error>) -> Result<T, Error> {
        queue.isEmpty ? fallback : queue.removeFirst()
    }

    // MARK: - OrderServing

    func createOrder(_ request: CreateOrderRequest) async throws -> OrderResponse {
        record()
        lastCreateOrderRequest = request
        return try createOrderResult.get()
    }

    func myOrders() async throws -> PagedOrderResponse {
        record()
        return try myOrdersResult.get()
    }

    func orderDetail(orderId: Int64) async throws -> OrderDetailResponse {
        record()
        lastOrderId = orderId
        if let orderDetailGate { await orderDetailGate() }
        return try next(&orderDetailResults, fallback: orderDetailResult).get()
    }

    func cancel(orderId: Int64) async throws {
        record()
        lastOrderId = orderId
        return try cancelResult.get()
    }

    func respond(orderId: Int64, action: OrderRespondAction) async throws {
        record()
        lastOrderId = orderId
        lastRespondAction = action
        return try respondResult.get()
    }

    func enRoute(orderId: Int64) async throws {
        record()
        lastOrderId = orderId
        return try enRouteResult.get()
    }

    func arrived(orderId: Int64) async throws {
        record()
        lastOrderId = orderId
        return try arrivedResult.get()
    }

    func startService(orderId: Int64) async throws {
        record()
        lastOrderId = orderId
        return try startServiceResult.get()
    }

    func finish(orderId: Int64) async throws {
        record()
        lastOrderId = orderId
        return try finishResult.get()
    }

    func keepWaiting(_ endpoint: KeepWaitingEndpoint, orderId: Int64) async throws {
        record()
        lastOrderId = orderId
        lastKeepWaitingEndpoint = endpoint
        return try keepWaitingResult.get()
    }

    func submitReview(_ request: CreateReviewRequest, orderId: Int64) async throws {
        record()
        lastOrderId = orderId
        lastReviewRequest = request
        return try submitReviewResult.get()
    }

    func reviews(orderId: Int64) async throws -> OrderReviewEnvelope {
        record()
        lastOrderId = orderId
        return try reviewsResult.get()
    }

    func statusLogs(orderId: Int64) async throws -> [OrderStatusLog] {
        record()
        lastOrderId = orderId
        return try statusLogsResult.get()
    }

    func introCallView(orderId: Int64) async throws -> IntroCallView {
        record()
        lastOrderId = orderId
        return try introCallViewResult.get()
    }

    func submitIntroCallDecision(_ decision: IntroCallDecision, orderId: Int64) async throws {
        record()
        lastOrderId = orderId
        lastIntroCallDecision = decision
        return try submitIntroCallDecisionResult.get()
    }

    func notifyIntroCallIncoming(orderId: Int64) async throws {
        record()
        lastOrderId = orderId
        return try notifyIntroCallIncomingResult.get()
    }

    func startLiveShare(orderId: Int64) async throws -> ShareLinkResponse {
        record()
        lastOrderId = orderId
        return try startLiveShareResult.get()
    }

    func stopLiveShare(orderId: Int64) async throws {
        record()
        lastOrderId = orderId
        return try stopLiveShareResult.get()
    }

    func volunteerLocation() async throws -> VolunteerLocationResponse {
        record()
        return try volunteerLocationResult.get()
    }

    func dispatchSummary() async throws -> VolunteerDispatchSummaryResponse {
        record()
        return try next(&dispatchSummaryResults, fallback: dispatchSummaryResult).get()
    }

    func setDispatchStatus(wantsDispatch: Bool) async throws {
        record()
        lastWantsDispatch = wantsDispatch
        return try setDispatchStatusResult.get()
    }

    func achievements() async throws -> VolunteerAchievementsResponse {
        record()
        return try achievementsResult.get()
    }
}
