import SwiftUI

/// 约跑页顶部的「约跑前还差 N 项」（#781）。
///
/// 2026-11-05 起新用户登录后直接进首页，不再先被拦在「完善信息」页（负责人原话：
/// 「这个应该是以后他们想填写再填写的，不要因为这个卡住他们」）。昵称和紧急联系人
/// 到约跑时才要：缺哪项这里就列哪一行，点进去补，补完回来这张卡自己消失。
///
/// 门槛本身没变，判据仍是 `BlindBookingGate`（后端无紧急联系人 403 `EMERGENCY_CONTACT_REQUIRED`；
/// 昵称用在求助短信里）。这里只决定「在哪儿补」。
///
/// 页面底是白的（`AppColors.background`），所以卡用浅灰底 `Flow.surfaceSubtle`，
/// 不用「我的」那张白卡 `GroupedCard`（白底上看不出卡）。
struct BlindBookingMissingSetupCard: View {
    let needsNickname: Bool
    /// nil = 紧急联系人齐了；否则是这一行右边的灰字。
    let emergencyContactsValue: String?

    private var missingCount: Int {
        (needsNickname ? 1 : 0) + (emergencyContactsValue == nil ? 0 : 1)
    }

    var body: some View {
        if missingCount > 0 {
            VStack(alignment: .leading, spacing: 8) {
                Text("约跑前还差 \(missingCount) 项")
                    .font(.footnote)
                    .foregroundColor(AppColors.textSecondary)
                    .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 0) {
                    if needsNickname {
                        NavigationLink {
                            BlindRunnerProfileView()
                        } label: {
                            SettingsRowLabel(title: "昵称", value: "未填写")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("昵称，未填写")
                        .accessibilityHint("去个人资料填写昵称，填完回到这一页接着约跑")
                        .accessibilityIdentifier("blindBookingMissingNicknameRow")
                    }
                    if needsNickname, emergencyContactsValue != nil {
                        GroupedCardDivider()
                    }
                    if let emergencyContactsValue {
                        NavigationLink {
                            EmergencyContactsView()
                        } label: {
                            SettingsRowLabel(title: "紧急联系人", value: emergencyContactsValue)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("紧急联系人，\(emergencyContactsValue)")
                        .accessibilityHint("至少添加 1 位，并设 1 位为主联系人。补完回到这一页接着约跑")
                        .accessibilityIdentifier("blindBookingMissingEmergencyContactsRow")
                    }
                }
                .background(AppColors.Flow.surfaceSubtle)
                .clipShape(RoundedRectangle(cornerRadius: GroupedCardMetrics.cardRadius, style: .continuous))

                GroupedCardFootnote(text: "补完回到这一页，接着约跑。")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("blindBookingMissingSetupCard")
        }
    }
}

extension BlindBookingMissingSetupCard {
    /// 从 `AppState` 取两项的现状。紧急联系人「有人但没有唯一主联系人」和「一个都没有」说法不同。
    @MainActor
    init(appState: AppState) {
        needsNickname = !appState.isBlindBasicProfileComplete
        if appState.hasValidEmergencyContacts {
            emergencyContactsValue = nil
        } else if appState.emergencyContactCount == 0 {
            emergencyContactsValue = "未添加"
        } else {
            emergencyContactsValue = "未设主联系人"
        }
    }
}
