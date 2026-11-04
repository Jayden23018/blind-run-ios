import SwiftUI

// MARK: - Emergency Contact Form

/// 新增/编辑表单。
/// 后端返回明文手机号，编辑时直接明文回填——不要再用「掩码值等于未修改」那套推断。
/// 主联系人开关不在这里：改主联系人只走 set-primary 端点。
struct EmergencyContactFormView: View {
    private enum Field: Hashable {
        case name
        case phone
        case relationship
    }

    @ObservedObject var viewModel: EmergencyContactsViewModel
    let contact: EmergencyContactResponse?
    let onFinish: () -> Void

    @EnvironmentObject private var speechService: SpeechService
    @State private var name = ""
    @State private var phone = ""
    @State private var relationship = ""
    @State private var makePrimary = false
    @State private var localErrorMessage: String?
    /// 确认弹窗必须挂在表单上：表单是 sheet，挂在被它盖住的列表页上的 alert 会被 SwiftUI 丢掉。
    @State private var showDeleteConfirmation = false
    @State private var showPrimaryConfirmation = false
    /// 这两个动作的按钮在表单最下面，错误文字在它上方，大字号时已滚出屏幕，`Form` 不渲染屏幕外的行。
    /// 所以失败要自己弹出来。
    @State private var showActionFailure = false
    @State private var showContactPicker = false
    /// 选择器选完之后那一句，同时上屏和朗读（#657 B-10）。
    @State private var pickNotice: String?
    /// 输入框之间的焦点。数字键盘没有回车键，原来填完号码只能自己摸去下一格（#657 B-10）。
    @FocusState private var focusedField: Field?

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

    private var isEditing: Bool { contact != nil }

    private var smsNotice: String { isEditing ? Self.editSmsNotice : Self.addSmsNotice }

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

    private var validationMessage: String? {
        EmergencyContactsViewModel.validationMessage(
            name: name,
            phone: phone,
            relationship: relationship
        )
    }

