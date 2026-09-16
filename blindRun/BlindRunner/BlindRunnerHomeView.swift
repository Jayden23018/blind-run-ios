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
    /// 首次使用引导。首次进首页自动推入一次，也可从「我的」进入。
    case help
    // `.settings` 已移除：设置改成底部标签栏的「我的」，不再是首页右上角的悬浮齿轮，
    // 所以首页这条导航栈里没有它的落点了。入口本身没有消失，见 `BlindRunnerTabView`。
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

    /// - Parameter announcesStatus: 首启引导页正压在首页上时传 `false`。
    ///
    ///   两个页面共用同一个 `AVSpeechSynthesizer`，而 `SpeechService.speak` 的第一件事是
    ///   `stopSpeaking(at: .immediate)`（`SpeechService.swift:47`）—— 谁后说谁赢。
    ///   这一句要等一次网络往返才回来，比引导页的 `.task` 晚，于是把引导念到一半的说明当场切断。
    ///   两句又都以「欢迎…助盲跑」开头，听感就是「只念了标题就没了」，2026-09-07 真机报的正是这个。
    ///
    ///   ⚠️ 传 `false` 是**推迟**不是取消：成功路径会置 `owesStatusAnnouncement`，
    ///   等首页重新成为最前面那一页时由 `announceStatusIfOwed()` 补上。
    ///   写成「不播」会让从引导页按返回键退出（不按「知道了」）的用户整次启动听不到任何东西。
    ///
    ///   **只闸成功路径的状态播报，不闸 `speakError`** —— 出错是最不该被静默的时刻，
    ///   而且它罕见到不值得为它多设一个开关。
    ///
    ///   请求合并（下面 `activeLoadTask` 那段）会把后到者的这个参数丢掉，先到的赢。
    ///   不特别处理是因为「欠着」这套机制本身兜住了：先到那次若传了 `false`，
    ///   欠账仍然在，首页一露头就补播 —— 后到者要的播报没丢，只是晚一点。
    func loadActiveOrder(announcesStatus: Bool = true) async {
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
            await self.performActiveOrderLoad(
                appState: appState,
                requestID: requestID,
                announcesStatus: announcesStatus
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

    private func performActiveOrderLoad(
        appState: AppState,
        requestID: UUID,
        announcesStatus: Bool = true
    ) async {
        do {
            let orders = appState.orders
            let statusRequestToken = activeOrder.map {
                appState.realtimeCoordinator.beginOrderStatusRequest(orderID: $0.orderId)
            }
            // 🚩 走 `/api/orders/active` 而不是 `/api/orders/mine`：那条是分页历史列表
            // （默认 `size=10`，`createdAt` 倒序），要客户端自己 filter + sort 才能挑出活跃那条。
            // 挑得出来靠的是两条**没写进契约**的性质：盲人同时只能有一条活跃订单、
            // 而且它一定落在最近 10 条里。这个端点由服务端判「哪些状态算活着」，
            // 与 `GET /api/emergency/active` 是同一次冷启动恢复里刻意做成一对的两条。
            //
            // 没有活跃订单时后端给的是 `data: null`（不是 404、不是空对象），
            // 所以这里解信封而不是直接解 `OrderDetailResponse` —— 见 `ActiveOrderEnvelope`。
            let envelope: ActiveOrderEnvelope = try await HomeLoadCoordinator.run(
                timeout: loadTimeout,
                operationName: "blind-active-order"
            ) {
                try await orders.activeOrder()
            }
            guard activeRequestID == requestID, !Task.isCancelled else { return }
            let previousOrderID = activeOrder?.orderId
            let candidate = envelope.data
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
            if announcesStatus {
                owesStatusAnnouncement = false
                speakCurrentStatus()
            } else {
                owesStatusAnnouncement = true
            }
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

    /// 首页欠着一次状态播报 —— 加载完成时引导页正压在上面，播了会把它切断。
    ///
    /// **必须是「欠着」而不是「进引导页时静音、出来时补播」**：用户可以在加载回来之前
    /// 就按下「知道了」（引导脚本 40–60 秒，而超时上限是 20 秒），那一刻
    /// `activeOrder` 还是 nil，照播就是对着一个有活跃订单的盲人念「可以点击开始约跑」。
    /// 只在**加载成功**时才置位，所以失败/超时那条路不会欠 —— 那边由没有加闸的
    /// `speakError` 负责，两条不会互相盖。
    @Published private(set) var owesStatusAnnouncement = false

    /// 首页重新成为最前面那一页时调用。欠着才播，播完清账。
    func announceStatusIfOwed() {
        guard owesStatusAnnouncement else { return }
        owesStatusAnnouncement = false
        speakCurrentStatus()
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
            try await appState.orders.cancel(orderId: activeOrder.orderId)
            let updated = try await appState.orders.orderDetail(orderId: activeOrder.orderId)
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
            // `try?` 是迁移前就有的，且这里正确：取消失败的原因**已经播报也已经写进
            // `errorMessage`**，这一步只是顺手把本地那份订单校准回真实状态。
            // 再抛一次只会把用户刚听到的失败原因换成第二条报错。
            if let updated = try? await appState.orders.orderDetail(orderId: activeOrder.orderId) {
                self.activeOrder = updated.status.isActiveForBlindRunner ? updated : nil
            }
        } catch {
            isPerformingAction = false
            errorMessage = "取消失败。"
            speechService?.speakError(errorMessage ?? "取消失败。")
            if let updated = try? await appState.orders.orderDetail(orderId: activeOrder.orderId) {
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
            safety: appState.safety,
            locate: { await EmergencyCoordinator.freshEmergencyCoordinate(using: locationService) },
            locationFailureReason: { locationService?.locationError }
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

    /// **由 `BlindRunnerTabView` 注入，不再自己 `@StateObject` 持有。**
    ///
    /// 理由是安全的：「我的」tab 底部那条兜底求助条要用同一个 `activeOrder` 判走云端还是走
    /// 本地拨号（`BlindHomeSOSMode.resolve`）。两个 tab 各持一个 view model 会让两处看到
    /// 不同的订单，而其中一处决定的是求助发不发得出去。所有权因此上移一层。
    @ObservedObject var viewModel: BlindRunnerHomeViewModel

    @State private var path: [BlindRunnerRoute] = []
    /// 订单出现或消失后，这一屏换掉的正是主内容块，焦点会被系统收走且落点不确定。
    /// 已经有 `speakStatusChange` 在播报变化，焦点不跟过来就是「听到了，但滑不到」。
    ///
    /// 只在 `activeOrder?.status` 变化时移。首页无订单时它恒为 nil，`onChange` 不触发 ——
    /// 没订单的用户进首页不会被抢焦点。
    @AccessibilityFocusState private var focusedSection: BlindHomeFocusTarget?

    /// 「首页是最前面那一页了，而且它还欠着一次状态播报」。
    /// 做成派生值是为了让下面那个 `onChange` 一条盖住两种到达顺序 —— 详见它的注释。
    private var shouldSettleHomeAnnouncement: Bool {
        path.isEmpty && viewModel.owesStatusAnnouncement
    }

    // 🗑 **装饰地图已从首页移除**（`mapBackgroundLayer` / `mapVisualHeight` / `mapRevealHeight`
    // 三者一并删除）。它是 `allowsHitTesting(false)` + `isDecorative` 的纯装饰层，
    // 信息在 `locationSummarySection` 里有文字版 —— 而设计稿把首页收成「问候 + 订单卡 +
    // 预约块」三块，地图没有位置，文字版那一行也随之删除（位置信息在订单卡的地点行里）。
    //
    // 连带失效的一整段历史：为压扁它做过两轮（300/236 → 200/150 → 横屏 140/96），
    // 理由都是「不可交互的装饰不该把唯一的主操作挤出屏幕」。删掉地图之后这个矛盾不再存在。
    // 详见 `docs/research/blind-ui-visual-benchmark-20260808.md` 规则 5「地图是装饰，列表是界面」。
    //
    // 🗑 **280pt 的「开始约跑」巨按钮也随之删除**（`primaryBookingHeight`）。设计稿改成
    // 「深蓝订单卡占最大位置、浅蓝预约块在其下」的两块结构：最大的位置留给**即将开始的那一单**
    // 而不是留给下单动作 —— 打开 App 第一句该听到的是最重要的信息。无订单时预约块上移到
    // 订单卡的位置，仍然是这一屏唯一的主操作。

    var body: some View {
        NavigationStack(path: $path) {
            contentLayer
            .background(AppColors.Flow.page)
            // 🗑 底部常驻求助条已从首页移除（项目负责人 2026-09-16 拍板），改由「我的」tab
            // 底部兜底 —— 同一个 `BlindHomeSOSBar`、同一条 `BlindHomeSOSMode.resolve` 判据，
            // 见 `BlindRunnerTabView`。`AGENTS.md` §6 与 `docs/05-page-specs.md` 已同步改口径。
            //
            // 🔴 **magic tap 手势刻意保留，并上移到了 `BlindRunnerTabView`。**
            // 它不占任何像素，所以与设计稿不冲突；而删掉它是纯损失 ——
            // 对 VoiceOver 用户，它是首页上唯一还能直达紧急入口的通道。
            // 挂在 tab 容器上而不是这一页，是为了三个 tab 上都能用，且弹窗只需接一处。
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
                //
                // 🚩 但光换顺序不够：加载**回来**得比引导页的 `.task` 晚，而
                // `SpeechService.speak` 先 `stopSpeaking(.immediate)` —— 首页这一句会把引导
                // 念到一半的说明切断（2026-09-07 真机报障）。所以引导在场时首页静音加载，
                // 播报推迟到用户按「知道了」（见下面的 `onChange`）。
                // 传 false 是**推迟**不是取消，还账在下面的 `onChange`。
                let showsFirstRunHelp = !appState.didSeeBlindFirstRunHelp
                if showsFirstRunHelp {
                    path.append(.help)
                }
                await viewModel.loadActiveOrder(announcesStatus: !showsFirstRunHelp)
            }
            // 引导期间首页只是**欠着**那次播报（见上面的 `.task`），这里还账。
            //
            // 判据是「首页重新成为最前面那一页 **且** 确实欠着」，两个条件缺一不可，
            // 而且**两种到达顺序都要覆盖**：
            //   ① 加载先回来（欠上账），用户再按「知道了」或返回键 → path 空 → 触发
            //   ② 用户先离开引导页，加载后回来才欠上账 → path 已空 → 同一个派生值翻面 → 触发
            // 第 ② 种是弱网下的常态：引导脚本 40–60 秒，而加载超时上限是 20 秒。
            //
            // ⚠️ 别改回「挂 `didSeeBlindFirstRunHelp`」：那个标志只在按下「知道了」时翻面，
            // 用返回键退出引导的人一辈子等不到它，整次启动首页一个字都不播。
            // 也别改成裸 `onChange(of: path)`：欠账这个条件同时挡住了从设置页 / 订单详情页
            // 返回时的多余播报 —— 那两条路径不欠账。
            .onChange(of: shouldSettleHomeAnnouncement) { shouldSettle in
                guard shouldSettle else { return }
                viewModel.announceStatusIfOwed()
            }
            // 🗑「取消订单」的确认弹窗已从首页移除。设计稿把首页收成两块，取消属于低频的
            // 破坏性操作，归宿是订单页信息列表的最后一行（`AGENTS.md` §5 的可取消状态不变，
            // `BlindRunnerHomeViewModel.cancelActiveOrder` 保留未动 —— 只是首页不再有入口）。
            //
            // 🗑 两个紧急弹窗随求助条一并上移到 `BlindRunnerTabView`：magic tap 可以在任意
            // tab 触发，弹窗挂在 tab 容器上才呈现得出来。挂在这一页的话，从「记录」或
            // 「我的」触发时弹窗所在的视图不在屏上，用户按了没有任何反应。
        }
    }

    // MARK: - Content

    /// 首页只有三块：问候 → 深蓝订单卡 → 浅蓝预约块。
    ///
    /// **没有待进行订单时深蓝卡整块不渲染，预约块自然上移到它的位置** —— 不是靠 Spacer
    /// 顶上去，而是它本来就是 `VStack` 里的下一个元素。
    ///
    /// **多个待进行订单时只显示最近的一个。** 这不是客户端挑的：数据源
    /// `GET /api/orders/active` 由服务端判「哪一条算活着」并只返回一条
    /// （见 `performActiveOrderLoad` 的注释）。其余在「记录」tab 里。
    private var contentLayer: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                greeting
                    .padding(.horizontal, 4)
                    .padding(.top, 18)

                if viewModel.isLoading {
                    syncNotice
                }

                if let errorMessage = viewModel.errorMessage {
                    errorSection(errorMessage)
                }

                if let order = viewModel.activeOrder {
                    BlindHomeOrderCard(order: order) {
                        path.append(.orderStatus(order.orderId))
                    }
                    .accessibilityFocused($focusedSection, equals: .activeOrder)
                    .padding(.top, 6)
                }

                BlindHomeBookingBlock(isEnabled: viewModel.canStartNewBooking) {
                    if viewModel.canStartNewBooking {
                        path.append(.voiceBooking)
                    } else {
                        viewModel.explainBookingUnavailable()
                    }
                }
                .accessibilityFocused($focusedSection, equals: .newBooking)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, FlowMetrics.pageHorizontalPadding)
            .padding(.bottom, 28)
            // 内容列在 iPad / 横屏上不铺满整屏，见 `BlindLayout.readableContentWidth`。
            .readableContentColumn()
        }
        .background(AppColors.Flow.page)
        // identifier 与改版前逐字相同：UI 测试拿它当「不吃点击的安全落点」敲屏幕
        // （守卫 `blind-tap-center` 的存在理由）。改名会让那几条用例找不到落点。
        .accessibilityIdentifier("blindRunnerHomeScrollView")
    }

    /// 「你好，{姓名}」。**这一屏的标题**，读屏带 header 特征。
    ///
    /// 姓名取 `blindProfile?.name`，没填就只说「你好」—— 不摆「未填写」这种占位，
    /// 也不改用手机号（那会在读屏外放时把号码念出来）。
    private var greeting: some View {
        Text(greetingText)
            .flowFont(FlowFonts.homeGreeting())
            .foregroundColor(AppColors.Flow.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("blindRunnerHomeGreeting")
    }

    private var greetingText: String {
        guard let name = appState.blindProfile?.name?.nilIfBlank else { return "你好" }
        return "你好，\(name)"
    }

    private var syncNotice: some View {
        Label("正在后台同步当前状态，页面仍可使用", systemImage: "arrow.triangle.2.circlepath")
            .flowFont(FlowFonts.rowDetail())
            .foregroundColor(AppColors.Flow.secondaryText)
            .accessibilityLabel("正在后台同步当前状态，页面仍可使用")
    }

    private func errorSection(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .flowFont(FlowFonts.statusSubtitle())
                .foregroundColor(AppColors.destructive)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(message)
            // 错误态下这是唯一的出路，按项目 64pt 硬规则给足触达。
            FlowActionButton(
                "重试加载",
                style: .ghost,
                accessibilityHint: "重新加载当前订单状态"
            ) {
                Task { await viewModel.loadActiveOrder() }
            }
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
        case .help:
            BlindRunnerHelpView(isFirstRun: true)
        }
    }

    // 🗑 `bookingButtonLabel` / `askQuestionButton` / `repeatStatusButton` 三者已删除。
    //
    // - `bookingButtonLabel`：280pt 的「开始约跑」巨按钮，被设计稿的浅蓝预约块取代。
    // - `askQuestionButton`：「问一句」。它已经在求助与安全中心弹层里（PR #139 的
    //   `BlindSafetyHubView` 就带这个入口），首页再留一个是同一个动作的第二个入口。
    // - `repeatStatusButton`：「重复当前状态」。**这一条是项目硬规则**
    //   （skill `aidrun-a11y-voice`：「可以降视觉权重，但不能删」，理由是系统的
    //   Speak Screen 读不到一次性的 `announcement`）。项目负责人 2026-09-16 拍板把它
    //   移进求助与安全中心弹层 —— **动作没有消失，位置变了**。阶段 3 接入弹层入口时落地；
    //   在那之前首页仍然会在进入时自动播报一次（`speakCurrentStatus`，未动），
    //   而 `viewModel.repeatCurrentStatus(locationDescription:)` 保留未删，等弹层来调。
    //
    // ⚠️ `docs/05-page-specs.md` 的「底部常驻条恒为两个版位」一节已随之改口径。
}

// MARK: - Shared Blind Runner Components

// 🗑 `BlindStatusCard` 已删除（改版后零调用点）。
//
// 它是改版前首页那张「状态图标 + 状态名 + 预约时间 + 出发地点 + 掩码电话」的浅灰小卡，
// 唯一调用点是同样已删的 `activeOrderSection`。同一批信息现在由 `BlindHomeOrderCard`
// 承载，且合成**一个**无障碍元素（原来那张卡也是 `.combine`，但标签里不含陪跑员信息）。
//
// 它的掩码电话那一行没有丢失语义：号码全程只走 `tel:`，屏幕上与读屏里都不出现全号 ——
// 这条规则现在钉在 `AGENTS.md` §8 与 `volunteerNameForSpeech` 一带，不再依赖某个视图的注释。

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
#Preview("首页 · 有订单") {
    BlindRunnerTabView()
        .environmentObject(AppState())
        .environmentObject(SpeechService())
        .environmentObject(LocationService())
        .environmentObject(SpeechInputService())
}
#endif
