import Combine
import SwiftUI

// MARK: - Emergency Contacts ViewModel

/// 紧急联系人集合的唯一可变入口。
///
/// 契约要点（后端 `/api/users/{userId}/emergency-contacts`）：
/// - `DELETE` 与 `PUT .../set-primary` 都只返回空对象，**不返回列表**，
///   所以任何一次变更之后都必须重新 `GET` 整份列表再写回 `AppState`。
/// - 后端把「超过 5 个 / 少于 1 个 / 字段为空」全部抛成同一个 `BAD_REQUEST`，
///   只能靠中文 message 区分。因此客户端**先本地拦**（数量、必填、主联系人不变量），
///   本地拦不住时直接原样展示后端 message，不去解析 message 猜类型。
/// - 后端 `PUT .../{contactId}` 传 `isPrimary: false` 是无条件赋值，会把唯一主联系人变成 0 个。
///   所以更新请求一律原样回传当前 `isPrimary`，改主联系人只走 `set-primary` 端点。
@MainActor
final class EmergencyContactsViewModel: ObservableObject {
    @Published private(set) var contacts: [EmergencyContactResponse] = []
    @Published var isLoading = false
    @Published var isMutating = false
    @Published var errorMessage: String?
    @Published private(set) var statusMessage: String?

    private weak var appState: AppState?
    private var speechService: SpeechService?

    // MARK: Configuration

    func configure(with appState: AppState, speechService: SpeechService) {
        self.appState = appState
        self.speechService = speechService
        if contacts.isEmpty {
            contacts = appState.emergencyContacts
        }
    }

    // MARK: Derived state

    var contactCount: Int { contacts.count }

    var canAddContact: Bool { contacts.count < EmergencyContactRules.maxCount }

    /// 到达上限时「新增」按钮禁用的原因，同时用于展示和朗读。
    var addBlockedReason: String? {
        canAddContact
            ? nil
            : "已保存 \(EmergencyContactRules.maxCount) 位紧急联系人，达到上限。如需新增，请先删除一位。"
    }

    var primaryContact: EmergencyContactResponse? {
        EmergencyContactResponse.singlePrimary(in: contacts)
    }

    /// 「重复当前状态」朗读内容。
    var listSummary: String {
        guard !contacts.isEmpty else {
            return "当前没有紧急联系人。至少需要 \(EmergencyContactRules.minCount) 位，最多 \(EmergencyContactRules.maxCount) 位。"
        }
        let primaryText = primaryContact.map { "主联系人是\($0.name?.nilIfBlank ?? "未命名联系人")。" }
            ?? "当前没有唯一的主联系人，请先设置一位主联系人。"
        return "共 \(contacts.count) 位紧急联系人，最多 \(EmergencyContactRules.maxCount) 位。\(primaryText)"
    }

    func accessibilityLabel(for contact: EmergencyContactResponse) -> String {
        var parts = [contact.name?.nilIfBlank ?? "未命名联系人"]
        if let relationship = contact.relationship?.nilIfBlank {
            parts.append("关系\(relationship)")
        }
        parts.append("电话\(contact.maskedPhone ?? "未填写")")
        parts.append(contact.isPrimary == true ? "主联系人" : "非主联系人")
        return parts.joined(separator: "，")
    }

    /// 删除前置守卫：本地先拦，服务端错误再兜底。
    func deletionBlockedReason(for contact: EmergencyContactResponse) -> String? {
        if contacts.count <= EmergencyContactRules.minCount {
            return "至少需要保留 \(EmergencyContactRules.minCount) 位紧急联系人，不能删除最后一位。"
        }
        if contact.isPrimary == true {
            return "这是当前主联系人。请先把另一位设为主联系人，再删除这一位。"
        }
        return nil
    }

    /// 删除被本地守卫拦下时只展示 + 朗读原因，不发请求。
    func reportDeletionBlocked(_ contact: EmergencyContactResponse) {
        guard let reason = deletionBlockedReason(for: contact) else { return }
        fail(with: reason)
    }

    // MARK: Actions

    func load() async {
        guard let appState, let userId = appState.userId else {
            // 会话未就绪时必须显式失败并朗读，否则盲人用户面对的是一个毫无反馈的空页面。
            fail(with: "用户未登录，请重新登录后再试。")
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            try await refreshContacts(appState: appState, userId: userId)
        } catch let error as APIError {
            handle(error)
        } catch {
            errorMessage = "加载紧急联系人失败，请重试。"
        }
        isLoading = false
    }

