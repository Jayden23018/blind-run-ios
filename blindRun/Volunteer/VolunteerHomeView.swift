import Combine
import CoreLocation
import SwiftUI

// MARK: - Volunteer Home ViewModel

@MainActor
final class VolunteerHomeViewModel: ObservableObject {
    @Published var isAvailable = false
    @Published var nickname = ""
    @Published var dispatchSummary: VolunteerDispatchSummaryResponse?
    @Published var errorMessage: String?
    @Published var dispatchSummaryErrorMessage: String?
    @Published private(set) var dispatchLoadState: AsyncLoadState<VolunteerDispatchSummaryResponse> = .idle
    @Published private(set) var refreshPhase: HomeRefreshPhase = .idle
    @Published var isUpdatingAvailability = false
    @Published var activeOrder: OrderDetailResponse?
    @Published private(set) var locationDispatchWarning: String?

    // WebSocket dispatch state
    @Published var incomingOrder: WSNewOrder?
    @Published var dispatchCountdown: Int = 0
    @Published var isRespondingToDispatch = false
    /// 接单被后端 403 `VOLUNTEER_NOT_VERIFIED` 拒绝后，错误区要长出「去上传资质证书」入口。
    @Published var needsCertificateUpload = false
    @Published var acceptedDispatchOrderId: Int64?
    @Published var acceptedDispatchInitialOrder: OrderDetailResponse?
    /// 要进的那一单通话磨合。**两种到达方式共用这一个导航源。**
    ///
    /// 🚨 带着**派单载荷**而不只是订单 id，因为通话磨合期志愿者根本取不到订单详情：
    /// 后端 `OrderQueryService.getOrder` 只认 `order.volunteer`，而 `markInterested`
    /// 只写 `dispatchCurrentVolunteerId`、`order.volunteer` 恒为 null ⇒ `GET /api/orders/{id}` 403。
    /// 那条推送是那一刻**唯一**的订单事实来源（出发地、时间、导盲犬），丢了就没别的地方能取回来。
    ///
    /// 而冷启动恢复那条路上它**确实丢了**（App 被杀，推送不会重放），所以
    /// `VolunteerIntroCallRoute.dispatchOrder` 是可选的 —— 见那个类型的注释。
    @Published var pendingIntroCallOrder: VolunteerIntroCallRoute?
    /// 已经因为 `introCallOrderId` 自动跳过一次的那一单。
    ///
    /// 🚨 **没有它就是一个导航死循环**：用户手动返回 → `pendingIntroCallOrder` 被清 →
    /// 下一次 `dispatch-summary` 刷新（首页每几秒就会刷）看到 `introCallOrderId` 还在 →
    /// 又把他推回通话页。在 20 分钟窗口结束前他出不来。
    ///
    /// 只记 id 不记「跳过几次」：换了一单就该再跳一次，那是另一个人在等他。
    private var autoOpenedIntroCallOrderId: Int64?

    private weak var appState: AppState?
    private var speechService: SpeechService?
    private var realtimeDispatchCancellable: AnyCancellable?
    private var realtimeRecoveryCancellable: AnyCancellable?
    private var realtimeStatusCancellable: AnyCancellable?
    private var countdownTask: Task<Void, Never>?
    private var delayedSummaryRefreshTask: Task<Void, Never>?
    private var isSceneActive = false
    /// 定位单次采样为 nil 是真机上的常见瞬态，报警必须等「连续失败」才算数。
    /// 取 3：刷新循环每 10 秒上报一次，连续 3 次约等于持续 20 秒都拿不到定位，
    /// 足以滤掉单次采样抖动，又不至于让真的定位失效拖到半分钟后才提示志愿者。
    private static let locationReportFailureThreshold = 3
    private var consecutiveLocationReportFailures = 0
    private var currentLocationProvider: () -> CLLocationCoordinate2D? = { nil }
    private var locationAuthorizedProvider: () -> Bool = { false }
    private let reportVolunteerLocation: @MainActor (AppState, CLLocationCoordinate2D?, Bool) -> Bool
    private let dispatchPropagationDelay: TimeInterval
    private let loadTimeout: TimeInterval
    private var activeLoadTask: Task<Void, Never>?
    private var activeRequestID: UUID?
    private var auxiliaryLoadTask: Task<Void, Never>?
    private var auxiliaryRequestID: UUID?
    private var summaryRefreshTask: Task<Void, Never>?
    private var summaryRefreshID: UUID?
    private var refreshLoopTask: Task<Void, Never>?

    init(
        dispatchPropagationDelay: TimeInterval = 1,
        loadTimeout: TimeInterval = HomeLoadPolicy.defaultTimeout,
        reportVolunteerLocation: @escaping @MainActor (AppState, CLLocationCoordinate2D?, Bool) -> Bool = {
            VolunteerLocationReporter.reportIfNeeded(
                appState: $0,
                currentLocation: $1,
                locationAuthorized: $2
            )
        }
    ) {
        self.dispatchPropagationDelay = max(0, dispatchPropagationDelay)
        self.loadTimeout = max(0.05, loadTimeout)
        self.reportVolunteerLocation = reportVolunteerLocation
    }

    var isLoading: Bool { refreshPhase.isRefreshing }

    var statusText: String {
        dispatchSummary?.dispatchStatusText ?? (isAvailable ? "等待系统派单" : "已关闭接单")
    }

    var displayedErrorMessage: String? {
        errorMessage ?? dispatchSummaryErrorMessage
    }

    var statusColor: Color {
        if dispatchSummary?.canDispatch == true {
            return AppColors.success
        }
        return isAvailable ? AppColors.warning : AppColors.textSecondary
    }

    var acceptBlockMessage: String? {
        VolunteerOrderActionGuard.acceptBlockMessage(
            profile: appState?.volunteerProfile,
            registrationStatus: appState?.volunteerRegistrationStatus
        )
    }

    static func activeVolunteerOrder(from orders: [OrderDetailResponse]) -> OrderDetailResponse? {
        orders
            .filter { $0.status.isActiveForVolunteer }
            .sorted { $0.sortKey > $1.sortKey }
            .first
    }

    func configure(
        with appState: AppState,
        speechService: SpeechService,
        currentLocationProvider: @escaping () -> CLLocationCoordinate2D? = { nil },
        locationAuthorizedProvider: @escaping () -> Bool = { false }
    ) {
        self.appState = appState
        self.speechService = speechService
        self.currentLocationProvider = currentLocationProvider
        self.locationAuthorizedProvider = locationAuthorizedProvider
        apply(profile: appState.volunteerProfile)
        subscribeToRealtimeCoordinator(appState)
    }

    func setSceneActive(_ isActive: Bool) {
        isSceneActive = isActive
        if !isActive {
            cancelLoading()
            summaryRefreshTask?.cancel()
            summaryRefreshTask = nil
            summaryRefreshID = nil
            delayedSummaryRefreshTask?.cancel()
            delayedSummaryRefreshTask = nil
            refreshLoopTask?.cancel()
            refreshLoopTask = nil
        }
    }

    // MARK: - WebSocket Dispatch

