import Combine
import CoreLocation
import SwiftUI

/// 首页那个「可服务」开关叫什么名字 —— **全 App 单一来源**。
///
/// 🔴 存在的理由是一个真实缺陷：资质审核通过的引导语此前写的是
/// 「请回到首页开启**接单开关**」（`VolunteerCertificateUploadView.swift:105`、`:130`），
/// 而首页那个控件叫「可服务开关」。**首页上根本没有叫「接单开关」的东西** ——
/// 用户照着那句话回首页找，找到的是另一个名字，没有办法确认这是不是同一个控件。
/// 对按控件名导航的读屏用户尤其致命，但看得见的人一样要停顿一下。
///
/// 抽成常量而不是写一条「两处文案要一致」的用例：常量化之后两处**不可能**再各叫各的，
/// 而用例只能在漂移发生之后报警。
enum VolunteerAvailabilityCopy {
    static let toggleTitle = "可服务开关"

    /// 引导用户去开这个开关的那半句。资质审核通过、身份材料通过两条路径共用。
    static let goOpenItHint = "请回到首页开启\(toggleTitle)。"
}

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

    /// 已确认但还没到点的跨天预约单，按开跑时间升序（最近的排最前）。
    ///
    /// 🚩 **不能靠 `activeOrder` 承载它**，两条独立的理由：
    /// ① 数据源根本给不到 —— 后端 `VolunteerService.loadActiveOrders` 的白名单只有
    ///    `IN_PROGRESS`/`DRIVER_EN_ROUTE`/`DRIVER_ARRIVED`，`dispatch-summary.activeOrders`
    ///    里从来不会出现 `SCHEDULED_CONFIRMED`（已投 handoff 请后端单开 `scheduledOrders`）。
    /// ② 就算给得到也不该共用一个位 —— `activeVolunteerOrder(from:)` 按 `createdAt` 降序取第一个，
    ///    而新接的即时单 `createdAt` 必然更晚 ⇒ 志愿者在预约日之前又接了一单即时的，
    ///    那张跨天单就从首页消失，直到即时单跑完。而闸门不会因为他在忙就暂停。
    ///
    /// 对标产品同样是两个位：Uber Opportunities Center / Lyft Scheduled pickups /
    /// Rover Upcoming inbox 都独立于「当前行程」
    /// （`docs/research/volunteer-scheduled-order-confirm-ui-20260906.md` §二.2）。
    @Published private(set) var scheduledOrders: [OrderDetailResponse] = []
    /// 正在提交确认/释放的那一单。用 id 而不是 Bool：同屏可能有多张预约单，
    /// 一个全局 Bool 会把所有卡片一起转圈。
    @Published private(set) var submittingScheduledOrderID: Int64?
    /// 预约区块自己的错误文案。**不复用 `errorMessage`** —— 那条挂在派单摘要的错误区上，
    /// 预约单拉失败时弹「重试加载」会让人以为整页坏了，而其余内容完全正常。
    @Published private(set) var scheduledOrdersMessage: String?

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
    /// 🚨 **发 `.accept` 还是 `.interested` 由推送里的 `requiresIntroCall` 决定，不由这里推算。**
    /// 后端 `app.intro-call.enabled` 默认 true，陌生人直接发 `ACCEPT` 会 409
    /// `INTRO_CALL_REQUIRED`（`DispatchService.handleAccept` 的守卫）。后端只在两种情况放行
    /// `ACCEPT`：这一对已经磨合成功过（`IntroCallPair.outcome == MATCHED`），或者距开跑时间
    /// 已经塞不下一轮通话窗口。两个判据客户端都拿不到 —— 前者在后端库里，后者的窗口长度是
    /// 后端配置（`app.intro-call.window-minutes`）。
    ///
    /// 所以判断只有一份，在后端（`DispatchService.introCallWindowFits`），结论随派单推送下发：
    /// `WSNewOrder.requiresIntroCall` → `WSNewOrder.dispatchRespondAction`。
    /// 调用方按那个属性传 `action` 进来，这里不再二次判断。
    ///
    /// **两个方向的 409 都要兜，因为推送是一个快照**：它发出之后，这一对的磨合记录
    /// 或 `app.intro-call.enabled` 都可能变，于是快照给的答案两边都可能过时。
    /// 志愿者已经点过这个动作了，30 秒倒计时里不该让他为后端改主意再点一遍。
    ///
    /// - `.accept` → 409 `INTRO_CALL_REQUIRED`：就地改发 `.interested` 重试一次
    ///   （下面那个内层 `do/catch`）。`.interested` 没有额外前置闸，就地重发是安全的。
    /// - `.interested` → 409 `INTRO_CALL_NOT_REQUIRED`：**递归重走本函数**而不是就地补一个
    ///   API 调用 —— `.accept` 有 `.interested` 没有的前置闸（定位权限判定 +
    ///   `VolunteerLocationReporter.reportIfNeeded`），就地补调用等于绕过它们。
    ///
    /// 两条各自只走一次，所以不会来回打：前者靠内层 `do` 的结构（重试不再被 catch 接住），
    /// 后者靠 `allowsIntroCallUpgrade` —— 递归时传 `false`。**调用方不要传这个参数。**
    ///
    /// ⚠️ 顺带一条历史：`requiresIntroCall` 曾经只挂在 `AvailableOrderResponse` 上，
    /// 而本 App 不调 `GET /api/orders/available`，所以那段时间客户端对陌生人一律发
    /// `.interested`，`AGENTS.md` §5 也据此写着「字段搬到推送上之前不要加 `.accept` 分支」。
    /// 后端已于 2026-08-22（迁移 `0031`）把它搬到 `NEW_ORDER` 上并标为**必填**
    /// （`websocket-protocol.md`「客户端按它决定 `/respond` 发哪个 `action`」），前提已解除。
    func respondToDispatch(
        action: OrderRespondAction,
        currentLocation: CLLocationCoordinate2D?,
        locationAuthorized: Bool,
        allowsIntroCallUpgrade: Bool = true
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
                var effectiveAction = action
                do {
                    try await submitDispatchResponse(
                        action: action,
                        order: order,
                        appState: appState,
                        currentLocation: currentLocation,
                        locationAuthorized: locationAuthorized
                    )
                } catch let error as APIError
                    where action == .accept && error.errorCode == .introCallRequired {
                    // 推送说「这一单可以直接接」，后端却说不行 —— 推送发出后这一对的磨合记录
                    // 或 `app.intro-call.enabled` 变了。这是同一个意图的两种发法，
                    // 不是一个需要用户重新决策的场景，所以自己改口，**只重试一次**。
                    // 重试仍失败就落到下面的正常错误分支。
                    effectiveAction = .interested
                    try await submitDispatchResponse(
                        action: .interested,
                        order: order,
                        appState: appState,
                        currentLocation: currentLocation,
                        locationAuthorized: locationAuthorized
                    )
                }
                // 请求已经在上面的 `submitDispatchResponse` 里发过了（`.accept` 撞上
                // `INTRO_CALL_REQUIRED` 时会自己改口重发一次），这里只是记结果。
                // 判据用 `effectiveAction` 而不是入参 `action`：改过口之后这一单没接成。
                let acceptedOrderId = effectiveAction == .accept ? order.orderId : nil
                let acceptedOrder = await refreshAfterDispatchResponse(
                    acceptedOrderId: acceptedOrderId,
                    appState: appState
                )
                dismissDispatch()
                appState.realtimeCoordinator.clearDispatch(orderID: order.orderId)
                acceptedDispatchInitialOrder = acceptedOrder
                acceptedDispatchOrderId = acceptedOrderId
                if effectiveAction == .interested {
                    pendingIntroCallOrder = VolunteerIntroCallRoute(dispatchOrder: order)
                }
                speechService?.speak(Self.dispatchResponseSpeech(for: effectiveAction))
            } catch let error as APIError {
                isRespondingToDispatch = false
                if appState.handleAuthenticatedAPIError(error) {
                    return
                }
                // 熟人误发 `INTERESTED`：后端 409 `INTRO_CALL_NOT_REQUIRED`（2026-08-26 新增）。
                //
                // 🚩 **必须重新走一遍本函数，不能就地补一个 API 调用**：`.accept` 有 `.interested`
                // 没有的前置闸（定位权限判定 + `VolunteerLocationReporter.reportIfNeeded`），
                // 就地补调用等于绕过它们，志愿者会在没给定位权限的情况下把单接下来。
                // 闸拦住时用户看到的是「需要定位权限」这类可执行的提示，也是对的。
                //
                // 不弹「操作失败」就停：派单弹窗只有「有意向」和「拒绝」两个按钮，
                // 停在这里等于让志愿者卡在一个本该能接的单上（后端在那条 handoff 里点名要求别这样）。
                if allowsIntroCallUpgrade,
                   action == .interested,
                   error.errorCode == .introCallNotRequired {
                    respondToDispatch(
                        action: .accept,
                        currentLocation: currentLocation,
                        locationAuthorized: locationAuthorized,
                        allowsIntroCallUpgrade: false
                    )
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

    /// 只做「发出去」这一件事，成功后的刷新 / 收弹窗 / 播报都留在调用方 ——
    /// 409 兜底会把它调两次，而那些后处理只该跑一次。
    private func submitDispatchResponse(
        action: OrderRespondAction,
        order: WSNewOrder,
        appState: AppState,
        currentLocation: CLLocationCoordinate2D?,
        locationAuthorized: Bool
    ) async throws {
        if action == .accept {
            VolunteerLocationReporter.reportIfNeeded(
                appState: appState,
                currentLocation: currentLocation,
                locationAuthorized: locationAuthorized
            )
        }
        try await appState.orders.respond(orderId: order.orderId, action: action)
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

            // 跨天预约单单独一条（后端 `dispatch-summary` 拿不到它，见 `scheduledOrders` 的注释）。
            // 与另外两条并行，不串在后面 —— 首页已经有三次往返，再排一次会让面板多等一个 RTT。
            let orders = appState.orders
            async let scheduledResult: Result<PagedOrderResponse, Error> = Self.fetchResult {
                try await HomeLoadCoordinator.run(
                    timeout: self.loadTimeout,
                    operationName: "volunteer-scheduled-orders"
                ) {
                    try await orders.scheduledOrders()
                }
            }

            let (profile, registration, scheduled) = await (profileResult, registrationResult, scheduledResult)
            guard !Task.isCancelled, self.auxiliaryRequestID == requestID else { return }
            if case .success(let value) = profile {
                appState.updateVolunteerProfile(value)
                self.apply(profile: value)
            }
            if case .success(let value) = registration {
                appState.updateVolunteerRegistrationStatus(value)
            }
            self.applyScheduled(scheduled)
            self.auxiliaryLoadTask = nil
            self.auxiliaryRequestID = nil
        }
    }

    /// 拉取结果落进 `scheduledOrders`。
    ///
    /// 🚨 **失败时不清空已有列表**：预约区块上挂着一个 60 分钟到期的确认动作，
    /// 一次网络抖动把整块抹掉，志愿者就会以为那张单已经没了、不必再管它 ——
    /// 而后端那边计时照走。失败只留一句说明，列表保持上一次的内容。
    ///
    /// ⚠️ 服务端返回的顺序是 `createdAt` 倒序（`OrderController.getMyOrders` 写死的），
    /// 这里按 `plannedStart` 重排成升序：这一块回答的是「下一件事什么时候」，
    /// 不是「我什么时候接的单」。缺 `plannedStart` 的排最后而不是丢掉。
    private func applyScheduled(_ result: Result<PagedOrderResponse, Error>) {
        switch result {
        case .success(let page):
            scheduledOrders = page.content
                .filter { $0.status == .scheduledConfirmed }
                .sorted { ($0.plannedStart ?? "\u{FFFF}") < ($1.plannedStart ?? "\u{FFFF}") }
            scheduledOrdersMessage = nil
        case .failure:
            ClientFlowDiagnostics.record(event: "failed", operation: "volunteer-scheduled-orders")
            // 🚨 **列表空时也要说话。** 早先这里是 `guard !scheduledOrders.isEmpty else { return }`，
            // 于是首次加载失败时既不渲染区块、也不设提示 —— 志愿者看到的与「我没有预约单」
            // 一模一样，而他可能正有一张单在倒计时。判据是「这个失败态下屏幕上会**多**出什么」，
            // 当时的答案是「什么都不多」，那就是静默失败。
            scheduledOrdersMessage = scheduledOrders.isEmpty
                ? "预约列表没能加载，如果你有还没到时间的预约，请下拉刷新再看一次。"
                : "预约列表没能刷新，显示的是上一次的内容。"
        }
    }

    nonisolated private static func fetchResult<Value: Sendable>(
        operation: @escaping @Sendable () async throws -> Value
    ) async -> Result<Value, Error> {
        do { return .success(try await operation()) }
        catch { return .failure(error) }
    }

    /// 临期确认「我还会去」（`SCHEDULED_CONFIRMED → PENDING_ACCEPT`）。
    ///
    /// 🚩 **成功后必须把他带进服务页，不能只把卡片移除。**
    /// 确认之后订单是 `PENDING_ACCEPT`，而那一态**既不在预约列表里**（这个列表按
    /// `status=SCHEDULED_CONFIRMED` 拉）、**也不在「当前订单」里**（后端
    /// `VolunteerService.loadActiveOrders` 的白名单只有陪跑中那三态）⇒ 只移除卡片的话，
    /// 他刚确认完就在首页上再也找不到这一单，而下一步「我已出发」要靠他自己翻回去。
    ///
    /// 复用派单接单后那条既有的导航（`acceptedDispatchOrderId` + `navigationDestination`），
    /// 不另起一套：两者要去的是同一个页面、同一个状态。
    func confirmScheduledDeparture(orderID: Int64) async {
        let order = scheduledOrders.first { $0.orderId == orderID }
        let confirmed = await submitScheduled(
            orderID: orderID,
            successSpeech: "已确认，到时间请按约定前往。"
        ) { orders in
            try await orders.confirmDeparture(orderId: orderID)
        }
        guard confirmed else { return }
        // 带上手里这份详情当初值，服务页就不必空着等第一次 GET 回来。
        acceptedDispatchInitialOrder = order?.replacingStatus(with: .pendingAccept)
        acceptedDispatchOrderId = orderID
    }

    /// 「我去不了」（走取消端点，订单转 `REMATCHING` 回到派单池）。
    ///
    /// 与确认共用同一条提交路径，**刻意不做得更难** —— 释放做得难只会把 no-show 从
    /// 「提前告知」变成「当天失联」，那对盲人差得多（`docs/research/volunteer-scheduled-order-confirm-ui-20260906.md` §二.1）。
    /// 二次确认在 View 上（`confirmationDialog`），因为它不可逆：抢不回同一个盲人。
    func releaseScheduledOrder(orderID: Int64) async {
        // 🚩 **不说「会转给其他志愿者」**：后端 `enterRematching` 在重匹次数达上限时是直接
        // 置 `CANCELLED` 而不是重派（`OrderLifecycleService`），那时这句话就是假的。
        // 只说他自己那一半 —— 那一半永远为真。
        _ = await submitScheduled(orderID: orderID, successSpeech: "已经告诉系统你去不了，这一单不在你名下了。") { orders in
            try await orders.cancel(orderId: orderID)
        }
    }

    /// 两个动作共用的提交路径。返回**这次提交是不是真的成功了**（调用方据此决定要不要导航）。
    ///
    /// 成功与 409 都从列表移除：两种情况下这一单都不再是「待你确认的预约」。
    private func submitScheduled(
        orderID: Int64,
        successSpeech: String,
        operation: @escaping (any OrderServing) async throws -> Void
    ) async -> Bool {
        guard submittingScheduledOrderID == nil, let appState else { return false }
        submittingScheduledOrderID = orderID
        scheduledOrdersMessage = nil
        defer { submittingScheduledOrderID = nil }
        do {
            try await operation(appState.orders)
            scheduledOrders.removeAll { $0.orderId == orderID }
            speechService?.speak(successSpeech)
            return true
        } catch let error as APIError {
            if appState.handleAuthenticatedAPIError(error) { return false }
            // 409 `ORDER_STATUS_NOT_ALLOWED`：订单已经不在 `SCHEDULED_CONFIRMED` 上了。
            //
            // 🚨 **不许断言是哪一种。** 至少三种成因，客户端一个都分不出：
            // 闸门已经把它退回重新匹配、盲人取消了、以及**上一次其实已经提交成功**
            // （请求到了服务端、响应在回来的路上丢了，用户以为没成功又点了一次）。
            // 早先这里写死「这一单已经转给其他志愿者了」——在第三种情况下那是句假话，
            // 而且紧跟着把卡片删掉，他从此在首页上再也看不到一张仍在自己名下的单。
            // 现在这句话对三种成因**都为真**，且给出的下一步（不用再确认）也都对。
            if case .serverError(let response) = error, response.errorCode == .invalidOrderStatus {
                scheduledOrders.removeAll { $0.orderId == orderID }
                let message = "这一单的状态已经变了，不用再确认。可以到「近期服务」里看它现在怎么样。"
                scheduledOrdersMessage = message
                speechService?.speakError(message)
                return false
            }
            scheduledOrdersMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
            return false
        } catch {
            let message = "操作没有成功，请重试。"
            scheduledOrdersMessage = message
            speechService?.speakError(message)
            return false
        }
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

/// 志愿者首页这一屏的圆角档位。**四档各有语义，不是四个可以互换的数。**
///
/// 立这个表的起因：全 App 的 `cornerRadius` 实测有 10 个取值
/// （8×46 / 12×36 / 16×17 / 14×11 / 18×4 / 20·28·999×2 / 10·24×1），
/// 而同一屏上派单状态卡是 16、当前订单卡是 20、卡内小格是 12 —— 没有规律可循，
/// 下一个人加卡片时只能随手挑一个，于是取值继续发散。
///
/// ⛔ **作用域刻意只到这一屏。** 跨屏共用的 `IncentiveCard` / `IncentiveHeroCard` /
/// `PartnerRowCard` 都是 14，改它们会波及盲人端的固定搭档页 —— 那不在本次范围内，
/// 且纯视觉收敛没有任何测试守得住，改坏了不会有信号。要全 App 统一是另一件事。
enum VolunteerHomeRadius {
    /// 居中弹出的模态对话框（派单弹窗）。
    static let modal: CGFloat = 24
    /// 内容流里的每一张卡片。
    static let card: CGFloat = 16
    /// 卡片**内部**的元素：小格子、整行按钮、内嵌地图。
    /// 比外层小是为了套着好看，不是另一套体系。
    static let tile: CGFloat = 12
    /// 药丸形（「回到当前位置」按钮）。滑动 CTA 用 `Capsule()` 不走这里 ——
    /// 它的圆角恒等于自身高度的一半，而那个高度跟着 Dynamic Type 变。
    static let pill: CGFloat = 999
}

// MARK: - Volunteer Home View

/// 志愿者端的根视图。**它本身只剩三件事**：装第一屏、把可服务开关挂在底部、
/// 让派单弹窗盖住一切。内容全在 `VolunteerProfileFirstScreen` 与
/// `VolunteerDispatchWorkbenchView` 里。
///
/// > 2026-09-14 从「地图铺满 + 底部可拖面板」的叠层结构改成这样。原结构有两个硬伤：
/// > ① 那张底图 `annotations` 恒为 `[]`，只画「我在哪」，却占着整屏；
/// > ② 面板拖到 `.compact` 档时**整块内容不渲染**，志愿者的服务量、勋章、最近陪跑
/// >   随手一拖就全没了。设计稿与依据见
/// >   `docs/ui/mockups/volunteer-profile-first-screen-20260914/`。
struct VolunteerHomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @EnvironmentObject private var locationService: LocationService
    @StateObject private var viewModel = VolunteerHomeViewModel()

    var body: some View {
        NavigationStack {
            VolunteerProfileFirstScreen(viewModel: viewModel, onReload: loadHome)
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
                    availabilityCTA
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
        }
        // 🚩 **派单弹窗挂在 `NavigationStack` 外面。**
        //
        // 挂在栈内根视图上时，push 出任何二级页（派单工作台、服务记录、设置）之后
        // 弹窗会被那一页盖住 —— 而「派单工作台」正是志愿者等单时最可能停留的页面。
        // 模态是最高优先级：不管他在哪一页，30 秒倒计时都必须看得见。
        .overlay {
            if let incomingOrder = viewModel.incomingOrder {
                VolunteerDispatchOverlay(
                    order: incomingOrder,
                    countdown: viewModel.dispatchCountdown,
                    isResponding: viewModel.isRespondingToDispatch,
                    currentLocation: locationService.currentLocation,
                    locationAuthorized: locationService.isAuthorized,
                    fallbackCoordinate: locationService.effectiveBackendLocation,
                    // 主动作是「有意向，想先聊聊」还是「接单」，由推送里的
                    // `requiresIntroCall` 决定（`WSNewOrder.dispatchRespondAction`）。
                    // 🚨 这里**不做第二次判断** —— 判据在后端，客户端自己算必然漂移，
                    // 而漂移的表现是「界面说能直接接、后端回 409」。
                    onRespond: { action in
                        viewModel.respondToDispatch(
                            action: action,
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

    /// 底部的可服务开关。**它替代了原来那个 `Toggle`** —— 依据是 Uber Base
    /// Sliding button 的用途判据「引入摩擦以确认意图」，而「从这一刻起开始收派单」
    /// 正是一个有后果的动作（`docs/research/volunteer-profile-first-screen-20260914.md` §3）。
    private var availabilityCTA: some View {
        VolunteerAvailabilitySlider(
            isAvailable: viewModel.isAvailable,
            isEnabled: appState.isVolunteerProfileApproved,
            isUpdating: viewModel.isUpdatingAvailability,
            statusText: viewModel.statusText,
            onChange: { viewModel.setAvailability($0) }
        )
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.regularMaterial)
    }

    private func loadHome() async {
        await viewModel.load(
            currentLocation: locationService.currentLocation,
            locationAuthorized: locationService.isAuthorized
        )
    }
}

// MARK: - Dispatch Workbench

/// 派单工作台：覆盖范围、派单统计、必修培训，以及那张辅助地图。
///
/// 🚩 **它是二级页，不是首屏。** 地图上没有任何订单标注（`annotations: []`），
/// 它回答的只是「我在哪、覆盖到哪」—— 而 Strava / Nike Run Club / Be My Eyes
/// 无一把地图放在个人首屏（调研 §2.6）。派单来的那一单有自己的地图
/// （`VolunteerDispatchOverlay.dispatchMap`），不在这张底图上。
///
/// 🔴 **带到期动作的东西一律不在这里**：跨天预约的临期确认、当前订单入口都留在首屏。
/// 一个 60 分钟到期的动作藏在二级页等于没有（`volunteer-scheduled-order-confirm-ui-20260906.md` §二）。
struct VolunteerDispatchWorkbenchView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationService: LocationService
    @ObservedObject var viewModel: VolunteerHomeViewModel

    let onReload: () async -> Void

    @State private var recenterToken = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                mapCard

                if let summary = viewModel.dispatchSummary {
                    VolunteerDispatchSummaryCard(summary: summary)

                    // 「尚未通过资质认证」必须能一键到达上传页，否则志愿者看到提示也无处可去。
                    if summary.notAvailableReasons?.contains(.notVerified) == true {
                        VolunteerCertificateUploadEntryLink()
                    }
                } else if viewModel.isLoading {
                    EmptyStateView(
                        title: "派单状态待同步",
                        message: "正在后台同步；首屏的记录、成就和设置仍可使用。"
                    )
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
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(errorMessage)
                        Button("重试加载") {
                            Task { await onReload() }
                        }
                        .buttonStyle(.bordered)
                        .accessibilityHint("重新加载派单和当前订单状态")
                    }
                }

                Text(locationSummaryText)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(locationSummaryText)

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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .readableContentColumn()
        }
        .background(AppColors.background)
        .navigationTitle(VolunteerProfileCopy.workbenchTitle)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await onReload()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("volunteerDispatchWorkbench")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await onReload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("刷新派单状态")
                .accessibilityHint("重新加载系统派单工作台")
                .accessibilityIdentifier("volunteerHomeRefreshButton")
            }
        }
    }

    private var mapCard: some View {
        MapViewWrapper(
            centerCoordinate: locationService.effectiveBackendLocation,
            showsUserLocation: locationService.isAuthorized,
            // 志愿者走系统派单，不展示公开订单池，所以底图上没有订单标注。
            annotations: [],
            zoomLevel: 13,
            recenterToken: recenterToken,
            showsCompass: false
        )
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: VolunteerHomeRadius.card, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            recenterButton.padding(12)
        }
        // 位置和派单摘要已由下面的卡片完整朗读；地图使用稳定语义，
        // 避免 MAMapView 帧更新反复求值动态时间/覆盖文案。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("志愿者辅助地图")
        .accessibilityHint("地图用于视觉查看当前位置覆盖范围；下面的派单状态卡会读出当前位置和覆盖摘要")
        .accessibilityIdentifier("volunteerHomeMap")
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

    private var locationSummaryText: String {
        if locationService.isAuthorized {
            return "\(locationService.readableCurrentLocationSummary)\(viewModel.dispatchSummary?.coverageText ?? "派单覆盖范围待同步")"
        }
        return "需要开启定位权限才能接收系统派单"
    }
}

