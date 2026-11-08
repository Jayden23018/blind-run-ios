import CoreLocation
import SwiftUI

extension VolunteerHomeViewModel {
    /// 「当前订单」不再属于这位陪跑员：状态推送进了非活跃态，或失联事件把它转走了（#456）。
    func dropActiveOrder(_ orderID: Int64) {
        activeOrder = nil
        appState?.realtimeCoordinator.unregisterActiveOrder(orderID)
        appState?.liveEscortCoordinator.clearOwnedOrder()
    }

    func load(currentLocation: CLLocationCoordinate2D?, locationAuthorized: Bool) async {
        guard let appState else { return }
        if pageRefresh.isRunning {
            ClientFlowDiagnostics.record(event: "coalesced", operation: "volunteer-home-refresh")
        }
        let outcome = await pageRefresh.run { [weak self, weak appState] ticket in
            ClientFlowDiagnostics.record(event: "started", operation: "volunteer-home-refresh")
            guard let self, let appState else { return }
            // 冷启动与下拉刷新各对一次待回复邀请（后端 #366）。并行发、不等它：首页不该被它拖住。
            Task { await appState.restorePendingInvites() }
            // 规则参数（自动打开订单页的提前量、取消弹层的窗口）并行拉，**不等它**：
            // 它挂住时不该把整个首页拖住（URLSession 超时 15 秒）。
            // ponytail: 首次冷启动若规则晚于派单摘要回来，那一次的自动打开按默认 120 分钟判
            // （与后端默认值相同）；要严格按下发值，得把 `resolveLaunchRouteIfNeeded` 改成规则到达后再判一次。
            Task { await appState.loadRuleParamsIfNeeded() }
            if self.dispatchSummary == nil {
                self.dispatchLoadState = .loading(requestID: ticket.id)
            }
            self.errorMessage = nil
            self.dispatchSummaryErrorMessage = nil
        } work: { [weak self, weak appState] ticket in
            guard let self, let appState else { return }
            await self.performInitialLoad(
                appState: appState,
                ticket: ticket,
                currentLocation: currentLocation,
                locationAuthorized: locationAuthorized
            )
        }

        switch outcome {
        case .finished:
            ClientFlowDiagnostics.record(event: "finished", operation: "volunteer-home-refresh")
            if dispatchLoadState.isLoading {
                if let dispatchSummary {
                    dispatchLoadState = .loaded(dispatchSummary)
                } else {
                    dispatchLoadState = .failed(message: "派单状态加载失败，请重试。")
                }
            }
        case .cancelled:
            // 被取消的请求不写内容、不写失败文案；首次加载回 `.idle`。已有新的一次在跑就不碰。
            if !pageRefresh.isRunning { cancelLoading() }
        case .joined:
            break
        }
    }

    func cancelLoading() {
        pageRefresh.cancel()
        auxiliaryLoadTask?.cancel()
        auxiliaryLoadTask = nil
        auxiliaryRequestID = nil
        if dispatchLoadState.isLoading {
            if let dispatchSummary {
                dispatchLoadState = .loaded(dispatchSummary)
            } else {
                dispatchLoadState = .idle
            }
        }
    }

