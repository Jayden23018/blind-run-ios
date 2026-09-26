import SwiftUI

// MARK: - 陪跑员订单页 v2

/// 陪跑员订单页（邀请 / 约好 / 出发 / 汇合 / 完成 / 跑者取消），交付包 `zhumangpao-handoff/02`。
///
/// 结构：导航栏（左返回、右**求助**）+ 可滚动内容（头卡 + 按状态的卡片）+ 底部固定的动作区。
/// 状态变化时原地切换，不 push 新页面（v3 原则不变）。
///
/// **这个视图不判任何状态。** 两个纯类型给它全部内容：
/// - `VolunteerOrderFlowPresentation`：信息行、主按钮、求助路由（隐私闸与按状态发动作都在那边，用例穷举）；
/// - `VolunteerOrderHero`：头卡（小标题、主角数字 / 主角句、副文、在场胶囊、提醒条、引导绳）。
///
/// 两个数据源各有一个入口：邀请吃派单推送 `WSNewOrder`（接单前拿不到订单详情，后端恒 403），
/// 其余吃 `OrderDetailResponse`。
struct VolunteerOrderFlowPage<Footer: View>: View {
    let presentation: VolunteerOrderFlowPresentation
    let hero: VolunteerOrderHero
    /// `nil` = 邀请态（没有订单详情）。
    var order: OrderDetailResponse?
    var phase: VolunteerOrderPhase?
    /// 邀请态头卡里的三宫格。
    var inviteMetrics: [VolunteerOrderMetric] = []
    /// 汇合页的方位盘、响铃、等待。`nil` = 不是汇合页。
    var meet: VolunteerOrderMeetPanel?
    /// 出发 / 汇合页的快捷回复。`nil` = 不显示。
    var quickReplies: VolunteerOrderQuickReplies?
    /// `nil` = 不放返回按钮（完成页）。
    var onBack: (() -> Void)?
    let onRowAction: (VolunteerOrderFlowPresentation.Action) -> Void
    let onPrimaryAction: () -> Void
    /// `helpMode == .cloud` 时（只可能是 `IN_PROGRESS`）交给宿主走现有云端链路。
    var onCloudHelp: () -> Void = {}
    var isPrimaryLoading: Bool = false
    /// 主按钮可不可按。
    ///
    /// 🔴 **必须接上，不能用默认值糊过去。** POST 回来了但确认那条 GET 还挂着的那几秒里，
    /// 同一次流转不许被提交第二次（`testVolunteerServiceRemainsInteractiveWhenTransitionConfirmationNeverReturns`）。
    /// 走 `.disabled()`：VoiceOver 会念「变暗」，静默 return 在读屏里是一个正常按钮、双击没反应。
    var isPrimaryEnabled: Bool = true
    /// 信息卡之后那块「刚才那一下的结果」。**这一页唯一的可见失败面**，少了它失败只剩一句 TTS。
    @ViewBuilder let footer: () -> Footer

