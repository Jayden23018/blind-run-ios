import SwiftUI

// 盲人端「个人资料」核对清单（#812，定稿 `docs/ui/mockups/blind-profile-checklist-20261106/`）：
// 5 张卡，除紧急联系人外每张卡点开后一题一屏，整张卡答完点「完成」才保存。
// 卡名与题目用负责人 2026-11-06 批准的书面说法。

// MARK: - 卡片

enum BlindProfileCard: String, CaseIterable, Identifiable {
    case escort
    case vision
    case guideNote
    case otherNeeds
    case emergencyContacts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .escort: return "陪跑方式"
        case .vision: return "视力状况与导盲犬"
        case .guideNote: return "途中提示"
        case .otherNeeds: return "其他需求"
        case .emergencyContacts: return BlindProfileCopy.emergencyContacts
        }
    }

    /// 卡片上「谁会看到」那句说明。紧急联系人不需要。
    var detail: String? {
        switch self {
        case .escort: return "包括引导方式与默认配速，共 2 题。派单时向陪跑员展示。"
        case .vision: return "属于敏感个人信息，填写前需单独同意。不填写不影响预约陪跑。"
        case .guideNote: return "包括路况播报、提示事项与补充说明，共 3 题。接单后向陪跑员展示。"
        case .otherNeeds: return "如途中休息、补水提醒等。接单后向陪跑员展示。"
        case .emergencyContacts: return nil
        }
    }

    var systemImage: String {
        switch self {
        case .escort: return "figure.run"
        case .vision: return "eye.fill"
        case .guideNote: return "text.bubble.fill"
        case .otherNeeds: return "doc.text.fill"
        case .emergencyContacts: return "phone.fill"
        }
    }

    /// 图标颜色（负责人 11-06 同意用彩色）。只用全局语义色：草稿里的天青 / 靛蓝 / 橙 / 琥珀在
    /// `AppColors.VolunteerHome` 下，注释写明只给陪跑员首页用，不当全局色。图标是装饰，读屏不念。
    var tint: Color {
        switch self {
        case .escort: return AppColors.success
        case .vision: return AppColors.primary
        case .guideNote: return AppColors.warning
        case .otherNeeds: return AppColors.Flow.secondaryText
        case .emergencyContacts: return AppColors.destructive
        }
    }

    /// 题目，按出现顺序。视力卡没取得同意时，前面还有一屏同意页（不算题号）。
    var questions: [BlindProfileQuestion] {
        switch self {
        case .escort: return [.tether, .pace]
        case .vision: return [.visionLevel, .guideDog]
        case .guideNote: return [.guideDetail, .guideCues, .guideSupplement]
        case .otherNeeds: return [.otherNeeds, .otherSupplement]
        case .emergencyContacts: return []
        }
    }
}

// MARK: - 题目

enum BlindProfileQuestion: String, Hashable {
    case tether
    case pace
    case visionLevel
    case guideDog
    case guideDetail
    case guideCues
    case guideSupplement
    case otherNeeds
    case otherSupplement

    enum Kind: Equatable {
        case single
        case multi
        case supplement
    }

    var kind: Kind {
        switch self {
        case .tether, .pace, .visionLevel, .guideDog, .guideDetail: return .single
        case .guideCues, .otherNeeds: return .multi
        case .guideSupplement, .otherSupplement: return .supplement
        }
    }

    var title: String {
        switch self {
        case .tether: return "引导方式"
        case .pace: return "默认配速"
        case .visionLevel: return "视力状况"
        case .guideDog: return "是否使用导盲犬"
        case .guideDetail: return "路况播报"
        case .guideCues: return "途中提示（可多选）"
        case .otherNeeds: return "其他需求（可多选）"
        case .guideSupplement, .otherSupplement: return "补充说明（选填）"
        }
    }

