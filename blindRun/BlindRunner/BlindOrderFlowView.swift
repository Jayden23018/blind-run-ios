import SwiftUI

// MARK: - 订单页四态的共用骨架

/// 匹配 / 约好 / 出发 / 汇合共用的**同一个**骨架：进度条 → 视觉区 → 状态标题副标题
/// → 信息列表 → 底部两个按钮。
///
/// **四个状态下每一块的位置都不变**，只换内容。这是设计稿最核心的一条：视障用户靠位置
/// 记忆操作，而改版前每个状态是独立页面 —— iOS 切页时 VoiceOver 会把焦点移回第一个元素，
/// 读屏用户每次都要从头找。单页原地更新让焦点保持不动，只播报变化。
///
/// 本轮（阶段 3）只做**静态布局**，不含过渡动画（阶段 4）。所以这里没有任何
/// `withAnimation` / `.transition` —— 守卫 `motion-not-gated` 要求位移类动效先判
/// 「减弱动态效果」，那一并在阶段 4 做。
struct BlindOrderFlowView: View {
    let presentation: BlindOrderFlowPresentation
    let order: OrderDetailResponse
    /// 集合地点那一行点下去做什么。`nil` = 不可点（拿不到地点时）。
    let onOpenStartPlace: (() -> Void)?
    let onLastRowTapped: () -> Void
    let onPrimaryAction: () -> Void
    let onOpenSafetyHub: () -> Void

