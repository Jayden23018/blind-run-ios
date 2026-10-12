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
/// 🔄 2026-10-13 按订单页同一套样式重做（定稿 v6，`docs/ui/mockups/intro-call-20261013/`，
/// 负责人：通话页与其余页面割裂）：彩色头卡（打电话前紫、打完回来 / 已说合适梅红）+ 进度绳
/// （第 1 格，对方是候选人）+ 订单页同一条底栏（主按钮、次要按钮、求助与安全）。
/// 「重复当前状态」从底部挪到导航栏右侧，与订单页同一个位置。**判定一行没改**，只换了外观。
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
/// 阶段的判定顺序**逐条搬自原 `introCallSection`**，不许重排（每条的理由见分支内注释）。
struct BlindIntroCallView: View {
    @EnvironmentObject private var speechService: SpeechService
    /// 两阶段切换的唯一信号源。iOS 不告诉 App「这通电话打完了」——
    /// 能观察到的只有「拨号确认框把我推到后台、然后我回来了」。
    @Environment(\.scenePhase) private var scenePhase

    /// 与订单状态页**同一个实例**。见类型注释。
    @ObservedObject var viewModel: BlindOrderStatusViewModel
    /// 「求助与安全」。宿主先收起这一页、收起动画结束后再打开求助中心 ——
    /// 全屏页盖着的时候，订单页那一层弹不出第二个页面。
    var onOpenSafetyHub: () -> Void = {}
    let onClose: () -> Void

