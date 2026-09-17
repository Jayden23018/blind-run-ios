import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// MARK: - 锁屏实时活动（状态清单 §16 跑者端 / §17 陪跑员端）
//
// 两端是**同一张卡**，差别只有两处：陪跑员端没有顶行、没有按钮。
// 状态清单 §17 的原话：「与跑者端同一张卡，去掉按钮」「一个可聚焦控件都没有」。
//
// ⛔ **锁屏上不许有结束按钮，也不许有求助按钮**（状态清单「禁止项」）：
// 结束是不可撤销的动作而口袋会误触；锁屏下 App 无法拨号，求助交给系统 SOS。

@available(iOS 16.2, *)
struct RunLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunLiveActivityAttributes.self) { context in
            RunLiveActivityLockScreenView(
                side: context.attributes.side,
                state: context.state
            )
            .activityBackgroundTint(RunLiveActivityPalette.color(RunLiveActivityPalette.cardSurface))
            .activitySystemActionForegroundColor(RunLiveActivityPalette.color(RunLiveActivityPalette.cta))
        } dynamicIsland: { context in
            // 灵动岛不在本轮设计范围内（设计包只给了锁屏两屏）。做成最小可用的一套：
            // 展开态复用锁屏那三个数字，收起态只给里程。**不放任何按钮** —— 与锁屏同一条红线。
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    RunLiveActivityMetricsRow(state: context.state)
                }
            } compactLeading: {
                Image(systemName: "figure.run")
            } compactTrailing: {
                Text(context.state.distanceText)
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "figure.run")
            }
        }
    }
}

// MARK: - 锁屏呈现

@available(iOS 16.2, *)
struct RunLiveActivityLockScreenView: View {
    let side: RunLiveActivitySide
    let state: RunLiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: RunLiveActivityMetrics.rowSpacing) {
            if let partnerName = state.partnerName, side == .runner {
                headline(partnerName)
            }
            RunLiveActivityMetricsRow(state: state)
            if side == .runner {
                announceButton
            }
        }
        .padding(RunLiveActivityMetrics.cardPadding)
    }

    /// 顶行：App 身份 + 「陪跑中 · 张伟」。
    ///
    /// 图标用 SF Symbol `figure.run` 而不是 App 图标位图 —— 设计包 Assets 一节要求
    /// 「图标全部用 SF Symbols」，且 widget target 不共享主 App 的资源目录。
    private func headline(_ name: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "figure.run")
                .font(.system(size: RunLiveActivityMetrics.labelSize, weight: .semibold))
            Text(RunLiveActivityCopy.appName)
                .font(.system(size: RunLiveActivityMetrics.labelSize, weight: .regular))
                .foregroundStyle(RunLiveActivityPalette.color(RunLiveActivityPalette.labelInk))
            Spacer(minLength: 8)
            avatar(name)
            Text(RunLiveActivityCopy.partnerHeadline(name))
                .font(.system(size: RunLiveActivityMetrics.headlineSize, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(RunLiveActivityPalette.color(RunLiveActivityPalette.numberInk))
        // 头像是纯装饰（姓氏已经在右边那行字里），合成成一个元素后只念文字。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(RunLiveActivityCopy.appName)，\(RunLiveActivityCopy.partnerHeadline(name))")
    }

    private func avatar(_ name: String) -> some View {
        Circle()
            .fill(RunLiveActivityPalette.color(RunLiveActivityPalette.avatarBackground))
            .frame(
                width: RunLiveActivityMetrics.avatarDiameter,
                height: RunLiveActivityMetrics.avatarDiameter
            )
            .overlay(
                Text(String(name.prefix(1)))
                    .font(.system(size: RunLiveActivityMetrics.avatarInitialSize, weight: .semibold))
                    .foregroundStyle(RunLiveActivityPalette.color(RunLiveActivityPalette.avatarInitial))
            )
            .accessibilityHidden(true)
    }

    private var announceButton: some View {
        Group {
            if #available(iOS 17.0, *) {
                Button(intent: AnnounceRunStatsIntent(spokenText: spokenAnnouncement)) {
                    Text(RunLiveActivityCopy.announceButtonTitle)
                        .font(.system(size: RunLiveActivityMetrics.announceButtonTitleSize, weight: .semibold))
                        // 高度低于仓库的 64pt 触达线是一次有意偏离，理由写在
                        // `RunLiveActivityMetrics.announceButtonHeight` 上。
                        .frame(maxWidth: .infinity, minHeight: RunLiveActivityMetrics.announceButtonHeight)
                        .foregroundStyle(RunLiveActivityPalette.color(RunLiveActivityPalette.onCTA))
                        .background(
                            RoundedRectangle(
                                cornerRadius: RunLiveActivityMetrics.announceButtonRadius,
                                style: .continuous
                            )
                            .fill(RunLiveActivityPalette.color(RunLiveActivityPalette.cta))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(RunLiveActivityCopy.announceButtonTitle)
            }
            // iOS 16.2–16.x 没有 `Button(intent:)`，锁屏卡只显示数字。
            // **刻意不退回一枚「打开 App」的按钮** —— 那与「不必解锁」正好相反，
            // 而一枚按下去要解锁、要等 App 起来的按钮，对正在跑的盲人是纯粹的干扰。
        }
    }

    private var spokenAnnouncement: String {
        RunLiveActivityCopy.announcement(
            distance: state.spokenDistance,
            duration: state.spokenDuration,
            pace: state.spokenPace
        )
    }
}

// MARK: - 三个数字

@available(iOS 16.2, *)
struct RunLiveActivityMetricsRow: View {
    let state: RunLiveActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: RunLiveActivityMetrics.columnSpacing) {
            metric(
                value: state.distanceText,
                label: RunLiveActivityCopy.distanceLabel,
                size: RunLiveActivityMetrics.distanceSize,
                accessibilityLabel: RunLiveActivityCopy.distanceAccessibilityLabel(state.spokenDistance)
            )
            metric(
                value: state.durationText,
                label: RunLiveActivityCopy.durationLabel,
                size: RunLiveActivityMetrics.metricSize,
                accessibilityLabel: RunLiveActivityCopy.durationAccessibilityLabel(state.spokenDuration)
            )
            metric(
                value: state.paceText,
                label: RunLiveActivityCopy.paceLabel,
                size: RunLiveActivityMetrics.metricSize,
                accessibilityLabel: RunLiveActivityCopy.paceAccessibilityLabel(state.spokenPace)
            )
            Spacer(minLength: 0)
        }
    }

    private func metric(
        value: String,
        label: String,
        size: CGFloat,
        accessibilityLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: size, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                // 里程在 AX 档会被顶宽，缩到 0.7 而不是换行 —— 与全屏那一屏同一条处理
                // （状态清单 §23）。
                .minimumScaleFactor(0.7)
                .foregroundStyle(RunLiveActivityPalette.color(RunLiveActivityPalette.numberInk))
            Text(label)
                .font(.system(size: RunLiveActivityMetrics.labelSize, weight: .regular))
                .lineLimit(1)
                .foregroundStyle(RunLiveActivityPalette.color(RunLiveActivityPalette.labelInk))
        }
        // 值与标签合成一个元素，念「里程 3.20 公里」而不是「3.20」「里程（公里）」两站。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}
