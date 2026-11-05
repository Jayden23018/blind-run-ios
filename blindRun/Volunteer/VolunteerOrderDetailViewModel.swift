import Combine
import CoreLocation
import SwiftUI

@MainActor
final class VolunteerOrderDetailViewModel: ObservableObject {
    @Published var order: OrderDetailResponse?
    @Published var isLoading = false
    @Published var isPerformingAction = false
    @Published var errorMessage: String?
    @Published var didCancelOrder = false
    /// 接单被后端 403 `VOLUNTEER_NOT_VERIFIED` 拒绝后，错误区要长出「去上传资质证书」入口。
    @Published var needsCertificateUpload = false
    @Published private(set) var transitionState: VolunteerOrderTransitionState = .idle

    private weak var appState: AppState?
    private var speechService: SpeechService?
    private var realtimeRefreshCancellable: AnyCancellable?
    private var realtimeStatusCancellable: AnyCancellable?
    private var confirmationTask: Task<Void, Never>?
    /// 取消之后那一句与「已记一次临时取消」的先后（`VolunteerCancelAnnouncement`）。
    private var cancelAnnouncement = VolunteerCancelAnnouncement()
    private let actionDeadlineNanoseconds: UInt64
    private let confirmationTimeout: TimeInterval
    private let orderLoadTimeout: TimeInterval

    init(
        actionDeadlineNanoseconds: UInt64 = 12_000_000_000,
        confirmationTimeout: TimeInterval = HomeLoadPolicy.defaultTimeout,
        orderLoadTimeout: TimeInterval = HomeLoadPolicy.defaultTimeout
    ) {
        self.actionDeadlineNanoseconds = actionDeadlineNanoseconds
        self.confirmationTimeout = max(0.05, confirmationTimeout)
        self.orderLoadTimeout = max(0.05, orderLoadTimeout)
    }

    var isTransitionPending: Bool { transitionState.blocksDuplicateSubmission }
    var transitionMessage: String? { transitionState.message }
    var canRetryTransitionConfirmation: Bool {
        if case .confirmationDelayed = transitionState { return true }
        return false
    }

    var canAccept: Bool {
        order?.status == .pendingMatch
    }

    var canShowPhone: Bool {
        guard let order else { return false }
        return order.status != .pendingMatch && order.blindPhone?.trimmed.isEmpty == false
    }