struct VolunteerCurrentOrderCard: View {
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
        .clipShape(RoundedRectangle(cornerRadius: VolunteerHomeRadius.card, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 5)
    }
}

private struct VolunteerDispatchSummaryCard: View {
    let summary: VolunteerDispatchSummaryResponse
    @State private var isTrainingSheetPresented = false

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
        // 外层 VStack 的存在理由：卡片本体要 `.combine` 成一个可听的整体，
        // 而「去培训」按钮必须留在那个整体之外才点得到。两者是兄弟节点，不是父子。
        VStack(alignment: .leading, spacing: 8) {
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

            // 列数跟着 `metrics` 走，不写字面量 —— `be4e030` 删掉「积分」那格时列数留在 4，
            // 于是三格挤在左边、右边空一格挂了很久。
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: metrics.count), spacing: 8) {
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
        .clipShape(RoundedRectangle(cornerRadius: VolunteerHomeRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        // 「积分 N」也从这条 label 里删掉 —— 数字从视觉上消失了，但读屏用户还在听，
        // 这一处最容易漏。
        .accessibilityLabel("派单状态：\(summary.dispatchStatusText)，\(summary.coverageText)，完成 \(summary.completedCount) 次，评分 \(summary.ratingText)")
        // 🚩 「去培训」按钮必须放在 `.accessibilityElement(children: .combine)` 的**外面**。
        //    塞进上面那个 VStack 里的话，combine 会把它并进一个不可操作的整体，
        //    VoiceOver 用户永远点不到它（同 `accessibility-identifier-overwrites-children`
        //    那类容器吃掉子元素的陷阱）。这也是为什么它是 `.overlay` 之后的兄弟节点而不是子节点。
        if needsTrainingEntry {
            trainingEntry
        }
        }
    }

    /// 只有「必修培训没完成」这一条原因才给按钮。
    ///
    /// 🚩 其余原因**刻意不给**：`OFFLINE` / `DISPATCH_DISABLED` 在这张卡的上方就有开关和
    /// 定位入口，再加一个按钮是噪音；`NOT_VERIFIED` 的去处是「我的 → 资质证书」，
    /// 那条今天没有按钮 —— 补它是另一件事，不夹带进这次改动。
    private var needsTrainingEntry: Bool {
        (summary.notAvailableReasons ?? []).contains(.trainingIncomplete)
    }

    /// 「为什么接不到单」和「去哪解决」必须在同一处。
    ///
    /// 🚩 只在卡片里写一句「尚未完成必修培训」而不给去处，就是装饰性提示：
    /// 志愿者读到了原因，却要自己猜去「我的」里翻。本仓库已经有过这个形状 ——
    /// `NOT_VERIFIED` 那条至今只有一行字。这次不复制它。
    private var trainingEntry: some View {
        Button {
            isTrainingSheetPresented = true
        } label: {
            HStack(spacing: 6) {
                Text("去培训")
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .accessibilityHidden(true)
            }
            .font(AppFonts.body().weight(.semibold))
            .foregroundColor(AppColors.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 44pt 是系统触达下限。志愿者端不受盲人端 64pt 线约束
            // （`guard.mjs` 的 `small-touch-target` 显式排除 /blindRun/Volunteer/）。
            .frame(minHeight: 44)  // guard:allow small-touch-target
            .padding(.horizontal, 14)
        }
        .accessibilityLabel("去培训")
        .accessibilityHint("打开陪跑培训，完成必修课程后即可接单")
        .accessibilityIdentifier("volunteerHomeTrainingEntry")
        // 用 sheet 而不是 NavigationLink：首页不保证处在 NavigationStack 里，
        // 而 sheet 自带一个 NavigationStack 就能让课程详情正常 push。
        .sheet(isPresented: $isTrainingSheetPresented) {
            NavigationStack {
                VolunteerTrainingView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("关闭") { isTrainingSheetPresented = false }
                        }
                    }
            }
        }
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
        .clipShape(RoundedRectangle(cornerRadius: VolunteerHomeRadius.tile, style: .continuous))
    }
}

