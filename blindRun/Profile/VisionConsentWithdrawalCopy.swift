import Foundation

// 资料页与「隐私与授权」页（#393）共用这份文案，所以单独成文件。

/// 撤回「视力状况 + 导盲犬」同意（#352）。原与安卓 #91 逐字一致（负责人 2026-10-07 同意）；
/// 2026-10-19 起后两句改成「改成不提供」（#472）：后端存的是「不提供」这个值，不是删掉了这一项，
/// 负责人要求文案严格成立。按钮标题未变。
enum VisionConsentWithdrawalCopy {
    static let buttonTitle = "撤回同意"
    static let accessibilityLabel = "撤回同意，不再提供视力状况和导盲犬。按下后立刻把资料里这两项改成不提供，以后想填可以再同意"
    static let succeeded = "已撤回。资料里的视力状况和导盲犬已改成不提供，以后想填可以再点「填写视力状况」。"

    static func failed(saveButtonTitle: String) -> String {
        "撤回还没有保存成功，请再点一次「\(saveButtonTitle)」。"
    }
}
