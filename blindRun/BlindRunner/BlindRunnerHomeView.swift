import CoreLocation
import Combine
import SwiftUI

// MARK: - Blind Runner Route

private enum BlindRunnerRoute: Hashable {
    /// 预约页，进去就自动开语音向导。首页只有这一个下单入口 —— 原来的纯表单入口 `.booking`
    /// 已删除：它进的是同一个页面，留着只是让人在首页多做一次「点哪个」的判断。
    /// 表单没有消失，在预约页里按「改用表单」即可。
    case voiceBooking
    case orderStatus(Int64)
    case settings
}

// MARK: - Blind Runner Home ViewModel

@MainActor
final class BlindRunnerHomeViewModel: ObservableObject {
    @Published var activeOrder: OrderDetailResponse?
    @Published private(set) var orderLoadState: AsyncLoadState<OrderDetailResponse?> = .idle
    @Published private(set) var refreshPhase: HomeRefreshPhase = .idle
    @Published var isPerformingAction = false
    @Published var errorMessage: String?

    private weak var appState: AppState?
    private var speechService: SpeechService?
    private var activeLoadTask: Task<Void, Never>?
    private var activeRequestID: UUID?
    private var realtimeStatusCancellable: AnyCancellable?
    private let loadTimeout: TimeInterval

    init(loadTimeout: TimeInterval = HomeLoadPolicy.defaultTimeout) {
        self.loadTimeout = max(0.05, loadTimeout)
    }

    var isLoading: Bool { refreshPhase.isRefreshing }

    var currentStatusText: String {
        guard let activeOrder else {
            return "当前没有进行中的预约，可以开始一次新的陪跑预约。"
        }
        let startText = activeOrder.startAddress?.nilIfBlank ?? "出发地点待确认"
        let timeText = activeOrder.plannedStartForAnnouncement ?? "预约时间待确认"
        return "当前订单：\(activeOrder.status.displayName)。预约时间：\(timeText)。出发地点：\(startText)。"
    }

    var canCancelActiveOrder: Bool {
        activeOrder?.status.canBlindRunnerCancel == true
    }

    var canStartNewBooking: Bool {
        guard activeOrder == nil else { return false }
        if case .loaded = orderLoadState { return true }
        return false
    }

    func explainBookingUnavailable() {
        let message = "订单状态尚未确认，请先重试加载，避免创建重复预约。"
        errorMessage = message
        speechService?.speakError(message)
    }

