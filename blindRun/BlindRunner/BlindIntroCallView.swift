import SwiftUI

// MARK: - 通话页该不该弹出来

/// 订单状态页把通话页推出来的那点状态。**两个 Bool，但转移规则不平凡**，
/// 所以打包成一个可测的值类型而不是散在两个 `@State` 上 —— 它的每一条转移
/// 都对应一个已经发生过（或差点发生）的缺陷：
///
/// - **关过一次就不再自动弹**：否则用户按「返回订单」后，5 秒轮询回来 `status` 还是
///   `PENDING_INTRO_CALL`，页面又弹出来 —— 一个关不掉的全屏页。志愿者侧踩过同一个坑，
///   那边的记号叫 `autoOpenedIntroCallOrderId`（`VolunteerHomeView.swift`）。
/// - **离开通话态时复位**：记号是**本轮**的，不是这一单的。本轮没聊成会退回
///   `PENDING_MATCH`，下一位候选人上来又是 `PENDING_INTRO_CALL` —— 那是一件新的、
///   必须让用户知道的事。不复位的话，第一次关掉之后这一单余下的每一位候选人都不再自动弹。
///
/// 判定只看 `status`，不看订单号：换单时这一页会整个重建，`@State` 跟着归零。
struct BlindIntroCallPresentation: Equatable {
    /// 通话页正开着。
    var isShowing = false
    /// **本轮**已经被用户手动关过一次。
    private(set) var dismissedThisRound = false

    /// 订单状态变了。
    mutating func apply(status: RunOrderStatus) {
        guard status == .pendingIntroCall else {
            isShowing = false
            dismissedThisRound = false
            return
        }
        guard !dismissedThisRound else { return }
        isShowing = true
    }

    /// 用户按了「返回订单」。**只有这一条路会置起记号** —— 系统主动收起
    /// （状态变了）走的是 `apply`，那种情况下本轮已经结束，记号该复位而不是置起。
    mutating func dismiss() {
        isShowing = false
        dismissedThisRound = true
    }
}

// MARK: - 盲人侧「接单前通话磨合」独立页

/// 盲人侧通话磨合页。**整屏只有一件事。**
///
/// 2026-09-05 从 `BlindOrderStatusView.introCallSection` 提出来。此前它是订单状态页里的
/// 一段，与「把行程告诉家人」「地图」「预约信息」「状态变更记录」共用一条滚动 ——
/// 而这一态盲人只有一件该做的事（打这通电话），下面那些全是跑起来之后才用得上的。
/// 志愿者侧从一开始就是独立页（`VolunteerIntroCallView`），两端不对称没有产品理由。
///
/// 🚩 **它共用 `BlindOrderStatusViewModel`，不另起一个 view model、也不另起一条轮询。**
/// 与志愿者侧的不对称是**契约造成的**，不是实现选择：通话期 `order.volunteer` 恒为 null，
/// 志愿者调 `GET /api/orders/{id}` 会 403，所以他那边必须自己轮询通话端点；
/// 而盲人读得到订单详情，`loadOrder` 每 5 秒一轮本来就会顺带把通话数据刷回来
/// （`refreshIntroCallIfNeeded`）。再起一条轮询等于对同一个端点每 5 秒打两次。
///
/// 直接后果：订单一离开 `PENDING_INTRO_CALL`（双方都说合适 → `PENDING_ACCEPT`，
/// 或本轮没成 → `PENDING_MATCH`），订单页那边的 `status` 一变就会把这一页收起来，
/// 这一页自己不需要判断「本轮结束了没有」。
///
/// 三个阶段的判定顺序**逐条搬自原 `introCallSection`**，不许重排（每条的理由见分支内注释）。
struct BlindIntroCallView: View {
    @EnvironmentObject private var speechService: SpeechService
    /// 两阶段切换的唯一信号源。iOS 不告诉 App「这通电话打完了」——
    /// 能观察到的只有「拨号确认框把我推到后台、然后我回来了」。
    @Environment(\.scenePhase) private var scenePhase

    /// 与订单状态页**同一个实例**。见类型注释。
    @ObservedObject var viewModel: BlindOrderStatusViewModel
    let onClose: () -> Void