/// 首页的「我的预约」区块 —— 跨天预约单（`SCHEDULED_CONFIRMED`）以及它们的临期确认动作。
///
/// **为什么它必须独立于「当前订单」和「近期服务」两块**：
/// - 与「当前订单」共用一个位会被即时单顶掉（见 `VolunteerHomeViewModel.scheduledOrders`）。
/// - 「近期服务」在语义上是历史（空态文案逐字是「完成服务后会显示在这里」），
///   而且只渲染 `prefix(3)`。把一个 60 分钟到期的待办混进历史列表，可发现性接近零。
///
/// 确认按钮直接摆在卡上、**不进二级页也不进溢出菜单** —— Rover 把改期藏进三点菜单、
/// 把接受放在会话线程里，是本轮调研里唯一被点名的反面教材。
struct VolunteerScheduledOrdersSection: View {
    let orders: [OrderDetailResponse]
    let submittingOrderID: Int64?
    let message: String?
    let onConfirm: (Int64) -> Void
    let onRelease: (Int64) -> Void

    /// 要释放的那一单。二次确认是因为释放不可逆 —— 订单回派单池，抢不回同一个盲人。
    @State private var pendingReleaseOrder: OrderDetailResponse?

    var body: some View {
        // `message` 非空时即使没有卡片也要渲染：加载失败而列表恰好为空是最需要说话的一刻，
        // 只按 `orders.isEmpty` 判会让那条提示无处可去（见 `applyScheduled` 的失败分支）。
        if !orders.isEmpty || message != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("我的预约")
                    .font(AppFonts.body().weight(.bold))
                    .foregroundColor(AppColors.textPrimary)

                if let message {
                    Text(message)
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(message)
                }

                ForEach(orders) { order in
                    card(order)
                }
            }
            .confirmationDialog(
                "确认去不了？",
                isPresented: Binding(
                    get: { pendingReleaseOrder != nil },
                    set: { if !$0 { pendingReleaseOrder = nil } }
                ),
                presenting: pendingReleaseOrder
            ) { order in
                Button("确认去不了", role: .destructive) { onRelease(order.orderId) }
                Button("再想想", role: .cancel) {}
            } message: { _ in
                Text("这一单会转给其他志愿者，之后不一定还能接回来。")
            }
        }
    }

    /// 一张预约卡。整块 `children: .contain` —— 容器上的无障碍设置会向下盖掉子元素，
    /// 而这张卡上的两个按钮必须各自可被读屏聚焦、也必须能被 UI 测试分别找到。
    private func card(_ order: OrderDetailResponse) -> some View {
        let isSubmitting = submittingOrderID == order.orderId
        let anySubmitting = submittingOrderID != nil
        return VStack(alignment: .leading, spacing: 10) {
            // 缺 `plannedStart` 时给一句话而不是空串：这一行是整张卡最重要的内容
            // （「什么时候」就是这一态的全部），空 `Text` 对读屏用户等于这张卡没有时间。
            Text(order.plannedStart?.nilIfBlank?.displayDateTime ?? "开跑时间待同步")
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(order.blindName ?? "盲人跑者") · \(order.startAddress ?? "出发地待同步")")
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // 竖直堆叠而不是并排：对标产品无一把两个动作并排放
            // （`blind-ui-visual-benchmark-20260808.md`「次级操作一律整行铺满竖直堆叠」），
            // 而且并排会让每个按钮的可点宽度减半，AX5 下文字直接被压成省略号。
            PrimaryButton(
                VolunteerServiceActionKind.confirmDeparture.title,
                isLoading: isSubmitting,
                action: { onConfirm(order.orderId) }
            )
            .disabled(anySubmitting)
            .accessibilityLabel(VolunteerServiceActionKind.confirmDeparture.title)
            .accessibilityHint("告诉跑者你仍然会来。不确认这一单会转给其他志愿者")
            .accessibilityIdentifier("volunteerScheduledConfirm-\(order.orderId)")

            Button(role: .destructive) {
                pendingReleaseOrder = order
            } label: {
                Text(VolunteerServiceActionKind.releaseScheduled.title)
                    .font(AppFonts.body().weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .background(AppColors.destructive.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: VolunteerHomeRadius.tile, style: .continuous))
            }
            .disabled(anySubmitting)
            .accessibilityLabel(VolunteerServiceActionKind.releaseScheduled.title)
            .accessibilityHint("这一单会转给其他志愿者，需要确认后释放")
            .accessibilityIdentifier("volunteerScheduledRelease-\(order.orderId)")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: VolunteerHomeRadius.card, style: .continuous))
        .accessibilityElement(children: .contain)
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
    let onRespond: (OrderRespondAction) -> Void
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
                            .clipShape(RoundedRectangle(cornerRadius: VolunteerHomeRadius.tile))
                    }
                    .disabled(isResponding)
                    .accessibilityLabel("拒绝订单")
                    .accessibilityHint("拒绝此次派单")

                    primaryActionButton
                }

                if isResponding {
                    ProgressView("正在响应...")
                        .accessibilityLabel("正在提交响应")
                }
            }
            .padding(24)
            .background(AppColors.background)
            .clipShape(RoundedRectangle(cornerRadius: VolunteerHomeRadius.modal, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 24)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("新订单派单通知，剩余\(countdown)秒")
    }

    /// 主动作按钮。「先聊聊」还是「直接接单」由 `WSNewOrder.requiresIntroCall` 决定。
    ///
    /// 🚩 `requiresIntroCall == false` 的三种成因（通话功能整体关闭 / 这两人已磨合成功过 /
    /// 距开跑已不够聊一轮）客户端**分不出来**，所以「接单」这一支的文案不解释原因 ——
    /// 写任何一种都可能是错的。措辞沿用通话磨合上线前的原实现，不新造一套说法。
    @ViewBuilder
    private var primaryActionButton: some View {
        let action = order.dispatchRespondAction
        let needsIntroCall = action == .interested
        Button {
            onRespond(action)
        } label: {
            Text(needsIntroCall ? "有意向，想先聊聊" : "接单")
                .font(AppFonts.body().weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(AppColors.primary)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: VolunteerHomeRadius.tile))
        }
        .disabled(isResponding)
        .accessibilityLabel(needsIntroCall ? "有意向，想先聊聊" : "接受订单")
        // 「先聊聊」那一支要说清**还不是接单**：把 INTERESTED 当成接单的人会以为事情定了，
        // 然后错过跑者那通电话 —— 而 20 分钟窗口过了这一单就换人了。
        .accessibilityHint(
            needsIntroCall
                ? "先锁定这一单并等跑者打电话给你，聊完双方都说合适才算接单"
                : "接受此次派单并进入服务流程"
        )
        .accessibilityIdentifier(
            needsIntroCall ? "volunteerDispatchInterestedButton" : "volunteerDispatchAcceptButton"
        )
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
        .clipShape(RoundedRectangle(cornerRadius: VolunteerHomeRadius.tile, style: .continuous))
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