    func configure(with appState: AppState, speechService: SpeechService) {
        self.appState = appState
        self.speechService = speechService
        if realtimeStatusCancellable == nil {
            realtimeStatusCancellable = appState.realtimeCoordinator.statusUpdatePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] update in
                    self?.applyRealtimeStatus(update)
                }
        }
    }

    private func applyRealtimeStatus(_ update: RealtimeOrderStatusUpdate) {
        guard let current = activeOrder, current.orderId == update.orderId else { return }
        let updated = current.replacingStatus(with: update.toStatus)
        speechService?.speakStatusChange(
            updated.status,
            text: updated.blindRunnerAnnouncement()
        )
        if updated.status.isActiveForBlindRunner {
            activeOrder = updated
            appState?.liveEscortCoordinator.updateOwnedOrder(
                orderID: updated.orderId,
                status: updated.status
            )
        } else {
            activeOrder = nil
            appState?.realtimeCoordinator.unregisterActiveOrder(updated.orderId)
            appState?.liveEscortCoordinator.clearOwnedOrder()
        }
        orderLoadState = .loaded(activeOrder)
        errorMessage = nil
    }

    func loadActiveOrder() async {
        guard let appState else { return }
        if let activeLoadTask {
            ClientFlowDiagnostics.record(event: "coalesced", operation: "blind-home-refresh")
            await activeLoadTask.value
            return
        }
        ClientFlowDiagnostics.record(event: "started", operation: "blind-home-refresh")
        let requestID = UUID()
        activeRequestID = requestID
        refreshPhase = .refreshing(requestID: requestID)
        if case .idle = orderLoadState {
            orderLoadState = .loading(requestID: requestID)
        }
        errorMessage = nil

        let workTask = Task { [weak self, weak appState] in
            guard let self, let appState else { return }
            await self.performActiveOrderLoad(appState: appState, requestID: requestID)
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
        ClientFlowDiagnostics.record(event: "finished", operation: "blind-home-refresh")
        if case .loading = orderLoadState {
            orderLoadState = .loaded(activeOrder)
        }
    }

    func cancelLoading() {
        activeLoadTask?.cancel()
        activeLoadTask = nil
        activeRequestID = nil
        refreshPhase = .idle
        if orderLoadState.isLoading { orderLoadState = .idle }
    }

    private func performActiveOrderLoad(appState: AppState, requestID: UUID) async {
        do {
            let apiClient = appState.apiClient
            let statusRequestToken = activeOrder.map {
                appState.realtimeCoordinator.beginOrderStatusRequest(orderID: $0.orderId)
            }
            let paged: PagedOrderResponse = try await HomeLoadCoordinator.run(
                timeout: loadTimeout,
                operationName: "blind-active-order"
            ) {
                try await apiClient.get("/api/orders/mine")
            }
            guard activeRequestID == requestID, !Task.isCancelled else { return }
            let previousOrderID = activeOrder?.orderId
            let candidate = paged.content
                .filter { $0.status.isActiveForBlindRunner }
                .sorted { $0.sortKey > $1.sortKey }
                .first
            if candidate == nil,
               let statusRequestToken,
               !appState.realtimeCoordinator.isOrderStatusRequestCurrent(statusRequestToken) {
                ClientFlowDiagnostics.record(
                    event: "late_empty_discarded",
                    operation: "blind-active-order"
                )
            } else if let candidate,
               let statusRequestToken,
               statusRequestToken.orderID == candidate.orderId {
                activeOrder = appState.realtimeCoordinator.reconcileOrderDetail(
                    candidate,
                    requestToken: statusRequestToken
                )
            } else {
                activeOrder = candidate
                if let candidate {
                    appState.realtimeCoordinator.registerActiveOrder(
                        candidate.orderId,
                        status: candidate.status
                    )
                }
            }
            if let previousOrderID, previousOrderID != activeOrder?.orderId {
                appState.realtimeCoordinator.unregisterActiveOrder(previousOrderID)
            }
            if let activeOrder {
                appState.liveEscortCoordinator.updateOwnedOrder(
                    orderID: activeOrder.orderId,
                    status: activeOrder.status
                )
            } else {
                appState.liveEscortCoordinator.clearOwnedOrder()
            }
            orderLoadState = .loaded(activeOrder)
            refreshPhase = .idle
            speakCurrentStatus()
        } catch HomeLoadCoordinatorError.timedOut {
            guard activeRequestID == requestID, !Task.isCancelled else { return }
            let message = "加载超过 20 秒，请重试。"
            errorMessage = message
            if activeOrder == nil {
                orderLoadState = .failed(message: message)
            }
            refreshPhase = .idle
            speechService?.speakError(message)
        } catch let error as APIError {
            guard activeRequestID == requestID, !Task.isCancelled else { return }
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            errorMessage = error.localizedMessage
            if activeOrder == nil {
                orderLoadState = .failed(message: error.localizedMessage)
            }
            refreshPhase = .idle
            speechService?.speakError(error.localizedMessage)
        } catch {
            guard activeRequestID == requestID, !Task.isCancelled else { return }
            errorMessage = "当前状态加载失败，请重试。"
            if activeOrder == nil {
                orderLoadState = .failed(message: "当前状态加载失败，请重试。")
            }
            refreshPhase = .idle
            speechService?.speakError("当前状态加载失败，请重试。")
        }
    }

    private func cancelRequestIfCurrent(_ requestID: UUID) {
        guard activeRequestID == requestID else { return }
        cancelLoading()
    }

    func handleOrderCreated(_ response: OrderResponse) {
        speechService?.resetLastStatus()
        if let status = response.status {
            speechService?.speakStatusChange(status)
        }
    }

    func speakCurrentStatus(locationDescription: String? = nil) {
        if let activeOrder {
            speechService?.speakStatusChange(
                activeOrder.status,
                text: homeAnnouncement(for: activeOrder, locationDescription: locationDescription)
            )
        } else {
            let locationText = locationDescription.map { "当前位置：\($0)。" } ?? ""
            speechService?.speak("欢迎来到助盲跑。\(locationText)可以点击开始约跑。")
        }
    }

    func repeatCurrentStatus(locationDescription: String) {
        if let activeOrder {
            speechService?.speak(homeAnnouncement(for: activeOrder, locationDescription: locationDescription))
        } else {
            speechService?.speak("当前没有进行中的预约。\(locationDescription)可以点击开始约跑。")
        }
    }

    private func homeAnnouncement(for order: OrderDetailResponse, locationDescription: String?) -> String {
        let timeText = order.plannedStartForAnnouncement.map { "预约时间：\($0)。" } ?? ""
        let locationText = locationDescription.map { "位置摘要：\($0)。" } ?? ""
        return "\(order.blindRunnerAnnouncement())\(timeText)出发地点：\(order.startAddressForAnnouncement)。\(locationText)"
    }

    func cancelActiveOrder() async {
        guard let activeOrder, let appState else { return }
        guard activeOrder.status.canBlindRunnerCancel else {
            let message = "当前订单状态不能由盲人取消。"
            errorMessage = message
            speechService?.speakError(message)
            return
        }
        isPerformingAction = true
        errorMessage = nil
        do {
            let _: EmptyResponse = try await appState.apiClient.post("/api/orders/\(activeOrder.orderId)/cancel")
            let updated: OrderDetailResponse = try await appState.apiClient.get("/api/orders/\(activeOrder.orderId)")
            self.activeOrder = updated.status.isActiveForBlindRunner ? updated : nil
            if self.activeOrder == nil {
                appState.realtimeCoordinator.unregisterActiveOrder(updated.orderId)
                appState.liveEscortCoordinator.clearOwnedOrder()
            }
            self.speechService?.speakStatusChange(updated.status, text: updated.blindRunnerAnnouncement())
            isPerformingAction = false
        } catch let error as APIError {
            isPerformingAction = false
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            errorMessage = error.localizedMessage
            speechService?.speakError(errorMessage ?? error.localizedMessage)
            if let updated: OrderDetailResponse = try? await appState.apiClient.get("/api/orders/\(activeOrder.orderId)") {
                self.activeOrder = updated.status.isActiveForBlindRunner ? updated : nil
            }
        } catch {
            isPerformingAction = false
            errorMessage = "取消失败。"
            speechService?.speakError(errorMessage ?? "取消失败。")
            if let updated: OrderDetailResponse = try? await appState.apiClient.get("/api/orders/\(activeOrder.orderId)") {
                self.activeOrder = updated.status.isActiveForBlindRunner ? updated : nil
            }
        }
    }

    /// 首页 SOS 条的云端分支。与 `BlindOrderStatusViewModel.enterEmergency()` 同一条链路
    /// （同一个 coordinator、同一个新鲜坐标闸门、同一套播报），只是入口不同。
    ///
    /// `locationService` 走参数而不是存成属性：这个 view model 的既有依赖都是 `weak`，
    /// 而定位服务由环境对象持有，存一份只会多一个可能为 nil 的引用。
    func enterEmergency(locationService: LocationService?) async {
        guard let activeOrder, let appState else { return }
        let outcome = await appState.emergencyCoordinator.trigger(
            order: activeOrder,
            role: appState.activeRole,
            userID: appState.userId,
            apiClient: appState.apiClient,
            locate: { await EmergencyCoordinator.freshEmergencyCoordinate(using: locationService) }
        )
        // 可见面是 SOS 条里的 `EmergencyStatusNotice`，这里只负责播报。
        // 刻意不再写 `errorMessage`：那会让同一句话在屏幕上出现两次、被读屏念两遍。
        if outcome.isFailure {
            speechService?.speakError(outcome.message)
        } else {
            speechService?.speak(outcome.message)
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

}

// MARK: - Blind Runner Home View

struct BlindRunnerHomeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @EnvironmentObject private var locationService: LocationService
    @StateObject private var viewModel = BlindRunnerHomeViewModel()
    @State private var path: [BlindRunnerRoute] = []
    @State private var showCancelConfirmation = false
    @State private var showEmergencyConfirmation = false
    @State private var showCallOptions = false

    /// 地图在视觉上占据的高度，`mapRevealHeight` 是内容层为它让出的部分 ——
    /// 两者相差的一段就是内容盖住地图下沿的量，做出「面板压在地图上」的层次。
    private static let mapVisualHeight: CGFloat = 300
    private static let mapRevealHeight: CGFloat = 236

    /// 「开始约跑」吃掉内容区的大半。此前它是 `minHeight: 64` —— 和「重复当前状态」一样高，
    /// 视觉上根本不像主按钮。对标 Be My Eyes 的 `Call a volunteer`（占内容区约 75%，
    /// 见 `docs/research/blind-ui-visual-benchmark-20260808.md` §1）。
    ///
    /// 这块面积对全盲用户没有点击收益 —— VoiceOver 选中后在屏幕任意位置双击都能激活，
    /// 物理面积不参与激活。它服务的是低视力用户和没开读屏的用户。
    ///
    /// ponytail: 固定高度而不是按屏高算比例。小屏（SE）上会滚动，而 ScrollView 本来就在；
    /// 要按比例得引 GeometryReader 重排整个内容层，不值这个复杂度。
    @ScaledMetric(relativeTo: .largeTitle) private var primaryBookingHeight: CGFloat = 280

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                mapBackgroundLayer
                contentLayer
                settingsOverlay
            }
            .background(AppColors.background)
            .safeAreaInset(edge: .bottom) { sosBar }
            // 全屏手势：读屏用户不必先找到按钮。两种模式都走同一个入口。
            .accessibilityAction(.magicTap) { activateSOS() }
            .navigationTitle("")
            .navigationBarHidden(true)
            .navigationDestination(for: BlindRunnerRoute.self) { route in
                destination(for: route)
            }
            .onAppear {
                viewModel.configure(with: appState, speechService: speechService)
                if locationService.isNotDetermined {
                    locationService.requestPermission()
                }
                locationService.startUpdating()
            }
            .onDisappear {
                viewModel.cancelLoading()
            }
            .task {
                await viewModel.loadActiveOrder()
            }
            .confirmationDialog("取消订单", isPresented: $showCancelConfirmation) {
                Button("确认取消", role: .destructive) {
                    Task { await viewModel.cancelActiveOrder() }
                }
                Button("不取消", role: .cancel) {}
            } message: {
                Text("确认取消本次预约？取消后将结束本次服务。")
            }
            .emergencyConfirmationAlert(isPresented: $showEmergencyConfirmation) {
                Task { await viewModel.enterEmergency(locationService: locationService) }
            }
            .confirmationDialog(
                EmergencySafetyCopy.homeCallTitle,
                isPresented: $showCallOptions,
                titleVisibility: .visible
            ) {
                if let contact = primaryEmergencyContact,
                   let url = EmergencyDialer.telURL(for: contact.phone) {
                    Button(EmergencySafetyCopy.homeCallContactTitle(name: contact.name)) {
                        openURL(url)
                    }
                }
                if let policeURL = EmergencyDialer.telURL(for: EmergencyDialer.policeNumber) {
                    Button(EmergencySafetyCopy.homeCallPoliceTitle) { openURL(policeURL) }
                }
                Button(EmergencySafetyCopy.cancelButtonTitle, role: .cancel) {}
            } message: {
                Text(callDialogMessage)
            }
        }
    }

    // MARK: - Layers

    /// 背景层：地图铺满上半屏。
    ///
    /// `accessibilitySortPriority(-1)` 让它在读屏遍历里排到内容之后 —— 视觉顺序与 VoiceOver
    /// 顺序在这里是**刻意解耦**的。规格允许这样做的前提有两条，都由这里满足：
    /// 地图不可交互（`allowsHitTesting(false)`），且不承载任何必要信息（同样的内容
    /// 在 `locationSummarySection` 里有文字版）。
    private var mapBackgroundLayer: some View {
        MapViewWrapper(
            centerCoordinate: viewModel.activeOrder?.startCoordinate ?? locationService.effectiveBackendLocation,
            showsUserLocation: locationService.isAuthorized,
            annotations: activeOrderMapAnnotations
        )
        .frame(maxWidth: .infinity)
        .frame(height: Self.mapVisualHeight)
        .allowsHitTesting(false)
        .ignoresSafeArea(edges: .top)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("辅助地图，显示当前位置或订单出发点")
        .accessibilityHint("地图仅用于视觉确认，不能操作。当前状态和主要操作排在读屏顺序的前面")
        .accessibilityIdentifier("blindRunnerHomeAuxiliaryMap")
        .accessibilitySortPriority(-1)
    }

    private var contentLayer: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 纯视觉留白，把地图让出来。读屏里不存在这一段。
                Color.clear
                    .frame(height: Self.mapRevealHeight)
                    .accessibilityHidden(true)

                VStack(spacing: 24) {
                    homeSections
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
                // ponytail: 直角。只圆上面两角要 iOS 16.4 的 UnevenRoundedRectangle 或自定义 Path，
                // 而本工程下限是 iOS 16 —— 视觉收益不值这个兼容成本。
                .background(AppColors.background)
            }
        }
        .accessibilityIdentifier("blindRunnerHomeScrollView")
        .accessibilitySortPriority(100)
    }

    /// 设置齿轮悬浮在地图右上角：视觉上还在老位置，但读屏遍历排到最后 ——
    /// 它此前在 header 的 `HStack` 里，于是每次进首页都是遍历到的第 2 个元素。
    private var settingsOverlay: some View {
        HStack {
            Spacer()
            Button {
                path.append(.settings)
            } label: {
                Image(systemName: "gearshape")
                    .font(.title2)
                    .foregroundColor(AppColors.textPrimary)
                    .frame(width: 64, height: 64)
                    .background(AppColors.background.opacity(0.9), in: Circle())
            }
            .accessibilityLabel("设置")
            .accessibilityHint("进入设置页面，可以编辑资料、实名认证或退出登录")
            .accessibilitySortPriority(-2)
        }
        .padding(.horizontal, 12)
    }

    private var sosBar: some View {
        BlindHomeSOSBar(
            coordinator: appState.emergencyCoordinator,
            mode: sosMode,
            action: activateSOS
        )
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var homeSections: some View {
        Group {
            header

            if viewModel.isLoading {
                Label(
                    "正在后台同步当前状态，页面仍可使用",
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
                .accessibilityLabel("正在后台同步当前状态，页面仍可使用")
            }

            if let errorMessage = viewModel.errorMessage {
                VStack(spacing: 10) {
                    Text(errorMessage)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.destructive)
                        .accessibilityLabel(errorMessage)
                    // 错误态下这是唯一的出路，按项目 64pt 硬规则给足触达 ——
                    // `.bordered` 的系统默认高度约 34pt，达不到。
                    Button("重试加载") {
                        Task { await viewModel.loadActiveOrder() }
                    }
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(AppColors.primary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 64)
                    .background(AppColors.secondaryBackground)
                    .cornerRadius(12)
                    .accessibilityHint("重新加载当前订单状态")
                }
            }

            if let order = viewModel.activeOrder {
                activeOrderSection(order)
            } else {
                newBookingSection
            }

            repeatStatusButton
            locationSummarySection

            #if DEBUG
            if AppBuildChannel.current.allowsEnvironmentSwitcher {
                DebugTestingPanel()
                    .environmentObject(appState)
            }
            #endif
        }
    }

    @ViewBuilder
    private func destination(for route: BlindRunnerRoute) -> some View {
        switch route {
        case .voiceBooking:
            BlindBookingView(startsWithVoice: true) { response in
                viewModel.handleOrderCreated(response)
                if let orderId = response.id {
                    path = [.orderStatus(orderId)]
                }
            }
        case .orderStatus(let orderId):
            BlindOrderStatusView(orderId: orderId) { updatedOrder in
                viewModel.activeOrder = updatedOrder.status.isActiveForBlindRunner ? updatedOrder : nil
            }
        case .settings:
            BlindRunnerSettingsView()
        }
    }

    // MARK: - SOS

    private var sosMode: BlindHomeSOSMode {
        BlindHomeSOSMode.resolve(order: viewModel.activeOrder, role: appState.activeRole)
    }

    private var primaryEmergencyContact: EmergencyContactResponse? {
        EmergencyContactResponse.singlePrimary(in: appState.emergencyContacts)
    }

    private var callDialogMessage: String {
        guard primaryEmergencyContact.flatMap({ EmergencyDialer.telURL(for: $0.phone) }) != nil else {
            return "\(EmergencySafetyCopy.homeCallDialogMessage)\(EmergencySafetyCopy.homeCallNoContactHint)"
        }
        return EmergencySafetyCopy.homeCallDialogMessage
    }

    private func activateSOS() {
        switch sosMode {
        case .cloudTrigger:
            showEmergencyConfirmation = true
        case .localCall:
            showCallOptions = true
        }
    }

    private func openURL(_ url: URL) {
        UIApplication.shared.open(url)
    }

    /// 标题与状态摘要合成**一个**焦点。它们语义相同（GB/T 37668 3.3.2.2 一级：
    /// 语义相同的部件应设联合单一聚焦框），拆成两个只是让读屏用户多滑一次。
    /// 合并后的朗读文本这里写死，不交给 `.combine` 自己拼 —— 自动拼接容易糊成一长串。
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HighContrastText("盲人跑者首页", style: .title)

            Text(viewModel.currentStatusText)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("盲人跑者首页。\(viewModel.currentStatusText)")
    }

    /// 地图的文字等价物 —— `docs/09-accessibility-and-voice-guidelines.md:78` 硬性要求它必须
    /// 在地图之外可用，所以不能删。但「位置摘要」这个标题可以：下面那行本身就自解释，
    /// 标题只对视觉扫读有用，而这一页没有扫读。降成一行 caption，不再是一张卡片。
    private var locationSummarySection: some View {
        Text(locationDescription)
            .font(AppFonts.caption())
            .foregroundColor(locationService.isDenied ? AppColors.warning : AppColors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(locationDescription)
            .accessibilityHint(locationService.isDenied ? "需要开启定位权限后才能创建预约" : "当前位置摘要")
    }

    private var activeOrderMapAnnotations: [MapAnnotationItem] {
        guard let order = viewModel.activeOrder, let coordinate = order.startCoordinate else { return [] }
        return [
            MapAnnotationItem(
                id: "active-order-start",
                coordinate: coordinate,
                title: "订单出发点",
                subtitle: order.startAddressForAnnouncement
            )
        ]
    }

    private var locationDescription: String {
        if locationService.isDenied {
            return "需要开启定位权限后才能创建预约。"
        }
        if let address = viewModel.activeOrder?.startAddress, !address.trimmed.isEmpty {
            return "订单出发点：\(address)。\(locationService.readableCurrentLocationSummary)"
        }
        return locationService.readableCurrentLocationSummary
    }

    private func activeOrderSection(_ order: OrderDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            BlindStatusCard(order: order)

            PrimaryButton("查看当前订单") {
                path.append(.orderStatus(order.orderId))
            }
            .accessibilityLabel("查看当前订单")
            .accessibilityHint("点击后查看订单状态详情")

            if viewModel.canCancelActiveOrder {
                Button("取消订单") {
                    showCancelConfirmation = true
                }
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.destructive)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 64)
                .disabled(viewModel.isPerformingAction)
                .accessibilityLabel("取消订单")
                .accessibilityHint("需要确认后取消当前订单")
            }
        }
    }

    /// 无订单态的唯一动作。此前上面还有一句「准备好后，可以创建一次新的陪跑预约。」——
    /// 那是在解释按钮要干什么，正好是 `accessibilityHint` 的定义，读屏用户听 hint、
    /// 低视力用户看按钮本身就够，屏幕上不需要第三份。
    private var newBookingSection: some View {
        Group {
            if viewModel.canStartNewBooking {
                // 只留一个入口。原来「开始约跑」和「语音下单」并列，等于每次下单前都要先做一次
                // 「我该点哪个」的判断，而两者进的本来就是同一个页面。现在统一进语音：进去就录音，
                // 说完读回整单再确认；不想说话就按「改用表单」，那张表一直都在。
                NavigationLink(value: BlindRunnerRoute.voiceBooking) {
                    bookingButtonLabel
                }
                .accessibilityLabel("开始约跑")
                .accessibilityHint("点击后进入语音下单：说一句想什么时候跑、跑多久，听完复述再确认。也可以改用表单填写")
                .accessibilityIdentifier("blindRunnerHomeStartBookingButton")
            } else {
                Button {
                    viewModel.explainBookingUnavailable()
                } label: {
                    bookingButtonLabel
                }
                .accessibilityLabel("开始约跑，订单状态尚未确认")
                .accessibilityHint("点击后说明如何先确认当前订单状态")
                .accessibilityIdentifier("blindRunnerHomeStartBookingGuardButton")
            }
        }
    }

    /// 按钮内部只有四个字：无图标、无副标题。对标产品的主按钮里一律没有第二样东西 ——
    /// 图标对读屏是噪音，对低视力是在跟文字抢字号。
    private var bookingButtonLabel: some View {
        Text("开始约跑")
            .font(AppFonts.largeTitle())
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: primaryBookingHeight)
            .background(AppColors.primary)
            .cornerRadius(16)
    }

    /// 视觉权重降为次要按钮，但**保留**：`AGENTS.md` 要求每个关键盲人页面都有它，
    /// 而且系统的 Speak Screen 读不到一次性 announcement，这是唯一能重听当前状态的入口。
    /// 降权只是为了不与「开始约跑」抢主按钮的位置，触达区仍是 64pt。
    private var repeatStatusButton: some View {
        Button("重复当前状态") {
            viewModel.repeatCurrentStatus(locationDescription: locationDescription)
        }
        .font(AppFonts.body().weight(.semibold))
        .foregroundColor(AppColors.primary)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 64)
        .background(AppColors.secondaryBackground)
        .cornerRadius(12)
        .accessibilityLabel("重复当前状态")
        .accessibilityHint("点击后重新播报当前页面信息")
    }
}

