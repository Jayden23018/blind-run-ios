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
    /// ⑨ 跑者已取消：本单状态变更记录，竖线停在哪一步由它推（#962）。空 = 不画竖线。
    var statusLogs: [OrderStatusLog] = []
    /// 非 `nil` = 顶栏「···」带举报 / 不再匹配此人。有没有对方由宿主判。
    var counterpartSafety: CounterpartBlockViewModel? = nil
    /// 「刚才那一下的结果」。**这一页唯一的可见失败面**，少了它失败只剩一句 TTS。
    @ViewBuilder let footer: () -> Footer

    @State var showsLocalHelp = false
    @AccessibilityFocusState var headerFocused: Bool
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    var body: some View {
        Group {
            if usesMap, let order {
                trackingLayout(order: order)
            } else {
                stageLayout
            }
        }
        .emergencyCallOptionsDialog(isPresented: $showsLocalHelp, context: .volunteerBeforeRun, primaryContact: nil)
        // 订单状态一变，读屏焦点移到页头（#962 第 4 项，同盲人端 `BlindOrderStatusView` 的 `statusHeaderFocused`）。
        // 状态句已经在播（`speakVolunteerStatusChange`），焦点不跟过来就是「听到了，但滑不到」。
        .onChange(of: order?.status) { status in
            guard status != nil else { return }
            headerFocused = true
        }
    }

    /// 出发起地图常驻（定稿第 1 条）。
    var usesMap: Bool {
        switch phase {
        case .departed, .arrived, .completed: return true
        case .confirmStillGoing, .agreedEarly, .agreedSoon, .runnerCancelled, .none: return false
        }
    }

    func openHelp() {
        switch presentation.helpMode {
        case .cloud: onCloudHelp()
        case .localCall: showsLocalHelp = true
        }
    }

    // MARK: 顶栏

    func topBar(surface: BlindOrderBarSurface) -> VolunteerOrderTopBar {
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
    var menuItems: [VolunteerOrderMenuItem] {
        guard let release = rows.first(where: { $0.action == .releaseOrder }) else { return [] }
        return [VolunteerOrderMenuItem(kind: .releaseOrder, title: release.value, isDestructive: true) {
            onRowAction(.releaseOrder)
        }]
    }

    // MARK: ①④⑨ 深色头 + 竖线

    var stageLayout: some View {
        BlindOrderStageScaffold(
            topBar: topBar(surface: .onDark),
            eyebrow: hero.eyebrow,
            title: headerTitle,
            // 过了建议出发时间：大字换金色（同 v2 头卡，稿 ④ 注解）。
            titleColor: hero.isGold ? AppColors.Flow.gold : BlindOrderV7Palette.headerTitle,
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
    var headerTitle: String {
        if let headline = hero.headline { return headline }
        return [hero.number, hero.unit].compactMap { $0 }.joined(separator: " ")
    }

    var stagePlace: String? {
        if phase == .runnerCancelled { return VolunteerOrderFlowCopy.runnerCancelledSubtitle }
        return placeRow?.value ?? order?.startAddress?.nilIfBlank
    }

    /// 地点下面那行：邀请态是距离 / 配速，其余是开跑时间。头部副文（建议出发时间、带绳提醒）进当前步那张卡。
    var stageWhen: String? {
        if !inviteMetrics.isEmpty {
            return inviteMetrics.map { [$0.value, $0.unit].compactMap { $0 }.joined(separator: " ") }.joined(separator: " · ")
        }
        return phase == .runnerCancelled ? nil : order?.blindRunnerShortStartText(now: Date())
    }

    var timelinePosition: BlindOrderTimelinePosition {
        switch phase {
        case .none: return .current(.matchVolunteer)
        case .confirmStillGoing, .agreedEarly, .agreedSoon: return .current(.awaitDeparture)
        // ⑨ 的竖线不经过这里：停在哪一步读状态变更记录（`VolunteerRunnerCancelledTimeline`，#962）。
        // 这一支只是让 switch 穷举，`timelineInput` 对 ⑨ 提前返回。
        case .runnerCancelled: return .stopped(.awaitDeparture)
        case .departed, .arrived: return .current(.meetUp)
        case .completed: return .allDone
        }
    }

    /// `nil` = 不画竖线（⑨ 拿不到状态变更记录时）。
    var timelineInput: BlindOrderTimelineInput? {
        if phase == .runnerCancelled { return VolunteerRunnerCancelledTimeline.input(logs: statusLogs) }
        var details: [BlindOrderTimelineStep: String] = [:]
        if case .current(let step) = timelinePosition {
            // 最后 10 秒不靠颜色提示：字里直接写「快到时间了」（v2 用金色 +「不用颜色区分」时的感叹号）。
            let reply = presentation.replyNotice.map { presentation.isReplyUrgent ? "快到时间了 · \($0)" : $0 }
            details[step] = reply ?? hero.presence
        }
        return BlindOrderTimelineInput(position: timelinePosition, details: details, vocabulary: .volunteer)
    }

    /// 当前步那张卡：深色块是头部副文（建议出发时间、带绳提醒），下半截是跑者一行。
    @ViewBuilder
    var currentCard: some View {
        let lines = hero.lines
        if phase == .runnerCancelled {
            EmptyView()
        } else if !lines.isEmpty {
            BlindOrderStepCard(lead: nil, body: lines.joined(separator: "\n")) {
                if let runnerLine { runnerLine }
            }
        } else if let runnerLine {
            // 没有副文时只剩跑者一行：不画空的深色块。
            VolunteerV7InfoBox { runnerLine }
        }
    }

    var runnerLine: BlindOrderPersonRow? {
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
    var stageFooter: some View {
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
    var stageBottom: some View {
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
                    // 「我已经出发了」是那一步唯一的主动作，同样实心藏青（#971，负责人 2026-11-12 批准）。
                    style: .solid,
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
