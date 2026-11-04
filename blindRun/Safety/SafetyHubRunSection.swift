import SwiftUI

/// 求助中心方格下面、只在跑步中出现的那一段（#660 F-20、B-4 / F-10）。
///
/// 放在方格**之后**：拨号几格的位置是盲人靠记忆找的，插在前面会让「往下第二个是 120」失效。
/// 单独成文件是因为 `SafetyHubView.swift` 在 SwiftLint 棘轮的冻结名单里，只许变短。
struct SafetyHubRunSection: View {
    let mode: BlindHomeSOSMode
    /// `nil` = 调用方不提供结束出口。
    let onEndRun: (() -> Void)?

    @State private var showsEndRunConfirmation = false

    /// 指引在跑步中就有（含登录过期那一档）：两台手机在一起，走散告警不会响，只能靠跑者自己按。
    static func showsGuide(mode: BlindHomeSOSMode) -> Bool { mode != .localCall }

    /// 结束出口只在 `.cloudTrigger`：后端只收 `IN_PROGRESS`，登录过期时 `finish` 必然 401。
    static func showsEndRun(mode: BlindHomeSOSMode, hasAction: Bool) -> Bool { mode == .cloudTrigger && hasAction }

    private var showsGuide: Bool { Self.showsGuide(mode: mode) }
    private var showsEndRun: Bool { Self.showsEndRun(mode: mode, hasAction: onEndRun != nil) }

    var body: some View {
        if showsGuide {
            VStack(alignment: .leading, spacing: 12) {
                guide
                if showsEndRun { endRunButton }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .readableContentColumn()
        }
    }

    private var guide: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(BlindRunnerFinishCopy.volunteerUnwellTitle)
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.textPrimary)
            Text(BlindRunnerFinishCopy.volunteerUnwellSteps)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("blindSafetyHubVolunteerUnwellGuide")
    }

    /// 不是红色：它不是求助，按下也不会通知任何人。边框与方格同一种（1.5pt），表示「这是一个可按的东西」。
    private var endRunButton: some View {
        Button {
            showsEndRunConfirmation = true
        } label: {
            VStack(spacing: 4) {
                Text(BlindRunnerFinishCopy.endRunTitle)
                    .font(AppFonts.body().weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(BlindRunnerFinishCopy.endRunHint)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .foregroundColor(AppColors.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 64)
            .padding(12)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(AppColors.textPrimary.opacity(0.85), lineWidth: 1.5)
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(BlindRunnerFinishCopy.endRunTitle)
        .accessibilityHint(BlindRunnerFinishCopy.endRunHint)
        .accessibilityIdentifier("blindSafetyHubEndRunWithoutVolunteer")
        // 确认框挂在弹层里面，确认后由调用方先关弹层再执行（同「一键求助」，见 `SafetyHubPresentation`）。
        .alert(BlindRunnerFinishCopy.confirmTitle, isPresented: $showsEndRunConfirmation) {
            Button(BlindRunnerFinishCopy.confirmButtonTitle, role: .destructive) { onEndRun?() }
            Button(BlindRunnerFinishCopy.cancelButtonTitle, role: .cancel) {}
        } message: {
            Text(BlindRunnerFinishCopy.confirmMessage)
        }
    }
}
