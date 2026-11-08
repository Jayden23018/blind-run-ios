import SwiftUI

extension BlindOrderStatusViewModel {
    /// - Parameter speechInputService: 「问一句」用。可选是为了让既有的一批单测不必凭空造一个
    ///   麦克风服务；传 nil 时按下按钮不会起听（`VoiceStatusQuerySession.ask` 自己 guard 掉）。
    func configure(
        appState: AppState,
        speechService: SpeechService,
        locationService: LocationService? = nil,
        speechInputService: SpeechInputService? = nil,
        placeSearchProvider: (any PlaceSearchProviding)? = nil
    ) {
        self.appState = appState
        self.speechService = speechService
        self.locationService = locationService
        self.placeSearchProvider = placeSearchProvider
        // 坐标取 `latestVolunteerCoordinate` 而不是重算一遍：它已经过了新鲜度闸
        // （WebSocket 那条由订单跟踪判新鲜度，过期时收到 `.peerLocationExpired` 清空）。
        voiceQuerySession.configure(
            speechService: speechService,
            speechInputService: speechInputService,
            context: { [weak self] in (self?.order, self?.latestVolunteerCoordinate) }
        )
        openOrderTrackIfNeeded(appState: appState)
    }

    func startPolling(orderId: Int64) {
        if currentOrderId != orderId {
            clearPeerLocation()
            // 上限是**这一单**的属性，不是这个 view model 的。换单不清会让新订单
            // 一进来就少一个本来该有的动作。
            keepWaitingLimitReached = false
            // 同理：状态记录是按单的，留着就会把上一单的内容展示在这一单下面。
            statusLogs = []
            statusLogsErrorMessage = nil
            // 轨迹统计同理，而且更要紧：它是屏幕上最大的那个数字，串单等于显示上一次的里程。
            // 里程碑基线一起清 —— 不清的话新单一开跑就会从上一单的公里数接着算。
            trackStats = nil
            lastTrackFetchAt = nil
            didFetchFinalTrack = false
            kilometerMilestones.reset()
            // 上一单没来得及播的那句完成播报不许跟到新一单上 —— 那会在一张刚下的单上
            // 念「结束了本次陪跑」。
            completionTask?.cancel()
            completionTask = nil
            // 换单时倒计时同样按单清。上一单遗留的任务会往新一单的屏幕上写数字。
            cancelRunCountdown()
            lastArrivalCancelGate = nil
        }
        currentOrderId = orderId
        // 登记活跃订单、（重）开 5 秒轮询并立即拉一次、开始收对方位置，都在订单跟踪里。
        // 轮询顺序（判停 → 睡 → 拉）与暂缓中（#376）连第一次也不拉，见 `OrderPollingPolicy.blindRunner`。
        orderTrack?.follow(orderID: orderId)
    }

    func stopPolling() {
        // 停轮询、停收对方位置；不注销活跃订单（注销只在 `apply` 的终态分支）。
        orderTrack?.pause()
        // 跟踪那边的 `.peerLocationExpired` 晚一拍才到，这里先同步清掉，离页即清。
        clearPeerLocation()
        cancelRunCountdown()
    }

    /// 取回本单的状态变更记录（`GET /api/orders/{id}/status-logs`，订单双方均可查）。
    ///
    /// 响应是裸数组，后端已按时间**倒序**返回（`OrderStatusLogRepository:16`），这里不重排。
    func loadStatusLogs() async {
        guard let order, let appState else { return }
        isLoadingStatusLogs = true
        statusLogsErrorMessage = nil
        do {
            let logs = try await appState.orders.statusLogs(orderId: order.orderId)
            isLoadingStatusLogs = false
            statusLogs = logs
        } catch let error as APIError {
            isLoadingStatusLogs = false
            if error.endsSession {
                return
            }
            statusLogsErrorMessage = error.localizedMessage
        } catch {
            isLoadingStatusLogs = false
            statusLogsErrorMessage = "获取状态变更记录失败。"
        }
    }