    func create(
        name: String,
        phone: String,
        relationship: String,
        makePrimary: Bool
    ) async -> Bool {
        if let addBlockedReason {
            fail(with: addBlockedReason)
            return false
        }
        if let validationMessage = Self.validationMessage(name: name, phone: phone, relationship: relationship) {
            fail(with: validationMessage)
            return false
        }
        // 第一位联系人必定是主联系人，后端也会强制。
        let isPrimary = makePrimary || contacts.isEmpty
        let request = EmergencyContactRequest(
            name: name.trimmed,
            phone: phone.trimmed,
            relationship: relationship.trimmed.nilIfBlank,
            isPrimary: isPrimary
        )
        return await mutate(successMessage: "已添加紧急联系人\(name.trimmed)。") { appState, userId in
            _ = try await appState.profile.createEmergencyContact(userId: userId, request)
        }
    }

    func update(
        contact: EmergencyContactResponse,
        name: String,
        phone: String,
        relationship: String
    ) async -> Bool {
        if let validationMessage = Self.validationMessage(name: name, phone: phone, relationship: relationship) {
            fail(with: validationMessage)
            return false
        }
        // isPrimary 原样回传：后端对 false 是无条件赋值，改主联系人只走 set-primary。
        let request = EmergencyContactRequest(
            name: name.trimmed,
            phone: phone.trimmed,
            relationship: relationship.trimmed.nilIfBlank,
            isPrimary: contact.isPrimary ?? false
        )
        return await mutate(successMessage: "已更新紧急联系人\(name.trimmed)。") { appState, userId in
            _ = try await appState.profile.updateEmergencyContact(
                userId: userId,
                contactId: contact.id,
                request
            )
        }
    }

    @discardableResult
    func delete(_ contact: EmergencyContactResponse) async -> Bool {
        if let reason = deletionBlockedReason(for: contact) {
            fail(with: reason)
            return false
        }
        let name = contact.name?.nilIfBlank ?? "该联系人"
        return await mutate(successMessage: "已删除紧急联系人\(name)。") { appState, userId in
            try await appState.profile.deleteEmergencyContact(userId: userId, contactId: contact.id)
        }
    }

    @discardableResult
    func setPrimary(_ contact: EmergencyContactResponse) async -> Bool {
        guard contact.isPrimary != true else { return true }
        let name = contact.name?.nilIfBlank ?? "该联系人"
        return await mutate(successMessage: "已把\(name)设为主联系人。") { appState, userId in
            try await appState.profile.setPrimaryEmergencyContact(userId: userId, contactId: contact.id)
        }
    }

    func repeatStatus() {
        speechService?.speak(listSummary)
    }

    // MARK: Private

    /// 所有变更走同一条路径：本地已放行 -> 调用端点 -> 重新 GET 整份列表 -> 写回 AppState。
    /// 失败（含可恢复冲突）时保留当前列表，不清空、不局部改写。
    private func mutate(
        successMessage: String,
        operation: @escaping (AppState, Int64) async throws -> Void
    ) async -> Bool {
        guard let appState, let userId = appState.userId else {
            fail(with: "用户未登录，请重新登录后再试。")
            return false
        }
        guard !isMutating else { return false }
        isMutating = true
        errorMessage = nil
        defer { isMutating = false }

        do {
            try await operation(appState, userId)
        } catch let error as APIError {
            handle(error)
            return false
        } catch {
            fail(with: "操作失败，请重试。")
            return false
        }

        do {
            try await refreshContacts(appState: appState, userId: userId)
        } catch {
            // 变更已生效但列表没刷新到：保留旧列表，明确告诉用户需要重新加载。
            fail(with: "操作已提交，但联系人列表刷新失败，请下拉重新加载。")
            return true
        }

        announce("\(successMessage)\(listSummary)")
        return true
    }

    private func refreshContacts(appState: AppState, userId: Int64) async throws {
        let latest = try await appState.profile.emergencyContacts(userId: userId)
        contacts = latest
        appState.updateEmergencyContacts(latest)
    }

    private func handle(_ error: APIError) {
        if appState?.handleAuthenticatedAPIError(error) == true { return }
        fail(with: Self.displayMessage(for: error))
    }

    /// 后端把「超过 5 个 / 少于 1 个 / 字段为空」全部抛成同一个 `BAD_REQUEST`，
    /// `ErrorCode` 的通用文案会把它们抹平成同一句话，而上限和下限需要完全不同的后续动作。
    /// 所以这里优先原样展示后端 message，并且不去解析 message 猜类型。
    nonisolated static func displayMessage(for error: APIError) -> String {
        if case .serverError(let response) = error, !response.message.trimmed.isEmpty {
            return response.message
        }
        return error.localizedMessage
    }