    /// 响应派单。
    ///
    /// 🚨 **`.interested` 是陌生人路径的默认动作，不是一个可选项。**
    /// 后端 `app.intro-call.enabled` 默认 true，陌生人直接发 `ACCEPT` 会 409
    /// `INTRO_CALL_REQUIRED`（`DispatchService.handleAccept` 的守卫）。后端只在两种情况放行
    /// `ACCEPT`：这一对已经磨合成功过（`IntroCallPair.outcome == MATCHED`），或者距开跑时间
    /// 已经塞不下一轮 20 分钟的通话窗口。
    ///
    /// 后端**已经算好了这个判据并起了名字**：`AvailableOrderResponse.requiresIntroCall`
    /// （`api_spec.yaml:5646`，2026-08-22 新增，逐字写着「客户端必须按它决定发哪个 action」）。
    /// 但它只挂在 `GET /api/orders/available` 上，而**本 App 不调那条端点** ——
    /// 公开订单池链路已删除，志愿者这边唯一的派单通道是 `NEW_ORDER` 推送，
    /// 而那份载荷里没有这个字段（后端 `NotificationService.sendDispatchNotification`
    /// 逐个 `msg.put` 得出来的键里没有它）。
    ///
    /// 自己算也不行：「这两人磨合成功过没有」客户端无从得知；通话窗口长度是后端配置
    /// （`app.intro-call.window-minutes`），照 20 分钟硬编码会在后端改配置那天静默错。
    ///
    /// 所以在字段搬到推送上之前一律发 `.interested` —— 那条路径在开关关掉时也照常可用
    /// （`DispatchService.introCallEnabled` 的注释：关掉只是不再**强制**）。
    /// 代价是熟人也要多聊一次。**已投 `demo/docs/handoff.md`**，
    /// 字段到了这里才该长出 `.accept` 分支。
    func respondToDispatch(
        action: OrderRespondAction,
        currentLocation: CLLocationCoordinate2D?,
        locationAuthorized: Bool
    ) {
        guard let order = incomingOrder else { return }
        guard let appState else { return }
        let accept = action == .accept
        if accept || action == .interested {
            // 定位权限只对 `.accept` 卡：`INTERESTED` 不上报位置，也还不是接单。
            // 为一件不需要定位的事拦住用户，代价落回正在等的盲人身上。
            // 资质（`verified`）两条路径都要过 —— 后端 `markInterested` 也跑同一套校验。
            let message = accept
                ? VolunteerOrderActionGuard.acceptBlockMessage(
                    profile: appState.volunteerProfile,
                    registrationStatus: appState.volunteerRegistrationStatus,
                    locationAuthorized: locationAuthorized
                )
                : VolunteerOrderActionGuard.acceptBlockMessage(
                    profile: appState.volunteerProfile,
                    registrationStatus: appState.volunteerRegistrationStatus
                )
            if let message {
                errorMessage = message
                speechService?.speakError(message)
                return
            }
        }
        isRespondingToDispatch = true
        Task {
            do {
                if accept {
                    VolunteerLocationReporter.reportIfNeeded(
                        appState: appState,
                        currentLocation: currentLocation,
                        locationAuthorized: locationAuthorized
                    )
                }
                try await appState.orders.respond(orderId: order.orderId, action: action)
                let acceptedOrderId = accept ? order.orderId : nil
                let acceptedOrder = await refreshAfterDispatchResponse(
                    acceptedOrderId: acceptedOrderId,
                    appState: appState
                )
                dismissDispatch()
                appState.realtimeCoordinator.clearDispatch(orderID: order.orderId)
                acceptedDispatchInitialOrder = acceptedOrder
                acceptedDispatchOrderId = acceptedOrderId
                if action == .interested {
                    pendingIntroCallOrder = VolunteerIntroCallRoute(dispatchOrder: order)
                }
                speechService?.speak(Self.dispatchResponseSpeech(for: action))
            } catch let error as APIError {
                isRespondingToDispatch = false
                if appState.handleAuthenticatedAPIError(error) {
                    return
                }
                needsCertificateUpload = error.errorCode == .volunteerNotApproved
                errorMessage = error.localizedMessage
                speechService?.speakError(error.localizedMessage)
            } catch {
                isRespondingToDispatch = false
                errorMessage = "响应失败，请重试"
                speechService?.speakError("响应失败，请重试")
            }
        }
    }

    /// 三种动作各自的播报。`.interested` 刻意不说「已接单」——它不是接单，说错了志愿者
    /// 会以为事情已经定了，然后错过那通电话。
    static func dispatchResponseSpeech(for action: OrderRespondAction) -> String {
        switch action {
        case .accept:
            return "已接受订单"
        case .decline:
            return "已拒绝订单"
        case .interested:
            return "已告诉跑者你有意向，请留意他的来电"
        }
    }

    func dismissDispatch() {
        countdownTask?.cancel()
        countdownTask = nil
        incomingOrder = nil
        dispatchCountdown = 0
        isRespondingToDispatch = false
    }

    /// 通话磨合结束（成单 / 换人 / 超时）后把入口收掉。
    ///
    /// ⚠️ **不清 `autoOpenedIntroCallOrderId`。** 用户手动返回也走这里，
    /// 清了的话下一次 `dispatch-summary` 刷新会把他重新推回通话页 —— 见那个字段的注释。
    /// 那个记号跟着 orderId 走，换一单自然失效。
    func clearIntroCall() {
        pendingIntroCallOrder = nil
    }

    private func refreshAfterDispatchResponse(
        acceptedOrderId: Int64?,
        appState: AppState
    ) async -> OrderDetailResponse? {
        var acceptedOrder: OrderDetailResponse?

        // 两处 `try?` 是**迁移前就有的**，这里原样保留：这一步跑在「已经响应成功」之后，
        // 播报与导航都不依赖它，拿不到只是首页少刷一次，5 秒后的下一轮会补上。
        if let acceptedOrderId {
            acceptedOrder = try? await appState.orders.orderDetail(orderId: acceptedOrderId)
            activeOrder = acceptedOrder
        }

        if let summary = try? await appState.orders.dispatchSummary() {
            apply(summary: summary)
        }

        if let acceptedOrder {
            activeOrder = acceptedOrder
        }

        return acceptedOrder
    }

