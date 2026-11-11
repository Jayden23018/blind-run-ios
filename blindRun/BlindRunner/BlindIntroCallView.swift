import SwiftUI

// MARK: - 盲人订单页 ②③「商量见面安排」（订单页 v7，#917）

/// 盲人侧通话磨合，**订单页同页显示**，竖线上是同一步「商量见面安排」：
///
/// - **② 通电话**（B1 待通话 / B2 等见面安排）：头部「先通个电话」+ 标题，卡片里是原副标题与候选人，
///   底部「致电陪跑员李*」（B2 换成「再次致电」）。
/// - **③ 确认见面安排**（B3）：头部「陪跑员李*已提交」+「见面安排（N 项变更）」，卡片里逐项列安排单，
///   底部「有异议，致电沟通」（描边）+「确认见面安排」（实心），两枚同高（视觉稿决定 3：避免让人觉得被迫同意）。
/// - 「更换陪跑员」收进顶栏「···」（负责人 11-09 第 9 条），按下仍先确认（#660 B-14）。
///
/// 🔄 2026-11-11（v7）起**不再是盖在订单页上的全屏页**：稿里 ②③ 与 ①④ 同一顶栏、同一条竖线，
/// 是订单页的一个状态。原来那套「关过一次本轮不再自动弹」的呈现规则随全屏页一起删掉。
///
/// 哪一屏由 `BlindOrderStatusViewModel.introCallRunnerStep` 决定，**服务端安排单优先**于
/// 本地「回过前台」标记 —— 关页重进、杀进程重启都回得到 B3（修审查 #4）。
///
/// 🚩 **它共用 `BlindOrderStatusViewModel`，不另起一个 view model、也不另起一条轮询。**
/// 通话期 `order.volunteer` 恒为 null；盲人读得到订单详情，`loadOrder` 每 5 秒一轮会顺带把通话数据刷回来
/// （`refreshIntroCallIfNeeded`）。订单一离开 `PENDING_INTRO_CALL`，订单页自己换屏。
struct BlindIntroCallView<Footer: View>: View {
    @EnvironmentObject private var speechService: SpeechService

    /// 与订单状态页**同一个实例**。见类型注释。
    @ObservedObject var viewModel: BlindOrderStatusViewModel
    let order: OrderDetailResponse
    /// 顶栏由订单页给（返回、求助、举报 / 不再匹配都是订单页的动作）；这里只补「···」里的「更换陪跑员」和喇叭念什么。
    let makeTopBar: (_ menu: [BlindOrderMenuItem], _ onRepeatStatus: @escaping () -> Void) -> BlindOrderTopBar
    /// 订单页的头部焦点。安排单刚到、陪跑员改了一版时钉回标题。
    var headerFocused: AccessibilityFocusState<Bool>.Binding
    @ViewBuilder let footer: () -> Footer

    @State private var confirmsDecline = false

    var body: some View {
        BlindOrderStageScaffold(
            topBar: makeTopBar([declineMenuItem], repeatCurrentState),
            eyebrow: eyebrow,
            title: headerTitle,
            headerAccessibilityLabel: headerAccessibilityLabel,
            headerFocused: headerFocused,
            headerIdentifier: isReviewingPlan ? .introCallPlanTitle : .introCallTitle,
            // ③ 安排单五项要首屏完整可见（v7 第 11 条 D），地点已在安排单里，不再单列。
            place: isReviewingPlan ? nil : order.startAddress?.nilIfBlank ?? viewModel.introCall?.startAddress?.nilIfBlank,
            when: isReviewingPlan ? nil : order.blindRunnerShortStartText(),
            timeline: timeline,
            card: { card },
            // 举报 / 不再匹配此人 2026-11-11 起收进顶栏「···」：订单页在 `makeTopBar` 里接在「更换陪跑员」后面，
            // 结果一行在 `footer()`（`BlindOrderStatusView.stageFooter`）。
            footer: { footer() },
            bottom: { bottomButtons }
        )
        .blindIntroCallDeclineConfirmation(isPresented: $confirmsDecline, viewModel: viewModel)
        .onChange(of: viewModel.introCallPlanFocusRequest) { _ in
            refocusTitle()
        }
    }

    // MARK: - 子状态

    private var step: IntroCallRunnerStep { viewModel.introCallRunnerStep }

