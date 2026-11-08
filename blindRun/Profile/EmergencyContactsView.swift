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
    /// 读列表的状态（#866）。读到过之后刷新失败停在 `.loaded`（页面规则），见 `failLoad`。
    @Published private(set) var listState: AsyncLoadState<[EmergencyContactResponse]> = .idle
    /// 进页时 `AppState` 里的缓存，服务端列表到手前先显示它。
    @Published private(set) var cachedContacts: [EmergencyContactResponse] = []
    private var listGeneration = 0
    @Published var isMutating = false
    @Published var errorMessage: String?
    @Published private(set) var statusMessage: String?
    var contacts: [EmergencyContactResponse] { listState.value ?? cachedContacts }
    var isLoading: Bool { listState.isLoading }
    /// 这一页从服务端拿到过列表没有。没拿到时 `contacts` 为空不代表真的一位都没有（弱网 load 失败、缓存为空）。
    var hasLoadedFromServer: Bool { listState.value != nil }

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
        if cachedContacts.isEmpty {
            cachedContacts = appState.emergencyContacts
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

    /// 确认过一位联系人都没有：新增的这位会是主联系人。只看本地 `contacts.isEmpty` 会在列表没加载到时误判，
    /// 发出 `isPrimary: true` 把服务端原来的主联系人顶掉（#807 审查）。
    var isKnownToHaveNoContacts: Bool { hasLoadedFromServer && contacts.isEmpty }

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
            failLoad("用户未登录，请重新登录后再试。")
            return
        }
        let previous = listState
        if previous.value == nil { listState = .loading(requestID: UUID()) }
        errorMessage = nil
        do {
            try await refreshContacts(appState: appState, userId: userId)
        } catch let error as APIError {
            if appState.handleAuthenticatedAPIError(error) { listState = previous; return }
            failLoad(Self.displayMessage(for: error))
        } catch {
            failLoad(Self.loadFailure)
        }
    }

    static let loadFailure = "加载紧急联系人失败，请重试。"

    /// 屏幕上一位都没有时失败由 `RemoteContent` 显示并朗读，不弹窗（免得念两遍）；有内容时保留内容，弹窗 + 朗读。
    private func failLoad(_ message: String) {
        if listState.value == nil { listState = .failed(message: message) }
        if contacts.isEmpty { errorMessage = nil; statusMessage = nil } else { fail(with: message) }
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
        // 第一位联系人必定是主联系人，后端也会强制。列表没从服务端拿到时不替它判，交给后端。
        let isPrimary = makePrimary || isKnownToHaveNoContacts
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

        announce(successMessage, summary: listSummary)
        return true
    }

    /// 后发的读取为准：首次读取还没回来时又做了变更，变更后刷新到的新列表不能被慢的那次旧结果盖掉。
    private func refreshContacts(appState: AppState, userId: Int64) async throws {
        listGeneration += 1
        let generation = listGeneration
        let latest = try await appState.profile.emergencyContacts(userId: userId)
        guard generation == listGeneration || listState.value == nil else { return }
        listState = .loaded(latest)
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

    /// 屏幕上只留结果那一句：概览行就在它正上方，再显示一遍概览就是同一段话印两次（#746 改版前的样子）。
    /// 朗读仍是「结果 + 概览」，读屏用户听不到上一行。
    private func announce(_ message: String, summary: String) {
        errorMessage = nil
        statusMessage = message
        speechService?.announce("\(message)\(summary)")
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
///
/// 版式照苹果「健康 › 医疗急救卡」的紧急联系人（#746）：概览一组、联系人一组、添加一组。
/// 添加的主路径是「从通讯录添加」—— 点了直接弹系统通讯录，选完进一页确认，按「添加」就存好（#807）
/// （苹果官方步骤：点「添加紧急联系人」→ 选一位联系人 → 选关系，support.apple.com/105072）。
struct EmergencyContactsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @StateObject private var viewModel = EmergencyContactsViewModel()
    @State private var editingTarget: EmergencyContactEditTarget?
    @State private var showContactPicker = false

    var body: some View {
        List {
            Section {
                Text(viewModel.listSummary)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, AppSpacing.xSmall)
                    .accessibilityLabel(viewModel.listSummary)

                // 成功提示跟着概览走：它俩说的是同一件事（当前状态），排在页首才有机会被看见。
                if let statusMessage = viewModel.statusMessage {
                    Label(statusMessage, systemImage: "checkmark.circle.fill")
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.success)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(statusMessage)
                }

                Button {
                    viewModel.repeatStatus()
                } label: {
                    EmergencyContactActionRowLabel(
                        title: "重复当前状态",
                        systemImage: "speaker.wave.2.fill",
                        tint: AppColors.primary,
                        isEnabled: true
                    )
                }
                .accessibilityLabel("重复当前状态")
                .accessibilityHint("再次朗读紧急联系人数量和主联系人")
            }

            if let primary = viewModel.primaryContact {
                // 主联系人单独一组 + 实心头像（负责人 2026-11-05 选的折中，#746）。组标题已经说了它是谁，行里不再写字。
                // 没有唯一主联系人（加载中、空列表、后端数据异常）时走下面的单组写法，联系人一个不漏。
                Section {
                    contactRow(primary)
                } header: {
                    groupHeader("主联系人")
                }
                Section {
                    ForEach(viewModel.contacts.filter { $0.id != primary.id }) { contact in
                        contactRow(contact)
                    }
                    addRows
                } header: {
                    groupHeader("其他联系人")
                } footer: {
                    addLimitFooter
                }
            } else {
                Section {
                    if viewModel.contacts.isEmpty {
                        RemoteContent(viewModel.listState, loadingLabel: "正在加载紧急联系人",
                                      failureIdentifier: "emergencyContactsRetryButton",
                                      retry: { Task { await viewModel.load() } }) { _ in
                            Text("还没有紧急联系人，请至少添加一位。")
                                .accessibilityLabel("还没有紧急联系人，请至少添加一位")
                        }
                    } else {
                        ForEach(viewModel.contacts) { contact in
                            contactRow(contact)
                        }
                    }
                    // 照医疗急救卡：添加行是联系人这一组的最后几行，不另起一组（也就少一个组标题要念）。
                    addRows
                } header: {
                    groupHeader("紧急联系人（\(viewModel.contactCount) / \(EmergencyContactRules.maxCount)）\u{202F}") // 全角「）」后补窄空格防判截断
                } footer: {
                    addLimitFooter
                }
            }
        }
        .listStyle(.insetGrouped)
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
        // 新增、编辑都推进一页，不再弹出层（#807）：返回就是取消，页内不必再找「取消」。
        // iOS 16 没有 `navigationDestination(item:)`，用 isPresented 包一层。
        .navigationDestination(isPresented: editingBinding) {
            editingDestination
        }
        .alert("紧急联系人提示", isPresented: failureAlertBinding) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    /// 两行都是整行按钮：「从通讯录添加」在前（能选就别打），「手动输入」在后。
    /// 满 5 位时两行一起禁用，原因写在组脚注里，同时进两行的读屏提示。
    @ViewBuilder
    private var addRows: some View {
        Button {
            showContactPicker = true
        } label: {
            EmergencyContactActionRowLabel(
                title: "从通讯录添加",
                systemImage: "plus.circle.fill",
                tint: AppColors.success,
                isEnabled: canStartAdding
            )
        }
        .disabled(!canStartAdding)
        .accessibilityLabel("从通讯录添加紧急联系人")
        .accessibilityHint(
            viewModel.addBlockedReason
                ?? "打开系统通讯录选一位联系人，自动填入姓名和手机号。助盲跑只拿到你选的这一位"
        )
        .accessibilityIdentifier("emergencyContactAddFromContacts")
        .background(
            ContactPhonePicker(isPresented: $showContactPicker) { pick in
                // 能直接添加的进确认页（一次确认就存好，#807）；号码不是手机号、没有名字的进手动表单，值已填好。
                editingTarget = EmergencyContactAddConfirmPage.canConfirm(pick) ? .confirm(pick) : .picked(pick)
            }
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        )

        Button {
            editingTarget = .new
        } label: {
            EmergencyContactActionRowLabel(
                title: "手动输入",
                systemImage: "keyboard",
                tint: AppColors.primary,
                isEnabled: canStartAdding
            )
        }
        .disabled(!canStartAdding)
        .accessibilityLabel("手动输入新增紧急联系人")
        .accessibilityHint(viewModel.addBlockedReason ?? "填写姓名和手机号后添加")
        .accessibilityIdentifier("emergencyContactAddManually")
    }

    /// 默认灰只有约 3.3:1，组标题统一压成 `textSecondary`。
    private func groupHeader(_ title: String) -> some View {
        Text(title).foregroundColor(AppColors.textSecondary)
    }

    @ViewBuilder
    private var addLimitFooter: some View {
        if let addBlockedReason = viewModel.addBlockedReason {
            Text(addBlockedReason)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(addBlockedReason)
        }
    }

    private var canStartAdding: Bool { viewModel.canAddContact && !viewModel.isMutating }

    /// 按返回退出新增 / 编辑页时，页内显示过的失败一并清掉，免得回到列表又弹一次。
    private var editingBinding: Binding<Bool> {
        Binding(
            get: { editingTarget != nil },
            set: { isPresented in
                guard !isPresented else { return }
                editingTarget = nil
                viewModel.isShowingFailure = false
            }
        )
    }

    @ViewBuilder
    private var editingDestination: some View {
        if case .confirm(let pick) = editingTarget {
            EmergencyContactAddConfirmPage(viewModel: viewModel, pick: pick) { added in
                if added { editingTarget = nil }
            }
        } else if let target = editingTarget {
            EmergencyContactFormView(
                viewModel: viewModel,
                contact: target.contact,
                initialPick: target.pick
            ) {
                editingTarget = nil
            }
        }
    }

    /// 新增 / 编辑页开着时不弹：被推进的页盖住的视图上呈现 alert 会被 SwiftUI 丢掉，
    /// 而那一页自己就把同一条 message 显示在页内，不会被挤出屏幕。
    ///
    /// 保存成功的回调不清 message：那条路径没有失败可清，白写一次 `@Published`。
    /// 用户按返回时由 `editingBinding` 清，失败已经显示在那一页里了。
    private var failureAlertBinding: Binding<Bool> {
        Binding(
            get: { editingTarget == nil && viewModel.isShowingFailure },
            set: { if !$0 { viewModel.isShowingFailure = false } }
        )
    }

    /// 行里只放内容，整行进编辑页；设为主联系人和删除都在编辑页里（#606）。
    /// Apple 通讯录式的「行 + 详情」：联系人多时列表仍然好扫读，空闲时间页也是这个写法（#481）。
    private func contactRow(_ contact: EmergencyContactResponse) -> some View {
        Button {
            editingTarget = .existing(contact)
        } label: {
            EmergencyContactRowLabel(contact: contact)
        }
        .disabled(viewModel.isMutating)
        .accessibilityLabel(viewModel.accessibilityLabel(for: contact))
        .accessibilityHint(contact.isPrimary == true ? "修改资料或删除" : "修改资料、设为主联系人或删除")
    }
}

// MARK: - Edit Target

enum EmergencyContactEditTarget: Identifiable {
    case new
    /// 从列表页的「从通讯录添加」选中、但不能直接添加的人（号码不是手机号、没有名字）：手动表单打开时已填好。
    case picked(ContactPhonePick)
    /// 从通讯录选中、可以直接添加的人：进 `EmergencyContactAddConfirmPage`（#807）。
    case confirm(ContactPhonePick)
    case existing(EmergencyContactResponse)

    var id: Int64 {
        switch self {
        case .new: return -1
        case .picked: return -2
        case .confirm: return -3
        case .existing(let contact): return contact.id
        }
    }

    var contact: EmergencyContactResponse? {
        if case .existing(let contact) = self { return contact }
        return nil
    }

    var pick: ContactPhonePick? {
        if case .picked(let pick) = self { return pick }
        return nil
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