    func configure(with appState: AppState, speechService: SpeechService) {
        self.appState = appState
        self.speechService = speechService
        if realtimeRefreshCancellable == nil {
            realtimeRefreshCancellable = appState.realtimeCoordinator.$pendingOrderRefreshIDs
                .receive(on: DispatchQueue.main)
                .sink { [weak self] orderIDs in
                    guard let self, let orderID = self.order?.orderId, orderIDs.contains(orderID) else { return }
                    Task { await self.load(orderId: orderID) }
                }
        }
        if realtimeStatusCancellable == nil {
            realtimeStatusCancellable = appState.realtimeCoordinator.statusUpdatePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] update in
                    guard let self,
                          let current = self.order,
                          current.orderId == update.orderId else { return }
                    self.apply(
                        current.replacingStatus(with: update.toStatus),
                        speakChanges: true
                    )
                    self.isLoading = false
                    self.errorMessage = nil
                }
        }
    }

    func load(orderId: Int64) async {
        guard let appState else { return }
        appState.realtimeCoordinator.registerActiveOrder(orderId)
        var refreshedAuthoritativeOrder = false
        defer {
            if refreshedAuthoritativeOrder {
                appState.realtimeCoordinator.completeOrderRefresh(orderId)
            } else {
                appState.realtimeCoordinator.failOrderRefresh(orderId)
            }
        }
        isLoading = order == nil
        errorMessage = nil

        do {
            let orders = appState.orders
            let requestToken = appState.realtimeCoordinator.beginOrderStatusRequest(orderID: orderId)
            let candidate: OrderDetailResponse = try await HomeLoadCoordinator.run(
                timeout: orderLoadTimeout,
                operationName: "volunteer-order-detail"
            ) {
                try await orders.orderDetail(orderId: orderId)
            }
            guard let loaded = appState.realtimeCoordinator.reconcileOrderDetail(
                candidate,
                requestToken: requestToken
            ) else {
                isLoading = false
                return
            }
            refreshedAuthoritativeOrder = true
            apply(loaded, speakChanges: false)
            isLoading = false
        } catch let error as APIError {
            isLoading = false
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isLoading = false
            errorMessage = "订单加载失败，请重试"
            speechService?.speakError("订单加载失败，请重试")
        }
    }

    func accept(currentLocation: CLLocationCoordinate2D?, locationAuthorized: Bool) async {
        guard let order, let appState else { return }
        if let message = VolunteerOrderActionGuard.acceptBlockMessage(
            profile: appState.volunteerProfile,
            registrationStatus: appState.volunteerRegistrationStatus,
            locationAuthorized: locationAuthorized
        ) {
            errorMessage = message
            speechService?.speakError(message)
            return
        }
        VolunteerLocationReporter.reportIfNeeded(
            appState: appState,
            currentLocation: currentLocation,
            locationAuthorized: locationAuthorized
        )
        let orders = appState.orders
        let orderID = order.orderId
        await submitTransition(target: .pendingAccept, orderID: orderID, appState: appState) {
            try await orders.respond(orderId: orderID, action: .accept)
        }
    }

    func enRoute() async {
        guard let order, let appState else { return }
        let orders = appState.orders
        let orderID = order.orderId
        await submitTransition(target: .driverEnRoute, orderID: orderID, appState: appState) {
            try await orders.enRoute(orderId: orderID)
        }
    }

    func arrive() async {
        guard let order, let appState else { return }
        let orders = appState.orders
        let orderID = order.orderId
        await submitTransition(target: .driverArrived, orderID: orderID, appState: appState) {
            try await orders.arrived(orderId: orderID)
        }
    }

    func startService() async {
        guard let order, let appState else { return }
        guard order.status.canStartService else {
            let message = order.status.startServiceBlockedMessage
            errorMessage = message
            speechService?.speakError(message)
            return
        }
        let orders = appState.orders
        let orderID = order.orderId
        await submitTransition(target: .inProgress, orderID: orderID, appState: appState) {
            try await orders.startService(orderId: orderID)
        }
    }

    func cancel() async {
        guard let order, let appState else { return }
        let orders = appState.orders
        let orderID = order.orderId
        await submitTransition(target: .rematching, orderID: orderID, appState: appState) { [weak self] in
            // 在闭包里而不是调用前 `begin()`：`submitTransition` 遇到重复提交会直接返回、不发请求，
            // 那时不该把这一单标成「我自己取消的」。
            await self?.beginCancellation()
            let response = try await orders.cancel(orderId: orderID)
            await self?.recordCancelResponse(response)
        }
        // 明确失败才复位；结果未知（超时 / 断网）时留着 —— 取消可能已经成功，确认拉取回来还要用它。
        if case .failed = transitionState {
            cancelAnnouncement = VolunteerCancelAnnouncement()
        }
    }

    func beginCancellation() {
        cancelAnnouncement.begin()
    }

    /// 取消响应到了。推送若已先到、取消那一句已在念，「已记一次临时取消」排在它后面补一句。
    /// 用 `.onDemand` 档：比正在念的那句（`.counterpartAction`）低一档才会排队而不是打断；
    /// 而它本来就是陪跑员自己按下「仍然取消」的回应。
    func recordCancelResponse(_ response: CancelOrderResponse) {
        if let followUp = cancelAnnouncement.recordResponse(response) {
            speechService?.speak(followUp, priority: .onDemand)
        }
    }

    /// 走 `speakStatusChange(_:text:)`：与首页那条状态订阅共用同一个去重键（两边都订阅了这条推送），
    /// 也带上这一态的震动。首页先念了的话，这里只补「已记一次临时取消」。
    private func announceCancellation(entering status: RunOrderStatus) {
        let speech = speechService
        if let followUp = cancelAnnouncement.announceCancellation(speak: { sentence in
            speech?.speakStatusChange(status, text: sentence) ?? false
        }) {
            speech?.speak(followUp, priority: .onDemand)
        }
    }

    func retryTransitionConfirmation() {
        guard let order, let appState, let target = transitionState.targetStatus else { return }
        transitionState = .awaitingConfirmation(target: target)
        errorMessage = nil
        startTransitionConfirmation(orderID: order.orderId, target: target, appState: appState)
    }

    private func submitTransition(
        target: RunOrderStatus,
        orderID: Int64,
        appState: AppState,
        operation: @escaping @concurrent @Sendable () async throws -> Void
    ) async {
        guard !isPerformingAction else { return }
        if transitionState.blocksDuplicateSubmission {
            guard transitionState.targetStatus != target else { return }
            let message = "上一项操作的状态尚未确认，请先重新确认状态。"
            errorMessage = message
            speechService?.speakError(message)
            return
        }
        confirmationTask?.cancel()
        confirmationTask = nil
        transitionState = .submitting(target: target)
        ClientFlowDiagnostics.record(event: "submitted", operation: "volunteer-detail-transition") // guard:allow legacy-status 诊断事件名，非订单状态
        isPerformingAction = true
        errorMessage = nil
        needsCertificateUpload = false
        defer { isPerformingAction = false }
        do {
            try await withVolunteerOrderActionDeadline(
                nanoseconds: actionDeadlineNanoseconds,
                operation: operation
            )
            transitionState = .awaitingConfirmation(target: target)
            ClientFlowDiagnostics.record(event: "awaiting_confirmation", operation: "volunteer-detail-transition")
            startTransitionConfirmation(orderID: orderID, target: target, appState: appState)
        } catch VolunteerOrderActionError.timedOut {
            markTransitionOutcomeUnknown(target: target, orderID: orderID, appState: appState)
        } catch let error as APIError {
            if appState.handleAuthenticatedAPIError(error) {
                transitionState = .failed(message: error.localizedMessage)
                return
            }
            switch error {
            case .networkError, .decodingError:
                markTransitionOutcomeUnknown(target: target, orderID: orderID, appState: appState)
            case .serverError, .rateLimited, .unknown, .invalidURL, .missingCredentials:
                transitionState = .failed(message: error.localizedMessage)
                // 403 VOLUNTEER_NOT_VERIFIED 的唯一解法是上传资质证书，错误区必须给出入口。
                needsCertificateUpload = error.errorCode == .volunteerNotApproved
                errorMessage = error.localizedMessage
                speechService?.speakError(error.localizedMessage)
            case .unauthorized:
                transitionState = .failed(message: error.localizedMessage)
            }
        } catch {
            markTransitionOutcomeUnknown(target: target, orderID: orderID, appState: appState)
        }
    }

    private func markTransitionOutcomeUnknown(
        target: RunOrderStatus,
        orderID: Int64,
        appState: AppState
    ) {
        transitionState = .awaitingConfirmation(target: target)
        speechService?.speakError("操作结果尚未确认，正在后台同步状态。请勿重复提交同一操作。")
        startTransitionConfirmation(orderID: orderID, target: target, appState: appState)
    }

    private func startTransitionConfirmation(
        orderID: Int64,
        target: RunOrderStatus,
        appState: AppState
    ) {
        confirmationTask?.cancel()
        let orders = appState.orders
        let requestToken = appState.realtimeCoordinator.beginOrderStatusRequest(orderID: orderID)
        confirmationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let candidate: OrderDetailResponse = try await HomeLoadCoordinator.run(
                    timeout: self.confirmationTimeout,
                    operationName: "volunteer-detail-transition-confirmation"
                ) {
                    try await orders.orderDetail(orderId: orderID)
                }
                guard !Task.isCancelled,
                      self.order?.orderId == orderID,
                      self.transitionState.targetStatus == target else { return }
                guard let updated = appState.realtimeCoordinator.reconcileOrderDetail(
                    candidate,
                    requestToken: requestToken
                ) else { return }
                self.apply(updated, speakChanges: true)
                if !updated.status.satisfiesVolunteerTransition(target: target) {
                    self.transitionState = .confirmationDelayed(target: target)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled,
                      self.order?.orderId == orderID,
                      self.transitionState.targetStatus == target else { return }
                self.transitionState = .confirmationDelayed(target: target)
                ClientFlowDiagnostics.record(event: "confirmation_delayed", operation: "volunteer-detail-transition")
            }
            self.confirmationTask = nil
        }
    }

    private func apply(_ updated: OrderDetailResponse, speakChanges: Bool) {
        let previousStatus = order?.status
        order = updated
        appState?.liveEscortCoordinator.updateOwnedOrder(orderID: updated.orderId, status: updated.status)
        // 要念取消那一句时不念通用状态句：两句都念的话，后一句同档打断前一句，
        // 陪跑员听到的是半句盲人端文案加一句取消说明。
        let announcesCancellation = cancelAnnouncement.announcesCancellation(entering: updated.status)
        if speakChanges, previousStatus != updated.status, !announcesCancellation {
            speechService?.speakVolunteerStatusChange(updated.status)
        }
        if let target = transitionState.targetStatus,
           updated.status.satisfiesVolunteerTransition(target: target) {
            transitionState = .idle
            ClientFlowDiagnostics.record(event: "confirmed", operation: "volunteer-detail-transition")
            confirmationTask?.cancel()
            confirmationTask = nil
            errorMessage = nil
        }
        if updated.status == .rematching || updated.status == .cancelled {
            appState?.realtimeCoordinator.unregisterActiveOrder(updated.orderId)
            appState?.liveEscortCoordinator.clearOwnedOrder()
            didCancelOrder = true
            // 只在**进入**这一态时念一次：确认拉取与推送都会走到这里，各念一遍就是两遍。
            // 跑者取消的 `CANCELLED` 不念这句，由上面的通用状态句说。
            if announcesCancellation, previousStatus != updated.status {
                announceCancellation(entering: updated.status)
            }
        }
    }
}
