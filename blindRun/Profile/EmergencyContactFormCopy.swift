import Foundation

// 紧急联系人表单的文案与纯函数（#746 从 `EmergencyContactFormView.swift` 挪出：那个文件超了 400 行）。
// 这里只放不碰表单私有状态的东西，单测直接调。
extension EmergencyContactFormView {
    /// 新增联系人有**外部副作用**：后端 `EmergencyContactService.addContact` 保存后会给这个第三方号码
    /// 发一条告知短信。盲人在按下「保存」之前有权知道这件事。
    ///
    /// 两处措辞是有依据的，不要随手改：
    /// - **不引述短信正文** —— 模板 `SMS_505950033` 的正文存在阿里云短信控制台、不在任何仓库里，
    ///   后端也没有控制台权限（handoff 2026-07-31）。写死一段猜的正文比不写更糟。
    /// - **不承诺送达** —— 短信失败不影响接口成功（后端已加 try-catch，`EmergencyContactService.java:91-93`），
    ///   所以「保存成功」不等于「对方收到了」。与 SOS 那条红线同源。
    static let addSmsNotice = "新增后，系统会向该号码发送一条来自「助盲跑」的短信，告知对方被设为你的紧急联系人。"
        + "短信可能发送失败，保存成功不代表对方已经收到。"

    /// 编辑走的是 `updateContact`，全仓库 `sendContactAddedSms` 只有 `addContact` 一个调用点
    /// （后端 2026-07-31 确认是有意为之）。**换号也不发**，所以编辑态说「会发短信」是一句念给盲人的假承诺。
    static let editSmsNotice = "修改手机号不会给新号码发送告知短信。如果需要对方收到告知，请删除后重新添加。"

    /// 「保存」按钮的提示。编辑态**不发**告知短信，原来这里不分情况一律说「会发短信」，
    /// 和同页的 `editSmsNotice` 互相矛盾（#657 B-32）。
    static func saveHint(isEditing: Bool, validationMessage: String?) -> String {
        if let validationMessage { return validationMessage }
        return isEditing
            ? "保存修改。修改手机号不会给新号码发送告知短信"
            : "保存后会向该号码发送一条告知短信"
    }

    /// 选中联系人后念的那一句。号码只念末四位：这一句也会进「重复当前状态」，外放时周围的人听得到。
    static func pickAnnouncement(name: String, phone: String) -> String {
        let who = name.trimmed.isEmpty ? "这位联系人" : name.trimmed
        guard AppState.isValidMainlandPhone(phone) else {
            return "已选择\(who)，但这个号码不是 11 位手机号，请换一个号码，或者手动输入。"
        }
        return "已选择\(who)，手机号尾号 \(phone.suffix(4))。请确认后保存。"
    }

    /// 选中联系人后表单里要填的值。纯函数，单测钉着（#746：列表页直接选人后表单一打开就是这些值）。
    struct PickedFields: Equatable {
        /// `nil` = 通讯录里没名字，保留表单原来的姓名。
        let name: String?
        let phone: String
        let notice: String
        let isValidPhone: Bool
    }

    static func pickedFields(_ pick: ContactPhonePick) -> PickedFields {
        let pickedPhone = pick.normalizedPhone
        return PickedFields(
            name: pick.name.trimmed.nilIfBlank,
            // 不是手机号也照填（截到 11 位），让用户听得到、看得到，再自己改；校验仍由保存时那一道兜底。
            phone: EmergencyContactsViewModel.normalizedPhoneInput(pickedPhone),
            notice: pickAnnouncement(name: pick.name, phone: pickedPhone),
            isValidPhone: AppState.isValidMainlandPhone(pickedPhone)
        )
    }
}
