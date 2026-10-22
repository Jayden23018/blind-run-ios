import SwiftUI

// 屏 3b「求助已发出」页的三个部件（#506，负责人 2026-10-22 批准的目视稿）。
// 倒计时那一屏不用它们，仍在 `EmergencyCountdownView` 里原样画。

/// 标题 + 「10:02 发出 · 3 分钟前」。
///
/// 图标与标题左对齐成一行（目视稿），不再是居中大图标：发出之后这一屏的重点是下面的状态与拨号，
/// 标题不该占掉首屏三分之一。图标跟随标题字号缩放（Dynamic Type 不封顶）。
///
/// 读屏合成一个标题元素：「求助已发出，10点02分发出，3分钟前」。每分钟刷新一次显示与标签。
struct EmergencySentHeader: View {
    let title: String
    /// nil = 不知道什么时候发出的（倒计时还没到点、恢复时后端没给时间）—— 那一行不显示，不猜。
    let sentAt: Date?

    var body: some View {
        TimelineView(.everyMinute) { context in
            let since = sentAt.map { EmergencySafetyCopy.sentSince($0, now: context.date) }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title.weight(.bold))
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.title.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundColor(AppColors.destructive)
                if let since {
                    Text(since.text)
                        .font(AppFonts.body())
                        .monospacedDigit()
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(since.map { "\(title)，\($0.spoken)" } ?? title)
        }
    }
}

/// 再按一次被并入同一条时的两行时间线：「10:02 发出求助」「10:05 又按了一次，并入这一条」。
///
/// 🔴 **对读屏隐藏**：它说的事，正文那句（`EmergencySafetyCopy.mergedIntoOpenEvent`）已经说过，
/// 再念一遍等于多划两次。它是给看得见、但看不清的人一眼认出「还是同一条」用的。
struct EmergencyMergeTimeline: View {
    let sentAt: Date
    let mergedAt: Date
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row(time: sentAt, text: EmergencySafetyCopy.sentTimelineFirstRow, isLatest: false)
            row(time: mergedAt, text: EmergencySafetyCopy.sentTimelineMergedRow, isLatest: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityHidden(true)
    }

    /// 辅助字号（AX1–AX5）下时刻单独占一行：并排时时刻列占掉近一半宽度，文字被挤成一字一行
    /// （#506 AX5 真机截图）。按档位切换，不用 `ViewThatFits`（会被无障碍审计判成改不了字号）。
    @ViewBuilder
    private func row(time: Date, text: String, isLatest: Bool) -> some View {
        let clock = Text(EmergencySafetyCopy.sentClock(time))
            .font(AppFonts.body().monospacedDigit())
            .foregroundColor(AppColors.textSecondary)
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                clock
                label(text: text, isLatest: isLatest)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                clock
                label(text: text, isLatest: isLatest)
            }
        }
    }

    private func label(text: String, isLatest: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            // 圆点不是唯一的区分手段：第二行的文字本身就说了「又按了一次」。
            Circle()
                .fill(isLatest ? AppColors.destructive : AppColors.textPrimary)
                .frame(width: 9, height: 9)
            Text(text)
                .font(AppFonts.body().weight(isLatest ? .semibold : .regular))
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 底部「误触了？撤销求助」：一行弱化的文字按钮。
///
/// 外部产品的取消都要刻意操作（滑块、PIN、长按），不和别的按钮一样醒目
/// （`docs/research/sos-sent-screen-patterns-20261022.md`）。这里**只降视觉、不降可点性**：
/// 可点高度仍是 64pt，点下去照旧弹二次确认（`cancelOwnerConfirmation`）。
/// 下划线是「这是能按的」的轮廓线索，低视力用户靠它把它和一句说明区分开。
struct EmergencyQuietCancelButton: View {
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading { ProgressView() }
                Text(EmergencySafetyCopy.sentQuietCancelTitle)
                    .font(AppFonts.body())
                    .underline()
                    .multilineTextAlignment(.center)
            }
            .foregroundColor(AppColors.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: AppTouchTarget.blindPrimary)
            .contentShape(Rectangle())
        }
        .disabled(isLoading)
        .accessibilityLabel(EmergencySafetyCopy.sentQuietCancelTitle)
        .accessibilityHint("误触时撤销本次求助，需要确认")
    }
}
