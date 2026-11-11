import SwiftUI

// MARK: - 陪跑员订单页 v7（#945，定稿 `docs/ui/mockups/volunteer-order-v7-20261111/`）

/// 陪跑员订单页（邀请 / 约好 / 出发 / 汇合 / 完成 / 跑者取消）。与盲人端订单页 v7 同一套版式：
/// - ① 邀请、④ 约好、⑨ 跑者已取消：顶栏 + 深色头 + 白底抽屉（地点、五步竖线、当前步那张卡）+ 底部一枚深色主按钮
///   （外壳 `BlindOrderStageScaffold`）；
/// - ⑤ 出发、⑥ 汇合、⑧ 完成：上半屏地图常驻 + 下半屏抽屉，竖线拉起抽屉才渐显（外壳 `BlindOrderTrackingView`）。
/// 跑步中是另一个结构体 `VolunteerRunningPage`，用同一个地图外壳。
///
/// 动效只留淡入淡出、当前步圆点、竖线生长（定稿第 5 条）：不再有弹簧、缩放、滑入、绳子画出。
///
/// **这个视图不判任何状态。** 两个纯类型给它全部内容：
/// - `VolunteerOrderFlowPresentation`：信息行、主按钮、求助路由（隐私闸与按状态发动作都在那边，用例穷举）；
/// - `VolunteerOrderHero`：头部的小标题、主角数字 / 主角句、副文、在场提示、提醒条。
///
/// 两个数据源各有一个入口：邀请吃派单推送 `WSNewOrder`（接单前拿不到订单详情，后端恒 403），
/// 其余吃 `OrderDetailResponse`。
struct VolunteerOrderFlowPage<Footer: View>: View {
    let presentation: VolunteerOrderFlowPresentation
    let hero: VolunteerOrderHero
    /// `nil` = 邀请态（没有订单详情）。
    var order: OrderDetailResponse?
    var phase: VolunteerOrderPhase?
    /// 邀请态的距离 / 配速这类封闭取值（接单前能给看的，AGENTS §8）。
    var inviteMetrics: [VolunteerOrderMetric] = []
    var inviteRunnerName: String?  // 邀请态没有订单详情时的跑者姓（去星号，#339）；接单后读 `order.blindName`
    /// 汇合页的方位盘、响铃、等待。`nil` = 不是汇合页。
    var meet: VolunteerOrderMeetPanel?
    /// 出发页的快捷回复。`nil` = 不显示。
    var quickReplies: VolunteerOrderQuickReplies?
    /// 出发 / 汇合 / 完成三态的地图。`nil` = 只画集合点（宿主拿不到位置时）。
    var mapInput: BlindTrackingMapInput?
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
    /// 「开始跑步」按下后后端答 `BLIND_CONFIRMATION_PENDING`：按钮上方小字换成「等待对方确认」，按钮仍可按。
    var awaitingBlindConfirmation: Bool = false
    /// 后端放行时刻给的那句小字（`VolunteerActionGate.caption`），优先于动作自己的那句。
    var gateCaption: String? = nil
    /// 非 `nil` = 顶栏「···」带举报 / 不再匹配此人。有没有对方由宿主判。
    var counterpartSafety: CounterpartBlockViewModel? = nil
    /// 「刚才那一下的结果」。**这一页唯一的可见失败面**，少了它失败只剩一句 TTS。
    @ViewBuilder let footer: () -> Footer

