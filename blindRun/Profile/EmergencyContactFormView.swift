import SwiftUI

// MARK: - Emergency Contact Form

/// 新增/编辑表单。
/// 后端返回明文手机号，编辑时直接明文回填——不要再用「掩码值等于未修改」那套推断。
/// 主联系人开关不在这里：改主联系人只走 set-primary 端点。
///
/// #807（负责人 2026-11-06）：「从通讯录选择」和手动输入分开。通讯录选人走 `EmergencyContactAddConfirmPage`，
/// 这里的新增态只剩姓名、手机号两格；关系与「设为主联系人」都到编辑态再改。
/// 页面由列表页 push 进来，「保存 / 添加」在底部，返回 = 不保存（工具栏文字按钮过不了审计，也够不到 64pt）。
struct EmergencyContactFormView: View {
    private enum Field: Hashable {
        case name
        case phone
    }

    @ObservedObject var viewModel: EmergencyContactsViewModel
    let contact: EmergencyContactResponse?
    /// 通讯录里选中的人不能直接添加（号码不是手机号、没有名字）时，列表页把他带进来，表单一打开就是填好的。
    var initialPick: ContactPhonePick?
    let onFinish: () -> Void

    @EnvironmentObject private var speechService: SpeechService
    @State private var name = ""
    @State private var phone = ""
    @State private var relationship = ""
    @State private var localErrorMessage: String?
    /// 确认弹窗必须挂在表单上，挂在被它盖住的列表页上的 alert 不会出来。
    @State private var showDeleteConfirmation = false
    @State private var showPrimaryConfirmation = false
    /// 这两个动作的按钮在表单最下面，错误文字在它上方，大字号时已滚出屏幕，`Form` 不渲染屏幕外的行。
    /// 所以失败要自己弹出来。
    @State private var showActionFailure = false
    /// 带着通讯录选中的人进来时那一句，同时上屏和朗读（#657 B-10）。
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
                if let pickNotice {
                    Text(pickNotice)
                        .font(AppFonts.formRow())
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(pickNotice)
                        .accessibilityIdentifier("emergencyContactPickNotice")
                        .padding(.vertical, AppSpacing.medium)
                        .emergencyFormRow()
                }

                EmergencyContactLabelledField(title: "姓名") {
                    TextField("必填", text: $name)
                        .font(AppFonts.formRow())
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .phone }
                        .accessibilityLabel("联系人姓名，必填")
                        .accessibilityHint("请输入紧急联系人姓名")
                }

                EmergencyContactLabelledField(title: "手机号") {
                    TextField("11 位手机号", text: $phone)
                        .font(AppFonts.formRow())
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .phone)
                        .accessibilityLabel("联系人手机号，必填，11 位")
                        .accessibilityHint("请输入紧急联系人手机号，只能输入数字")
                        .onChange(of: phone) { newValue in
                            let normalized = EmergencyContactsViewModel.normalizedPhoneInput(newValue)
                            if normalized != newValue { phone = normalized }
                        }
                }

                // 关系只在编辑态出现：新增只填必填的两项（#807）。
                if isEditing {
                    relationshipRow
                }
            } footer: {
                Text(smsNotice)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(smsNotice)
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
        .safeAreaInset(edge: .bottom) { saveBar }
        .navigationTitle(isEditing ? "编辑紧急联系人" : Self.addTitle)
        .navigationBarTitleDisplayMode(.inline)
        // 二级页藏标签栏，底部按钮才贴得到屏幕底（记忆 tab-bar-clips-the-last-line-of-secondary-pages）。
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
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

    /// 贴底的「添加 / 保存」。底色同 `Form` 的分组底，滚到它后面的行不会被半透明栏压成低对比度。
    private var saveBar: some View {
        PrimaryButton(isEditing ? "保存" : EmergencyContactAddConfirmPage.addButtonTitle, isLoading: viewModel.isMutating) {
            save()
        }
        .accessibilityHint(Self.saveHint(isEditing: isEditing, validationMessage: validationMessage))
        .accessibilityIdentifier("emergencyContactFormSave")
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(uiColor: .systemGroupedBackground))
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
        Section {
            if contact.isPrimary != true {
                Button {
                    showPrimaryConfirmation = true
                } label: {
                    contactActionLabel("设为主联系人", color: AppColors.primary)
                }
                .disabled(viewModel.isMutating)
                .accessibilityLabel("把\(displayName)设为主联系人")
                .accessibilityHint("需要二次确认")
                .emergencyFormRow()
            }

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
            .emergencyFormRow()
        }
    }

    private func contactActionLabel(_ title: String, color: Color) -> some View {
        Text(title)
            .font(AppFonts.formRow().weight(.semibold))
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
                    .font(AppFonts.formRow())
                    .foregroundColor(AppColors.textPrimary)
                Spacer(minLength: AppSpacing.small)
                Text(value)
                    .font(AppFonts.formRow())
                    .foregroundColor(relationship.trimmed.isEmpty ? AppColors.textSecondary : AppColors.primary)
                    .multilineTextAlignment(.trailing)
            }
            .frame(minHeight: AppTouchTarget.blindPrimary)
        }
        .emergencyFormRow()
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

    /// 开场只说一句：两次 speak 时后一句会切断前一句（记忆 later-speak-silently-cuts-the-earlier-one）。
    /// 通讯录选中的人不能直接添加、被带进这里时，把「选了谁、哪里不对」并进开场白。
    private func speakIntro() {
        guard let initialPick else {
            let fields = isEditing ? "姓名和手机号必填，关系选填。" : "填写姓名和手机号。"
            speechService.speak("\(isEditing ? "编辑紧急联系人" : Self.addTitle)。\(fields)\(smsNotice)")
            return
        }
        let picked = fill(from: initialPick)
        speechService.speakError("\(Self.addTitle)。\(picked.notice)\(smsNotice)")
    }

    /// 把选中的人填进表单，返回要说的那一句。这里不朗读，由调用方决定怎么说。
    @discardableResult
    private func fill(from pick: ContactPhonePick) -> PickedFields {
        let picked = Self.pickedFields(pick)
        if let pickedName = picked.name { name = pickedName }
        phone = picked.phone
        pickNotice = picked.notice
        localErrorMessage = nil
        if !picked.isValidPhone {
            focusedField = .phone
        } else if picked.name == nil {
            focusedField = .name
        }
        return picked
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
                    relationship: "",
                    // 不给开关（#807）：第一位自动是主联系人，后面的人到编辑页自己设。
                    makePrimary: viewModel.contacts.isEmpty
                )
            }
            if success { onFinish() }
        }
    }
}
