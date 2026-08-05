import XCTest
@testable import blindRun

/// 第 4 组（Emergency Contact Management）的最小可运行检查：
/// 数量上限/下限、主联系人不变量、删除前置守卫、变更后列表完整性、可恢复冲突不写坏本地列表。
@MainActor
final class EmergencyContactsViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeContact(
        id: Int64,
        name: String,
        phone: String = "13800138000",
        isPrimary: Bool = false
    ) -> EmergencyContactResponse {
        EmergencyContactResponse(
            id: id,
            name: name,
            phone: phone,
            relationship: nil,
            isPrimary: isPrimary
        )
    }

    private func makeViewModel(
        contacts: [EmergencyContactResponse]
    ) -> (EmergencyContactsViewModel, AppState, ContactsAPIClientStub) {
        let client = ContactsAPIClientStub(contacts: contacts)
        let appState = AppState(apiClient: client, tokenStore: ContactsInMemoryTokenStore())
        appState.userId = 7
        appState.updateEmergencyContacts(contacts)
        let viewModel = EmergencyContactsViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())
        return (viewModel, appState, client)
    }

    // MARK: - Count limits

    func testAddIsBlockedLocallyWhenFiveContactsExist() async {
        let contacts = (1...5).map { makeContact(id: Int64($0), name: "联系人\($0)", isPrimary: $0 == 1) }
        let (viewModel, appState, client) = makeViewModel(contacts: contacts)

        XCTAssertFalse(viewModel.canAddContact)
        XCTAssertNotNil(viewModel.addBlockedReason)

        let created = await viewModel.create(
            name: "第六位",
            phone: "13900139000",
            relationship: "",
            makePrimary: false
        )

        XCTAssertFalse(created)
        XCTAssertTrue(client.requests.isEmpty, "达到上限时不应该发出创建请求")
        XCTAssertEqual(viewModel.contacts.count, 5)
        XCTAssertEqual(appState.emergencyContactCount, 5)
        XCTAssertEqual(viewModel.errorMessage, viewModel.addBlockedReason)
    }

    func testDeletingTheOnlyContactIsBlockedLocally() async {
        let contact = makeContact(id: 1, name: "唯一联系人", isPrimary: true)
        let (viewModel, appState, client) = makeViewModel(contacts: [contact])

        XCTAssertNotNil(viewModel.deletionBlockedReason(for: contact))

        let deleted = await viewModel.delete(contact)

        XCTAssertFalse(deleted)
        XCTAssertTrue(client.requests.isEmpty, "只剩一位时不应该发出删除请求")
        XCTAssertEqual(viewModel.contacts.count, 1)
        XCTAssertEqual(appState.emergencyContactCount, 1)
    }

    // MARK: - Primary invariant

    func testDeletingCurrentPrimaryRequiresAnotherPrimaryFirst() async {
        let primary = makeContact(id: 1, name: "主联系人", isPrimary: true)
        let other = makeContact(id: 2, name: "备用联系人")
        let (viewModel, _, client) = makeViewModel(contacts: [primary, other])

        XCTAssertNotNil(viewModel.deletionBlockedReason(for: primary))
        XCTAssertNil(viewModel.deletionBlockedReason(for: other))

        let deleted = await viewModel.delete(primary)

        XCTAssertFalse(deleted)
        XCTAssertTrue(client.requests.isEmpty)
    }

    func testUpdateReplaysCurrentPrimaryFlagInsteadOfClearingIt() async {
        let primary = makeContact(id: 1, name: "主联系人", isPrimary: true)
        let (viewModel, appState, client) = makeViewModel(contacts: [primary])

        let updated = await viewModel.update(
            contact: primary,
            name: "主联系人改名",
            phone: "13900139000",
            relationship: "家人"
        )

        XCTAssertTrue(updated)
        // 后端对 isPrimary=false 是无条件赋值，会把唯一主联系人清成 0 个。
        XCTAssertEqual(client.capturedUpdate?.isPrimary, true)
        XCTAssertEqual(appState.primaryEmergencyContact?.id, 1)
        XCTAssertTrue(appState.hasExactlyOnePrimaryEmergencyContact)
    }

    func testSetPrimaryRefetchesCompleteListBecauseEndpointReturnsEmptyObject() async {
        let first = makeContact(id: 1, name: "主联系人", isPrimary: true)
        let second = makeContact(id: 2, name: "备用联系人")
        let (viewModel, appState, client) = makeViewModel(contacts: [first, second])

        let changed = await viewModel.setPrimary(second)

        XCTAssertTrue(changed)
        XCTAssertEqual(
            client.requests.last?.path,
            "/api/users/7/emergency-contacts",
            "set-primary 只返回空对象，必须紧跟一次完整列表 GET"
        )
        XCTAssertEqual(client.requests.last?.method, .get)
        XCTAssertEqual(viewModel.contacts.count, 2)
        XCTAssertEqual(appState.primaryEmergencyContact?.id, 2)
    }

    // MARK: - Complete list preservation

    func testCreateWritesTheCompleteServerListBackToAppState() async {
        let existing = [
            makeContact(id: 1, name: "主联系人", isPrimary: true),
            makeContact(id: 2, name: "备用联系人")
        ]
        let (viewModel, appState, _) = makeViewModel(contacts: existing)

        let created = await viewModel.create(
            name: "第三位",
            phone: "13700137000",
            relationship: "同事",
            makePrimary: false
        )

        XCTAssertTrue(created)
        // 变更端点的返回体不是列表，必须回写重新 GET 到的整份列表，而不是只追加新建那一条。
        XCTAssertEqual(viewModel.contacts.map(\.id), [1, 2, 3])
        XCTAssertEqual(appState.emergencyContacts.map(\.id), [1, 2, 3])
        XCTAssertEqual(appState.primaryEmergencyContact?.id, 1)
    }

    func testListRefreshFailureAfterMutationKeepsThePreviousCompleteList() async {
        let existing = [
            makeContact(id: 1, name: "主联系人", isPrimary: true),
            makeContact(id: 2, name: "备用联系人")
        ]
        let (viewModel, appState, client) = makeViewModel(contacts: existing)
        client.failNextRefresh = true

        let changed = await viewModel.setPrimary(existing[1])

        XCTAssertTrue(changed, "变更已经在服务端生效，不能报告成失败")
        XCTAssertEqual(viewModel.contacts.map(\.id), [1, 2])
        XCTAssertEqual(appState.emergencyContacts.map(\.id), [1, 2])
        XCTAssertEqual(viewModel.errorMessage, "操作已提交，但联系人列表刷新失败，请下拉重新加载。")
    }

    // MARK: - Masked display vs. plain-text edits

    func testUpdateSendsTheFullPlainPhoneInsteadOfTheMaskedValue() async {
        let contact = makeContact(id: 1, name: "主联系人", phone: "13800138000", isPrimary: true)
        // ViewModel 只弱引用 AppState，这里必须持有到断言结束：
        // 丢弃它会让 mutate() 走「用户未登录」分支，请求根本发不出去，测的就不是手机号了。
        let (viewModel, appState, client) = makeViewModel(contacts: [contact])

        let updated = await viewModel.update(
            contact: contact,
            name: "主联系人",
            phone: "13900139000",
            relationship: ""
        )

        XCTAssertTrue(updated)
        // 后端 phone 必填，「掩码值等于未修改」的老技巧已废弃。
        XCTAssertEqual(client.capturedUpdate?.phone, "13900139000")
        XCTAssertEqual(appState.emergencyContacts.first?.phone, "13900139000")
    }

    func testContactAnnouncementUsesTheMaskedPhoneNotThePlainNumber() {
        let contact = makeContact(id: 1, name: "主联系人", phone: "13800138000", isPrimary: true)
        let (viewModel, _, _) = makeViewModel(contacts: [contact])

        let label = viewModel.accessibilityLabel(for: contact)

        XCTAssertTrue(label.contains("138****8000"))
        XCTAssertFalse(label.contains("13800138000"), "VoiceOver 不得读出完整手机号")
        XCTAssertTrue(label.contains("主联系人"))
    }

    // MARK: - Recoverable conflicts

    func testRecoverableServerConflictKeepsLocalListIntactAndShowsServerMessage() async {
        let first = makeContact(id: 1, name: "主联系人", isPrimary: true)
        let second = makeContact(id: 2, name: "备用联系人")
        let (viewModel, appState, client) = makeViewModel(contacts: [first, second])
        client.errorForNextMutation = APIError.serverError(
            ErrorResponse(code: "BAD_REQUEST", message: "最多只能保存 5 位紧急联系人。")
        )

        let created = await viewModel.create(
            name: "新联系人",
            phone: "13700137000",
            relationship: "",
            makePrimary: false
        )

        XCTAssertFalse(created)
        // 后端把上限/下限/字段为空挤进同一个 BAD_REQUEST，必须原样展示 message。
        XCTAssertEqual(viewModel.errorMessage, "最多只能保存 5 位紧急联系人。")
        XCTAssertEqual(viewModel.contacts.count, 2)
        XCTAssertEqual(appState.emergencyContactCount, 2)
        XCTAssertEqual(appState.primaryEmergencyContact?.id, 1)
    }

    // MARK: - Session not ready

    func testLoadReportsAnErrorWhenSessionUserIdIsMissing() async {
        let (viewModel, appState, client) = makeViewModel(contacts: [makeContact(id: 1, name: "主联系人", isPrimary: true)])
        appState.userId = nil

        await viewModel.load()

        // 静默 return 会让盲人用户面对一个没有 loading、没有错误、没有播报的空页面。
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(client.requests.isEmpty, "没有 userId 时不应该发出请求")
        XCTAssertFalse(viewModel.isLoading)
    }

    // MARK: - Validation

    func testValidationRejectsEmptyNameAndBadPhoneAndOverlongRelationship() {
        XCTAssertEqual(
            EmergencyContactsViewModel.validationMessage(name: " ", phone: "13800138000", relationship: ""),
            "请填写联系人姓名。"
        )
        XCTAssertEqual(
            EmergencyContactsViewModel.validationMessage(name: "家人", phone: "1380013800", relationship: ""),
            "请输入正确的 11 位手机号。"
        )
        XCTAssertNotNil(
            EmergencyContactsViewModel.validationMessage(
                name: "家人",
                phone: "13800138000",
                relationship: String(repeating: "关", count: EmergencyContactRules.maxRelationshipLength + 1)
            )
        )
        XCTAssertNil(
            EmergencyContactsViewModel.validationMessage(name: "家人", phone: "13800138000", relationship: "母亲")
        )
    }

    func testPhoneInputKeepsOnlyFirstElevenDigits() {
        XCTAssertEqual(
            EmergencyContactsViewModel.normalizedPhoneInput("abc 138-0013-8000 999"),
            "13800138000"
        )
    }

    // MARK: - 短信告知文案

    /// 编辑联系人走 `updateContact`，后端**不发**告知短信（`sendContactAddedSms` 全仓只有 `addContact`
    /// 一个调用点，2026-07-31 确认是有意为之）。编辑态说「会发送短信」是一句念给盲人的假承诺。
    func testEditCopyDoesNotPromiseAnSmsThatIsNeverSent() {
        let copy = EmergencyContactFormView.editSmsNotice

        XCTAssertFalse(copy.contains("会向该号码发送"), "编辑态不得承诺发短信：\(copy)")
        XCTAssertTrue(copy.contains("不会"), "编辑态必须说清楚换号不发短信：\(copy)")
    }

    /// 新增确实会发短信，但**发送失败不影响 201**（后端已加 try-catch），所以文案不得把
    /// 「保存成功」表述成「对方已收到」。与 SOS 的送达红线同源。
    func testAddCopyDisclosesTheSmsWithoutClaimingDelivery() {
        let copy = EmergencyContactFormView.addSmsNotice

        XCTAssertTrue(copy.contains("短信"), "必须在保存前告知对方会收到短信：\(copy)")
        XCTAssertTrue(copy.contains("不代表对方已经收到"), "不得把保存成功表述成已送达：\(copy)")
        for claim in ["已通知", "已送达", "已收到你的"] {
            XCTAssertFalse(copy.contains(claim), "不得出现完成时的送达断言「\(claim)」：\(copy)")
        }
    }
}