    private func subscribeToRealtimeCoordinator(_ appState: AppState) {
        guard realtimeDispatchCancellable == nil else { return }
        realtimeDispatchCancellable = appState.realtimeCoordinator.$pendingDispatch
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] prompt in
                self?.handleNewOrder(prompt)
            }
        realtimeRecoveryCancellable = appState.realtimeCoordinator.recoveryPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] signal in
                guard signal.role == .volunteer else { return }
                self?.recoverDispatchReadinessAfterReconnect()
            }
        realtimeStatusCancellable = appState.realtimeCoordinator.statusUpdatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                guard let self,
                      let current = self.activeOrder,
                      current.orderId == update.orderId else { return }
                let updated = current.replacingStatus(with: update.toStatus)
                if updated.status.isActiveForVolunteer {
                    self.activeOrder = updated
                    self.appState?.liveEscortCoordinator.updateOwnedOrder(
                        orderID: updated.orderId,
                        status: updated.status
                    )
                } else {
                    self.activeOrder = nil
                    self.appState?.realtimeCoordinator.unregisterActiveOrder(updated.orderId)
                    self.appState?.liveEscortCoordinator.clearOwnedOrder()
                }
                self.speechService?.speakStatusChange(updated.status)
                self.dispatchSummaryErrorMessage = nil
                if let summary = self.dispatchSummary {
                    self.dispatchLoadState = .loaded(summary)
                }
            }
    }

    private func handleNewOrder(_ prompt: RealtimeDispatchPrompt) {
        let order = prompt.order
        // 如果已经有一个正在展示的 dispatch，忽略新的
        guard incomingOrder == nil else { return }

        incomingOrder = order
        appState?.realtimeCoordinator.markDispatchPresented(orderID: order.orderId)
        dispatchCountdown = prompt.remainingSeconds()
        guard dispatchCountdown > 0 else {
            dismissDispatch()
            return
        }
        speechService?.speak("新订单到达，请在\(dispatchCountdown)秒内响应")

        countdownTask?.cancel()
        countdownTask = Task {
            while dispatchCountdown > 0, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                dispatchCountdown -= 1
            }
            if !Task.isCancelled {
                // 超时自动拒绝
                respondToDispatch(action: .decline, currentLocation: nil, locationAuthorized: false)
            }
        }
    }

    func load(currentLocation: CLLocationCoordinate2D?, locationAuthorized: Bool) async {
        guard let appState else { return }
        if let activeLoadTask {
            ClientFlowDiagnostics.record(event: "coalesced", operation: "volunteer-home-refresh")
            await activeLoadTask.value
            return
        }
        ClientFlowDiagnostics.record(event: "started", operation: "volunteer-home-refresh")
        let requestID = UUID()
        activeRequestID = requestID
        refreshPhase = .refreshing(requestID: requestID)
        if dispatchSummary == nil {
            dispatchLoadState = .loading(requestID: requestID)
        }
        errorMessage = nil
        dispatchSummaryErrorMessage = nil
        needsCertificateUpload = false

        let workTask = Task { [weak self, weak appState] in
            guard let self, let appState else { return }
            await self.performInitialLoad(
                appState: appState,
                requestID: requestID,
                currentLocation: currentLocation,
                locationAuthorized: locationAuthorized
            )
        }
        activeLoadTask = workTask

        await withTaskCancellationHandler {
            await workTask.value
        } onCancel: {
            workTask.cancel()
            Task { @MainActor [weak self] in
                self?.cancelRequestIfCurrent(requestID)
            }
        }

        guard activeRequestID == requestID else { return }
        activeLoadTask = nil
        activeRequestID = nil
        refreshPhase = .idle
        ClientFlowDiagnostics.record(event: "finished", operation: "volunteer-home-refresh")
        if dispatchLoadState.isLoading {
            if let dispatchSummary {
                dispatchLoadState = .loaded(dispatchSummary)
            } else {
                dispatchLoadState = .failed(message: "派单状态加载失败，请重试。")
            }
        }
    }

    func cancelLoading() {
        activeLoadTask?.cancel()
        auxiliaryLoadTask?.cancel()
        activeLoadTask = nil
        auxiliaryLoadTask = nil
        auxiliaryRequestID = nil
        activeRequestID = nil
        refreshPhase = .idle
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
        requestID: UUID,
        currentLocation: CLLocationCoordinate2D?,
        locationAuthorized: Bool
    ) async {
        let didReportLocation = reportVolunteerLocation(appState, currentLocation, locationAuthorized)
        updateLocationDispatchWarning(didReportLocation: didReportLocation, appState: appState)

        do {
            let orders = appState.orders
            let summary: VolunteerDispatchSummaryResponse = try await HomeLoadCoordinator.run(
                timeout: loadTimeout,
                operationName: "volunteer-dispatch-initial"
            ) {
                try await orders.dispatchSummary()
            }
            guard activeRequestID == requestID, !Task.isCancelled else { return }
            apply(summary: summary)
            dispatchLoadState = .loaded(summary)
            dispatchSummaryErrorMessage = nil
        } catch HomeLoadCoordinatorError.timedOut {
            guard activeRequestID == requestID, !Task.isCancelled else { return }
            let message = "加载超过 20 秒，请重试。"
            dispatchSummaryErrorMessage = message
            dispatchLoadState = dispatchSummary.map(AsyncLoadState.loaded) ?? .failed(message: message)
            speechService?.speakError(message)
        } catch let apiError as APIError {
            guard activeRequestID == requestID, !Task.isCancelled else { return }
            if appState.handleAuthenticatedAPIError(apiError) { return }
            dispatchSummaryErrorMessage = apiError.localizedMessage
            dispatchLoadState = dispatchSummary.map(AsyncLoadState.loaded) ?? .failed(message: apiError.localizedMessage)
            speechService?.speakError(apiError.localizedMessage)
        } catch is CancellationError {
            return
        } catch {
            guard activeRequestID == requestID, !Task.isCancelled else { return }
            let message = "派单状态加载失败，请重试。"
            dispatchSummaryErrorMessage = message
            dispatchLoadState = dispatchSummary.map(AsyncLoadState.loaded) ?? .failed(message: message)
            speechService?.speakError(message)
        }

        guard activeRequestID == requestID, !Task.isCancelled else { return }
        startAuxiliaryLoad(appState: appState)
    }

    private func startAuxiliaryLoad(appState: AppState) {
        auxiliaryLoadTask?.cancel()
        let requestID = UUID()
        auxiliaryRequestID = requestID
        // 这两条是**认证·会话片**的端点（`AuthServing.volunteerProfile` /
        // `.volunteerRegistrationStatus`），不在订单片里再开一条同路径 ——
        // 同一个端点两处字面量迟早漂移。
        let auth = appState.auth
        auxiliaryLoadTask = Task { [weak self, weak appState] in
            guard let self, let appState else { return }
            async let profileResult: Result<VolunteerProfileResponse, Error> = Self.fetchResult {
                try await HomeLoadCoordinator.run(
                    timeout: self.loadTimeout,
                    operationName: "volunteer-profile"
                ) {
                    try await auth.volunteerProfile()
                }
            }
            async let registrationResult: Result<VolunteerRegistrationStatus, Error> = Self.fetchResult {
                try await HomeLoadCoordinator.run(
                    timeout: self.loadTimeout,
                    operationName: "volunteer-registration"
                ) {
                    try await auth.volunteerRegistrationStatus()
                }
            }

            let (profile, registration) = await (profileResult, registrationResult)
            guard !Task.isCancelled, self.auxiliaryRequestID == requestID else { return }
            if case .success(let value) = profile {
                appState.updateVolunteerProfile(value)
                self.apply(profile: value)
            }
            if case .success(let value) = registration {
                appState.updateVolunteerRegistrationStatus(value)
            }
            self.auxiliaryLoadTask = nil
            self.auxiliaryRequestID = nil
        }
    }

    nonisolated private static func fetchResult<Value: Sendable>(
        operation: @escaping @Sendable () async throws -> Value
    ) async -> Result<Value, Error> {
        do { return .success(try await operation()) }
        catch { return .failure(error) }
    }

    private func cancelRequestIfCurrent(_ requestID: UUID) {
        guard activeRequestID == requestID else { return }
        cancelLoading()
    }

    func setAvailability(_ value: Bool) {
        guard !isUpdatingAvailability, let appState else { return }

        let previousValue = isAvailable
        isAvailable = value
        Task {
            await updateAvailability(value, previousValue: previousValue, appState: appState)
        }
    }

    private func updateAvailability(_ value: Bool, previousValue: Bool, appState: AppState) async {
        isUpdatingAvailability = true
        errorMessage = nil

        do {
            try await appState.orders.setDispatchStatus(wantsDispatch: value)
            let existingProfile = appState.volunteerProfile
                let profile = VolunteerProfileResponse(
                    name: existingProfile?.name,
                    verificationStatus: existingProfile?.verificationStatus,
                    adminReviewStatus: existingProfile?.adminReviewStatus,
                    registrationStep: existingProfile?.registrationStep,
                    canAcceptOrders: existingProfile?.canAcceptOrders,
                    isAvailable: value,
                    wantsDispatch: value,
                    availableTimeSlots: existingProfile?.availableTimeSlots,
                acceptsGuideDog: existingProfile?.acceptsGuideDog,
                paceRange: existingProfile?.paceRange
            )
            appState.updateVolunteerProfile(profile)
            apply(profile: profile)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else {
                isUpdatingAvailability = false
                return
            }
            // `try?` 是迁移前就有的：开关本身已经切成功并播报过了，这一步只是把摘要刷新一下，
            // 拿不到不改变「已上线 / 已下线」这个既成事实。
            if let summary = try? await appState.orders.dispatchSummary() {
                apply(summary: summary)
            }
            isUpdatingAvailability = false
        } catch let error as APIError {
            isAvailable = previousValue
            isUpdatingAvailability = false
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isAvailable = previousValue
            isUpdatingAvailability = false
            errorMessage = "可服务状态更新失败，请重试"
            speechService?.speakError("可服务状态更新失败，请重试")
        }
    }

    private func apply(profile: VolunteerProfileResponse?) {
        guard let profile else { return }
        nickname = profile.name ?? ""
        isAvailable = profile.isAvailable ?? false
    }

    /// 摘要的唯一漏斗 —— 冷启动首屏、下拉刷新、接单后回读全从这里过，
    /// 所以 `recoverIntroCallIfNeeded` 挂在这里就够，不必在每个调用点各接一次。
    ///
    /// 非 private 是为了让单测能直接喂一份摘要进来：起真实的加载流程会顺带打三四个端点、
    /// 动状态机，把「摘要里有 introCallOrderId 会怎样」这一条断言埋进一堆无关请求里。
    func apply(
        summary: VolunteerDispatchSummaryResponse,
        statusRequestToken: OrderStatusRequestToken? = nil
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
        recoverIntroCallIfNeeded(summary: summary)
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

    func refreshDispatchSummary() async {
        guard let appState else { return }
        if let activeLoadTask {
            ClientFlowDiagnostics.record(event: "coalesced", operation: "volunteer-summary-refresh")
            await activeLoadTask.value
            return
        }
        if let summaryRefreshTask {
            ClientFlowDiagnostics.record(event: "coalesced", operation: "volunteer-summary-refresh")
            await summaryRefreshTask.value
            return
        }

        let refreshID = UUID()
        summaryRefreshID = refreshID
        ClientFlowDiagnostics.record(event: "started", operation: "volunteer-summary-refresh")
        refreshPhase = .refreshing(requestID: refreshID)
        let task = Task { [weak self, weak appState] in
            guard let self, let appState else { return }
            await self.performDispatchSummaryRefresh(appState: appState, refreshID: refreshID)
        }
        summaryRefreshTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if summaryRefreshID == refreshID {
            summaryRefreshTask = nil
            summaryRefreshID = nil
            refreshPhase = .idle
            ClientFlowDiagnostics.record(event: "finished", operation: "volunteer-summary-refresh")
        }
    }

    private func performDispatchSummaryRefresh(appState: AppState, refreshID: UUID) async {
        do {
            let orders = appState.orders
            let statusRequestToken = activeOrder.map {
                appState.realtimeCoordinator.beginOrderStatusRequest(orderID: $0.orderId)
            }
            let summary: VolunteerDispatchSummaryResponse = try await HomeLoadCoordinator.run(
                timeout: loadTimeout,
                operationName: "volunteer-dispatch-refresh"
            ) {
                try await orders.dispatchSummary()
            }
            guard !Task.isCancelled, summaryRefreshID == refreshID else { return }
            apply(summary: summary, statusRequestToken: statusRequestToken)
            dispatchLoadState = .loaded(summary)
            dispatchSummaryErrorMessage = nil
        } catch HomeLoadCoordinatorError.timedOut {
            guard !Task.isCancelled, summaryRefreshID == refreshID else { return }
            dispatchSummaryErrorMessage = "派单状态刷新超过 20 秒，请重试"
        } catch let error as APIError {
            guard !Task.isCancelled, summaryRefreshID == refreshID else { return }
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            dispatchSummaryErrorMessage = error.localizedMessage
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, summaryRefreshID == refreshID else { return }
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
        let didReportLocation = reportVolunteerLocation(
            appState,
            currentLocation,
            locationAuthorized
        )
        updateLocationDispatchWarning(
            didReportLocation: didReportLocation,
            appState: appState
        )
        if didReportLocation {
            try? await Task.sleep(nanoseconds: UInt64(dispatchPropagationDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
        }
        await refreshDispatchSummary()
    }

    private func recoverDispatchReadinessAfterReconnect() {
        guard isSceneActive else { return }
        delayedSummaryRefreshTask?.cancel()
        delayedSummaryRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.reportLocationThenRefreshSummary(
                currentLocation: self.currentLocationProvider(),
                locationAuthorized: self.locationAuthorizedProvider()
            )
        }
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

// MARK: - Volunteer Home Layout Helpers

enum VolunteerDemandPanelDetent: CaseIterable, Equatable {
    case compact
    case medium
    case expanded

    static let bottomMargin: CGFloat = 8

    /// 档位的可读名。调整动作必须有它 —— 没有当前值的可调整控件，
    /// 读屏用户调完听不到自己调到了哪一档，等于在盲调。
    var accessibilityValue: String {
        switch self {
        case .compact:
            return "收起"
        case .medium:
            return "中等"
        case .expanded:
            return "展开"
        }
    }

    func height(viewportHeight: CGFloat, topContentBottom: CGFloat) -> CGFloat {
        let viewportHeight = Self.safeViewportHeight(viewportHeight)
        let topContentBottom = Self.safeTopContentBottom(topContentBottom)
        switch self {
        case .compact:
            return Self.compactHeight(viewportHeight: viewportHeight)
        case .medium:
            let proposed = viewportHeight * 0.42
            let maximum = max(Self.compactHeight(viewportHeight: viewportHeight), viewportHeight * 0.56)
            return min(max(proposed, 300), maximum)
        case .expanded:
            let topLimit = max(topContentBottom + 8, 96)
            let proposed = viewportHeight - topLimit - Self.bottomMargin
            return max(Self.compactHeight(viewportHeight: viewportHeight), proposed)
        }
    }

    func next() -> VolunteerDemandPanelDetent {
        switch self {
        case .compact:
            return .medium
        case .medium:
            return .expanded
        case .expanded:
            return .compact
        }
    }

    /// 相邻档位，**不循环**。
    ///
    /// 与 `next()` 的区别是刻意的：`next()` 给点抓手用，点到最大再点回最小是一个手指
    /// 在同一个位置反复点时想要的行为。而 VoiceOver 的「向上轻扫增大」和 Switch Control
    /// 的「调整」都有方向语义 —— 增大到顶应该停住，循环回最小会让人以为自己滑反了。
    func adjusted(by delta: Int) -> VolunteerDemandPanelDetent {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self) else { return self }
        return all[min(max(index + delta, 0), all.count - 1)]
    }

    static func compactHeight(viewportHeight: CGFloat) -> CGFloat {
        let viewportHeight = safeViewportHeight(viewportHeight)
        return min(max(viewportHeight * 0.12, 104), 136)
    }

    static func clampedHeight(
        _ height: CGFloat,
        viewportHeight: CGFloat,
        topContentBottom: CGFloat
    ) -> CGFloat {
        let viewportHeight = safeViewportHeight(viewportHeight)
        let topContentBottom = safeTopContentBottom(topContentBottom)
        let minimum = compact.height(viewportHeight: viewportHeight, topContentBottom: topContentBottom)
        let maximum = max(minimum, expanded.height(viewportHeight: viewportHeight, topContentBottom: topContentBottom))
        let safeHeight = height.isFinite ? height : minimum
        return min(max(safeHeight, minimum), maximum)
    }

    static func nearest(
        to height: CGFloat,
        viewportHeight: CGFloat,
        topContentBottom: CGFloat
    ) -> VolunteerDemandPanelDetent {
        let safeHeight = height.isFinite ? height : compactHeight(viewportHeight: viewportHeight)
        return allCases.min { lhs, rhs in
            abs(lhs.height(viewportHeight: viewportHeight, topContentBottom: topContentBottom) - safeHeight) <
                abs(rhs.height(viewportHeight: viewportHeight, topContentBottom: topContentBottom) - safeHeight)
        } ?? .medium
    }

    private static func safeViewportHeight(_ value: CGFloat) -> CGFloat {
        guard value.isFinite, value > 0 else { return 0 }
        return value
    }

    private static func safeTopContentBottom(_ value: CGFloat) -> CGFloat {
        guard value.isFinite, value > 0 else { return 0 }
        return value
    }
}

struct VolunteerHomeMapLayout {
    static func screenAnchorY(
        viewportHeight: CGFloat,
        topContentBottom: CGFloat,
        demandPanelTop: CGFloat
    ) -> CGFloat {
        guard viewportHeight.isFinite, viewportHeight > 1 else { return 0.5 }
        let safeTopContentBottom = topContentBottom.isFinite ? topContentBottom : 0
        let safeDemandPanelTop = demandPanelTop.isFinite ? demandPanelTop : safeTopContentBottom + 1
        let upper = max(safeTopContentBottom, 0)
        let lower = max(safeDemandPanelTop, upper + 1)
        let visibleCenterY = (upper + lower) / 2
        return min(max(visibleCenterY / viewportHeight, 0.18), 0.82)
    }
}

enum VolunteerHomeTopLayout {
    /// 顶部保留高度占视口的上限。
    ///
    /// 定这个数的是 `.expanded` 档位的算式：它 = `viewport − (reservedBottom + 8) − bottomMargin`。
    /// 保留高度不封顶时，iPhone 横屏（视口约 390pt）+ 有进行中订单会算出
    /// `390 − 308 − 8 = 74`，被 `max(compactHeight, …)` 抬回 104 —— **与 `.compact` 相等**。
    /// 于是 `clampedHeight` 的上下界重合，面板卡死在最小高度：展开点了没反应，也拖不动。
    ///
    /// 0.55 是从「展开档至少要占视口 45%」倒推的：`reserved ≤ viewport × 0.55 − 16`。
    /// iPhone 竖屏（844pt → 448）与 iPad（≥1024pt → ≥547）都够不着这条线，行为不变；
    /// 只有矮窗口会被压。压小后面板可能盖住顶部状态块 —— 但面板是可拖的，
    /// 拖下来就能看到；卡死则是无解。
    static let maximumReservedFraction: CGFloat = 0.55
    private static let expandedDetentInset: CGFloat = 16

    static func reservedBottom(
        safeAreaTop: CGFloat,
        hasActiveOrder: Bool,
        viewportHeight: CGFloat
    ) -> CGFloat {
        let safeTop = safeAreaTop.isFinite ? max(safeAreaTop, 0) : 0
        // Keep the panel below the material status block without feeding a measured
        // child frame back into the same layout graph.
        let desired = safeTop + (hasActiveOrder ? 300 : 180)
        guard viewportHeight.isFinite, viewportHeight > 0 else { return desired }
        let ceiling = viewportHeight * maximumReservedFraction - expandedDetentInset
        // `ceiling` 在极矮的视口下会算成负数，那时保留 0 —— 让面板拿走整屏，
        // 总好过返回一个负的保留高度把地图锚点算到屏幕外。
        return min(desired, max(ceiling, 0))
    }
}

// MARK: - Volunteer Home View

struct VolunteerHomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    /// 派单面板是全 App 位移幅度最大的动效（整块面板弹到另一个档位），而弹簧的回弹正是
    /// 「减弱动态效果」要压掉的那一类。开启后改成瞬时切换：落点不变，只是不弹。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var nearbyHeaderLargeSize: CGFloat = 30
    @ScaledMetric(relativeTo: .title) private var nearbyHeaderCompactSize: CGFloat = 24
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @EnvironmentObject private var locationService: LocationService
    @StateObject private var viewModel = VolunteerHomeViewModel()
    @State private var recenterToken = 0
    @State private var demandPanelDetent: VolunteerDemandPanelDetent = .medium
    @State private var demandPanelDragTranslation: CGFloat = 0

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let resolvedTopBottom = resolvedTopContentBottom(in: proxy)
                let panelHeight = demandPanelHeight(in: proxy, topContentBottom: resolvedTopBottom)
                let panelTop = proxy.size.height - panelHeight - VolunteerDemandPanelDetent.bottomMargin
                let mapAnchorY = VolunteerHomeMapLayout.screenAnchorY(
                    viewportHeight: proxy.size.height,
                    topContentBottom: resolvedTopBottom,
                    demandPanelTop: panelTop
                )

                ZStack(alignment: .bottom) {
                    homeMap(screenAnchor: CGPoint(x: 0.5, y: mapAnchorY))

                    VStack(spacing: 0) {
                        Spacer()

                        recenterButton
                            .padding(.horizontal, 16)
                            .padding(.bottom, panelHeight + 16)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    nearbyDemandPanel(height: panelHeight, isCompact: demandPanelDetent == .compact, proxy: proxy)
                        .padding(.horizontal, 10)
                        .padding(.bottom, VolunteerDemandPanelDetent.bottomMargin)
                }
                .overlay(alignment: .top) {
                    VStack(spacing: 8) {
                        homeStatusOverlay

                        if let activeOrder = viewModel.activeOrder {
                            NavigationLink {
                                currentOrderDestination(activeOrder)
                            } label: {
                                VolunteerCurrentOrderCard(order: activeOrder)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("当前订单：\(activeOrder.status.displayName)，盲人 \(activeOrder.blindName ?? "")，地点 \(activeOrder.startAddress ?? "")")
                            .accessibilityHint("点击进入当前订单")
                            .accessibilityIdentifier("volunteerHomeCurrentOrderCard")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .background(AppColors.background)
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            // 一个 destination 分两种落点，不是两个 `navigationDestination(isPresented:)` ——
            // 同一个视图上挂两条 `isPresented` 版本在 iOS 16 上会互相顶掉。
            .navigationDestination(
                isPresented: Binding(
                    get: { viewModel.acceptedDispatchOrderId != nil || viewModel.pendingIntroCallOrder != nil },
                    set: { isPresented in
                        if !isPresented {
                            viewModel.acceptedDispatchOrderId = nil
                            viewModel.acceptedDispatchInitialOrder = nil
                            viewModel.clearIntroCall()
                        }
                    }
                )
            ) {
                if let introCallRoute = viewModel.pendingIntroCallOrder {
                    VolunteerIntroCallView(route: introCallRoute)
                } else if let orderId = viewModel.acceptedDispatchOrderId {
                    VolunteerInServiceView(
                        orderId: orderId,
                        initialOrder: viewModel.acceptedDispatchInitialOrder
                    )
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomEntries
            }
            .onAppear {
                locationService.requestPermission()
                locationService.startUpdating()
            }
            .onDisappear {
                viewModel.setSceneActive(false)
            }
            .task(id: scenePhase) {
                viewModel.configure(
                    with: appState,
                    speechService: speechService,
                    currentLocationProvider: { locationService.currentLocation },
                    locationAuthorizedProvider: { locationService.isAuthorized }
                )
                let isActive = scenePhase == .active
                viewModel.setSceneActive(isActive)
                guard isActive else { return }
                await loadHome()
                viewModel.startRefreshLoop()
            }
            .overlay {
                if viewModel.incomingOrder != nil {
                    VolunteerDispatchOverlay(
                        order: viewModel.incomingOrder!,
                        countdown: viewModel.dispatchCountdown,
                        isResponding: viewModel.isRespondingToDispatch,
                        currentLocation: locationService.currentLocation,
                        locationAuthorized: locationService.isAuthorized,
                        fallbackCoordinate: locationService.effectiveBackendLocation,
                        // 🚨 「有意向」替代了「接单」：陌生人直接发 ACCEPT 会被后端 409
                        // `INTRO_CALL_REQUIRED`，而派单推送里没带 `requiresIntroCall`，
                        // 客户端分不出这一对是不是熟人（见 `respondToDispatch` 上那段说明）。
                        onInterested: {
                            viewModel.respondToDispatch(
                                action: .interested,
                                currentLocation: locationService.currentLocation,
                                locationAuthorized: locationService.isAuthorized
                            )
                        },
                        onDecline: {
                            viewModel.respondToDispatch(
                                action: .decline,
                                currentLocation: nil,
                                locationAuthorized: false
                            )
                        }
                    )
                }
            }
        }
    }

    private func homeMap(screenAnchor: CGPoint) -> some View {
        MapViewWrapper(
            centerCoordinate: locationService.effectiveBackendLocation,
            showsUserLocation: locationService.isAuthorized,
            // 志愿者首页走系统派单，不再展示公开订单池，所以底图上没有订单标注。
            // 派单来的那一单有自己的地图（`VolunteerOrderMap`），不在这张底图上。
            annotations: [],
            zoomLevel: 13,
            recenterToken: recenterToken,
            showsCompass: false,
            screenAnchor: screenAnchor
        )
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.16)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 260)
            .allowsHitTesting(false)
        }
        // 位置和派单摘要已由顶部状态块完整朗读；地图使用稳定语义，
        // 避免 MAMapView 帧更新反复求值动态时间/覆盖文案。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("志愿者首页辅助地图")
        .accessibilityHint("地图用于视觉查看当前位置覆盖范围；派单状态面板会读出当前位置和覆盖摘要")
        .accessibilityIdentifier("volunteerHomeMap")
    }

    private var homeStatusOverlay: some View {
        VolunteerHomeStatusOverlay(
            nickname: viewModel.nickname.isEmpty ? "志愿者" : viewModel.nickname,
            detailText: viewModel.dispatchSummary?.coverageText ?? "派单状态待同步",
            statusText: viewModel.statusText,
            statusColor: viewModel.statusColor,
            isUpdatingAvailability: viewModel.isUpdatingAvailability,
            isApproved: appState.isVolunteerProfileApproved,
            isAvailable: Binding(
                get: { viewModel.isAvailable },
                set: { viewModel.setAvailability($0) }
            ),
            locationText: locationSummaryText,
            acceptBlockMessage: viewModel.acceptBlockMessage
        )
    }

    private var recenterButton: some View {
        Button {
            locationService.requestOneTimeLocation()
            recenterToken += 1
        } label: {
            Label("回到当前位置", systemImage: "location.fill")
                .font(AppFonts.body().weight(.semibold))
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .background(AppColors.background)
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.16), radius: 12, x: 0, y: 4)
        }
        .accessibilityLabel("回到当前位置")
        .accessibilityHint("将地图中心移动到当前定位，不提供路线导航")
    }

    /// 面板换档的动效。三处（点抓手 / 拖拽结束 / 高度变化）必须是同一条曲线，
    /// 否则同一个动作会有两种回弹。`nil` = 瞬时到位，这是「减弱动态效果」下的正解。
    private var demandPanelAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)
    }

    private func nearbyDemandPanel(height: CGFloat, isCompact: Bool, proxy: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            demandPanelGrabber
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(demandPanelAnimation) {
                        demandPanelDetent = demandPanelDetent.next()
                    }
                }
                .gesture(demandPanelDragGesture(proxy: proxy))

            nearbyOrdersHeader(showsSubtitle: !isCompact)
                .padding(.horizontal, 20)
                .padding(.bottom, isCompact ? 12 : 10)
                .contentShape(Rectangle())
                .gesture(demandPanelDragGesture(proxy: proxy))

            if !isCompact {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        nearbyDemandContent
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)
                }
                .accessibilityIdentifier("volunteerHomeDemandScrollView")
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(AppColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 20, x: 0, y: -8)
        .animation(demandPanelAnimation, value: demandPanelDetent)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("volunteerHomeDemandPanel")
    }

    private var demandPanelGrabber: some View {
        RoundedRectangle(cornerRadius: 999)
            .fill(AppColors.textSecondary.opacity(0.28))
            .frame(width: 46, height: 5)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .accessibilityLabel("派单面板高度，当前\(demandPanelDetent.accessibilityValue)")
            // 原文案是「上滑展开，下滑收起」—— 那是给**手指**说的。开着 VoiceOver 或
            // Switch Control 时，上滑下滑早被辅助技术接管，照做没有任何反应，
            // 而这块面板是志愿者接单的唯一入口。换成这两条通道真正能执行的动作。
            .accessibilityHint("双击切换到下一档；用调整手势逐档展开或收起")
            .accessibilityAdjustableAction { direction in
                withAnimation(demandPanelAnimation) {
                    switch direction {
                    case .increment:
                        demandPanelDetent = demandPanelDetent.adjusted(by: 1)
                    case .decrement:
                        demandPanelDetent = demandPanelDetent.adjusted(by: -1)
                    @unknown default:
                        break
                    }
                }
            }
            .accessibilityIdentifier("volunteerHomeDemandPanelGrabber")
    }

    private func nearbyOrdersHeader(showsSubtitle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("系统派单")
                    // 写死 pt 的字号不跟 Dynamic Type 走：把系统字号调到 AX5 之后，
                    // 整屏都变大而这个标题纹丝不动 —— 它是这一屏的入口标题，不该是唯一不变的那个。
                    // `@ScaledMetric` 保住原来的视觉尺寸，同时跟着用户设置缩放。
                    .font(.system(size: showsSubtitle ? nearbyHeaderLargeSize : nearbyHeaderCompactSize, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()

                Button {
                    Task { await loadHome() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("刷新派单状态")
                .accessibilityHint("重新加载系统派单工作台")
                .accessibilityIdentifier("volunteerHomeRefreshButton")
            }

            if showsSubtitle {
                Text(viewModel.dispatchSummary?.dispatchStatusText ?? (locationService.isAuthorized ? "正在同步派单状态。" : "定位未开启，系统派单不可用。"))
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var nearbyDemandContent: some View {
        if let summary = viewModel.dispatchSummary {
            if viewModel.isLoading {
                Label(
                    "正在后台刷新派单状态，当前内容仍可使用",
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
                .accessibilityLabel("正在后台刷新派单状态，当前内容仍可使用")
            }
            VolunteerDispatchSummaryCard(summary: summary)

            // 「尚未通过资质认证」必须能一键到达上传页，否则志愿者看到提示也无处可去。
            if summary.notAvailableReasons?.contains(.notVerified) == true {
                VolunteerCertificateUploadEntryLink(
                    title: "上传资质证书",
                    subtitle: "资质审核通过后才能接单"
                )
            }

            if let activeOrder = viewModel.activeOrder {
                NavigationLink {
                    currentOrderDestination(activeOrder)
                } label: {
                    VolunteerCurrentOrderCard(order: activeOrder)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("当前订单：\(activeOrder.status.displayName)，盲人 \(activeOrder.blindName ?? "")，地点 \(activeOrder.startAddress ?? "")")
                .accessibilityHint("点击进入当前订单")
            }

            VolunteerRecentOrdersSection(orders: summary.recentOrders ?? [])
        } else if viewModel.isLoading {
            VStack(alignment: .leading, spacing: 10) {
                EmptyStateView(
                    title: "派单状态待同步",
                    message: "正在后台同步；记录、积分、设置和面板操作仍可使用。"
                )
                Label("正在后台同步派单状态", systemImage: "arrow.triangle.2.circlepath")
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityLabel("正在后台同步派单状态，页面仍可使用")
            }
        } else {
            EmptyStateView(
                title: "派单状态待同步",
                message: locationService.isAuthorized ? "请稍后刷新。" : "开启定位后才能接收系统派单。"
            )
        }

        if let errorMessage = viewModel.displayedErrorMessage {
            VStack(alignment: .leading, spacing: 8) {
                Text(errorMessage)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.destructive)
                    .accessibilityLabel(errorMessage)
                Button("重试加载") {
                    Task { await loadHome() }
                }
                .buttonStyle(.bordered)
                .accessibilityHint("重新加载派单和当前订单状态")
            }
        }

        // 接单被后端 403 VOLUNTEER_NOT_VERIFIED 拒绝时，直接给出上传入口。
        if viewModel.needsCertificateUpload {
            VolunteerCertificateUploadEntryLink(
                title: "去上传资质证书",
                subtitle: "资质审核通过后才能接单"
            )
        }

        if let warning = viewModel.locationDispatchWarning {
            Label(warning, systemImage: "location.slash.fill")
                .font(AppFonts.body())
                .foregroundColor(AppColors.warning)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(warning)
                .accessibilityHint("请检查定位权限，并等待设备获取当前位置")
                .accessibilityIdentifier("volunteerDispatchLocationWarning")
        }

        #if DEBUG
        if let diagnostic = appState.realtimeCoordinator.dispatchDiagnostic {
            Text("派单诊断：\(diagnostic.debugSummary)")
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
                .textSelection(.enabled)
                .accessibilityLabel("派单诊断，\(diagnostic.debugSummary)")
                .accessibilityIdentifier("volunteerDispatchDiagnostic")
        }
        DebugTestingPanel()
            .environmentObject(appState)
        #endif
    }

    private func currentOrderDestination(_ order: OrderDetailResponse) -> some View {
        VolunteerInServiceView(orderId: order.orderId, initialOrder: order)
    }

    private func demandPanelDragGesture(proxy: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                demandPanelDragTranslation = value.translation.height
            }
            .onEnded { value in
                let resolvedTopBottom = resolvedTopContentBottom(in: proxy)
                let baseHeight = demandPanelDetent.height(
                    viewportHeight: proxy.size.height,
                    topContentBottom: resolvedTopBottom
                )
                let proposedHeight = VolunteerDemandPanelDetent.clampedHeight(
                    baseHeight - value.translation.height,
                    viewportHeight: proxy.size.height,
                    topContentBottom: resolvedTopBottom
                )
                let target = VolunteerDemandPanelDetent.nearest(
                    to: proposedHeight,
                    viewportHeight: proxy.size.height,
                    topContentBottom: resolvedTopBottom
                )
                withAnimation(demandPanelAnimation) {
                    demandPanelDetent = target
                    demandPanelDragTranslation = 0
                }
            }
    }

    private func demandPanelHeight(in proxy: GeometryProxy, topContentBottom: CGFloat) -> CGFloat {
        let baseHeight = demandPanelDetent.height(
            viewportHeight: proxy.size.height,
            topContentBottom: topContentBottom
        )
        return VolunteerDemandPanelDetent.clampedHeight(
            baseHeight - demandPanelDragTranslation,
            viewportHeight: proxy.size.height,
            topContentBottom: topContentBottom
        )
    }

    private func resolvedTopContentBottom(in proxy: GeometryProxy) -> CGFloat {
        VolunteerHomeTopLayout.reservedBottom(
            safeAreaTop: proxy.safeAreaInsets.top,
            hasActiveOrder: viewModel.activeOrder != nil,
            viewportHeight: proxy.size.height
        )
    }

    private var locationSummaryText: String {
        if locationService.isAuthorized {
            return "\(locationService.readableCurrentLocationSummary)\(viewModel.dispatchSummary?.coverageText ?? "派单覆盖范围待同步")"
        }
        return "需要开启定位权限才能接收系统派单"
    }

    private func loadHome() async {
        await viewModel.load(
            currentLocation: locationService.currentLocation,
            locationAuthorized: locationService.isAuthorized
        )
    }

    private var bottomEntries: some View {
        HStack(spacing: 10) {
            NavigationLink {
                VolunteerServiceRecordsView()
            } label: {
                VolunteerEntryItem(icon: "clock.arrow.circlepath", title: "记录")
            }
            .accessibilityLabel("我的服务记录")

            NavigationLink {
                VolunteerServiceRecognitionView()
            } label: {
                VolunteerEntryItem(icon: "rosette", title: "成就")
            }
            .accessibilityLabel("服务成就")
            .accessibilityHint("查看已完成的服务次数、评分和称号")

            NavigationLink {
                VolunteerSettingsView()
            } label: {
                VolunteerEntryItem(icon: "gearshape", title: "设置")
            }
            .accessibilityLabel("设置")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
}

private struct VolunteerHomeStatusOverlay: View {
    let nickname: String
    let detailText: String
    let statusText: String
    let statusColor: Color
    let isUpdatingAvailability: Bool
    let isApproved: Bool
    @Binding var isAvailable: Bool
    let locationText: String
    let acceptBlockMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Text(nickname)
                    .font(.headline.weight(.bold))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                HStack(spacing: 8) {
                    if isUpdatingAvailability {
                        ProgressView()
                            .accessibilityLabel("正在更新可服务状态")
                    }

                    Toggle(
                        isOn: $isAvailable
                    ) {
                        Text("可服务开关")
                    }
                    .labelsHidden()
                    .disabled(!isApproved || isUpdatingAvailability)
                    .accessibilityLabel("可服务开关，\(statusText)")
                    .accessibilityHint("关闭后不会收到新的系统派单，但不影响当前订单")
                }
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text(statusText)
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(statusColor)
                Text("·")
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityHidden(true)
                Text(detailText)
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(AppColors.textPrimary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("当前状态：\(statusText)，\(detailText)")

            Text(locationText)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(locationText)

            if let acceptBlockMessage {
                Text(acceptBlockMessage)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(acceptBlockMessage)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.14), radius: 14, x: 0, y: 5)
        .accessibilityIdentifier("volunteerHomeTopStatusBlock")
    }
}

private struct VolunteerCurrentOrderCard: View {
    let order: OrderDetailResponse

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: order.status.statusSymbolName)
                .font(.title3)
                .foregroundColor(order.status.statusColor)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("当前订单")
                        .font(AppFonts.caption().weight(.semibold))
                        .foregroundColor(AppColors.textSecondary)
                    Text(order.status.displayName)
                        .font(AppFonts.caption().weight(.semibold))
                        .foregroundColor(order.status.statusColor)
                }

                Text(order.blindName ?? "盲人跑者")
                    .font(AppFonts.body().weight(.bold))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(order.startAddress ?? "")
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text((order.plannedStart ?? "").displayDateTime)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Label("进入", systemImage: "chevron.right")
                    .labelStyle(.titleAndIcon)
                    .font(AppFonts.caption().weight(.semibold))
                    .foregroundColor(AppColors.primary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColors.background.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 5)
    }
}

private struct VolunteerDispatchSummaryCard: View {
    let summary: VolunteerDispatchSummaryResponse

    /// 三格，不是四格。此前第一格是「积分」，值是 `totalCompleted * 100` ——
    /// 后端从来没有 `pointsBalance` 字段，那个数字只是「完成 N 单」换了个说法，
    /// 却被命名成一种可累积、可兑换的东西。
    ///
    /// ponytail: 删掉后**不补第四格凑数**。`totalDispatched` / `totalDeclined` /
    /// `totalTimeout` 在下面本来就有一行专门展示，挪上来只是重复。
    private var metrics: [(String, String)] {
        [
            ("完成", "\(summary.completedCount)"),
            ("评分", summary.ratingText),
            ("接单率", summary.acceptanceRateText)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: summary.canDispatch == true ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(summary.canDispatch == true ? AppColors.success : AppColors.warning)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.dispatchStatusText)
                        .font(AppFonts.body().weight(.bold))
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(summary.coverageText)
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.textSecondary)
                }

                Spacer(minLength: 0)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(metrics, id: \.0) { metric in
                    VolunteerMetricTile(title: metric.0, value: metric.1)
                }
            }

            HStack(spacing: 8) {
                Text("派单 \(summary.totalDispatched ?? 0)")
                Text("接受 \(summary.totalAccepted ?? 0)")
                Text("拒绝 \(summary.totalDeclined ?? 0)")
                Text("超时 \(summary.totalTimeout ?? 0)")
            }
            .font(AppFonts.caption())
            .foregroundColor(AppColors.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        }
        .padding(14)
        .background(AppColors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        // 「积分 N」也从这条 label 里删掉 —— 数字从视觉上消失了，但读屏用户还在听，
        // 这一处最容易漏。
        .accessibilityLabel("派单状态：\(summary.dispatchStatusText)，\(summary.coverageText)，完成 \(summary.completedCount) 次，评分 \(summary.ratingText)")
    }
}

