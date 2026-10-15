import Combine
import SwiftUI

// MARK: - 志愿者侧「接单前通话磨合」

/// 进通话页要带的东西。**两条到达路径共用一个导航源**，区别只在 `dispatchOrder` 有没有。
///
/// - 推送路径（`INTERESTED` 发出去之后）：`dispatchOrder` 有值，本单信息与导盲犬提示位照常渲染。
/// - **冷启动恢复路径**（`dispatch-summary` 的 `introCallOrderId`）：`dispatchOrder` 是 nil。
///
/// 恢复路径上**出发地与时间照常有** —— 它们来自 `IntroCallView`（后端为这件事专门加的
/// `startAddress` / `plannedStartTime`，字段说明里点名了「杀掉 App 再打开就回不到通话页」）。
///
/// 拿不到的只有**距离**和**导盲犬**：前者要 `distanceKm`（只在派单推送里），
/// 后者要 `escortNeeds`（同上）。这两块在恢复路径上不渲染，**这是诚实不是缺陷** ——
/// 志愿者据此判断的是「要不要接这一单」，编一个距离比空着更糟。
/// 不加 `Equatable`：`WSNewOrder` 是 `Codable, Sendable` 而非 `Equatable`，
/// 为了一个导航值给整条派单载荷补 `Equatable` 是本末倒置。
/// 断言拿 `orderId` 和 `dispatchOrder == nil` 比即可（后者对任何类型都成立）。
struct VolunteerIntroCallRoute {
    let orderId: Int64
    let dispatchOrder: WSNewOrder?

    init(orderId: Int64, dispatchOrder: WSNewOrder? = nil) {
        self.orderId = orderId
        self.dispatchOrder = dispatchOrder
    }

    init(dispatchOrder: WSNewOrder) {
        self.orderId = dispatchOrder.orderId
        self.dispatchOrder = dispatchOrder
    }
}

/// 本轮通话在志愿者这边的落点。
enum VolunteerIntroCallOutcome: Equatable {
    /// 还在通话磨合中。
    case active
    /// 双方都说合适 ⇒ 正式接单，可以进服务流程了。
    case matched
    /// 本轮结束但这一单不是你的（对方换人 / 你自己说了不合适 / 窗口超时 / 盲人取消了订单）。
    ///
    /// 🚨 **四种成因在界面上不区分。** 后端把它们全都发成同一条中性的 `INTRO_CALL_CLOSED`，
    /// 理由与盲人侧的无声拒绝对称：告诉志愿者「跑者拒绝了你」同样是在制造挫败，
    /// 而这个功能存在的意义就是让退出不带评判。
    case closed
}

@MainActor
final class VolunteerIntroCallViewModel: ObservableObject {
    @Published private(set) var introCall: IntroCallView?
    @Published private(set) var outcome: VolunteerIntroCallOutcome = .active
    @Published private(set) var isSubmitting = false
    @Published var errorMessage: String?
    /// 成单后交给 `VolunteerInServiceView` 的首帧订单。成单那一刻 `order.volunteer` 才被写上，
    /// 也正是从那一刻起志愿者才读得到订单详情。
    @Published private(set) var matchedOrder: OrderDetailResponse?
    /// 「跑者王*正在来电」显示到几点（收到 `INTRO_CALL_INCOMING` 的发出时刻 + 2 分钟）。
    @Published private(set) var incomingCallUntil: Date?

    private weak var appState: AppState?
    private var speechService: SpeechService?
    private var pollingTask: Task<Void, Never>?
    private var orderId: Int64?
    /// 剩 5 分钟 / 1 分钟各播一次。轮询再多也不重复（去重逻辑在 #440 的 `IntroCallCountdownAnnouncer`）。
    private var countdownAnnouncer = IntroCallCountdownAnnouncer()
    /// 上一条来电提醒的发出时刻。重连补读会把同一条再投一次，同一条不重播。
    private var lastIncomingSentAt: Date?

    /// 与盲人订单页同一个 5 秒兜底：这一页的状态由**对方**的动作驱动，
    /// 而 WebSocket 只保证「大概率到」。
    private let pollingInterval: TimeInterval = AppConstants.Timing.orderPollingInterval