    @State private var showsLocalHelp = false
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            FlowOrderNavBar(title: navTitle, onBack: onBack, onHelp: openHelp)
                .padding(.horizontal, FlowMetrics.v2ScreenPadding - 8)
            ScrollView {
                VStack(spacing: FlowMetrics.v2SectionGap) {
                    heroCard
                    if let notice = hero.notice {
                        FlowNoticeBar(text: notice)
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                    }
                    if let meet { meetSection(meet) }
                    runnerCard
                    if let place = placeRow { placeRowView(place) }
                    if let quickReplies {
                        FlowQuickReplyGrid(
                            title: "一键告诉\(quickReplies.runnerName)",
                            items: quickReplies.items,
                            onTap: { quickReplies.onTap($0.id) }
                        )
                    }
                    if !infoRows.isEmpty { infoCard }
                    completionLinks
                    footer()
                }
                .padding(.horizontal, FlowMetrics.v2ScreenPadding)
                .padding(.vertical, FlowMetrics.v2SectionGap)
                .animation(.easeInOut(duration: 0.25), value: hero.notice)
                // 状态原地切换（03 §二）：卡片的出现 / 消失跟着 spring 走；减弱动态效果下 0.2 秒淡入淡出。
                .animation(phaseAnimation, value: phase)
            }
        }
        .background(AppColors.Flow.page.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomActions }
        .emergencyCallOptionsDialog(isPresented: $showsLocalHelp, context: .volunteerBeforeRun, primaryContact: nil)
    }

    private var navTitle: String {
        switch phase {
        case .none: return "陪跑邀请"
        case .completed: return "陪跑完成"
        default: return VolunteerOrderFlowCopy.pageTitle
        }
    }

    private func openHelp() {
        switch presentation.helpMode {
        case .cloud: onCloudHelp()
        case .localCall: showsLocalHelp = true
        }
    }

    /// 03 §二默认 spring；§四减弱动态效果下 0.2 秒淡入淡出。
    private var phaseAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.85)
    }

    // MARK: 头卡

    private var heroCard: some View {
        FlowHeroCard(style: hero.style.cardStyle) {
            if phase == .completed {
                // `Done.dc.html`：整卡居中、没有小标题（导航栏已经写着「陪跑完成」），
                // 绳子换成单独的一张并肩大插图。
                VStack(spacing: 12) {
                    RopeTogetherIllustration(runnerName: order?.blindName)
                    heroBody
                }
                .frame(maxWidth: .infinity)
            } else {
                standardHeroContent
            }
        }
    }

    @ViewBuilder
    private var standardHeroContent: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(hero.eyebrow)
                .flowFont(FlowV2Fonts.subhead(bold: true))
                .foregroundColor(hero.style == .light ? AppColors.Flow.accent : AppColors.Flow.onHeroEyebrow)
            Spacer(minLength: 8)
            replyNotice
        }
        RopeView(
            state: hero.rope,
            theme: hero.style.ropeTheme,
            runnerName: order?.blindName,
            remainingMinutes: hero.remainingMinutes
        )
        heroBody
    }

    /// 头卡正文合成**一个**读屏元素（绳子与回复倒计时各是一个）。
    private var heroBody: some View {
        let centered = phase == .completed
        return VStack(alignment: centered ? .center : .leading, spacing: 8) {
            if let number = hero.number {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(number).flowHeroNumber(hero.numberSize)
                    if let unit = hero.unit {
                        Text(unit).flowFont(FlowV2Fonts.heroUnit())
                    }
                }
                .foregroundColor(heroForeground)
                .contentTransition(.numericText(countsDown: true))
                .animation(.easeOut(duration: 0.6), value: number)
                // 出发 → 快迟到：数字颜色 0.25 秒过渡到金色（03 §二）。
                .animation(.easeInOut(duration: 0.25), value: hero.isGold)
            }
            if let headline = hero.headline {
                Text(headline)
                    .flowFont(phase == .completed ? FlowV2Fonts.title2() : FlowV2Fonts.title())
                    .foregroundColor(heroForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(hero.lines, id: \.self) { line in
                Text(line)
                    .flowFont(FlowV2Fonts.callout())
                    .foregroundColor(hero.style == .light ? AppColors.Flow.secondaryText : AppColors.Flow.onHeroBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !inviteMetrics.isEmpty { metricsTriple }
            if let presence = hero.presence {
                FlowPresencePill(text: presence)
                    .transition(.opacity)
            }
        }
        .multilineTextAlignment(centered ? .center : .leading)
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hero.accessibilityLabel + metricsSpoken)
        .accessibilityIdentifier("volunteerOrderFlowStatusCard")
    }

    private var heroForeground: Color {
        if hero.isGold { return AppColors.Flow.gold }
        return hero.style == .light ? AppColors.Flow.primaryText : AppColors.Flow.onHeroStrong
    }

    /// 「还剩 25 秒回复」。只有邀请态有；每秒都变，所以是独立读屏元素。
    /// 进入最后 10 秒只靠颜色转折时，「不使用颜色区分」下补一个感叹号。
    @ViewBuilder
    private var replyNotice: some View {
        if let notice = presentation.replyNotice {
            HStack(spacing: 4) {
                if differentiateWithoutColor && presentation.isReplyUrgent {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .accessibilityHidden(true)
                }
                Text(notice).flowFont(FlowV2Fonts.subhead(), monospacedDigit: true)
            }
            .foregroundColor(presentation.isReplyUrgent ? AppColors.Flow.replyUrgentText : AppColors.Flow.secondaryText)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("volunteerOrderFlowReplyCountdown")
        }
    }

    private var metricsTriple: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 0))
        return layout {
            ForEach(inviteMetrics) { metric in
                VStack(spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(metric.value).flowFont(FlowV2Fonts.metricValue(), monospacedDigit: true)
                        if let unit = metric.unit { Text(unit).flowFont(FlowV2Fonts.tag()) }
                    }
                    .foregroundColor(AppColors.Flow.primaryText)
                    Text(metric.label)
                        .flowFont(FlowV2Fonts.tag())
                        .foregroundColor(AppColors.Flow.secondaryText)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 12)
        .background(AppColors.Flow.surfaceSubtle, in: RoundedRectangle(cornerRadius: FlowMetrics.v2ChipRadius, style: .continuous))
    }

    private var metricsSpoken: String {
        inviteMetrics.isEmpty ? "" : "，" + inviteMetrics.map(\.spoken).joined(separator: "，")
    }

    // MARK: 汇合

    @ViewBuilder
    private func meetSection(_ meet: VolunteerOrderMeetPanel) -> some View {
        VStack(spacing: FlowMetrics.v2SectionGap) {
            if meet.canEndWait {
                WaitRing(waitedSeconds: WaitRing.defaultFullSeconds)
            } else {
                DirectionDial(relativeDegrees: meet.relativeDegrees, sectorWidth: meet.sectorWidth)
                    // 出发 → 汇合：方位盘从 0.9 倍缩放并淡入（03 §二）。
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
                if let remaining = meet.endWaitRemainingSeconds, remaining > 0 {
                    Text("再等 \(Int((Double(remaining) / 60).rounded(.up))) 分钟可以结束等待")
                        .flowFont(FlowV2Fonts.subhead())
                        .foregroundColor(AppColors.Flow.secondaryText)
                }
            }
            ringButton(meet)
            if let ringNotice = meet.ringNotice {
                Text(ringNotice)
                    .flowFont(FlowV2Fonts.subhead(bold: true))
                    .foregroundColor(AppColors.Flow.warmCardTitle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            meetButtons(callFirst: meet.canEndWait)
        }
        .frame(maxWidth: .infinity)
    }

    private func ringButton(_ meet: VolunteerOrderMeetPanel) -> some View {
        Button(action: meet.onRing) {
            HStack(spacing: 8) {
                ringIcon(isRinging: meet.isRinging)
                Text(meet.isRinging ? "正在响铃…" : "让\(meet.runnerName)的手机响起来")
                    .flowFont((16, .bold, .callout))
                    .fixedSize(horizontal: false, vertical: true)
            }
            // v2 C08：藏青现在代表「约好」，响铃改汇合的暖色（暖底 + 描边 + 深琥珀字）。
            .foregroundColor(AppColors.Flow.arrivedInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .frame(minHeight: FlowMetrics.actionButtonMinHeight)
            .background(AppColors.Flow.arrivedTint)
            .overlay(
                RoundedRectangle(cornerRadius: FlowMetrics.buttonRadius, style: .continuous)
                    .strokeBorder(AppColors.Flow.arrivedTintBorder, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: FlowMetrics.buttonRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(meet.isRinging ? "正在响铃" : "让\(meet.runnerNameSpoken)的手机响起来")
        .accessibilityHint("\(meet.runnerNameSpoken)的手机会响铃，并播报你的陪跑员到了")
        .disabled(meet.isRinging)
        .accessibilityIdentifier("volunteerOrderRingButton")
    }

    /// 交付包 03 §三：响铃中图标做 `variableColor`（iOS 17+）；减弱动态效果下静止。
    @ViewBuilder
    private func ringIcon(isRinging: Bool) -> some View {
        let image = Image(systemName: "speaker.wave.2").font(.system(size: 17, weight: .bold))
        if #available(iOS 17.0, *) {
            image.symbolEffect(.variableColor.iterative, isActive: isRinging && !reduceMotion)
                .accessibilityHidden(true)
        } else {
            image.accessibilityHidden(true)
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 「打电话 / 找不到对方」两列（AX 字号下竖排）。等满时限后打电话排第一个并加重（交付包 ④b）。
    @ViewBuilder
    private func meetButtons(callFirst: Bool) -> some View {
        let buttons = [callRow, cannotFindRow].compactMap { $0 }
        if !buttons.isEmpty {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 10))
                : AnyLayout(HStackLayout(spacing: 10))
            layout {
                ForEach(buttons) { row in
                    let emphasized = callFirst && row.action == .callRunner
                    Button { onRowAction(row.action ?? .callRunner) } label: {
                        Label(
                            row.action == .callRunner ? "打电话" : row.value,
                            systemImage: row.action == .callRunner ? "phone" : "magnifyingglass"
                        )
                        .flowFont((15, .bold, .callout))
                        .foregroundColor(emphasized ? .white : AppColors.Flow.primaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .frame(minHeight: FlowMetrics.v2TertiaryMinHeight)
                        // v2 C09：等满时限后的「打电话」用汇合琥珀底白字。
                        .background(emphasized ? AppColors.Flow.stateArrived : AppColors.Flow.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: FlowMetrics.buttonRadius, style: .continuous)
                                .strokeBorder(emphasized ? Color.clear : AppColors.Flow.ghostStroke, lineWidth: 1.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: FlowMetrics.buttonRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(row.accessibilityLabel)
                    .accessibilityHintIfPresent(row.accessibilityHint)
                    .accessibilityIdentifier("volunteerOrderFlowRow-\(row.id)")
                }
            }
            // 等满时限后打电话排第一个：它在行里本来就排第一（`metUp` 先放拨号行），这里只负责加重。
        }
    }

    // MARK: 跑者卡

    @ViewBuilder
    private var runnerCard: some View {
        if let order, let runnerRow, showsRunnerCard {
            FlowRunnerCard(
                name: runnerRow.value,
                detail: (runnerRow.detail ?? "").replacingOccurrences(of: "，", with: " · "),
                togetherCount: order.completedTogetherCount,
                // 交付包 02 ②b：出发前 30 分钟那一屏不再显示留言气泡，保持卡片短。
                message: phase == .agreedSoon ? nil : order.messageToVolunteer,
                preferenceText: order.guidePreferenceText
            )
        }
    }

    private var showsRunnerCard: Bool {
        switch phase {
        case .confirmStillGoing, .agreedEarly, .agreedSoon, .departed: return true
        case .arrived, .completed, .runnerCancelled, .none: return false
        }
    }

    // MARK: 行的分派
    //
    // 行本身（有哪些、读屏说什么、接单前露不露）全在 `VolunteerOrderFlowPresentation` 里定；
    // 这里只决定**画成什么形状**：集合点画成地点行、「去不了」画成底部文字按钮、
    // 汇合页的拨号与找人画成两列按钮、完成页两个去处画成文字链接，其余进信息卡。

    private var rows: [VolunteerOrderFlowPresentation.Row] { presentation.rows }
    private var runnerRow: VolunteerOrderFlowPresentation.Row? { rows.first { $0.id == "runner" } }
    private var placeRow: VolunteerOrderFlowPresentation.Row? { rows.first { $0.action == .openMeetingPoint } }
    private var dismissRow: VolunteerOrderFlowPresentation.Row? {
        rows.first { $0.action == .releaseOrder || $0.action == .declineInvite }
    }
    private var cannotFindRow: VolunteerOrderFlowPresentation.Row? { rows.first { $0.action == .cannotFindRunner } }
    /// 只有汇合页把拨号画成按钮；其余页电话仍是信息卡里一行（`AGENTS.md` §8：掩码号 + 拨号入口）。
    private var callRow: VolunteerOrderFlowPresentation.Row? {
        cannotFindRow == nil ? nil : rows.first { $0.action == .callRunner }
    }
    private var linkRows: [VolunteerOrderFlowPresentation.Row] {
        rows.filter { $0.action == .viewRunRecord || $0.action == .reportIssue }
    }
    private var infoRows: [VolunteerOrderFlowPresentation.Row] {
        let taken = Set([placeRow, dismissRow, cannotFindRow, callRow].compactMap { $0?.id } + linkRows.map(\.id))
        return rows.filter { row in
            if taken.contains(row.id) { return false }
            if row.id == "runner" && showsRunnerCard { return false }
            // 邀请态三宫格已经说了跑多远 / 配速，信息卡里不再重复。
            if !inviteMetrics.isEmpty && (row.id == "plannedDistance" || row.id == "pace") { return false }
            return true
        }
    }

    private func placeRowView(_ row: VolunteerOrderFlowPresentation.Row) -> some View {
        let isNavigate = row.id == "navigate"
        return FlowPlaceRow(
            systemImage: isNavigate ? "location.north.fill" : "mappin",
            title: row.value,
            subtitle: isNavigate ? row.detail : nil,
            trailing: isNavigate ? .arrow : .mapLink,
            accessibilityPrefix: isNavigate ? "" : VolunteerOrderFlowCopy.meetingPointLabel,
            action: { onRowAction(.openMeetingPoint) }
        )
        .accessibilityIdentifier("volunteerOrderFlowRow-\(row.id)")
    }

    private var infoCard: some View {
        FlowCard {
            VStack(spacing: 0) {
                ForEach(Array(infoRows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { FlowSeparator() }
                    infoRow(row)
                }
            }
        }
    }

    @ViewBuilder
    private func infoRow(_ row: VolunteerOrderFlowPresentation.Row) -> some View {
        FlowInfoRow(
            label: row.label,
            kind: row.action.map { action in .navigable(action: { onRowAction(action) }) } ?? .display,
            accessibilityLabel: row.accessibilityLabel,
            accessibilityHint: row.accessibilityHint,
            minHeight: row.detail == nil ? nil : FlowMetrics.volunteerRowMinHeight
        ) {
            VStack(alignment: row.label == nil ? .leading : .trailing, spacing: 3) {
                Text(row.value)
                    .flowFont(row.label == nil ? FlowFonts.rowValue() : FlowFonts.rowValueEmphasized())
                    .foregroundColor(AppColors.Flow.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(row.label == nil ? .leading : .trailing)
                if let detail = row.detail {
                    Text(detail)
                        .flowFont(FlowFonts.rowDetail())
                        .foregroundColor(AppColors.Flow.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(row.label == nil ? .leading : .trailing)
                }
            }
            .frame(maxWidth: .infinity, alignment: row.label == nil ? .leading : .trailing)
        }
        .accessibilityIdentifier("volunteerOrderFlowRow-\(row.id)")
    }

    /// 完成页的「查看跑步记录 · 上报问题」（交付包 ⑤）。
    @ViewBuilder
    private var completionLinks: some View {
        if !linkRows.isEmpty {
            HStack(spacing: 8) {
                ForEach(linkRows) { row in
                    FlowTextButton(
                        title: row.value,
                        tone: row.action == .viewRunRecord ? .link : .neutral,
                        accessibilityHint: row.accessibilityHint,
                        action: { onRowAction(row.action ?? .reportIssue) }
                    )
                    .accessibilityIdentifier("volunteerOrderFlowRow-\(row.id)")
                }
            }
        }
    }

    // MARK: 底部动作区

    private var bottomActions: some View {
        VStack(spacing: 8) {
            if let action = presentation.primaryAction {
                if let caption = action.caption {
                    Text(caption)
                        .flowFont(FlowV2Fonts.subhead())
                        .foregroundColor(AppColors.Flow.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        // 已经拼进按钮的 hint，不再单独念一遍。
                        .accessibilityHidden(true)
                }
                FlowActionButton(
                    action.title,
                    systemImage: action.systemImage,
                    style: action == .alreadyDeparted ? .outlined : .raisedPrimary,
                    isLoading: isPrimaryLoading,
                    isEnabled: isPrimaryEnabled,
                    accessibilityHint: [action.caption, primaryActionHint(action)]
                        .compactMap { $0 }.joined(separator: "。").nilIfBlank,
                    action: onPrimaryAction
                )
                .accessibilityIdentifier("volunteerOrderFlowPrimaryButton")
                // ② → ②b「主按钮升级」：白色次要按钮原地换成黄色主按钮，0.98→1 缩放 + 交叉淡入，0.35 秒（03 §二）。
                // 换动作就换身份，旧按钮淡出、新按钮淡入；减弱动态效果下只淡入淡出。
                .id(action.title)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.98).combined(with: .opacity))
            }
            if let dismissRow {
                FlowTextButton(
                    title: dismissRow.value,
                    tone: .neutral,
                    accessibilityHint: dismissRow.accessibilityHint,
                    action: { onRowAction(dismissRow.action ?? .releaseOrder) }
                )
                .accessibilityIdentifier("volunteerOrderFlowRow-\(dismissRow.id)")
            }
        }
        .padding(.horizontal, FlowMetrics.v2ScreenPadding)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .animation(.easeInOut(duration: reduceMotion ? 0.2 : 0.35), value: presentation.primaryAction)
        .background(
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [AppColors.Flow.page.opacity(0), AppColors.Flow.page],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: FlowMetrics.v2BottomFadeHeight)
                .offset(y: -FlowMetrics.v2BottomFadeHeight)
                AppColors.Flow.page
            }
            .ignoresSafeArea(edges: .bottom)
            .accessibilityHidden(true)
        )
    }

    private func primaryActionHint(_ action: VolunteerOrderFlowPresentation.PrimaryAction) -> String? {
        switch action {
        case .acceptInvite:
            // 不解释「先聊聊还是直接接」：两种 `OrderRespondAction` 下这枚按钮做的是同一件事。
            return "接下这一单并通知跑者"
        case .confirmDeparture:
            return "告诉跑者你仍然会来。不确认这一单会转给其他志愿者"
        case .enRoute, .alreadyDeparted:
            return "点击后通知跑者你正在前往"
        case .arrived:
            return "点击后通知跑者你已到达集合点"
        case .startRun:
            return "开始计时，跑者那边也会同步开始"
        case .endWaiting:
            return "这一单会结束，跑者会收到通知"
        case .doneReviewing, .backToHome:
            return nil
        }
    }
}

// MARK: - 头卡状态色

extension VolunteerOrderHero.Style {
    /// 交付包 v2 C01。纯类型那边只说「是哪一种」，取色在视图层。
    var color: Color? {
        switch self {
        case .light: return nil
        case .agreed: return AppColors.Flow.stateAgreed
        case .departed: return AppColors.Flow.stateDeparted
        case .arrived: return AppColors.Flow.stateArrived
        case .done: return AppColors.Flow.stateDone
        }
    }

    var cardStyle: FlowHeroCardStyle {
        color.map { .tinted($0) } ?? .light
    }

    var ropeTheme: RopeView.Theme {
        color.map { .onHero($0) } ?? .light
    }
}

// MARK: - 页面的附属数据

/// 邀请态三宫格里的一格。值与单位分开：两个字号。
struct VolunteerOrderMetric: Identifiable, Equatable {
    let label: String
    let value: String
    let unit: String?

    var id: String { label }
    /// 读屏先说这是什么：「离你，3.2 公里」。
    var spoken: String { "\(label)，\(value)\(unit.map { " \($0)" } ?? "")" }

    /// 与邀请卡 `VolunteerInviteCard.metrics` 同一套取值（离你 / 跑多远 / 配速），缺的格子不画。
    static func invite(_ dispatch: WSNewOrder) -> [Self] {
        [
            dispatch.distanceKm.map { Self(label: "离你", value: String(format: "%.1f", $0), unit: "公里") },
            RunPlanFormat.plannedDistanceParts(meters: dispatch.plannedDistanceMeters).map {
                Self(label: VolunteerOrderFlowCopy.plannedDistanceLabel, value: $0.value, unit: $0.unit)
            },
            dispatch.plannedPaceText.map { Self(label: VolunteerOrderFlowCopy.paceLabel, value: $0, unit: nil) },
        ].compactMap { $0 }
    }
}

/// 汇合页那块：方位盘 / 等待环 + 响铃 + 两列按钮。状态由宿主持有。
struct VolunteerOrderMeetPanel {
    /// 屏幕上的跑者称呼（掩码）与读屏版。
    var runnerName: String
    var runnerNameSpoken: String
    /// `nil` = 不画扇形（`FAR` / `UNKNOWN` / 没有朝向或跑者位置）。
    var relativeDegrees: Double?
    var sectorWidth: Double = DirectionDialGeometry.minimumSector
    var canEndWait: Bool
    /// 距 `earliestEndWaitAt` 还有多少秒。`nil` = 后端没给。
    var endWaitRemainingSeconds: Int?
    /// 在 `ringingUntil` 之前按钮不可点。
    var isRinging: Bool
    /// 「对方可能没收到」/ 429 的等待提示。
    var ringNotice: String?
    var onRing: () -> Void
}

struct VolunteerOrderQuickReplies {
    var runnerName: String
    var items: [FlowQuickReplyGrid.Item]
    var onTap: (String) -> Void
}

extension WaitRing {
    /// 后端 `app.order.arrival-wait-timeout-minutes` 的默认值。
    /// ponytail: 只用于等满后的那一圈「满环」，判定一律走 `earliestEndWaitAt`；后端给出到达时刻后改为实算。
    static let defaultFullSeconds = 900
}

// MARK: - Previews

#if DEBUG
#Preview("① 邀请") { VolunteerOrderV2Preview(kind: .invite) }
#Preview("② 约好 · 前一晚") { VolunteerOrderV2Preview(kind: .agreedEarly) }
#Preview("②b 约好 · 出发前 30 分钟") { VolunteerOrderV2Preview(kind: .agreedSoon) }
#Preview("② 约好 · 没有位置记录") { VolunteerOrderV2Preview(kind: .agreedNoLocation) }
#Preview("② 跨天预约 · 确认还会去") { VolunteerOrderV2Preview(kind: .confirmStillGoing) }
#Preview("③ 出发") { VolunteerOrderV2Preview(kind: .departed(late: false)) }
#Preview("③b 快迟到") { VolunteerOrderV2Preview(kind: .departed(late: true)) }
#Preview("④ 汇合 · 10 米") { VolunteerOrderV2Preview(kind: .arrived(.within10)) }
#Preview("④ 汇合 · 50 米") { VolunteerOrderV2Preview(kind: .arrived(.within50)) }
#Preview("④ 汇合 · 100 米") { VolunteerOrderV2Preview(kind: .arrived(.within100)) }
#Preview("④ 汇合 · 较远") { VolunteerOrderV2Preview(kind: .arrived(.far)) }
#Preview("④ 汇合 · 看不到位置") { VolunteerOrderV2Preview(kind: .arrived(.unknown)) }
#Preview("④b 等满时限") { VolunteerOrderV2Preview(kind: .waitedEnough) }
#Preview("⑤ 完成 · 第 4 次") { VolunteerOrderV2Preview(kind: .completed(count: 4)) }
#Preview("⑤ 完成 · 第一次") { VolunteerOrderV2Preview(kind: .completed(count: 1)) }
#Preview("跑者取消") { VolunteerOrderV2Preview(kind: .runnerCancelled) }
#Preview("③ 出发 · 深色") { VolunteerOrderV2Preview(kind: .departed(late: false)).preferredColorScheme(.dark) }
#Preview("② 约好 · SE + AX3") {
    VolunteerOrderV2Preview(kind: .agreedEarly)
        .environment(\.dynamicTypeSize, .accessibility3)
        .frame(width: 375, height: 667)
}
#Preview("④ 汇合 · SE + AX3") {
    VolunteerOrderV2Preview(kind: .arrived(.within50))
        .environment(\.dynamicTypeSize, .accessibility3)
        .frame(width: 375, height: 667)
}
#Preview("⑤ 完成 · SE + AX3") {
    VolunteerOrderV2Preview(kind: .completed(count: 4))
        .environment(\.dynamicTypeSize, .accessibility3)
        .frame(width: 375, height: 667)
}

/// 所有状态的 Preview 共用这一份装配。示意数据只在这里出现（交付包 00 §四：不要写死）。
private struct VolunteerOrderV2Preview: View {
    enum Kind {
        case invite, agreedEarly, agreedSoon, agreedNoLocation, confirmStillGoing
        case departed(late: Bool)
        case arrived(DistanceBucket)
        case waitedEnough
        case completed(count: Int)
        case runnerCancelled
    }

    let kind: Kind
    private let now = Date()

    var body: some View {
        if case .invite = kind {
            let dispatch = OrderDetailResponse.previewDispatch()
            let presentation = VolunteerOrderFlowPresentation.make(dispatch: dispatch, remainingSeconds: 25)
            VolunteerOrderFlowPage(
                presentation: presentation,
                hero: .make(invite: presentation),
                inviteMetrics: VolunteerOrderMetric.invite(dispatch),
                onBack: {},
                onRowAction: { _ in },
                onPrimaryAction: {},
                footer: { EmptyView() }
            )
        } else {
            let order = self.order
            let phase = VolunteerOrderPhase.resolve(order: order, now: now)
            if let presentation = VolunteerOrderFlowPresentation.make(order: order, distanceText: "距出发地点约 600 米", now: now),
               let phase {
                VolunteerOrderFlowPage(
                    presentation: presentation,
                    hero: .make(order: order, phase: phase, now: now, direction: "右前方"),
                    order: order,
                    phase: phase,
                    meet: meetPanel(order: order, phase: phase),
                    quickReplies: quickReplies(phase: phase),
                    onBack: phase == .completed ? nil : {},
                    onRowAction: { _ in },
                    onPrimaryAction: {},
                    footer: { EmptyView() }
                )
            } else {
                Text("这一态不走 v2 页面")
            }
        }
    }

    private var order: OrderDetailResponse {
        func at(_ minutes: Double) -> String { OrderDetailResponse.previewLocalTime(minutesFromNow: minutes, now: now) }
        var order: OrderDetailResponse
        switch kind {
        case .invite, .agreedEarly:
            order = .preview(status: .pendingAccept, plannedStart: at(22 * 60), blindPhone: "13800001234")
            order.travelMinutes = 20
            order.suggestedDepartAt = at(22 * 60 - 25)
            order.departReminderAt = at(22 * 60 - 30)
            order.primaryActionUnlockAt = at(22 * 60 - 55)
            order.messageToVolunteer = "明天见，谢谢你陪我跑！"
        case .agreedSoon:
            order = .preview(status: .pendingAccept, plannedStart: at(40), blindPhone: "13800001234")
            order.travelMinutes = 20
            order.suggestedDepartAt = at(15)
            order.departReminderAt = at(10)
            order.primaryActionUnlockAt = at(-15)
            order.messageToVolunteer = "明天见，谢谢你陪我跑！"
        case .agreedNoLocation:
            order = .preview(status: .pendingAccept, plannedStart: at(22 * 60), blindPhone: "13800001234")
        case .confirmStillGoing:
            order = .preview(status: .scheduledConfirmed, plannedStart: at(3 * 24 * 60))
        case .departed(let late):
            order = .preview(status: .driverEnRoute, plannedStart: at(late ? 5 : 11), blindPhone: "13800001234")
            order.eta = EtaView(
                remainingMinutes: late ? 11 : 8, arriveAt: at(late ? 11 : 8),
                deltaVsStartMinutes: late ? 6 : -3, late: late, progress: late ? 0.35 : 0.68
            )
            order.runnerAtMeetingPoint = true
        case .arrived(let bucket):
            order = .preview(status: .driverArrived, plannedStart: at(2), blindPhone: "13800001234")
            order.meet = MeetView(distanceBucket: bucket, farDistanceKm: bucket == .far ? 1.8 : nil)
            order.earliestEndWaitAt = at(4)
        case .waitedEnough:
            order = .preview(status: .driverArrived, plannedStart: at(-15), blindPhone: "13800001234")
            order.meet = MeetView(distanceBucket: .far, farDistanceKm: 1.8)
            order.earliestEndWaitAt = at(-1)
        case .completed(let count):
            order = .preview(status: .completed)
            order.completedTogetherCount = count
            order.actualDistanceMeters = 5120
            order.actualDurationSeconds = 2360
        case .runnerCancelled:
            order = .preview(status: .cancelled)
        }
        order.guidePreferenceText = "我习惯你在我左边。过台阶和转弯前，提前说一声就好。"
        order.completedTogetherCount = order.completedTogetherCount ?? 3
        return order
    }

    private func meetPanel(order: OrderDetailResponse, phase: VolunteerOrderPhase) -> VolunteerOrderMeetPanel? {
        guard case .arrived(let canEndWait) = phase else { return nil }
        let bucket = order.meet?.distanceBucket ?? .unknown
        return VolunteerOrderMeetPanel(
            runnerName: "李*", runnerNameSpoken: "李",
            relativeDegrees: MeetBucketCopy.showsDirection(for: bucket) ? 35 : nil,
            sectorWidth: 70,
            canEndWait: canEndWait,
            endWaitRemainingSeconds: canEndWait ? 0 : 240,
            isRinging: false,
            onRing: {}
        )
    }

    private func quickReplies(phase: VolunteerOrderPhase) -> VolunteerOrderQuickReplies? {
        switch phase {
        case .departed:
            return VolunteerOrderQuickReplies(
                runnerName: "李*",
                items: [
                    .init(id: QuickMessageCode.almostThere.rawValue, title: QuickMessageCode.almostThere.title),
                    .init(id: QuickMessageCode.waitFiveMinutes.rawValue, title: QuickMessageCode.waitFiveMinutes.title),
                ],
                onTap: { _ in }
            )
        default:
            return nil
        }
    }
}
#endif
