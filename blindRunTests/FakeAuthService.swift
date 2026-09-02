import Foundation
@testable import blindRun

/// `AuthServing` 的测试替身。**范例文件：其余几片的 Fake 照这个写。**
///
/// 硬规矩两条，违反了就等于把 `MockAPIClient` 的病搬到新层：
/// 1. **不许含任何业务判定**（`if` / `switch` / 校验 / 状态机）。
///    每个方法只做两件事：记一笔调用、返回构造时注入的罐装值。
/// 2. **默认是失败而不是成功**：没打桩的方法抛 `NotStubbed`，
///    用例因此会明确地红在「你没打这个桩」上，而不是拿到一个凭空捏造的成功值继续跑。
///
/// 想演「后端在这一步返回什么」的用例，注入 `.success(...)` / `.failure(...)`；
/// 想演「这条链路会不会打这个端点」的用例，读 `calls`。
final class FakeAuthService: AuthServing, @unchecked Sendable {

    struct NotStubbed: Error, CustomStringConvertible {
        let method: String
        var description: String { "FakeAuthService.\(method) 没有打桩" }
    }

    /// 调用顺序，元素是 `#function`（如 `"logout()"`）。
    private(set) var calls: [String] = []

    var sendVerificationCodeResult: Result<SendCodeResponse, Error> = .failure(NotStubbed(method: "sendVerificationCode"))
    var verifyCodeResult: Result<LoginResponse, Error> = .failure(NotStubbed(method: "verifyCode"))
    var currentUserResult: Result<CurrentUserResponse, Error> = .failure(NotStubbed(method: "currentUser"))
    var logoutResult: Result<LogoutResponse, Error> = .failure(NotStubbed(method: "logout"))
    var deleteAccountResult: Result<DeleteAccountResponse, Error> = .failure(NotStubbed(method: "deleteAccount"))
    var legalLinksResult: Result<LegalLinksResponse, Error> = .failure(NotStubbed(method: "legalLinks"))
    var missedNotificationsResult: Result<[MissedNotificationResponse], Error> = .failure(NotStubbed(method: "missedNotifications"))
    var accountDeletionOrderPreflightResult: Result<PagedOrderResponse, Error> = .failure(NotStubbed(method: "accountDeletionOrderPreflight"))
    var blindProfileResult: Result<BlindProfileResponse, Error> = .failure(NotStubbed(method: "blindProfile"))
    var emergencyContactsResult: Result<[EmergencyContactResponse], Error> = .failure(NotStubbed(method: "emergencyContacts"))
    var volunteerProfileResult: Result<VolunteerProfileResponse, Error> = .failure(NotStubbed(method: "volunteerProfile"))
    var volunteerRegistrationStatusResult: Result<VolunteerRegistrationStatus, Error> = .failure(NotStubbed(method: "volunteerRegistrationStatus"))
    var registerDeviceTokenResult: Result<Void, Error> = .failure(NotStubbed(method: "registerDeviceToken"))
    var unregisterDeviceTokenResult: Result<Void, Error> = .failure(NotStubbed(method: "unregisterDeviceToken"))

    /// 最后一次收到的参数。断言「传下去的是哪个值」用，不参与任何判定。
    private(set) var lastPhone: String?
    private(set) var lastCode: String?
    private(set) var lastUserId: Int64?
    private(set) var lastAfterTimestamp: String?
    private(set) var lastDeviceToken: String?

    private func record(_ method: String = #function) {
        calls.append(method)
    }

    func sendVerificationCode(phone: String) async throws -> SendCodeResponse {
        record()
        lastPhone = phone
        return try sendVerificationCodeResult.get()
    }

    func verifyCode(phone: String, code: String) async throws -> LoginResponse {
        record()
        lastPhone = phone
        lastCode = code
        return try verifyCodeResult.get()
    }

    func currentUser() async throws -> CurrentUserResponse {
        record()
        return try currentUserResult.get()
    }

    func logout() async throws -> LogoutResponse {
        record()
        return try logoutResult.get()
    }

    func deleteAccount(userId: Int64) async throws -> DeleteAccountResponse {
        record()
        lastUserId = userId
        return try deleteAccountResult.get()
    }

    func legalLinks() async throws -> LegalLinksResponse {
        record()
        return try legalLinksResult.get()
    }

    func missedNotifications(after: String) async throws -> [MissedNotificationResponse] {
        record()
        lastAfterTimestamp = after
        return try missedNotificationsResult.get()
    }

    func accountDeletionOrderPreflight() async throws -> PagedOrderResponse {
        record()
        return try accountDeletionOrderPreflightResult.get()
    }

    func blindProfile() async throws -> BlindProfileResponse {
        record()
        return try blindProfileResult.get()
    }

    func emergencyContacts(userId: Int64) async throws -> [EmergencyContactResponse] {
        record()
        lastUserId = userId
        return try emergencyContactsResult.get()
    }

    func volunteerProfile() async throws -> VolunteerProfileResponse {
        record()
        return try volunteerProfileResult.get()
    }

    func volunteerRegistrationStatus() async throws -> VolunteerRegistrationStatus {
        record()
        return try volunteerRegistrationStatusResult.get()
    }

    func registerDeviceToken(_ token: String) async throws {
        record()
        lastDeviceToken = token
        return try registerDeviceTokenResult.get()
    }

    func unregisterDeviceToken(_ token: String) async throws {
        record()
        lastDeviceToken = token
        return try unregisterDeviceTokenResult.get()
    }
}