    func configure(orderId: Int64, appState: AppState, speechService: SpeechService) {
        self.orderId = orderId
        self.appState = appState
        self.speechService = speechService
    }

    func startPolling() {
        guard orderId != nil else { return }
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            await self?.load()
            while !Task.isCancelled {
                guard let self, self.outcome == .active else { return }
                try? await Task.sleep(nanoseconds: UInt64(self.pollingInterval * 1_000_000_000))
                if Task.isCancelled { return }
                await self.load()
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// 拉一次通话数据。轮询用它，用例也直接调它（不必等 5 秒一轮）。
    func refresh(now: Date = Date()) async {
        await load(now: now)
    }

    private func load(now: Date = Date()) async {
        guard let orderId, let appState else { return }
        do {
            introCall = try await appState.safety.introCall(orderId: orderId)
            clearLoadFailure()
            announceCountdownIfDue(now: now)
        } catch let error as APIError {
            if appState.handleAuthenticatedAPIError(error) { return }
            guard Self.endsTheRound(error) else {
                noteLoadFailure()
                return
            }
            // 到底是成了还是没成，端点自己不说，也不该说。
            await resolveFinishedRound(orderId: orderId, appState: appState)
        } catch {
            noteLoadFailure()
        }
    }

    // MARK: 子状态

    /// V1 等来电 / V3 等跑者确认。
    ///
    /// 🚩 **服务端说有安排单就是 V3，哪怕这一版读不懂**（`hasUnreadablePlan`）：退回 V1 会让陪跑员以为
    /// 自己还没提交、再提交一版 —— 而每提交一版跑者之前的确认就作废一次。
    var step: IntroCallVolunteerStep {
        introCall?.plan != nil ? .awaitingRunnerConfirmation : IntroCallVolunteerStep.resolve(plan: introCall?.meetupPlan)
    }

    /// 「跑者王*正在来电」那 2 分钟。
    func isShowingIncomingCall(now: Date) -> Bool {
        guard outcome == .active, let incomingCallUntil else { return false }
        return incomingCallUntil > now
    }

    // MARK: 倒计时

    /// 剩 5 分钟 / 1 分钟各主动播一次（视觉稿时间线第 7 行，陪跑员端只报剩余时间）。平时静默。
    func announceCountdownIfDue(now: Date = Date()) {
        guard outcome == .active,
              let endsAt = introCall?.windowEndsAt?.nilIfBlank?.backendTimestamp,
              countdownAnnouncer.nodeToAnnounce(windowEndsAt: endsAt, now: now) != nil else { return }
        speechService?.speak(IntroCallMeetupCopy.countdownAnnouncement(windowEndsAt: endsAt, now: now, isReviewingPlan: false))
    }

    // MARK: 跑者正在来电（V1′）

    /// 收到 `INTRO_CALL_INCOMING`。`sentAt` 是后端发出的时刻：重连补读来的旧提醒若已过 2 分钟，不显示也不播。
    func noteIncomingCall(sentAt: Date, now: Date = Date()) {
        // 发出时刻晚于本机「现在」（两端时钟偏差）按现在算，免得「正在来电」挂得比 2 分钟还久。
        let until = min(sentAt, now).addingTimeInterval(IntroCallCopy.incomingCallDisplaySeconds)
        guard outcome == .active, until > now, sentAt != lastIncomingSentAt else { return }
        lastIncomingSentAt = sentAt
        incomingCallUntil = until
        speechService?.speak(IntroCallCopy.volunteerIncomingCallAnnouncement(counterpartName: introCall?.counterpartName))
    }

    /// 服务端明说「这一轮结束了」的回答。契约 `GET /api/orders/{id}/intro-call` 只列了两种：
    /// 409 `INTRO_CALL_NOT_ACTIVE`（本轮已结束）、403 `NOT_ORDER_PARTICIPANT`（我们已经不是参与者了）。
    /// 后端没回可解码的错误体时，同样两个状态码落成 `.unknown(statusCode:)`，一并算。
    ///
    /// 🚨 其余一律不算：网络失败、429、解码失败、5xx 都只是「这次没拿到」。
    /// 当成结束会让弱网一次就把志愿者踢出通话页（#428）—— `resolveFinishedRound` 里的
    /// `matchedOrder` 在弱网下同样失败，于是判成「没成」并停轮询，而盲人可能正在拨他的电话。
    static func endsTheRound(_ error: APIError) -> Bool {
        if let code = error.errorCode, code == .introCallNotActive || code == .notOrderParticipant {
            return true
        }
        if case .unknown(let statusCode) = error {
            return statusCode == 403 || statusCode == 409
        }
        return false
    }

    /// 这次没拿到通话数据：留在 `.active`、轮询照常继续，**只在第一次失败时播一遍** ——
    /// 轮询每 5 秒一次，每次都播会把读屏用户淹掉（与盲人侧 `refreshIntroCallIfNeeded` 同一条）。
    private func noteLoadFailure() {
        guard errorMessage != IntroCallCopy.loadFailed else { return }
        errorMessage = IntroCallCopy.loadFailed
        speechService?.speakError(IntroCallCopy.loadFailed)
    }

    /// 拿到了就撤掉上一次的「暂时拿不到」。只撤这一句：表态失败的错误文案不归这里管。
    private func clearLoadFailure() {
        if errorMessage == IntroCallCopy.loadFailed {
            errorMessage = nil
        }
    }

    /// 本轮结束之后**唯一**能判定「这一单是不是我的」的办法。
    ///
    /// 成单时后端 `IntroCallService.confirmMatch` 会写上 `order.volunteer`，
    /// 而 `OrderQueryService.getOrder` 正是拿这个字段判权限 —— 于是：
    /// 订单详情读得到 ⇒ 成了；仍然 403 ⇒ 这一单不是我的。
    /// 这不是取巧，是这个契约下唯一存在的判据：通话端点刻意不回对方的表态。
    private func resolveFinishedRound(orderId: Int64, appState: AppState) async {
        introCall = nil
        incomingCallUntil = nil
        if let order = try? await appState.safety.matchedOrder(orderId: orderId) {
            matchedOrder = order
            outcome = .matched
            speechService?.speak(IntroCallCopy.volunteerMatchedAnnouncement(order: order))
        } else {
            outcome = .closed
            speechService?.speak(IntroCallCopy.volunteerRoundClosed)
        }
        stopPolling()
    }

    // MARK: 提交见面安排（V2）

    /// `PUT /intro-call/plan`。**提交本身就是陪跑员的「合适」**（契约），所以这一侧不再发 `decision=ACCEPT`。
    ///
    /// 成功后就地把这一版挂到 `introCall.plan` 上 —— 页面立刻切到 V3，不等下一轮轮询（5 秒的空档里
    /// 陪跑员会以为没交上去、再点一次）。
    func submitPlan(_ request: IntroCallPlanRequest, distanceFromOriginal: Double?) async -> VolunteerMeetupPlanSubmitOutcome {
        guard let orderId, let appState else { return .roundEnded }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let stored = try await appState.safety.submitIntroCallPlan(orderId: orderId, plan: request)
            if var current = introCall {
                current.plan = stored
                introCall = current
            }
            clearLoadFailure()
            speechService?.speak(IntroCallCopy.volunteerPlanSubmittedAnnouncement)
            return .submitted
        } catch let error as APIError {
            if appState.handleAuthenticatedAPIError(error) { return .roundEnded }
            if Self.endsTheRound(error) {
                await resolveFinishedRound(orderId: orderId, appState: appState)
                return .roundEnded
            }
            let mapped = VolunteerMeetupPlanSubmitError.make(for: error, distanceFromOriginal: distanceFromOriginal)
            speechService?.speakError(mapped.message)
            return .failed(mapped)
        } catch {
            let mapped = VolunteerMeetupPlanSubmitError.make(for: error, distanceFromOriginal: distanceFromOriginal)
            speechService?.speakError(mapped.message)
            return .failed(mapped)
        }
    }

    // MARK: 退出

    /// 「不合适」。
    ///
    /// ⚠️ 请求体**没有 reason 字段**，这是后端刻意的：要求填理由等于要求当面说「不」。
    func submit(_ decision: IntroCallDecision) async {
        await perform { safety, orderId in
            try await safety.submitIntroCallDecision(orderId: orderId, decision: decision)
        }
    }

    /// 「未接到来电」。
    ///
    /// 🚩 **与「不合适」是两个端点，不能合并。** 后端的统计口径相反：这条只增
    /// dispatched + timeout，不动 declined —— 他并没有拒绝任何人，而 `acceptanceRate`
    /// 直接进派单评分。且这一对不进候选池硬过滤，没接到电话不代表两人不合适。
    func reportUnreachable() async {
        await perform { safety, orderId in
            try await safety.reportIntroCallUnreachable(orderId: orderId)
        }
    }

    /// 两个表态端点共用的收尾。`orderId` 由这里 guard 出来再交给闭包 ——
    /// 迁移前是先用 `orderId ?? 0` 拼好路径再在这里 guard，那条路径永远不该被构造出来。
    private func perform(_ call: (any SafetyServing, Int64) async throws -> Void) async {
        guard let orderId, let appState else { return }
        isSubmitting = true
        errorMessage = nil
        do {
            try await call(appState.safety, orderId)
            isSubmitting = false
            // 表态之后本轮的落点由服务端宣布。让下一次轮询把结果带回来，不在本地假设任何结论。
            await load()
        } catch let error as APIError {
            isSubmitting = false
            if appState.handleAuthenticatedAPIError(error) { return }
            if error.errorCode == .introCallNotActive {
                // 窗口已经超时、订单已经换人。这不是失败重试能解决的，直接收尾。
                await resolveFinishedRound(orderId: orderId, appState: appState)
                return
            }
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isSubmitting = false
            let message = "没有提交成功，请再试一次。"
            errorMessage = message
            speechService?.speakError(message)
        }
    }
}

/// 志愿者侧通话磨合页。
///
/// 数据来源是**派单载荷 + 通话端点**，不是订单详情：通话期 `order.volunteer` 恒为 null，
/// `GET /api/orders/{id}` 会 403（见 `VolunteerHomeViewModel.pendingIntroCallOrder`）。
///
/// 🔄 2026-10-15 按见面安排单视觉稿 v2 重做（`docs/ui/mockups/intro-call-meetup-plan-20261015/`，#433）：
/// - V1 等来电：主按钮「填写见面安排」（v6 是「合适，接这一单」）；次「不合适」；文字「未接到来电」
/// - V1′ 跑者正在来电：收到 `INTRO_CALL_INCOMING` 后 2 分钟，标题换句话、播一次
/// - V2 填写见面安排：`VolunteerMeetupPlanFormView`（表单页）
/// - V3 等跑者确认：安排摘要；「修改见面安排」（先提示需跑者重新确认）；文字「不合适」。**不显示跑者听没听、同不同意**
/// - V4 约好：原地变成订单页「约好」（新增见面位置与两人上衣，见 `VolunteerOrderFlowPresentation.meetupRows`）
/// - V4′ 没约成：「本次沟通已结束」+「返回首页」，**不自动跳转**（v6 停 3 秒自动关页，会截断播报）
/// 头卡整步沿用匹配钢蓝 `stateMatching`，去掉 v6 的通话前紫与通话后梅红；子状态靠那句话与绳子上的图标区分。
struct VolunteerIntroCallView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @EnvironmentObject private var amapGeocodingService: AMapGeocodingService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = VolunteerIntroCallViewModel()
    /// 求助胶囊按下去：这一态不是 `IN_PROGRESS`，一律本地拨号（`VolunteerOrderSOSMode`）。
    @State private var showsLocalHelp = false
    @State private var showsPlanForm = false
    @State private var showsEditConfirm = false

