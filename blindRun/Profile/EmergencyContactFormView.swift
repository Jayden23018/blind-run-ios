import SwiftUI

// MARK: - Emergency Contact Form

/// 新增/编辑表单。
/// 后端返回明文手机号，编辑时直接明文回填——不要再用「掩码值等于未修改」那套推断。
/// 主联系人开关不在这里：改主联系人只走 set-primary 端点。
struct EmergencyContactFormView: View {
    private enum Field: Hashable {
        case name
        case phone
    }

    @ObservedObject var viewModel: EmergencyContactsViewModel
    let contact: EmergencyContactResponse?
    /// 列表页「从通讯录添加」选中的人（#746）。有值时表单一打开就是填好的。
    var initialPick: ContactPhonePick?
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
    /// 从「关系」选择页退回来时 `onAppear` 会再跑一次，不挡的话会把改到一半的值重置回去（#746）。
    @State private var hasLoaded = false

    private var isEditing: Bool { contact != nil }

    private var smsNotice: String { isEditing ? Self.editSmsNotice : Self.addSmsNotice }

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
                    EmergencyContactActionRowLabel(
                        title: pickButtonTitle,
                        systemImage: "person.crop.circle.fill",
                        tint: AppColors.primary,
                        isEnabled: !viewModel.isMutating
                    )
                }
                .disabled(viewModel.isMutating)
                .accessibilityLabel(pickButtonTitle)
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
            }

            Section {
                EmergencyContactLabelledField(title: "姓名") {
                    TextField("必填", text: $name)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .phone }
                        .accessibilityLabel("联系人姓名，必填")
                        .accessibilityHint("请输入紧急联系人姓名")
                }

                EmergencyContactLabelledField(title: "手机号") {
                    TextField("11 位手机号", text: $phone)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .phone)
                        .accessibilityLabel("联系人手机号，必填，11 位")
                        .accessibilityHint("请输入紧急联系人手机号，只能输入数字")
                        .onChange(of: phone) { newValue in
                            let normalized = EmergencyContactsViewModel.normalizedPhoneInput(newValue)
                            if normalized != newValue { phone = normalized }
                        }
                }

                relationshipRow
            } footer: {
                Text(smsNotice)
                    .font(AppFonts.body())
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
                if focusedField == .name {
                    Button("下一项") { focusedField = .phone }
                        .accessibilityHint("跳到下一个输入框")
                } else {
                    Button("完成") { focusedField = nil }
                        .accessibilityLabel("收起键盘")
                }
            }
        }
        .onAppear {
            guard !hasLoaded else { return }
            hasLoaded = true
            if let contact {
                name = contact.name ?? ""
                // 后端 v1.5.0 起返回明文，直接明文回填。
                phone = contact.phone ?? ""
                relationship = contact.relationship ?? ""
            } else {
                makePrimary = viewModel.contacts.isEmpty
            }
            speakIntro()
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
}

// 关系行、保存、选择器回填这几个动作放在扩展里：结构体本身已到 SwiftLint 的 type_body_length 上限（250 行）。
// 同一文件里的扩展照样能访问上面的 `private` 状态。静态文案与纯函数在 `EmergencyContactFormCopy.swift`。
extension EmergencyContactFormView {
    /// 关系一行推进选择页（#746）：右边是当前值，没选时灰字「未填写」。
    private var relationshipRow: some View {
        let value = EmergencyContactRelationship.displayValue(for: relationship)
        return NavigationLink {
            EmergencyContactRelationshipPicker(relationship: $relationship)
        } label: {
            HStack(spacing: AppSpacing.medium) {
                Text("关系")
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                Spacer(minLength: AppSpacing.small)
                Text(value)
                    .font(AppFonts.body())
                    .foregroundColor(relationship.trimmed.isEmpty ? AppColors.textSecondary : AppColors.primary)
                    .multilineTextAlignment(.trailing)
            }
            .frame(minHeight: AppTouchTarget.blindPrimary)
        }
        // 标签直接挂在 NavigationLink 上：它本身就是一个按钮元素，再套一层 `.ignore` 有吞掉读屏双击的风险。
        .accessibilityLabel("与联系人的关系，\(value)")
        .accessibilityHint("选填。打开列表选择关系")
        .accessibilityIdentifier("emergencyContactRelationshipRow")
    }

    /// 动作成功才关页：失败时用户留在这里看到原因。
    private func perform(_ action: @escaping @MainActor (EmergencyContactResponse) async -> Bool) {
        guard let contact else { return }
        Task {
            if await action(contact) {
                onFinish()
            } else {
                showActionFailure = true
            }
        }
    }

    private var pickButtonTitle: String { initialPick == nil ? "从通讯录选择" : "换一位联系人" }

    /// 开场只说一句：两次 speak 时后一句会切断前一句（记忆 later-speak-silently-cuts-the-earlier-one）。
    /// 列表页直接选人进来时，把「选了谁」并进开场白。
    private func speakIntro() {
        guard let initialPick else {
            speechService.speak(
                "\(isEditing ? "编辑紧急联系人" : "新增紧急联系人")。可以从通讯录选择，也可以手动输入。姓名和手机号必填，关系选填。\(smsNotice)"
            )
            return
        }
        let picked = fill(from: initialPick)
        let intro = "新增紧急联系人。\(picked.notice)关系选填。\(smsNotice)"
        if picked.isValidPhone {
            speechService.speak(intro)
        } else {
            speechService.speakError(intro)
        }
    }

    /// 把选中的人填进表单，返回要说的那一句。这里不朗读，由调用方决定怎么说。
    @discardableResult
    private func fill(from pick: ContactPhonePick) -> PickedFields {
        let picked = Self.pickedFields(pick)
        if let pickedName = picked.name { name = pickedName }
        phone = picked.phone
        pickNotice = picked.notice
        localErrorMessage = nil
        if !picked.isValidPhone { focusedField = .phone }
        return picked
    }

    private func applyPick(_ pick: ContactPhonePick) {
        let picked = fill(from: pick)
        if picked.isValidPhone {
            speechService.speak(picked.notice)
        } else {
            speechService.speakError(picked.notice)
        }
    }

    /// 校验没过时把焦点放到出问题的那一格，免得读屏用户从头找。
    /// 按校验规则本身判，不按提示文案判：顺序与 `EmergencyContactsViewModel.validationMessage` 相同。
    /// 关系超长时没有输入框可放焦点（它在选择页里），返回 `nil`；原因已经上屏并朗读。
    private var firstInvalidField: Field? {
        let trimmedName = name.trimmed
        if trimmedName.isEmpty || trimmedName.count > EmergencyContactRules.maxNameLength { return .name }
        if !AppState.isValidMainlandPhone(phone.trimmed) { return .phone }
        return nil
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
