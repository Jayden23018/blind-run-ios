import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// MARK: - 跑步中的锁屏实时活动（稿 B8 / B9 跑者端、V7 陪跑员端，2026-11-11 定稿）
//
// 照 Gentler Streak / Apple 健身：顶行是状态，中间三个并排同字号大数字，数字下面彩色小标签，
// 底线 = 里程 / 目标里程（没有目标里程时不画线）。
// - 跑者端（B8）：右侧 52pt 白色圆形喇叭键「听当前状态」，按下不开 App 直接播报。跑完（B9）换绿底，锁屏留 30 分钟。
// - 陪跑员端（V7）：没有按钮（口袋误触）；顶行右边是跑者最近一次节奏信号。
// 卡上不写名字（负责人 2026-11-11）。两端仍是同一个 `ActivityAttributes`、同一条本地更新链路。
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
            .activityBackgroundTint(RunLiveActivityPalette.color(Self.background(for: context.state)))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            // 稿「三」：紧凑态左跑步图标，右「2.40 公里」；最小态只放数字；展开态 = 锁屏卡去掉按钮。
            let state = context.state
            let label = RunLiveActivityCopy.cardAccessibilityLabel(
                headline: context.attributes.side == .volunteer
                    ? RunLiveActivityCopy.volunteerHeadline(isPaused: state.isPaused == true, isFinished: state.isFinished == true)
                    : RunLiveActivityCopy.runnerHeadline(isFinished: state.isFinished == true),
                state: state
            )
            return DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    RunCardBody(
                        headline: context.attributes.side == .volunteer
                            ? RunLiveActivityCopy.volunteerHeadline(isPaused: state.isPaused == true, isFinished: state.isFinished == true)
                            : RunLiveActivityCopy.runnerHeadline(isFinished: state.isFinished == true),
                        showsLiveDot: state.isFinished != true && state.isPaused != true,
                        trailingNote: context.attributes.side == .volunteer && state.isFinished != true
                            ? RunLiveActivityCopy.volunteerRhythm(state.rhythmSignal, isPaused: state.isPaused == true)
                            : nil,
                        distanceText: context.attributes.side == .volunteer
                            ? RunLiveActivityCopy.distanceWithTarget(state.distanceText, target: state.targetDistanceText)
                            : state.distanceText,
                        state: state,
                        dimsLabels: state.isFinished == true
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(label)
                }
            } compactLeading: {
                Image(systemName: "figure.run")
                    .foregroundStyle(RunLiveActivityPalette.color(RunLiveActivityV4Palette.liveGreen))
                    .accessibilityLabel(RunLiveActivityCopy.appName)
            } compactTrailing: {
                Text("\(state.distanceText) \(RunLiveActivityCopy.kilometers)")
                    .font(.system(size: 14, weight: .heavy))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityLabel(RunLiveActivityCopy.distanceAccessibilityLabel(state.spokenDistance))
            } minimal: {
                Text(state.distanceText)
                    .font(.system(size: 13, weight: .heavy))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .accessibilityLabel(label)
            }
            .keylineTint(RunLiveActivityPalette.color(RunLiveActivityV4Palette.liveGreen))
        }
    }

    /// 跑步中深蓝，跑完绿（B9），暂停灰。
    static func background(for state: RunLiveActivityAttributes.ContentState) -> UInt32 {
        if state.isFinished == true { return RunLiveActivityV4Palette.finished }
        if state.isPaused == true { return BlindOrderActivityPalette.stale }
        return BlindOrderActivityPalette.card
    }
}

// MARK: - 跑者端（B8 / B9）

@available(iOS 16.2, *)
struct RunLiveActivityLockScreenView: View {
    let side: RunLiveActivitySide
    let state: RunLiveActivityAttributes.ContentState

    private typealias M = RunLiveActivityMetrics