// MARK: - Shared Blind Runner Components

struct BlindStatusCard: View {
    let order: OrderDetailResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: order.status.statusSymbolName)
                    .font(.title)
                    .foregroundColor(order.status.statusColor)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(order.status.displayName)
                        .font(.title2.bold())
                        .foregroundColor(AppColors.textPrimary)
                    Text(order.status.blindRunnerDescription)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textSecondary)
                }
            }

            Divider()
                .background(AppColors.textSecondary.opacity(0.4))

            Text("预约时间：\((order.plannedStart ?? "").displayDateTime)")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
            Text("出发地点：\(order.startAddress ?? "")")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
            if let volunteerPhone = order.volunteerPhone, !volunteerPhone.trimmed.isEmpty {
                Text("志愿者电话：\(volunteerPhone)")
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("当前订单：\(order.status.displayName)，预约时间 \((order.plannedStart ?? "").displayDateTime)，出发地点 \(order.startAddress ?? "")")
        .accessibilityHint("订单状态摘要")
    }
}

#if DEBUG
struct DebugTestingPanel: View {
    @EnvironmentObject private var appState: AppState
    @State private var showEnvironmentConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("测试入口")
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)

            Button {
                appState.returnToRoleSelectionForTesting()
            } label: {
                Text("返回角色选择")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("返回角色选择")
            .accessibilityHint("回到角色选择页，用于测试不同身份")

            Button {
                showEnvironmentConfirmation = true
            } label: {
                Text("切换测试模式：\(appState.currentEnvironment.displayName)")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("切换测试模式")
            .accessibilityHint("当前模式 \(appState.currentEnvironment.displayName)，点击后可切换并重新登录")
        }
        .padding()
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
        .confirmationDialog("切换测试模式", isPresented: $showEnvironmentConfirmation) {
            Button("切换到 \(nextEnvironment.displayName) 并重新登录", role: .destructive) {
                appState.switchToNextEnvironmentForTesting()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("切换测试模式会清除当前登录状态，并返回登录页。")
        }
    }

    private var nextEnvironment: APIEnvironment {
        let allEnvironments = AppState.debugTestEnvironments
        guard let currentIndex = allEnvironments.firstIndex(of: appState.currentEnvironment) else {
            return .mock
        }
        return allEnvironments[(currentIndex + 1) % allEnvironments.count]
    }
}
#endif

#if DEBUG
#Preview {
    BlindRunnerHomeView()
        .environmentObject(AppState())
        .environmentObject(SpeechService())
        .environmentObject(LocationService())
}
#endif