    /// 用户按过拨号按钮。
    @State private var didDial = false
    /// 拨号之后 App 回到前台了 ⇒ 进入阶段 B（给出「聊过了，合适」）。
    ///
    /// ⚠️ 这是**推断，不是事实**：在系统拨号确认框上点「取消」走的是同一条路径。
    /// 所以阶段 B 一定要保留「再打一次」，见 `stageBActions`。
    @State private var returnedFromDialer = false
    /// 进页面时把 VoiceOver 焦点钉在头卡正文上。
    ///
    /// 这一页是**自动弹出来**的，焦点落点不确定的代价比在订单页上更大：用户可能正在听
    /// 别的东西，屏幕换了而焦点还在旧位置，他会以为按钮没出现。
    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            OrderFlowScaffold(bottom: bottomActions) {
                heroCard
            }
            .navigationTitle(IntroCallCopy.pageTitle)
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
                    Button {
                        viewModel.repeatStatus()
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(AppColors.Flow.accent)
                            // 工具栏按钮的系统触达区约 44pt，低于盲人端 64pt 下限 ——
                            // `contentShape` 撑大命中区而不改变视觉尺寸（同订单页那枚）。
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle().size(width: 64, height: 64))
                    }
                    .accessibilityLabel("重复当前状态")
                    .accessibilityHint("点击后重新播报当前订单状态")
                    .accessibilityIdentifier("blindIntroCallRepeatStatusButton")
                }
            }
        }
        .onAppear { titleFocused = true }
        .onChange(of: scenePhase) { phase in
            guard phase == .active, didDial else { return }
            returnedFromDialer = true
        }
    }

    // MARK: - 头卡

    /// 绳子上这一页处在哪一档。**只用自己知道的事**：拨没拨过（本地）、自己表没表态（服务端回的 `myDecision`）。
    private var ropeStage: IntroCallRopeStage {
        if viewModel.isWaitingForIntroCallCounterpart { return .decided }
        return returnedFromDialer ? .afterCall : .beforeCall
    }

    /// 打电话前紫，打完回来 / 已说合适梅红（定稿 v6：「聊前和聊后颜色不同」）。
    private var tone: BlindHeroTone {
        ropeStage == .beforeCall ? .calling : .called
    }

    private var heroCard: some View {
        let palette = BlindHeroPalette(tone: tone)
        return FlowHeroCard(style: palette.cardStyle) {
            if let eyebrow {
                // 不单独进读屏：它是正文合成标签的第一句。
                Text(eyebrow)
                    .flowFont(FlowV2Fonts.subhead(bold: true))
                    .foregroundColor(palette.eyebrow)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
            RopeView(
                state: .introCall(ropeStage),
                theme: palette.ropeTheme,
                volunteerInitial: counterpartInitial,
                perspective: .runner
            )
            .frame(maxWidth: RopeGeometry.width * 1.2)
            .frame(maxWidth: .infinity)
            heroBody(palette: palette)
        }
    }

    private func heroBody(palette: BlindHeroPalette) -> some View {
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
            if viewModel.introCall == nil, !viewModel.introCallUnavailable, !viewModel.isWaitingForIntroCallCounterpart {
                // 还在拉。**整屏不许空白** —— 标题位已经在说「正在获取」，转圈只给眼睛看。
                ProgressView()
                    .tint(.white)
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("blindIntroCallLoading")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // 🔴 正文合成**一个**元素：「谁 / 现在该干什么 / 还剩多久」一站听完，再滑一下就是主按钮。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(heroAccessibilityLabel)
        .accessibilityAddTraits(.isHeader)
        .accessibilityFocused($titleFocused)
        .accessibilityIdentifier("blindIntroCallTitle")
    }

    private var heroAccessibilityLabel: String {
        [eyebrow?.replacingOccurrences(of: " · ", with: "，"), headerTitle.unmaskedForSpeech,
         headerSubtitle, remaining]
            .compactMap { $0?.nilIfBlank }
            .joined(separator: "，")
    }

    /// 「明天早上 7:00 · 朝阳公园南门」。原先在一张单独的信息卡里，现在与订单页一样放在头卡小标题。
    private var eyebrow: String? {
        IntroCallCopy.eyebrow(
            plannedStart: viewModel.introCall?.plannedStartTime,
            address: viewModel.introCall?.startAddress
        )
    }

    /// 本轮还剩几分钟。每轮订单轮询都会重新赋值 `introCall`，所以这个数字跟着一起重算 ——
    /// 不需要（也不该）为它单起一条每秒跳一次的计时器：分钟级的精度对「要不要现在打」已经足够。
    private var remaining: String? {
        IntroCallCopy.blindWindowRemainingText(windowEndsAt: viewModel.introCall?.windowEndsAt)
    }

    private var counterpartName: String {
        viewModel.introCall?.counterpartDisplayName(fallback: "这位志愿者") ?? "这位志愿者"
    }

    /// 绳子右边那个头像里的字：候选人的姓。拿不到写「陪」（同订单页）。
    private var counterpartInitial: String {
        viewModel.introCall?.counterpartName?.nilIfBlank?.unmaskedForSpeech.first.map(String.init) ?? "陪"
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

    // MARK: - 底栏

    /// 主按钮 + 次要按钮 + 求助与安全。四个分支，**顺序逐条搬自原 `introCallSection`**，判定条件一字未改。
    private var bottomActions: OrderFlowBottomActions {
        OrderFlowBottomActions(
            owner: .blindRunner,
            primary: primaryAction,
            secondary: AnyView(secondaryButtons),
            safetyHub: OrderFlowSafetyHubAction(action: onOpenSafetyHub)
        )
    }

    private var primaryAction: OrderFlowPrimaryAction? {
        if viewModel.isWaitingForIntroCallCounterpart {
            // 🚩 **表过态之后这一支优先，且不依赖再拉一次 view。**
            // 已表态、在等对方。**这一屏刻意没有主动作** —— 此刻用户没有该做的事，
            // 摆一个大按钮只会让他以为还要再做点什么。
            return nil
        }
        if viewModel.introCall == nil, viewModel.introCallUnavailable {
            // 🚨 播报由 `refreshIntroCallIfNeeded` 在失败那一跳负责（只播一次），这里只管看得见的那半。
            return OrderFlowPrimaryAction(
                title: IntroCallCopy.retryButtonTitle,
                isEnabled: !viewModel.isPerformingAction,
                accessibilityHint: IntroCallCopy.retryAccessibilityHint
            ) {
                Task { await viewModel.reloadIntroCall() }
            }
        }
        guard viewModel.introCall != nil else { return nil }
        if returnedFromDialer {
            return OrderFlowPrimaryAction(
                title: IntroCallCopy.acceptButtonTitle,
                systemImage: "hand.thumbsup.fill",
                isEnabled: !viewModel.isPerformingAction,
                accessibilityHint: IntroCallCopy.acceptAccessibilityHint
            ) {
                Task { await viewModel.submitIntroCallDecision(.accept) }
            }
        }
        return OrderFlowPrimaryAction(
            title: IntroCallCopy.callButtonTitle,
            systemImage: "phone.fill",
            isEnabled: !viewModel.isPerformingAction,
            accessibilityHint: IntroCallCopy.callAccessibilityHint,
            action: dial
        )
    }

    /// 次要按钮。
    ///
    /// 🚩 阶段 B **必须保留「再打一次」**：阶段切换的判定（点过拨号按钮 + `scenePhase` 回到
    /// `.active`）是**推断不是事实**，用户在系统拨号确认框上点「取消」会走同一条路径。
    /// 保留拨号入口 = 推断错了也有退路。**这处冗余是刻意的。**
    ///
    /// 「换一位」在每一支都在：数据拉多久用户都有权结束这一轮，不该被一个转圈按在原地等 20 分钟窗口超时。
    @ViewBuilder
    private var secondaryButtons: some View {
        VStack(spacing: FlowMetrics.actionButtonSpacing) {
            if showsDialAgain {
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
            // 不用红色：「换一位」是平权的退出，不是拒绝谁（`IntroCallCopy.declineButtonTitle` 的注释）；
            // 红色在本 App 里专指求助与阻断，用在这里等于替用户说了一句「不行」。
            FlowActionButton(
                IntroCallCopy.declineButtonTitle,
                style: .ghost,
                isEnabled: !viewModel.isPerformingAction,
                accessibilityHint: IntroCallCopy.declineAccessibilityHint
            ) {
                Task { await viewModel.submitIntroCallDecision(.decline) }
            }
            .accessibilityIdentifier("blindIntroCallDeclineButton")
        }
    }

    /// 阶段 B 必给；已表态时**拿得到号码**才给（等待期间对方可能想再聊两句）。
    private var showsDialAgain: Bool {
        if viewModel.isWaitingForIntroCallCounterpart {
            return viewModel.introCall?.dialableCounterpartPhone != nil
        }
        return viewModel.introCall != nil && returnedFromDialer
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
}