    @State private var showsLocalHelp = false
    @AccessibilityFocusState private var headerFocused: Bool
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        Group {
            if usesMap, let order {
                trackingLayout(order: order)
            } else {
                stageLayout
            }
        }
        .emergencyCallOptionsDialog(isPresented: $showsLocalHelp, context: .volunteerBeforeRun, primaryContact: nil)
    }

    /// 出发起地图常驻（定稿第 1 条）。
    private var usesMap: Bool {
        switch phase {
        case .departed, .arrived, .completed: return true
        case .confirmStillGoing, .agreedEarly, .agreedSoon, .runnerCancelled, .none: return false
        }
    }

    private func openHelp() {
        switch presentation.helpMode {
        case .cloud: onCloudHelp()
        case .localCall: showsLocalHelp = true
        }
    }

    // MARK: 顶栏

    private func topBar(surface: BlindOrderBarSurface) -> VolunteerOrderTopBar {
        VolunteerOrderTopBar(
            surface: surface,
            onBack: { onBack?() },
            showsBack: onBack != nil,
            menu: menuItems,
            counterpartSafety: counterpartSafety,
            isCloudHelp: presentation.helpMode == .cloud,
            onHelp: openHelp
        )
    }

    /// 「我去不了」收进「···」（定稿第 4 条，与盲人端「取消预约」一致）。邀请态的「这次去不了」留在主按钮下面：
    /// 那是对邀请的回答，不是次要操作。
    private var menuItems: [VolunteerOrderMenuItem] {
        guard let release = rows.first(where: { $0.action == .releaseOrder }) else { return [] }
        return [VolunteerOrderMenuItem(kind: .releaseOrder, title: release.value, isDestructive: true) {
            onRowAction(.releaseOrder)
        }]
    }

    // MARK: ①④⑨ 深色头 + 竖线

    private var stageLayout: some View {
        BlindOrderStageScaffold(
            topBar: topBar(surface: .onDark),
            eyebrow: hero.eyebrow,
            title: headerTitle,
            headerAccessibilityLabel: hero.accessibilityLabel + metricsSpoken,
            headerFocused: $headerFocused,
            headerIdentifier: .volunteerStatusCard,
            place: stagePlace,
            when: stageWhen,
            timeline: timelineInput,
            card: { currentCard },
            footer: { stageFooter },
            bottom: { stageBottom }
        )
    }

    /// 头部大字：主角句优先，没有就拼主角数字（「8 分钟后到」「明天 7:00 开跑」）。
    private var headerTitle: String {
        if let headline = hero.headline { return headline }
        return [hero.number, hero.unit].compactMap { $0 }.joined(separator: " ")
    }

    private var stagePlace: String? {
        if phase == .runnerCancelled { return VolunteerOrderFlowCopy.runnerCancelledSubtitle }
        return placeRow?.value ?? order?.startAddress?.nilIfBlank
    }

    /// 地点下面那行：邀请态是距离 / 配速，其余是头部副文的第一行。
    private var stageWhen: String? {
        if !inviteMetrics.isEmpty {
            return inviteMetrics.map { [$0.value, $0.unit].compactMap { $0 }.joined(separator: " ") }.joined(separator: " · ")
        }
        return phase == .runnerCancelled ? nil : hero.lines.first
    }

    private var timelinePosition: BlindOrderTimelinePosition {
        switch phase {
        case .none: return .current(.matchVolunteer)
        case .confirmStillGoing, .agreedEarly, .agreedSoon, .runnerCancelled: return .current(.awaitDeparture)
        case .departed, .arrived: return .current(.meetUp)
        case .completed: return .allDone
        }
    }

    private var timelineInput: BlindOrderTimelineInput {
        var details: [BlindOrderTimelineStep: String] = [:]
        if phase == .runnerCancelled {
            // ⑨：五步全画、行距放宽（负责人 11-11「太挤了」），中断那步打叉。
            details[.awaitDeparture] = VolunteerOrderFlowCopy.runnerCancelledStepDetail
            return BlindOrderTimelineInput(
                position: timelinePosition, details: details, folds: false,
                currentDot: .interrupted, vocabulary: .volunteer, roomy: true
            )
        }
        if case .current(let step) = timelinePosition {
            details[step] = presentation.replyNotice ?? hero.presence
        }
        return BlindOrderTimelineInput(position: timelinePosition, details: details, vocabulary: .volunteer)
    }

    /// 当前步那张卡：深色块是头部副文（建议出发时间、带绳提醒），下半截是跑者一行。
    @ViewBuilder
    private var currentCard: some View {
        let lines = Array(hero.lines.dropFirst(stageWhen == hero.lines.first ? 1 : 0))
        if phase == .runnerCancelled {
            EmptyView()
        } else if !lines.isEmpty || runnerLine != nil {
            BlindOrderStepCard(lead: nil, body: lines.isEmpty ? VolunteerOrderFlowCopy.pageTitle : lines.joined(separator: "\n")) {
                if let runnerLine { runnerLine }
            }
        }
    }

    private var runnerLine: BlindOrderPersonRow? {
        guard let runnerRow, showsRunnerCard else { return nil }
        let name = runnerRow.value
        let line = [name, runnerRow.detail?.replacingOccurrences(of: "，", with: " · ")].compactMap { $0?.nilIfBlank }.joined(separator: " · ")
        return BlindOrderPersonRow(
            initial: String(name.unmaskedForSpeech.prefix(1)),
            label: "你陪的跑者",
            line: line,
            spoken: runnerRow.accessibilityLabel
        )
    }

    @ViewBuilder
    private var stageFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let notice = hero.notice {
                FlowNoticeBar(text: notice).transition(.opacity)
            }
            if !infoRows.isEmpty { infoBox }
            footer()
        }
        .padding(.top, phase == .runnerCancelled ? 14 : 0)
        .animation(.easeInOut(duration: 0.25), value: hero.notice)
    }

    @ViewBuilder
    private var stageBottom: some View {
        VStack(spacing: 4) {
            if let action = presentation.primaryAction {
                if let caption = primaryCaption(action) {
                    Text(caption)
                        .flowFont(FlowV2Fonts.subhead())
                        .foregroundColor(AppColors.Flow.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        // 已经拼进按钮的 hint，不再单独念一遍。
                        .accessibilityHidden(true)
                }
                BlindOrderStageButton(
                    title: action.title,
                    systemImage: action.systemImage,
                    style: action == .alreadyDeparted ? .outline : .solid,
                    isEnabled: isPrimaryEnabled && !isPrimaryLoading,
                    accessibilityHint: primaryHint(action),
                    action: onPrimaryAction
                )
                .accessibilityIdentifier("volunteerOrderFlowPrimaryButton")
                .transition(.opacity)
            }
            if let decline = rows.first(where: { $0.action == .declineInvite }) {
                FlowTextButton(
                    title: decline.value,
                    tone: .neutral,
                    accessibilityHint: decline.accessibilityHint,
                    action: { onRowAction(.declineInvite) }
                )
                .accessibilityIdentifier("volunteerOrderFlowRow-\(decline.id)")
            }
        }
        .animation(.easeInOut(duration: 0.25), value: presentation.primaryAction)
    }

    // MARK: ⑤⑥⑧ 地图 + 抽屉

    private func trackingLayout(order: OrderDetailResponse) -> some View {
        var input = mapInput ?? BlindTrackingMapInput(meetPoint: order.startCoordinate)
        input.peerTitle = "跑者"
        return BlindOrderTrackingView(
            status: order.status,
            mapInput: input,
            topBar: topBar(surface: .onMap),
            bottom: OrderFlowBottomActions(owner: .volunteer, primary: trackingPrimary, safetyHub: nil),
            drawer: { trackingDrawer(order: order) },
            timeline: {
                BlindOrderTimelineView(
                    input: BlindOrderTimelineInput(position: timelinePosition, folds: false, vocabulary: .volunteer)
                ) { _ in EmptyView() }
            },
            footer: { footer() }
        )
    }

    private var trackingPrimary: OrderFlowPrimaryAction? {
        presentation.primaryAction.map { action in
            OrderFlowPrimaryAction(
                title: action.title,
                systemImage: action.systemImage,
                isLoading: isPrimaryLoading,
                isEnabled: isPrimaryEnabled,
                caption: primaryCaption(action),
                accessibilityHint: primaryActionHint(action),
                action: onPrimaryAction
            )
        }
    }

    @ViewBuilder
    private func trackingDrawer(order: OrderDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            switch phase {
            case .completed:
                completedDrawer(order: order)
            case .arrived:
                arrivedDrawer
            default:
                drawerHeader(title: headerTitle, subtitle: departedSubtitle)
                if let runnerLine { runnerLine.padding(.horizontal, -16) }
                if let quickReplies {
                    FlowQuickReplyGrid(
                        title: "一键告诉\(quickReplies.runnerName)",
                        items: quickReplies.items,
                        onTap: { quickReplies.onTap($0.id) }
                    )
                }
                if let place = placeRow { placeRowView(place) }
                if let notice = hero.notice { FlowNoticeBar(text: notice) }
                if !infoRows.isEmpty { infoBox }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.25), value: phase)
    }

    /// 出发：「8 分钟后到」+ 头部副文。
    private var departedSubtitle: [String] {
        var lines: [String] = []
        if hero.headline != nil, let number = hero.number {
            lines.append([number, hero.unit].compactMap { $0 }.joined(separator: " "))
        }
        return lines + hero.lines
    }

    /// 抽屉顶上的标题与蓝字副标题。合成一个元素，沿用 v2 头卡的 identifier。
    private func drawerHeader(title: String, subtitle: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .flowFont(FlowV2Fonts.title())
                .foregroundColor(hero.isGold ? AppColors.Flow.gold : AppColors.Flow.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(subtitle, id: \.self) { line in
                Text(line)
                    .flowFont(FlowV2Fonts.callout())
                    .foregroundColor(AppColors.Flow.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hero.accessibilityLabel)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("volunteerOrderFlowStatusCard")
    }

    // MARK: ⑥ 汇合

    @ViewBuilder
    private var arrivedDrawer: some View {
        HStack(alignment: .center, spacing: 12) {
            drawerHeader(title: headerTitle, subtitle: hero.lines)
            if let meet, !meet.canEndWait, let degrees = meet.relativeDegrees {
                // 没有方向（太远 / 位置未知 / 拿不到朝向）不画方位盘（负责人 2026-10-05）。
                DirectionDial(relativeDegrees: degrees, sectorWidth: meet.sectorWidth, diameter: 96)
                    .transition(.opacity)
            }
        }
        if let meet {
            if meet.canEndWait {
                WaitRing(waitedSeconds: WaitRing.defaultFullSeconds)
                    .frame(maxWidth: .infinity)
            } else if let remaining = meet.endWaitRemainingSeconds, remaining > 0 {
                Text("再等 \(Int((Double(remaining) / 60).rounded(.up))) 分钟可以结束等待")
                    .flowFont(FlowV2Fonts.subhead())
                    .foregroundColor(AppColors.Flow.secondaryText)
            }
            meetButtons(callFirst: meet.canEndWait)
            ringButton(meet)
            if let ringNotice = meet.ringNotice {
                Text(ringNotice)
                    .flowFont(FlowV2Fonts.subhead(bold: true))
                    .foregroundColor(AppColors.Flow.warmCardTitle)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if let notice = hero.notice { FlowNoticeBar(text: notice) }
        if !infoRows.isEmpty { infoBox }
    }

    /// 「让陈的手机响起来」：一整行，与盲人 v7 抽屉里的行同一个样子。
    private func ringButton(_ meet: VolunteerOrderMeetPanel) -> some View {
        Button(action: meet.onRing) {
            HStack(spacing: 10) {
                ringIcon(isRinging: meet.isRinging)
                Text(meet.isRinging ? "正在响铃…" : "让\(meet.runnerName)的手机响起来")
                    .flowFont((17, .semibold, .body))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppColors.Flow.secondaryText)
                    .accessibilityHidden(true)
            }
            .foregroundColor(AppColors.Flow.primaryText)
            .frame(maxWidth: .infinity, minHeight: FlowMetrics.actionButtonMinHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { FlowSeparator() }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(meet.isRinging ? "正在响铃" : "让\(meet.runnerNameSpoken)的手机响起来")
        .accessibilityHint("\(meet.runnerNameSpoken)的手机会响铃，并播报你的陪跑员到了")
        .disabled(meet.isRinging)
        .accessibilityIdentifier("volunteerOrderRingButton")
    }

    /// 响铃中图标做 `variableColor`（iOS 17+，淡入淡出类的动效）；减弱动态效果下静止。
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// 「打电话 / 找不到对方」两枚胶囊（AX 字号下竖排）。等满时限后打电话加重。
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
                        .flowFont((16, .bold, .callout))
                        .foregroundColor(emphasized ? .white : AppColors.Flow.primaryText)
                        .frame(maxWidth: .infinity, minHeight: FlowMetrics.v2TertiaryMinHeight)
                        .background(Capsule().fill(emphasized ? AppColors.Flow.navy : AppColors.Flow.surfaceSubtle))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(row.accessibilityLabel)
                    .accessibilityHintIfPresent(row.accessibilityHint)
                    .accessibilityIdentifier("volunteerOrderFlowRow-\(row.id)")
                }
            }
        }
    }

    // MARK: ⑧ 完成

    /// 负责人 11-11「状态卡有点挤」后的改稿：标题只写「跑完了」，次数进副标题；
    /// 绿卡里距离单独一行、用时第二行；星级单独一张卡（在 `footer` 里）；两个去处并排。
    @ViewBuilder
    private func completedDrawer(order: OrderDetailResponse) -> some View {
        drawerHeader(
            title: VolunteerOrderFlowCopy.completedDrawerTitle,
            subtitle: [hero.headline, order.startAddress?.nilIfBlank].compactMap { $0 }
        )
        VolunteerCompletedResultCard(order: order)
        if !linkRows.isEmpty {
            HStack(spacing: 10) {
                ForEach(linkRows) { row in
                    Button { onRowAction(row.action ?? .reportIssue) } label: {
                        Text(row.value)
                            .flowFont((16, .bold, .callout))
                            .foregroundColor(AppColors.Flow.primaryText)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: FlowMetrics.v2TertiaryMinHeight)
                            .background(Capsule().fill(AppColors.Flow.surfaceSubtle))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHintIfPresent(row.accessibilityHint)
                    .accessibilityIdentifier("volunteerOrderFlowRow-\(row.id)")
                }
            }
        }
    }

    // MARK: 行的分派
    //
    // 行本身（有哪些、读屏说什么、接单前露不露）全在 `VolunteerOrderFlowPresentation` 里定；
    // 这里只决定**画成什么形状**：集合点画成地点行、「我去不了」进「···」、「这次去不了」画成主按钮下的文字按钮、
    // 汇合页的拨号与找人画成两枚胶囊、完成页两个去处画成并排按钮，其余进信息块。

    private var rows: [VolunteerOrderFlowPresentation.Row] { presentation.rows }
    private var runnerRow: VolunteerOrderFlowPresentation.Row? { rows.first { $0.id == "runner" } }
    private var placeRow: VolunteerOrderFlowPresentation.Row? { rows.first { $0.action == .openMeetingPoint } }
    private var dismissRow: VolunteerOrderFlowPresentation.Row? {
        rows.first { $0.action == .releaseOrder || $0.action == .declineInvite }
    }
    private var cannotFindRow: VolunteerOrderFlowPresentation.Row? { rows.first { $0.action == .cannotFindRunner } }
    /// 只有汇合页把拨号画成按钮；其余页电话仍是信息块里一行（`AGENTS.md` §8：掩码号 + 拨号入口）。
    private var callRow: VolunteerOrderFlowPresentation.Row? {
        cannotFindRow == nil ? nil : rows.first { $0.action == .callRunner }
    }
    private var linkRows: [VolunteerOrderFlowPresentation.Row] {
        rows.filter { $0.action == .viewRunRecord || $0.action == .reportIssue }
    }

    private var showsRunnerCard: Bool {
        switch phase {
        case .confirmStillGoing, .agreedEarly, .agreedSoon, .departed: return true
        case .arrived, .completed, .runnerCancelled, .none: return false
        }
    }

    private var infoRows: [VolunteerOrderFlowPresentation.Row] {
        // 出发起集合点画成地点行；①④ 的集合点已在抽屉顶上那行，但它是个可点的导航入口，留在信息块里。
        let placeTaken = usesMap ? placeRow?.id : nil
        let taken = Set([placeTaken, dismissRow?.id, cannotFindRow?.id, callRow?.id].compactMap { $0 } + linkRows.map(\.id))
        return rows.filter { row in
            if taken.contains(row.id) { return false }
            if row.id == "runner" && showsRunnerCard { return false }
            // 邀请态地点下面那行已经说了跑多远 / 配速，信息块里不再重复。
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

    /// 信息块：浅灰圆角底、行间细线（同盲人 v7 ③ 安排单与 ⑨ 原定信息卡）。
    private var infoBox: some View {
        VStack(spacing: 0) {
            ForEach(Array(infoRows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { FlowSeparator() }
                infoRow(row)
            }
        }
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(AppColors.Flow.surfaceSubtle)
        )
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

    private var metricsSpoken: String {
        inviteMetrics.isEmpty ? "" : "，" + inviteMetrics.map(\.spoken).joined(separator: "，")
    }

    // MARK: 主按钮

    private func primaryCaption(_ action: VolunteerOrderFlowPresentation.PrimaryAction) -> String? {
        gateCaption ?? action.caption(awaitingBlindConfirmation: awaitingBlindConfirmation, tetherPreference: order?.tetherPreference)
    }

    /// 小字 + 动作说明合成的读屏提示（小字本身对读屏隐藏，免得念两遍）。
    private func primaryHint(_ action: VolunteerOrderFlowPresentation.PrimaryAction) -> String? {
        [primaryCaption(action), primaryActionHint(action)].compactMap { $0 }.joined(separator: "。").nilIfBlank
    }

    private func primaryActionHint(_ action: VolunteerOrderFlowPresentation.PrimaryAction) -> String? {
        switch action {
        case .acceptInvite:
            // 不解释「先聊聊还是直接接」：两种 `OrderRespondAction` 下这枚按钮做的是同一件事。
            return "接受预约"
        case .confirmDeparture:
            return "请确认按时到达。未确认的订单将转给其他陪跑员"
        case .enRoute, .alreadyDeparted:
            return "点击后通知跑者你正在前往"
        case .arrived:
            return "点击后通知跑者你已到达集合点"
        case .startRun:
            return "开始计时，跑者那边也会同步开始"
        case .endWaiting:
            return "此订单会结束，跑者会收到通知"
        case .doneReviewing, .backToHome:
            return nil
        }
    }
}

/// ⑧ 完成页的绿色成果卡：距离单独一行，用时在第二行（负责人 11-11「有点挤」后的改稿）。
/// 只读订单上已有的实跑数字；没有就整卡不画（跑步记录页有完整数据）。
struct VolunteerCompletedResultCard: View {
    let order: OrderDetailResponse

    var body: some View {
        if let meters = order.actualDistanceMeters {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(RunPlanFormat.kilometresValue(Double(meters) / 1_000))
                        .flowHeroNumber(FlowV2Fonts.heroM, capped: false)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("公里").flowFont(FlowV2Fonts.heroUnit())
                }
                if let seconds = order.actualDurationSeconds {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("用时")
                            .flowFont(FlowV2Fonts.subhead())
                            .foregroundColor(Color.white.opacity(0.85))
                        Text("\(Int((Double(seconds) / 60).rounded())) 分钟")
                            .flowFont((20, .bold, .title3))
                    }
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(AppColors.Flow.stateDone))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken(meters: meters))
        }
    }

    private func spoken(meters: Int) -> String {
        var parts = ["跑了 \(RunPlanFormat.kilometresValue(Double(meters) / 1_000)) 公里"]
        if let seconds = order.actualDurationSeconds {
            parts.append("用时 \(Int((Double(seconds) / 60).rounded())) 分钟")
        }
        return parts.joined(separator: "，")
    }
}