private struct VolunteerMetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(AppColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct VolunteerRecentOrdersSection: View {
    let orders: [VolunteerDispatchSummaryRecentOrder]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("近期服务")
                .font(AppFonts.body().weight(.bold))
                .foregroundColor(AppColors.textPrimary)

            if orders.isEmpty {
                EmptyStateView(title: "暂无服务记录", message: "完成服务后会显示在这里。")
            } else {
                VStack(spacing: 10) {
                    ForEach(orders.prefix(3)) { order in
                        NavigationLink {
                            VolunteerOrderDetailView(orderId: order.orderId)
                        } label: {
                            VolunteerRecentOrderCard(order: order)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("点击查看订单详情")
                    }
                }
            }
        }
    }
}

private struct VolunteerRecentOrderCard: View {
    let order: VolunteerDispatchSummaryRecentOrder

    /// 抽成独立属性而不是在 `.accessibilityLabel(...)` 里现拼：
    /// 把这段带可选拆包的拼接塞回 `body` 会让 Swift 类型检查器超时
    /// （`unable to type-check this expression in reasonable time`）。
    ///
    /// `pointsText` 现在是 `String?`，只在后端真的发了 `pointsDelta` 时才有值 ——
    /// 没有就整段不念，而不是念一个编出来的「+100」。
    private var accessibilityDescription: String {
        var parts = [
            "盲人：\(order.blindName ?? "")",
            "地点：\(order.startAddress ?? "")",
            "状态：\(order.status.displayName)"
        ]
        if let points = order.pointsText {
            parts.append("积分：\(points)")
        }
        return parts.joined(separator: "，")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: order.status.statusSymbolName)
                .font(.body.weight(.semibold))
                .foregroundColor(order.status.statusColor)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(order.blindName ?? "盲人跑者")
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)

                Text(order.startAddress ?? "地点待同步")
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(order.status.displayName)
                    .font(AppFonts.caption().weight(.semibold))
                    .foregroundColor(order.status.statusColor)

                // 只在后端真的发了 `pointsDelta` 时才显示这一行。此前它恒显示 `+100`
                // （`resolvedPointsDelta` 在 nil 时返回 100），而后端从来没有这个字段。
                if let points = order.pointsText {
                    Text(points)
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.success)
                }
            }
        }
        .padding(12)
        .background(AppColors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }
}