    private func performInitialLoad(
        appState: AppState,
        ticket: RefreshTicket,
        currentLocation: CLLocationCoordinate2D?,
        locationAuthorized: Bool
    ) async {
        reportDispatchLocationIfAllowed(appState, currentLocation, locationAuthorized)

        do {
            let orders = appState.orders
            let requestedAt = Date()
            let summary: VolunteerDispatchSummaryResponse = try await HomeLoadCoordinator.run(
                timeout: loadTimeout,
                operationName: "volunteer-dispatch-initial"
            ) {
                try await orders.dispatchSummary()
            }
            guard pageRefresh.isCurrent(ticket), !Task.isCancelled else { return }
            apply(summary: summary, requestedAt: requestedAt)
            dispatchLoadState = .loaded(summary)
            dispatchSummaryErrorMessage = nil
        } catch HomeLoadCoordinatorError.timedOut {
            guard pageRefresh.isCurrent(ticket), !Task.isCancelled else { return }
            let message = "加载超过 20 秒，请重试。"
            dispatchSummaryErrorMessage = message
            dispatchLoadState = dispatchSummary.map(AsyncLoadState.loaded) ?? .failed(message: message)
            speechService?.speakError(message)
        } catch let apiError as APIError {
            guard pageRefresh.isCurrent(ticket), !Task.isCancelled else { return }
            if appState.handleAuthenticatedAPIError(apiError) { return }
            dispatchSummaryErrorMessage = apiError.localizedMessage
            dispatchLoadState = dispatchSummary.map(AsyncLoadState.loaded) ?? .failed(message: apiError.localizedMessage)
            speechService?.speakError(apiError.localizedMessage)
        } catch is CancellationError {
            return
        } catch {
            guard pageRefresh.isCurrent(ticket), !Task.isCancelled else { return }
            let message = "派单状态加载失败，请重试。"
            dispatchSummaryErrorMessage = message
            dispatchLoadState = dispatchSummary.map(AsyncLoadState.loaded) ?? .failed(message: message)
            speechService?.speakError(message)
        }

        guard pageRefresh.isCurrent(ticket), !Task.isCancelled else { return }
        startAuxiliaryLoad(appState: appState)
    }

    private func startAuxiliaryLoad(appState: AppState) {
        auxiliaryLoadTask?.cancel()
        let requestID = UUID()
        auxiliaryRequestID = requestID
        // 这两条是**档案·资质片**的端点（`ProfileServing.volunteerProfile` /
        // `.volunteerRegistrationStatus`），不在订单片里再开一条同路径 ——
        // 同一个端点两处字面量迟早漂移。
        //
        // 它们原先暂放在 `AuthServing` 上（订单片就是照那个写的），档案片落 main 时
        // 搬回了自己家。两片并行开发看不见对方的搬迁，这里跟着改指向。
        let profile = appState.profile
        auxiliaryLoadTask = Task { [weak self, weak appState] in
            guard let self, let appState else { return }
            async let profileResult: Result<VolunteerProfileResponse, Error> = Self.fetchResult {
                try await HomeLoadCoordinator.run(
                    timeout: self.loadTimeout,
                    operationName: "volunteer-profile"
                ) {
                    try await profile.volunteerProfile()
                }
            }
            async let registrationResult: Result<VolunteerRegistrationStatus, Error> = Self.fetchResult {
                try await HomeLoadCoordinator.run(
                    timeout: self.loadTimeout,
                    operationName: "volunteer-registration"
                ) {
                    try await profile.volunteerRegistrationStatus()
                }
            }

            // 「接下来要去的单」：派单摘要带了 `upcomingOrders`（#471）就不再打这两条；没带（`nil`）才回落。
            let lists = self.dispatchSummary?.upcomingOrders == nil
                ? await self.fetchUpcomingOrderLists(appState.orders) : nil
            let (profile, registration) = await (profileResult, registrationResult)
            guard !Task.isCancelled, self.auxiliaryRequestID == requestID else { return }
            if case .success(let value) = profile {
                appState.updateVolunteerProfile(value)
                self.apply(profile: value)
            }
            if case .success(let value) = registration {
                appState.updateVolunteerRegistrationStatus(value)
            }
            if let lists { self.applyUpcoming(scheduled: lists.scheduled, pendingAccept: lists.pendingAccept) }
            // 三岔路的另一岔（2 小时内开始的陪跑）只有等这条请求回来才判得了 —— 跨天预约单
            // 不在 `dispatch-summary` 里。判完这一轮就关窗，之后每 10 秒的刷新不再自动导航。
            self.resolveLaunchRouteIfNeeded()
            self.didResolveLaunchRoute = true
            self.auxiliaryLoadTask = nil
            self.auxiliaryRequestID = nil
        }
    }

    nonisolated static func fetchResult<Value: Sendable>(
        operation: @escaping @concurrent @Sendable () async throws -> Value
    ) async -> Result<Value, Error> {
        do { return .success(try await operation()) }
        catch { return .failure(error) }
    }
}
