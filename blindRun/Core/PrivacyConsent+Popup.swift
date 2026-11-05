import Foundation

/// 单独同意的小弹窗与表单勾选框用到的文案（#769，2026-11-05 由整页逐条告知改成小弹窗 / 勾选框）。
///
/// 这里只能**点名** `disclosures` 里已有的处理行为，不能引入新内容 —— 完整告知仍是 `disclosures`，
/// 收在弹窗的「查看详细说明」和勾选框旁的协议页里。所以改这里不需要 +1 `disclosureVersion`；
/// 改 `disclosures` 才要判。依据见 `docs/research/consent-forms-mainstream-20261105.md`。
extension PrivacyConsentPurpose {
    /// 小弹窗的正文。为 nil 的目的不弹这种小弹窗（首启有自己的弹窗；志愿者实名在表单底部勾选；
    /// 位置轨迹用系统定位框前的说明页，文案在 `PrivacyConsent+LocationPreAlert.swift`，#776）。
    /// 用 `default` 而不逐个列出：不让这里卡住其他目的的增删。
    var popupSummary: String? {
        switch self {
        case .blindVisionProfile:
            return "视力状况和是否使用导盲犬属于敏感个人信息，只用来让陪跑员提前做好准备，陪跑员接单前就能看到。不填也能约跑。"
        case .voiceOrderThirdPartyLLM:
            return "你说的话会转成文字，发给阿里云通义千问（第三方大模型），帮助理解你要去哪里、什么时候出发。不同意可以手动填写。"
        default:
            return nil
        }
    }

    /// 小弹窗的自动播报：标题 + 摘要；没有摘要时退回全文。详细说明不念，展开后每条可单独听。
    var popupSpokenScript: String {
        guard let popupSummary else { return spokenScript }
        return [title, popupSummary].joined(separator: " ")
    }

    /// 表单底部勾选框旁的协议名（志愿者实名）。点开看的是 `disclosures` 原文。
    var checkboxDocumentTitle: String? {
        switch self {
        case .volunteerIdentity: return "身份信息与人脸核验授权"
        default: return nil
        }
    }

    /// 勾选框旁协议名点开后的页面：`disclosures` 原文逐条成行，不改一个字。
    var checkboxDocument: LegalFallbackCopy.Document {
        LegalFallbackCopy.Document(
            title: checkboxDocumentTitle ?? title,
            notice: "以下是提交前我们需要告知你的全部内容。看完回到上一页，勾选同意后再提交。",
            sections: [
                LegalFallbackCopy.Section(heading: "我们会怎么使用这些信息", bullets: disclosures)
            ]
        )
    }
}
