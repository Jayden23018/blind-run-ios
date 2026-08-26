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
            let view: IntroCallView = try await appState.apiClient.get(
                IntroCallEndpoint.view.path(orderId: orderId)
            )
            introCall = view
        } catch let error as APIError {
            if appState.handleAuthenticatedAPIError(error) { return }
            // 409 `INTRO_CALL_NOT_ACTIVE`（或 403 —— 我们已经不是参与者了）都意味着本轮结束。
            // 到底是成了还是没成，端点自己不说，也不该说。
            await resolveFinishedRound(orderId: orderId, appState: appState)
        } catch {
            errorMessage = IntroCallCopy.loadFailed
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
        if let order: OrderDetailResponse = try? await appState.apiClient.get("/api/orders/\(orderId)") {
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
        await perform(
            path: IntroCallEndpoint.decision.path(orderId: orderId ?? 0),
            body: IntroCallDecisionRequest(decision: decision)
        )
    }

    /// 「一直没接到电话」。
    ///
    /// 🚩 **与「不合适」是两个端点，不能合并。** 后端的统计口径相反：这条只增
    /// dispatched + timeout，不动 declined —— 他并没有拒绝任何人，而 `acceptanceRate`
    /// 直接进派单评分。且这一对不进候选池硬过滤，没接到电话不代表两人不合适。
    func reportUnreachable() async {
        await perform(path: IntroCallEndpoint.unreachable.path(orderId: orderId ?? 0), body: nil)
    }

    private func perform(path: String, body: (any Encodable & Sendable)?) async {
        guard let orderId, let appState else { return }
        isSubmitting = true
        errorMessage = nil
        do {
            let _: EmptyResponse = try await appState.apiClient.post(path, body: body)
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
struct VolunteerIntroCallView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = VolunteerIntroCallViewModel()

    let route: VolunteerIntroCallRoute

    /// 派单载荷。冷启动恢复路径上是 nil —— 那两块信息没有数据源，见 `VolunteerIntroCallRoute`。
    private var dispatchOrder: WSNewOrder? { route.dispatchOrder }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                // 复用接单后那块「本单为视障跑者」提示位，不新建组件。
                // 接单前只剩导盲犬那一行 —— 视力情况与引导方式走
                // `disclosesBlindRunnerNotesToVolunteer` 闸，通话发生在接单之前。
                //
                // 恢复路径上是空数组，该组件对空数组本来就什么都不渲染（见它的 `body`）。
                VolunteerRunnerNeedsBanner(needs: dispatchOrder?.escortNeeds ?? [])

                counterpartCard
                orderFactsCard

                switch viewModel.outcome {
                case .active:
                    actionButtons
                case .matched:
                    matchedNotice
                case .closed:
                    closedNotice
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.destructive)
                        .accessibilityLabel(errorMessage)
                        .accessibilityIdentifier("volunteerIntroCallError")
                }
            }
            .padding(20)
            .readableContentColumn()
        }
        .background(AppColors.background)
        .navigationTitle("通话确认")
        .navigationBarTitleDisplayMode(.inline)
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(RunOrderStatus.pendingIntroCall.serviceStageTitle)
                .font(.title2.bold())
                .foregroundColor(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(RunOrderStatus.pendingIntroCall.serviceStageSubtitle)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("volunteerIntroCallHeader")
    }

    /// 对方是谁 + 会用哪个号码打给你。
    ///
    /// 🚨 掩码号只用来**认人**，这里刻意**没有**拨号按钮：号码在这一侧是单向的，
    /// 后端恒不下发志愿者能拨通的明文号（`IntroCallView.counterpartPhoneMasked` 的注释）。
    /// 把 `138****1234` 拼进 `tel:` 会拨成 `1381234` —— 空号，而界面上看不出任何异常。
    @ViewBuilder
    private var counterpartCard: some View {
        if let introCall = viewModel.introCall {
            VStack(alignment: .leading, spacing: 8) {
                Text("盲人跑者")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)
                Text(introCall.counterpartDisplayName(fallback: "跑者"))
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                if let masked = introCall.counterpartPhoneMasked?.nilIfBlank {
                    Text("\(masked)　\(IntroCallCopy.volunteerPhoneHint)")
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let windowEndsAt = introCall.windowEndsAt?.nilIfBlank {
                    Text("请在 \(windowEndsAt.displayDateTime) 前完成这次通话确认")
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.secondaryBackground)
            .cornerRadius(8)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("volunteerIntroCallCounterpartCard")
        }
    }

    /// 出发地与时间**优先取派单载荷，取不到回落 `IntroCallView`**。
    ///
    /// 两个来源同源（契约逐字：`IntroCallView.startAddress` 与 `NEW_ORDER` 的 `startAddress`
    /// 是同一个值），所以回落不会让两条路径显示不同的地址。回落存在的理由只有冷启动恢复：
    /// 那时派单推送已经随进程一起没了。
    ///
    /// 距离与配速**没有回落** —— `IntroCallView` 里没有它们，而编一个比空着更糟。
    /// 不要在这里补「距离：暂无」之类的占位：志愿者据此判断要不要接这一单，
    /// 一个说不出内容的占位行比没有这一行更容易被当成真的。
    private var orderFactsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let address = dispatchOrder?.startAddress?.nilIfBlank
                ?? viewModel.introCall?.startAddress?.nilIfBlank {
                Text("出发地：\(address)")
            }
            if let plannedStart = dispatchOrder?.plannedStart?.nilIfBlank
                ?? viewModel.introCall?.plannedStartTime?.nilIfBlank {
                Text("时间：\(plannedStart.displayDateTime)")
            }
            if let distance = dispatchOrder?.distanceKm {
                Text(String(format: "距离：%.1fkm", distance))
            }
            if let pace = dispatchOrder?.pacePreference?.nilIfBlank {
                Text("配速：\(PacePreference(rawValue: pace)?.displayName ?? pace)")
            }
        }
        .font(AppFonts.body())
        .foregroundColor(AppColors.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("volunteerIntroCallOrderFacts")
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            PrimaryButton(IntroCallCopy.volunteerAcceptButtonTitle, isLoading: viewModel.isSubmitting) {
                Task { await viewModel.submit(.accept) }
            }
            .disabled(viewModel.isSubmitting)
            .accessibilityLabel(IntroCallCopy.volunteerAcceptButtonTitle)
            .accessibilityHint("双方都说合适才算接单")
            .accessibilityIdentifier("volunteerIntroCallAcceptButton")

            secondaryButton(
                title: IntroCallCopy.volunteerDeclineButtonTitle,
                hint: "结束这次通话确认，系统会把这一单派给下一位",
                identifier: "volunteerIntroCallDeclineButton",
                tint: AppColors.destructive
            ) {
                Task { await viewModel.submit(.decline) }
            }

            secondaryButton(
                title: IntroCallCopy.volunteerUnreachableButtonTitle,
                hint: IntroCallCopy.volunteerUnreachableAccessibilityHint,
                identifier: "volunteerIntroCallUnreachableButton",
                tint: AppColors.textSecondary
            ) {
                Task { await viewModel.reportUnreachable() }
            }
        }
    }

    /// 成单后**不自动跳转**：志愿者刚放下电话，被弹进另一个页面是失去控制感的；
    /// 而且自动 push 要拿一个 `isPresented` 绑定，返回时会立刻重新 push 回去。
    /// 给一个明确的入口，他自己决定什么时候进。
    @ViewBuilder
    private var matchedNotice: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(IntroCallCopy.volunteerMatched)
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(IntroCallCopy.volunteerMatched)
                .accessibilityIdentifier("volunteerIntroCallMatchedNotice")

            if let order = viewModel.matchedOrder {
                NavigationLink {
                    VolunteerInServiceView(orderId: order.orderId, initialOrder: order)
                } label: {
                    Text("进入服务流程")
                        .font(AppFonts.body().weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                        .background(AppColors.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityLabel("进入服务流程")
                .accessibilityIdentifier("volunteerIntroCallEnterServiceButton")
            }
        }
    }

    private var closedNotice: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(IntroCallCopy.volunteerRoundClosed)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(IntroCallCopy.volunteerRoundClosed)
                .accessibilityIdentifier("volunteerIntroCallClosedNotice")
            PrimaryButton("返回首页") { dismiss() }
                .accessibilityLabel("返回首页")
        }
    }

    private func secondaryButton(
        title: String,
        hint: String,
        identifier: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(tint)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
        }
        .disabled(viewModel.isSubmitting)
        .buttonShapeOutlineIfNeeded(color: tint)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
        .accessibilityIdentifier(identifier)
    }
}