    /// B3（含刚确认成功、订单还没转走的那几秒）。
    private var isReviewingPlan: Bool {
        (step == .reviewingPlan || step == .confirmed) && planLayout != nil
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

    // MARK: - 头部

    private var eyebrow: String {
        isReviewingPlan
            ? IntroCallCopy.blindPlanSubmittedBy(counterpartName: counterpartName)
            : BlindOrderStageCopy.introCallEyebrow
    }

    private var headerTitle: String {
        if isReviewingPlan, let layout = planLayout {
            return viewModel.introCallPlanChangedNotice
                ? IntroCallCopy.blindPlanChangedHeadline
                : IntroCallCopy.blindPlanHeadline(changeCount: layout.changeCount)
        }
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

    /// B3 只念标题这一句（`planSpeech.title`，去星号）；B1 / B2 念「谁 / 现在该干什么 / 还剩多久」
    /// （视觉稿 B1 原话：「陪跑员李*已响应。请先与陪跑员通话。通话后，对方将提交见面安排供你确认。剩余 19 分钟。」）。
    private var headerAccessibilityLabel: String {
        if isReviewingPlan, let layout = planLayout { return layout.titleSpeech }
        let title = headerTitle.unmaskedForSpeech
        return [title.hasSuffix("。") ? title : title + "。", headerSubtitle, remaining.map { $0 + "。" }]
            .compactMap { $0?.nilIfBlank }
            .joined()
    }

    /// 「剩余 19 分钟」/「剩余不到 1 分钟」。每轮订单轮询都会重新赋值 `introCall`，所以这个数字跟着重算。
    private var remaining: String? {
        guard let endsAt = viewModel.introCall?.windowEndsAt?.nilIfBlank?.backendTimestamp else { return nil }
        // 已过期而服务端还没转走的那几秒也落「不到 1 分钟」，不说「已超时」（超时由服务端宣布）。
        return IntroCallMeetupCopy.remainingText(windowEndsAt: endsAt, now: Date())
    }

    /// 屏幕上的称呼保留掩码（`李*`），读屏一路各自去星号。
    private var counterpartName: String {
        viewModel.introCall?.counterpartName?.nilIfBlank ?? ""
    }

    // MARK: - 竖线

    private var timeline: BlindOrderTimelineInput {
        BlindOrderTimelineInput(
            position: .current(.arrangeMeetup),
            details: [
                .arrangeMeetup: isReviewingPlan
                    ? BlindOrderStageCopy.planDetail(remaining: remaining)
                    : BlindOrderStageCopy.introCallDetail(remaining: remaining)
            ],
            showsNextStep: !isReviewingPlan
        )
    }

    // MARK: - 卡片

    @ViewBuilder
    private var card: some View {
        if isReviewingPlan, let layout = planLayout {
            planCard(layout)
        } else {
            BlindOrderStepCard(lead: nil, body: headerSubtitle) {
                if isLoading {
                    // 还在拉。**整屏不许空白** —— 卡片已经在说「正在获取」，转圈只给眼睛看。
                    ProgressView()
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                        .accessibilityIdentifier("blindIntroCallLoading")
                } else if let name = counterpartName.nilIfBlank {
                    BlindOrderPersonRow(
                        initial: name.unmaskedForSpeech.first.map(String.init) ?? "陪",
                        label: BlindOrderStageCopy.introCallCandidateLabel,
                        line: name,
                        spoken: "\(BlindOrderStageCopy.introCallCandidateLabel)，\(name.unmaskedForSpeech)"
                    )
                }
            }
        }
    }

    private var planLayout: (titleSpeech: String, changeCount: Int, rows: [BlindMeetupPlanRow])? {
        guard let view = viewModel.introCall, let plan = view.meetupPlan else { return nil }
        return BlindMeetupPlanLayout.rows(
            plan: plan,
            original: view.originalArrangement,
            volunteerName: view.counterpartDisplayName(fallback: "")
        )
    }

    private func planCard(_ layout: (titleSpeech: String, changeCount: Int, rows: [BlindMeetupPlanRow])) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(layout.rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { FlowSeparator() }
                BlindMeetupPlanRowView(row: row)
            }
        }
        .background(AppColors.Flow.surfaceSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - 底部

    @ViewBuilder
    private var bottomButtons: some View {
        if isUnavailable {
            // 🚨 播报由 `refreshIntroCallIfNeeded` 在失败那一跳负责（只播一次），这里只管看得见的那半。
            BlindOrderStageButton(
                title: IntroCallCopy.retryButtonTitle,
                style: .solid,
                isEnabled: !viewModel.isPerformingAction,
                accessibilityHint: IntroCallCopy.retryAccessibilityHint
            ) {
                Task { await viewModel.reloadIntroCall() }
            }
            .accessibilityIdentifier("blindIntroCallPrimaryButton")
        } else if isReviewingPlan {
            planDecisionButtons
        } else if viewModel.introCall != nil, step == .awaitingCall {
            BlindOrderStageButton(
                title: IntroCallCopy.callButtonTitle(counterpartName: counterpartName),
                systemImage: "phone.fill",
                style: .solid,
                isEnabled: !viewModel.isPerformingAction,
                accessibilityHint: IntroCallCopy.callAccessibilityHint,
                action: dial
            )
            .accessibilityIdentifier("blindIntroCallPrimaryButton")
        } else if step == .awaitingPlan, viewModel.introCall?.dialableCounterpartPhone != nil {
            // 🚩 B2 **必须保留「再次致电」**：拨号后对方可能没接（审查 #9），而 B2 只说明 App 回过前台。
            BlindOrderStageButton(
                title: IntroCallCopy.callAgainButtonTitle,
                systemImage: "phone.fill",
                style: .solid,
                isEnabled: !viewModel.isPerformingAction,
                accessibilityHint: IntroCallCopy.callAccessibilityHint,
                action: dial
            )
            .accessibilityIdentifier("blindIntroCallDialAgainButton")
        }
    }

    /// 确认失败横条 +「有异议，致电沟通」+「确认见面安排」。两枚同高（视觉稿决定 3）。
    private var planDecisionButtons: some View {
        VStack(spacing: 0) {
            if viewModel.introCallConfirmFailed {
                // 修审查 #3：此前确认失败只有语音。屏幕上这一条与播报**同时**出现；
                // 读屏也滑得到它（紧挨在两枚按钮前面），漏听了那句播报还能在这里再听一次。
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
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("blindIntroCallConfirmFailedBanner")
            }

            // 「有异议」直接拨号，安排单保留；陪跑员那边只会再收到一次「跑者正在给你打电话」。
            BlindOrderStageButton(
                title: IntroCallCopy.blindDisputePlanButtonTitle,
                systemImage: "phone.fill",
                style: .outline,
                isEnabled: !viewModel.isPerformingAction,
                accessibilityHint: IntroCallCopy.callAccessibilityHint,
                action: dial
            )
            .accessibilityIdentifier("blindIntroCallDisputePlanButton")

            BlindOrderStageButton(
                title: IntroCallCopy.blindConfirmPlanButtonTitle,
                systemImage: "checkmark",
                style: .solid,
                isEnabled: !viewModel.isPerformingAction && step == .reviewingPlan,
                accessibilityHint: IntroCallCopy.blindConfirmPlanAccessibilityHint
            ) {
                Task { await viewModel.confirmIntroCallPlan() }
            }
            .accessibilityIdentifier("blindIntroCallConfirmPlanButton")
        }
    }

    // MARK: - 动作

    private var declineMenuItem: BlindOrderMenuItem {
        BlindOrderMenuItem(kind: .changeVolunteer, title: IntroCallCopy.declineButtonTitle) {
            confirmsDecline = true
        }
    }

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

    /// 「重复当前状态」按这一屏念（修审查 #12）。B3 重念整张安排单。
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
        speechService.speak(headerAccessibilityLabel)
    }

    /// 焦点挪回标题。先放开再落下：已经是 true 时再赋 true 不会触发移动；
    /// 隔一拍是给 B2 → B3 换屏留出布局时间，标题元素还不在树里时设焦点会落空。
    private func refocusTitle() {
        headerFocused.wrappedValue = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            headerFocused.wrappedValue = true
        }
    }
}