extension VolunteerOrderHero.Style {
    /// 交付包 v2 C01。纯类型那边只说「是哪一种」，取色在视图层。v7 页面只在锁屏卡等处还用到它。
    var color: Color {
        switch self {
        case .matching: return AppColors.Flow.stateMatching
        case .agreed: return AppColors.Flow.stateAgreed
        case .departed: return AppColors.Flow.stateDeparted
        case .arrived: return AppColors.Flow.stateArrived
        case .done: return AppColors.Flow.stateDone
        }
    }
}

// MARK: - 跑步中（v7 ⑦）

/// 跑步中头卡的全部内容。纯类型，用例 `VolunteerRunningHeroTests`。
///
/// 数据只有跑者那一份 `blindStats`（与跑者端同一个端点、同一份数字），目标来自订单的
/// `plannedDistanceMeters`。**不画「折返」**：画布的「2.50 折返」默认原路往返，
/// 而契约里没有路线形状，绕圈跑时那个标记是错的。
struct VolunteerRunningHero: Equatable {
    struct Goal: Equatable {
        /// 0…1，跑过目标钳在 1。
        let progress: Double
        let text: String
        let isReached: Bool
    }

    let eyebrow: String
    /// 两位小数的公里数；还没有数据时 `--`（刚起跑的十几秒轨迹点不够，那是空态不是错误）。
    let distance: String
    let duration: String
    let pace: String
    /// `nil` = 订单没有计划里程 ⇒ 不画进度条。
    let goal: Goal?
    /// 头卡下方那一条提示（同一时间最多一条）。屏幕版带掩码姓名，读屏版不带。
    let notice: String?
    let noticeSpoken: String?
    let accessibilityLabel: String

