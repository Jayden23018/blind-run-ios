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

    /// 失败反馈的弹窗开关。
    ///
    /// 失败**必须自己弹出来**。它此前唯一的展示面是列表最末尾的一个 `Section`，而联系人到 4 位时
    /// 「新增」入口就已经被顶出屏幕（`blindRunUITests.swift` 的 `addContact` 注释记的就是这件事），
    /// 排在它后面的失败行只会更靠下 —— SwiftUI 的 `List` 压根不渲染屏幕外的行，于是「删除主联系人
    /// 被拦下」在屏幕上一个字都不多，只有 `speakError` 那一声。明眼志愿者与低视力用户拿到的
    /// 就是「点了没反应」。同形状的缺陷在账号删除预检那里已经修过一次
    /// （`AccountDeletionViewModel.isShowingPreflightBlock`，`AppState.swift`）。
    ///
    /// 成功的 `statusMessage` **刻意不弹**：那条只是补充确认，列表本身已经变了、`announce`
    /// 也播过，每次保存成功都弹一次等于给盲人多加一次「知道了」。它改成排在页首的概览行旁边。
    var isShowingFailure: Bool {
        get { errorMessage != nil }
        set { if !newValue { errorMessage = nil } }
    }

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
        operation: @escaping @MainActor (AppState, Int64) async throws -> Void
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

    var body: some View {
        List {
            Section {
                Text(viewModel.listSummary)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityLabel(viewModel.listSummary)

                // 成功提示跟着概览走：它俩说的是同一件事（当前状态），排在页首才有机会被看见。
                if let statusMessage = viewModel.statusMessage {
                    Text(statusMessage)
                        .font(AppFonts.body())
                        .accessibilityLabel(statusMessage)
                }

                Button {
                    viewModel.repeatStatus()
                } label: {
                    contactsActionLabel("重复当前状态", systemImage: "speaker.wave.2")
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
                Text("紧急联系人（\(viewModel.contactCount) / \(EmergencyContactRules.maxCount)）\u{202F}").foregroundColor(AppColors.textSecondary) // 默认灰只有约 3.3:1；全角「）」后补窄空格防判截断
            }

            Section {
                Button {
                    editingTarget = .new
                } label: {
                    contactsActionLabel("新增紧急联系人", systemImage: "plus", isEnabled: viewModel.canAddContact)
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
        .alert("紧急联系人提示", isPresented: failureAlertBinding) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    /// 表单以 sheet 呈现时不弹：被 sheet 盖住的视图上呈现 alert 会被 SwiftUI 丢掉，
    /// 而表单自己就把同一条 message 显示在它那张三段式短表里，不会被挤出屏幕。
    ///
    /// 保存成功的回调不清 message：那条路径没有失败可清，白写一次 `@Published`。
    /// 用户按「取消」时由表单自己清，失败已经显示在表单里了。
    private var failureAlertBinding: Binding<Bool> {
        Binding(
            get: { editingTarget == nil && viewModel.isShowingFailure },
            set: { if !$0 { viewModel.isShowingFailure = false } }
        )
    }

    private func contactsActionLabel(_ title: String, systemImage: String, isEnabled: Bool = true) -> some View {
        HStack(spacing: AppSpacing.small) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(title)
                .font(AppFonts.body().weight(.semibold))
            Spacer(minLength: 0)
        }
        // 写死颜色后系统不再把禁用态变灰，要自己分开。
        .foregroundColor(isEnabled ? AppColors.primary : AppColors.textSecondary)
        .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// 行里只放内容，整行进编辑页；设为主联系人和删除都在编辑页里（#606）。
    /// Apple 通讯录式的「行 + 详情」：联系人多时列表仍然好扫读，空闲时间页也是这个写法（#481）。
    private func contactRow(_ contact: EmergencyContactResponse) -> some View {
        Button {
            editingTarget = .existing(contact)
        } label: {
            HStack(spacing: AppSpacing.small) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(contact.name?.nilIfBlank ?? "未命名联系人")
                            .font(.headline)
                            .foregroundColor(AppColors.textPrimary)
                        if contact.isPrimary == true {
                            Text("主联系人")
                                .font(AppFonts.caption())
                                .foregroundColor(AppColors.primary)
                        }
                    }
                    Text(contactDetailLine(contact))
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(AppFonts.caption().weight(.semibold))
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: .leading)
            .contentShape(Rectangle())
        }
        .disabled(viewModel.isMutating)
        .accessibilityLabel(viewModel.accessibilityLabel(for: contact))
        .accessibilityHint(contact.isPrimary == true ? "修改资料或删除" : "修改资料、设为主联系人或删除")
    }

    private func contactDetailLine(_ contact: EmergencyContactResponse) -> String {
        let phone = contact.maskedPhone ?? "未填写手机号"
        guard let relationship = contact.relationship?.nilIfBlank else { return phone }
        return "\(phone) · \(relationship)"
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

#if DEBUG
#Preview {
    NavigationStack {
        EmergencyContactsView()
            .environmentObject(AppState())
            .environmentObject(SpeechService())
    }
}
#endif
