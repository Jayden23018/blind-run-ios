import SwiftUI

// MARK: - 陪跑员端订单页（邀请 / 约好 / 出发）

/// 设计交付文档 v3 §5 的前三态，与跑者端**同一个外壳**（`OrderFlowScaffold`）。
///
/// 一屏的内容全部来自 `VolunteerOrderFlowPresentation` —— 这个视图不判任何状态。
/// 判状态的地方只有那一个纯类型，而它能被用例穷举；散回视图里的 `if` 谁都验不了。
///
/// 两个数据源各有一个构造入口：
/// - 邀请：派单推送 `WSNewOrder`（那一刻志愿者拿不到订单详情，后端恒 403）；
/// - 约好 / 出发：`OrderDetailResponse`。
struct VolunteerOrderFlowPage<Footer: View>: View {
    let presentation: VolunteerOrderFlowPresentation
    /// 头像圆里那个字取自它。邀请态没有姓名（派单载荷不含），圆里是「跑」。
    let runnerName: String?
    let onRowAction: (VolunteerOrderFlowPresentation.Action) -> Void
    let onPrimaryAction: () -> Void
    /// 主按钮在转圈。
    var isPrimaryLoading: Bool = false
    /// 主按钮可不可按。
    ///
    /// 🔴 **必须接上，不能用默认值糊过去。** 旧的底部面板靠 `transitionsDisabled` 防止
    /// 同一次流转被提交两次（POST 回来了但确认那条 GET 还挂着的那几秒）；骨架第一版漏了它，
    /// 于是志愿者可以连点两下「我出发了」，第二下被后端拒绝、而屏幕上只多一行红字。
    /// 是 `testVolunteerServiceRemainsInteractiveWhenTransitionConfirmationNeverReturns`
    /// 编译不过才暴露出来的 —— 那条用例断的就是这一下。
    ///
    /// 走 `.disabled()` 而不是在 action 里 `guard return`：前者同时给无障碍元素打上
    /// 「不可用」，VoiceOver 会念「变暗」；静默 return 在读屏里仍是一个完全正常的按钮，
    /// 双击之后什么都不发生、什么都不念。
    var isPrimaryEnabled: Bool = true
    /// 信息卡之后那块**「刚才那一下的结果」**。
    ///
    /// 🔴 **不是可选装饰**：这一页唯一的**可见**失败面（接单失败、状态流转超时）挂在这里。
    /// 少了它，失败只剩一句 TTS —— 不开读屏的低视力志愿者屏幕上零变化
    /// （记忆 `claimed-fallback-may-not-exist-in-release`）。
    @ViewBuilder let footer: () -> Footer

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        OrderFlowScaffold(bottom: bottomActions) {
            statusCard
            infoCard
            footer()
        }
    }

    private var bottomActions: OrderFlowBottomActions {
        OrderFlowBottomActions(
            owner: .volunteer,
            primary: presentation.primaryAction.map { action in
                OrderFlowPrimaryAction(
                    title: action.title,
                    systemImage: action.systemImage,
                    isLoading: isPrimaryLoading,
                    isEnabled: isPrimaryEnabled,
                    accessibilityHint: primaryActionHint(action),
                    action: onPrimaryAction
                )
            },
            // 前三态一律不给 —— 理由写在 `VolunteerOrderFlowPresentation.showsSafetyHub` 上。
            // 这里仍按值分流而不是写死 `nil`：汇合那一态搬过来时判据已经在位。
            safetyHub: presentation.showsSafetyHub ? OrderFlowSafetyHubAction(action: {}) : nil
        )
    }

    private func primaryActionHint(_ action: VolunteerOrderFlowPresentation.PrimaryAction) -> String? {
        switch action {
        case .acceptInvite:
            // 🚩 **不解释「先聊聊还是直接接」**：两种 `OrderRespondAction` 下这枚按钮
            // 做的是同一件事（把这一单接下来），差别是后端的机制。
            // 而 `requiresIntroCall == false` 的三种成因客户端分不出来，写任何一种都可能是错的。
            return "接下这一单并通知跑者"
        case .confirmDeparture:
            return "告诉跑者你仍然会来。不确认这一单会转给其他志愿者"
        case .enRoute:
            return "点击后通知跑者你正在前往"
        case .arrived:
            return "点击后通知跑者你已到达集合点"
        }
    }

    // MARK: 状态卡

    private var statusCard: some View {
        FlowCard {
            VStack(spacing: 0) {
                FlowStepper(
                    currentStep: presentation.step.rawValue,
                    titles: VolunteerOrderFlowStep.allTitles
                )
                FlowSeparator()
                heroSection
                // 倒计时是状态卡里的**独立无障碍元素**，不并进上面那个合成元素 ——
                // 它每秒都变，合进去会让读屏每秒把整条状态重念一遍。
                replyNoticeView
            }
        }
    }

    private var heroSection: some View {
        VStack(spacing: 0) {
            visualArea
            Text(presentation.title)
                .flowFont(FlowFonts.statusTitle(), monospacedDigit: true)
                .foregroundColor(AppColors.Flow.primaryText)
                .multilineTextAlignment(.center)
                // 34pt 在 AX5 下会长到一百多 pt，必须允许换行。
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, FlowMetrics.statusTitleTopSpacing)

            if !presentation.subtitle.isEmpty {
                Text(presentation.subtitle)
                    .flowFont(FlowFonts.statusSubtitle())
                    .foregroundColor(AppColors.Flow.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, presentation.replyNotice == nil ? 16 : 10)
        .frame(maxWidth: .infinity)
        // 标题 + 副标题合成**一个**元素，这一页最重要的那个。
        // 回复倒计时**不在里面**（见下）—— 它每秒都变，合进来会让读屏每秒重念一遍状态。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusAccessibilityLabel)
        .accessibilityIdentifier("volunteerOrderFlowStatusCard")
    }

    private var statusAccessibilityLabel: String {
        [presentation.title, presentation.subtitle]
            .filter { !$0.isEmpty }
            .joined(separator: "。")
    }

    /// 「还剩 25 秒回复」。
    ///
    /// 进入最后 10 秒此前**只有颜色变化**（蓝 → 红）。红绿色觉障碍看不出这个转折，
    /// 而这个转折决定的是「还要不要再想想」—— 超时算没回应，这一单会转给下一个人。
    /// 开启「不使用颜色区分」时补一个感叹号：形状差异不依赖色觉。
    @ViewBuilder
    private var replyNoticeView: some View {
        if let notice = presentation.replyNotice {
            HStack(spacing: 6) {
                if differentiateWithoutColor && presentation.isReplyUrgent {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .accessibilityHidden(true)
                }
                Text(notice)
                    .flowFont(FlowFonts.rowValueEmphasized(), monospacedDigit: true)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundColor(presentation.isReplyUrgent ? AppColors.destructive : AppColors.Flow.accent)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 16)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("volunteerOrderFlowReplyCountdown")
        }
    }

    // MARK: 视觉区（纯装饰，对读屏隐藏）

    private var visualArea: some View {
        ZStack {
            avatar
            if presentation.visual == .avatarWithProgressRing {
                progressRing
            }
        }
        .frame(width: FlowMetrics.visualSide, height: FlowMetrics.visualSide)
        // 状态信息在标题与副标题里有完整文字版，这里是装饰。
        .accessibilityHidden(true)
    }

    private var avatar: some View {
        FlowAvatar(
            name: runnerName,
            diameter: FlowMetrics.avatarDiameter,
            background: AppColors.Flow.avatarBackground,
            foreground: AppColors.Flow.avatarInitial,
            placeholder: "跑"
        )
    }

    /// ⚠️ **进度值是固定的 0.35，不是算出来的。** 没有 ETA 也没有「总距离」这个基准，
    /// 任何「按距离算百分比」都要先编一个起始距离。画成固定一段是诚实的：
    /// 它表达「在路上」，不表达「走了多少」。同跑者端。
    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(AppColors.Flow.radarOuterStroke, lineWidth: FlowMetrics.progressRingWidth)
            Circle()
                .trim(from: 0, to: 0.35)
                .stroke(
                    AppColors.Flow.accent,
                    style: StrokeStyle(lineWidth: FlowMetrics.progressRingWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }

    // MARK: 信息卡

    private var infoCard: some View {
        FlowCard {
            VStack(spacing: 0) {
                ForEach(Array(presentation.rows.enumerated()), id: \.element.id) { index, row in
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
}

// MARK: - Previews

#if DEBUG
#Preview("陪跑员订单页 · 邀请") {
    VolunteerOrderFlowPreview(kind: .invite(remainingSeconds: 25))
}

#Preview("陪跑员订单页 · 邀请 · 快到期") {
    VolunteerOrderFlowPreview(kind: .invite(remainingSeconds: 6))
}

#Preview("陪跑员订单页 · 约好（跨天预约）") {
    VolunteerOrderFlowPreview(kind: .order(.scheduledConfirmed))
}

#Preview("陪跑员订单页 · 约好（待出发）") {
    VolunteerOrderFlowPreview(kind: .order(.pendingAccept))
}

#Preview("陪跑员订单页 · 出发") {
    VolunteerOrderFlowPreview(kind: .order(.driverEnRoute), distanceText: "距出发地点约 600 米")
}

