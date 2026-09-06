//
//  OrderService.swift
//  blindRun
//
//  领域 service 层的第二片：订单。形状照 `AuthService.swift`。
//

import Foundation

// MARK: - Protocol

/// 订单片对外的全部能力。
///
/// **每个方法都必须有生产调用点**，没有的当场删 —— service 层的价值是收敛调用点，
/// 不是先摆一层空壳。当前 22 个方法覆盖迁移前 7 个 view 文件里的 49 个 `apiClient.<verb>`
/// （另外 2 个是 `/api/volunteer/profile` 与 `/api/volunteer/registration/status`，
/// 它们在 `AuthServing` 上已有方法，走那边而不是在这里开第二条同路径；
/// 还有 1 个是 `VoiceOrderEndpoint.parseOrder`，属语音片）。
///
/// 错误一律 `throws` 抛出去，**这一层不吞**。谁负责渲染谁 catch：
/// 吞在 service 里的错误在 UI 上表现成「点了没反应」，对盲人端就是事故。
///
/// 🚨 **这一层不做业务判定。** 「这个状态能不能取消」「陌生人该发 ACCEPT 还是 INTERESTED」
/// 全在调用方（`RunOrderStatus` 的那些穷举 switch、`VolunteerOrderActionGuard`）。
/// 在这里补一条判断，就多一处「Mock 和真实后端行为不一样」的来源。
protocol OrderServing: Sendable {
    // 下单与查询
    func createOrder(_ request: CreateOrderRequest) async throws -> OrderResponse
    func myOrders() async throws -> PagedOrderResponse
    /// 冷启动 / 重连时问服务端「这个盲人现在有没有一条没走完的单」。
    /// 没有时 `data` 为 `null`（不是 404、不是空对象），所以返回信封而不是订单本体。
    func activeOrder() async throws -> ActiveOrderEnvelope
    func orderDetail(orderId: Int64) async throws -> OrderDetailResponse

    /// 志愿者手上**已确认但还没到点**的跨天预约单。
    ///
    /// 🚩 **为什么不复用 `dispatchSummary()`**：后端 `VolunteerService.loadActiveOrders` 的白名单只有
    /// `IN_PROGRESS` / `DRIVER_EN_ROUTE` / `DRIVER_ARRIVED`，`SCHEDULED_CONFIRMED` 不在里面
    /// ⇒ 志愿者杀掉 App 再打开，那张预约单在首页上**不存在**，而它带着一个 60 分钟到期的确认动作。
    /// 已请后端在 dispatch-summary 上单开 `scheduledOrders` 字段（见 `demo/docs/handoff.md`），
    /// 落地后这条可以撤掉；在那之前自己打一次列表端点。
    func scheduledOrders() async throws -> PagedOrderResponse

    // 状态流转
    func cancel(orderId: Int64) async throws
    func respond(orderId: Int64, action: OrderRespondAction) async throws
    func enRoute(orderId: Int64) async throws
    func arrived(orderId: Int64) async throws
    func startService(orderId: Int64) async throws
    func finish(orderId: Int64) async throws

    /// 跨天预约单的临期确认。与 `enRoute` **不是一回事**，理由见 `OrderEndpoint.confirmDeparture`。
    func confirmDeparture(orderId: Int64) async throws

    /// 延长等待窗口。**端点由调用方按状态选**（`RunOrderStatus.keepWaitingEndpoint`）——
    /// 两条端点的前置状态互斥，选错得到的 409 含义是「你手上的状态已经过期了」，
    /// 而不是「换一个 URL 再打一次」。这条判定留在调用方，这里只负责发出去。
    func keepWaiting(_ endpoint: KeepWaitingEndpoint, orderId: Int64) async throws

    // 评价与状态记录
    func submitReview(_ request: CreateReviewRequest, orderId: Int64) async throws
    func reviews(orderId: Int64) async throws -> OrderReviewEnvelope
    func statusLogs(orderId: Int64) async throws -> [OrderStatusLog]

    // 接单前通话磨合（盲人侧。志愿者侧的 `unreachable` 还在 `VolunteerIntroCallView` 里直连）
    func introCallView(orderId: Int64) async throws -> IntroCallView
    func submitIntroCallDecision(_ decision: IntroCallDecision, orderId: Int64) async throws
    func notifyIntroCallIncoming(orderId: Int64) async throws

    // 行程实时分享
    func startLiveShare(orderId: Int64) async throws -> ShareLinkResponse
    func stopLiveShare(orderId: Int64) async throws

    // 陪跑途中
    func volunteerLocation() async throws -> VolunteerLocationResponse

    // 志愿者派单
    func dispatchSummary() async throws -> VolunteerDispatchSummaryResponse
    func setDispatchStatus(wantsDispatch: Bool) async throws
}

// MARK: - Implementation

/// 唯一的生产实现。**只做两件事**：选端点、转参数。
///
/// 不做重试、不做缓存、不做错误分类 —— 那些属于调用方或 `APIClient`。
struct OrderService: OrderServing {
    let transport: any APIClientProtocol

    init(transport: any APIClientProtocol) {
        self.transport = transport
    }

