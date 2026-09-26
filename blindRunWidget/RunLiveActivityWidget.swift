import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// MARK: - 锁屏实时活动（状态清单 §16 跑者端 / §17 陪跑员端）
//
// 跑者端：深色卡，顶行 + 三个数字 + 播报按钮（状态清单 §16）。
// 陪跑员端：2026-09-26 起换成 v2 样式（交付包 04 最后一节，决定源 V3）—— 状态色底、
// 节奏信号顶行、「距离 / 目标」、进度条，见文件末尾 `VolunteerRunCardView`。
// 两端仍是**同一个 `ActivityAttributes` 类型、同一条本地更新链路**，只是长相按 `side` 分叉；
// 陪跑员端依旧「一个可聚焦控件都没有」（状态清单 §17）。
//
// ⛔ **锁屏上不许有结束按钮，也不许有求助按钮**（状态清单「禁止项」）：
// 结束是不可撤销的动作而口袋会误触；锁屏下 App 无法拨号，求助交给系统 SOS。

@available(iOS 16.2, *)
struct RunLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunLiveActivityAttributes.self) { context in
            Group {
                if context.attributes.side == .volunteer {
                    VolunteerRunCardView(state: context.state)
                } else {
                    RunLiveActivityLockScreenView(side: context.attributes.side, state: context.state)
                }
            }
            .activityBackgroundTint(RunLiveActivityPalette.color(Self.background(for: context)))
            .activitySystemActionForegroundColor(RunLiveActivityPalette.color(RunLiveActivityPalette.cta))
        } dynamicIsland: { context in
            // 跑者端：设计包没给灵动岛，做成最小可用的一套 —— 展开态复用锁屏那三个数字，收起态只给里程。
            // 陪跑员端 v2（交付包 04）：紧凑态左侧并肩两点 + 金色短绳，右侧「2.40 公里」；最小态只有并肩圆点。
            // 两端都**不放任何按钮** —— 与锁屏同一条红线。
            let isVolunteer = context.attributes.side == .volunteer
            return DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    RunLiveActivityMetricsRow(state: context.state)
                }
            } compactLeading: {
                if isVolunteer { SideBySideDots() } else { Image(systemName: "figure.run") }
            } compactTrailing: {
                Text(isVolunteer ? "\(context.state.distanceText) \(RunLiveActivityCopy.kilometers)" : context.state.distanceText)
                    .font(isVolunteer ? .system(size: 14, weight: .heavy) : nil)
                    .monospacedDigit()
            } minimal: {
                if isVolunteer { SideBySideDots(showsRope: false) } else { Image(systemName: "figure.run") }
            }
        }
    }

    /// 跑者端沿用深色卡；陪跑员端跟随状态色（决定源 V3 / V13）：跑步中青绿、暂停灰。
    private static func background(for context: ActivityViewContext<RunLiveActivityAttributes>) -> UInt32 {
        guard context.attributes.side == .volunteer else { return RunLiveActivityPalette.cardSurface }
        return context.state.isPaused == true ? LiveActivityStatePalette.statePaused : LiveActivityStatePalette.stateRunning
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

// MARK: - 陪跑员端 v2 跑步卡（交付包 04 最后一节）
//
// 三行：「陪跑中 · 李：刚刚好」/「2.40 / 5.00 公里 · 18:32 · 7'43"」/ 8pt 进度条。
// **不画折返线**（决定源 V12：没有数据来源）、**不放任何按钮**（口袋误触会结束陪跑）。

@available(iOS 16.2, *)
struct VolunteerRunCardView: View {
    let state: RunLiveActivityAttributes.ContentState

    private var isPaused: Bool { state.isPaused == true }
    private var tint: Color {
        RunLiveActivityPalette.color(isPaused ? LiveActivityStatePalette.statePaused : LiveActivityStatePalette.stateRunning)
    }

    var body: some View {
        let headline = RunLiveActivityCopy.volunteerHeadline(
            surname: state.partnerName,
            rhythmSignal: state.rhythmSignal,
            isPaused: isPaused
        )
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: "figure.run")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(tint)
                    )
                Text(headline)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(LiveActivityStatePalette.onHeroEyebrowOpacity))
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(state.distanceText)
                    .font(.system(size: 40, weight: .heavy))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(RunLiveActivityCopy.targetSuffix(state.targetDistanceText))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white.opacity(LiveActivityStatePalette.onHeroBodyOpacity))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(state.durationText) · \(state.paceText)")
                    .font(.system(size: 17, weight: .heavy))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.top, 8)
            if let progress = state.progress {
                ProgressBar(progress: progress)
                    .padding(.top, 12)
            }
        }
        .foregroundStyle(.white)
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RunLiveActivityCopy.volunteerCardAccessibilityLabel(headline: headline, state: state))
    }
}

private struct ProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(LiveActivityStatePalette.onHeroTrackOpacity))
                Capsule().fill(.white).frame(width: proxy.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 8)
    }
}

/// 陪跑员端灵动岛：并肩的两个小圆点（+ 金色短绳）。
private struct SideBySideDots: View {
    var showsRope = true

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: -2) {
                Circle().fill(.white).frame(width: 12, height: 12)
                Circle().stroke(.white, lineWidth: 1.5).frame(width: 11, height: 11)
            }
            if showsRope {
                Capsule()
                    .fill(RunLiveActivityPalette.color(LiveActivityStatePalette.gold))
                    .frame(width: 14, height: 2)
            }
        }
        .accessibilityHidden(true)
    }
}