    /// 题目下面那句灰字：谁会看到、什么时候看到。
    var note: String {
        switch self {
        case .tether, .visionLevel: return "派单时向陪跑员展示，便于提前准备。"
        case .pace: return "预约陪跑时默认采用此配速，下单时可调整。"
        case .guideDog: return "选择「有」后，仅为你匹配接受导盲犬同行的陪跑员。"
        case .guideDetail, .guideCues, .otherNeeds: return "接单后向陪跑员展示。"
        case .guideSupplement, .otherSupplement: return "可点按「语音输入」口述，也可直接输入。"
        }
    }

    /// 单选 / 多选的选项：`id` 是存进草稿的值，`title` 是屏幕上与读屏念的字。
    var options: [BlindProfileOption] {
        switch self {
        case .tether:
            return TetherPreference.allCases.map { BlindProfileOption(id: $0.rawValue, title: $0.displayName) }
                + [BlindProfileOption(id: BlindProfileOption.tetherUndecidedID, title: BlindProfileCopy.tetherUndecided)]
        case .pace:
            return PacePreference.allCases.map { BlindProfileOption(id: $0.rawValue, title: $0.displayName) }
        case .visionLevel:
            // 没有「不填」：清空走「撤回同意」（理由见 `BlindEscortPreferencesTests`）。
            return [VisionLevel.totalBlind, VisionLevel.lowVision].map {
                BlindProfileOption(id: $0.rawValue, title: BlindProfileCopy.visionLevelTitle($0))
            }
        case .guideDog:
            return GuideDogStatus.allCases.map { BlindProfileOption(id: $0.rawValue, title: $0.profileOptionTitle) }
        case .guideDetail:
            return BlindProfilePhraseSet.guideNote.singleOptions.map { BlindProfileOption(id: $0, title: $0) }
        case .guideCues:
            return BlindProfilePhraseSet.guideNote.multiOptions.map { BlindProfileOption(id: $0, title: $0) }
        case .otherNeeds:
            return BlindProfilePhraseSet.specialNeeds.multiOptions.map { BlindProfileOption(id: $0, title: $0) }
        case .guideSupplement, .otherSupplement:
            return []
        }
    }

    /// 这道题的答案拼进哪张卡的文字（`nil` = 不是常用说法题）。题 → 字段的对应只在这里写一次。
    var phraseCard: BlindProfileCard? {
        switch self {
        case .guideDetail, .guideCues, .guideSupplement: return .guideNote
        case .otherNeeds, .otherSupplement: return .otherNeeds
        case .tether, .pace, .visionLevel, .guideDog: return nil
        }
    }

    /// 这道题属于哪一组说法。
    var phraseSet: BlindProfilePhraseSet? {
        switch phraseCard {
        case .guideNote: return .guideNote
        case .otherNeeds: return .specialNeeds
        default: return nil
        }
    }
}

struct BlindProfileOption: Identifiable, Hashable {
    /// 「暂不确定」不是 `TetherPreference` 的 case（理由见 `TetherPreference.notSpecifiedRawValue`），单给一个 id。
    static let tetherUndecidedID = "UNDECIDED"

    let id: String
    let title: String
}

// MARK: - 一张卡的答案草稿

/// 弹层里的答案。点「完成」之前只改这里，不碰 view model；关掉弹层就整份丢掉。
struct BlindProfileCardDraft: Equatable {
    /// 单选题的答案（选项 id）。「路况播报」不在这里，在 `guideNote.single`。
    var choices: [BlindProfileQuestion: String] = [:]
    var guideNote = BlindProfilePhraseAnswer.empty
    var specialNeeds = BlindProfilePhraseAnswer.empty

    func selection(for question: BlindProfileQuestion) -> String? {
        question == .guideDetail ? guideNote.single : choices[question]
    }

    func selectedSet(for question: BlindProfileQuestion) -> Set<String> {
        switch question {
        case .guideCues: return guideNote.multi
        case .otherNeeds: return specialNeeds.multi
        default: return []
        }
    }

    func phraseAnswer(for question: BlindProfileQuestion) -> BlindProfilePhraseAnswer? {
        switch question.phraseCard {
        case .guideNote: return guideNote
        case .otherNeeds: return specialNeeds
        default: return nil
        }
    }