// MARK: - B3 安排单的一行

/// B3 每项一个读屏元素，标签取 `planSpeech` 那一句：改过的项念「已变更：由 X 改为 Y」，地点再报距离。
struct BlindMeetupPlanRowView: View {
    let row: BlindMeetupPlanRow

    var body: some View {
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
            // 撑满行宽、左对齐：frame 贴着字宽时，行尾的全角括号会画出 frame 外，
            // 审计判「放大字号后可能被截断」（2026-10-16 真机：「你：蓝色（通话中确认）」）。
            ForEach(row.values, id: \.self) { value in
                Text(value)
                    .flowFont(FlowFonts.rowValueEmphasized())
                    .foregroundColor(AppColors.Flow.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let original = row.original {
                Text(original)
                    .flowFont(FlowFonts.rowDetail())
                    .foregroundColor(AppColors.Flow.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        // 与 `FlowInfoRow` 同一个下限，并让整行（含 padding）成为这个读屏元素的范围。
        .frame(minHeight: FlowMetrics.infoRowDisplayMinHeight) // guard:allow small-touch-target
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.speech)
        .modifier(PlanRowIdentifier(kind: row.kind))
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
        case .pace: content.accessibilityIdentifier("blindIntroCallPlanRowPace")
        case .guideDog: content.accessibilityIdentifier("blindIntroCallPlanRowGuideDog")
        case .notes: content.accessibilityIdentifier("blindIntroCallPlanRowNotes")
        case .greeting: content.accessibilityIdentifier("blindIntroCallPlanRowGreeting")
        }
    }
}

extension IntroCallRunnerStep {
    /// 通话子状态在进度绳第一格挂什么：B1 电话 → B2 灰色单子（单子还没来）。
    /// 订单页 v7（#917）起盲人订单页不再画进度绳，这个映射只剩进度绳组件自己的用例在守（`RopeAndDirectionTests`）。
    var blindRopeStage: IntroCallRopeStage {
        switch self {
        case .awaitingCall: return .beforeCall
        case .awaitingPlan: return .awaitingPlan
        case .reviewingPlan: return .afterCall
        case .confirmed: return .decided
        }
    }
}