    /// 用户按过拨号按钮。
    @State private var didDial = false
    /// 拨号之后 App 回到前台了 ⇒ 进入阶段 B（给出「聊过了，合适」）。
    ///
    /// ⚠️ 这是**推断，不是事实**：在系统拨号确认框上点「取消」走的是同一条路径。
    /// 所以阶段 B 一定要保留「再打一次」，见 `stageBActions`。
    @State private var returnedFromDialer = false
    /// 进页面时把 VoiceOver 焦点钉在标题上。
    ///
    /// 这一页是**自动弹出来**的，焦点落点不确定的代价比在订单页上更大：用户可能正在听
    /// 别的东西，屏幕换了而焦点还在旧位置，他会以为按钮没出现。
    @AccessibilityFocusState private var titleFocused: Bool

    /// 主按钮高度。比订单页的 140 大：那一页主按钮上面压着一张状态卡（≈150pt），
    /// 这一页只有标题两行加一张信息卡，同样的首屏能给主按钮更多。
    @ScaledMetric(relativeTo: .largeTitle) private var primaryActionButtonHeight: CGFloat = 180

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    factsCard
                    actions
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
                // 与订单状态页同一条：这一页的标题、信息行都是长文本，
                // iPad 上不限宽会横跨整屏。
                .readableContentColumn()
            }
            .background(AppColors.background)
            .navigationTitle("通话确认")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(IntroCallCopy.blindCloseButtonTitle, action: onClose)
                        .accessibilityLabel(IntroCallCopy.blindCloseButtonTitle)
                        .accessibilityHint(IntroCallCopy.blindCloseAccessibilityHint)
                        .accessibilityIdentifier("blindIntroCallCloseButton")
                }
            }
            // 「重复当前状态」在盲人端每一页都在同一个位置。这一页也不例外 ——
            // 它是读屏用户确认「我现在在哪一步」的唯一手段，缺了这一页就成了孤岛。
            .safeAreaInset(edge: .bottom) {
                PrimaryButton("重复当前状态") {
                    viewModel.repeatStatus()
                }
                .accessibilityLabel("重复当前状态")
                .accessibilityHint("点击后重新播报当前订单状态")
                .accessibilityIdentifier("blindIntroCallRepeatStatusButton")
                .readableContentColumn()
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(AppColors.background)
            }
        }
        .onAppear { titleFocused = true }
        .onChange(of: scenePhase) { phase in
            guard phase == .active, didDial else { return }
            returnedFromDialer = true
        }
    }

    // MARK: - 头部

    /// 标题按阶段换，副标题跟着换。**两个 Text 不合成一个焦点**：
    /// 标题是「谁 / 现在该干什么」，副标题是规则说明 —— 已经听过一遍的人该能一滑跳过。
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headerTitle)
                .font(.title.bold())
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)
                .accessibilityIdentifier("blindIntroCallTitle")

            Text(headerSubtitle)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var counterpartName: String {
        viewModel.introCall?.counterpartDisplayName(fallback: "这位志愿者") ?? "这位志愿者"
    }

    private var headerTitle: String {
        if viewModel.isWaitingForIntroCallCounterpart {
            return IntroCallCopy.waitingForCounterpart
        }
        if viewModel.introCall == nil {
            // 失败与加载中共用这个标题位，各自的说明在副标题里分开。
            return IntroCallCopy.blindPageTitle(counterpartName: counterpartName)
        }
        return returnedFromDialer
            ? IntroCallCopy.blindAfterCallTitle(counterpartName: counterpartName)
            : IntroCallCopy.blindPageTitle(counterpartName: counterpartName)
    }

    private var headerSubtitle: String {
        if viewModel.isWaitingForIntroCallCounterpart {
            // 🚨 标题已经是那句进行时了，副标题不许再补一句「等待对方确认」——
            // 我们拿不到对方的表态，说了就是编（`IntroCallView` 的类型注释）。
            return IntroCallCopy.blindPageSubtitle
        }
        if viewModel.introCall == nil {
            return viewModel.introCallUnavailable
                ? IntroCallCopy.loadFailed
                : IntroCallCopy.blindLoadingNotice
        }
        return returnedFromDialer
            ? IntroCallCopy.blindAfterCallSubtitle
            : IntroCallCopy.blindPageSubtitle
    }

    // MARK: - 这一单是哪一单

    /// 出发地、时间、本轮剩余分钟。三项都来自 `IntroCallView`，**后端已经在下发，
    /// 此前盲人侧一行都没用上** —— 内嵌在订单页时它们是冗余的（订单信息就在同一页下面），
    /// 独立出来之后就不是了：这一页没有别的地方能告诉用户这通电话是为哪一单打的。
    ///
    /// 任何一项取不到就整行不出现，**不摆占位**。理由与志愿者侧 `orderFactsCard`
    /// 逐字相同：一个说不出内容的占位行比没有这一行更容易被当成真的。
    @ViewBuilder
    private var factsCard: some View {
        if let introCall = viewModel.introCall, !factRows(introCall).isEmpty {
            let rows = factRows(introCall)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows, id: \.self) { row in
                    Text(row)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.secondaryBackground)
            .cornerRadius(8)
            // 三行合成一个焦点：它们回答的是同一个问题（这是哪一单），
            // 拆成三次滑动只是在主动作之前多插两步。
            .accessibilityElement(children: .combine)
            .accessibilityLabel(rows.joined(separator: "。"))
            .accessibilityIdentifier("blindIntroCallFacts")
        }
    }

    private func factRows(_ introCall: IntroCallView) -> [String] {
        var rows: [String] = []
        if let address = introCall.startAddress?.nilIfBlank {
            rows.append("\(IntroCallCopy.blindStartAddressPrefix)：\(address)")
        }
        if let plannedStart = introCall.plannedStartTime?.nilIfBlank {
            rows.append("\(IntroCallCopy.blindPlannedTimePrefix)：\(plannedStart.displayDateTime)")
        }
        // 每轮订单轮询都会重新赋值 `introCall`，所以这个数字跟着一起重算 ——
        // 不需要（也不该）为它单起一条每秒跳一次的计时器：读屏用户听到的是一个
        // 会自己变化的数字，而分钟级的精度对「要不要现在打」这个决定已经足够。
        if let remaining = IntroCallCopy.blindWindowRemainingText(windowEndsAt: introCall.windowEndsAt) {
            rows.append(remaining)
        }
        return rows
    }

    // MARK: - 动作区

    /// 四个分支，**顺序逐条搬自原 `introCallSection`**，判定条件一字未改。
    @ViewBuilder
    private var actions: some View {
        if viewModel.isWaitingForIntroCallCounterpart {
            // 🚩 **表过态之后这一支优先，且不依赖再拉一次 view。**
            // 服务端已经记下了我的表态，此刻拉不拉得到通话数据都不改变「在等对方」这件事。
            // 排在失败块前面是刻意的：说完「合适」之后不该再看到「换一位」当主动作。
            waitingActions
        } else if viewModel.introCall == nil, viewModel.introCallUnavailable {
            loadFailedActions
        } else if viewModel.introCall != nil {
            // 走到这里 = 还没表过态（表过的在上面第一支）。
            if returnedFromDialer {
                stageBActions
            } else {
                stageAActions
            }
        } else {
            // 还在拉。**整屏不许空白** —— 见 `blindLoadingNotice`。
            // 「换一位」在这里也留着：数据拉多久用户都有权结束这一轮，
            // 不该被一个转圈按在原地等 20 分钟窗口超时。
            VStack(spacing: 14) {
                ProgressView()
                    .tint(AppColors.primary)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                declineButton
            }
            .accessibilityIdentifier("blindIntroCallLoading")
        }
    }

    /// 阶段 A：还没拨号。主动作只有一个 —— 打这通电话。
    private var stageAActions: some View {
        VStack(spacing: 14) {
            primaryButton(
                title: IntroCallCopy.callButtonTitle,
                hint: IntroCallCopy.callAccessibilityHint,
                identifier: "blindIntroCallDialButton",
                tint: AppColors.primary,
                action: dial
            )
            declineButton
        }
    }

    /// 阶段 B：拨号返回后。
    ///
    /// 🚩 **必须保留「再打一次」。** 阶段切换的判定（点过拨号按钮 + `scenePhase` 回到
    /// `.active`）是**推断不是事实**：用户在系统拨号确认框上点「取消」会走同一条路径，
    /// 界面于是变成他没预期的样子。保留拨号入口 = 推断错了也有退路。
    /// **这处冗余是刻意的，不要以「阶段 B 不该有拨号按钮」为由删掉。**
    private var stageBActions: some View {
        VStack(spacing: 14) {
            primaryButton(
                title: IntroCallCopy.acceptButtonTitle,
                hint: IntroCallCopy.acceptAccessibilityHint,
                identifier: "blindIntroCallAcceptButton",
                tint: AppColors.success
            ) {
                Task { await viewModel.submitIntroCallDecision(.accept) }
            }
            dialAgainButton
            declineButton
        }
    }

    /// 已表态、在等对方。**这一屏刻意没有主动作** —— 此刻用户没有该做的事，
    /// 摆一个大按钮只会让他以为还要再做点什么。
    private var waitingActions: some View {
        VStack(spacing: 14) {
            // 拿得到号码就仍然给「再打一次」—— 等待期间对方可能想再聊两句。
            if viewModel.introCall?.dialableCounterpartPhone != nil {
                dialAgainButton
            }
            declineButton
        }
    }

    /// 通话数据拉不到。
    ///
    /// 🚨 播报由 `refreshIntroCallIfNeeded` 在失败那一跳负责（只播一次），这里只管看得见的那半。
    /// 措辞不许说成「打不通」「对方不在」：失败的是我们这次取号码的请求，
    /// 志愿者那边一切正常 —— 说错方向会让盲人以为该换人，而他只需要重试一下。
    private var loadFailedActions: some View {
        VStack(spacing: 14) {
            primaryButton(
                title: IntroCallCopy.retryButtonTitle,
                hint: IntroCallCopy.retryAccessibilityHint,
                identifier: "blindIntroCallRetryButton",
                tint: AppColors.primary
            ) {
                Task { await viewModel.reloadIntroCall() }
            }
            declineButton
        }
    }

    private var dialAgainButton: some View {
        secondaryButton(
            title: IntroCallCopy.callAgainButtonTitle,
            hint: IntroCallCopy.callAccessibilityHint,
            identifier: "blindIntroCallDialAgainButton",
            tint: AppColors.primary,
            action: dial
        )
    }

    private var declineButton: some View {
        secondaryButton(
            title: IntroCallCopy.declineButtonTitle,
            hint: IntroCallCopy.declineAccessibilityHint,
            identifier: "blindIntroCallDeclineButton",
            tint: AppColors.destructive
        ) {
            Task { await viewModel.submitIntroCallDecision(.decline) }
        }
    }

    /// 拨号。**先通知对方再立刻拨**，不等响应（理由在 `introCallDialURL` 上）。
    ///
    /// `didDial` 在这里就置 true，而不是等 `openURL` 回调 —— 系统拨号确认框弹出
    /// 本身就会把 App 推到后台，回来时要能认出「刚才去拨号了」。
    ///
    /// 🚨 拿不到 URL 时**必须出声**。这条路的唯一成因是通话数据没拉回来，
    /// 而静默 return 的表现是「按了没反应」—— 对盲人端就是事故。
    private func dial() {
        guard let url = viewModel.introCallDialURL() else {
            speechService.speakError(IntroCallCopy.loadFailed)
            return
        }
        didDial = true
        EmergencyDialer.dial(url)
    }

    private func primaryButton(
        title: String,
        hint: String,
        identifier: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppFonts.largeTitle())
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: primaryActionButtonHeight)
                .background(tint)
                .cornerRadius(16)
        }
        .disabled(viewModel.isPerformingAction)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
        .accessibilityIdentifier(identifier)
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
                .frame(minHeight: 64)
        }
        .disabled(viewModel.isPerformingAction)
        .buttonShapeOutlineIfNeeded(color: tint)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
        .accessibilityIdentifier(identifier)
    }
}
