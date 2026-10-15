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

// MARK: - 盲人侧「先通个电话」独立页

/// 盲人侧通话页，三屏（#434，视觉稿 v2 `docs/ui/mockups/intro-call-meetup-plan-20261015/` ③④）：
///
/// - **B1 待通话**：「陪跑员李*已响应」，主按钮「致电陪跑员李*」，次「更换陪跑员」。
/// - **B2 等待见面安排**：只在拨过号、App **从后台**回到前台之后进入。**没有主按钮** ——
///   此刻没有该盲人做的事。v6 的「聊过了，合适」去掉了：「合适」现在是确认陪跑员发来的安排单。
/// - **B3 确认见面安排**：标题 + 每项一个读屏元素（顺序固定）+ 两个同为 84pt 的大按钮
///   「确认见面安排」「有异议，致电沟通」+「更换陪跑员」；只有「求助与安全」常驻底部。
///
/// 哪一屏由 `BlindOrderStatusViewModel.introCallRunnerStep` 决定，**服务端安排单优先**于
/// 本地「回过前台」标记 —— 关页重进、杀进程重启都回得到 B3（修审查 #4）。
///
/// 2026-09-05 从 `BlindOrderStatusView.introCallSection` 提出来；2026-10-13 按订单页样式重做（v6）；
/// 2026-10-15 视觉稿 v2：通话整步沿用进度绳上「匹配 / 邀请」那一格的颜色，去掉 v6 的紫与梅红。
///
/// 🚩 **它共用 `BlindOrderStatusViewModel`，不另起一个 view model、也不另起一条轮询。**
/// 与志愿者侧的不对称是**契约造成的**，不是实现选择：通话期 `order.volunteer` 恒为 null，
/// 志愿者调 `GET /api/orders/{id}` 会 403，所以他那边必须自己轮询通话端点；
/// 而盲人读得到订单详情，`loadOrder` 每 5 秒一轮本来就会顺带把通话数据刷回来
/// （`refreshIntroCallIfNeeded`）。再起一条轮询等于对同一个端点每 5 秒打两次。
///
/// 直接后果：订单一离开 `PENDING_INTRO_CALL`（约好 → `PENDING_ACCEPT`，
/// 或本轮没成 → `PENDING_MATCH`），订单页那边的 `status` 一变就会把这一页收起来，
/// 这一页自己不需要判断「本轮结束了没有」。
struct BlindIntroCallView: View {
    @EnvironmentObject private var speechService: SpeechService

    /// 与订单状态页**同一个实例**。见类型注释。
    @ObservedObject var viewModel: BlindOrderStatusViewModel
    /// 「求助与安全」。宿主先收起这一页、收起动画结束后再打开求助中心 ——
    /// 全屏页盖着的时候，订单页那一层弹不出第二个页面。
    var onOpenSafetyHub: () -> Void = {}
    let onClose: () -> Void

    /// 进页面、安排单刚到、陪跑员改了一版时，把 VoiceOver 焦点钉在标题上。
    ///
    /// 这一页是**自动弹出来**的，焦点落点不确定的代价比在订单页上更大：用户可能正在听
    /// 别的东西，屏幕换了而焦点还在旧位置，他会以为按钮没出现。
    @AccessibilityFocusState private var titleFocused: Bool

    /// B3 两枚大按钮的高度（视觉稿决定 3：「确认」与「有异议」同样高，避免让人觉得被迫同意）。
    /// 现有 `FlowActionButton` 最高是 `.call` 的 80pt，而共用设计组件归 #433，所以这两枚在本文件里画。
    static let planDecisionButtonMinHeight: CGFloat = 84

