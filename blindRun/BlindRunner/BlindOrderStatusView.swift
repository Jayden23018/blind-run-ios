import Combine
import CoreLocation
import SwiftUI

// MARK: - Blind Order Status ViewModel

@MainActor
final class BlindOrderStatusViewModel: ObservableObject {
    @Published var order: OrderDetailResponse?
    @Published var isLoading = false
    @Published var isPerformingAction = false
    @Published var isSubmittingReview = false
    @Published var reviewRating = 5
    @Published var reviewComment = ""
    @Published var didSubmitReview = false
    /// 本单已有的评价。**离开页面再回来时唯一的真相来源** —— `didSubmitReview` 是进程内的一次性标记，
    /// 重进这一单它就回到 false，评价表单会再摆一次，提交后只能收到 409 `REVIEW_ALREADY_SUBMITTED`。
    @Published private(set) var existingReview: OrderReview?
    @Published private(set) var statusLogs: [OrderStatusLog] = []
    @Published private(set) var isLoadingStatusLogs = false
    /// 状态记录单独一条错误，不复用 `errorMessage`：那条会被 `speakError` 念出来，
    /// 而这是用户主动展开的一块辅助信息，加载失败不该打断正在进行的服务播报。
    @Published private(set) var statusLogsErrorMessage: String?
    @Published var volunteerDistanceToStartText: String?
    @Published private(set) var latestVolunteerSample: LocatedCoordinate?
    @Published var errorMessage: String?
    /// 本单是否已经用完延长次数。**按单记**，换单时清空（见 `startPolling`）。
    @Published private(set) var keepWaitingLimitReached = false

    private weak var appState: AppState?
    private var speechService: SpeechService?
    private weak var locationService: LocationService?
    private var pollingTask: Task<Void, Never>?
    private var currentOrderId: Int64?
    private var latestVolunteerCoordinate: CLLocationCoordinate2D?
    private var latestVolunteerWebSocketDate: Date?
    private var peerExpiryTask: Task<Void, Never>?
    private var acceptsPeerLocations = true
    private var cancellables = Set<AnyCancellable>()
    private let voiceQuerySession = VoiceStatusQuerySession()
    private let peerFreshness: TimeInterval

    init(peerFreshness: TimeInterval = LiveEscortSessionCoordinator.peerFreshness) {
        self.peerFreshness = max(0.01, peerFreshness)
    }

    /// Active blind-runner orders keep the 5-second REST fallback even when WebSocket is connected.
    var effectivePollingInterval: TimeInterval {
        return AppConstants.Timing.orderPollingInterval
    }

    var canShowEmergency: Bool {
        order?.status.canBlindRunnerTriggerEmergency == true
    }

    var canShowCancel: Bool {
        order?.status.canBlindRunnerCancel == true
    }

    /// 上限到了就把按钮收起来，不留一个必定失败的控件 —— 对盲人来说
    /// 「按了、听到报错、再按、还是报错」比没有按钮更糟。
    var canShowKeepWaiting: Bool {
        order?.status.offersKeepWaiting == true && !keepWaitingLimitReached
    }

    var shouldPoll: Bool {
        order?.status.shouldPoll ?? true
    }

    /// - Parameter speechInputService: 「问一句」用。可选是为了让既有的一批单测不必凭空造一个
    ///   麦克风服务；传 nil 时按下按钮不会起听（`VoiceStatusQuerySession.ask` 自己 guard 掉）。
    func configure(
        appState: AppState,
        speechService: SpeechService,
        locationService: LocationService? = nil,
        speechInputService: SpeechInputService? = nil
    ) {
        self.appState = appState
        self.speechService = speechService
        self.locationService = locationService
        acceptsPeerLocations = true
        // 坐标取 `latestVolunteerCoordinate` 而不是重算一遍：它已经过了新鲜度闸
        // （WebSocket 那条判 `age <= peerFreshness`，过期由 `schedulePeerExpiry` 清空）。
        voiceQuerySession.configure(
            speechService: speechService,
            speechInputService: speechInputService,
            context: { [weak self] in (self?.order, self?.latestVolunteerCoordinate) }
        )
        subscribeToRealtimeCoordinator(appState: appState)
    }

    /// 按下「问一句」。判定与答句在 `VoiceStatusQuery`，录音与拨号在 `VoiceStatusQuerySession`。
    func askVoiceQuestion() {
        voiceQuerySession.ask()
    }

