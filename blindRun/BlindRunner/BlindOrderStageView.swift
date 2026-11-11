import SwiftUI

// MARK: - 订单页 v7 ①–④ 的外壳（#917）

/// 深色头 + 白底抽屉（地点、时间、五步竖线）+ 贴底按钮区。①④ 与 ②③ 共用这一个外壳，只换内容。
///
/// 读屏顺序 = 视觉顺序：顶栏（返回 → 喇叭 → ··· → 求助）→ 头部（一个合成元素）→ 地点与时间 → 竖线 → 结果面 → 底部按钮。
/// 头部是状态变化时焦点落点（`headerFocused`），沿用改版前状态卡的 identifier `blindOrderFlowStatusCard`。
struct BlindOrderStageScaffold<Card: View, Footer: View, Bottom: View>: View {
    let topBar: BlindOrderTopBar
    let eyebrow: String
    let title: String
    let headerAccessibilityLabel: String
    var headerFocused: AccessibilityFocusState<Bool>.Binding
    var headerIdentifier: BlindOrderStageHeaderIdentifier = .statusCard
    let place: String?
    let when: String?
    let timeline: BlindOrderTimelineInput
    @ViewBuilder let card: () -> Card
    /// 竖线下面那块：刚才那一下的结果（错误、分享提示）、举报 / 不再匹配、调试按钮。正常时大多为空。
    @ViewBuilder let footer: () -> Footer
    @ViewBuilder let bottom: () -> Bottom

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .background(BlindOrderV7Palette.headerTop.ignoresSafeArea(edges: .top))
            ScrollView {
                VStack(spacing: 0) {
                    header
                    sheet
                }
            }
            .background(AppColors.Flow.surface)
            bottomPanel
        }
        .background(AppColors.Flow.surface.ignoresSafeArea())
        // 系统导航栏藏掉之后，读屏「两指 Z」不再自动返回；接到顶栏同一个返回动作上。
        .accessibilityAction(.escape) { topBar.onBack() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .flowFont(FlowV2Fonts.callout())
                .foregroundColor(BlindOrderV7Palette.headerEyebrow)
            Text(title)
                .flowFont((30, .bold, .title))
                .foregroundColor(BlindOrderV7Palette.headerTitle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 8)
        // 抽屉的圆角压在头部下沿上（稿里抽屉往上叠 20pt）。
        .padding(.bottom, 20 + BlindOrderStageMetrics.sheetOverlap)
        .background(BlindOrderV7Palette.headerGradient)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(headerAccessibilityLabel)
        .accessibilityAddTraits(.isHeader)
        .accessibilityFocused(headerFocused)
        .modifier(headerIdentifier)
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            if place != nil || when != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if let place {
                        Text(place)
                            .flowFont((20, .bold, .title3))
                            .foregroundColor(AppColors.Flow.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let when {
                        Text(when)
                            .flowFont(FlowV2Fonts.callout())
                            .foregroundColor(AppColors.Flow.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("blindOrderStagePlace")
                .padding(.bottom, 20)
            }
            BlindOrderTimelineView(input: timeline) { _ in card() }
            footer()
                .padding(.top, 8)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: BlindOrderStageMetrics.sheetRadius, style: .continuous)
                .fill(AppColors.Flow.surface)
                // 只要上面两个圆角：下沿往下多铺一截，盖住下面两个圆角。
                .padding(.bottom, -BlindOrderStageMetrics.sheetRadius)
        )
        .padding(.top, -BlindOrderStageMetrics.sheetOverlap)
        .readableContentColumn()
    }

    private var bottomPanel: some View {
        VStack(spacing: 0) {
            bottom()
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .background(AppColors.Flow.surface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppColors.Flow.separator)
                .frame(height: 1)
                .accessibilityHidden(true)
        }
        // 底栏自己的 identifier：无障碍审计据它的上沿放过「滚到栏后面」的元素（同 `blindOrderFlowBottomBar`）。
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blindOrderFlowBottomBar")
    }
}

/// 头部的 identifier。①④ 沿用改版前状态卡的那个，②③ 沿用通话页标题的两个 ——
/// 守着它们的 UI 用例不用换判据。字面量分支的理由同 `OrderFlowBottomActions.Owner`。
enum BlindOrderStageHeaderIdentifier: ViewModifier {
    case statusCard
    case introCallTitle
    case introCallPlanTitle