    let route: VolunteerIntroCallRoute

    /// 派单载荷。冷启动恢复路径上是 nil —— 那两块信息没有数据源，见 `VolunteerIntroCallRoute`。
    private var dispatchOrder: WSNewOrder? { route.dispatchOrder }

    /// 倒计时胶囊与「正在来电」两分钟的刷新粒度。只换屏幕上的字，播报由 view model 在轮询里判。
    private static let clockTick: TimeInterval = 15

    var body: some View {
        Group {
            if viewModel.outcome == .matched, let order = viewModel.matchedOrder {
                // 成单：原地换成订单页（「约好」）。不 push：push 要一个 `isPresented` 绑定，
                // 返回时会被立刻重新推回去；原地换内容没有这个问题，订单页自己的返回键关掉的是整页。
                VolunteerInServiceView(orderId: order.orderId, initialOrder: order)
                    .transition(.opacity)
            } else {
                callPage
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.outcome)
        // 订单页那一族不带标签栏（设计交付 v3 §4.2 总表，S5 邀请就是 S6 的一个状态）；
        // 自带导航栏，系统那条整条藏掉，否则两条叠着。返回箭头在，不会把人关在这一页里。
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            viewModel.configure(
                orderId: route.orderId,
                appState: appState,
                speechService: speechService
            )
            viewModel.startPolling()
            appState.realtimeCoordinator.introCallPageDidAppear()
        }
        .onDisappear {
            viewModel.stopPolling()
            appState.realtimeCoordinator.introCallPageDidDisappear()
        }
        .onReceive(appState.realtimeCoordinator.introCallIncomingPublisher) { sentAt in
            viewModel.noteIncomingCall(sentAt: sentAt)
        }
        .onChange(of: viewModel.outcome) { outcome in
            // 表单开着时这一轮结束了：没有可改的了，收起表单让人看到结局。
            if outcome != .active { showsPlanForm = false }
        }
    }