    static let title = "陪跑中"
    /// 跑过目标不足 50 米不说「多跑了」：公里数是一位小数（#846 D8），十几米会写成「多跑了 0.1」。
    static let overrunThresholdMeters: Double = 50

    static func make(
        order: OrderDetailResponse,
        stats: TrackStats?,
        isPeerLocationFresh: Bool,
        isPeerAlertAcknowledged: Bool
    ) -> Self {
        let place = order.startAddress?.nilIfBlank
        let name = order.blindName?.nilIfBlank ?? VolunteerOrderFlowCopy.unknownRunnerName
        let spokenName = order.blindNameForSpeech

        let goal = order.plannedDistanceMeters.flatMap { planned -> Goal? in
            guard planned > 0 else { return nil }
            let target = RunPlanFormat.kilometresValue(Double(planned) / 1_000)
            guard let run = stats?.distanceMeters else {
                return Goal(progress: 0, text: "目标 \(target) 公里", isReached: false)
            }
            let over = run - Double(planned)
            if over >= 0 {
                let extra = over >= overrunThresholdMeters ? " · 多跑了 \(RunPlanFormat.kilometresValue(over / 1_000))" : ""
                return Goal(progress: 1, text: "已完成 \(target) 公里目标\(extra)", isReached: true)
            }
            return Goal(
                progress: run / Double(planned),
                text: "还剩 \(RunPlanFormat.kilometresValue(-over / 1_000)) 公里 · 目标 \(target)",
                isReached: false
            )
        }

        // 已确认的求助排在前面：那是「他还在求助、只是有人接手了」，比位置断了更要紧。
        // 未确认的不走这里 —— 全屏告警和求助结果区已经在说。
        let notice: (String, String)?
        if isPeerAlertAcknowledged {
            let status = EmergencySafetyCopy.volunteerPeerStatusAcknowledged
            notice = ("\(name)的求助\(status)", "\(spokenName)的求助\(status)")
        } else if !isPeerLocationFresh {
            let stale = EmergencySafetyCopy.volunteerPeerLocationStale
            notice = ("\(stale)\(name)的位置", "\(stale)\(spokenName)的位置")
        } else {
            notice = nil
        }

        func spoken(_ label: String, _ value: String?) -> String {
            value.map { "\(label) \($0)" } ?? "\(label)，正在获取"
        }
        let spokenParts = [
            place.map { "\(title)，\($0)" } ?? title,
            spoken("已跑", stats?.distanceText),
            spoken("时长", stats?.durationText),
            spoken("配速", stats?.averagePaceText),
            goal?.text.replacingOccurrences(of: " · ", with: "，"),
        ]

        return Self(
            eyebrow: place.map { "\(title) · \($0)" } ?? title,
            distance: stats?.distanceKilometersText ?? "--",
            duration: stats?.durationClockText ?? "--",
            pace: stats?.paceClockText ?? "--",
            goal: goal,
            notice: notice?.0,
            noticeSpoken: notice?.1,
            accessibilityLabel: spokenParts.compactMap { $0 }.joined(separator: "。")
        )
    }
}

