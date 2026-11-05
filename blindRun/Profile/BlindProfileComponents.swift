import SwiftUI

// 盲人端「个人资料」查看页、选择页、编辑页共用的文案、选项表和分组卡（#750，定稿 `docs/ui/mockups/blind-profile-edit-20261105/`）。
//
// 组标题按「陪跑员什么时候看得到」分：视力、牵引方式和订单配速在派单邀请里就显示
// （`VolunteerInviteQueue.swift` 的 `escortNeeds`），两段自由文本接单后才给（AGENTS.md §8）。
// 改组标题之前先核这两处，别写成别的说法。

enum BlindProfileCopy {
    static let roleLine = "视障跑者"
    static let nickname = "昵称"
    static let tether = "希望怎么被引导"
    static let pace = "默认配速"
    static let guideNote = "给陪跑员的话"
    static let specialNeeds = "特殊需求"
    static let vision = "视力"
    static let guideDog = "平时使用导盲犬"
    static let emergencyContacts = "紧急联系人"
    static let unfilled = "未填写"
    static let tetherUndecided = "还没决定"

    static let dispatchGroupTitle = "派单时，陪跑员就会看到"
    static let acceptedGroupTitle = "接单后，陪跑员才看到"
    /// 全角「）」收尾补窄空格，防无障碍审计判裁切（记忆 `text-clipped-audit-trailing-fullwidth-paren`）。
    static let visionGroupTitle = "视力状况（敏感个人信息）\u{202F}"

    static let withdrawRowTitle = "撤回这两项的同意"
    static let fillVisionRowTitle = "填写视力状况"

    static let visionConsentedFootnote = "派单时陪跑员会看到，好提前准备。撤回后这两项改成「不提供」，以后想填可以再同意。"
    static let visionPendingFootnote = "这两项属于敏感个人信息，填之前我们会先单独问你一次。"
    static let contactsFootnote = "下单前至少要有 1 位，最多 \(EmergencyContactRules.maxCount) 位。"

    static let tetherChoiceFootnote = "陪跑员到场前会看到这一项，好提前准备。不选也能约跑。"
    static let paceChoiceFootnote = "下单时默认用这个配速，下单时还能改。陪跑员在派单时会看到订单的配速。"
    static let visionChoiceFootnote = "属于敏感个人信息，你已单独同意。派单时陪跑员会看到，好提前准备。不想再提供，回上一页点「撤回这两项的同意」。"
    static let guideDogChoiceFootnote = "选「有」之后，只会给你派接受与导盲犬同行的陪跑员。"

    static func visionLevelTitle(_ level: VisionLevel?) -> String {
        switch level {
        case .totalBlind: return "完全看不见"
        case .lowVision: return "还有一些视力"
        default: return "不填"
        }
    }
}

/// 选择页的一项。`title` 同时是选中后「已保存：xx」里的那个词。
struct BlindProfileChoice<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var id: String { title }
}

enum BlindProfileChoices {
    static let tether: [BlindProfileChoice<TetherPreference?>] =
        [BlindProfileChoice(value: nil, title: BlindProfileCopy.tetherUndecided)]
            + TetherPreference.allCases.map { BlindProfileChoice(value: $0, title: $0.displayName) }

    static let pace: [BlindProfileChoice<PacePreference>] =
        PacePreference.allCases.map { BlindProfileChoice(value: $0, title: $0.displayName) }

    /// 文案用功能性自述而不是残疾等级（理由见 `BlindEscortPreferencesTests.testVisionOptionsUseFunctionalWordingNotDisabilityGrades`）。
    /// 没有「不填」：选它请求里不带 `visionLevel`，服务端保留原值，念「已保存」就是假的。清空走「撤回这两项的同意」。
    static let vision: [BlindProfileChoice<VisionLevel?>] =
        [VisionLevel.totalBlind, VisionLevel.lowVision].map {
            BlindProfileChoice(value: $0, title: BlindProfileCopy.visionLevelTitle($0))
        }

    static let guideDog: [BlindProfileChoice<GuideDogStatus>] =
        GuideDogStatus.allCases.map { BlindProfileChoice(value: $0, title: $0.profileOptionTitle) }
}

/// 一组：灰色小标题（可无）+ 白色圆角卡 + 灰色说明（可无）。
struct BlindProfileGroup<Content: View>: View {
    var title: String?
    var footnote: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
                    .padding(.top, 8)
                    .accessibilityAddTraits(.isHeader)
            }
            GroupedCard {
                content
            }
            if let footnote {
                GroupedCardFootnote(text: footnote)
            }
        }
    }
}

/// 两行的行：上面名称，下面一行灰字（给陪跑员的话、紧急联系人摘要）。灰字为空时退回「名称 + 右侧值」。
struct BlindProfileDetailRowLabel: View {
    let title: String
    let detail: String?
    var emptyValue = BlindProfileCopy.unfilled
    var detailColor = AppColors.textSecondary

    var body: some View {
        if let detail = detail?.nilIfBlank {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textPrimary)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundColor(detailColor)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                SettingsChevron()
            }
            .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: .leading)
            .contentShape(Rectangle())
        } else {
            SettingsRowLabel(title: title, value: emptyValue)
        }
    }
}

/// 「紧急联系人」一行摘要 → #747 的 `EmergencyContactsView`。
///
/// 读屏标签保持「管理紧急联系人」（UI 用例按它找这一行），摘要放进 value。
struct BlindProfileEmergencyContactsGroup: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        BlindProfileGroup(title: BlindProfileCopy.emergencyContacts, footnote: BlindProfileCopy.contactsFootnote) {
            NavigationLink {
                EmergencyContactsView()
            } label: {
                BlindProfileDetailRowLabel(
                    title: BlindProfileCopy.emergencyContacts,
                    detail: summary,
                    detailColor: appState.hasExactlyOnePrimaryEmergencyContact
                        ? AppColors.textSecondary
                        : AppColors.destructive
                )
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("管理紧急联系人")
            .accessibilityValue(summary.replacingOccurrences(of: " · ", with: "，"))
            .accessibilityHint("添加、编辑、删除紧急联系人，或切换主联系人")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("blindProfileEmergencyContactsRow")
        }
    }

    private var summary: String {
        let count = appState.emergencyContactCount
        guard count > 0 else { return "还没有，下单前至少要有 1 位" }
        guard let primary = appState.primaryEmergencyContact else {
            return "\(count) 位 · 还没有主联系人，请点进去设置"
        }
        return "\(count) 位 · 主联系人是\(primary.name?.nilIfBlank ?? "未命名")"
    }
}