    var body: some View {
        NavigationStack {
            OrderFlowScaffold(bottom: bottomActions) {
                if isReviewingPlan, let layout = planLayout {
                    planContent(layout)
                } else {
                    heroCard
                }
            }
            .navigationTitle(isReviewingPlan ? IntroCallCopy.blindPlanPageTitle : IntroCallCopy.pageTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    // 看起来是返回箭头（与订单页同一个位置、同一个样子），读屏仍念「返回订单」——
                    // 盲人需要知道退回去之后到哪儿（`blindCloseButtonTitle` 的注释）。
                    Button(action: onClose) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(AppColors.Flow.primaryText)
                            .frame(width: 44, height: 44, alignment: .leading)
                            .contentShape(Rectangle().size(width: 64, height: 64))
                    }
                    .accessibilityLabel(IntroCallCopy.blindCloseButtonTitle)
                    .accessibilityHint(IntroCallCopy.blindCloseAccessibilityHint)
                    .accessibilityIdentifier("blindIntroCallCloseButton")
                }
                // 「重复当前状态」在盲人端每一页都在。它是读屏用户确认「我现在在哪一步」的唯一手段
                // （系统的 Speak Screen 读不到一次性的 announcement）。位置与订单页那枚相同。
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: repeatCurrentState) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(AppColors.Flow.accent)
                            // 工具栏按钮的系统触达区约 44pt，低于盲人端 64pt 下限 ——
                            // `contentShape` 撑大命中区而不改变视觉尺寸（同订单页那枚）。
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle().size(width: 64, height: 64))
                    }
                    .accessibilityLabel("重复当前状态")
                    .accessibilityHint("点击后重新播报这一步的内容")
                    .accessibilityIdentifier("blindIntroCallRepeatStatusButton")
                }
            }
        }
        .onAppear { titleFocused = true }
        .onChange(of: viewModel.introCallPlanFocusRequest) { _ in
            refocusTitle()
        }
    }

    // MARK: - 子状态

    private var step: IntroCallRunnerStep { viewModel.introCallRunnerStep }

    /// B3（含刚确认成功、订单还没转走的那几秒）。
    private var isReviewingPlan: Bool {
        step == .reviewingPlan || step == .confirmed
    }

    /// 拉不到，或拉到了但安排单读不懂。🚨 后者**不许**退回 B1 / B2：陪跑员已经提交了，
    /// 盲人以为对方还没动静会一直等到窗口超时（`IntroCallView.hasUnreadablePlan`）。
    private var isUnavailable: Bool {
        (viewModel.introCall == nil && viewModel.introCallUnavailable)
            || viewModel.introCall?.hasUnreadablePlan == true
    }

    private var isLoading: Bool {
        viewModel.introCall == nil && !viewModel.introCallUnavailable && !viewModel.isWaitingForIntroCallCounterpart
    }

    // MARK: - B1 / B2 头卡

    private var palette: BlindHeroPalette {
        // 视觉稿 v2 决定 1：通话这一步不再加颜色，整步沿用「匹配 / 邀请」那一格。
        BlindHeroPalette(tone: .matching)
    }

    private var heroCard: some View {
        FlowHeroCard(style: palette.cardStyle) {
            if let eyebrow {
                Text(eyebrow)
                    .flowFont(FlowV2Fonts.subhead(bold: true))
                    .foregroundColor(palette.eyebrow)
                    .fixedSize(horizontal: false, vertical: true)
                    // 自成一个读屏元素：视觉稿的进入朗读从标题开始，但时间地点不能因此听不到。
                    .accessibilityLabel(eyebrow.replacingOccurrences(of: " · ", with: "，"))
                    .accessibilityIdentifier("blindIntroCallEyebrow")
            }
            RopeView(
                // 绳子第一格上的小图标区分子状态：B1 电话；B2 不画电话（「单子」图标随 #433 加）。
                state: .introCall(ropeStage),
                theme: palette.ropeTheme,
                volunteerInitial: counterpartInitial,
                perspective: .runner
            )
            .frame(maxWidth: RopeGeometry.width * 1.2)
            .frame(maxWidth: .infinity)
            heroBody
        }
    }

    private var ropeStage: IntroCallRopeStage {
        switch step {
        case .awaitingCall: return .beforeCall
        case .awaitingPlan, .reviewingPlan: return .afterCall
        case .confirmed: return .decided
        }
    }

    private var heroBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headerTitle)
                .flowFont(FlowV2Fonts.title())
                .foregroundColor(palette.strong)
                .fixedSize(horizontal: false, vertical: true)
            Text(headerSubtitle)
                .flowFont(FlowV2Fonts.callout())
                .foregroundColor(palette.body)
                .fixedSize(horizontal: false, vertical: true)
            if let remaining {
                FlowHeroPill(text: remaining, systemImage: "clock")
                    .padding(.top, 4)
            }
            if isLoading {
                // 还在拉。**整屏不许空白** —— 副标题已经在说「正在获取」，转圈只给眼睛看。
                ProgressView()
                    .tint(.white)
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("blindIntroCallLoading")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // 🔴 正文合成**一个**元素：「谁 / 现在该干什么 / 还剩多久」一站听完，再滑一下就是按钮。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(heroAccessibilityLabel)
        .accessibilityAddTraits(.isHeader)
        // 倒计时按分钟静默更新：读屏不主动念，只在剩 5 / 1 分钟时由 view model 播报。
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityFocused($titleFocused)
        .accessibilityIdentifier("blindIntroCallTitle")
    }

    /// 视觉稿 B1 原话：「陪跑员李*已响应。请先与陪跑员通话。通话后，对方将提交见面安排供你确认。剩余 19 分钟。」
    private var heroAccessibilityLabel: String {
        let title = headerTitle.unmaskedForSpeech
        return [title.hasSuffix("。") ? title : title + "。", headerSubtitle, remaining.map { $0 + "。" }]
            .compactMap { $0?.nilIfBlank }
            .joined()
    }

    /// 「明天早上 7:00 · 朝阳公园南门」。
    private var eyebrow: String? {
        IntroCallCopy.eyebrow(
            plannedStart: viewModel.introCall?.plannedStartTime,
            address: viewModel.introCall?.startAddress
        )
    }

    /// 「剩余 19 分钟」/「剩余不到 1 分钟」。每轮订单轮询都会重新赋值 `introCall`，所以这个数字跟着重算 ——
    /// 分钟级的精度对「要不要现在打」已经足够，不单起每秒一跳的计时器。
    private var remaining: String? {
        guard let endsAt = viewModel.introCall?.windowEndsAt?.nilIfBlank?.backendTimestamp else { return nil }
        // 已过期而服务端还没转走的那几秒也落「不到 1 分钟」，不说「已超时」（超时由服务端宣布）。
        return IntroCallMeetupCopy.remainingText(windowEndsAt: endsAt, now: Date())
    }

    /// 屏幕上的称呼保留掩码（`李*`），读屏一路各自去星号。
    private var counterpartName: String {
        viewModel.introCall?.counterpartName?.nilIfBlank ?? ""
    }

    /// 绳子右边那个头像里的字：候选人的姓。拿不到写「陪」（同订单页）。
    private var counterpartInitial: String {
        counterpartName.nilIfBlank?.unmaskedForSpeech.first.map(String.init) ?? "陪"
    }

    private var headerTitle: String {
        // 已确认、但确认之后那次刷新没拉到安排单（订单马上就会转走）：不画 B1 / B2 的话。
        if step == .confirmed { return IntroCallCopy.blindPlanPageTitle }
        return step == .awaitingPlan && !isUnavailable
            ? IntroCallCopy.blindAwaitingPlanTitle
            : IntroCallCopy.blindAwaitingCallTitle(counterpartName: counterpartName)
    }

    private var headerSubtitle: String {
        // 「已经告诉系统你觉得合适，约好之后会通知你。」—— 进行时，不说对方的表态（那句的注释）。
        if step == .confirmed { return IntroCallCopy.waitingForCounterpart }
        if isUnavailable { return IntroCallCopy.loadFailed }
        if isLoading { return IntroCallCopy.blindLoadingNotice }
        return step == .awaitingPlan ? IntroCallCopy.blindAwaitingPlanSubtitle : IntroCallCopy.blindAwaitingCallSubtitle
    }

    // MARK: - B3 确认见面安排

    private var planLayout: (titleSpeech: String, changeCount: Int, rows: [BlindMeetupPlanRow])? {
        guard let view = viewModel.introCall, let plan = view.meetupPlan else { return nil }
        return BlindMeetupPlanLayout.rows(
            plan: plan,
            original: view.originalArrangement,
            volunteerName: view.counterpartDisplayName(fallback: "")
        )
    }

    @ViewBuilder
    private func planContent(_ layout: (titleSpeech: String, changeCount: Int, rows: [BlindMeetupPlanRow])) -> some View {
        planHeader(layout)
        FlowCard {
            VStack(spacing: 0) {
                ForEach(Array(layout.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { FlowSeparator() }
                    planRow(row)
                }
            }
        }
        planDecisionButtons
    }

    /// 头部：「陪跑员李*已提交」+ 大字「见面安排（2 项变更）」+ 剩余时间。不画绳子（视觉稿决定 2）。
    /// **读屏只念一句**：`planSpeech.title`（「陪跑员李*已提交见面安排，共 2 项变更。」，去星号）。
    private func planHeader(_ layout: (titleSpeech: String, changeCount: Int, rows: [BlindMeetupPlanRow])) -> some View {
        FlowHeroCard(style: palette.cardStyle) {
            VStack(alignment: .leading, spacing: 8) {
                Text(IntroCallCopy.blindPlanSubmittedBy(counterpartName: counterpartName))
                    .flowFont(FlowV2Fonts.subhead(bold: true))
                    .foregroundColor(palette.eyebrow)
                    .fixedSize(horizontal: false, vertical: true)
                Text(viewModel.introCallPlanChangedNotice
                     ? IntroCallCopy.blindPlanChangedHeadline
                     : IntroCallCopy.blindPlanHeadline(changeCount: layout.changeCount))
                    .flowFont(FlowV2Fonts.title())
                    .foregroundColor(palette.strong)
                    .fixedSize(horizontal: false, vertical: true)
                if let remaining {
                    FlowHeroPill(text: remaining, systemImage: "clock")
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // 视觉稿 B3 ① 只念标题这一句。剩余时间靠剩 5 / 1 分钟那两次播报与 10 分钟提醒，
            // 不塞进 ①：标题之后紧接着就是 ② 开跑时间，顺序是视觉稿钉死的。
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(layout.titleSpeech)
            .accessibilityAddTraits(.isHeader)
            .accessibilityFocused($titleFocused)
            .accessibilityIdentifier("blindIntroCallPlanTitle")
        }
    }

    private func planRow(_ row: BlindMeetupPlanRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title = row.title {
                HStack(spacing: 8) {
                    Text(title)
                        .flowFont(FlowFonts.rowLabel())
                        .foregroundColor(AppColors.Flow.secondaryText)
                    if row.isChanged {
                        // 「已变更」浅蓝小标签 + 下面一行「原定 …」。不用删除线：读屏念不出删除线（视觉稿决定 4）。
                        Text("已变更")
                            .flowFont(FlowFonts.rowDetail())
                            .foregroundColor(AppColors.Flow.onBlueTint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(AppColors.Flow.blueTint)
                            .clipShape(Capsule())
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(row.values, id: \.self) { value in
                Text(value)
                    .flowFont(FlowFonts.rowValue())
                    .foregroundColor(AppColors.Flow.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let original = row.original {
                Text(original)
                    .flowFont(FlowFonts.rowDetail())
                    .foregroundColor(AppColors.Flow.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, FlowMetrics.infoRowHorizontalPadding)
        .padding(.vertical, 14)
        // 🔴 每项**一个**读屏元素，标签取 `planSpeech` 那一句：改过的项念「已变更：由 X 改为 Y」，地点再报距离。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.speech)
        .modifier(PlanRowIdentifier(kind: row.kind))
    }

    /// 红条 +「确认见面安排」+「有异议，致电沟通」+「更换陪跑员」。放在滚动区里，不进底栏 ——
    /// 两枚 84pt 再加两枚 64pt 贴底会吃掉半屏，而视觉稿只让「求助与安全」常驻底部。
    private var planDecisionButtons: some View {
        VStack(spacing: FlowMetrics.actionButtonSpacing) {
            if viewModel.introCallConfirmFailed {
                // 修审查 #3：此前确认失败只有语音。屏幕上这一条与播报**同时**出现；
                // 读屏也滑得到它（紧挨在「确认见面安排」前面），漏听了那句播报还能在这里再听一次。
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .accessibilityHidden(true)
                    Text(IntroCallCopy.blindConfirmNotDeliveredBanner)
                        .flowFont(FlowFonts.rowValue())
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundColor(AppColors.Flow.helpText)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.Flow.helpBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: FlowMetrics.buttonRadius, style: .continuous)
                        .strokeBorder(AppColors.Flow.helpStroke, lineWidth: 1.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: FlowMetrics.buttonRadius, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("blindIntroCallConfirmFailedBanner")
            }

            PlanDecisionButton(
                title: IntroCallCopy.blindConfirmPlanButtonTitle,
                systemImage: "checkmark",
                kind: .confirm,
                isEnabled: !viewModel.isPerformingAction && step == .reviewingPlan,
                accessibilityHint: IntroCallCopy.blindConfirmPlanAccessibilityHint
            ) {
                Task { await viewModel.confirmIntroCallPlan() }
            }
            .accessibilityIdentifier("blindIntroCallConfirmPlanButton")

            // 「有异议」直接拨号，安排单保留；陪跑员那边只会再收到一次「跑者正在给你打电话」。
            PlanDecisionButton(
                title: IntroCallCopy.blindDisputePlanButtonTitle,
                systemImage: "phone.fill",
                kind: .dispute,
                isEnabled: !viewModel.isPerformingAction,
                accessibilityHint: IntroCallCopy.callAccessibilityHint,
                action: dial
            )
            .accessibilityIdentifier("blindIntroCallDisputePlanButton")

            declineButton
        }
    }

    // MARK: - 底栏

    private var bottomActions: OrderFlowBottomActions {
        OrderFlowBottomActions(
            owner: .blindIntroCall,
            primary: primaryAction,
            secondary: isReviewingPlan ? nil : AnyView(secondaryButtons),
            safetyHub: OrderFlowSafetyHubAction(action: onOpenSafetyHub)
        )
    }

    private var primaryAction: OrderFlowPrimaryAction? {
        if isUnavailable {
            // 🚨 播报由 `refreshIntroCallIfNeeded` 在失败那一跳负责（只播一次），这里只管看得见的那半。
            return OrderFlowPrimaryAction(
                title: IntroCallCopy.retryButtonTitle,
                isEnabled: !viewModel.isPerformingAction,
                accessibilityHint: IntroCallCopy.retryAccessibilityHint
            ) {
                Task { await viewModel.reloadIntroCall() }
            }
        }
        // B2 / B3 / 还在拉：没有黄色主按钮。B2 此刻没有该你做的事；B3 的两枚大按钮在滚动区里。
        guard viewModel.introCall != nil, step == .awaitingCall else { return nil }
        return OrderFlowPrimaryAction(
            title: IntroCallCopy.callButtonTitle(counterpartName: counterpartName),
            systemImage: "phone.fill",
            isEnabled: !viewModel.isPerformingAction,
            accessibilityHint: IntroCallCopy.callAccessibilityHint,
            action: dial
        )
    }

    /// B2 的「再次致电」+ 每一屏都有的「更换陪跑员」。
    ///
    /// 🚩 B2 **必须保留「再次致电」**：拨号后对方可能没接（审查 #9），而 B2 只说明 App 回过前台。
    ///
    /// 「更换陪跑员」在每一支都在：数据拉多久用户都有权结束这一轮，不该被一个转圈按在原地等 20 分钟窗口超时。
    @ViewBuilder
    private var secondaryButtons: some View {
        VStack(spacing: FlowMetrics.actionButtonSpacing) {
            if step == .awaitingPlan, !isUnavailable, viewModel.introCall?.dialableCounterpartPhone != nil {
                FlowActionButton(
                    IntroCallCopy.callAgainButtonTitle,
                    systemImage: "phone.fill",
                    style: .ghost,
                    isEnabled: !viewModel.isPerformingAction,
                    accessibilityHint: IntroCallCopy.callAccessibilityHint,
                    action: dial
                )
                .accessibilityIdentifier("blindIntroCallDialAgainButton")
            }
            declineButton
        }
    }

    /// 不用红色：「更换陪跑员」是平权的退出，不是拒绝谁（`IntroCallCopy.declineButtonTitle` 的注释）；
    /// 红色在本 App 里专指求助与阻断，用在这里等于替用户说了一句「不行」。
    private var declineButton: some View {
        FlowActionButton(
            IntroCallCopy.declineButtonTitle,
            style: .ghost,
            isEnabled: !viewModel.isPerformingAction,
            accessibilityHint: IntroCallCopy.declineAccessibilityHint
        ) {
            Task { await viewModel.declineIntroCall() }
        }
        .accessibilityIdentifier("blindIntroCallDeclineButton")
    }

    // MARK: - 动作

    /// 拨号。**先通知对方再立刻拨**，不等响应（理由在 `introCallDialURL` 上）。
    ///
    /// 🚨 拿不到 URL 时**必须出声**。这条路的唯一成因是通话数据没拉回来，
    /// 而静默 return 的表现是「按了没反应」—— 对盲人端就是事故。
    private func dial() {
        guard let url = viewModel.introCallDialURL() else {
            speechService.speakError(IntroCallCopy.loadFailed)
            return
        }
        EmergencyDialer.dial(url)
    }

    /// 「重复当前状态」按这一屏念（修审查 #12：此前只念订单级文案，不知道自己在 B1 还是 B2）。
    /// B3 重念整张安排单。
    private func repeatCurrentState() {
        if isReviewingPlan, let view = viewModel.introCall, let plan = view.meetupPlan {
            let speech = IntroCallMeetupCopy.planSpeech(
                plan: plan,
                original: view.originalArrangement,
                volunteerName: view.counterpartDisplayName(fallback: "")
            )
            speechService.speak(speech.fullText)
            return
        }
        speechService.speak(heroAccessibilityLabel)
    }

    /// 焦点挪回标题。先放开再落下：已经是 true 时再赋 true 不会触发移动；
    /// 隔一拍是给 B2 → B3 换屏留出布局时间，标题元素还不在树里时设焦点会落空。
    private func refocusTitle() {
        titleFocused = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            titleFocused = true
        }
    }
}

// MARK: - B3 的两枚大按钮

/// 「确认见面安排」（黄）与「有异议，致电沟通」（白底蓝框），**同为 84pt**。
/// 外观逐项对齐 `FlowActionButton` 的 `.primary` / `.call`，只有高度不同（理由见 `planDecisionButtonMinHeight`）。
private struct PlanDecisionButton: View {
    enum Kind { case confirm, dispute }

    let title: String
    let systemImage: String?
    let kind: Kind
    let isEnabled: Bool
    let accessibilityHint: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .semibold))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .flowFont(FlowFonts.actionButton())
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            }
            .foregroundColor(kind == .confirm ? AppColors.Flow.onCTA : AppColors.Flow.bluePressed)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            // 挂在 label 里面：挂在 Button 外面撑不大可点区（记忆 `button-frame-outside-label-does-not-grow-hit-area`）。
            .frame(minHeight: BlindIntroCallView.planDecisionButtonMinHeight)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: FlowMetrics.buttonRadius, style: .continuous)
                    .strokeBorder(kind == .confirm ? Color.clear : AppColors.Flow.accent, lineWidth: kind == .confirm ? 0 : 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: FlowMetrics.buttonRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(title)
        .accessibilityHintIfPresent(accessibilityHint)
        // 挂在 `.accessibilityElement(children: .ignore)` 之后，读屏才念「变暗」（`FlowActionButton.body` 里那段）。
        .disabled(!isEnabled)
    }

    private var background: Color {
        switch kind {
        case .confirm: return isEnabled ? AppColors.Flow.cta : AppColors.Flow.ctaDisabled
        case .dispute: return AppColors.Flow.surface
        }
    }
}

/// B3 每一行的 identifier。字面量分支的理由同 `OrderFlowBottomActions.Owner`（`stale-ui-test-identifier` 只认字面量）。
private struct PlanRowIdentifier: ViewModifier {
    let kind: BlindMeetupPlanRow.Kind

    func body(content: Content) -> some View {
        switch kind {
        case .time: content.accessibilityIdentifier("blindIntroCallPlanRowTime")
        case .place: content.accessibilityIdentifier("blindIntroCallPlanRowPlace")
        case .meetSpot: content.accessibilityIdentifier("blindIntroCallPlanRowMeetSpot")
        case .colors: content.accessibilityIdentifier("blindIntroCallPlanRowColors")
        case .greeting: content.accessibilityIdentifier("blindIntroCallPlanRowGreeting")
        }
    }
}
