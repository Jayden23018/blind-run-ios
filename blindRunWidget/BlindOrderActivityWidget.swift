import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - 盲人端「约跑进度」锁屏卡 + 灵动岛（#919，稿 B1–B7、B10、B11）
//
// 版式照 Uber 等车卡（`docs/ui/mockups/live-activity-v7-20261111/` DECISION 第 6 条）：
// 左上小标「助盲跑」→ 一行粗标题 → 一行短副标题，右侧通用人像，底部一根进度线。
// **卡上没有按钮**（找人、赶路时没有该在锁屏上做的事；求助交给系统 SOS，同跑步卡的禁止项）。
//
// 本文件也编进 app target：`LiveActivityCardHeightTests` 要在真机上排这张卡量高度（≤ 160pt）。

@available(iOS 16.2, *)
struct BlindOrderActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BlindOrderActivityAttributes.self) { context in
            let presentation = BlindOrderActivityPresentation(state: context.state, isStale: context.isStale)
            BlindOrderLockScreenView(presentation: presentation)
                .activityBackgroundTint(RunLiveActivityPalette.color(presentation.background))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let presentation = BlindOrderActivityPresentation(state: context.state, isStale: context.isStale)
            return DynamicIsland {
                // 展开态 = 锁屏卡去掉按钮（这张卡本来就没有按钮）。
                DynamicIslandExpandedRegion(.bottom) {
                    BlindOrderCardContent(presentation: presentation, showsBrand: true)
                }
            } compactLeading: {
                BlindOrderCompactLeading(presentation: presentation)
                    .accessibilityLabel(presentation.compactAccessibilityLabel)
            } compactTrailing: {
                BlindOrderCompactTrailing(presentation: presentation)
            } minimal: {
                BlindOrderCompactLeading(presentation: presentation)
                    .accessibilityLabel(presentation.compactAccessibilityLabel)
            }
            .keylineTint(LiveActivityProgressLine.defaultAccent)
        }
    }
}

// MARK: - 锁屏

@available(iOS 16.2, *)
struct BlindOrderLockScreenView: View {
    let presentation: BlindOrderActivityPresentation

    var body: some View {
        BlindOrderCardContent(presentation: presentation, showsBrand: true)
            .padding(.horizontal, BlindOrderCardMetrics.horizontalPadding)
            .padding(.top, BlindOrderCardMetrics.topPadding)
            .padding(.bottom, BlindOrderCardMetrics.bottomPadding)
            .background(RunLiveActivityPalette.color(presentation.background))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(presentation.accessibilityLabel)
    }
}

/// 稿 `.la` 的量（Uber 卡量出来的比例）。**卡高预算 160pt**：
/// 14 + 18（小标）+ 8 + 56（26pt 大标题 + 副标题，与 46pt 人像取大）+ 10 + 39（进度线）+ 12 ≈ 157。
enum BlindOrderCardMetrics {
    static let horizontalPadding: CGFloat = 18
    static let topPadding: CGFloat = 14
    static let bottomPadding: CGFloat = 12
    static let brandSize: CGFloat = 14
    static let titleSize: CGFloat = 22
    static let largeTitleSize: CGFloat = 26
    static let subtitleSize: CGFloat = 16
    static let avatarDiameter: CGFloat = 46
    static let avatarIcon: CGFloat = 22
    static let brandToMain: CGFloat = 8
    static let mainToLine: CGFloat = 10
    static let titleToSubtitle: CGFloat = 4
}

@available(iOS 16.2, *)
struct BlindOrderCardContent: View {
    let presentation: BlindOrderActivityPresentation
    let showsBrand: Bool

    private typealias M = BlindOrderCardMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsBrand {
                HStack(spacing: 5) {
                    Image(systemName: "figure.run")
                        .font(.system(size: M.brandSize - 1, weight: .semibold))
                    Text(BlindOrderActivityCopy.appName)
                        .font(.system(size: M.brandSize, weight: .semibold))
                }
            }
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: M.titleToSubtitle) {
                    title
                    subtitle
                }
                Spacer(minLength: 0)
                if presentation.showsAvatar {
                    BlindOrderAvatar(diameter: M.avatarDiameter, iconSize: M.avatarIcon)
                }
            }
            .padding(.top, showsBrand ? M.brandToMain : 0)
            if let line = presentation.line {
                LiveActivityProgressLine(mode: line)
                    .padding(.top, M.mainToLine)
            }
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var title: some View {
        let font = Font.system(
            size: presentation.titleIsLarge ? M.largeTitleSize : M.titleSize,
            weight: .bold
        )
        Group {
            if case .titlePrefix(let until, let suffix) = presentation.countdown {
                // 系统自走的倒计时（稿 B5「30 分钟」）。`Text(_:style: .timer)` 能和别的 `Text` 拼成一行。
                Text(until, style: .timer).monospacedDigit() + Text(suffix)
            } else {
                Text(presentation.title)
            }
        }
        .font(font)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    @ViewBuilder
    private var subtitle: some View {
        Group {
            if case .subtitlePrefix(let until, let prefix) = presentation.countdown {
                Text(prefix) + Text(until, style: .timer).monospacedDigit()
            } else if let subtitle = presentation.subtitle {
                Text(subtitle)
            }
        }
        .font(.system(size: M.subtitleSize))
        .foregroundStyle(.white.opacity(BlindOrderActivityPalette.subtitleOpacity))
        .lineLimit(1)
        .truncationMode(.middle)
    }
}

/// 通用人像（负责人 11-11：卡上不写名字）。纯装饰，读屏不念。
struct BlindOrderAvatar: View {
    let diameter: CGFloat
    let iconSize: CGFloat

    var body: some View {
        Circle()
            .fill(RunLiveActivityPalette.color(BlindOrderActivityPalette.avatarBackground))
            .frame(width: diameter, height: diameter)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(RunLiveActivityPalette.color(BlindOrderActivityPalette.avatarInk))
            )
            .overlay(Circle().stroke(.white, lineWidth: diameter > 30 ? 3 : 1.5))
            .accessibilityHidden(true)
    }
}

// MARK: - 灵动岛紧凑态 / 最小态（稿「三」：左人像或呼吸点，右一个数）

@available(iOS 16.2, *)
private struct BlindOrderCompactLeading: View {
    let presentation: BlindOrderActivityPresentation

    var body: some View {
        if presentation.compactShowsSearchingDot {
            Circle()
                .fill(LiveActivityProgressLine.defaultAccent)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(LiveActivityProgressLine.defaultAccent.opacity(0.35), lineWidth: 6))
                .frame(width: 22, height: 22)
        } else {
            BlindOrderAvatar(diameter: 22, iconSize: 12)
        }
    }
}

@available(iOS 16.2, *)
private struct BlindOrderCompactTrailing: View {
    let presentation: BlindOrderActivityPresentation

    var body: some View {
        Group {
            if case .titlePrefix(let until, _) = presentation.countdown {
                Text(until, style: .timer)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 52)
            } else {
                Text(presentation.compactTrailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(.white)
        .accessibilityLabel(presentation.compactTrailing)
    }
}