private struct VolunteerEntryItem: View {
    let icon: String
    let title: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
            Text(title)
                .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .foregroundColor(AppColors.primary)
    }
}

// MARK: - Dispatch Overlay

private struct VolunteerDispatchOverlay: View {
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 48
    /// 倒计时转入「紧迫」的阈值。具名是因为它同时决定颜色和那个感叹号 ——
    /// 两处各写一个 10，改一处漏一处的表现是「图标出现了但字还是蓝的」。
    private static let urgentCountdownSeconds = 10

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let order: WSNewOrder
    let countdown: Int
    let isResponding: Bool
    let currentLocation: CLLocationCoordinate2D?
    let locationAuthorized: Bool
    let fallbackCoordinate: CLLocationCoordinate2D
    let onInterested: () -> Void
    let onDecline: () -> Void

    var body: some View {
        ZStack {
            // 半透明遮罩在「降低透明度」开启时换成不透明：那个开关的用户正是被
            // 底层内容透上来的杂色干扰的人，而这一层底下是地图（高对比度的彩色纹理）。
            Color.black.opacity(reduceTransparency ? 1 : 0.5)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(spacing: 20) {
                Text("新订单派单")
                    .font(.title2.bold())
                    .foregroundColor(AppColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                dispatchMap

                VStack(alignment: .leading, spacing: 10) {
                    if let address = order.startAddress {
                        HStack {
                            Text("出发地：")
                                .foregroundColor(AppColors.textSecondary)
                            Text(address)
                                .foregroundColor(AppColors.textPrimary)
                        }
                        .font(AppFonts.body())
                    }

                    if let distance = order.distanceKm {
                        HStack {
                            Text("距离：")
                                .foregroundColor(AppColors.textSecondary)
                            Text(String(format: "%.1fkm", distance))
                                .foregroundColor(AppColors.textPrimary)
                        }
                        .font(AppFonts.body())
                    }

                    if let plannedStart = order.plannedStart {
                        HStack {
                            Text("时间：")
                                .foregroundColor(AppColors.textSecondary)
                            Text(plannedStart.displayDateTime)
                                .foregroundColor(AppColors.textPrimary)
                        }
                        .font(AppFonts.body())
                    }

                    if let priority = order.priority {
                        HStack {
                            Text("优先级：")
                                .foregroundColor(AppColors.textSecondary)
                            Text(priority)
                                .foregroundColor(AppColors.textPrimary)
                        }
                        .font(AppFonts.body())
                    }

                    if let pace = order.pacePreference {
                        HStack {
                            Text("配速：")
                                .foregroundColor(AppColors.textSecondary)
                            Text(PacePreference(rawValue: pace)?.displayName ?? pace)
                                .foregroundColor(AppColors.textPrimary)
                        }
                        .font(AppFonts.body())
                    }

                    if order.hasGuideDog == true {
                        HStack {
                            Text("导盲犬：")
                                .foregroundColor(AppColors.textSecondary)
                            Text("本次携带")
                                .foregroundColor(AppColors.textPrimary)
                        }
                        .font(AppFonts.body())
                    }

                    // 这里**不展示**盲人的自由文本备注：这是接单前（下面就是倒计时和接单/拒绝按钮），
                    // 而 AGENTS.md §8 要求接单前隐藏敏感健康信息。字段已从 `WSNewOrder` 整个删掉，
                    // 所以这不是一条靠人遵守的约定 —— 见 WebSocketModels.swift 上那段说明。
                    // 接单后的完整备注在 `VolunteerServiceOrderEssentials`。
                }

                // Countdown
                //
                // 进入最后 10 秒此前**只有颜色变化**（蓝 → 红）。红绿色觉障碍看不出这个转折，
                // 而这个转折决定的是「还要不要再想想」——超时算拒单，代价落回正在等的盲人身上。
                // 开启「不使用颜色区分」时补一个感叹号：形状差异不依赖色觉。
                HStack(spacing: 6) {
                    if differentiateWithoutColor && countdown <= Self.urgentCountdownSeconds {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 32, weight: .bold))
                            .accessibilityHidden(true)
                    }
                    Text("\(countdown)s")
                        // 同上：倒计时是这张卡上最要紧的数字，调大系统字号时它必须跟着变。
                        .font(.system(size: countdownSize, weight: .bold, design: .rounded))
                }
                .foregroundColor(countdown <= Self.urgentCountdownSeconds ? AppColors.destructive : AppColors.primary)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("剩余\(countdown)秒")

                // Action buttons
                HStack(spacing: 16) {
                    Button(action: onDecline) {
                        Text("拒绝")
                            .font(AppFonts.body().weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(AppColors.destructive.opacity(0.12))
                            .foregroundColor(AppColors.destructive)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isResponding)
                    .accessibilityLabel("拒绝订单")
                    .accessibilityHint("拒绝此次派单")

                    Button(action: onInterested) {
                        Text("有意向，想先聊聊")
                            .font(AppFonts.body().weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(AppColors.primary)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isResponding)
                    .accessibilityLabel("有意向，想先聊聊")
                    // 说清「还不是接单」：把 INTERESTED 当成接单的人会以为事情定了，
                    // 然后错过跑者那通电话 —— 而 20 分钟窗口过了这一单就换人了。
                    .accessibilityHint("先锁定这一单并等跑者打电话给你，聊完双方都说合适才算接单")
                    .accessibilityIdentifier("volunteerDispatchInterestedButton")
                }

                if isResponding {
                    ProgressView("正在响应...")
                        .accessibilityLabel("正在提交响应")
                }
            }
            .padding(24)
            .background(AppColors.background)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 24)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("新订单派单通知，剩余\(countdown)秒")
    }

    private var dispatchMap: some View {
        let presentation = VolunteerServiceMapPresentation(
            dispatchOrder: order,
            currentLocation: currentLocation,
            locationAuthorized: locationAuthorized,
            fallbackCoordinate: fallbackCoordinate
        )
        return MapViewWrapper(
            centerCoordinate: presentation.centerCoordinate,
            showsUserLocation: locationAuthorized,
            annotations: presentation.annotations,
            zoomLevel: 15,
            showsCompass: false,
            tracksUserLocation: false,
            animatesCenterChanges: false
        )
        .frame(height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .topLeading) {
            VolunteerMapLegend(
                showsCurrentLocation: presentation.isCurrentLocationAvailable,
                showsMissingLocationNotice: !presentation.isCurrentLocationAvailable
            )
            .padding(8)
        }
        .accessibilityLabel(
            presentation.isCurrentLocationAvailable
                ? "派单地图，显示我的位置和出发地点"
                : "派单地图，红色标记显示出发地点"
        )
        .accessibilityHint("地图用于确认接单距离和出发地点")
    }
}

#if DEBUG
#Preview {
    VolunteerHomeView()
        .environmentObject(AppState())
        .environmentObject(SpeechService())
        .environmentObject(LocationService())
}
#endif
