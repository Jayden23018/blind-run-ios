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

    private weak var appState: AppState?
    private var speechService: SpeechService?
    private var pollingTask: Task<Void, Never>?
    private var orderId: Int64?

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

    private func load() async {
        guard let orderId, let appState else { return }
        do {
            introCall = try await appState.safety.introCall(orderId: orderId)
            clearLoadFailure()
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
        if let order = try? await appState.safety.matchedOrder(orderId: orderId) {
            matchedOrder = order
            outcome = .matched
            speechService?.speak(IntroCallCopy.volunteerMatched)
        } else {
            outcome = .closed
            speechService?.speak(IntroCallCopy.volunteerRoundClosed)
        }
        stopPolling()
    }

    /// 「合适，接这一单」/「不合适」。
    ///
    /// ⚠️ 请求体**没有 reason 字段**，这是后端刻意的：要求填理由等于要求当面说「不」。
    func submit(_ decision: IntroCallDecision) async {
        await perform { safety, orderId in
            try await safety.submitIntroCallDecision(orderId: orderId, decision: decision)
        }
    }

    /// 「一直没接到电话」。
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
            // 表态之后本轮的落点由**对方**决定（我说合适 ≠ 成单）。让下一次轮询把结果带回来，
            // 不在本地假设任何结论。
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

/// 志愿者侧通话磨合页。**一次给全三个动作**，不分阶段。
///
/// 与盲人侧的两阶段不对称是刻意的：盲人那边阶段 A 唯一该做的事是拨号，多摆两个结果按钮
/// 只会让读屏用户先滑过两个此刻按不得的东西；志愿者这边不拨号（他在等来电），
/// 三个动作从一开始就都可能是对的。
///
/// 🚩 **「一直没接到电话」只在这一侧。** 对盲人来说「聊完不合适」和「没打通」结果完全一样
/// （换一位），分成两个按钮只是多一次读屏滑动；而后端确实要区分这两种口径 ——
/// 那就由这一侧提供，不让盲人替系统的统计需求多按一个键。
///
/// 数据来源是**派单载荷 + 通话端点**，不是订单详情：通话期 `order.volunteer` 恒为 null，
/// `GET /api/orders/{id}` 会 403（见 `VolunteerHomeViewModel.pendingIntroCallOrder`）。
///
/// 🔄 2026-10-13 按订单页同一套样式重做（定稿 v6，负责人：通话页与其余页面割裂）：
/// 订单页的导航栏（左返回、右求助胶囊）+ 彩色头卡（等来电紫、已说合适梅红）+ 进度绳 + 同一条底栏。
/// 两张结局页一并去掉（负责人：「这一单是你的了」「这一单已经安排好了」不要）——
/// 成单时**这一页原地变成订单页**（约好那一屏），没成时自己关掉回首页、由语音说一句。
struct VolunteerIntroCallView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = VolunteerIntroCallViewModel()
    /// 求助胶囊按下去：这一态不是 `IN_PROGRESS`，一律本地拨号（`VolunteerOrderSOSMode`）。
    @State private var showsLocalHelp = false

    let route: VolunteerIntroCallRoute

    /// 派单载荷。冷启动恢复路径上是 nil —— 那两块信息没有数据源，见 `VolunteerIntroCallRoute`。
    private var dispatchOrder: WSNewOrder? { route.dispatchOrder }

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
        }
        .onDisappear {
            viewModel.stopPolling()
        }
        // 没成：自己关掉回首页。那句中性的话已经由 view model 在落定那一刻播了
        // （`IntroCallCopy.volunteerRoundClosed`），不再停在一整屏上。
        .onChange(of: viewModel.outcome) { outcome in
            if outcome == .closed { dismiss() }
        }
    }

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
                    heroCard
                    // 复用接单后那块「本单为视障跑者」提示位，不新建组件。
                    // 接单前只剩导盲犬那一行 —— 视力情况与引导方式走
                    // `disclosesBlindRunnerNotesToVolunteer` 闸，通话发生在接单之前。
                    // 恢复路径上是空数组，该组件对空数组本来就什么都不渲染。
                    VolunteerRunnerNeedsBanner(needs: dispatchOrder?.escortNeeds ?? [])
                    paceCard
                    if let errorMessage = viewModel.errorMessage {
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
    }

    // MARK: 头卡

    /// 已经说了「合适」，在等对方。**只看自己的表态**，对方的拿不到也不该拿到。
    private var isWaiting: Bool {
        viewModel.introCall?.isWaitingForCounterpart == true
    }

    /// 等来电紫，已说合适梅红（定稿 v6，与盲人端同一套）。
    private var heroColor: Color {
        isWaiting ? AppColors.Flow.stateCalled : AppColors.Flow.stateCalling
    }

    private var runnerName: String {
        viewModel.introCall?.counterpartDisplayName(fallback: "跑者") ?? "跑者"
    }

    private var heroCard: some View {
        FlowHeroCard(style: .tinted(heroColor)) {
            if let eyebrow {
                Text(eyebrow)
                    .flowFont(FlowV2Fonts.subhead(bold: true))
                    .foregroundColor(AppColors.Flow.onHeroEyebrow)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
            RopeView(
                state: .introCall(isWaiting ? .decided : .beforeCall),
                theme: .onHero(heroColor),
                runnerName: viewModel.introCall?.counterpartName
            )
            heroBody
        }
    }

    private var heroBody: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            if let windowEnds = IntroCallCopy.volunteerWindowEndsText(windowEndsAt: viewModel.introCall?.windowEndsAt) {
                FlowHeroPill(text: windowEnds, systemImage: "clock")
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(heroAccessibilityLabel)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("volunteerIntroCallHeader")
    }

    private var title: String {
        if isWaiting { return IntroCallCopy.waitingForCounterpart }
        // 还在拉：整屏不许空白（理由同盲人侧 `blindLoadingNotice`）。
        if viewModel.introCall == nil, viewModel.errorMessage == nil { return IntroCallCopy.volunteerLoadingNotice }
        return IntroCallCopy.volunteerWaitingForCallTitle(counterpartName: runnerName)
    }

    /// 🚨 掩码号只用来**认人**，这一页刻意**没有**拨号按钮：号码在这一侧是单向的，
    /// 后端恒不下发志愿者能拨通的明文号（`IntroCallView.counterpartPhoneMasked` 的注释）。
    /// 把 `138****1234` 拼进 `tel:` 会拼成一个七位的、可能真打给别人的号码。
    private var lines: [String] {
        if isWaiting { return [IntroCallCopy.blindAfterCallSubtitle] }
        guard let masked = viewModel.introCall?.counterpartPhoneMasked?.nilIfBlank else { return [] }
        return [IntroCallCopy.volunteerIncomingNumberLine(masked: masked)]
    }

    /// 出发地与时间**优先取派单载荷，取不到回落 `IntroCallView`**（两个来源同源，契约逐字）。
    /// 距离**没有回落** —— `IntroCallView` 里没有它，而编一个比空着更糟。
    private var eyebrow: String? {
        IntroCallCopy.eyebrow(
            plannedStart: dispatchOrder?.plannedStart?.nilIfBlank ?? viewModel.introCall?.plannedStartTime,
            address: dispatchOrder?.startAddress?.nilIfBlank ?? viewModel.introCall?.startAddress,
            distanceKm: dispatchOrder?.distanceKm
        )
    }

    private var heroAccessibilityLabel: String {
        let windowEnds = IntroCallCopy.volunteerWindowEndsText(windowEndsAt: viewModel.introCall?.windowEndsAt)
        return ([eyebrow?.replacingOccurrences(of: " · ", with: "，"), title.unmaskedForSpeech] + lines.map(Optional.some) + [windowEnds])
            .compactMap { $0?.nilIfBlank }
            .joined(separator: "，")
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

    private var bottomActions: some View {
        OrderFlowBottomActions(
            owner: .volunteer,
            primary: isWaiting ? nil : OrderFlowPrimaryAction(
                title: IntroCallCopy.volunteerAcceptButtonTitle,
                isLoading: viewModel.isSubmitting,
                isEnabled: !viewModel.isSubmitting,
                accessibilityHint: "双方都说合适才算接单"
            ) {
                Task { await viewModel.submit(.accept) }
            },
            secondary: AnyView(secondaryButtons),
            safetyHub: nil
        )
    }

    /// 「不合适」与「一直没接到电话」。
    ///
    /// 🚩 **两个端点，不能合并**（`reportUnreachable` 的注释：统计口径相反）。
    /// 已经说了合适之后只留「不合适」—— 说合适意味着电话打通了，「没接到电话」此刻不成立。
    @ViewBuilder
    private var secondaryButtons: some View {
        VStack(spacing: FlowMetrics.actionButtonSpacing) {
            FlowActionButton(
                IntroCallCopy.volunteerDeclineButtonTitle,
                style: .ghost,
                isEnabled: !viewModel.isSubmitting,
                accessibilityHint: "结束这次通话确认，系统会把这一单派给下一位"
            ) {
                Task { await viewModel.submit(.decline) }
            }
            .accessibilityIdentifier("volunteerIntroCallDeclineButton")

            if !isWaiting {
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
    }
}