    var body: some View {
        Form {
            Section {
                // 排在输入框前面：手打 11 位是这张表最容易出错的一步，能选就别打（#657 B-10）。
                Button {
                    focusedField = nil
                    showContactPicker = true
                } label: {
                    contactActionLabel("从通讯录选择", color: AppColors.primary)
                }
                .disabled(viewModel.isMutating)
                .accessibilityLabel("从通讯录选择")
                .accessibilityHint("打开系统通讯录选一位联系人，自动填入姓名和手机号。助盲跑只拿到你选的这一位")
                .accessibilityIdentifier("emergencyContactPickFromContacts")
                .background(
                    ContactPhonePicker(isPresented: $showContactPicker) { pick in
                        applyPick(pick)
                    }
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
                )

                if let pickNotice {
                    Text(pickNotice)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(pickNotice)
                        .accessibilityIdentifier("emergencyContactPickNotice")
                }

                TextField("联系人姓名", text: $name)
                    .focused($focusedField, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .phone }
                    .accessibilityLabel("联系人姓名，必填")
                    .accessibilityHint("请输入紧急联系人姓名")

                TextField("11 位手机号", text: $phone)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .phone)
                    .accessibilityLabel("联系人手机号，必填，11 位")
                    .accessibilityHint("请输入紧急联系人手机号，只能输入数字")
                    .onChange(of: phone) { newValue in
                        let normalized = EmergencyContactsViewModel.normalizedPhoneInput(newValue)
                        if normalized != newValue { phone = normalized }
                    }

                TextField("关系，选填", text: $relationship)
                    .focused($focusedField, equals: .relationship)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
                    .accessibilityLabel("与联系人的关系，选填")
                    .accessibilityHint("例如家人、朋友、同事")
            } footer: {
                Text(smsNotice)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(smsNotice)
            }

            if !isEditing {
                Section {
                    Toggle("设为主联系人", isOn: $makePrimary)
                        .disabled(viewModel.contacts.isEmpty)
                        .accessibilityLabel("设为主联系人")
                        .accessibilityHint(
                            viewModel.contacts.isEmpty
                                ? "第一位紧急联系人必定是主联系人"
                                : "紧急情况下优先联系这一位"
                        )
                }
            }

            if let message = localErrorMessage ?? viewModel.errorMessage {
                Section {
                    Text(message)
                        .foregroundColor(AppColors.destructive)
                        .accessibilityLabel(message)
                }
            }

            if let contact {
                contactActions(contact)
            }
        }
        .navigationTitle(isEditing ? "编辑紧急联系人" : "新增紧急联系人")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    // 这条失败已经显示在表单里了，再回列表页弹一次只会多挡一层。
                    viewModel.isShowingFailure = false
                    onFinish()
                }
                    .accessibilityLabel("取消")
                    .accessibilityHint("放弃本次修改并返回")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .disabled(viewModel.isMutating)
                    .accessibilityLabel("保存")
                    .accessibilityHint(Self.saveHint(isEditing: isEditing, validationMessage: validationMessage))
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                if focusedField == .name || focusedField == .phone {
                    Button("下一项") {
                        focusedField = focusedField == .name ? .phone : .relationship
                    }
                    .accessibilityHint("跳到下一个输入框")
                } else {
                    Button("完成") { focusedField = nil }
                        .accessibilityLabel("收起键盘")
                }
            }
        }
        .onAppear {
            if let contact {
                name = contact.name ?? ""
                // 后端 v1.5.0 起返回明文，直接明文回填。
                phone = contact.phone ?? ""
                relationship = contact.relationship ?? ""
            } else {
                makePrimary = viewModel.contacts.isEmpty
            }
            speechService.speak(
                "\(isEditing ? "编辑紧急联系人" : "新增紧急联系人")。可以从通讯录选择，也可以手动输入。姓名和手机号必填，关系选填。\(smsNotice)"
            )
        }
        .alert("确认删除联系人", isPresented: $showDeleteConfirmation) {
            Button("确认删除", role: .destructive) {
                perform { await viewModel.delete($0) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除紧急联系人\(displayName)。删除后无法恢复，需要时请重新添加。")
        }
        .alert("确认设为主联系人", isPresented: $showPrimaryConfirmation) {
            Button("设为主联系人") {
                perform { await viewModel.setPrimary($0) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("紧急情况下会优先联系\(displayName)。原主联系人会自动变为普通联系人。\(unsavedEditsNotice)")
        }
        .alert("紧急联系人提示", isPresented: $showActionFailure) {
            Button("知道了", role: .cancel) { viewModel.isShowingFailure = false }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    /// 设为主联系人成功后表单就关了，改到一半的内容不会存下。
    private var unsavedEditsNotice: String {
        guard let contact else { return "" }
        let isUnchanged = name == (contact.name ?? "")
            && phone == (contact.phone ?? "")
            && relationship == (contact.relationship ?? "")
        return isUnchanged ? "" : "本页未保存的修改不会保留。"
    }

    private var displayName: String {
        contact?.name?.nilIfBlank ?? "该联系人"
    }

    /// 这两项会改变谁能接到紧急呼叫，所以放在页面最下面，都要二次确认。
    @ViewBuilder
    private func contactActions(_ contact: EmergencyContactResponse) -> some View {
        if contact.isPrimary != true {
            Section {
                Button {
                    showPrimaryConfirmation = true
                } label: {
                    contactActionLabel("设为主联系人", color: AppColors.primary)
                }
                .disabled(viewModel.isMutating)
                .accessibilityLabel("把\(displayName)设为主联系人")
                .accessibilityHint("需要二次确认")
            }
        }

        Section {
            Button(role: .destructive) {
                if viewModel.deletionBlockedReason(for: contact) == nil {
                    showDeleteConfirmation = true
                } else {
                    viewModel.reportDeletionBlocked(contact)
                    showActionFailure = true
                }
            } label: {
                contactActionLabel("删除联系人", color: AppColors.destructive)
            }
            .disabled(viewModel.isMutating)
            .accessibilityLabel("删除\(displayName)")
            .accessibilityHint(viewModel.deletionBlockedReason(for: contact) ?? "危险操作，需要二次确认")
        }
    }

    private func contactActionLabel(_ title: String, color: Color) -> some View {
        Text(title)
            .font(AppFonts.body().weight(.semibold))
            .foregroundColor(color)
            .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: .leading)
            .contentShape(Rectangle())
    }

    /// 动作成功才关页：失败时用户留在这里看到原因。
    private func perform(_ action: @escaping (EmergencyContactResponse) async -> Bool) {
        guard let contact else { return }
        Task {
            if await action(contact) {
                onFinish()
            } else {
                showActionFailure = true
            }
        }
    }

    private func applyPick(_ pick: ContactPhonePick) {
        let pickedPhone = pick.normalizedPhone
        if !pick.name.trimmed.isEmpty { name = pick.name.trimmed }
        // 不是手机号也照填（截到 11 位），让用户听得到、看得到，再自己改；校验仍由保存时那一道兜底。
        phone = EmergencyContactsViewModel.normalizedPhoneInput(pickedPhone)
        let message = Self.pickAnnouncement(name: pick.name, phone: pickedPhone)
        pickNotice = message
        localErrorMessage = nil
        if AppState.isValidMainlandPhone(pickedPhone) {
            speechService.speak(message)
        } else {
            speechService.speakError(message)
            focusedField = .phone
        }
    }

    /// 校验没过时把焦点放到出问题的那一格，免得读屏用户从头找。
    /// 按校验规则本身判，不按提示文案判：顺序与 `EmergencyContactsViewModel.validationMessage` 相同。
    private var firstInvalidField: Field {
        let trimmedName = name.trimmed
        if trimmedName.isEmpty || trimmedName.count > EmergencyContactRules.maxNameLength { return .name }
        if !AppState.isValidMainlandPhone(phone.trimmed) { return .phone }
        return .relationship
    }

    private func save() {
        if let validationMessage {
            localErrorMessage = validationMessage
            speechService.speakError(validationMessage)
            focusedField = firstInvalidField
            return
        }
        localErrorMessage = nil
        Task {
            let success: Bool
            if let contact {
                success = await viewModel.update(
                    contact: contact,
                    name: name,
                    phone: phone,
                    relationship: relationship
                )
            } else {
                success = await viewModel.create(
                    name: name,
                    phone: phone,
                    relationship: relationship,
                    makePrimary: makePrimary
                )
            }
            if success { onFinish() }
        }
    }
}