    func createOrder(_ request: CreateOrderRequest) async throws -> OrderResponse {
        try await transport.send(OrderEndpoint.create.request, body: request)
    }

    func myOrders() async throws -> PagedOrderResponse {
        try await transport.send(OrderEndpoint.mine.request)
    }

    func activeOrder() async throws -> ActiveOrderEnvelope {
        try await transport.send(OrderEndpoint.active.request)
    }

    func orderDetail(orderId: Int64) async throws -> OrderDetailResponse {
        try await transport.send(OrderEndpoint.detail(orderId: orderId).request)
    }

    /// 🚨 **query 必须走 `send(_:query:)`，绝不能拼进路径字面量**，两个理由各自都足以致命：
    /// ① `APIClient.request` 用 `baseURL.appendingPathComponent(path)`，`?` 会被百分号编码成
    ///    `%3F` —— 打出去是一条 404，而客户端只看到「请求的资源不存在」，看不出是自己拼错了。
    /// ② `scripts/validate-spec-coverage.mjs` 扫的是引号里的整串且**不剥 query**，
    ///    `"/api/orders/mine?role=..."` 在契约里不存在 ⇒ 当场判硬错误。
    func scheduledOrders() async throws -> PagedOrderResponse {
        try await transport.send(
            OrderEndpoint.mine.request,
            query: ["role": "VOLUNTEER", "status": RunOrderStatus.scheduledConfirmed.rawValue]
        )
    }

    func cancel(orderId: Int64) async throws {
        let _: EmptyResponse = try await transport.send(OrderEndpoint.cancel(orderId: orderId).request)
    }

    func respond(orderId: Int64, action: OrderRespondAction) async throws {
        let _: EmptyResponse = try await transport.send(
            OrderEndpoint.respond(orderId: orderId).request,
            body: OrderRespondRequest(action: action)
        )
    }

    func enRoute(orderId: Int64) async throws {
        let _: EmptyResponse = try await transport.send(OrderEndpoint.enRoute(orderId: orderId).request)
    }

    func arrived(orderId: Int64) async throws {
        let _: EmptyResponse = try await transport.send(OrderEndpoint.arrived(orderId: orderId).request)
    }

    func startService(orderId: Int64) async throws {
        let _: EmptyResponse = try await transport.send(OrderEndpoint.startService(orderId: orderId).request)
    }

    func finish(orderId: Int64) async throws {
        let _: EmptyResponse = try await transport.send(OrderEndpoint.finish(orderId: orderId).request)
    }

    func confirmDeparture(orderId: Int64) async throws {
        let _: EmptyResponse = try await transport.send(
            OrderEndpoint.confirmDeparture(orderId: orderId).request
        )
    }

    func keepWaiting(_ endpoint: KeepWaitingEndpoint, orderId: Int64) async throws {
        let _: EmptyResponse = try await transport.send(
            OrderEndpoint.keepWaiting(endpoint, orderId: orderId).request
        )
    }

    func submitReview(_ request: CreateReviewRequest, orderId: Int64) async throws {
        let _: EmptyResponse = try await transport.send(
            OrderEndpoint.review(orderId: orderId).request,
            body: request
        )
    }

    func reviews(orderId: Int64) async throws -> OrderReviewEnvelope {
        try await transport.send(OrderEndpoint.reviews(orderId: orderId).request)
    }

    func statusLogs(orderId: Int64) async throws -> [OrderStatusLog] {
        try await transport.send(OrderEndpoint.statusLogs(orderId: orderId).request)
    }

    func introCallView(orderId: Int64) async throws -> IntroCallView {
        try await transport.send(OrderEndpoint.introCall(.view, orderId: orderId).request)
    }

    func submitIntroCallDecision(_ decision: IntroCallDecision, orderId: Int64) async throws {
        let _: EmptyResponse = try await transport.send(
            OrderEndpoint.introCall(.decision, orderId: orderId).request,
            body: IntroCallDecisionRequest(decision: decision)
        )
    }

    func notifyIntroCallIncoming(orderId: Int64) async throws {
        let _: EmptyResponse = try await transport.send(
            OrderEndpoint.introCall(.notifyIncoming, orderId: orderId).request
        )
    }

    func startLiveShare(orderId: Int64) async throws -> ShareLinkResponse {
        try await transport.send(OrderEndpoint.startLiveShare(orderId: orderId).request)
    }

    func stopLiveShare(orderId: Int64) async throws {
        let _: EmptyResponse = try await transport.send(OrderEndpoint.stopLiveShare(orderId: orderId).request)
    }

    func volunteerLocation() async throws -> VolunteerLocationResponse {
        try await transport.send(OrderEndpoint.volunteerLocation.request)
    }

    func dispatchSummary() async throws -> VolunteerDispatchSummaryResponse {
        try await transport.send(OrderEndpoint.dispatchSummary.request)
    }

    func setDispatchStatus(wantsDispatch: Bool) async throws {
        let _: EmptyResponse = try await transport.send(
            OrderEndpoint.dispatchStatus.request,
            body: DispatchStatusRequest(wantsDispatch: wantsDispatch)
        )
    }
}
