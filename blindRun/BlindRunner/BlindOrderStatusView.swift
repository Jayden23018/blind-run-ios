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
    /// 通话磨合页数据。`nil` = 这一单不在 `PENDING_INTRO_CALL`，或者这一轮已经结束，
    /// **或者这一轮的数据拉失败了** —— 后者由 `introCallUnavailable` 区分。
    ///
    /// 🚨 它里面**没有对方的表态、也没有轮次进度**，而且不许在客户端补算出来
    /// （见 `IntroCallView` 的类型注释）。
    @Published private(set) var introCall: IntroCallView?
    /// 处在 `PENDING_INTRO_CALL` 但通话数据**拉不到**。
    ///
    /// 存在的理由是一个真实缺陷：`introCall == nil` 此前同时代表「不在通话态」和
    /// 「拉失败了」，而通话区靠 `let introCall` 拆包 ⇒ 拉失败时
    /// 拨号 / 合适 / 换一位三个按钮**一个都不渲染**，没有错误文字、没有播报，
    /// 而状态播报仍在说「有位志愿者想陪你跑，可以打个电话聊聊」。
    /// 对看不见屏幕的人，那是被告知去做一件屏幕上根本没有入口的事。
    ///
    /// **不复用 `errorMessage`**：`loadOrder` 每一轮开头都会把它清空（见那里），
    /// 而这个状态要跨轮活着。理由与 `statusLogsErrorMessage` 同源。
    @Published private(set) var introCallUnavailable = false
    /// 这一轮我**已经提交过**的表态。`nil` = 还没表态。
    ///
    /// 🚨 它的作用只有一个：**表过态之后，「拉不到通话数据」就不再算失败。**
    /// 表态已经被服务端记下了，再拉不到 view 也不改变这个事实。
    /// 没有它，用户刚听完「已经告诉系统你觉得合适」就会被「暂时拿不到通话信息」盖掉，
    /// 而屏幕上还会冒出一个「换一位」—— 他刚说完合适，那个按钮在那一刻是危险的。
    /// （`submitIntroCallDecision` 成功后紧接着就 `loadOrder`，这条路每次都会走到。）
    ///
    /// 🚩 **服务端说了话就以它为准**：每次成功拉到 view 都用 `myDecisionValue` 覆盖它。
    /// 换了候选人时后端回的 `myDecision` 是 nil，本地这个记号必须跟着作废 ——
    /// 否则新一轮一开局就显示成「正在等对方」，而用户其实还没打那通电话。
    /// 本地只是在**拉不到的时候**替服务端记着，不是另一个真相来源。
    @Published private(set) var submittedIntroCallDecision: IntroCallDecision?

    /// 我已经说过「合适」，正在等对方。
    ///
    /// 表过态之后**不依赖再拉一次 view** 才知道这件事 —— 那正是上面那个记号存在的理由。
    var isWaitingForIntroCallCounterpart: Bool {
        submittedIntroCallDecision == .accept || introCall?.isWaitingForCounterpart == true
    }

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
            try await appState.orders.keepWaiting(endpoint, orderId: order.orderId)
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

    // MARK: - 接单前通话磨合

    /// 拉通话页数据。跟着订单轮询走，不另起一条定时器 —— 这一页本来就每 5 秒刷一次订单。
    ///
    /// **拿不到仍然清空 `introCall`，但必须同时立起 `introCallUnavailable`。**
    ///
    /// 清空是对的，别改成「保留上一轮的号码」：同一个 `PENDING_INTRO_CALL` 里候选人是会换的
    /// （后端 `INTRO_CALL_NOT_ACTIVE` 的说明逐字写着「本轮候选人已换人」），
    /// 留着旧号码就会把电话打给上一位候选人 —— 而屏幕上看不出任何异常。
    ///
    /// 🚨 缺的从来不是「保留数据」，是**说出来**。原来这里是 `try?`，失败与
    /// 「不在通话态」塌缩成同一个 `nil`，于是整块操作区静默消失。
    private func refreshIntroCallIfNeeded(for order: OrderDetailResponse, appState: AppState) async {
        guard order.status == .pendingIntroCall else {
            clearIntroCallState()
            return
        }
        do {
            let view = try await appState.orders.introCallView(orderId: order.orderId)
            introCall = view
            introCallUnavailable = false
            // 服务端说了话就以它为准。换了候选人时它是 nil，本地记号跟着作废 ——
            // 见 `submittedIntroCallDecision` 的注释。
            submittedIntroCallDecision = view.myDecisionValue
        } catch {
            introCall = nil
            // 🚩 **已经表过态就不算失败。** 表态服务端已经记下了，拉不到 view 不改变这件事，
            // 而此刻用户没有任何该做而做不了的事 —— 报错只会盖掉他刚听到的确认，
            // 并在屏幕上摆出一个他不该在这一刻碰到的「换一位」。
            guard submittedIntroCallDecision == nil else { return }
            // **只在 false → true 那一跳播一次。** `loadOrder` 每 5 秒重跑一遍，
            // 每轮都播会把读屏用户淹掉 —— 而他要听的是「这次没拿到，可以重试」，
            // 不是同一句话每 5 秒一遍。
            if !introCallUnavailable {
                introCallUnavailable = true
                speechService?.speakError(IntroCallCopy.loadFailed)
            }
        }
    }

    /// 离开通话态、或换单时把这一族状态整组清掉。**三个字段必须一起动** ——
    /// 少清一个就会让下一单一进通话态就顶着上一单的错误块或表态。
    private func clearIntroCallState() {
        introCall = nil
        introCallUnavailable = false
        submittedIntroCallDecision = nil
    }

    /// 「重新加载」按下时走这里。也是单测的入口：正常路径下通话数据跟着订单轮询一起拉，
    /// 而用例要的是「只拉这一次」—— 起轮询会顺带打订单详情、动状态机，
    /// 把断言埋进一堆无关请求里。
    ///
    /// 2026-08-26 从 `#if DEBUG` 的 `loadIntroCallForTesting` 提成正式方法：
    /// 失败态那个「重新加载」按钮要的正是同一件事，没有理由再留一个只给测试的孪生入口。
    func reloadIntroCall() async {
        guard let order, let appState else { return }
        await refreshIntroCallIfNeeded(for: order, appState: appState)
    }

    /// 先通知对方，然后**立刻**回拨号 URL 给调用方。
    ///
    /// 🚨 **不等响应**：对盲人来说「点了没反应」是最糟的反馈。APNs 到达与对方手机响铃之间
    /// 本就有几秒差，时序天然对得上；推送晚到还有派单文案兜底
    /// （后端 `notify-incoming` 的端点说明逐字写着这一条）。
    ///
    /// 🚨 返回的号码**只能**来自 `dialableCounterpartPhone`。掩码串拼进 `tel:` 会被
    /// `EmergencyDialer.telURL` 取成 `1381234` 拨出去 —— 空号，而界面上看不出任何异常。
    func introCallDialURL() -> URL? {
        guard let order, let appState, let phone = introCall?.dialableCounterpartPhone else { return nil }
        let orders = appState.orders
        let orderId = order.orderId
        Task {
            // 唯一一处刻意吞掉的错误，理由在上面：这是给对方的一条**预告推送**，
            // 不是拨号的前置条件。它失败时用户该做的事（打这通电话）没有任何变化，
            // 屏幕上也不该多出任何东西 —— 拨号 URL 已经返回，电话照打。
            try? await orders.notifyIntroCallIncoming(orderId: orderId)
        }
        return EmergencyDialer.telURL(for: phone)
    }

    /// 通话后的表态。`.accept` = 合适；`.decline` = 换一位。
    ///
    /// ⚠️ 请求体**没有 reason 字段**，这是后端刻意的：要求填理由等于要求当面说「不」。
    /// 成功后不改本地状态 —— 订单是不是转 `PENDING_ACCEPT` 取决于对方，而我们拿不到对方的表态。
    /// 让 5 秒轮询把真实状态带回来。
    func submitIntroCallDecision(_ decision: IntroCallDecision) async {
        guard let order, let appState else { return }
        isPerformingAction = true
        errorMessage = nil
        do {
            try await appState.orders.submitIntroCallDecision(decision, orderId: order.orderId)
            isPerformingAction = false
            // 先落本地记号，再刷订单 —— `loadOrder` 紧接着就会去拉通话数据，
            // 而那一步拉失败时要靠这个记号判「已经表过态，不算失败」。
            // 顺带把失败态收掉：用户是从失败块里按的「换一位」时，那个块该消失了。
            submittedIntroCallDecision = decision
            introCallUnavailable = false
            switch decision {
            case .accept:
                speechService?.speak(IntroCallCopy.waitingForCounterpart)
            case .decline:
                // 🚨 中性、进行时，与常规等待读起来完全一样：不许出现「重新」「换了一位」
                // 这类暗示前面失败过的措辞（无声拒绝）。
                speechService?.speak(IntroCallCopy.continuedSearch)
            }
            await loadOrder(orderId: order.orderId, speakChanges: false)
        } catch let error as APIError {
            isPerformingAction = false
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
            // 409 `INTRO_CALL_NOT_ACTIVE` 的常见成因是窗口已经超时。刷订单让页面回到真实状态，
            // 不重试 —— 重试只会得到同一个 409。
            await loadOrder(orderId: order.orderId, speakChanges: true)
        } catch {
            isPerformingAction = false
            let message = "没有提交成功，请再试一次。"
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
            try await appState.orders.cancel(orderId: order.orderId)
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
            safety: appState.safety,
            locate: { await self.freshEmergencyCoordinate() },
            locationFailureReason: { self.locationService?.locationError }
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
        let outcome = await appState.emergencyCoordinator.cancelByOwner(safety: appState.safety)
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
            try await appState.orders.submitReview(request, orderId: order.orderId)
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
            let envelope = try await appState.orders.reviews(orderId: order.orderId)
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
            let logs = try await appState.orders.statusLogs(orderId: order.orderId)
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
            apply(updated, speakChanges: speakChanges)
            await refreshIntroCallIfNeeded(for: updated, appState: appState)
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
                text: statusChangeAnnouncement(from: previousStatus, to: updated)
            )
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
    }

    /// 状态推进时该播哪一句。除了一处例外，都是 `blindRunnerAnnouncement`。
    ///
    /// 例外是**通话没聊成、退回派单队列**。两个落点各自的常规播报在这一刻都是错的：
    /// - `PENDING_MATCH` 念「订单提交成功，系统正在为你派单」—— 订单是二十分钟前提交的。
    /// - `REMATCHING` 念「正在确认志愿者状态，请稍候」—— 这一刻**没有志愿者可确认**，
    ///   刚才那位候选人从来就没接过单。
    ///
    /// 后端为这条转移专门发了 `INTRO_CALL_CONTINUE`（正文「正在为你寻找合适的陪跑伙伴」），
    /// 两个落点逐字复用它 —— 后端也**刻意**对两种状态发同一条中性文案，不为 `REMATCHING` 另开一条。
    ///
    /// ⚠️ `REMATCHING` 这个落点是 2026-08-26 后端修 P0（N105）之后才有的：通话退出改成回
    /// 「进通话之前那个状态」，而进通话之前它可能就是 `REMATCHING`。
    ///
    /// 🚨 措辞里不许出现「重新」「换一位」「再找一位」这类暗示前面失败过的词：
    /// 无声拒绝的全部要求就是盲人无从得知自己被谁拒过。
    private func statusChangeAnnouncement(
        from previousStatus: RunOrderStatus?,
        to updated: OrderDetailResponse
    ) -> String {
        if previousStatus == .pendingIntroCall,
           updated.status == .pendingMatch || updated.status == .rematching {
            return IntroCallCopy.continuedSearch
        }
        return updated.blindRunnerAnnouncement(distanceText: volunteerDistanceToStartText)
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

    /// 🚩 判据是 `fetchesVolunteerLocation`（后端 `sharesLiveLocation()` 那三态），
    /// **不是** `offersVolunteerDistanceToStart`（念不念距离那两态）。两者 2026-08-31 拆开，
    /// 拆之前这里用后者，于是 `PENDING_ACCEPT` 每 5 秒白调一次、`IN_PROGRESS` 一次都不调 ——
    /// 而 `IN_PROGRESS` 正是走散检测唯一需要兜底的那一段。
    private func refreshVolunteerLocationFallbackIfNeeded(for order: OrderDetailResponse, appState: AppState) async {
        guard order.status.fetchesVolunteerLocation else { return }
        let websocketSampleIsFresh = latestVolunteerWebSocketDate.map { Date().timeIntervalSince($0) <= 15 } ?? false
        guard !appState.isWebSocketConnected || !websocketSampleIsFresh else { return }

        do {
            let response = try await appState.orders.volunteerLocation()
            guard let coordinate = Self.volunteerFallbackCoordinate(from: response.data, matching: order) else { return }
            latestVolunteerCoordinate = coordinate
            refreshVolunteerDistance()
            feedEscortPeerLocation(from: response.data, coordinate: coordinate, order: order, appState: appState)
        } catch {
            // 订单轮询才是权威源，兜底拿不到位置不致命 —— 所以这里既不清空已知位置，也不播报。
            //
            // **404 尤其不是错误**：位置 key 不存在（志愿者超过 TTL 没上报）后端就返 404，
            // 契约明写「这是正常情况，客户端应静默保持上一个已知位置，别念报错」
            // （`api_spec.yaml:2365-2366`）。对盲人来说，陪跑途中每隔几秒念一次
            // 「获取位置失败」既没有可执行的动作，又会占住他用来听环境和陪跑员说话的通道。
        }
    }

    /// 把兜底坐标喂给走散检测（`LiveEscortSessionCoordinator` 只读
    /// `AppRealtimeCoordinator` 的对方样本存量，没有自己的 REST 兜底）。
    ///
    /// 🚩 **与上面那句 `latestVolunteerCoordinate = coordinate` 是两件事，故意分开写：**
    ///
    /// | | 念距离（上面那条） | 走散检测（这一条） |
    /// |---|---|---|
    /// | 问的是 | 屏幕上/播报里那个数字 | 两个人还在不在一起 |
    /// | `updatedAt` 缺失 | **放行**（`volunteerFallbackCoordinate` 的既有口径，失败开放） | **不喂** |
    /// | 新鲜度 | 30 秒（后端 Redis TTL） | 15 秒（`peerFreshness`，由 coordinator 判） |
    ///
    /// 缺 `updatedAt` 时不喂，是因为这一条唯一能凑的替代值是「现在」——
    /// 那会让一个 29 秒前的坐标伪装成刚采的，把「已经走散了」演成「一切正常」。
    /// 念距离那条允许缺失是相反方向的选择：那里拦一次的后果只是数字不出现，
    /// 而这条链路已经因为两道失败闭合的闸各坏过一次（见 `volunteerFallbackCoordinate`）。
    private func feedEscortPeerLocation(
        from data: VolunteerLocationData?,
        coordinate: CLLocationCoordinate2D,
        order: OrderDetailResponse,
        appState: AppState
    ) {
        guard let capturedAtMilliseconds = data?.updatedAt else { return }
        appState.realtimeCoordinator.ingestFallbackPeerLocation(
            RealtimePeerLocationSample(
                orderId: order.orderId,
                ownerRole: .volunteer,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                timestampMilliseconds: capturedAtMilliseconds
            )
        )
    }

    /// 志愿者位置 REST 兜底的新鲜度阈值。与后端 Redis `vol:loc:{id}` 的 TTL
    /// （`app.volunteer.location-ttl-seconds`）取同一个数：key 还在 ⇒ 志愿者这么久内上报过。
    static let volunteerFallbackFreshness: TimeInterval = 30

    /// REST 兜底拿到的坐标能不能采信。抽成静态方法只为**可测** —— 唯一调用点埋在 async 网络分支里。
    ///
    /// **这个方法只做一件事：判坐标能不能用。它的每一道闸都必须失败开放**，因为它拦掉一次
    /// 的后果不是「显示旧值」而是「『志愿者距出发地点约 X』整个不出现，且没有任何日志」——
    /// 这条链路已经因为两道失败闭合的闸各坏过一次：
    ///
    /// - `updatedAt` 曾是 `String?` + `ISO8601DateFormatter`，而后端当时**压根不发这个字段**
    ///   ⇒ `flatMap` 恒 nil ⇒ 恒 return。对真实后端 100% 静默失效，而 Mock 自己造了一个
    ///   `updatedAt`，于是开发期永远看不到。
    /// - `status` 曾因后端键名是 `orderStatus` 而恒为 nil，那条比较从未真正执行过。
    ///
    /// 两个字段都在 2026-08-20（后端 `119c810`）对齐了，所以两道闸会**第一次真的开始工作** ——
    /// 这正是最危险的时刻：把它们原样留着，等于在这一刻新增两条能否掉坐标的分支，
    /// 而失败表现与它们各自修的那个 bug 一模一样。因此：
    ///
    /// 1. **`status` 不再参与判定。** 契约原话：「拿它做交叉校验时应『不一致以本条为准并刷新订单』，
    ///    **不要用它否掉坐标** —— 坐标是这个端点存在的唯一理由」（`api_spec.yaml:2355-2357`）。
    ///    不一致时也不额外发一次刷新请求：本方法由 `loadOrder` 调用，递归回去会死循环；
    ///    而订单本来就 5 秒轮询一次（`AppConstants.Timing.orderPollingInterval`），
    ///    最多晚一轮就拿到权威状态。多一条立即刷新路径的风险大于那 5 秒。
    /// 2. **`updatedAt` 缺失一律放行**，只在它真的有值时判新鲜度。后端 2026-08-20 才补上这个字段，
    ///    生产未必已部署 —— 失败闭合就会原地重演上面第一条。
    /// 3. 时间戳落在**未来**（设备时钟偏差）按「刚采样」处理，不因此丢坐标。与 WebSocket 那条
    ///    `handleVolunteerLocationUpdate` 的 `max(0, ...)` 口径一致。
    static func volunteerFallbackCoordinate(
        from data: VolunteerLocationData?,
        matching order: OrderDetailResponse,
        now: Date = Date()
    ) -> CLLocationCoordinate2D? {
        guard let data,
              data.coordinateIsValid,
              data.orderId == nil || data.orderId == order.orderId,
              let lat = data.lat,
              let lng = data.lng else { return nil }
        if let updatedAt = data.updatedAt {
            let capturedAt = Date(timeIntervalSince1970: TimeInterval(updatedAt) / 1_000)
            let age = max(0, now.timeIntervalSince(capturedAt))
            guard age <= volunteerFallbackFreshness else { return nil }
        }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    // MARK: - Mock 环境的对家代打

#if DEBUG
    /// Mock 状态测试面板上那几个按钮代表的一步。志愿者那半边在单设备上凑不齐，
    /// 由这一组按钮代打。
    enum MockCounterpartStep {
        case respond(OrderRespondAction)
        /// 跨天预约单的临期确认。志愿者那半边在单设备上凑不齐，由这个按钮代打 ——
        /// 不做的话 `SCHEDULED_CONFIRMED` 之后的整条链路在 Mock 里根本走不下去。
        case confirmDeparture
        case enRoute
        case arrived
        case startService
        case finish
    }

    /// 代对方角色推进一次状态机（`.mock` 环境专用，调用点自己判环境）。
    ///
    /// 🚨 **失败必须说出来。** 这段原来是 6 个 `try?`，散在 view body 里：
    /// 从 `PENDING_ACCEPT` 直接打 `/arrived` 会被 Mock 按真实状态机拒掉，
    /// 而 `try?` 把拒绝吞成静默，现象是「点了没反应」，后续依赖 `DRIVER_ARRIVED`
    /// 的「模拟服务开始」永不出现 —— 排查时看不出是被拒了还是按钮没接上。
    func runMockCounterpartSteps(_ steps: [MockCounterpartStep], orderId: Int64) async {
        guard let appState else { return }
        let orders = appState.orders
        do {
            for step in steps {
                switch step {
                case .respond(let action):
                    try await orders.respond(orderId: orderId, action: action)
                case .confirmDeparture:
                    try await orders.confirmDeparture(orderId: orderId)
                case .enRoute:
                    try await orders.enRoute(orderId: orderId)
                case .arrived:
                    try await orders.arrived(orderId: orderId)
                case .startService:
                    try await orders.startService(orderId: orderId)
                case .finish:
                    try await orders.finish(orderId: orderId)
                }
            }
            errorMessage = nil
        } catch let error as APIError {
            errorMessage = "Mock 状态测试失败：\(error.localizedMessage)"
        } catch {
            errorMessage = "Mock 状态测试失败。"
        }
        startPolling(orderId: orderId)
    }
#endif

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
    @StateObject private var shareViewModel = RunPlanLiveShareViewModel()
    @State private var showEmergencyConfirmation = false
    @State private var showEmergencyCancelConfirmation = false
    @State private var showCancelConfirmation = false
    @State private var showStatusLogs = false
    @State private var showRunPlanShare = false
    @State private var showLiveShareConsent = false
    @State private var showLiveShareConfirmation = false
    /// 通话页什么时候弹出来。整个通话流程在 `BlindIntroCallView` 里，这一页只管呈现时机 ——
    /// 转移规则（关过一次不再弹、离开通话态复位）在 `BlindIntroCallPresentation` 上，
    /// 连同它们各自防的那个缺陷一起。
    @State private var introCallPresentation = BlindIntroCallPresentation()
    /// 状态推进后把 VoiceOver 焦点接到状态卡上。
    ///
    /// 这一页每 5 秒轮询一次，重绘时焦点会被系统收走，落点不确定 —— 而状态卡恰恰是
    /// 盲人此刻在等的那一条。已经有 `speakStatusChange` 在播报了，焦点不跟过来的话
    /// 两条通道就分家：听到「志愿者已到达」，抬手一滑却还在旧位置。
    ///
    /// 只在 `status` **真的变了**时移（含首次加载的 nil → 有值），不是每次轮询都移 ——
    /// 后者会把正在读订单信息的用户反复弹回顶部。
    @AccessibilityFocusState private var statusHeaderFocused: Bool
    let orderId: Int64
    let onOrderUpdated: (OrderDetailResponse) -> Void

    /// 主按钮高度。比首页的 280 小：这一页顶上还有状态卡要占位置，
    /// 而状态本身也是盲人此刻需要的信息，不能被按钮挤出首屏。
    ///
    /// 2026-09-05 起**只剩「打电话给志愿者」用它**。「继续等待」原先共用这个高度，
    /// 已降级为 64pt 的次级按钮 —— 见 `keepWaitingSection`。
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
                    // 顺序即优先级：状态（一句话 + 一个数字）→ 这一态唯一的主动作 →
                    // 同一态的次级动作 → 附属动作 → 其余全部下沉。此前主动作排在第 4 位，
                    // 读屏要滑过状态卡、地图、生命周期卡才够得着。
                    //
                    // `actionSection` 2026-08-19 从第 8 位提到这里：它装的是**这一态的
                    // 状态机动作**（等待中取消、终态返回首页），与上面的主动作同族；
                    // 而「把行程告诉家人」是附属动作 —— 跑不跑得成与它无关。
                    // 排在附属动作后面的直接后果：延长次数用完的 `REMATCHING`
                    // 主动作版位是空的，于是首屏第一个能按的东西是分享，
                    // 而此刻用户唯一还能做的决定是「要不要取消」。
                    statusHeader(order)
                        .accessibilityFocused($statusHeaderFocused)
                    introCallEntrySection(order)
                    volunteerCallSection(order)
                    inlineAskQuestionSection
                    keepWaitingSection(order)
                    actionSection(order)
                    runPlanShareSection(order)
                    peerMapSection(order)
                    lifecycleSection(order)
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
            // 这一页在 iPad 上最吃亏：状态卡、生命周期、订单信息全是长文本行，
            // 不限宽时一行横跨 1024pt。见 `BlindLayout.readableContentWidth`。
            .readableContentColumn()
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
                    shareViewModel.note(RunPlanShareCopy.sent, isProblem: false)
                case .cancelled:
                    shareViewModel.note(RunPlanShareCopy.cancelled, isProblem: false)
                case .failed:
                    shareViewModel.note(RunPlanShareCopy.failed, isProblem: true)
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
                    Task { await shareViewModel.startLiveShare() }
                },
                onDecline: {
                    showLiveShareConsent = false
                    shareViewModel.note(RunPlanShareConsentCopy.declined, isProblem: false)
                }
            )
        }
        .alert(RunPlanShareConsentCopy.repeatConfirmationTitle, isPresented: $showLiveShareConfirmation) {
            Button(RunPlanShareConsentCopy.agreeButtonTitle) {
                Task { await shareViewModel.startLiveShare() }
            }
            Button(RunPlanShareConsentCopy.declineButtonTitle, role: .cancel) {
                shareViewModel.note(RunPlanShareConsentCopy.declined, isProblem: false)
            }
        } message: {
            Text(RunPlanShareConsentCopy.repeatConfirmationMessage)
        }
        .sheet(item: $shareViewModel.payload) { payload in
            ShareLinkSheet(text: payload.text) {
                shareViewModel.payload = nil
                // 面板关掉不改变任何事实：链接在服务端已经生效，选没选目标应用都一样在分享中。
                shareViewModel.note(RunPlanLiveShareCopy.panelDismissed, isProblem: false)
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
            shareViewModel.configure(
                appState: appState,
                speechService: speechService,
                orderId: orderId
            )
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
        .onChange(of: viewModel.order?.status) { status in
            guard let status else { return }
            statusHeaderFocused = true
            introCallPresentation.apply(status: status)
        }
        // 全屏，不是 sheet：这一态盲人只有一件该做的事，而 sheet 会把订单页的内容
        // 留在下缘可见、可被 VoiceOver 滑到 —— 那正是这次要解决的问题。
        // 关闭只走「返回订单」按钮（`fullScreenCover` 本来就不能下滑关掉），
        // 于是「用户主动关过」这个事实能被可靠地记下来，不会与「系统因状态变化收起」混淆。
        .fullScreenCover(isPresented: $introCallPresentation.isShowing) {
            BlindIntroCallView(viewModel: viewModel) {
                introCallPresentation.dismiss()
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

            // 还在等人时，这一格是「已等待 12 分钟」；有志愿者了换成距离；跑起来了换成
            // 约定结束时间。三者状态集互不相交（`offersWaitedDuration` 的注释里有理由），
            // 所以卡上任何时刻只有一个数字。
            if let waitedText = order.blindRunnerWaitedText() {
                Text(waitedText)
                    .font(.title.bold())
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
            }

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
        if let waitedText = order.blindRunnerWaitedText() {
            parts.append(waitedText)
        }
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
        case .tracking, .inService, .terminal:
            // 这三条分支此前各渲染一张「标题 + 正文」卡片，正文都与 `statusHeader` 重复：
            //   · `DRIVER_ARRIVED` 的 `arrivedWaitingCopy` **就是**它的 `blindRunnerDescription`
            //     （`OrderDisplayHelpers.swift:77` 直接 return 了它）—— 逐字重复
            //   · `IN_PROGRESS` 那句「请与志愿者保持沟通，注意安全。系统会持续同步订单状态，
            //     服务完成后进入评价页面。」33 个字里没有一个能让盲人做出动作：
            //     「持续同步订单状态」是实现细节，「完成后进入评价页面」是还没发生的事
            //   · `.terminal` 的 `terminalSection`（2026-08-19 并进来）整张卡就是
            //     `Text(status.displayName)` + `Text(status.blindRunnerDescription)`，
            //     与 `statusHeader` **逐字**是同两句 —— 已取消 / 暂无志愿者的人把
            //     「本次预约已取消」听两遍，中间还隔着一次滑动
            // 读屏用户为此要多滑一次、把同一件事听两遍。状态语义由 `statusHeader` 一处承担。
            EmptyView()
        case .completion:
            completionRatingSection(order)
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
                .frame(minHeight: 64)
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
                // 隐藏走 `isDecorative`，不是在外层加 `.accessibilityHidden(true)` ——
                // 后者在真 key 构建下盖不住 `MapViewWrapper` 自己合成的那个元素
                // （2026-08-22 在盲人首页实测，见 `MapViewWrapper.isDecorative` 的说明）。
                // 这一页同样是「地图是装饰、列表才是界面」，所以同一个洞在这里也开着。
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
                    tracksUserLocation: false,
                    isDecorative: true
                )
                .decorativeMapHeight(180)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .allowsHitTesting(false)
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
                EmergencyDialer.dial(telURL)
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

    /// 进通话页的入口。通话本身整个在 `BlindIntroCallView` 里，这里只有一个按钮。
    ///
    /// 🚩 **它不能因为「反正会自动弹」而省掉。** 自动弹出只发生在 `status` **变化**那一跳，
    /// 而用户按过「返回订单」之后本轮就不再自动弹（`BlindIntroCallPresentation`）——
    /// 没有这个按钮，他此刻回不去了：状态卡还在念「有位志愿者想陪你跑，可以打个电话聊聊」，
    /// 而屏幕上没有任何入口。那与 `introCallUnavailable` 当初修的是同一类缺陷。
    ///
    /// 还有一条更细的路会绕过自动弹出：同一次通话磨合里换候选人要经过 `PENDING_MATCH`
    /// （`AGENTS.md` §5），而这一页 5 秒轮一次 —— 后端立刻派给下一位时，那个中间态
    /// 可能整个落在两次轮询之间。客户端看到的是 `PENDING_INTRO_CALL → PENDING_INTRO_CALL`，
    /// `onChange` 不触发。
    ///
    /// 版位与 `volunteerCallSection` / `keepWaitingSection` 相同、状态集互斥
    /// （`.pendingIntroCall` 不在 `offersVolunteerCall` 也不在 `offersKeepWaiting` 里），
    /// 所以读屏遍历时状态卡之后紧跟的永远是此刻唯一该做的那件事。
    ///
    /// 🚨 文案**不许复用 `callButtonTitle`**（「打电话给这位志愿者」）：那个按钮按下去
    /// 立刻弹系统拨号确认，这个按钮只是打开一个页面。对看不见屏幕的人，两件事听起来
    /// 一样就等于随时可能误拨。
    @ViewBuilder
    private func introCallEntrySection(_ order: OrderDetailResponse) -> some View {
        if order.status == .pendingIntroCall {
            Button {
                introCallPresentation.isShowing = true
            } label: {
                Text(IntroCallCopy.blindEntryButtonTitle)
                    .font(AppFonts.largeTitle())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: primaryActionButtonHeight)
                    .background(AppColors.primary)
                    .cornerRadius(16)
            }
            .accessibilityLabel(IntroCallCopy.blindEntryButtonTitle)
            .accessibilityHint(IntroCallCopy.blindEntryAccessibilityHint)
            .accessibilityIdentifier("blindOrderStatusIntroCallEntryButton")
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
    ///
    /// 🚩 **2026-09-05 从 140pt 的实心主按钮降级为 64pt 的描边次级按钮，功能一字未动。**
    /// 等待态这一页真正的主体是「系统正在派单」这条状态，而这个按钮此刻并不是用户**该做**
    /// 的事 —— 它是一条**保险**（不按，订单会在后端的窗口到点后被自动取消）。
    /// 用主按钮的体量把它摆在那里，会让盲人以为等待期有一件必须完成的操作。
    ///
    /// 🚨 **降级的是体量，不是可达性。** 三条不许动：
    /// 1. 仍在 `statusHeader` 之后的同一个版位，读屏遍历顺序不变；
    /// 2. 仍是整行铺满、64pt 高（`docs/research/blind-ui-visual-benchmark-20260808.md`
    ///    那条「次级操作一律整行铺满竖直堆叠」，与「换一位」「取消订单」同档）；
    /// 3. `repeatStatus` 里那句 `KeepWaitingCopy.repeatStatusSuffix` 照旧念 ——
    ///    看不见屏幕的人靠它知道这个按钮存在，那才是它真正的发现路径。
    ///
    /// `buttonShapeOutlineIfNeeded` 不能省：这一段降级后是纯文字按钮，开启「按钮形状」
    /// 的低视力用户否则看不出它可点（与 `actionSection` 的「取消订单」同一条理由）。
    @ViewBuilder
    private func keepWaitingSection(_ order: OrderDetailResponse) -> some View {
        if viewModel.canShowKeepWaiting {
            Button {
                Task { await viewModel.keepWaiting() }
            } label: {
                Text(KeepWaitingCopy.buttonTitle)
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(AppColors.primary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 64)
            }
            .disabled(viewModel.isPerformingAction)
            .buttonShapeOutlineIfNeeded(color: AppColors.primary)
            .accessibilityLabel(KeepWaitingCopy.buttonTitle)
            .accessibilityHint(KeepWaitingCopy.accessibilityHint)
            .accessibilityIdentifier("blindOrderStatusKeepWaitingButton")
        }
    }

    /// 把这次行程告诉家人。主路径是**实时分享**（后端生成免登录链接，家属能看到位置与轨迹），
    /// 短信是它失败时的降级路径。
    ///
    /// 排在主动作与 `actionSection` 之后、地图之前：它是**附属**动作（不该抢 140pt 的主按钮
    /// 版位，也不该排在「取消订单」这种状态机动作前面），但也不能沉到订单信息下面 ——
    /// 看不见屏幕的人靠遍历顺序发现功能存在，沉下去等于没做。样式用整行铺满的次级按钮，与
    /// `docs/research/blind-ui-visual-benchmark-20260808.md` 那条「次级操作一律整行铺满
    /// 竖直堆叠」一致。
    ///
    /// 终态整段消失（`offersRunPlanShare`），不是禁用：后端对终态返 409，
    /// 摆一个按下去必然报错的按钮，对读屏用户是纯噪音。
    @ViewBuilder
    private func runPlanShareSection(_ order: OrderDetailResponse) -> some View {
        if order.status.offersRunPlanShare {
            VStack(spacing: 10) {
                if shareViewModel.isLiveSharing {
                    runPlanShareButton(
                        title: RunPlanLiveShareCopy.stopButtonTitle,
                        hint: RunPlanLiveShareCopy.stopAccessibilityHint,
                        identifier: "blindOrderStatusStopLiveShareButton",
                        tint: AppColors.destructive,
                        action: { Task { await shareViewModel.stopLiveShare() } }
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
                if shareViewModel.showSMSFallback, MessageComposeSheet.canSendText {
                    runPlanShareButton(
                        title: RunPlanLiveShareCopy.smsFallbackButtonTitle,
                        hint: RunPlanLiveShareCopy.smsFallbackHint,
                        identifier: "blindOrderStatusShareRunPlanButton",
                        tint: AppColors.primary,
                        action: { shareRunPlanBySMS(order) }
                    )
                }

                if let notice = shareViewModel.notice {
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
        .disabled(shareViewModel.isWorking)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Live share

    private var consentStore: RunPlanShareConsentStore {
        RunPlanShareConsentStore(persistence: appState.persistence)
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
        shareViewModel.clearNotice(hidingSMSFallback: true)
        switch RunPlanShareConsentStep.next(hasGivenConsent: consentStore.hasGivenConsent(userKey: consentUserKey)) {
        case .fullDisclosure:
            showLiveShareConsent = true
        case .shortConfirmation:
            showLiveShareConfirmation = true
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
            shareViewModel.note(RunPlanShareCopy.unavailable, isProblem: true)
            return
        }
        guard appState.primaryEmergencyContact?.phone?.nilIfBlank != nil else {
            shareViewModel.note(RunPlanShareCopy.noContact, isProblem: true)
            return
        }
        // 第三道门与前两道一样要出声。`compose` 只在 `status.offersRunPlanShare == false` 时返回 nil，
        // 也就是 5 秒轮询把订单推到终态、而按钮还留在屏幕上的那一瞬 —— 静默 return 的表现是
        // 「点了没反应」，对盲人端就是事故（`AGENTS.md` §1 那条枚举红线的同类）。
        guard RunPlanShareMessage.compose(order: order) != nil else {
            shareViewModel.note(RunPlanShareCopy.notShareable, isProblem: true)
            return
        }
        shareViewModel.clearNotice()
        showRunPlanShare = true
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

    /// 求助区块**不在这里** —— 它在底部常驻的 `repeatStatusArea` 里（`IN_PROGRESS` 时）。
    ///
    /// 2026-08-19 搬走：这个 section 排在滚动内容第 7 位，`IN_PROGRESS` 时上面压着状态卡、
    /// 140pt 的「打电话给志愿者」、行程分享、180pt 装饰地图 —— 内容顶到求助按钮约 700pt，
    /// 而底部常驻条吃掉约 164pt 后视口只剩约 550pt，**服务进行中的求助按钮在首屏之外，要下滑**。
    /// 而且它的位置还不稳定：拿不到志愿者位置时地图退化成一行文字，求助又回到首屏。
    /// 这直接违反 `docs/research/blind-voice-booking-ia-20260805.md` §4「求助（`IN_PROGRESS` 时）
    /// 必须在首屏两次滑动内可达」。
    ///
    /// 求助搬走之后这里剩下的两个都是**这一态的状态机动作**：等待中的「取消订单」、
    /// 终态的「返回首页」。所以同日把整段从第 8 位提到主动作紧后面 —— 一个页面上
    /// 「此刻能对这一单做的事」应该连在一起，中间不隔着分享和地图。
    /// `IN_PROGRESS` 时这一段是空的（`canBlindRunnerCancel` 为假，`AGENTS.md` §5
    /// 明确禁止服务中展示取消），所以那一态的布局不受这次移动影响。
    private func actionSection(_ order: OrderDetailResponse) -> some View {
        VStack(spacing: 14) {
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
                            await viewModel.runMockCounterpartSteps(
                                [.respond(.accept)],
                                orderId: order.orderId
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("模拟志愿者接单")

                    // 真实链路里陌生人**不能**直接接单（后端 409 `INTRO_CALL_REQUIRED`），
                    // 走的是这一条。留着上面那个是因为熟人路径与「后端把开关关掉」都还走它。
                    Button("模拟志愿者想先聊聊") {
                        Task {
                            await viewModel.runMockCounterpartSteps(
                                [.respond(.interested)],
                                orderId: order.orderId
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("模拟志愿者想先聊聊")
                }

                // 通话磨合期只有盲人这一侧能在 Mock 里操作，志愿者那半边由这个按钮代打 ——
                // 否则「双方都说合适」在单设备上永远凑不齐。
                if order.status == .pendingIntroCall {
                    Button("模拟志愿者说合适") {
                        (appState.apiClient as? MockAPIClient)?.simulateIntroCallDecisionForTesting(
                            orderId: order.orderId,
                            role: .volunteer,
                            decision: .accept
                        )
                        viewModel.startPolling(orderId: order.orderId)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("模拟志愿者说合适")
                }

                // 跨天预约单：先让志愿者「确认出发」把它推到 `PENDING_ACCEPT`，
                // 之后就接回既有的那几个按钮。分开一个按钮而不是并进下面那条链，
                // 是因为这一步本身就是要验的东西 —— 合进去就跳过了它。
                if order.status == .scheduledConfirmed {
                    Button("模拟志愿者确认出发") {
                        Task {
                            await viewModel.runMockCounterpartSteps([.confirmDeparture], orderId: order.orderId)
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("模拟志愿者确认出发")
                }

                if order.status == .driverEnRoute || order.status == .pendingAccept {
                    Button("模拟志愿者到达") {
                        Task {
                            // 真实状态机是 PENDING_ACCEPT → DRIVER_EN_ROUTE → DRIVER_ARRIVED，不能跳级，
                            // 所以 `PENDING_ACCEPT` 要先补一步 en-route。被 Mock 拒掉时
                            // `runMockCounterpartSteps` 会把原因写进 `errorMessage`，不再静默。
                            let steps: [BlindOrderStatusViewModel.MockCounterpartStep] =
                                order.status == .pendingAccept ? [.enRoute, .arrived] : [.arrived]
                            await viewModel.runMockCounterpartSteps(steps, orderId: order.orderId)
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("模拟志愿者到达")
                }

                if order.status == .driverArrived {
                    Button("模拟服务开始") {
                        Task {
                            await viewModel.runMockCounterpartSteps([.startService], orderId: order.orderId)
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("模拟服务开始")
                }

                if order.status == .inProgress {
                    Button("模拟服务完成") {
                        Task {
                            await viewModel.runMockCounterpartSteps([.finish], orderId: order.orderId)
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

    /// 底部常驻区。**永远是两个版位**，第二个恒为「重复当前状态」，第一个按状态换人：
    ///
    /// - `IN_PROGRESS`：求助区块。这是这一页唯一一个「晚一秒都算代价」的动作，必须零滚动可达。
    /// - 其余状态：「问一句」。它排在「重复当前状态」之前是因为更省时间 ——
    ///   整段状态播报要 15~25 秒，而问一句只念被问的那一项。
    ///
    /// **为什么是换而不是加**：再叠一个 64pt 就是三个按钮 220pt，在 6.1" 上吃掉 26% 屏幕，
    /// 把滚动区压得更小 —— 治了求助够不着，换来别的都够不着。`IN_PROGRESS` 时「问一句」下沉到
    /// 滚动区「打电话给志愿者」的下一位（仍在首屏内），不是删掉：
    /// `blindOrderStatusAskQuestionButton` 这个标识符没变，按 id 找它的用例照样找得到。
    ///
    /// 求助进行中时这一条会变高（求助 + 结果文案 + 撤销求助 + 重复当前状态）。这是有意的：
    /// 那正是这一页唯一该被求助占满的时刻，也是「撤销求助」必须跟着按钮走的理由 ——
    /// 按下去的结果不该出现在屏幕外。
    private var repeatStatusArea: some View {
        VStack(spacing: 12) {
            if viewModel.canShowEmergency {
                // 整块交给 `EmergencyActionSection`：它自己订阅 coordinator。
                // 直接读 `appState.emergencyCoordinator.state` 是值对但不跟着刷新 —— 详见该类型的注释。
                EmergencyActionSection(
                    coordinator: appState.emergencyCoordinator,
                    onTrigger: { showEmergencyConfirmation = true },
                    onCancelOwnEmergency: { showEmergencyCancelConfirmation = true }
                )
            } else {
                askQuestionButton
            }
            PrimaryButton("重复当前状态") {
                viewModel.repeatStatus()
            }
            .accessibilityLabel("重复当前状态")
            .accessibilityHint("点击后重新播报当前订单状态")
        }
        // 与内容列同宽。都是具名按钮，收窄不影响读屏用户找得到。
        .readableContentColumn()
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        // 这条常驻底栏压在滚动内容之上，`.regularMaterial` 会把下面滑过去的文字透上来。
        // 「降低透明度」开启时换成实色 —— 那个开关的用户正是被这种叠影干扰的人，
        // 而底下这些按钮是这一页任何时刻都要够得着的东西。
        .background(reduceTransparency ? AnyShapeStyle(AppColors.background) : AnyShapeStyle(.regularMaterial))
    }

    /// `IN_PROGRESS` 时「问一句」被求助顶出底部常驻条，落在这里 —— 紧跟「打电话给志愿者」。
    ///
    /// 选这个位置是为了让它仍在首屏内：状态卡 ≈150 + 打电话 140 + 问一句 64 + 间距 ≈ 430pt，
    /// 而这一态下的视口约 550pt。排到 `actionSection` 那边就又掉出首屏了，
    /// 那正是求助原先的处境。
    @ViewBuilder
    private var inlineAskQuestionSection: some View {
        if viewModel.canShowEmergency {
            askQuestionButton
        }
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