#Preview("陪跑员订单页 · 约好 · AX5") {
    VolunteerOrderFlowPreview(kind: .order(.pendingAccept))
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("陪跑员订单页 · 出发 · 深色") {
    VolunteerOrderFlowPreview(kind: .order(.driverEnRoute), distanceText: "距出发地点约 600 米")
        .preferredColorScheme(.dark)
}

/// Preview 共用的装配。抽成具名类型而不是抄七遍 —— 抄七遍改一处会漏六处，
/// 而 Preview 的漂移没有任何东西会报警。
private struct VolunteerOrderFlowPreview: View {
    enum Kind {
        case invite(remainingSeconds: Int)
        case order(RunOrderStatus)
    }

    let kind: Kind
    var distanceText: String?

    var body: some View {
        switch kind {
        case .invite(let seconds):
            VolunteerOrderFlowPage(
                presentation: .make(dispatch: OrderDetailResponse.previewDispatch(), remainingSeconds: seconds),
                runnerName: nil,
                onRowAction: { _ in },
                onPrimaryAction: {},
                footer: { EmptyView() }
            )
        case .order(let status):
            let order = OrderDetailResponse.preview(status: status, blindName: "李*")
            if let presentation = VolunteerOrderFlowPresentation.make(order: order, distanceText: distanceText) {
                VolunteerOrderFlowPage(
                    presentation: presentation,
                    runnerName: order.blindName,
                    onRowAction: { _ in },
                    onPrimaryAction: {},
                    footer: { EmptyView() }
                )
            } else {
                Text("这一态不走前三格：\(status.rawValue)")
            }
        }
    }
}
#endif