    /// 「减弱动态效果」。阶段 3 只有雷达那圈弧线在转，所以现在只用它判这一处；
    /// 阶段 4 接过渡动画时这个环境值会被更多地方读到。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    statusCard
                    infoCard
                }
                .padding(.horizontal, FlowMetrics.pageHorizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .readableContentColumn()
            }
            bottomActions
        }
        .background(AppColors.Flow.page)
    }

    // MARK: - 状态卡

    private var statusCard: some View {
        FlowCard {
            VStack(spacing: 0) {
                FlowStepper(
                    currentStep: presentation.step.rawValue,
                    titles: BlindOrderFlowStep.allTitles
                )
                FlowSeparator()
                heroSection
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
                // 34pt 在 AX5 下会长到一百多 pt，必须允许换行 ——
                // `lineLimit(1)` 在这里等于把这一屏最重要的一行裁掉。
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, FlowMetrics.statusTitleTopSpacing)

            Text(presentation.subtitle)
                .flowFont(FlowFonts.statusSubtitle())
                .foregroundColor(AppColors.Flow.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            // 只在异常时出现。正常状态**不显示任何「定位正常」之类的反向提示** ——
            // 那种提示对读屏用户是每次进页面都要滑过去的一条无信息内容。
            if let warning = presentation.warning {
                Text(warning)
                    .flowFont(FlowFonts.rowDetail())
                    .foregroundColor(AppColors.destructive)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        // 🔴 标题 + 副标题（+ 警示）合成**一个**元素，而且是这一页最重要的那个。
        // 拆开的后果是读屏用户要滑两三次才听全「现在是什么情况」。
        // 视觉区在里面，但它 `accessibilityHidden`，不参与合成。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusAccessibilityLabel)
        .accessibilityIdentifier("blindOrderFlowStatusCard")
    }

    private var statusAccessibilityLabel: String {
        var parts = [presentation.title, presentation.subtitle]
        if let warning = presentation.warning { parts.append(warning) }
        return parts.joined(separator: "。")
    }

    // MARK: - 视觉区（纯装饰，对读屏隐藏）

    /// 124×124 的方形区域。四态换内容但**尺寸不变** —— 骨架固定这条就落在这里：
    /// 下面的标题不会因为上面换了一种图形而上下跳。
    private var visualArea: some View {
        ZStack {
            switch presentation.visual {
            case .radar:
                radar
            case .avatar:
                avatar
            case .avatarWithProgressRing:
                avatar
                progressRing
            case .avatarWithSuccessBadge:
                avatar
                successBadge
            }
        }
        .frame(width: FlowMetrics.visualSide, height: FlowMetrics.visualSide)
        // 整块纯装饰：状态信息在标题与副标题里有完整文字版。
        // 装饰内容的标准处理就是对辅助技术隐藏 —— 读屏用户 0 次多余划动就够到状态。
        .accessibilityHidden(true)
    }

    private var radar: some View {
        ZStack {
            Circle()
                .fill(AppColors.Flow.radarOuter)
                .overlay(Circle().strokeBorder(AppColors.Flow.radarOuterStroke, lineWidth: 1.5))
            Circle()
                .fill(AppColors.Flow.radarInner)
                .overlay(Circle().strokeBorder(AppColors.Flow.radarInnerStroke, lineWidth: 1.5))
                .frame(width: 84, height: 84)
            Circle()
                .fill(AppColors.Flow.accent)
                .frame(width: 52, height: 52)
            Image(systemName: "figure.run")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
            // 旋转的那圈弧线在阶段 4 接（连同「减弱动态效果」的降级）。
            // 现在画成静态的一段弧：**不留空** —— 空着的话匹配态的视觉区只有三个同心圆，
            // 与「正在找人」这件事没有任何视觉关联。
            Circle()
                .trim(from: 0, to: 0.17)
                .stroke(AppColors.Flow.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }

    private var avatar: some View {
        FlowAvatar(
            name: order.volunteerName,
            diameter: FlowMetrics.avatarDiameter,
            background: AppColors.Flow.avatarBackground,
            foreground: AppColors.Flow.avatarInitial
        )
    }

    /// 出发态头像外圈那道进度环。
    ///
    /// ⚠️ **进度值是固定的 0.35，不是算出来的。** 没有 ETA 也没有「总距离」这个基准
    /// （后端契约里都没有），任何「按距离算百分比」都要先编一个起始距离。
    /// 画成固定一段是诚实的：它表达「在路上」，不表达「走了多少」。
    /// 阶段 4 接动画时也只做「出现时扫出来」，不做「按进度增长」。
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

    private var successBadge: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 17, weight: .heavy))
            .foregroundColor(.white)
            .frame(width: FlowMetrics.successBadgeDiameter, height: FlowMetrics.successBadgeDiameter)
            .background(AppColors.Flow.successBadge, in: Circle())
            .overlay(
                Circle().strokeBorder(AppColors.Flow.surface, lineWidth: FlowMetrics.successBadgeRingWidth)
            )
            .frame(
                width: FlowMetrics.visualSide,
                height: FlowMetrics.visualSide,
                alignment: .bottomTrailing
            )
            .offset(x: -8, y: -8)
    }

    // MARK: - 信息列表

    private var infoCard: some View {
        FlowCard {
            VStack(spacing: 0) {
                volunteerRow
                FlowSeparator()
                timeRow
                FlowSeparator()
                placeRow
                FlowSeparator()
                lastRow
            }
        }
    }

    /// 陪跑员行：姓名 + 经验，两行值合成一句读屏文本。
    ///
    /// 姓名**视觉上保留掩码**（`张*`）、**朗读去掉星号** —— 后端的姓名始终带掩码，
    /// 原样交给 VoiceOver 会念成「张星号」，而这个 App 的读屏是外放的。
    private var volunteerRow: some View {
        FlowInfoRow(
            label: "陪跑员",
            accessibilityLabel: volunteerAccessibilityLabel,
            minHeight: FlowMetrics.volunteerRowMinHeight
        ) {
            VStack(alignment: .trailing, spacing: 3) {
                Text(volunteerDisplayName)
                    .flowFont(FlowFonts.rowValueEmphasized())
                    .foregroundColor(AppColors.Flow.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.trailing)
                if let experience = order.volunteerExperienceText {
                    Text(experience)
                        .flowFont(FlowFonts.rowDetail(), monospacedDigit: true)
                        .foregroundColor(AppColors.Flow.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !hasVolunteer {
                    Text("匹配成功后显示陪跑经验")
                        .flowFont(FlowFonts.rowDetail())
                        .foregroundColor(AppColors.Flow.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var hasVolunteer: Bool { order.volunteerName?.nilIfBlank != nil }

    private var volunteerDisplayName: String {
        guard hasVolunteer else { return "正在匹配" }
        return order.volunteerName ?? ""
    }

    /// ⚠️ 设计稿这里是「张伟，已认证」。**「已认证」不显示** ——
    /// 订单详情里没有这个字段（契约里 0 命中）。无字段却印「已认证」是伪造信任标识，
    /// 而这恰恰是盲人决定要不要把自己交给一个陌生人时唯一能依据的东西。
    /// 已投 handoff 请后端补。
    private var volunteerAccessibilityLabel: String {
        guard hasVolunteer else { return "陪跑员，正在匹配，匹配成功后显示陪跑经验" }
        var label = "陪跑员\(order.volunteerNameForSpeech)"
        if let experience = order.volunteerExperienceText { label += "，\(experience)" }
        return label
    }

    private var timeRow: some View {
        FlowInfoRow(label: "时间", accessibilityLabel: timeAccessibilityLabel) {
            Text(order.blindRunnerShortStartText() ?? "待确认")
                .flowFont(FlowFonts.rowValue(), monospacedDigit: true)
                .foregroundColor(AppColors.Flow.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 读屏念完整日期而不是屏幕上那个「明天 7:00」：听的人没有屏幕可以回看，
    /// 含糊的相对日期反而要他自己换算。
    private var timeAccessibilityLabel: String {
        "时间，\(order.plannedStartForAnnouncement ?? order.blindRunnerShortStartText() ?? "待确认")"
    }

    private var placeRow: some View {
        FlowInfoRow(
            label: "集合地点",
            kind: onOpenStartPlace.map { .navigable(action: $0) } ?? .display,
            accessibilityLabel: "集合地点，\(placeText)",
            accessibilityHint: onOpenStartPlace == nil ? nil : "双击查看集合地点在地图上的位置"
        ) {
            Text(placeText)
                .flowFont(FlowFonts.rowValue())
                .foregroundColor(AppColors.Flow.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.trailing)
        }
    }

    private var placeText: String {
        order.startAddress?.nilIfBlank ?? "出发地点待确认"
    }

    /// 最后一行：这一态的破坏性/求助入口。**固定位置、点击后二次确认。**
    ///
    /// 文案随状态变（取消匹配 / 取消预约 / 遇到问题），判据在
    /// `BlindOrderFlowPresentation.lastRowTitle`。
    private var lastRow: some View {
        FlowInfoRow(
            label: nil,
            kind: .navigable(action: onLastRowTapped),
            accessibilityLabel: presentation.lastRowTitle,
            accessibilityHint: "双击后会先确认一次"
        ) {
            Text(presentation.lastRowTitle)
                .flowFont(FlowFonts.rowValue())
                .foregroundColor(AppColors.Flow.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("blindOrderFlowLastRowButton")
    }

    // MARK: - 底部操作区

    /// 主按钮（可能为空）+ 固定的「求助与安全」。
    ///
    /// 设计意图第 3 条：旧版把打电话、修改取消、求助三个按钮并排，重点不清。
    /// 这里只有两个版位，且第二个的文案与位置**永不变化** —— 视障用户靠位置记忆操作。
    private var bottomActions: some View {
        VStack(spacing: FlowMetrics.actionButtonSpacing) {
            if let action = presentation.primaryAction {
                FlowActionButton(
                    action.title,
                    systemImage: action.systemImage,
                    style: .primary,
                    accessibilityHint: primaryActionHint(action),
                    action: onPrimaryAction
                )
                .accessibilityIdentifier("blindOrderFlowPrimaryButton")
            }

            FlowActionButton(
                EmergencySafetyCopy.hubTitle,
                systemImage: "shield",
                style: .help,
                accessibilityLabel: EmergencySafetyCopy.hubAccessibilityLabel,
                accessibilityHint: EmergencySafetyCopy.hubAccessibilityHint,
                action: onOpenSafetyHub
            )
            .accessibilityIdentifier("blindOrderFlowSafetyHubButton")
        }
        .padding(.horizontal, FlowMetrics.pageHorizontalPadding)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .readableContentColumn()
        // 恒实色，不用材质。理由与订单页那条旧底栏同源（`docs/05-page-specs.md`）：
        // 这一条压着滚动内容，材质会让正文从按钮底下透上来，成了文字叠文字 ——
        // 而那正好打掉低视力用户唯一的通道，且对比度审计查不出来
        // （它查静态配色，不查两层内容叠在一起）。
        .background(AppColors.Flow.surface)
        .overlay(alignment: .top) {
            // 底栏与内容之间唯一的边界。**不调透明度** —— 25% 下只有约 1.4:1，
            // 够不到 WCAG 1.4.11 对控件边界要求的 3:1。
            Rectangle()
                .fill(AppColors.Flow.separator)
                .frame(height: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func primaryActionHint(_ action: BlindOrderFlowPresentation.PrimaryAction) -> String {
        switch action {
        case .callVolunteer:
            // 刻意**不念号码**：VoiceOver 每次焦点落到按钮上就把 11 位号码整个念出来，
            // 而视障跑者在户外常常不戴耳机（要听车流）—— 外放等于把陪跑员的号码
            // 广播给周围所有人。号码对「要不要打这通电话」没有任何帮助。
            return "系统会先弹出拨号确认，确认后才会拨出"
        case .openIntroCall:
            return IntroCallCopy.blindEntryAccessibilityHint
        case .keepWaiting:
            return KeepWaitingCopy.accessibilityHint
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("订单页 · 匹配中") {
    BlindOrderFlowPreview(status: .pendingMatch, volunteerName: nil)
}

#Preview("订单页 · 已约好") {
    BlindOrderFlowPreview(status: .scheduledConfirmed)
}

#Preview("订单页 · 出发中") {
    BlindOrderFlowPreview(status: .driverEnRoute, distanceText: "距出发地点约 600 米")
}

#Preview("订单页 · 已汇合") {
    BlindOrderFlowPreview(status: .driverArrived)
}

#Preview("订单页 · 已约好 · AX5") {
    BlindOrderFlowPreview(status: .scheduledConfirmed)
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("订单页 · 出发中 · 深色") {
    BlindOrderFlowPreview(status: .driverEnRoute, distanceText: "距出发地点约 600 米")
        .preferredColorScheme(.dark)
}

/// 六个 Preview 共用的装配。抽成具名类型而不是抄六遍 —— 抄六遍改一处会漏五处，
/// 而 Preview 的漂移没有任何东西会报警。
private struct BlindOrderFlowPreview: View {
    let status: RunOrderStatus
    var volunteerName: String? = "张*"
    var distanceText: String?

    var body: some View {
        let order = OrderDetailResponse.preview(
            status: status,
            volunteerName: volunteerName,
            volunteerTotalCompleted: volunteerName == nil ? nil : 32,
            volunteerPhone: volunteerName == nil ? nil : "13800000001"
        )
        if let presentation = BlindOrderFlowPresentation.make(
            order: order,
            distanceText: distanceText,
            canKeepWaiting: false
        ) {
            BlindOrderFlowView(
                presentation: presentation,
                order: order,
                onOpenStartPlace: {},
                onLastRowTapped: {},
                onPrimaryAction: {},
                onOpenSafetyHub: {}
            )
        } else {
            Text("这一态不走四步骨架：\(status.rawValue)")
        }
    }
}
#endif