    func choosing(_ id: String, for question: BlindProfileQuestion) -> BlindProfileCardDraft {
        var next = self
        if question == .guideDetail {
            next.guideNote.single = id
        } else {
            next.choices[question] = id
        }
        return next
    }

    func toggling(_ id: String, for question: BlindProfileQuestion) -> BlindProfileCardDraft {
        var next = self
        switch question {
        case .guideCues:
            next.guideNote.multi = BlindProfilePhraseSet.guideNote.toggling(id, in: guideNote.multi)
        case .otherNeeds:
            next.specialNeeds.multi = BlindProfilePhraseSet.specialNeeds.toggling(id, in: specialNeeds.multi)
        default:
            break
        }
        return next
    }

    func withSupplement(_ text: String, for question: BlindProfileQuestion) -> BlindProfileCardDraft {
        var next = self
        switch question {
        case .guideSupplement: next.guideNote.supplement = text
        case .otherSupplement: next.specialNeeds.supplement = text
        default: break
        }
        return next
    }

    /// 「继续 / 完成」能不能按。补充说明题总能按（超长在按下时拦，并念出差几个字）。
    func canAdvance(from question: BlindProfileQuestion) -> Bool {
        switch question.kind {
        case .single: return selection(for: question) != nil
        // 「其他需求」至少选一项（有「无其他需求」可选），「途中提示」一项不选也行。
        case .multi: return question == .otherNeeds ? !specialNeeds.multi.isEmpty : true
        case .supplement: return true
        }
    }

    /// 按「完成」时的校验：拼好的文字超长就不存。
    func lengthError(for card: BlindProfileCard) -> String? {
        switch card {
        case .guideNote: return BlindProfilePhraseSet.guideNote.lengthError(for: guideNote)
        case .otherNeeds: return BlindProfilePhraseSet.specialNeeds.lengthError(for: specialNeeds)
        case .escort, .vision, .emergencyContacts: return nil
        }
    }
}

// MARK: - 草稿 ↔ 资料

extension BlindProfileCardDraft {
    /// 打开弹层时的初值：已经答过的卡预选现有答案，没答过的单选题留空（「继续」是灰的）。
    @MainActor
    static func initial(for card: BlindProfileCard, viewModel: BlindRunnerProfileViewModel, isSet: Bool) -> BlindProfileCardDraft {
        var draft = BlindProfileCardDraft()
        switch card {
        case .escort:
            guard isSet else { break }
            draft.choices[.tether] = viewModel.tetherPreference?.rawValue ?? BlindProfileOption.tetherUndecidedID
            draft.choices[.pace] = viewModel.defaultPace.selectable.rawValue
        case .vision:
            guard isSet, let level = viewModel.visionLevel else { break }
            draft.choices[.visionLevel] = level.rawValue
            draft.choices[.guideDog] = viewModel.guideDog.rawValue
        case .guideNote:
            draft.guideNote = BlindProfilePhraseSet.guideNote.parse(viewModel.guidePreferenceText)
        case .otherNeeds:
            draft.specialNeeds = BlindProfilePhraseSet.specialNeeds.parse(viewModel.specialNeeds)
        case .emergencyContacts:
            break
        }
        return draft
    }

    /// 点「完成」后写进 view model 的那一步（随后整份保存；没存上由 `saveCard` 改回去）。
    @MainActor
    func apply(to card: BlindProfileCard, viewModel: BlindRunnerProfileViewModel) {
        switch card {
        case .escort:
            if let tether = choices[.tether] {
                viewModel.tetherPreference = TetherPreference(rawValue: tether)
            }
            if let pace = choices[.pace].flatMap(PacePreference.init(rawValue:)) {
                viewModel.defaultPace = pace
            }
        case .vision:
            if let level = choices[.visionLevel].flatMap(VisionLevel.init(rawValue:)) {
                viewModel.visionLevel = level
            }
            if let dog = choices[.guideDog].flatMap(GuideDogStatus.init(rawValue:)) {
                viewModel.guideDog = dog
            }
        case .guideNote:
            viewModel.guidePreferenceText = BlindProfilePhraseSet.guideNote.compose(guideNote)
        case .otherNeeds:
            viewModel.specialNeeds = BlindProfilePhraseSet.specialNeeds.compose(specialNeeds)
        case .emergencyContacts:
            break
        }
    }