    private func fail(with message: String) {
        errorMessage = message
        statusMessage = nil
        speechService?.speakError(message)
    }

    private func announce(_ message: String) {
        errorMessage = nil
        statusMessage = message
        speechService?.announce(message)
    }

    // MARK: Validation

    nonisolated static func normalizedPhoneInput(_ value: String) -> String {
        String(value.filter(\.isNumber).prefix(11))
    }

    static func validationMessage(
        name: String,
        phone: String,
        relationship: String
    ) -> String? {
        let name = name.trimmed
        if name.isEmpty { return "请填写联系人姓名。" }
        if name.count > EmergencyContactRules.maxNameLength {
            return "联系人姓名不能超过 \(EmergencyContactRules.maxNameLength) 个字。"
        }
        if !AppState.isValidMainlandPhone(phone.trimmed) { return "请输入正确的 11 位手机号。" }
        if relationship.trimmed.count > EmergencyContactRules.maxRelationshipLength {
            return "关系不能超过 \(EmergencyContactRules.maxRelationshipLength) 个字。"
        }
        return nil
    }
}

// MARK: - Emergency Contacts View

/// 紧急联系人管理页。始终由外层 `NavigationStack` 以 `NavigationLink` push 呈现
/// （资料页、设置页、引导流都在 `NavigationStack` 内）。
struct EmergencyContactsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @StateObject private var viewModel = EmergencyContactsViewModel()
    @State private var editingTarget: EmergencyContactEditTarget?
    @State private var pendingDeletion: EmergencyContactResponse?
    @State private var pendingPrimary: EmergencyContactResponse?

    var body: some View {
        List {
            Section {
                Text(viewModel.listSummary)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityLabel(viewModel.listSummary)

                Button("重复当前状态") {
                    viewModel.repeatStatus()
                }
                .accessibilityLabel("重复当前状态")
                .accessibilityHint("再次朗读紧急联系人数量和主联系人")
            }

            Section {
                if viewModel.isLoading && viewModel.contacts.isEmpty {
                    Text("正在加载紧急联系人…")
                        .accessibilityLabel("正在加载紧急联系人")
                } else if viewModel.contacts.isEmpty {
                    Text("还没有紧急联系人，请至少添加一位。")
                        .accessibilityLabel("还没有紧急联系人，请至少添加一位")
                } else {
                    ForEach(viewModel.contacts) { contact in
                        contactRow(contact)
                    }
                }
            } header: {
                Text("紧急联系人（\(viewModel.contactCount) / \(EmergencyContactRules.maxCount)）")
            }

            Section {
                Button("新增紧急联系人") {
                    editingTarget = .new
                }
                .disabled(!viewModel.canAddContact || viewModel.isMutating)
                .accessibilityLabel("新增紧急联系人")
                .accessibilityHint(viewModel.addBlockedReason ?? "填写姓名、手机号和关系后保存")

                if let addBlockedReason = viewModel.addBlockedReason {
                    Text(addBlockedReason)
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.textSecondary)
                        .accessibilityLabel(addBlockedReason)
                }
            }

            if let statusMessage = viewModel.statusMessage {
                Section {
                    Text(statusMessage)
                        .font(AppFonts.body())
                        .accessibilityLabel(statusMessage)
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.destructive)
                        .accessibilityLabel(errorMessage)
                }
            }
        }
        .navigationTitle("紧急联系人")
        .refreshable {
            await viewModel.load()
        }
        .task {
            // configure 必须先于 load：load 依赖注入进来的 appState。
            viewModel.configure(with: appState, speechService: speechService)
            speechService.speak("紧急联系人管理。\(viewModel.listSummary)")
            await viewModel.load()
        }
        .sheet(item: $editingTarget) { target in
            NavigationStack {
                EmergencyContactFormView(
                    viewModel: viewModel,
                    contact: target.contact
                ) {
                    editingTarget = nil
                }
            }
        }
        .alert("确认删除联系人", isPresented: deletionAlertBinding, presenting: pendingDeletion) { contact in
            Button("确认删除", role: .destructive) {
                Task { await viewModel.delete(contact) }
            }
            Button("取消", role: .cancel) {}
        } message: { contact in
            Text("将删除紧急联系人\(contact.name?.nilIfBlank ?? "该联系人")。删除后无法恢复，需要时请重新添加。")
        }
        .alert("确认设为主联系人", isPresented: primaryAlertBinding, presenting: pendingPrimary) { contact in
            Button("设为主联系人") {
                Task { await viewModel.setPrimary(contact) }
            }
            Button("取消", role: .cancel) {}
        } message: { contact in
            Text("紧急情况下会优先联系\(contact.name?.nilIfBlank ?? "该联系人")。原主联系人会自动变为普通联系人。")
        }
    }

    private var deletionAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    private var primaryAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingPrimary != nil },
            set: { if !$0 { pendingPrimary = nil } }
        )
    }

    @ViewBuilder
    private func contactRow(_ contact: EmergencyContactResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(contact.name?.nilIfBlank ?? "未命名联系人")
                        .font(.headline)
                    if contact.isPrimary == true {
                        Text("主联系人")
                            .font(AppFonts.caption())
                            .foregroundColor(AppColors.primary)
                    }
                }
                Text(contact.maskedPhone ?? "未填写手机号")
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                if let relationship = contact.relationship?.nilIfBlank {
                    Text("关系：\(relationship)")
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(viewModel.accessibilityLabel(for: contact))

            HStack(spacing: 16) {
                Button("编辑") {
                    editingTarget = .existing(contact)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("编辑\(contact.name?.nilIfBlank ?? "联系人")")
                .accessibilityHint("修改姓名、手机号或关系")

                if contact.isPrimary != true {
                    Button("设为主联系人") {
                        pendingPrimary = contact
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("把\(contact.name?.nilIfBlank ?? "联系人")设为主联系人")
                    .accessibilityHint("需要二次确认")
                }

                Button("删除", role: .destructive) {
                    if viewModel.deletionBlockedReason(for: contact) == nil {
                        pendingDeletion = contact
                    } else {
                        viewModel.reportDeletionBlocked(contact)
                    }
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("删除\(contact.name?.nilIfBlank ?? "联系人")")
                .accessibilityHint(viewModel.deletionBlockedReason(for: contact) ?? "危险操作，需要二次确认")
            }
            .disabled(viewModel.isMutating)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Edit Target

enum EmergencyContactEditTarget: Identifiable {
    case new
    case existing(EmergencyContactResponse)

    var id: Int64 {
        switch self {
        case .new: return -1
        case .existing(let contact): return contact.id
        }
    }

    var contact: EmergencyContactResponse? {
        switch self {
        case .new: return nil
        case .existing(let contact): return contact
        }
    }
}

// MARK: - Emergency Contact Form

/// 新增/编辑表单。
/// 后端返回明文手机号，编辑时直接明文回填——不要再用「掩码值等于未修改」那套推断。
/// 主联系人开关不在这里：改主联系人只走 set-primary 端点。
struct EmergencyContactFormView: View {
    @ObservedObject var viewModel: EmergencyContactsViewModel
    let contact: EmergencyContactResponse?
    let onFinish: () -> Void

    @EnvironmentObject private var speechService: SpeechService
    @State private var name = ""
    @State private var phone = ""
    @State private var relationship = ""
    @State private var makePrimary = false
    @State private var localErrorMessage: String?

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
                TextField("联系人姓名", text: $name)
                    .accessibilityLabel("联系人姓名，必填")
                    .accessibilityHint("请输入紧急联系人姓名")

                TextField("11 位手机号", text: $phone)
                    .keyboardType(.numberPad)
                    .accessibilityLabel("联系人手机号，必填，11 位")
                    .accessibilityHint("请输入紧急联系人手机号，只能输入数字")
                    .onChange(of: phone) { newValue in
                        let normalized = EmergencyContactsViewModel.normalizedPhoneInput(newValue)
                        if normalized != newValue { phone = normalized }
                    }

                TextField("关系，选填，例如家人", text: $relationship)
                    .accessibilityLabel("与联系人的关系，选填")
                    .accessibilityHint("例如家人、朋友、同事")
            } footer: {
                Text(smsNotice)
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
        }
        .navigationTitle(isEditing ? "编辑紧急联系人" : "新增紧急联系人")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { onFinish() }
                    .accessibilityLabel("取消")
                    .accessibilityHint("放弃本次修改并返回")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .disabled(viewModel.isMutating)
                    .accessibilityLabel("保存")
                    .accessibilityHint(validationMessage ?? "保存后会向该号码发送一条告知短信")
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
                "\(isEditing ? "编辑紧急联系人" : "新增紧急联系人")。姓名和手机号必填，关系选填。\(smsNotice)"
            )
        }
    }

    private func save() {
        if let validationMessage {
            localErrorMessage = validationMessage
            speechService.speakError(validationMessage)
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

#if DEBUG
#Preview {
    NavigationStack {
        EmergencyContactsView()
            .environmentObject(AppState())
            .environmentObject(SpeechService())
    }
}
#endif
