import CoreLocation
import SwiftUI

extension VolunteerHomeViewModel {
    /// 摘要的唯一漏斗 —— 冷启动首屏、下拉刷新、接单后回读全从这里过，
    /// 所以 `recoverIntroCallIfNeeded` 挂在这里就够，不必在每个调用点各接一次。
    ///
    /// 非 private 是为了让单测能直接喂一份摘要进来：起真实的加载流程会顺带打三四个端点、
    /// 动状态机，把「摘要里有 introCallOrderId 会怎样」这一条断言埋进一堆无关请求里。
    func apply(
        summary: VolunteerDispatchSummaryResponse,
        statusRequestToken: OrderStatusRequestToken? = nil,
        requestedAt: Date? = nil
    ) {
        let previousOrderID = activeOrder?.orderId
        dispatchSummary = summary
        isAvailable = summary.wantsDispatch ?? isAvailable
        if let active = summary.activeOrders?.first {
            let candidate = active.orderDetail
            if let statusRequestToken,
               statusRequestToken.orderID == candidate.orderId {
                activeOrder = appState?.realtimeCoordinator.reconcileOrderDetail(
                    candidate,
                    requestToken: statusRequestToken
                )
            } else {
                activeOrder = candidate
                appState?.realtimeCoordinator.registerActiveOrder(
                    candidate.orderId,
                    status: candidate.status
                )
            }
        } else if let statusRequestToken,
                  appState?.realtimeCoordinator.isOrderStatusRequestCurrent(statusRequestToken) == false {
            ClientFlowDiagnostics.record(
                event: "late_empty_discarded",
                operation: "volunteer-summary-refresh"
            )
        } else {
            activeOrder = nil
        }
        if let previousOrderID, previousOrderID != activeOrder?.orderId {
            appState?.realtimeCoordinator.unregisterActiveOrder(previousOrderID)
        }
        if let activeOrder {
            appState?.liveEscortCoordinator.updateOwnedOrder(
                orderID: activeOrder.orderId,
                status: activeOrder.status
            )
        } else {
            appState?.liveEscortCoordinator.clearOwnedOrder()
        }
        // 订单交给协调器之后再判：协调器这时才答得出这一单要不要问同一件事（#420）。
        requestTrackConsentIfStandbyResumesWithoutIt()
        if let upcoming = summary.upcomingOrders,
           (requestedAt ?? .distantFuture) >= (scheduledOrdersChangedLocallyAt ?? .distantPast) {
            applyUpcoming(fromSummary: upcoming)
        }
        recoverIntroCallIfNeeded(summary: summary)
        // 三岔路的「有进行中订单」那一岔在这里就判得了。另一岔（2 小时内开始的陪跑）：摘要带了 `upcomingOrders`
        // 时这里也判得了（#471）；没带时等 `startAuxiliaryLoad` 回落的那两条请求回来，在它的收尾里判。
        resolveLaunchRouteIfNeeded()
    }

    /// 冷启动恢复：App 被杀之后回到那一通没打完的电话。
    ///
    /// 🚨 **这不是「顺手多接一个字段」，它补的是一个真实的失联**：通话磨合态
    /// `order.volunteer` 还是 null ⇒ `GET /api/orders/{id}` 恒 403、`/api/orders/mine` 也不返回，
    /// 而派单推送不会重放 —— 志愿者重开 App 之后**没有任何入口**回到通话页，
    /// 只能等 20 分钟窗口超时，而盲人在等他这通电话。
    /// `introCallOrderId` 是那一刻唯一的线索（后端为此专门加的字段）。
    ///
    /// 三道闸缺一不可：
    /// 1. `introCallOrderId` 非空 —— 绝大多数时候它是 null。
    /// 2. `pendingIntroCallOrder == nil` —— 已经在通话页上了就别再动导航。
    /// 3. `autoOpenedIntroCallOrderId != id` —— **同一单只自动跳一次**。
    ///    没有第 3 条，用户手动返回后每次摘要刷新都会把他拽回去，20 分钟内出不来。
    ///
    /// `dispatchOrder` 传 nil：那条推送早随进程一起没了，客户端拿不回来，也不许编。
    private func recoverIntroCallIfNeeded(summary: VolunteerDispatchSummaryResponse) {
        guard let introCallOrderId = summary.introCallOrderId,
              pendingIntroCallOrder == nil,
              autoOpenedIntroCallOrderId != introCallOrderId else { return }
        autoOpenedIntroCallOrderId = introCallOrderId
        pendingIntroCallOrder = VolunteerIntroCallRoute(orderId: introCallOrderId)
    }