// MARK: - Test Doubles

private final class ContactsAPIClientStub: APIClientProtocol, @unchecked Sendable {
    struct RecordedRequest {
        let method: HTTPMethod
        let path: String
    }

    private(set) var contacts: [EmergencyContactResponse]
    private(set) var requests: [RecordedRequest] = []
    private(set) var capturedUpdate: EmergencyContactRequest?
    var errorForNextMutation: APIError?
    /// 让变更之后的那次「重新 GET 整份列表」失败，用于验证旧列表被完整保留。
    var failNextRefresh = false

    init(contacts: [EmergencyContactResponse]) {
        self.contacts = contacts
    }

    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        requests.append(RecordedRequest(method: method, path: path))

        if method == .get, path.hasSuffix("/emergency-contacts") {
            if failNextRefresh {
                failNextRefresh = false
                throw APIError.invalidURL
            }
            return try cast(contacts)
        }

        if let errorForNextMutation {
            self.errorForNextMutation = nil
            throw errorForNextMutation
        }

        if method == .post, path.hasSuffix("/emergency-contacts") {
            let request = body as? EmergencyContactRequest
            let created = EmergencyContactResponse(
                id: (contacts.map(\.id).max() ?? 0) + 1,
                name: request?.name,
                phone: request?.phone,
                relationship: request?.relationship,
                isPrimary: request?.isPrimary ?? false
            )
            contacts.append(created)
            if created.isPrimary == true { applyPrimary(id: created.id) }
            return try cast(created)
        }