    private var isFinished: Bool { state.isFinished == true }
    private var headline: String { RunLiveActivityCopy.runnerHeadline(isFinished: isFinished) }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RunCardBody(
                headline: headline,
                showsLiveDot: !isFinished,
                trailingNote: nil,
                distanceText: state.distanceText,
                state: state,
                dimsLabels: isFinished
            )
            // 数字合成一站念；圆键单独一站（「听当前状态，按钮」）。
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(RunLiveActivityCopy.cardAccessibilityLabel(headline: headline, state: state))
            announceButton
        }
        .padding(.horizontal, M.horizontalPadding)
        .padding(.top, M.topPadding)
        .padding(.bottom, M.bottomPadding)
        .background(RunLiveActivityPalette.color(RunLiveActivityWidget.background(for: state)))
    }

    private var announceButton: some View {
        Group {
            if #available(iOS 17.0, *) {
                Button(intent: AnnounceRunStatsIntent(spokenText: spokenAnnouncement)) {
                    Circle()
                        .fill(.white)
                        .frame(width: M.announceButtonDiameter, height: M.announceButtonDiameter)
                        .overlay(
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: M.announceIconSize, weight: .semibold))
                                .foregroundStyle(RunLiveActivityPalette.color(BlindOrderActivityPalette.card))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(RunLiveActivityCopy.announceButtonTitle)
            }
            // iOS 16.2–16.x 没有 `Button(intent:)`，锁屏卡只显示数字。
            // **刻意不退回一枚「打开 App」的按钮** —— 那与「不必解锁」正好相反。
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

// MARK: - 陪跑员端（V7）

/// 「陪跑中 … 刚刚好」/「2.40 / 5.00 公里 · 用时 · 配速」/ 里程线。**不放任何按钮**（口袋误触会结束陪跑）。
/// 跑完同版式换绿底「跑完了」、不显示节奏信号，锁屏留 30 分钟（稿「五」第二段 · 两端）。
@available(iOS 16.2, *)
struct VolunteerRunCardView: View {
    let state: RunLiveActivityAttributes.ContentState

    private typealias M = RunLiveActivityMetrics

    private var isPaused: Bool { state.isPaused == true }
    private var isFinished: Bool { state.isFinished == true }

    var body: some View {
        let headline = RunLiveActivityCopy.volunteerHeadline(isPaused: isPaused, isFinished: isFinished)
        let rhythm = isFinished ? nil : RunLiveActivityCopy.volunteerRhythm(state.rhythmSignal, isPaused: isPaused)
        RunCardBody(
            headline: headline,
            showsLiveDot: !isPaused && !isFinished,
            trailingNote: rhythm,
            distanceText: RunLiveActivityCopy.distanceWithTarget(state.distanceText, target: state.targetDistanceText),
            state: state,
            dimsLabels: isFinished
        )
        .padding(.horizontal, M.horizontalPadding)
        .padding(.top, M.topPadding)
        .padding(.bottom, M.bottomPadding)
        .background(RunLiveActivityPalette.color(RunLiveActivityWidget.background(for: state)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RunLiveActivityCopy.cardAccessibilityLabel(headline: headline, rhythm: rhythm, state: state))
    }
}

// MARK: - 两端共用的卡身：顶行 + 三个数字 + 里程线

@available(iOS 16.2, *)
struct RunCardBody: View {
    let headline: String
    let showsLiveDot: Bool
    /// 顶行右边那几个字（陪跑员端的节奏信号）。跑者端顶行右边写 App 名。
    let trailingNote: String?
    let distanceText: String
    let state: RunLiveActivityAttributes.ContentState
    /// 跑完了（B9）：小标签改白 70%，绿底上彩色标签对比度不够。
    let dimsLabels: Bool

    private typealias M = RunLiveActivityMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                if showsLiveDot {
                    Circle()
                        .fill(RunLiveActivityPalette.color(RunLiveActivityV4Palette.liveGreen))
                        .frame(width: M.liveDot, height: M.liveDot)
                }
                Text(headline)
                Spacer(minLength: 8)
                Text(trailingNote ?? RunLiveActivityCopy.appName)
                    .foregroundStyle(.white.opacity(BlindOrderActivityPalette.subtitleOpacity))
                    .lineLimit(1)
            }
            .font(.system(size: M.headlineSize, weight: .semibold))
            HStack(alignment: .top, spacing: M.columnSpacing) {
                metric(distanceText, label: RunLiveActivityCopy.distanceLabel, labelColor: RunLiveActivityV4Palette.liveGreen)
                metric(state.durationText, label: RunLiveActivityCopy.durationLabel, labelColor: RunLiveActivityV4Palette.accent)
                metric(state.paceText, label: RunLiveActivityCopy.paceLabel, labelColor: RunLiveActivityV4Palette.accent)
            }
            .padding(.top, M.headlineToMetrics)
            if let progress = state.progress {
                LiveActivityProgressLine(mode: .mileage(progress: progress))
                    .padding(.top, M.metricsToLine)
            }
        }
        .foregroundStyle(.white)
    }

    private func metric(_ value: String, label: String, labelColor: UInt32) -> some View {
        VStack(alignment: .leading, spacing: M.labelSpacing) {
            Text(value)
                .font(.system(size: M.metricSize, weight: .heavy))
                .monospacedDigit()
                .lineLimit(1)
                // 「2.40 / 5.00」与最大字号下会顶宽：缩到 0.6 而不是换行（同全屏那一屏的处理，状态清单 §23）。
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: M.labelSize, weight: .bold))
                .foregroundStyle(dimsLabels ? Color.white.opacity(0.7) : RunLiveActivityPalette.color(labelColor))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
