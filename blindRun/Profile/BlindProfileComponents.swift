import SwiftUI

// 盲人端「个人资料」共用的文案（#750 起；#812 改成核对清单后只剩这些）。
// 卡片与题目的文案在 `BlindProfileChecklistCards.swift`，常用说法在 `BlindProfilePhrases.swift`。

enum BlindProfileCopy {
    static let roleLine = "视障跑者"
    static let nickname = "昵称"
    static let emergencyContacts = "紧急联系人"
    static let unfilled = "未填写"
    /// 引导方式的「还没决定」选项（不是 `TetherPreference` 的 case）。负责人 11-06 批准改成书面说法。
    static let tetherUndecided = "暂不确定"

    /// 视力卡上撤回同意的按钮（读屏标签另走 `VisionConsentWithdrawalCopy.accessibilityLabel`）。
    static let withdrawRowTitle = "撤回同意"

    /// 文案用功能性自述而不是残疾等级（理由见 `BlindEscortPreferencesTests.testVisionOptionsUseFunctionalWordingNotDisabilityGrades`）。
    static func visionLevelTitle(_ level: VisionLevel?) -> String {
        switch level {
        case .totalBlind: return "完全看不见"
        case .lowVision: return "还有一些视力"
        default: return "不填"
        }
    }
}
