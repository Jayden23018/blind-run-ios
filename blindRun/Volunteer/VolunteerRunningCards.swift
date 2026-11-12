import SwiftUI

// 陪跑员跑步中卡片页（`VolunteerRunningPage`，#972）彩色卡下面的两张白卡。
// 样子同盲人 v8 的白卡（`BlindRunCardSurface`），批准稿 `docs/ui/mockups/volunteer-run-finish-v8-20261112/`。

/// 跑步中卡片页的一张白卡（#972，批准稿 `docs/ui/mockups/volunteer-run-finish-v8-20261112/`）：
/// 标题 + 一行说明 + 右边开关，样子同盲人 v8 的白卡（`BlindRunCardSurface`）。
struct VolunteerRunVoiceToggle: View {
    @AppStorage(VolunteerRunVoiceBroadcast.defaultsKey) private var isOn = false

    var body: some View {
        BlindRunCardSurface(insets: EdgeInsets(top: 10, leading: 18, bottom: 10, trailing: 18)) {
            Toggle(isOn: $isOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(VolunteerRunCopy.voiceToggleTitle)
                        .flowFont(FlowV2Fonts.callout(bold: true))
                        .foregroundColor(AppColors.Flow.primaryText)
                    Text(VolunteerRunCopy.voiceToggleSubtitle)
                        .flowFont((13, .regular, .footnote))
                        .foregroundColor(AppColors.Flow.secondaryText)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: AppTouchTarget.blindPrimary)
        }
        .accessibilityIdentifier("volunteerRunVoiceToggle")
    }
}

/// 跑步中卡片页「让李*的手机响起来」那张卡（#972）。动作与跑步中求助面板那一行相同（`ringRunner`，后端 #445），
/// 走散时不用先开面板。响铃中、登录过期时不可点（同面板那一行）；结果走页脚的 `nudgeNotice`。
struct VolunteerRunRingCard: View {
    /// 屏幕上的称呼与读屏版。
    let runnerName: String
    let runnerNameSpoken: String
    let isRinging: Bool
    let isEnabled: Bool
    let onRing: () -> Void

    var body: some View {
        Button(action: onRing) {
            BlindRunCardSurface(insets: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                HStack(spacing: 10) {
                    Text(isRinging ? VolunteerRunCopy.ringingRowTitle : VolunteerRunCopy.ringRowTitle(runnerName))
                        .flowFont(FlowFonts.rowValue())
                        .foregroundColor(AppColors.Flow.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.Flow.secondaryText)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: AppTouchTarget.blindPrimary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.6)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isRinging ? VolunteerRunCopy.ringingRowTitle : VolunteerRunCopy.ringRowTitle(runnerNameSpoken))
        .accessibilityHint(VolunteerRunCopy.ringRowSubtitle)
        .accessibilityIdentifier("volunteerRunRingButton")
    }
}