/// 陪跑员跑步中那一屏（v7 ⑦，#945）：地图常驻 + 抽屉（距离 / 用时 / 配速、目标进度、一条提示、耳机播报）+
/// 底部长按结束。右上角红色实心「求助」开跑步中求助面板（V5，面板本身不改）。
///
/// 求助走云端还是本地拨号只读 `VolunteerOrderSOSMode.resolve`（AGENTS §6）：这一页只在 `IN_PROGRESS` 出现，结果恒为云端。
/// 不画「折返」：契约里没有路线形状。地图只画跑者位置与集合点（跑中没有整条路线数据）。
///
/// 自己 `@ObservedObject` 持有 coordinator：`AppState.emergencyCoordinator` 是 `let`，
/// 在宿主 body 里读它**读得到值但不跟着更新**（记忆 `nested-observableobject-does-not-republish`）。
struct VolunteerRunningPage<Footer: View>: View {
    @ObservedObject var coordinator: EmergencyCoordinator
    let order: OrderDetailResponse
    let stats: TrackStats?
    let isPeerLocationFresh: Bool
    /// 跑者位置、集合点、本机位置。`nil` = 只画集合点。
    var mapInput: BlindTrackingMapInput?
    let isFinishing: Bool
    let isFinishEnabled: Bool
    let onBack: () -> Void
    let onHelp: () -> Void
    let onFinish: () -> Void
    /// 跑到一半陪不了了（受伤、临时有事）：订单转 `REMATCHING` 换人，**不是**结束陪跑。
    /// 删掉的话唯一的退出就只剩「结束陪跑」—— 那会把没跑完的一单记成完成、并计入志愿时长。
    let onCancel: () -> Void
    /// 提示（走散 / 电量低 / 定位弱）、暂停与继续。
    let tip: VolunteerRunTip?
    let isTogglingPause: Bool
    let onResume: () -> Void
    /// 求助结果、流转失败文案。**这一页唯一的可见失败面**。
    @ViewBuilder let footer: () -> Footer

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var hero: VolunteerRunningHero {
        .make(
            order: order,
            stats: stats,
            isPeerLocationFresh: isPeerLocationFresh,
            isPeerAlertAcknowledged: coordinator.volunteerAlert?.isAcknowledged == true
        )
    }