    func body(content: Content) -> some View {
        switch self {
        case .statusCard: content.accessibilityIdentifier("blindOrderFlowStatusCard")
        case .introCallTitle: content.accessibilityIdentifier("blindIntroCallTitle")
        case .introCallPlanTitle: content.accessibilityIdentifier("blindIntroCallPlanTitle")
        }
    }
}

enum BlindOrderStageMetrics {
    static let sheetRadius: CGFloat = 22
    static let sheetOverlap: CGFloat = 20
}

// MARK: - 当前步那张卡

/// 当前步下面那张卡：上半截深色块（一行小字 + 一行大字），下半截可选的一行（陪跑员 / 候选人）。稿 ①②④ 同一个样子。
///
/// `lead == nil` 时只有一段字（② 用现有副标题原文，句子长，改用 17pt）。
struct BlindOrderStepCard<Lower: View>: View {
    let lead: String?
    let body_: String
    @ViewBuilder let lower: () -> Lower

    init(lead: String?, body: String, @ViewBuilder lower: @escaping () -> Lower) {
        self.lead = lead
        self.body_ = body
        self.lower = lower
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                if let lead {
                    Text(lead)
                        .flowFont(FlowV2Fonts.subhead())
                        .foregroundColor(BlindOrderV7Palette.headerEyebrow)
                }
                Text(body_)
                    .flowFont(lead == nil ? (17, .semibold, .body) : (20, .bold, .title3))
                    .foregroundColor(.white)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(BlindOrderV7Palette.cardDark)
            .accessibilityElement(children: .combine)
            lower()
        }
        .background(AppColors.Flow.surfaceSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

extension BlindOrderStepCard where Lower == EmptyView {
    init(lead: String?, body: String) {
        self.init(lead: lead, body: body) { EmptyView() }
    }
}

/// 卡片下半截那一行：头像 + 小字标签 + 姓名行。合成一个读屏元素，念 `spoken`（去星号）。
struct BlindOrderPersonRow: View {
    let initial: String
    let label: String
    let line: String
    let spoken: String

    var body: some View {
        HStack(spacing: 14) {
            Text(initial)
                .flowFont((20, .bold, .title3))
                .foregroundColor(AppColors.Flow.onBlueTint)
                .frame(width: 48, height: 48)
                .background(Circle().fill(AppColors.Flow.blueTint))
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .flowFont(FlowV2Fonts.tag())
                    .foregroundColor(AppColors.Flow.secondaryText)
                Text(line)
                    .flowFont((18, .bold, .headline))
                    .foregroundColor(AppColors.Flow.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}

// MARK: - 底部按钮

/// 底部一枚按钮。外形沿用 #749 定稿（胶囊 52pt 可见、整行 64pt 可点，`capsuleButtonChrome`）；
/// 实心用深蓝 `AppColors.Flow.navy`（v7 稿「底部一个深色主按钮」，白字约 14:1），描边用 `NeutralButtonStyle`。
/// 一屏只有一枚实心（负责人「按钮要克制」）。
struct BlindOrderStageButton: View {
    enum Style { case solid, outline }

    let title: String
    var systemImage: String?
    let style: Style
    var isEnabled = true
    var accessibilityHint: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).accessibilityHidden(true)
                }
                Text(title)
            }
        }
        .modifier(StageButtonStyle(style: style))
        .disabled(!isEnabled)
        .accessibilityHintIfPresent(accessibilityHint)
    }

    private struct StageButtonStyle: ViewModifier {
        let style: Style

        func body(content: Content) -> some View {
            switch style {
            case .solid: content.buttonStyle(NavySolidButtonStyle())
            case .outline: content.buttonStyle(NeutralButtonStyle())
            }
        }
    }
}

/// v7 底部实心按钮：深蓝底白字，不可用时同 `PrimaryButtonStyle` 的灰底。
private struct NavySolidButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let ink = isEnabled ? Color.white : AppColors.textSecondary
        configuration.label
            .font(AppFonts.primaryButton())
            .foregroundColor(ink)
            .multilineTextAlignment(.center)
            .capsuleButtonChrome(fill: fill(isPressed: configuration.isPressed))
    }

    private func fill(isPressed: Bool) -> Color {
        guard isEnabled else { return AppColors.ButtonPalette.disabledFill }
        return isPressed ? AppColors.Flow.navy.opacity(0.85) : AppColors.Flow.navy
    }
}