    func loadOrder(orderId: Int64, speakChanges: Bool) async {
        guard let appState else { return }
        var refreshedAuthoritativeOrder = false
        defer {
            if refreshedAuthoritativeOrder {
                appState.realtimeCoordinator.completeOrderRefresh(orderId)
            } else {
                appState.realtimeCoordinator.failOrderRefresh(orderId)
            }
        }
        if order == nil {
            isLoading = true
        }
        errorMessage = nil

        do {
            let requestToken = appState.realtimeCoordinator.beginOrderStatusRequest(orderID: orderId)
            let orders = appState.orders
            let candidate: OrderDetailResponse = try await HomeLoadCoordinator.run(
                timeout: HomeLoadPolicy.defaultTimeout,
                operationName: "blind-order-poll"
            ) {
                try await orders.orderDetail(orderId: orderId)
            }
            guard let updated = appState.realtimeCoordinator.reconcileOrderDetail(
                candidate,
                requestToken: requestToken
            ) else {
                isLoading = false
                return
            }
            refreshedAuthoritativeOrder = true
            isLoading = false
            pollFailureGate.reportSuccess(orderId: orderId, statusWillBeSpoken: speakChanges && order?.status != updated.status && speechService?.lastSpokenStatus != updated.status, to: speechService)
            apply(updated, speakChanges: speakChanges)
            await refreshIntroCallIfNeeded(for: updated, appState: appState)
            await refreshVolunteerLocationFallbackIfNeeded(for: updated, appState: appState)
            // 完成那一轮这里大概率**拉不到**（`apply` 刚刚自我取消了这个任务），
            // 所以终值那一次由 `startCompletionAnnouncement` 的独立任务负责 ——
            // 而 `didFetchFinalTrack` 只在**成功**时置位，这一次失败不会把那条路堵掉。
            await refreshTrackStatsIfNeeded(for: updated, appState: appState)
        } catch let error as APIError {
            isLoading = false
            if error.endsSession { return }
            errorMessage = error.localizedMessage
            pollFailureGate.reportFailure(error.localizedMessage, orderId: orderId, to: speechService)
        } catch {
            isLoading = false
            errorMessage = "获取订单状态失败。"
            pollFailureGate.reportFailure("获取订单状态失败。", orderId: orderId, to: speechService)
        }
    }

    private func performAction(
        failureMessage: String,
        operation: @MainActor () async throws -> Void
    ) async {
        isPerformingAction = true
        errorMessage = nil

        do {
            try await operation()
            isPerformingAction = false
        } catch let error as APIError {
            isPerformingAction = false
            if error.endsSession {
                return
            }
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isPerformingAction = false
            errorMessage = failureMessage
            speechService?.speakError(failureMessage)
        }
    }

    /// - Returns: 这一次念没念状态句（首页据此决定念不念，design §6）。完成那句走独立任务，算没念。
    @discardableResult
    func apply(_ updated: OrderDetailResponse, speakChanges: Bool) -> Bool {
        let previousStatus = order?.status
        order = updated
        announceArrivalCancelUnlockIfNeeded(for: updated, speakChanges: speakChanges)
        appState?.liveEscortCoordinator.updateOwnedOrder(orderID: updated.orderId, status: updated.status)
        // 锁屏卡顶行那句「陪跑中 · 张」。姓氏只有这一端拿得到，所以**排在
        // `updateOwnedOrder` 之后** —— 换单时它内部会 `clearRuntimeSession()`，
        // 那里要清掉上一单的名字，排在前面会被当场擦掉。
        // 名字住在 `ContentState` 里（不是 `attributes`），所以后到也补得上，见那里的注释。
        appState?.liveEscortCoordinator.updateLiveActivityPartnerName(updated.volunteerSurname?.nilIfBlank)
        refreshVolunteerDistance()
        updateRunCountdown(from: previousStatus, to: updated.status)
        var spokeStatus = false
        if speakChanges, previousStatus != updated.status {
            if let completion = Self.completionAnnouncement(from: previousStatus, to: updated.status) {
                // 不在这里播 —— 里程要等 `/track` 的终值回来，而这一刻紧接着就要自我取消。
                startCompletionAnnouncement(completion, order: updated)
            } else {
                // 被去重挡掉（这一态已念过）算没念：首页再念也同样会被挡掉。
                spokeStatus = speechService?.speakBlindRunnerStatusChange(
                    updated,
                    text: statusChangeAnnouncement(from: previousStatus, to: updated)
                ) ?? false
            }
        }
        if updated.status != .pendingIntroCall {
            clearIntroCallState()
        }
        if !updated.status.shouldPoll {
            appState?.realtimeCoordinator.unregisterActiveOrder(updated.orderId)
            if updated.status != .completed {
                appState?.liveEscortCoordinator.clearOwnedOrder()
            }
            stopPolling()
        }
        return spokeStatus
    }
}