    private var isClosed: Bool { viewModel.outcome == .closed }
    private var isAwaitingConfirmation: Bool { !isClosed && viewModel.step == .awaitingRunnerConfirmation }

    private var callPage: some View {
        VStack(spacing: 0) {
            FlowOrderNavBar(
                title: IntroCallCopy.pageTitle,
                onBack: { dismiss() },
                onHelp: { showsLocalHelp = true }
            )
            .padding(.horizontal, FlowMetrics.v2ScreenPadding - 8)
            ScrollView {
                VStack(spacing: FlowMetrics.v2SectionGap) {
                    TimelineView(.periodic(from: Date(), by: Self.clockTick)) { context in
                        heroCard(now: context.date)
                    }
                    if isAwaitingConfirmation {
                        planSummaryCard
                    } else if !isClosed {
                        // 复用接单后那块「本单为视障跑者」提示位，不新建组件。
                        // 接单前只剩导盲犬那一行 —— 视力情况与引导方式走
                        // `disclosesBlindRunnerNotesToVolunteer` 闸，通话发生在接单之前。
                        // 恢复路径上是空数组，该组件对空数组本来就什么都不渲染。
                        VolunteerRunnerNeedsBanner(needs: dispatchOrder?.escortNeeds ?? [])
                        paceCard
                    }
                    if let errorMessage = viewModel.errorMessage, !isClosed {
                        Text(errorMessage)
                            .flowFont(FlowV2Fonts.callout(bold: true))
                            .foregroundColor(AppColors.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel(errorMessage)
                            .accessibilityIdentifier("volunteerIntroCallError")
                    }
                }
                .padding(.horizontal, FlowMetrics.v2ScreenPadding)
                .padding(.vertical, FlowMetrics.v2SectionGap)
                .readableContentColumn()
            }
        }
        .background(AppColors.Flow.page.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomActions }
        .emergencyCallOptionsDialog(isPresented: $showsLocalHelp, context: .volunteerBeforeRun, primaryContact: nil)
        .alert(IntroCallCopy.volunteerEditPlanConfirmTitle, isPresented: $showsEditConfirm) {
            Button("取消", role: .cancel) {}
            Button(IntroCallCopy.volunteerEditPlanConfirmButton) { showsPlanForm = true }
        }
        .sheet(isPresented: $showsPlanForm) {
            planForm
        }
    }

    @ViewBuilder
    private var planForm: some View {
        if let introCall = viewModel.introCall {
            VolunteerMeetupPlanFormView(
                original: introCall.originalArrangement,
                editing: introCall.meetupPlan,
                windowEndsAt: introCall.windowEndsAt?.nilIfBlank?.backendTimestamp
            ) { request, distance in
                await viewModel.submitPlan(request, distanceFromOriginal: distance)
            }
            .environmentObject(amapGeocodingService)
        }
    }

    // MARK: 头卡

    private var runnerName: String? {
        viewModel.introCall?.counterpartName?.nilIfBlank
    }

    private func heroCard(now: Date) -> some View {
        let incoming = viewModel.isShowingIncomingCall(now: now)
        return FlowHeroCard(style: .tinted(AppColors.Flow.stateMatching)) {
            if let eyebrow {
                Text(eyebrow)
                    .flowFont(FlowV2Fonts.subhead(bold: true))
                    .foregroundColor(AppColors.Flow.onHeroEyebrow)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
            RopeView(
                state: .introCall(ropeStage),
                theme: .onHero(AppColors.Flow.stateMatching),
                runnerName: runnerName
            )
            heroBody(incoming: incoming)
            heroPill(now: now, incoming: incoming)
        }
    }

    private var ropeStage: IntroCallRopeStage {
        if isClosed { return .ended }
        return isAwaitingConfirmation ? .planSubmitted : .beforeCall
    }

    private func heroBody(incoming: Bool) -> some View {
        let title = title(incoming: incoming)
        let lines = lines(incoming: incoming)
        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .flowFont(FlowV2Fonts.title())
                .foregroundColor(AppColors.Flow.onHeroStrong)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .flowFont(FlowV2Fonts.callout())
                    .foregroundColor(AppColors.Flow.onHeroBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            ([eyebrow?.replacingOccurrences(of: " · ", with: "，"), title.unmaskedForSpeech] + lines.map(Optional.some))
                .compactMap { $0?.nilIfBlank }
                .joined(separator: "，")
        )
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("volunteerIntroCallHeader")
    }

    /// 倒计时胶囊。**单独一个读屏元素、常驻**（来电提醒期间也在，只是上面多一枚来电胶囊），
    /// 按分钟静默更新（`updatesFrequently`），只在剩 5 / 1 分钟时由 view model 主动播。
    /// 并进头卡标签会让整段标题每 15 秒被重念一遍。
    @ViewBuilder
    private func heroPill(now: Date, incoming: Bool) -> some View {
        if !isClosed {
            VStack(alignment: .leading, spacing: 8) {
                if incoming {
                    HStack { FlowHeroPill(text: IntroCallCopy.volunteerIncomingCallPill, systemImage: "phone.fill") }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(IntroCallCopy.volunteerIncomingCallPill.replacingOccurrences(of: " · ", with: "，"))
                        .accessibilityIdentifier("volunteerIntroCallIncomingPill")
                }
                countdownPill(now: now)
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func countdownPill(now: Date) -> some View {
        if let text = IntroCallCopy.volunteerWindowPillText(
            windowEndsAt: viewModel.introCall?.windowEndsAt, isAwaitingConfirmation: isAwaitingConfirmation, now: now
        ) {
            HStack { FlowHeroPill(text: text, systemImage: "clock") }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(IntroCallCopy.volunteerWindowPillAccessibilityLabel(
                    windowEndsAt: viewModel.introCall?.windowEndsAt, isAwaitingConfirmation: isAwaitingConfirmation, now: now
                ) ?? text)
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityIdentifier("volunteerIntroCallCountdown")
        }
    }

    private func title(incoming: Bool) -> String {
        if isClosed { return IntroCallCopy.volunteerRoundClosedTitle }
        // 还在拉：整屏不许空白（理由同盲人侧 `blindLoadingNotice`）。
        if viewModel.introCall == nil, viewModel.errorMessage == nil { return IntroCallCopy.volunteerLoadingNotice }
        // V3 时跑者又打来（他点了「有异议，致电沟通」）：同样换成来电那句 —— 不告诉陪跑员「跑者不同意」。
        if incoming { return IntroCallCopy.volunteerIncomingCallTitle(counterpartName: runnerName) }
        if isAwaitingConfirmation { return IntroCallCopy.volunteerAwaitingConfirmationTitle(counterpartName: runnerName) }
        return IntroCallCopy.volunteerWaitingForCallTitle(counterpartName: runnerName)
    }

    /// 🚨 掩码号只用来**认人**，这一页刻意**没有**拨号按钮：号码在这一侧是单向的，
    /// 后端恒不下发志愿者能拨通的明文号（`IntroCallView.counterpartPhoneMasked` 的注释）。
    /// 把 `138****1234` 拼进 `tel:` 会拼成一个七位的、可能真打给别人的号码。
    private func lines(incoming: Bool) -> [String] {
        if isClosed { return [IntroCallCopy.volunteerRoundClosedSubtitle] }
        let masked = viewModel.introCall?.counterpartPhoneMasked?.nilIfBlank
        if incoming, let masked { return [IntroCallCopy.volunteerIncomingCallNumberLine(masked: masked)] }
        if isAwaitingConfirmation { return [IntroCallCopy.volunteerAwaitingConfirmationSubtitle] }
        guard let masked else { return [] }
        return [IntroCallCopy.volunteerIncomingNumberLine(masked: masked)]
    }

    /// 出发地与时间**优先取派单载荷，取不到回落 `IntroCallView`**（两个来源同源，契约逐字）。
    /// 距离**没有回落** —— `IntroCallView` 里没有它，而编一个比空着更糟。
    ///
    /// V3 改成安排单里的生效时间与地点（视觉稿「明天 7:30 · 朝阳公园东门」），并且**不再带距离**：
    /// 派单载荷的距离量的是原集合点，地点改了之后那个数字就不对了。
    private var eyebrow: String? {
        if isAwaitingConfirmation, let summary = planSummary {
            return IntroCallCopy.eyebrow(
                plannedStart: summary.start.map(DateFormatter.aidRunBackendLocalDateTime.string(from:)),
                address: summary.address
            )
        }
        return IntroCallCopy.eyebrow(
            plannedStart: dispatchOrder?.plannedStart?.nilIfBlank ?? viewModel.introCall?.plannedStartTime,
            address: dispatchOrder?.startAddress?.nilIfBlank ?? viewModel.introCall?.startAddress,
            distanceKm: dispatchOrder?.distanceKm
        )
    }

    // MARK: V3 安排摘要

    private var planSummary: VolunteerMeetupPlanSummary? {
        guard let introCall = viewModel.introCall, let plan = introCall.meetupPlan else { return nil }
        return VolunteerMeetupPlanSummary.make(plan: plan, original: introCall.originalArrangement)
    }

    /// 改过的项标「已变更」（浅蓝小标签，不用删除线 —— 读屏念不出删除线）。
    /// 这一版读不懂（`hasUnreadablePlan`）时不画：读坏的时间会被当成「按原约」，摘要会说错。
    @ViewBuilder
    private var planSummaryCard: some View {
        if let summary = planSummary, !summary.rows.isEmpty {
            FlowCard {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(summary.rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { FlowSeparator() }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text(row.label)
                                    .flowFont(FlowV2Fonts.subhead())
                                    .foregroundColor(AppColors.Flow.secondaryText)
                                if row.isChanged {
                                    FlowTag(text: VolunteerMeetupPlanCopy.changedTag)
                                }
                            }
                            Text(row.value)
                                .flowFont(FlowV2Fonts.headline())
                                .foregroundColor(AppColors.Flow.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(row.accessibilityLabel)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("volunteerIntroCallPlanSummary")
        }
    }

    /// 配速。只在派单载荷里有（恢复路径上没有就不画，**不摆「暂无」占位**）。
    @ViewBuilder
    private var paceCard: some View {
        if let pace = dispatchOrder?.pacePreference?.nilIfBlank {
            let text = PacePreference(rawValue: pace)?.displayName ?? pace
            FlowCard {
                FlowInfoRow(label: "配速", accessibilityLabel: "配速，\(text)") {
                    Text(text)
                        .flowFont(FlowFonts.rowValue())
                        .foregroundColor(AppColors.Flow.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.trailing)
                }
            }
            .accessibilityIdentifier("volunteerIntroCallOrderFacts")
        }
    }

    // MARK: 底栏

    @ViewBuilder
    private var bottomActions: some View {
        if isClosed {
            // V4′：留在这一页，等陪跑员自己点（v6 停 3 秒自动关页，会截断那句播报）。
            OrderFlowBottomActions(
                owner: .volunteer,
                primary: OrderFlowPrimaryAction(title: IntroCallCopy.volunteerBackHomeButtonTitle) { dismiss() },
                safetyHub: nil
            )
        } else if isAwaitingConfirmation {
            // V3：此刻没有该他做的主动作 —— 不放黄色主按钮。
            OrderFlowBottomActions(
                owner: .volunteer,
                primary: nil,
                secondary: AnyView(awaitingConfirmationButtons),
                safetyHub: nil
            )
        } else {
            OrderFlowBottomActions(
                owner: .volunteer,
                primary: OrderFlowPrimaryAction(
                    title: IntroCallCopy.volunteerFillPlanButtonTitle,
                    isLoading: viewModel.isSubmitting,
                    isEnabled: !viewModel.isSubmitting && viewModel.introCall != nil,
                    accessibilityHint: IntroCallCopy.volunteerFillPlanAccessibilityHint
                ) {
                    showsPlanForm = true
                },
                secondary: AnyView(awaitingCallButtons),
                safetyHub: nil
            )
        }
    }

    /// V1：「不合适」与「未接到来电」。
    ///
    /// 🚩 **两个端点，不能合并**（`reportUnreachable` 的注释：统计口径相反）。
    @ViewBuilder
    private var awaitingCallButtons: some View {
        VStack(spacing: FlowMetrics.actionButtonSpacing) {
            declineButton(style: .ghost)
            FlowTextButton(
                title: IntroCallCopy.volunteerUnreachableButtonTitle,
                accessibilityHint: IntroCallCopy.volunteerUnreachableAccessibilityHint
            ) {
                Task { await viewModel.reportUnreachable() }
            }
            .disabled(viewModel.isSubmitting)
            .accessibilityIdentifier("volunteerIntroCallUnreachableButton")
        }
    }

    /// V3：「修改见面安排」（先提示需跑者重新确认）与文字「不合适」。
    /// 已经提交过安排单 = 电话打通了，「未接到来电」此刻不成立，不给。
    @ViewBuilder
    private var awaitingConfirmationButtons: some View {
        VStack(spacing: FlowMetrics.actionButtonSpacing) {
            FlowActionButton(
                IntroCallCopy.volunteerEditPlanButtonTitle,
                style: .outlined,
                isEnabled: !viewModel.isSubmitting,
                accessibilityHint: IntroCallCopy.volunteerEditPlanConfirmTitle
            ) {
                showsEditConfirm = true
            }
            .accessibilityIdentifier("volunteerIntroCallEditPlanButton")

            FlowTextButton(
                title: IntroCallCopy.volunteerDeclineButtonTitle,
                accessibilityHint: "结束这次通话确认，系统会把这一单派给下一位"
            ) {
                Task { await viewModel.submit(.decline) }
            }
            .disabled(viewModel.isSubmitting)
            .accessibilityIdentifier("volunteerIntroCallDeclineButton")
        }
    }

    private func declineButton(style: FlowActionButton.Style) -> some View {
        FlowActionButton(
            IntroCallCopy.volunteerDeclineButtonTitle,
            style: style,
            isEnabled: !viewModel.isSubmitting,
            accessibilityHint: "结束这次通话确认，系统会把这一单派给下一位"
        ) {
            Task { await viewModel.submit(.decline) }
        }
        .accessibilityIdentifier("volunteerIntroCallDeclineButton")
    }
}