    /// 冷启动三岔路（设计交付 v3 §4.1）：有进行中订单或 2 小时内开始的陪跑就直接进订单页。
    ///
    /// 调用点有两个，都在**首次加载**这一轮上：`apply(summary:)` 末尾（在途订单那一岔，
    /// 不必等预约单那条请求回来）、`applyUpcoming(scheduled:pendingAccept:)` 之后（预约单那一岔）。
    /// 窗口由 `didResolveLaunchRoute` 关上 —— 见它的注释，那不是优化。
    ///
    /// 🚩 **复用派单接单后那条既有导航**（`acceptedDispatchOrderId` + 首页 tab 的
    /// `navigationDestination`），不另起一条路由：要去的是同一个页面。
    /// `confirmScheduledDeparture` 也是这么做的。
    ///
    /// 🚩 通话磨合让路：`pendingIntroCallOrder` 在场时一律不动。那一态有 20 分钟窗口、
    /// 对面有人在等电话，而订单页随时可以再进（`navigationDestination` 里的顺序也是这个优先级）。
    ///
    /// 🚩 **邀请卡的结果卡同样让路，理由一模一样。** 刚接下那一刻屏幕上是「已约好」，
    /// 而它是唯一一处告诉陪跑员「跑者的全名和电话已经放进订单」的地方（设计交付 v3 §4.4.3）。
    /// 这一岔会在**首次加载还没跑完时收到派单**的情况下真的撞上：首次加载的窗口还开着，
    /// 而接单后的 `refreshAfterDispatchResponse` 会再走一遍 `apply(summary:)` ——
    /// 于是这条路由把那张确认卡一闪而过。由
    /// `testAcceptingDispatchShowsTheBookedCardAndOnlyNavigatesOnTap` 红出来。
    func resolveLaunchRouteIfNeeded() {
        guard !didResolveLaunchRoute,
              pendingIntroCallOrder == nil,
              acceptedDispatchOrderId == nil,
              invites.allSatisfy(\.isAwaitingReply),
              let order = Self.launchOrderToOpen(
                  activeOrder: activeOrder,
                  scheduledOrders: scheduledOrders,
                  // 后端下发（`GET /api/config/rules`），拉不到时是默认 120 分钟。
                  leadMinutes: (appState?.ruleParams ?? .fallback).volunteerOrderAutoOpenLeadMinutes
              ) else { return }
        didResolveLaunchRoute = true
        // 带上手里这份详情当初值，订单页就不必空着等第一次 GET 回来。
        acceptedDispatchInitialOrder = order
        acceptedDispatchOrderId = order.orderId
    }

    func refreshDispatchSummary() async {
        guard let appState else { return }
        // 整页刷新在跑就等它，它本身就会拉派单摘要。
        if pageRefresh.isRunning {
            ClientFlowDiagnostics.record(event: "coalesced", operation: "volunteer-summary-refresh")
            await pageRefresh.join()
            return
        }
        if summaryRefresh.isRunning {
            ClientFlowDiagnostics.record(event: "coalesced", operation: "volunteer-summary-refresh")
        }
        let outcome = await summaryRefresh.run { _ in
            ClientFlowDiagnostics.record(event: "started", operation: "volunteer-summary-refresh")
        } work: { [weak self, weak appState] ticket in
            guard let self, let appState else { return }
            await self.performDispatchSummaryRefresh(appState: appState, ticket: ticket)
        }
        if outcome == .finished {
            ClientFlowDiagnostics.record(event: "finished", operation: "volunteer-summary-refresh")
        }
    }