    private var isPaused: Bool { order.isRunPaused }

    private var notice: VolunteerRunningNotice? {
        .resolve(
            isPeerAlertAcknowledged: coordinator.volunteerAlert?.isAcknowledged == true,
            heroHasNotice: hero.notice != nil,
            tip: tip
        )
    }

    var body: some View {
        var input = mapInput ?? BlindTrackingMapInput(meetPoint: order.startCoordinate)
        input.peerTitle = "跑者"
        return BlindOrderTrackingView(
            status: order.status,
            mapInput: input,
            topBar: VolunteerOrderTopBar(
                surface: .onMap,
                onBack: onBack,
                isCloudHelp: VolunteerOrderSOSMode.resolve(status: order.status) == .cloud,
                isHelpBusy: coordinator.state.isBusy,
                onHelp: onHelp
            ),
            bottom: OrderFlowBottomActions(owner: .volunteer, primary: nil, secondary: AnyView(bottomControls), safetyHub: nil),
            drawer: { drawer },
            timeline: {
                BlindOrderTimelineView(
                    input: BlindOrderTimelineInput(position: .current(.startRun), folds: false, vocabulary: .volunteer)
                ) { _ in EmptyView() }
            },
            footer: { footer() }
        )
    }

    // MARK: 抽屉

    private var drawer: some View {
        let hero = hero
        return VStack(alignment: .leading, spacing: 16) {
            statsBlock(hero)
            // 同一时刻只有一条（`VolunteerRunningNotice`）。
            switch notice {
            case .hero:
                if let text = hero.notice {
                    FlowNoticeBar(text: text)
                        .accessibilityLabel(hero.noticeSpoken ?? text)
                        .accessibilityIdentifier("volunteerRunningNotice")
                }
            case .tip(let tip):
                VolunteerRunTipBar(tip: tip, name: order.runnerShortName)
            case .none:
                EmptyView()
            }
            VolunteerRunVoiceToggle()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.25), value: notice)
        .animation(.easeInOut(duration: 0.25), value: isPaused)
    }

    private var title: String {
        if isPaused { return VolunteerRunCopy.pausedTitle(elapsed: order.run?.elapsedClockText) }
        return "和\(order.runnerShortName)一起跑步中"
    }

    /// 标题 + 44pt 距离 + 用时 / 配速 + 目标进度。合成一个读屏元素，沿用 v2 头卡的 identifier。
    private func statsBlock(_ hero: VolunteerRunningHero) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .flowFont(FlowV2Fonts.title(), monospacedDigit: true)
                .foregroundColor(AppColors.Flow.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if isPaused {
                Text(VolunteerRunCopy.pausedBody)
                    .flowFont(FlowV2Fonts.callout())
                    .foregroundColor(AppColors.Flow.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            metricsRow(hero)
            if let goal = hero.goal { goalView(goal) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isPaused
                ? "\(VolunteerRunCopy.pausedTitle(elapsed: order.run?.elapsedClockText))，\(VolunteerRunCopy.pausedBody)。\(hero.accessibilityLabel)"
                : hero.accessibilityLabel
        )
        .accessibilityIdentifier("volunteerRunningStatsCard")
    }

    /// 距离 44pt（盲人 v7 ⑦ 同值），用时 / 配速在右边；辅助字号下竖排。
    private func metricsRow(_ hero: VolunteerRunningHero) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .lastTextBaseline, spacing: 24))
        return layout {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(hero.distance)
                    .flowFont((44, .bold, .largeTitle), monospacedDigit: true)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("公里").flowFont(FlowV2Fonts.heroUnit())
            }
            metric(value: hero.duration, label: "用时")
            metric(value: hero.pace, label: "配速")
        }
        .foregroundColor(AppColors.Flow.primaryText)
    }

    private func metric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .flowFont(FlowV2Fonts.subhead())
                .foregroundColor(AppColors.Flow.secondaryText)
            Text(value)
                .flowFont((22, .bold, .title2), monospacedDigit: true)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    private func goalView(_ goal: VolunteerRunningHero.Goal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColors.Flow.separator)
                    Capsule()
                        .fill(goal.isReached ? AppColors.Flow.stateDone : AppColors.Flow.navy)
                        .frame(width: proxy.size.width * goal.progress)
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
            Text(goal.text)
                .flowFont(FlowV2Fonts.subhead(), monospacedDigit: true)
                .foregroundColor(AppColors.Flow.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 底部

    private var bottomControls: some View {
        VStack(spacing: 8) {
            // 暂停中本屏唯一的实心按钮（08 §五）；长按结束保持在它下面。
            if isPaused {
                BlindOrderStageButton(
                    title: VolunteerRunCopy.resume,
                    systemImage: "play.fill",
                    style: .solid,
                    isEnabled: !isTogglingPause,
                    accessibilityHint: "恢复计时",
                    action: onResume
                )
                .accessibilityIdentifier("volunteerRunResumeButton")
                .transition(.opacity)
            }
            VolunteerFinishLongPressButton(
                isPerformingAction: isFinishing,
                isEnabled: isFinishEnabled,
                onFinish: onFinish
            )
            // 取消类一律灰色文字（交付包 v3 禁止项），不和长按结束抢视觉重量。
            FlowTextButton(
                title: VolunteerServiceActionKind.cancelOrder.title,
                tone: .neutral,
                accessibilityHint: "双击后会先确认一次。取消前请先把跑者带到安全的地方",
                action: onCancel
            )
            .disabled(isFinishing || !isFinishEnabled)
            .accessibilityIdentifier("volunteerRunningCancel")
        }
        .animation(.easeInOut(duration: 0.25), value: isPaused)
    }
}

// MARK: - 页面的附属数据

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