    func startPolling(orderId: Int64) {
        if currentOrderId != orderId {
            clearPeerLocation()
            // 上限是**这一单**的属性，不是这个 view model 的。换单不清会让新订单
            // 一进来就少一个本来该有的动作。
            keepWaitingLimitReached = false
            // 同理：评价与状态记录都是按单的，留着就会把上一单的内容展示在这一单下面。
            existingReview = nil
            statusLogs = []
            statusLogsErrorMessage = nil
        }
        currentOrderId = orderId
        acceptsPeerLocations = true
        appState?.realtimeCoordinator.registerActiveOrder(orderId)
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            await self?.loadOrder(orderId: orderId, speakChanges: true)

            while !Task.isCancelled {
                guard let self else { return }
                if !self.shouldContinuePolling {
                    return
                }
                try? await Task.sleep(nanoseconds: UInt64(self.effectivePollingInterval * 1_000_000_000))
                if Task.isCancelled { return }
                await self.loadOrder(orderId: orderId, speakChanges: true)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        acceptsPeerLocations = false
        clearPeerLocation()
    }

    func repeatStatus() {
        if let order {
            var announcement = order.blindRunnerAnnouncement(distanceText: volunteerDistanceToStartText)
            // 「继续等待」只有在这里被念到才会被发现：它是等待期唯一的主动作，
            // 而看不见屏幕的人不会知道页面上多了一个按钮。
            if canShowKeepWaiting {
                announcement += " " + KeepWaitingCopy.repeatStatusSuffix
            }
            // Canonical order status first, emergency state appended after it — never instead of it.
            if let sos = appState?.emergencyCoordinator.repeatStatusSuffix {
                announcement += " " + sos
            }
            speechService?.speak(announcement)
        } else {
            speechService?.speak("正在获取订单状态。")
        }
    }

    /// 刷新后端的等待超时窗口，让订单不被自动取消。
    ///
    /// **按状态分派，且只打这一个端点。** 两个端点的前置状态互斥，409
    /// `ORDER_STATUS_NOT_ALLOWED` 的含义是「你手上的状态已经过期了」——
    /// 此时正确的动作是刷新订单，不是换一个 URL 再打一次。盲人听不见网络请求，
    /// 连打两次的唯一可见结果是等待时间翻倍。
    ///
    /// 刻意**不做二次确认**：这个动作幂等、可重复，且方向是保住订单。误触的代价是多等一会儿，
    /// 而多一轮确认对读屏用户的代价是实打实的十几秒。（取消订单那条的二次确认不受影响。）
    func keepWaiting() async {
        guard let order, let appState else { return }
        guard let endpoint = order.status.keepWaitingEndpoint else {
            let message = "当前订单状态不能继续等待。"
            errorMessage = message
            speechService?.speakError(message)
            return
        }

        isPerformingAction = true
        errorMessage = nil
        do {
            let _: EmptyResponse = try await appState.apiClient.put(
                endpoint.path(orderId: order.orderId)
            )
            isPerformingAction = false
            // 成功不改状态（后端只回 `{"success": true}`），所以反馈只能由本地这句话给出。
            speechService?.speak(KeepWaitingCopy.success)
        } catch let error as APIError {
            isPerformingAction = false
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            switch error.errorCode {
            case .keepWaitingLimitReached:
                keepWaitingLimitReached = true
                errorMessage = KeepWaitingCopy.limitReached
                speechService?.speakError(KeepWaitingCopy.limitReached)
            case .invalidOrderStatus:
                // 本地状态过期。刷订单让页面回到真实状态，**不重试另一个端点**。
                errorMessage = error.localizedMessage
                speechService?.speakError(error.localizedMessage)
                await loadOrder(orderId: order.orderId, speakChanges: true)
            default:
                errorMessage = error.localizedMessage
                speechService?.speakError(error.localizedMessage)
            }
        } catch {
            isPerformingAction = false
            let message = "继续等待没有成功，请再试一次。"
            errorMessage = message
            speechService?.speakError(message)
        }
    }

    func cancelOrder() async {
        guard let order, let appState else { return }
        guard order.status.canBlindRunnerCancel else {
            let message = "当前订单状态不能由盲人取消。"
            errorMessage = message
            speechService?.speakError(message)
            return
        }
        isPerformingAction = true
        errorMessage = nil
        do {
            let _: EmptyResponse = try await appState.apiClient.post("/api/orders/\(order.orderId)/cancel")
            isPerformingAction = false
            await self.loadOrder(orderId: order.orderId, speakChanges: true)
        } catch let error as APIError {
            isPerformingAction = false
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            let message = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
            await self.loadOrder(orderId: order.orderId, speakChanges: true)
            errorMessage = message
        } catch {
            isPerformingAction = false
            let message = "取消失败。"
            speechService?.speakError(message)
            await self.loadOrder(orderId: order.orderId, speakChanges: true)
            errorMessage = message
        }
    }

    /// Sends one SOS for the current `IN_PROGRESS` order.
    ///
    /// Every outcome — including "not sent" — is both shown and spoken. A blind runner decides
    /// whether to look for help another way based on this announcement, so silence on failure
    /// would be the worst possible bug here.
    func enterEmergency() async {
        guard let order, let appState else { return }
        let coordinator = appState.emergencyCoordinator
        let outcome = await coordinator.trigger(
            order: order,
            role: appState.activeRole,
            userID: appState.userId,
            apiClient: appState.apiClient,
            locate: { await self.freshEmergencyCoordinate() }
        )
        // The visible surface is `EmergencyStatusNotice`, driven by the coordinator's state.
        // Deliberately not also setting `errorMessage`: that would render the same sentence twice
        // and make VoiceOver read the failure twice over.
        if outcome.isFailure {
            speechService?.speakError(outcome.message)
        } else {
            speechService?.speak(outcome.message)
        }
    }

    /// Withdraws one's own false alarm. The only user-side exit that exists: the escorting volunteer
    /// is refused this action server-side on purpose.
    func cancelEmergency() async {
        guard let appState else { return }
        let outcome = await appState.emergencyCoordinator.cancelByOwner(apiClient: appState.apiClient)
        if outcome.isFailure {
            speechService?.speakError(outcome.message)
        } else {
            speechService?.speak(outcome.message)
        }
    }

    /// 新鲜真实坐标，实现在 `EmergencyCoordinator.freshEmergencyCoordinate(using:)`。
    ///
    /// 2026-08-07 从这里提走：首页 SOS 条是第二个求助入口，而这段逻辑的每一条都是安全约束
    /// （只接受真实设备采样、演示坐标进不来、拿不到就返回 nil 让上层如实播报「未发出」）。
    /// 两份实现意味着这条保证要守两遍，迟早漂移。
    ///
    /// `IN_PROGRESS` 期间实时陪跑会话每 5 秒采样一次，所以那次有界重试只在刚起跑
    /// 或位置更新短暂暂停时才用得上。
    private func freshEmergencyCoordinate() async -> LocatedCoordinate? {
        await EmergencyCoordinator.freshEmergencyCoordinate(using: locationService)
    }

    func submitReview() async {
        guard let order, let appState, order.status == .completed else { return }
        guard (1...5).contains(reviewRating) else {
            errorMessage = "请选择 1 到 5 星评分。"
            speechService?.speakError("请选择 1 到 5 星评分。")
            return
        }

        isSubmittingReview = true
        errorMessage = nil
        do {
            let request = CreateReviewRequest(
                rating: reviewRating,
                comment: reviewComment.nilIfBlank
            )
            let _: EmptyResponse = try await appState.apiClient.post(
                "/api/orders/\(order.orderId)/review",
                body: request
            )
            isSubmittingReview = false
            didSubmitReview = true
            speechService?.speak("评价已提交，感谢反馈。")
        } catch let error as APIError {
            isSubmittingReview = false
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            // 已评价过不是失败：用户就站在这一单的评价页上，能做的正确动作只有把页面切到已评价态。
            // 后端 2026-07-31 起用专用码 REVIEW_ALREADY_SUBMITTED，不再与 DUPLICATE_ORDER 混用。
            if error.errorCode == .reviewAlreadySubmitted {
                didSubmitReview = true
                speechService?.speak(ErrorCode.reviewAlreadySubmitted.localizedMessage)
                // 把那条已存在的评价取回来念给用户听。否则「已评价过此订单」之后是一片空白，
                // 用户既不知道自己当初打了几分，也无从判断要不要联系客服。
                await loadExistingReview()
                return
            }
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isSubmittingReview = false
            errorMessage = "评价提交失败，请稍后重试。"
            speechService?.speakError("评价提交失败，请稍后重试。")
        }
    }

    func skipReview() {
        didSubmitReview = true
        speechService?.speak("已跳过评价，返回首页。")
    }

    /// 取回本单已有的评价（`GET /api/orders/{id}/reviews`，订单双方均可查）。
    ///
    /// 尚未评价时后端回 200 + `data: null`，那是正常业务状态：`existingReview` 保持 nil，
    /// 评价表单照常展示。**只在 `COMPLETED` 调** —— 其余状态下这一单不可能有评价。
    func loadExistingReview() async {
        guard let order, let appState, order.status == .completed else { return }
        do {
            let envelope: OrderReviewEnvelope = try await appState.apiClient.get(
                "/api/orders/\(order.orderId)/reviews"
            )
            existingReview = envelope.data
            if envelope.data != nil {
                didSubmitReview = true
            }
        } catch {
            // 刻意不报错、不播报：拿不到已有评价的唯一后果是评价表单多摆一次，
            // 而重复提交那一路已经由 `REVIEW_ALREADY_SUBMITTED` 兜住（见 `submitReview`）。
            // 为一块只读的辅助信息打断服务播报，代价比它自己大。
        }
    }

    /// 取回本单的状态变更记录（`GET /api/orders/{id}/status-logs`，订单双方均可查）。
    ///
    /// 响应是裸数组，后端已按时间**倒序**返回（`OrderStatusLogRepository:16`），这里不重排。
    func loadStatusLogs() async {
        guard let order, let appState else { return }
        isLoadingStatusLogs = true
        statusLogsErrorMessage = nil
        do {
            let logs: [OrderStatusLog] = try await appState.apiClient.get(
                "/api/orders/\(order.orderId)/status-logs"
            )
            isLoadingStatusLogs = false
            statusLogs = logs
        } catch let error as APIError {
            isLoadingStatusLogs = false
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            statusLogsErrorMessage = error.localizedMessage
        } catch {
            isLoadingStatusLogs = false
            statusLogsErrorMessage = "获取状态变更记录失败。"
        }
    }

    private var shouldContinuePolling: Bool {
        guard let order else { return true }
        return order.status.shouldPoll
    }

    private func loadOrder(orderId: Int64, speakChanges: Bool) async {
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
            let apiClient = appState.apiClient
            let candidate: OrderDetailResponse = try await HomeLoadCoordinator.run(
                timeout: HomeLoadPolicy.defaultTimeout,
                operationName: "blind-order-poll"
            ) {
                try await apiClient.get("/api/orders/\(orderId)")
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
            apply(updated, speakChanges: speakChanges)
            await refreshVolunteerLocationFallbackIfNeeded(for: updated, appState: appState)
        } catch let error as APIError {
            isLoading = false
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isLoading = false
            errorMessage = "获取订单状态失败。"
            speechService?.speakError("获取订单状态失败。")
        }
    }

    private func performAction(
        failureMessage: String,
        operation: () async throws -> Void
    ) async {
        isPerformingAction = true
        errorMessage = nil

        do {
            try await operation()
            isPerformingAction = false
        } catch let error as APIError {
            isPerformingAction = false
            if appState?.handleAuthenticatedAPIError(error) == true {
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

    private func apply(_ updated: OrderDetailResponse, speakChanges: Bool) {
        let previousStatus = order?.status
        order = updated
        appState?.liveEscortCoordinator.updateOwnedOrder(orderID: updated.orderId, status: updated.status)
        refreshVolunteerDistance()
        if speakChanges, previousStatus != updated.status {
            speechService?.speakStatusChange(
                updated.status,
                text: updated.blindRunnerAnnouncement(distanceText: volunteerDistanceToStartText)
            )
        }
        if !updated.status.shouldPoll {
            appState?.realtimeCoordinator.unregisterActiveOrder(updated.orderId)
            if updated.status != .completed {
                appState?.liveEscortCoordinator.clearOwnedOrder()
            }
            stopPolling()
        }
    }

    func handleVolunteerLocationUpdate(_ sample: RealtimePeerLocationSample) {
        guard acceptsPeerLocations,
              sample.ownerRole == .volunteer,
              sample.orderId == activeOrderId else { return }
        let capturedAt = Date(timeIntervalSince1970: TimeInterval(sample.timestampMilliseconds) / 1_000)
        let age = max(0, Date().timeIntervalSince(capturedAt))
        guard age <= peerFreshness,
              let located = BackendCoordinateNormalizer.backend(
            latitude: sample.latitude,
            longitude: sample.longitude,
            capturedAt: capturedAt
        ) else { return }

        latestVolunteerWebSocketDate = capturedAt
        latestVolunteerSample = located
        latestVolunteerCoordinate = located.coordinate
        refreshVolunteerDistance()
        schedulePeerExpiry(for: located, orderID: sample.orderId, remaining: peerFreshness - age)
    }

    func handleVolunteerLocationUpdate(_ message: WSVolunteerLocationUpdate) {
        handleVolunteerLocationUpdate(
            RealtimePeerLocationSample(
                orderId: message.orderId,
                ownerRole: .volunteer,
                latitude: message.lat,
                longitude: message.lng,
                timestampMilliseconds: message.timestamp
            )
        )
    }

    // `shouldSuppressDirectNotificationSpeech(_:)` 已于 2026-08-09 删除（连同 31 条中文片段表）。
    //
    // 它按通知正文的中文片段决定要不要抑制播报，而**生产代码里一个调用点都没有** ——
    // 唯一的调用者是它自己的那条测试。抑制实际发生在 `AppRealtimeCoordinator`，
    // 那边已经改成按 `eventType` 判定（`lifecycleStatus(forEventType:)`）。
    //
    // 删掉而不是留着的理由不是「没人用」，是**它会被照抄**：按正文匹配意味着后端改任何一条
    // 通知模板的正文都会静默改变 iOS 的播报行为，后端新增的 `REMATCH_ACCEPTED` 就是这么被吞掉的。
    // 片段表里还混着 `"测试志愿者"` / `"志愿者测试"` 两条——测试数据渗进产品代码，
    // 本身就是这段代码只为测试而活的证据。

    private var activeOrderId: Int64? {
        order?.orderId ?? currentOrderId
    }

    private func schedulePeerExpiry(
        for sample: LocatedCoordinate,
        orderID: Int64,
        remaining: TimeInterval
    ) {
        peerExpiryTask?.cancel()
        peerExpiryTask = Task { [weak self] in
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(max(0.01, remaining) * 1_000_000_000)
                )
            } catch {
                return
            }
            guard !Task.isCancelled,
                  let self,
                  self.activeOrderId == orderID,
                  self.latestVolunteerSample == sample else { return }
            self.clearPeerLocation()
        }
    }

    private func clearPeerLocation() {
        peerExpiryTask?.cancel()
        peerExpiryTask = nil
        latestVolunteerSample = nil
        latestVolunteerCoordinate = nil
        latestVolunteerWebSocketDate = nil
        refreshVolunteerDistance()
    }

    private func refreshVolunteerDistance() {
        guard let order, order.status.offersVolunteerDistanceToStart else {
            volunteerDistanceToStartText = nil
            return
        }
        volunteerDistanceToStartText = order.volunteerDistanceToStartText(from: latestVolunteerCoordinate)
    }

    private func refreshVolunteerLocationFallbackIfNeeded(for order: OrderDetailResponse, appState: AppState) async {
        guard order.status.offersVolunteerDistanceToStart else { return }
        let websocketSampleIsFresh = latestVolunteerWebSocketDate.map { Date().timeIntervalSince($0) <= 15 } ?? false
        guard !appState.isWebSocketConnected || !websocketSampleIsFresh else { return }

        do {
            let response: VolunteerLocationResponse = try await appState.apiClient.get("/api/blind/volunteer-location")
            guard let data = response.data,
                  data.coordinateIsValid,
                  data.orderId == nil || data.orderId == order.orderId,
                  data.status == nil || data.status == order.status,
                  let updatedAt = data.updatedAt.flatMap(Self.parseISO8601),
                  abs(Date().timeIntervalSince(updatedAt)) <= 30,
                  let lat = data.lat,
                  let lng = data.lng else { return }
            latestVolunteerCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            refreshVolunteerDistance()
        } catch {
            // Order polling remains authoritative; an unavailable location fallback is non-fatal.
        }
    }

    private static func parseISO8601(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }

    // MARK: - App-lifetime realtime routing

    private func subscribeToRealtimeCoordinator(appState: AppState) {
        cancellables.removeAll()
        let coordinator = appState.realtimeCoordinator
        coordinator.$pendingOrderRefreshIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] orderIDs in
                guard let self, let orderID = self.activeOrderId, orderIDs.contains(orderID) else { return }
                Task { await self.loadOrder(orderId: orderID, speakChanges: true) }
            }
            .store(in: &cancellables)

        coordinator.statusUpdatePublisher
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
            .store(in: &cancellables)

        coordinator.peerLocationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sample in self?.handleVolunteerLocationUpdate(sample) }
            .store(in: &cancellables)