    private func performDispatchSummaryRefresh(appState: AppState, ticket: RefreshTicket) async {
        do {
            let orders = appState.orders
            let statusRequestToken = activeOrder.map {
                appState.realtimeCoordinator.beginOrderStatusRequest(orderID: $0.orderId)
            }
            let requestedAt = Date()
            let summary: VolunteerDispatchSummaryResponse = try await HomeLoadCoordinator.run(
                timeout: loadTimeout,
                operationName: "volunteer-dispatch-refresh"
            ) {
                try await orders.dispatchSummary()
            }
            guard !Task.isCancelled, summaryRefresh.isCurrent(ticket) else { return }
            apply(summary: summary, statusRequestToken: statusRequestToken, requestedAt: requestedAt)
            dispatchLoadState = .loaded(summary)
            dispatchSummaryErrorMessage = nil
        } catch HomeLoadCoordinatorError.timedOut {
            guard !Task.isCancelled, summaryRefresh.isCurrent(ticket) else { return }
            dispatchSummaryErrorMessage = "派单状态刷新超过 20 秒，请重试"
        } catch let error as APIError {
            guard !Task.isCancelled, summaryRefresh.isCurrent(ticket) else { return }
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            dispatchSummaryErrorMessage = error.localizedMessage
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, summaryRefresh.isCurrent(ticket) else { return }
            dispatchSummaryErrorMessage = "派单状态刷新失败，请重试"
        }
    }

    func startRefreshLoop() {
        guard isSceneActive, refreshLoopTask == nil else { return }
        refreshLoopTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.isSceneActive {
                do {
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled, self.isSceneActive else { return }
                await self.reportLocationThenRefreshSummary(
                    currentLocation: self.currentLocationProvider(),
                    locationAuthorized: self.locationAuthorizedProvider()
                )
            }
        }
    }

    func reportLocationThenRefreshSummary(
        currentLocation: CLLocationCoordinate2D?,
        locationAuthorized: Bool
    ) async {
        guard let appState else { return }
        let didReportLocation = reportDispatchLocationIfAllowed(appState, currentLocation, locationAuthorized)
        if didReportLocation {
            try? await Task.sleep(nanoseconds: UInt64(dispatchPropagationDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
        }
        await refreshDispatchSummary()
    }

    func recoverDispatchReadinessAfterReconnect() {
        guard isSceneActive else { return }
        // 断线期间的撤回推送补不回来，重连后以服务端待回复列表为准（契约）。
        if let appState { Task { await appState.restorePendingInvites() } }
        delayedSummaryRefreshTask?.cancel()
        delayedSummaryRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.reportLocationThenRefreshSummary(
                currentLocation: self.currentLocationProvider(),
                locationAuthorized: self.locationAuthorizedProvider()
            )
        }
    }

    /// 为派单上报位置的唯一入口（首屏加载与刷新循环）。#368 之后只在开着接单开关、且同意过
    /// 位置轨迹时才报 —— 同意文案写着「暂停接单后不再为派单获取位置」。不该报时不算失败：
    /// 清掉「定位暂不可用」的提示，否则暂停接单的人会被一句与他无关的警告反复打断。
    @discardableResult
    func reportDispatchLocationIfAllowed(
        _ appState: AppState,
        _ currentLocation: CLLocationCoordinate2D?,
        _ locationAuthorized: Bool
    ) -> Bool {
        guard isAvailable, appState.hasLocationTrackConsent(.volunteerLocationTrack) else {
            consecutiveLocationReportFailures = 0
            locationDispatchWarning = nil
            return false
        }
        let didReportLocation = reportVolunteerLocation(appState, currentLocation, locationAuthorized)
        updateLocationDispatchWarning(didReportLocation: didReportLocation, appState: appState)
        return didReportLocation
    }

    private func updateLocationDispatchWarning(
        didReportLocation: Bool,
        appState: AppState
    ) {
        guard appState.currentEnvironment != .mock else {
            consecutiveLocationReportFailures = 0
            locationDispatchWarning = nil
            return
        }
        if didReportLocation {
            consecutiveLocationReportFailures = 0
            locationDispatchWarning = nil
            return
        }
        consecutiveLocationReportFailures += 1
        // 未达阈值的瞬态失败完全静默：横幅不出现（也就不会闪），更不播报。
        guard consecutiveLocationReportFailures >= Self.locationReportFailureThreshold else { return }
        let message = "定位暂不可用，可能无法收到派单"
        let shouldSpeak = locationDispatchWarning != message
        locationDispatchWarning = message
        if shouldSpeak {
            speechService?.speakError(message)
        }
    }
}
