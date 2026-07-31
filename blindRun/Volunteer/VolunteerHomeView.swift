import Combine
import CoreLocation
import SwiftUI

// MARK: - Volunteer Home ViewModel

@MainActor
final class VolunteerHomeViewModel: ObservableObject {
    @Published var isAvailable = false
    @Published var nickname = ""
    @Published var rows: [VolunteerAvailableOrderRow] = []
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

    private weak var appState: AppState?
    private var speechService: SpeechService?
    private var realtimeDispatchCancellable: AnyCancellable?
    private var realtimeRecoveryCancellable: AnyCancellable?
    private var realtimeStatusCancellable: AnyCancellable?
    private var countdownTask: Task<Void, Never>?
    private var delayedSummaryRefreshTask: Task<Void, Never>?
    private var isSceneActive = false
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

    func respondToDispatch(
        accept: Bool,
        currentLocation: CLLocationCoordinate2D?,
        locationAuthorized: Bool
    ) {
        guard let order = incomingOrder else { return }
        guard let appState else { return }
        if accept,
             let message = VolunteerOrderActionGuard.acceptBlockMessage(
                 profile: appState.volunteerProfile,
                 registrationStatus: appState.volunteerRegistrationStatus,
                 locationAuthorized: locationAuthorized
             ) {
            errorMessage = message
            speechService?.speakError(message)
            return
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
                let request = OrderRespondRequest(action: accept ? .accept : .decline)
                let _: EmptyResponse = try await appState.apiClient.post(
                    "/api/orders/\(order.orderId)/respond",
                    body: request
                )
                let acceptedOrderId = accept ? order.orderId : nil
                let acceptedOrder = await refreshAfterDispatchResponse(
                    acceptedOrderId: acceptedOrderId,
                    appState: appState
                )
                dismissDispatch()
                appState.realtimeCoordinator.clearDispatch(orderID: order.orderId)
                acceptedDispatchInitialOrder = acceptedOrder
                acceptedDispatchOrderId = acceptedOrderId
                speechService?.speak(accept ? "已接受订单" : "已拒绝订单")
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

    func dismissDispatch() {
        countdownTask?.cancel()
        countdownTask = nil
        incomingOrder = nil
        dispatchCountdown = 0
        isRespondingToDispatch = false
    }

    private func refreshAfterDispatchResponse(
        acceptedOrderId: Int64?,
        appState: AppState
    ) async -> OrderDetailResponse? {
        var acceptedOrder: OrderDetailResponse?

        if let acceptedOrderId {
            acceptedOrder = try? await appState.apiClient.get("/api/orders/\(acceptedOrderId)")
            activeOrder = acceptedOrder
        }

        if let summary: VolunteerDispatchSummaryResponse = try? await appState.apiClient.get("/api/volunteer/dispatch-summary") {
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
                respondToDispatch(accept: false, currentLocation: nil, locationAuthorized: false)
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
            let apiClient = appState.apiClient
            let summary: VolunteerDispatchSummaryResponse = try await HomeLoadCoordinator.run(
                timeout: loadTimeout,
                operationName: "volunteer-dispatch-initial"
            ) {
                try await apiClient.get("/api/volunteer/dispatch-summary")
            }
            guard activeRequestID == requestID, !Task.isCancelled else { return }
            apply(summary: summary)
            rows = []
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
        let apiClient = appState.apiClient
        auxiliaryLoadTask = Task { [weak self, weak appState] in
            guard let self, let appState else { return }
            async let profileResult: Result<VolunteerProfileResponse, Error> = Self.fetchResult {
                try await HomeLoadCoordinator.run(
                    timeout: self.loadTimeout,
                    operationName: "volunteer-profile"
                ) {
                    try await apiClient.get("/api/volunteer/profile")
                }
            }
            async let registrationResult: Result<VolunteerRegistrationStatus, Error> = Self.fetchResult {
                try await HomeLoadCoordinator.run(
                    timeout: self.loadTimeout,
                    operationName: "volunteer-registration"
                ) {
                    try await apiClient.get("/api/volunteer/registration/status")
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
            let request = DispatchStatusRequest(wantsDispatch: value)
            let _: EmptyResponse = try await appState.apiClient.put(
                "/api/volunteer/dispatch-status",
                body: request
            )
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
            if let summary: VolunteerDispatchSummaryResponse = try? await appState.apiClient.get("/api/volunteer/dispatch-summary") {
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

    private func apply(
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
            let apiClient = appState.apiClient
            let statusRequestToken = activeOrder.map {
                appState.realtimeCoordinator.beginOrderStatusRequest(orderID: $0.orderId)
            }
            let summary: VolunteerDispatchSummaryResponse = try await HomeLoadCoordinator.run(
                timeout: loadTimeout,
                operationName: "volunteer-dispatch-refresh"
            ) {
                try await apiClient.get("/api/volunteer/dispatch-summary")
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
            locationDispatchWarning = nil
            return
        }
        if didReportLocation {
            locationDispatchWarning = nil
            return
        }
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
    static func reservedBottom(safeAreaTop: CGFloat, hasActiveOrder: Bool) -> CGFloat {
        let safeTop = safeAreaTop.isFinite ? max(safeAreaTop, 0) : 0
        // Keep the panel below the material status block without feeding a measured
        // child frame back into the same layout graph.
        return safeTop + (hasActiveOrder ? 300 : 180)
    }
}

// MARK: - Volunteer Home View

struct VolunteerHomeView: View {
    @Environment(\.scenePhase) private var scenePhase
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
            .navigationDestination(
                isPresented: Binding(
                    get: { viewModel.acceptedDispatchOrderId != nil },
                    set: { isPresented in
                        if !isPresented {
                            viewModel.acceptedDispatchOrderId = nil
                            viewModel.acceptedDispatchInitialOrder = nil
                        }
                    }
                )
            ) {
                if let orderId = viewModel.acceptedDispatchOrderId {
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
                        onAccept: {
                            viewModel.respondToDispatch(
                                accept: true,
                                currentLocation: locationService.currentLocation,
                                locationAuthorized: locationService.isAuthorized
                            )
                        },
                        onDecline: {
                            viewModel.respondToDispatch(
                                accept: false,
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
            annotations: viewModel.rows.compactMap(\.annotation),
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

    private func nearbyDemandPanel(height: CGFloat, isCompact: Bool, proxy: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            demandPanelGrabber
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
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
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: demandPanelDetent)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("volunteerHomeDemandPanel")
    }

    private var demandPanelGrabber: some View {
        RoundedRectangle(cornerRadius: 999)
            .fill(AppColors.textSecondary.opacity(0.28))
            .frame(width: 46, height: 5)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .accessibilityLabel("拖动派单状态面板")
            .accessibilityHint("上滑展开，下滑收起")
            .accessibilityIdentifier("volunteerHomeDemandPanelGrabber")
    }

    private func nearbyOrdersHeader(showsSubtitle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("系统派单")
                    .font(.system(size: showsSubtitle ? 30 : 24, weight: .bold))
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
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
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
            hasActiveOrder: viewModel.activeOrder != nil
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
                VolunteerPointsPlaceholderView()
            } label: {
                VolunteerEntryItem(icon: "gift", title: "积分")
            }
            .accessibilityLabel("积分商城")
            .accessibilityHint("查看积分和商城占位页")

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

    private var metrics: [(String, String)] {
        [
            ("积分", "\(summary.resolvedPointsBalance)"),
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
        .accessibilityLabel("派单状态：\(summary.dispatchStatusText)，\(summary.coverageText)，积分 \(summary.resolvedPointsBalance)，完成 \(summary.completedCount) 次，评分 \(summary.ratingText)")
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

                Text(order.pointsText)
                    .font(AppFonts.caption())
                    .foregroundColor(order.resolvedPointsDelta == nil ? AppColors.textSecondary : AppColors.success)
            }
        }
        .padding(12)
        .background(AppColors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("盲人：\(order.blindName ?? "")，地点：\(order.startAddress ?? "")，状态：\(order.status.displayName)，积分：\(order.pointsText)")
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
    let order: WSNewOrder
    let countdown: Int
    let isResponding: Bool
    let currentLocation: CLLocationCoordinate2D?
    let locationAuthorized: Bool
    let fallbackCoordinate: CLLocationCoordinate2D
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
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

                    if let notes = order.specialNotes, !notes.isEmpty {
                        Text(notes)
                            .font(AppFonts.caption())
                            .foregroundColor(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // Countdown
                Text("\(countdown)s")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(countdown <= 10 ? AppColors.destructive : AppColors.primary)
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

                    Button(action: onAccept) {
                        Text("接受")
                            .font(AppFonts.body().weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(AppColors.primary)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isResponding)
                    .accessibilityLabel("接受订单")
                    .accessibilityHint("接受此次派单并进入服务流程")
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
