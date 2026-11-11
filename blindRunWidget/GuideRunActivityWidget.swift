import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// MARK: - 陪跑员实时活动 V1–V6（#920，稿 `docs/ui/mockups/live-activity-v7-20261111/` 第四节）
//
// 每一块的内容由 `GuideRunActivityPresentation` 算好，这里只管画。
// 版式照 Uber：标志行 / 大标题 + 一句副标题 + 右侧圆头像或一个按钮 / 底部一根进度线。
// 按钮只在 iOS 17+ 出现（`Button(intent:)`），16.x 上那一格画人像。

@available(iOS 16.2, *)
struct GuideRunActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GuideRunAttributes.self) { context in
            let presentation = GuideRunActivityPresentation(
                attributes: context.attributes, state: context.state, isStale: context.isStale
            )
            GuideRunLockScreenView(attributes: context.attributes, presentation: presentation)
                .activityBackgroundTint(GuideRunCardPalette.color(presentation.background))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let presentation = GuideRunActivityPresentation(
                attributes: context.attributes, state: context.state, isStale: context.isStale
            )
            return DynamicIsland {
                // 展开态 = 锁屏卡去掉按钮（稿第三节）。
                DynamicIslandExpandedRegion(.bottom) {
                    GuideRunCardContent(attributes: context.attributes, presentation: presentation, showsButton: false)
                }
            } compactLeading: {
                GuideRunAvatar(diameter: GuideRunActivityMetrics.compactAvatar)
                    .accessibilityHidden(true)
            } compactTrailing: {
                GuideRunCompactTrailing(presentation: presentation)
            } minimal: {
                GuideRunAvatar(diameter: GuideRunActivityMetrics.compactAvatar)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(presentation.compactAccessibilityLabel)
            }
        }
    }
}

/// 尺寸照稿 `draft.html` 的 CSS（Uber 量出来的比例：组间距 8 / 10、标准卡约 145pt）。
/// 每张卡 ≤160pt 由 `LiveActivityCardHeightTests` 在真机上钉住。
enum GuideRunActivityMetrics {
    static let topPadding: CGFloat = 15
    static let bottomPadding: CGFloat = 14
    static let horizontalPadding: CGFloat = 18
    static let brandHeight: CGFloat = 18
    static let brandToMain: CGFloat = 8
    static let mainToLine: CGFloat = 10
    static let titleSize: CGFloat = 22
    static let largeTitleSize: CGFloat = 26
    static let subtitleSize: CGFloat = 16
    static let avatar: CGFloat = 46
    static let compactAvatar: CGFloat = 22
    /// 稿 `.btn`：44pt 高、22pt 圆角的胶囊。
    static let buttonHeight: CGFloat = 44
    /// 共用进度线（#919）「看步骤」的高度：线 + 节点下两字。
    static let progressLineHeight: CGFloat = 30
}

@available(iOS 16.2, *)
struct GuideRunLockScreenView: View {
    let attributes: GuideRunAttributes
    let presentation: GuideRunActivityPresentation

    var body: some View {
        GuideRunCardContent(attributes: attributes, presentation: presentation, showsButton: true)
            .padding(.top, GuideRunActivityMetrics.topPadding)
            .padding(.bottom, GuideRunActivityMetrics.bottomPadding)
            .padding(.horizontal, GuideRunActivityMetrics.horizontalPadding)
    }
}

