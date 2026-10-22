import SwiftUI

// 屏 3b「求助已发出」页的三个部件（#506，负责人 2026-10-22 批准的目视稿）。
// 倒计时那一屏不用它们，仍在 `EmergencyCountdownView` 里原样画。

/// 屏 3b 发出之后那一段：有哪些动作、什么顺序、拨号选择说哪一句 —— **逐状态穷举的唯一判定**。
///
/// 做成纯函数是 #506 code review 的 A1 / A2：最初只分「没发出」和「其余」，于是撤销后、倒计时内撤回后、
/// 正在发出时，拨号选择都说「求助已经发出」—— 违反 `AGENTS.md` §6。穷举 switch 让新增状态时编译器逼一次决策，
/// 单测逐状态钉住（`EmergencySentScreenTests`）。界面只照它渲染。
enum EmergencySentScreenAction: Equatable {
    case callMedical
    case retrySend
    case otherCalls(EmergencyCallContext)
    case quietCancel

    static func plan(for state: EmergencySOSState, hasActiveEvent: Bool) -> [EmergencySentScreenAction] {
        if state.isCountingDown { return [] }
        let others = EmergencySentScreenAction.otherCalls(callContext(for: state, hasActiveEvent: hasActiveEvent))
        // 一个字节都没发出去、也没有可撤销的事件：急救电话在前，重发在后（摔倒的人先要够到 120）。
        if state.isFailure, !hasActiveEvent { return [.callMedical, .retrySend, others] }
        return [.callMedical, others] + (hasActiveEvent ? [.quietCancel] : [])
    }

    /// 拨号选择的第一句。只有确定发出过才说「已经发出」，确定没发出才说「没有发出去」，其余一律中性。
    static func callContext(for state: EmergencySOSState, hasActiveEvent: Bool) -> EmergencyCallContext {
        switch state {
        case .acknowledged, .mergedIntoOpenEvent, .contactSmsDelivered, .contactNotifyFailed:
            return .cloudSent
        case .idle:
            return hasActiveEvent ? .cloudSent : .cloudUncertain
        case .unsentNoLocation, .unsentSessionExpired, .failed:
            return hasActiveEvent ? .cloudSent : .cloudFailed
        // 冷却 = 「刚刚已经发送过求助」：没对上账时说「没有发出去」就和那句自相矛盾。
        case .cooldown:
            return hasActiveEvent ? .cloudSent : .cloudUncertain
        case .countingDown, .locating, .submitting, .cancelledByOwner, .withdrawnBeforeSending, .withdrawFailed:
            return .cloudUncertain
        }
    }
}

/// 标题 + 「10:02 发出 · 3 分钟前」。
///
/// 图标与标题左对齐成一行（目视稿），不再是居中大图标：发出之后这一屏的重点是下面的状态与拨号，
/// 标题不该占掉首屏三分之一。图标跟随标题字号缩放（Dynamic Type 不封顶）。
///
/// 读屏合成一个标题元素：「求助已发出，10点02分发出，3分钟前」。每分钟刷新一次显示与标签。
struct EmergencySentHeader: View {
    /// 读屏合成的那一句：「求助已发出，10点02分发出，3 分钟前」；不知道发出时间就只念标题。
    static func accessibilityLabel(title: String, spokenSince: String?) -> String {
        spokenSince.map { "\(title)，\($0)" } ?? title
    }

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
            .accessibilityLabel(Self.accessibilityLabel(title: title, spokenSince: since?.spoken))
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
