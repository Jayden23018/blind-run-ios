import SwiftUI

extension VolunteerInServiceViewModel {
    /// - Parameter statusConflictMessage: 409 `ORDER_STATUS_NOT_ALLOWED` 时替换掉那句通用文案。
    ///   加它是因为**同一个错误码在不同动作下要说的话不一样**：`ErrorCode.invalidOrderStatus`
    ///   在后端有 13 个抛出点，全局文案只能是「当前订单状态不允许此操作」，而
    ///   `confirm-departure` 的契约 description 明写这条 409 最常见的成因是
    ///   「闸门已经把这一单退回重新匹配了」，要告诉志愿者「这一单已经转走了」而不是「操作失败」——
    ///   后者会让他以为再点一次就好。默认 nil = 沿用全局文案，其余调用点行为不变。
    func submitTransition(
        target: RunOrderStatus,
        orderID: Int64,
        appState: AppState,
        statusConflictMessage: String? = nil,
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
        ClientFlowDiagnostics.record(event: "submitted", operation: "volunteer-service-transition") // guard:allow legacy-status 诊断事件名，非订单状态
        isPerformingAction = true
        errorMessage = nil
        defer { isPerformingAction = false }
        do {
            try await withVolunteerOrderActionDeadline(
                nanoseconds: actionDeadlineNanoseconds,
                operation: operation
            )
            if discardsResultOfLostOrder() { return }
            transitionState = .awaitingConfirmation(target: target)
            ClientFlowDiagnostics.record(event: "awaiting_confirmation", operation: "volunteer-service-transition")
            startTransitionConfirmation(orderID: orderID, target: target, appState: appState)
            simulateRealtimeConfirmationIfRequested(
                orderID: orderID,
                fromStatus: order?.status,
                target: target,
                appState: appState
            )
        } catch VolunteerOrderActionError.timedOut {
            if discardsResultOfLostOrder() { return }
            markTransitionOutcomeUnknown(target: target, orderID: orderID, appState: appState)
        } catch let error as APIError {
            if appState.handleAuthenticatedAPIError(error) {
                transitionState = .failed(message: error.localizedMessage)
                return
            }
            if discardsResultOfLostOrder() { return }
            switch error {
            case .networkError, .decodingError:
                markTransitionOutcomeUnknown(target: target, orderID: orderID, appState: appState)
            case .serverError(let response) where response.errorCode == .invalidOrderStatus
                && statusConflictMessage != nil:
                // 走到这里说明订单已经不在本次动作的前置状态上了。**同时刷新一次订单**：
                // 只播一句「已经转走了」而屏幕还停在旧状态，等于让志愿者对着一个已经不成立的界面。
                // 先刷新再报：刷新把状态推进时 `apply` 会清错误，反过来写会把这句吞掉。
                let message = statusConflictMessage ?? error.localizedMessage
                transitionState = .failed(message: message)
                await load(orderId: orderID, speakChanges: false)
                errorMessage = message
                speechService?.speakError(message)
            case .serverError, .rateLimited, .unknown, .invalidURL, .missingCredentials:
                transitionState = .failed(message: error.localizedMessage)
                errorMessage = error.localizedMessage
                // 只有 `start-service` 会答这个码。按钮不置灰，换的是按钮上方那行小字。
                if error.errorCode == .blindConfirmationPending { awaitingBlindConfirmation = true }
                speechService?.speakError(error.localizedMessage)
            case .unauthorized:
                transitionState = .failed(message: error.localizedMessage)
            }
        } catch {
            if discardsResultOfLostOrder() { return }
            markTransitionOutcomeUnknown(target: target, orderID: orderID, appState: appState)
        }
    }

    private func simulateRealtimeConfirmationIfRequested(
        orderID: Int64,
        fromStatus: RunOrderStatus?,
        target: RunOrderStatus,
        appState: AppState
    ) {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_CONFIRM_TRANSITION_VIA_REALTIME"] == "1",
              let fromStatus else { return }
        Task { @MainActor in
            await Task.yield()
            appState.realtimeCoordinator.simulateIncomingEventForTesting(
                .orderStatusChanged(
                    WSOrderStatusChanged(
                        type: WSMessageType.orderStatusChanged.rawValue,
                        orderId: orderID,
                        fromStatus: fromStatus.rawValue,
                        toStatus: target.rawValue,
                        message: nil,
                        ttsText: nil,
                        priority: "NORMAL",
                        timestamp: nil
                    )
                )
            )
        }
        #endif
    }

    private func markTransitionOutcomeUnknown(
        target: RunOrderStatus,
        orderID: Int64,
        appState: AppState
    ) {
        transitionState = .awaitingConfirmation(target: target)
        let message = "操作结果尚未确认，正在后台同步状态。请勿重复提交同一操作。"
        errorMessage = nil
        speechService?.speakError(message)
        startTransitionConfirmation(orderID: orderID, target: target, appState: appState)
    }

    func startTransitionConfirmation(
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
                    operationName: "volunteer-transition-confirmation"
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
                    self.errorMessage = nil
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled,
                      self.order?.orderId == orderID,
                      self.transitionState.targetStatus == target else { return }
                self.transitionState = .confirmationDelayed(target: target)
                ClientFlowDiagnostics.record(event: "confirmation_delayed", operation: "volunteer-service-transition")
                self.errorMessage = nil
            }
            self.confirmationTask = nil
        }
    }
}