        if let orderID = activeOrderId,
           let sample = coordinator.latestPeerLocation(orderID: orderID, ownerRole: .volunteer) {
            handleVolunteerLocationUpdate(sample)
        }
    }
}

// MARK: - Blind Order Status View

struct BlindOrderStatusView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var speechInputService: SpeechInputService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @StateObject private var viewModel = BlindOrderStatusViewModel()
    @StateObject private var trackViewModel = CompletedTrackSummaryViewModel()
    @State private var showEmergencyConfirmation = false
    @State private var showEmergencyCancelConfirmation = false
    @State private var showCancelConfirmation = false
    @State private var showStatusLogs = false
    @State private var showRunPlanShare = false
    @State private var runPlanShareNotice: RunPlanShareNotice?
    @State private var showLiveShareConsent = false
    @State private var showLiveShareConfirmation = false
    @State private var liveSharePayload: ShareLinkPayload?
    @State private var isLiveSharing = false
    @State private var isWorkingOnLiveShare = false
    /// 短信入口是**降级路径**，不是常驻功能：实时分享失败（断网 / 权限 / 终态 409）时才露出来。
    /// 常驻会让读屏用户每次都多滑一个按钮，而它在实时分享可用时并不是用户想要的那条路。
    @State private var showSMSFallback = false
    let orderId: Int64

    /// 行程告知的结果提示。盲人靠 `speak` 听到，低视力用户靠这行字看到 ——
    /// 两条通道都要有，`isProblem` 只决定颜色，不决定有没有。
    private struct RunPlanShareNotice: Equatable {
        let text: String
        let isProblem: Bool
    }
    let onOrderUpdated: (OrderDetailResponse) -> Void

    /// 主按钮高度。比首页的 280 小：这一页顶上还有状态卡要占位置，
    /// 而状态本身也是盲人此刻需要的信息，不能被按钮挤出首屏。
    ///
    /// 「打电话给志愿者」与「继续等待」共用它：两者的状态集互斥
    /// （`offersVolunteerCall` 是汇合中的四态，`offersKeepWaiting` 是等待中的两态），
    /// 同一个版位在任一时刻只会有其中一个，高度不该因为是哪一个而变。
    @ScaledMetric(relativeTo: .largeTitle) private var primaryActionButtonHeight: CGFloat = 140

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if viewModel.isLoading && viewModel.order == nil {
                    ProgressView("正在获取订单状态...")
                        .tint(AppColors.primary)
                        .accessibilityLabel("正在获取订单状态")
                }

                if let order = viewModel.order {
                    // 顺序即优先级：状态（一句话 + 一个数字）→ 唯一主动作（打电话）→
                    // 其余全部下沉。此前主动作排在第 4 位，读屏要滑过状态卡、地图、
                    // 生命周期卡才够得着。
                    statusHeader(order)
                    volunteerCallSection(order)
                    keepWaitingSection(order)
                    runPlanShareSection(order)
                    peerMapSection(order)
                    lifecycleSection(order)
                    actionSection(order)
                    orderInfoSection(order)
                    statusLogSection
                    debugMockControls(order)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.destructive)
                        .accessibilityLabel(errorMessage)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        }
        .background(AppColors.background)
        .navigationTitle("订单状态")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            repeatStatusArea
        }
        .confirmationDialog("取消订单", isPresented: $showCancelConfirmation) {
            Button("确认取消", role: .destructive) {
                Task {
                    await viewModel.cancelOrder()
                    if let order = viewModel.order {
                        onOrderUpdated(order)
                    }
                }
            }
            Button("不取消", role: .cancel) {}
        } message: {
            Text("确认取消本次预约？取消后将结束本次服务。")
        }
        .confirmationDialog(
            EmergencySafetyCopy.cancelButtonTitleForOwner,
            isPresented: $showEmergencyCancelConfirmation
        ) {
            Button(EmergencySafetyCopy.cancelButtonTitleForOwner, role: .destructive) {
                Task { await viewModel.cancelEmergency() }
            }
            Button("保持求助", role: .cancel) {}
        } message: {
            Text(EmergencySafetyCopy.cancelOwnerConfirmation)
        }
        .sheet(isPresented: $showRunPlanShare) {
            // 正文在呈现时重算而不是提前存进 @State：这一页每 5 秒轮询一次订单，
            // 打开 sheet 那一刻的行程要素才是要发出去的那份。
            MessageComposeSheet(
                recipients: [appState.primaryEmergencyContact?.phone?.nilIfBlank].compactMap { $0 },
                body: viewModel.order.flatMap(RunPlanShareMessage.compose(order:)) ?? ""
            ) { outcome in
                showRunPlanShare = false
                switch outcome {
                case .sent:
                    // 进行时。`.sent` 只代表用户点了发送，不代表送达 —— 见 `RunPlanShareCopy`。
                    setRunPlanShareNotice(RunPlanShareCopy.sent, isProblem: false)
                    speechService.speak(RunPlanShareCopy.sent)
                case .cancelled:
                    setRunPlanShareNotice(RunPlanShareCopy.cancelled, isProblem: false)
                    speechService.speak(RunPlanShareCopy.cancelled)
                case .failed:
                    setRunPlanShareNotice(RunPlanShareCopy.failed, isProblem: true)
                    speechService.speakError(RunPlanShareCopy.failed)
                }
            }
        }
        // 全屏，不是对话框：三条告知要各自可听、可停、可回头再听，理由见 `RunPlanShareConsentView`。
        .fullScreenCover(isPresented: $showLiveShareConsent) {
            RunPlanShareConsentView(
                onAgree: {
                    showLiveShareConsent = false
                    // 同意在**发请求之前**落盘。反过来的话，一次网络失败会让用户下次再看一遍
                    // 全文告知 —— 而他已经同意过了，重复告知是在消耗告知本身的效力。
                    consentStore.recordConsent(userKey: consentUserKey)
                    Task { await startLiveShare() }
                },
                onDecline: {
                    showLiveShareConsent = false
                    setRunPlanShareNotice(RunPlanShareConsentCopy.declined, isProblem: false)
                    speechService.speak(RunPlanShareConsentCopy.declined)
                }
            )
        }
        .alert(RunPlanShareConsentCopy.repeatConfirmationTitle, isPresented: $showLiveShareConfirmation) {
            Button(RunPlanShareConsentCopy.agreeButtonTitle) {
                Task { await startLiveShare() }
            }
            Button(RunPlanShareConsentCopy.declineButtonTitle, role: .cancel) {
                setRunPlanShareNotice(RunPlanShareConsentCopy.declined, isProblem: false)
                speechService.speak(RunPlanShareConsentCopy.declined)
            }
        } message: {
            Text(RunPlanShareConsentCopy.repeatConfirmationMessage)
        }
        .sheet(item: $liveSharePayload) { payload in
            ShareLinkSheet(text: payload.text) {
                liveSharePayload = nil
                // 面板关掉不改变任何事实：链接在服务端已经生效，选没选目标应用都一样在分享中。
                setRunPlanShareNotice(RunPlanLiveShareCopy.panelDismissed, isProblem: false)
                speechService.speak(RunPlanLiveShareCopy.panelDismissed)
            }
        }
        .emergencyConfirmationAlert(isPresented: $showEmergencyConfirmation) {
            Task {
                await viewModel.enterEmergency()
                if let order = viewModel.order {
                    onOrderUpdated(order)
                }
            }
        }
        .onAppear {
            // 分享状态来自本地记录而不是订单详情：后端没有查询分享状态的端点，
            // 理由与代价写在 `RunPlanLiveShareStore` 的注释里。
            isLiveSharing = liveShareStore.isSharing(orderID: orderId)
            viewModel.configure(
                appState: appState,
                speechService: speechService,
                locationService: locationService,
                speechInputService: speechInputService
            )
            viewModel.startPolling(orderId: orderId)
        }
        .onDisappear {
            viewModel.stopPolling()
            if let order = viewModel.order {
                onOrderUpdated(order)
            }
        }
        .task(id: viewModel.order?.status) {
            guard viewModel.order?.status == .completed else { return }
            await viewModel.loadExistingReview()
            await trackViewModel.load(orderID: orderId, appState: appState)
            if let summary = trackViewModel.track?.spokenSummary { speechService.speak(summary) }
        }
        // 展开时拉一次，之后每次状态推进再拉一次 —— 服务进行中新增的那条转移会自己出现。
        // 折叠状态下不请求：这是一块用户主动来找的辅助信息，不该给主路径加一次 5 秒一轮的开销。
        .task(id: statusLogReloadKey) {
            guard showStatusLogs else { return }
            await viewModel.loadStatusLogs()
        }
    }

    private var statusLogReloadKey: String {
        "\(showStatusLogs)-\(viewModel.order?.status.rawValue ?? "")"
    }

    /// 一句话 + 一个数字，合成**一个** VoiceOver 焦点。
    ///
    /// 距离此前埋在下面的「志愿者信息」卡片里当正文读，而它恰恰是这一页唯一会变的数字 ——
    /// 对标 GoodMaps 的 `Start Walking … 96 ft`、WeWALK 的 `116 meters`：状态旁边就该是那个数
    /// （`docs/research/blind-ui-visual-benchmark-20260808.md` §1 规则 4）。
    private func statusHeader(_ order: OrderDetailResponse) -> some View {
        VStack(spacing: 12) {
            Image(systemName: order.status.statusSymbolName)
                .font(.system(size: 56))
                .foregroundColor(order.status.statusColor)
                .accessibilityHidden(true)

            Text(order.status.displayName)
                .font(.largeTitle.bold())
                .foregroundColor(AppColors.textPrimary)

            Text(order.status.blindRunnerDescription)
                .font(.title3)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)

            if let distanceText = viewModel.volunteerDistanceToStartText {
                Text("志愿者\(distanceText)")
                    .font(.title.bold())
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
            }

            // 服务进行中，把约定的结束时间摆在首屏。低视力用户靠这行字看到，
            // 读屏用户靠 `statusHeaderAnnouncement` 听到 —— 两条通道都要有。
            if let plannedEndText = plannedEndHeaderText(order) {
                Text(plannedEndText)
                    .font(.title2.bold())
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(statusHeaderAnnouncement(order))
    }

    /// 结束时间只在服务进行中出现在首屏。派单期、汇合期摆它没有用（还没开始跑），
    /// 终态更不该摆（已经结束了，一个「预计」是噪音）。
    ///
    /// 拼接抽成独立函数而不是塞进 `Text(...)`：带可选拆包的字符串插值放在 view builder 里
    /// 会把类型检查器拖到超时（`unable to type-check this expression in reasonable time`）。
    private func plannedEndHeaderText(_ order: OrderDetailResponse) -> String? {
        guard order.status == .inProgress, let end = order.plannedEndForAnnouncement else { return nil }
        return "预计 \(end) 结束"
    }

    /// 合并后的朗读文本写死，不交给 `.combine` 自己拼 —— 自动拼接会把状态名、说明和距离
    /// 糊成一长串没有停顿的音。
    private func statusHeaderAnnouncement(_ order: OrderDetailResponse) -> String {
        var parts = [order.status.displayName, order.status.blindRunnerDescription]
        if let distanceText = viewModel.volunteerDistanceToStartText {
            parts.append("志愿者\(distanceText)")
        }
        if let plannedEndText = plannedEndHeaderText(order) {
            parts.append(plannedEndText)
        }
        return parts.joined(separator: "。")
    }

    @ViewBuilder
    private func lifecycleSection(_ order: OrderDetailResponse) -> some View {
        switch order.status.blindRunnerRoute {
        case .tracking, .inService:
            // 这两条分支此前各渲染一张「标题 + 正文」卡片，两处正文都与 `statusHeader` 重复：
            //   · `DRIVER_ARRIVED` 的 `arrivedWaitingCopy` **就是**它的 `blindRunnerDescription`
            //     （`OrderDisplayHelpers.swift:77` 直接 return 了它）—— 逐字重复
            //   · `IN_PROGRESS` 那句「请与志愿者保持沟通，注意安全。系统会持续同步订单状态，
            //     服务完成后进入评价页面。」33 个字里没有一个能让盲人做出动作：
            //     「持续同步订单状态」是实现细节，「完成后进入评价页面」是还没发生的事
            // 读屏用户为此要多滑两次、把同一件事听两遍。状态语义由 `statusHeader` 一处承担。
            EmptyView()
        case .completion:
            completionRatingSection(order)
        case .terminal:
            terminalSection(order)
        }
    }

    private func completionRatingSection(_ order: OrderDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("服务已完成")
                .font(.title3.bold())
                .foregroundColor(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            if let track = trackViewModel.track {
                CompletedTrackSummaryView(track: track) {
                    speechService.speak(track.spokenSummary)
                }
            } else if trackViewModel.isLoading {
                ProgressView("正在加载本次路线")
            } else if let error = trackViewModel.errorMessage {
                Text(error).foregroundColor(AppColors.textSecondary)
            }

            if viewModel.didSubmitReview {
                if let review = viewModel.existingReview {
                    submittedReviewSummary(review)
                }
                Text("感谢反馈，可以返回首页。")
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityLabel("感谢反馈，可以返回首页")
            } else {
                Picker("评分", selection: $viewModel.reviewRating) {
                    ForEach(1...5, id: \.self) { value in
                        Text("\(value) 星").tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("服务评分")
                .accessibilityHint("选择一到五星评分")

                TextEditor(text: $viewModel.reviewComment)
                    .frame(minHeight: 96)
                    .padding(8)
                    .background(AppColors.background)
                    .cornerRadius(8)
                    .accessibilityLabel("评价内容，选填")

                PrimaryButton("提交评价", isLoading: viewModel.isSubmittingReview) {
                    Task { await viewModel.submitReview() }
                }
                .accessibilityLabel("提交评价")
                .accessibilityHint("提交本次服务评分和评价")

                Button("跳过评价并返回首页") {
                    viewModel.skipReview()
                    dismiss()
                }
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .buttonShapeOutlineIfNeeded(color: AppColors.textSecondary)
                .accessibilityLabel("跳过评价并返回首页")
            }

            if viewModel.didSubmitReview {
                PrimaryButton("返回首页") {
                    dismiss()
                }
                .accessibilityLabel("返回首页")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
    }

    /// 已提交过的评价读回来。
    ///
    /// 这一块的存在理由是**重进这一单**：`didSubmitReview` 只活在这个进程里，
    /// 重开 App 再进已完成的订单，用户看到的是一张空白评价表 —— 填完提交只会撞上
    /// 409「已评价过此订单」。把真实评价念出来，用户才知道这一单已经评过、评的是什么。
    /// 合成一个焦点：星数和评语分两次读会让读屏用户以为是两条不同的记录。
    private func submittedReviewSummary(_ review: OrderReview) -> some View {
        let comment = review.comment?.nilIfBlank
        let reviewedAt = review.createdAt?.nilIfBlank?.displayDateTime
        // 视觉与读屏两条通道给同一份内容，不给读屏偷偷多塞一句 —— 低视力用户走的是视觉那条
        // （AGENTS.md §1.4）。
        return VStack(alignment: .leading, spacing: 4) {
            Text("你给本次服务打了 \(review.rating) 星")
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.textPrimary)
            if let comment {
                Text(comment)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
            }
            if let reviewedAt {
                Text("评价于\(reviewedAt)")
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "你给本次服务打了 \(review.rating) 星"
                + (comment.map { "，评语：\($0)" } ?? "")
                + (reviewedAt.map { "，评价于\($0)" } ?? "")
        )
    }

    /// 「刚才到底发生了什么」。
    ///
    /// 折叠，理由与「预约信息」同一条：这是用户想回溯时才来找的信息，不是主路径上的动作。
    /// 摊开会让读屏用户在到达「重复当前状态」之前多滑十几次。
    private var statusLogSection: some View {
        DisclosureGroup("状态变更记录", isExpanded: $showStatusLogs) {
            statusLogContent
                .padding(.top, 12)
        }
        .font(.title3.bold())
        .tint(AppColors.textPrimary)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
        .accessibilityHint("展开后可以听到这一单每一次状态变化和发生时间")
        .accessibilityIdentifier("blindOrderStatusLogsDisclosure")
    }

    @ViewBuilder
    private var statusLogContent: some View {
        if viewModel.isLoadingStatusLogs && viewModel.statusLogs.isEmpty {
            ProgressView("正在获取状态变更记录")
                .tint(AppColors.primary)
                .accessibilityLabel("正在获取状态变更记录")
        } else if let errorMessage = viewModel.statusLogsErrorMessage {
            // 「拿不到」和「没有记录」必须分得开：前者可以重试，后者重试也没用。
            Text(errorMessage)
                .font(AppFonts.body())
                .foregroundColor(AppColors.destructive)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(errorMessage)
        } else if viewModel.statusLogs.isEmpty {
            Text("暂无状态变更记录")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("暂无状态变更记录")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                // 后端已按时间倒序给，最新的一条在最上面 —— 读屏第一个听到的就是刚发生的事。
                ForEach(viewModel.statusLogs) { log in
                    infoRow(log.changedAt.displayDateTime, log.displayText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func peerMapSection(_ order: OrderDetailResponse) -> some View {
        if [.driverEnRoute, .driverArrived, .inProgress].contains(order.status) {
            let peer = viewModel.latestVolunteerSample?.coordinate
            if let peer {
                // 与首页同一条规则：地图是装饰，列表才是界面。它不可交互、不承载任何必要信息
                // ——「志愿者距你多远」的文字版在 `statusHeader` 里，是那一页最大的那个数字。
                // 「同行位置」这个标题一并去掉：视觉扫读才需要标题，这一页没有扫读。
                MapViewWrapper(
                    centerCoordinate: peer,
                    showsUserLocation: false,
                    annotations: [MapAnnotationItem(
                        id: "associated-volunteer",
                        coordinate: peer,
                        title: "同行志愿者",
                        subtitle: "位置刚刚更新",
                        kind: .peer
                    )],
                    tracksUserLocation: false
                )
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            } else {
                // 但「拿不到位置」必须留在读屏里：盲人据此决定要不要打电话，
                // 这是状态信息不是装饰。
                Text("同行位置暂时不可用")
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("同行位置暂时不可用")
            }
        }
    }

    private func terminalSection(_ order: OrderDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(order.status.displayName)
                .font(.title3.bold())
                .foregroundColor(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(order.status.blindRunnerDescription)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(order.status.displayName)，\(order.status.blindRunnerDescription)")
    }

    /// 接单后这一页唯一的主动作：打电话给志愿者。
    ///
    /// 此前它是「志愿者信息」卡片里的一行只读文字（`Text("志愿者电话：…")`）。
    /// 打车 App 里视障乘客靠车型 / 车牌 / 颜色确认对方，**陪跑场景这三样都没有** ——
    /// 志愿者是个人，视障者手里唯一的汇合手段就是这通电话。把它做成一行文字，
    /// 等于把唯一的出路藏在第四张卡片里。
    ///
    /// 依据：202 名视障者问卷 + 12 人访谈的结论是导航阶段最优先的信息为「怎么找到正确的那一个」；
    /// Guide Dogs for the Blind 给视障乘客的操作建议直接就是「接驾前几分钟主动打电话说明自己在哪」。
    /// 见 `docs/research/blind-ui-visual-benchmark-20260808.md` §3.2。
    ///
    /// 只在需要汇合的状态出现：终态（已完成 / 已取消 / 暂无志愿者）下电话可能还在，
    /// 但那时候摆一个占半屏的拨号按钮是错的。
    /// ponytail: 复用 `EmergencyDialer.telURL` —— 它只是在拼 `tel://`，与求助语义无关，
    /// 不值得为「非紧急拨号」再造一个同样的三行函数。
    @ViewBuilder
    private func volunteerCallSection(_ order: OrderDetailResponse) -> some View {
        if order.status.offersVolunteerCall,
           let volunteerPhone = order.volunteerPhone?.nilIfBlank,
           let telURL = EmergencyDialer.telURL(for: volunteerPhone) {
            Button {
                UIApplication.shared.open(telURL)
            } label: {
                Text("打电话给志愿者")
                    .font(AppFonts.largeTitle())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: primaryActionButtonHeight)
                    .background(AppColors.primary)
                    .cornerRadius(16)
            }
            .accessibilityLabel("打电话给志愿者")
            // 这里此前是「拨打 \(volunteerPhone)，系统会先弹出拨号确认」——
            // VoiceOver 每次焦点落到按钮上就把 11 位号码整个念出来，用户还没决定要不要打。
            // 视障跑者在户外常常**不戴耳机**（要听车流），外放等于把志愿者的手机号广播给周围的人。
            // 号码对「要不要打这通电话」这个决策没有任何帮助，唯一有用的信息是「会先弹确认」。
            //
            // 语音拨号那条路**照旧逐位复述号码**（`VoiceStatusQuery.swift:212`），
            // 那不是冗余暴露：用户已经明确说了要打，复述是拨号前确认拨给谁，删掉会变成盲拨。
            .accessibilityHint("系统会先弹出拨号确认，确认后才会拨出")
            .accessibilityIdentifier("blindOrderStatusCallVolunteerButton")
        }
    }

    /// 等待期这一页唯一的主动作。
    ///
    /// 后端的 `ORDER_CANCELLATION_WARNING` 正文逐字写着「点击继续等待可延长」，在这个按钮
    /// 存在之前，盲人听到那句话之后**在屏幕上找不到它**，能做的只有等订单被自动取消再重下一单。
    ///
    /// 排在 `volunteerCallSection` 后面同一个版位：两者状态集互斥，等待中给这个、汇合中给电话，
    /// 读屏遍历时状态卡之后紧跟的永远是此刻唯一该做的那件事。
    ///
    /// 没有二次确认（幂等 + 方向是保住订单）。取消订单那条的确认对话框不受影响。
    @ViewBuilder
    private func keepWaitingSection(_ order: OrderDetailResponse) -> some View {
        if viewModel.canShowKeepWaiting {
            Button {
                Task { await viewModel.keepWaiting() }
            } label: {
                Text(KeepWaitingCopy.buttonTitle)
                    .font(AppFonts.largeTitle())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: primaryActionButtonHeight)
                    .background(AppColors.primary)
                    .cornerRadius(16)
            }
            .disabled(viewModel.isPerformingAction)
            .accessibilityLabel(KeepWaitingCopy.buttonTitle)
            .accessibilityHint(KeepWaitingCopy.accessibilityHint)
            .accessibilityIdentifier("blindOrderStatusKeepWaitingButton")
        }
    }

    /// 把这次行程告诉家人。主路径是**实时分享**（后端生成免登录链接，家属能看到位置与轨迹），
    /// 短信是它失败时的降级路径。
    ///
    /// 排在两个主动作之后、地图之前：它是次级动作（不该抢 140pt 的主按钮版位），
    /// 但也不能沉到订单信息下面 —— 看不见屏幕的人靠遍历顺序发现功能存在，
    /// 沉下去等于没做。样式用整行铺满的次级按钮，与
    /// `docs/research/blind-ui-visual-benchmark-20260808.md` 那条「次级操作一律整行铺满
    /// 竖直堆叠」一致。
    ///
    /// 终态整段消失（`offersRunPlanShare`），不是禁用：后端对终态返 409，
    /// 摆一个按下去必然报错的按钮，对读屏用户是纯噪音。
    @ViewBuilder
    private func runPlanShareSection(_ order: OrderDetailResponse) -> some View {
        if order.status.offersRunPlanShare {
            VStack(spacing: 10) {
                if isLiveSharing {
                    runPlanShareButton(
                        title: RunPlanLiveShareCopy.stopButtonTitle,
                        hint: RunPlanLiveShareCopy.stopAccessibilityHint,
                        identifier: "blindOrderStatusStopLiveShareButton",
                        tint: AppColors.destructive,
                        action: { Task { await stopLiveShare() } }
                    )
                } else {
                    runPlanShareButton(
                        title: RunPlanLiveShareCopy.buttonTitle,
                        hint: RunPlanLiveShareCopy.accessibilityHint,
                        identifier: "blindOrderStatusLiveShareButton",
                        tint: AppColors.primary,
                        action: { requestLiveShare() }
                    )
                }

                // 只在实时分享走不通时露出来。`canSendText` 一并判掉：这台设备本来就发不了短信时
                // 摆出降级入口，等于把用户支上一条同样走不通的路。
                if showSMSFallback, MessageComposeSheet.canSendText {
                    runPlanShareButton(
                        title: RunPlanLiveShareCopy.smsFallbackButtonTitle,
                        hint: RunPlanLiveShareCopy.smsFallbackHint,
                        identifier: "blindOrderStatusShareRunPlanButton",
                        tint: AppColors.primary,
                        action: { shareRunPlanBySMS(order) }
                    )
                }

                if let notice = runPlanShareNotice {
                    Text(notice.text)
                        .font(AppFonts.body())
                        .foregroundColor(notice.isProblem ? AppColors.destructive : AppColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(notice.text)
                        .accessibilityIdentifier("blindOrderStatusShareRunPlanNotice")
                }
            }
        }
    }

    private func runPlanShareButton(
        title: String,
        hint: String,
        identifier: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppFonts.title())
                .foregroundColor(tint)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 64)
                .background(AppColors.secondaryBackground)
                .cornerRadius(16)
        }
        .disabled(isWorkingOnLiveShare)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Live share

    private var consentStore: RunPlanShareConsentStore {
        RunPlanShareConsentStore(persistence: appState.persistence)
    }

    private var liveShareStore: RunPlanLiveShareStore {
        RunPlanLiveShareStore(persistence: appState.persistence)
    }

    /// 同意按**用户**存。未登录拿不到 userId 时用一个恒不命中的 key，效果是每次都走全屏告知 ——
    /// 这条路正常走不到（这一页在登录后才可达），宁可多告知一次也不要让一个空 key
    /// 被所有账号共用。
    private var consentUserKey: String {
        appState.currentUser.map { String($0.userId) } ?? "anonymous"
    }

    /// 按下分享：先过明示同意这道门。**不许直接发请求** ——
    /// 调 `POST /api/orders/{id}/share` 本身就等同于盲人对「向持链接者提供实时位置与轨迹」
    /// 作出单独同意（PIPL 第 23/29 条，轨迹属第 28 条敏感个人信息）。后端挡不住这一层，
    /// 只有客户端能，判定在 `RunPlanShareConsentStep.next`。
    private func requestLiveShare() {
        runPlanShareNotice = nil
        showSMSFallback = false
        switch RunPlanShareConsentStep.next(hasGivenConsent: consentStore.hasGivenConsent(userKey: consentUserKey)) {
        case .fullDisclosure:
            showLiveShareConsent = true
        case .shortConfirmation:
            showLiveShareConfirmation = true
        }
    }

    private func startLiveShare() async {
        guard !isWorkingOnLiveShare else { return }
        isWorkingOnLiveShare = true
        defer { isWorkingOnLiveShare = false }

        setRunPlanShareNotice(RunPlanLiveShareCopy.preparing, isProblem: false)
        speechService.speak(RunPlanLiveShareCopy.preparing)
        do {
            let response: ShareLinkResponse = try await appState.apiClient.post("/api/orders/\(orderId)/share")
            liveShareStore.markSharing(orderID: orderId)
            isLiveSharing = true
            setRunPlanShareNotice(RunPlanLiveShareCopy.sharing, isProblem: false)
            speechService.speak(RunPlanLiveShareCopy.ready)
            liveSharePayload = ShareLinkPayload(
                text: RunPlanLiveShareMessage.compose(shareUrl: response.shareUrl)
            )
        } catch {
            // 失败一律露出短信降级入口，包括 409（终态竞态）—— 那种情况下实时分享已经不可能，
            // 而「把这次行程告诉家人」这件事仍然做得到。
            let reason = (error as? APIError)?.localizedMessage ?? APIError.networkError(error).localizedMessage
            showSMSFallback = true
            let text = RunPlanLiveShareCopy.failed(reason, offersSMSFallback: MessageComposeSheet.canSendText)
            setRunPlanShareNotice(text, isProblem: true)
            speechService.speakError(text)
        }
    }

    private func stopLiveShare() async {
        guard !isWorkingOnLiveShare else { return }
        isWorkingOnLiveShare = true
        defer { isWorkingOnLiveShare = false }

        setRunPlanShareNotice(RunPlanLiveShareCopy.stopping, isProblem: false)
        speechService.speak(RunPlanLiveShareCopy.stopping)
        do {
            let _: EmptyResponse = try await appState.apiClient.delete("/api/orders/\(orderId)/share")
            liveShareStore.clear()
            isLiveSharing = false
            setRunPlanShareNotice(RunPlanLiveShareCopy.stopped, isProblem: false)
            speechService.speak(RunPlanLiveShareCopy.stopped)
        } catch {
            // **失败时不清本地状态**：链接可能还有效，把「停止分享」入口一起收走，
            // 用户就再也停不掉了。宁可让他多按一次，也不要把入口弄丢。
            setRunPlanShareNotice(RunPlanLiveShareCopy.stopFailed, isProblem: true)
            speechService.speakError(RunPlanLiveShareCopy.stopFailed)
        }
    }

    // MARK: - SMS fallback

    /// 把行程要素交给系统短信，发给紧急联系人。**不发任何网络请求** ——
    /// 行程来自本页已持有的 `OrderDetailResponse`，收件人来自 `AppState.emergencyContacts`。
    ///
    /// 三道门，顺序不能换：**先问设备能不能发**，再问有没有收件人。
    /// 反过来的话，一台不能发短信的设备会先把用户支去添加紧急联系人，
    /// 加完回来发现还是发不出去 —— 那是一趟白跑的路，而这条路对盲人格外贵。
    private func shareRunPlanBySMS(_ order: OrderDetailResponse) {
        guard MessageComposeSheet.canSendText else {
            setRunPlanShareNotice(RunPlanShareCopy.unavailable, isProblem: true)
            speechService.speakError(RunPlanShareCopy.unavailable)
            return
        }
        guard appState.primaryEmergencyContact?.phone?.nilIfBlank != nil else {
            setRunPlanShareNotice(RunPlanShareCopy.noContact, isProblem: true)
            speechService.speakError(RunPlanShareCopy.noContact)
            return
        }
        guard RunPlanShareMessage.compose(order: order) != nil else { return }
        runPlanShareNotice = nil
        showRunPlanShare = true
    }

    private func setRunPlanShareNotice(_ text: String, isProblem: Bool) {
        runPlanShareNotice = RunPlanShareNotice(text: text, isProblem: isProblem)
    }

    /// 折叠。这 8 行在下单时已经被逐条读回确认过一遍，服务进行中它们既不可改也无需再听 ——
    /// 摊开就是读屏用户在主路径上多滑 8 次。`DisclosureGroup` 保留了「想听时能听」，
    /// 而不是把信息删掉。
    private func orderInfoSection(_ order: OrderDetailResponse) -> some View {
        DisclosureGroup("预约信息") {
            orderInfoRows(order)
                .padding(.top, 12)
        }
        .font(.title3.bold())
        .tint(AppColors.textPrimary)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
        .accessibilityHint("展开后可以听到预约时间、出发地点等已确认的信息")
    }

    private func orderInfoRows(_ order: OrderDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            infoRow("预约时间", (order.plannedStart ?? "").displayDateTime)
            // 约定的结束时间。取 `plannedEnd`，**不是** `预约时间 + 预计时长` 推的 ——
            // 理由见 `plannedEndForAnnouncement`。下面那行「预计时长」是用户下单时选的档位，
            // 两者放在一起时更要分清：时长是意愿，结束时间是后端算出来的约定。
            if let plannedEnd = order.plannedEndForAnnouncement {
                infoRow("预计结束时间", plannedEnd)
            }
            if let address = order.startAddress, !address.trimmed.isEmpty {
                infoRow("出发地点", address)
            }
            if let endAddress = order.endAddressForDisplay {
                infoRow("结束地点", endAddress)
            }
            if let routeNotes = order.routeNotes, !routeNotes.trimmed.isEmpty {
                infoRow("路线备注", routeNotes)
            }
            if let duration = order.expectedDurationMinutes {
                infoRow("预计时长", "\(duration) 分钟")
            }
            if let pace = order.pacePreference {
                infoRow("配速偏好", pace.displayName)
            }
            if let route = order.routePreference {
                infoRow("路线偏好", route.displayName)
            }
            if order.hasGuideDogThisRun == true {
                infoRow("导盲犬", "本次携带")
            }
            if let notes = order.specialNotes, !notes.trimmed.isEmpty {
                infoRow("特殊说明", notes)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
            Text(value)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)：\(value)")
    }

    private func actionSection(_ order: OrderDetailResponse) -> some View {
        VStack(spacing: 14) {
            if viewModel.canShowEmergency {
                // 求助区块整体交给 `EmergencyActionSection`：它自己订阅 coordinator。
                // 此前这里直接读 `appState.emergencyCoordinator.state`，值是对的但不保证跟着更新
                // —— 详见该类型的注释。
                EmergencyActionSection(
                    coordinator: appState.emergencyCoordinator,
                    onTrigger: { showEmergencyConfirmation = true },
                    onCancelOwnEmergency: { showEmergencyCancelConfirmation = true }
                )
            }

            if viewModel.canShowCancel {
                Button("取消订单") {
                    showCancelConfirmation = true
                }
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.destructive)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 64)
                // 这一页只有这一个按钮是**纯文字**（其余都是实心色块），开启「按钮形状」时
                // 它是唯一一个看不出可点的。而它是破坏性操作，认不出来的代价是两个方向的：
                // 想取消的人找不到，不想取消的人以为那只是一行说明。
                .buttonShapeOutlineIfNeeded(color: AppColors.destructive)
                .accessibilityLabel("取消订单")
                .accessibilityHint("需要确认后取消")
            }

            if order.status.isTerminal && order.status != .completed {
                PrimaryButton("返回首页") {
                    dismiss()
                }
                .accessibilityLabel("返回首页")
                .accessibilityHint("点击后返回盲人首页")
            }
        }
    }

    @ViewBuilder
    private func debugMockControls(_ order: OrderDetailResponse) -> some View {
        #if DEBUG
        if appState.currentEnvironment == .mock {
            VStack(alignment: .leading, spacing: 10) {
                Text("Mock 状态测试")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)

                if order.status == .pendingMatch {
                    Button("模拟志愿者接单") {
                        Task {
                            let request = OrderRespondRequest(action: .accept)
                            let _: EmptyResponse? = try? await appState.apiClient.post(
                                "/api/orders/\(order.orderId)/respond",
                                body: request
                            )
                            viewModel.startPolling(orderId: order.orderId)
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("模拟志愿者接单")
                }

                if order.status == .driverEnRoute || order.status == .pendingAccept {
                    Button("模拟志愿者到达") {
                        Task {
                            // 真实状态机是 PENDING_ACCEPT → DRIVER_EN_ROUTE → DRIVER_ARRIVED，不能跳级。
                            // 从 PENDING_ACCEPT 直接打 /arrived 会被拒（Mock 与后端同口径），
                            // 而下面的 try? 把拒绝静默吞掉，现象是「点了没反应」，
                            // 后续依赖 DRIVER_ARRIVED 的「模拟服务开始」永不出现。
                            if order.status == .pendingAccept {
                                let _: EmptyResponse? = try? await appState.apiClient.post("/api/orders/\(order.orderId)/en-route")
                            }
                            let _: EmptyResponse? = try? await appState.apiClient.post("/api/orders/\(order.orderId)/arrived")
                            viewModel.startPolling(orderId: order.orderId)
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("模拟志愿者到达")
                }

                if order.status == .driverArrived {
                    Button("模拟服务开始") {
                        Task {
                            let _: EmptyResponse? = try? await appState.apiClient.post("/api/orders/\(order.orderId)/start-service")
                            viewModel.startPolling(orderId: order.orderId)
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("模拟服务开始")
                }

                if order.status == .inProgress {
                    Button("模拟服务完成") {
                        Task {
                            let _: EmptyResponse? = try? await appState.apiClient.post("/api/orders/\(order.orderId)/finish")
                            viewModel.startPolling(orderId: order.orderId)
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("模拟服务完成")
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.secondaryBackground)
            .cornerRadius(8)
        }
        #endif
    }

    /// 「问一句」排在「重复当前状态」**之前**：它是这两者里更省时间的那个 ——
    /// 整段状态播报要 15~25 秒，而问一句只念被问的那一项。
    private var repeatStatusArea: some View {
        VStack(spacing: 12) {
            askQuestionButton
            PrimaryButton("重复当前状态") {
                viewModel.repeatStatus()
            }
            .accessibilityLabel("重复当前状态")
            .accessibilityHint("点击后重新播报当前订单状态")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        // 这条常驻底栏压在滚动内容之上，`.regularMaterial` 会把下面滑过去的文字透上来。
        // 「降低透明度」开启时换成实色 —— 那个开关的用户正是被这种叠影干扰的人，
        // 而底下这两个按钮（问一句 / 重复当前状态）是这一页任何时刻都要够得着的东西。
        .background(reduceTransparency ? AnyShapeStyle(AppColors.background) : AnyShapeStyle(.regularMaterial))
    }

    private var askQuestionButton: some View {
        Button("问一句") {
            viewModel.askVoiceQuestion()
        }
        .font(AppFonts.body().weight(.semibold))
        .foregroundColor(AppColors.primary)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 64)
        .background(AppColors.secondaryBackground)
        .cornerRadius(12)
        .accessibilityLabel("问一句")
        .accessibilityHint("点击后开始录音，可以问志愿者还有多远、几点开始，或者打电话给志愿者")
        .accessibilityIdentifier("blindOrderStatusAskQuestionButton")
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        BlindOrderStatusView(orderId: 1) { _ in }
            .environmentObject(AppState())
            .environmentObject(SpeechService())
            .environmentObject(LocationService())
            .environmentObject(SpeechInputService())
    }
}
#endif