    /// 保存成功后念的「已保存：…」里的那段。
    func savedLabel(for card: BlindProfileCard) -> String {
        func title(_ question: BlindProfileQuestion) -> String? {
            let id = selection(for: question)
            return question.options.first { $0.id == id }?.title
        }
        switch card {
        case .escort:
            return [title(.tether), title(.pace)].compactMap { $0 }.joined(separator: " · ")
        case .vision:
            return [title(.visionLevel), title(.guideDog).map { "导盲犬：\($0)" }].compactMap { $0 }.joined(separator: " · ")
        case .guideNote, .otherNeeds, .emergencyContacts:
            return card.title
        }
    }
}

// MARK: - 卡片状态

/// 卡片「已设置 / 尚未设置」和状态行。判据只看已存的资料，不记本地标志（换设备、重装都一致）。
struct BlindProfileCardStatus: Equatable {
    let isSet: Bool
    /// 状态行。已设置时是现有答案的摘要。
    let line: String

    static let unsetLine = "尚未设置"

    @MainActor
    static func resolve(
        _ card: BlindProfileCard,
        viewModel: BlindRunnerProfileViewModel,
        profile: BlindProfileResponse?,
        contactCount: Int,
        primaryContactName: String?
    ) -> BlindProfileCardStatus {
        switch card {
        case .escort:
            // 引导方式答过（含「暂不确定」= `NOT_SPECIFIED` 以外的值），或配速存过。
            let hasTether = profile?.tetherPreference.map { !TetherPreference.isUnprovided($0) } ?? false
            guard hasTether || profile?.defaultPace != nil else { return .unset(card) }
            let tether = viewModel.tetherPreference?.displayName ?? BlindProfileCopy.tetherUndecided
            return BlindProfileCardStatus(isSet: true, line: "\(tether) · \(viewModel.defaultPace.displayName)")
        case .vision:
            // 存量档案都回填过 `NOT_SPECIFIED`，所以只认「已同意且有值」，拒绝过的也算没设置。
            guard viewModel.hasVisionConsent, let level = viewModel.visionLevel else { return .unset(card) }
            let line = "\(BlindProfileCopy.visionLevelTitle(level)) · 导盲犬：\(viewModel.guideDog.profileOptionTitle)"
            return BlindProfileCardStatus(isSet: true, line: line)
        case .guideNote:
            guard let text = profile?.guidePreferenceText?.trimmed.nilIfBlank else { return .unset(card) }
            return BlindProfileCardStatus(isSet: true, line: text)
        case .otherNeeds:
            guard let text = profile?.specialNeeds?.trimmed.nilIfBlank else { return .unset(card) }
            return BlindProfileCardStatus(isSet: true, line: text)
        case .emergencyContacts:
            return contacts(count: contactCount, primaryName: primaryContactName)
        }
    }

    private static func contacts(count: Int, primaryName: String?) -> BlindProfileCardStatus {
        guard count > 0 else {
            return BlindProfileCardStatus(isSet: false, line: "尚未添加，预约陪跑前至少需要 1 位")
        }
        // 没有主要联系人时约跑会被拦（`AppState.hasValidEmergencyContacts`），所以仍算「未设置」。
        guard let primaryName else {
            return BlindProfileCardStatus(isSet: false, line: "\(count) 位 · 尚未设置主要联系人")
        }
        return BlindProfileCardStatus(isSet: true, line: "\(count) 位 · 主要联系人：\(primaryName)")
    }

    private static func unset(_ card: BlindProfileCard) -> BlindProfileCardStatus {
        BlindProfileCardStatus(isSet: false, line: card == .vision ? "\(unsetLine) · 敏感个人信息" : unsetLine)
    }
}
