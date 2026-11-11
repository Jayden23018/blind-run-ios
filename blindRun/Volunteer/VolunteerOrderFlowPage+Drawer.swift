import SwiftUI

// `VolunteerOrderFlowPage` 的下半部分：⑤⑥⑧ 地图 + 抽屉、行的分派、主按钮（#945）。
// 拆出来是为了页面结构体与文件长度过 SwiftLint 棘轮（#488）。
extension VolunteerOrderFlowPage {
    // MARK: ⑤⑥⑧ 地图 + 抽屉

    func trackingLayout(order: OrderDetailResponse) -> some View {
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

    var trackingPrimary: OrderFlowPrimaryAction? {
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
    func trackingDrawer(order: OrderDetailResponse) -> some View {
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
    var departedSubtitle: [String] {
        var lines: [String] = []
        if hero.headline != nil, let number = hero.number {
            lines.append([number, hero.unit].compactMap { $0 }.joined(separator: " "))
        }
        return lines + hero.lines
    }

    /// 抽屉顶上的标题与蓝字副标题。合成一个元素，沿用 v2 头卡的 identifier。
    func drawerHeader(title: String, subtitle: [String]) -> some View {
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
    var arrivedDrawer: some View {
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
    func ringButton(_ meet: VolunteerOrderMeetPanel) -> some View {
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
    func ringIcon(isRinging: Bool) -> some View {
        let image = Image(systemName: "speaker.wave.2").font(.system(size: 17, weight: .bold))
        if #available(iOS 17.0, *) {
            image.symbolEffect(.variableColor.iterative, isActive: isRinging && !reduceMotion)
                .accessibilityHidden(true)
        } else {
            image.accessibilityHidden(true)
        }
    }


    /// 「打电话 / 找不到对方」两枚胶囊（AX 字号下竖排）。等满时限后打电话加重。
    @ViewBuilder
    func meetButtons(callFirst: Bool) -> some View {
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
    func completedDrawer(order: OrderDetailResponse) -> some View {
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

    var rows: [VolunteerOrderFlowPresentation.Row] { presentation.rows }
    var runnerRow: VolunteerOrderFlowPresentation.Row? { rows.first { $0.id == "runner" } }
    var placeRow: VolunteerOrderFlowPresentation.Row? { rows.first { $0.action == .openMeetingPoint } }
    var dismissRow: VolunteerOrderFlowPresentation.Row? {
        rows.first { $0.action == .releaseOrder || $0.action == .declineInvite }
    }
    var cannotFindRow: VolunteerOrderFlowPresentation.Row? { rows.first { $0.action == .cannotFindRunner } }
    /// 只有汇合页把拨号画成按钮；其余页电话仍是信息块里一行（`AGENTS.md` §8：掩码号 + 拨号入口）。
    var callRow: VolunteerOrderFlowPresentation.Row? {
        cannotFindRow == nil ? nil : rows.first { $0.action == .callRunner }
    }
    var linkRows: [VolunteerOrderFlowPresentation.Row] {
        rows.filter { $0.action == .viewRunRecord || $0.action == .reportIssue }
    }

    var showsRunnerCard: Bool {
        switch phase {
        case .confirmStillGoing, .agreedEarly, .agreedSoon, .departed: return true
        case .arrived, .completed, .runnerCancelled, .none: return false
        }
    }

    var infoRows: [VolunteerOrderFlowPresentation.Row] {
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

    func placeRowView(_ row: VolunteerOrderFlowPresentation.Row) -> some View {
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
    var infoBox: some View {
        VStack(spacing: 0) {
            ForEach(Array(infoRows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { FlowSeparator() }
                infoRow(row)
            }
        }
        .padding(.horizontal, 16)
        .modifier(VolunteerV7InfoBoxBackground())
    }

    @ViewBuilder
    func infoRow(_ row: VolunteerOrderFlowPresentation.Row) -> some View {
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

    var metricsSpoken: String {
        inviteMetrics.isEmpty ? "" : "，" + inviteMetrics.map(\.spoken).joined(separator: "，")
    }

    // MARK: 主按钮

    func primaryCaption(_ action: VolunteerOrderFlowPresentation.PrimaryAction) -> String? {
        gateCaption ?? action.caption(awaitingBlindConfirmation: awaitingBlindConfirmation, tetherPreference: order?.tetherPreference)
    }

    /// 小字 + 动作说明合成的读屏提示（小字本身对读屏隐藏，免得念两遍）。
    func primaryHint(_ action: VolunteerOrderFlowPresentation.PrimaryAction) -> String? {
        [primaryCaption(action), primaryActionHint(action)].compactMap { $0 }.joined(separator: "。").nilIfBlank
    }

    func primaryActionHint(_ action: VolunteerOrderFlowPresentation.PrimaryAction) -> String? {
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