        if method == .put, path.hasSuffix("/set-primary") {
            guard let id = trailingId(in: path, dropLastComponents: 1) else { throw APIError.invalidURL }
            applyPrimary(id: id)
            return try cast(EmptyResponse())
        }

        if method == .put, let id = trailingId(in: path, dropLastComponents: 0) {
            let request = body as? EmergencyContactRequest
            capturedUpdate = request
            guard let index = contacts.firstIndex(where: { $0.id == id }) else { throw APIError.invalidURL }
            let updated = EmergencyContactResponse(
                id: id,
                name: request?.name,
                phone: request?.phone,
                relationship: request?.relationship,
                isPrimary: request?.isPrimary ?? false
            )
            contacts[index] = updated
            return try cast(updated)
        }

        if method == .delete, let id = trailingId(in: path, dropLastComponents: 0) {
            contacts.removeAll { $0.id == id }
            return try cast(EmptyResponse())
        }

        throw APIError.invalidURL
    }

    func upload<T: Decodable>(
        path: String,
        query: [String: String]?,
        fields: [String: String]?,
        files: [MultipartFile],
        requiresAuth: Bool
    ) async throws -> T {
        throw APIError.invalidURL
    }

    private func cast<T: Decodable>(_ value: Any) throws -> T {
        guard let typed = value as? T else { throw APIError.invalidURL }
        return typed
    }

    private func applyPrimary(id: Int64) {
        contacts = contacts.map {
            EmergencyContactResponse(
                id: $0.id,
                name: $0.name,
                phone: $0.phone,
                relationship: $0.relationship,
                isPrimary: $0.id == id
            )
        }
    }

    private func trailingId(in path: String, dropLastComponents: Int) -> Int64? {
        var components = path.split(separator: "/")
        components.removeLast(min(dropLastComponents, components.count))
        return components.last.flatMap { Int64($0) }
    }
}

private final class ContactsInMemoryTokenStore: TokenStoring {
    private var token: String?

    func save(_ token: String) { self.token = token }
    func read() -> String? { token }
    func delete() { token = nil }
}
