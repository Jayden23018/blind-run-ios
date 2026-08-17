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
    /// 首次使用引导。首次进首页自动推入一次，也可从设置进入。
    case help
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
    private let voiceQuerySession = VoiceStatusQuerySession()
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

    /// - Parameter speechInputService: 「问一句」用。可选是为了让既有的一批单测不必凭空造一个
    ///   麦克风服务；传 nil 时按下按钮不会起听（`VoiceStatusQuerySession.ask` 自己 guard 掉）。
    func configure(
        with appState: AppState,
        speechService: SpeechService,
        speechInputService: SpeechInputService? = nil
    ) {
        self.appState = appState
        self.speechService = speechService
        voiceQuerySession.configure(
            speechService: speechService,
            speechInputService: speechInputService,
            context: { [weak self] in (self?.activeOrder, self?.freshVolunteerCoordinate) }
        )
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

    /// 按下「问一句」。判定与答句在 `VoiceStatusQuery`，录音与拨号在 `VoiceStatusQuerySession`。
    func askVoiceQuestion() {
        voiceQuerySession.ask()
    }

    /// 志愿者的最新坐标，**过期的一律当没有**。
    ///
    /// `latestPeerLocation` 只是取缓存、不判新鲜度（订单状态页那套过期清理在
    /// `schedulePeerExpiry`，首页没有）。念一个几分钟前的距离，对听不见屏幕的人就是假数据。
    private var freshVolunteerCoordinate: CLLocationCoordinate2D? {
        guard let activeOrder,
              let sample = appState?.realtimeCoordinator.latestPeerLocation(
                orderID: activeOrder.orderId,
                ownerRole: .volunteer
              ),
              sample.isValid else { return nil }
        let capturedAt = Date(timeIntervalSince1970: TimeInterval(sample.timestampMilliseconds) / 1_000)
        guard Date().timeIntervalSince(capturedAt) <= LiveEscortSessionCoordinator.peerFreshness else {
            return nil
        }
        return BackendCoordinateNormalizer.backend(
            latitude: sample.latitude,
            longitude: sample.longitude,
            capturedAt: capturedAt
        )?.coordinate
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

/// 首页在订单出现 / 消失后要把 VoiceOver 焦点接到哪一块。
///
/// 用枚举而不是两个 Bool：两块内容互斥（有订单渲染订单卡，没订单渲染约跑按钮），
/// 两个 Bool 允许「都为 true」这种在页面上不存在的状态。
private enum BlindHomeFocusTarget: Hashable {
    case activeOrder
    case newBooking
}

struct BlindRunnerHomeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var speechInputService: SpeechInputService
    @StateObject private var viewModel = BlindRunnerHomeViewModel()
    @State private var path: [BlindRunnerRoute] = []
    @State private var showCancelConfirmation = false
    @State private var showEmergencyConfirmation = false
    @State private var showCallOptions = false
    /// 横屏（含 iPhone 横置、iPad 分屏的矮窗口）判定。
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    /// 订单出现或消失后，这一屏换掉的正是主内容块，焦点会被系统收走且落点不确定。
    /// 已经有 `speakStatusChange` 在播报变化，焦点不跟过来就是「听到了，但滑不到」。
    ///
    /// 只在 `activeOrder?.status` 变化时移。首页无订单时它恒为 nil，`onChange` 不触发 ——
    /// 没订单的用户进首页不会被抢焦点。
    @AccessibilityFocusState private var focusedSection: BlindHomeFocusTarget?

    /// 地图在视觉上占据的高度，`mapRevealHeight` 是内容层为它让出的部分 ——
    /// 两者相差的一段就是内容盖住地图下沿的量，做出「面板压在地图上」的层次。
    ///
    /// **横屏必须压扁**：这两个值原本是写死的 300 / 236。iPhone 横屏可用高度约 390pt，
    /// 300pt 的装饰性地图会吃掉 77% 的屏幕，把「开始约跑」整个挤到折叠线以下 ——
    /// 而地图在这个 App 里是 `allowsHitTesting(false)` 的纯装饰层
    /// （不承载任何必要信息，文字版在 `locationSummarySection`）。
    /// 让一个不可交互的装饰把唯一的主操作挤出屏幕，是本末倒置。
    ///
    /// 用 `verticalSizeClass` 而不是 `GeometryReader`：只需要区分「横屏/竖屏」这一个二值，
    /// 引 `GeometryReader` 要重排整个内容层，不值这个复杂度。
    ///
    /// **竖屏也压过一次（300/236 → 200/150）**：横屏那轮只修了横屏，同一个本末倒置在竖屏上
    /// 仍然成立，只是程度轻到没被当成 bug。按 iPhone 15（852pt）默认字号排一遍无订单态：
    /// 让位 236 + 内边距 28 + 标题区约 64 + 间距 24 + 「开始约跑」280 + 间距 24 = 656pt，
    /// 而底部 SOS 条（64pt 按钮 + 上下 16 + 安全区 34）之上只剩到 738pt ——
    /// 「重复当前状态」落在 656–720，**首屏只露得出小半截**。
    /// 它是 `AGENTS.md` 要求每个盲人页面都有的 M 档入口，却要先滚动才看得全。
    ///
    /// 这一刀切掉的 86pt 全给内容：同样排法下按钮落到 570–634，默认字号首屏整条可见。
    /// 对 VoiceOver 用户（A 类）没有区别 —— 滑动本来就到得了；受损的一直是**低视力且不开读屏**
    /// 的 B 类，他们只有「看得见的那一屏」这一条通道。见
    /// `docs/research/blind-ui-visual-benchmark-20260808.md` 规则 5「地图是装饰，列表是界面」。
    private var mapVisualHeight: CGFloat { verticalSizeClass == .compact ? 140 : 200 }
    private var mapRevealHeight: CGFloat { verticalSizeClass == .compact ? 96 : 150 }

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
                viewModel.configure(
                    with: appState,
                    speechService: speechService,
                    speechInputService: speechInputService
                )
                if locationService.isNotDetermined {
                    locationService.requestPermission()
                }
                locationService.startUpdating()
            }
            .onDisappear {
                viewModel.cancelLoading()
            }
            .onChange(of: viewModel.activeOrder?.status) { status in
                focusedSection = status == nil ? .newBooking : .activeOrder
            }
            .task {
                // 引导先于订单加载推入：它不依赖订单，而等加载完再跳会让用户先听半句首页播报
                // 再被切走。`.task` 只在根视图首次出现时跑，所以从引导页返回不会把人弹回去；
                // 标志只在按下「知道了」时才写（`markBlindFirstRunHelpSeen`），
                // 没看完就退出的人下次重进 App 仍会拿到引导。
                if !appState.didSeeBlindFirstRunHelp {
                    path.append(.help)
                }
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
                        EmergencyDialer.dial(url)
                    }
                }
                if let policeURL = EmergencyDialer.telURL(for: EmergencyDialer.policeNumber) {
                    Button(EmergencySafetyCopy.homeCallPoliceTitle) { EmergencyDialer.dial(policeURL) }
                }
                Button(EmergencySafetyCopy.cancelButtonTitle, role: .cancel) {}
            } message: {
                Text(callDialogMessage)
            }
        }
    }

    // MARK: - Layers

    /// 背景层：地图铺满上半屏，**对读屏完全隐藏**。
    ///
    /// 这一层是纯装饰：不可交互（`allowsHitTesting(false)`），且不承载任何必要信息
    /// （同样的内容在 `locationSummarySection` 里有文字版）。装饰性内容的标准处理就是
    /// 对辅助技术隐藏 —— 读屏用户进首页 0 次多余划动就够到唯一的主操作，比「排到内容后面」
    /// 还好一档。低视力用户看到的画面完全不变。
    ///
    /// **为什么不是「排到内容后面」**：SwiftUI 把 VoiceOver 遍历顺序绑死在**绘制顺序**上，
    /// 而地图必须画在最底层。2026-08-14 在真机上逐个实测了四种排法 —— 裸
    /// `accessibilitySortPriority`、换声明顺序 + `zIndex` 维持视觉、三层都加
    /// `accessibilityElement(children: .contain)` 再排、把地图改成内容层的 `.background`
    /// —— 地图**一律**排在内容前面。`accessibilitySortPriority` 在这个结构里是空操作，
    /// 别再往回加。详见 `docs/research/swiftui-voiceover-traversal-order-20260814.md`。
    ///
    private var mapBackgroundLayer: some View {
        MapViewWrapper(
            centerCoordinate: viewModel.activeOrder?.startCoordinate ?? locationService.effectiveBackendLocation,
            showsUserLocation: locationService.isAuthorized,
            annotations: activeOrderMapAnnotations
        )
        .frame(maxWidth: .infinity)
        .frame(height: mapVisualHeight)
        .allowsHitTesting(false)
        .ignoresSafeArea(edges: .top)
        // 整棵子树一起隐藏：真机上高德的 `MKMapView` 自己会挂一堆无障碍元素，只在最外层
        // 挂 label 挡不住它们冒出来。
        .accessibilityHidden(true)
    }

    private var contentLayer: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 纯视觉留白，把地图让出来。读屏里不存在这一段。
                Color.clear
                    .frame(height: mapRevealHeight)
                    .accessibilityHidden(true)

                VStack(spacing: 24) {
                    homeSections
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
                // 先限宽再居中：内容列在 iPad / 横屏上不铺满整屏，见 `BlindLayout.readableContentWidth`。
                // 背景仍然铺满，所以视觉上还是一整块面板压在地图上，只是文字不横跨全宽。
                .readableContentColumn()
                // ponytail: 直角。只圆上面两角要 iOS 16.4 的 UnevenRoundedRectangle 或自定义 Path，
                // 而本工程下限是 iOS 16 —— 视觉收益不值这个兼容成本。
                .background(AppColors.background)
            }
        }
        .accessibilityIdentifier("blindRunnerHomeScrollView")
    }

    /// 设置齿轮悬浮在地图右上角：视觉上还在老位置，但读屏遍历排到最后 ——
    /// 它此前在 header 的 `HStack` 里，于是每次进首页都是遍历到的第 2 个元素。
    ///
    /// 「排到最后」靠的是它在 `body` 的 ZStack 里**最后声明**（遍历顺序 = 绘制顺序），
    /// 不是 `accessibilitySortPriority` —— 那个修饰符在这个结构里实测无效，已移除。
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
        }
        .padding(.horizontal, 12)
    }

    private var sosBar: some View {
        BlindHomeSOSBar(
            coordinator: appState.emergencyCoordinator,
            mode: sosMode,
            action: activateSOS
        )
        // 与内容列同宽：不限的话 SOS 条在 iPad 上是一条 1024pt 宽的红杠，
        // 和上面 700pt 的内容列左右都对不齐。材质背景仍铺满整宽。
        .readableContentColumn()
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
                    .accessibilityFocused($focusedSection, equals: .activeOrder)
            } else {
                newBookingSection
                    .accessibilityFocused($focusedSection, equals: .newBooking)
            }

            // 无订单时不给这个按钮 —— 它在那个状态下没有答案可给，见 `askQuestionButton` 的注释。
            if viewModel.activeOrder != nil {
                askQuestionButton
            }
            repeatStatusButton
            locationSummarySection
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
        case .help:
            BlindRunnerHelpView(isFirstRun: true)
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

    /// 排在「重复当前状态」之前：整段状态播报要 15~25 秒，问一句只念被问的那一项，
    /// 是这两个「听」入口里更省时间的那个，所以先遍历到它。
    ///
    /// 与「重复当前状态」同一套次要按钮样式和 64pt 触达 —— 主按钮位置留给「开始约跑」。
    ///
    /// **只在有进行中订单时出现。** 两条理由，第二条才是根因：
    ///
    /// 1. 无订单态的上方是 280pt 的「开始约跑」（`primaryBookingHeight`，还会随字号长），
    ///    它排在后面正好落进底部 SOS 条那一截，把「重复当前状态」一起顶出可见区。
    /// 2. 更要紧的是**那个状态下它没有答案可给**：`VoiceStatusQuery.answer` 在
    ///    `order == nil` 时短路，四个意图统一回「当前没有进行中的预约」
    ///    （`VoiceStatusQuery.swift:109`）。按下去要走一趟麦克风授权 + 录音 + 等待，
    ///    换来的是 header 已经念过的同一句话 —— 对全盲用户这就是一次白等。
    ///
    /// 订单详情页那个「问一句」（`blindOrderStatusAskQuestionButton`）不受此限，它天然只在有订单时存在。
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
        .accessibilityIdentifier("blindRunnerHomeAskQuestionButton")
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
        .environmentObject(SpeechInputService())
}
#endif