/// 锁屏卡与灵动岛展开态共用的三层。文字（含标志与进度线的读法）合成一站念完；按钮单独一站。
@available(iOS 16.2, *)
private struct GuideRunCardContent: View {
    let attributes: GuideRunAttributes
    let presentation: GuideRunActivityPresentation
    let showsButton: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "figure.run")
                    .font(.system(size: 13, weight: .bold))
                Text(GuideRunActivityCopy.brand)
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(height: GuideRunActivityMetrics.brandHeight)
            // 标志与进度线都已念进 `texts` 那一站。
            .accessibilityHidden(true)

            HStack(spacing: 14) {
                texts
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(presentation.accessibilityLabel)
                if hasButton {
                    button
                } else if presentation.trailing != .none {
                    GuideRunAvatar(diameter: GuideRunActivityMetrics.avatar)
                        .accessibilityHidden(true)
                }
            }
            .padding(.top, GuideRunActivityMetrics.brandToMain)

            if let step = presentation.step {
                GuideRunStepsPlaceholder(current: step)
                    .padding(.top, GuideRunActivityMetrics.mainToLine)
            }
        }
        .foregroundStyle(.white)
    }

    private var hasButton: Bool {
        guard showsButton, !presentation.actions.isEmpty else { return false }
        if #available(iOS 17.0, *) { return true }
        return false
    }

    /// 「我快到了」「让他手机响」两种字数下都放得下的宽度（16pt 粗体 5 个字 + 左右 16）。
    private var buttonWidth: CGFloat { 116 }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(presentation.title)
                .font(.system(
                    size: presentation.titleIsLarge ? GuideRunActivityMetrics.largeTitleSize : GuideRunActivityMetrics.titleSize,
                    weight: .bold
                ))
                .monospacedDigit()
                .foregroundStyle(presentation.titleIsWarning ? GuideRunCardPalette.color(GuideRunCardPalette.gold) : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            subtitle
                .font(.system(size: GuideRunActivityMetrics.subtitleSize))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(GuideRunCardPalette.subtitleOpacity))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var subtitle: some View {
        if let prefix = presentation.subtitle, let deadline = presentation.subtitleCountdownTo, deadline > Date() {
            // 系统自走倒计时：App 不在前台时也会一秒一秒走（稿 B3 / V1 的「还剩」）。
            Text(prefix) + Text(timerInterval: Date()...deadline, countsDown: true)
        } else if let text = presentation.subtitle {
            Text(text)
        }
    }

    @ViewBuilder
    private var button: some View {
        if #available(iOS 17.0, *), hasButton, let action = presentation.actions.first {
            Button(intent: GuideRunActivityIntent(orderID: attributes.orderID, action: action)) {
                Text(action.title)
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 16)
                    .frame(width: buttonWidth, height: GuideRunActivityMetrics.buttonHeight)
                    .background(Capsule().fill(.white.opacity(GuideRunCardPalette.buttonFillOpacity)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .accessibilityLabel(action.title)
        }
    }
}

/// TODO(#919): 换成 `LiveActivityProgressLine(mode: .steps(current: current))`。
/// 现在只占同样的高度，好让高度用例与真机排版先按最终尺寸量。
private struct GuideRunStepsPlaceholder: View {
    let current: Int

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: GuideRunActivityMetrics.progressLineHeight)
            .accessibilityHidden(true)
    }
}

/// 右侧通用人像（DECISION 第 7 条：卡上不写名字，不放姓氏首字）。读屏由调用方决定藏不藏。
private struct GuideRunAvatar: View {
    let diameter: CGFloat

    var body: some View {
        Circle()
            .fill(GuideRunCardPalette.color(GuideRunCardPalette.avatarFill))
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: diameter * 0.5, weight: .bold))
                    .foregroundStyle(GuideRunCardPalette.color(GuideRunCardPalette.avatarInk))
            )
            .overlay(Circle().stroke(.white, lineWidth: diameter > 30 ? 3 : 0))
            .frame(width: diameter, height: diameter)
    }
}

/// 灵动岛紧凑态右侧：一个数（倒计时 / 「8 分钟」/「到了」）。
@available(iOS 16.2, *)
private struct GuideRunCompactTrailing: View {
    let presentation: GuideRunActivityPresentation

    var body: some View {
        Group {
            if let target = presentation.compactCountdownTo, target > Date() {
                Text(timerInterval: Date()...target, countsDown: true)
                    .frame(maxWidth: 52)
            } else {
                Text(presentation.compactTrailing)
            }
        }
        .font(.system(size: 15, weight: .bold))
        .monospacedDigit()
        .lineLimit(1)
        .foregroundStyle(presentation.compactIsPositive ? GuideRunCardPalette.color(GuideRunCardPalette.positive) : .white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.compactAccessibilityLabel)
    }
}
