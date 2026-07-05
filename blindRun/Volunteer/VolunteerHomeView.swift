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
    @Published var isLoading = false
    @Published var isUpdatingAvailability = false
    @Published var activeOrder: OrderDetailResponse?

    // WebSocket dispatch state
    @Published var incomingOrder: WSNewOrder?
    @Published var dispatchCountdown: Int = 0
    @Published var isRespondingToDispatch = false
    @Published var acceptedDispatchOrderId: Int64?
    @Published var acceptedDispatchInitialOrder: OrderDetailResponse?

    private weak var appState: AppState?
    private var speechService: SpeechService?
    private var appStateWebSocketCancellable: AnyCancellable?
    private var webSocketEventCancellable: AnyCancellable?
    private weak var subscribedWebSocketService: WebSocketService?
    private var countdownTask: Task<Void, Never>?

    var statusText: String {
        dispatchSummary?.dispatchStatusText ?? (isAvailable ? "等待系统派单" : "已关闭接单")
    }

    var statusColor: Color {
        if dispatchSummary?.canDispatch == true {
            return AppColors.success
        }
        return isAvailable ? AppColors.warning : AppColors.textSecondary
    }

    var acceptBlockMessage: String? {
        VolunteerOrderActionGuard.acceptBlockMessage(profile: appState?.volunteerProfile)
    }

    static func activeVolunteerOrder(from orders: [OrderDetailResponse]) -> OrderDetailResponse? {
        orders
            .filter { $0.status.isActiveForVolunteer }
            .sorted { $0.sortKey > $1.sortKey }
            .first
    }

    func configure(with appState: AppState, speechService: SpeechService) {
        self.appState = appState
        self.speechService = speechService
        apply(profile: appState.volunteerProfile)
        subscribeToAppStateWebSocket(appState)
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
                acceptedDispatchInitialOrder = acceptedOrder
                acceptedDispatchOrderId = acceptedOrderId
                speechService?.speak(accept ? "已接受订单" : "已拒绝订单")
            } catch let error as APIError {
                isRespondingToDispatch = false
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

    private func subscribeToAppStateWebSocket(_ appState: AppState) {
        subscribeToWebSocketService(appState.webSocketService)

        guard appStateWebSocketCancellable == nil else { return }
        appStateWebSocketCancellable = appState.$webSocketService
            .sink { [weak self] service in
                self?.subscribeToWebSocketService(service)
            }
    }

    private func subscribeToWebSocketService(_ service: WebSocketService?) {
        guard let service else {
            webSocketEventCancellable?.cancel()
            webSocketEventCancellable = nil
            subscribedWebSocketService = nil
            return
        }

        guard subscribedWebSocketService !== service else { return }

        webSocketEventCancellable?.cancel()
        subscribedWebSocketService = service
        webSocketEventCancellable = service.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleWebSocketEvent(event)
            }
    }

    private func handleWebSocketEvent(_ event: WSIncomingEvent) {
        switch event {
        case .newOrder(let order):
            handleNewOrder(order)
        default:
            break
        }
    }

    private func handleNewOrder(_ order: WSNewOrder) {
        // 如果已经有一个正在展示的 dispatch，忽略新的
        guard incomingOrder == nil else { return }

        incomingOrder = order
        dispatchCountdown = order.dispatchTimeoutSeconds ?? 30
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
        isLoading = dispatchSummary == nil
        errorMessage = nil

        do {
            // Load volunteer profile
            let profile: VolunteerProfileResponse = try await appState.apiClient.get("/api/volunteer/profile")
            appState.updateVolunteerProfile(profile)
            apply(profile: profile)

            VolunteerLocationReporter.reportIfNeeded(
                appState: appState,
                currentLocation: currentLocation,
                locationAuthorized: locationAuthorized
            )

            let summary: VolunteerDispatchSummaryResponse = try await appState.apiClient.get("/api/volunteer/dispatch-summary")
            apply(summary: summary)
            rows = []
            isLoading = false
        } catch let error as APIError {
            isLoading = false
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isLoading = false
            errorMessage = "订单加载失败，请重试"
            speechService?.speakError("订单加载失败，请重试")
        }
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
                isAvailable: value,
                wantsDispatch: value,
                availableTimeSlots: existingProfile?.availableTimeSlots,
                acceptsGuideDog: existingProfile?.acceptsGuideDog,
                paceRange: existingProfile?.paceRange
            )
            appState.updateVolunteerProfile(profile)
            apply(profile: profile)
            if let summary: VolunteerDispatchSummaryResponse = try? await appState.apiClient.get("/api/volunteer/dispatch-summary") {
                apply(summary: summary)
            }
            isUpdatingAvailability = false
        } catch let error as APIError {
            isAvailable = previousValue
            isUpdatingAvailability = false
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

    private func apply(summary: VolunteerDispatchSummaryResponse) {
        dispatchSummary = summary
        isAvailable = summary.wantsDispatch ?? isAvailable
        if let active = summary.activeOrders?.first {
            activeOrder = active.orderDetail
        } else {
            activeOrder = nil
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
        min(max(viewportHeight * 0.12, 104), 136)
    }

    static func clampedHeight(
        _ height: CGFloat,
        viewportHeight: CGFloat,
        topContentBottom: CGFloat
    ) -> CGFloat {
        let minimum = compact.height(viewportHeight: viewportHeight, topContentBottom: topContentBottom)
        let maximum = expanded.height(viewportHeight: viewportHeight, topContentBottom: topContentBottom)
        return min(max(height, minimum), maximum)
    }

    static func nearest(
        to height: CGFloat,
        viewportHeight: CGFloat,
        topContentBottom: CGFloat
    ) -> VolunteerDemandPanelDetent {
        allCases.min { lhs, rhs in
            abs(lhs.height(viewportHeight: viewportHeight, topContentBottom: topContentBottom) - height) <
                abs(rhs.height(viewportHeight: viewportHeight, topContentBottom: topContentBottom) - height)
        } ?? .medium
    }
}

struct VolunteerHomeMapLayout {
    static func screenAnchorY(
        viewportHeight: CGFloat,
        topContentBottom: CGFloat,
        demandPanelTop: CGFloat
    ) -> CGFloat {
        guard viewportHeight > 1 else { return 0.5 }
        let upper = max(topContentBottom, 0)
        let lower = max(demandPanelTop, upper + 1)
        let visibleCenterY = (upper + lower) / 2
        return min(max(visibleCenterY / viewportHeight, 0.18), 0.82)
    }
}

private struct VolunteerHomeTopBottomPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Volunteer Home View

struct VolunteerHomeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @EnvironmentObject private var locationService: LocationService
    @StateObject private var viewModel = VolunteerHomeViewModel()
    @State private var recenterToken = 0
    @State private var demandPanelDetent: VolunteerDemandPanelDetent = .medium
    @State private var demandPanelDragTranslation: CGFloat = 0
    @State private var topContentBottom: CGFloat = 0

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
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, max(proxy.safeAreaInsets.top + 4, 8))
                    .frame(maxWidth: .infinity, alignment: .top)
                    .background(
                        GeometryReader { topProxy in
                            Color.clear.preference(
                                key: VolunteerHomeTopBottomPreferenceKey.self,
                                value: topProxy.frame(in: .named("VolunteerHome")).maxY
                            )
                        }
                    )
                    .frame(maxHeight: .infinity, alignment: .top)

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
                .background(AppColors.background)
                .coordinateSpace(name: "VolunteerHome")
                .onPreferenceChange(VolunteerHomeTopBottomPreferenceKey.self) { topContentBottom = $0 }
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
                viewModel.configure(with: appState, speechService: speechService)
                locationService.requestPermission()
                locationService.startUpdating()
                Task { await loadHome() }
            }
            .overlay {
                if viewModel.incomingOrder != nil {
                    VolunteerDispatchOverlay(
                        order: viewModel.incomingOrder!,
                        countdown: viewModel.dispatchCountdown,
                        isResponding: viewModel.isRespondingToDispatch,
                        currentLocation: locationService.currentLocation,
                        locationAuthorized: locationService.isAuthorized,
                        fallbackCoordinate: locationService.effectiveLocation,
                        onAccept: {
                            viewModel.respondToDispatch(
                                accept: true,
                                currentLocation: locationService.effectiveLocation,
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
            centerCoordinate: locationService.effectiveLocation,
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
        .accessibilityLabel("地图，显示当前位置和系统派单覆盖范围")
        .accessibilityHint("地图用于查看当前位置覆盖范围，不提供路线导航或实时轨迹")
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
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(AppColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 20, x: 0, y: -8)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: demandPanelDetent)
        .accessibilityElement(children: .contain)
    }

    private var demandPanelGrabber: some View {
        RoundedRectangle(cornerRadius: 999)
            .fill(AppColors.textSecondary.opacity(0.28))
            .frame(width: 46, height: 5)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .accessibilityLabel("拖动派单状态面板")
            .accessibilityHint("上滑展开，下滑收起")
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
        if viewModel.isLoading {
            ProgressView("正在加载派单状态...")
                .accessibilityLabel("正在加载派单状态")
        } else if let summary = viewModel.dispatchSummary {
            VolunteerDispatchSummaryCard(summary: summary)

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
        } else {
            EmptyStateView(
                title: "派单状态待同步",
                message: locationService.isAuthorized ? "请稍后刷新。" : "开启定位后才能接收系统派单。"
            )
        }

        if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .font(AppFonts.body())
                .foregroundColor(AppColors.destructive)
                .accessibilityLabel(errorMessage)
        }

        #if DEBUG
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
        max(topContentBottom, proxy.safeAreaInsets.top + 96)
    }

    private var locationSummaryText: String {
        if locationService.isAuthorized {
            return viewModel.dispatchSummary?.coverageText ?? "当前位置已同步"
        }
        return "需要开启定位权限才能接收系统派单"
    }

    private func loadHome() async {
        await viewModel.load(
            currentLocation: locationService.effectiveLocation,
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
                .lineLimit(1)
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
