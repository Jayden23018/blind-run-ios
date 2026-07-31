import Combine
import Foundation
import SwiftUI

enum SessionRestorationState: Equatable {
    case restoring
    case validationFailed(message: String)
    case unauthenticated
    case choosingRole
    case authenticated
}

enum SessionOperationState: Equatable {
    case idle
    case inProgress
    case revocationFailed(message: String)
}

@MainActor
final class AccountDeletionViewModel: ObservableObject {
    @Published var showFinalConfirmation = false
    @Published var preflightMessage: String?

    private static let blockingStatuses: Set<RunOrderStatus> = [
        .pendingMatch, .pendingAccept, .driverEnRoute, .driverArrived, .inProgress, .rematching
    ]

    func preflight(appState: AppState, speechService: SpeechService) async {
        preflightMessage = nil
        do {
            let orders: PagedOrderResponse = try await appState.apiClient.get(
                "/api/orders/mine",
                query: ["page": "0", "size": "100"]
            )
            if orders.content.contains(where: { Self.blockingStatuses.contains($0.status) }) {
                let message = "当前存在进行中的服务，请处理完成后再删除账户。"
                preflightMessage = message
                speechService.speakError(message)
                return
            }
        } catch APIError.unauthorized {
            appState.expireSession()
            return
        } catch {
            // 预检只提供及时提示；最终权限与订单状态始终由删除接口裁决。
        }
        showFinalConfirmation = true
    }
}

// MARK: - AppState

/// 全局应用状态，管理用户会话、Token 和环境配置。
/// 作为 @EnvironmentObject 注入整个应用的 View 层级。
@MainActor
final class AppState: ObservableObject {
    private let mockAPIClient = MockAPIClient()
    private let apiClientOverride: (any APIClientProtocol)?
    let persistence: AppStatePersistence
    private let tokenStore: any TokenStoring
    let realtimeCoordinator: AppRealtimeCoordinator
    let liveEscortCoordinator: LiveEscortSessionCoordinator

    // MARK: - Session

    /// JWT 访问令牌（持久化在 Keychain，见 `KeychainTokenStore`）
    @Published var accessToken: String? {
        didSet {
            persistToken()
            if oldValue != accessToken {
                realtimeCoordinator.detach(clearSessionState: true)
                liveEscortCoordinator.reset(clearIdentity: false)
            }
        }
    }

    /// 当前用户 ID
    @Published var userId: Int64? {
        didSet {
            // Token changes already clear initial login/logout. A non-nil account switch
            // needs its own boundary even if an integration reuses the same token value.
            if oldValue != nil, oldValue != userId {
                realtimeCoordinator.detach(clearSessionState: true)
                liveEscortCoordinator.reset(clearIdentity: false)
            }
        }
    }

    /// 仅保存在内存中的当前用户，不额外持久化手机号等身份信息。
    @Published private(set) var currentUser: CurrentUserResponse?

    @Published private(set) var sessionRestorationState: SessionRestorationState = .restoring
    @Published private(set) var logoutState: SessionOperationState = .idle
    @Published private(set) var accountDeletionState: SessionOperationState = .idle

    /// 当前激活角色（首次登录可能为 nil，需路由到角色选择）
    @Published var activeRole: UserRole? {
        didSet {
            persistActiveRole()
            mockAPIClient.syncRoleFromAppState(activeRole)
            if oldValue != activeRole {
                realtimeCoordinator.detach(clearSessionState: true)
                liveEscortCoordinator.reset(clearIdentity: false)
            }
        }
    }

    /// 当前用户的盲人跑者资料
    @Published var blindProfile: BlindProfileResponse?

    /// 当前用户的志愿者资料
    @Published var volunteerProfile: VolunteerProfileResponse?

    /// 当前用户的志愿者主注册流程状态
    @Published var volunteerRegistrationStatus: VolunteerRegistrationStatus?

    /// 紧急联系人列表
    @Published var emergencyContacts: [EmergencyContactResponse] = []

    /// 实名软引导的「稍后再说」标记。按账号记：`performLocalSessionCleanup` 会清掉它。
    /// 走 `persistence` 而不是 `@AppStorage`，否则单元/UI 测试会写进 App 的标准域。
    @Published private(set) var didDismissBlindIdentityPrompt = false

    /// 会话过期后带到登录页展示的一次性提示。
    @Published private(set) var sessionExpirationMessage: String?

    // MARK: - WebSocket

    /// WebSocket 服务实例（登录后创建，登出时销毁）
    @Published var webSocketService: WebSocketService? {
        didSet {
            let role: WSRole?
            switch activeRole {
            case .blind: role = .blind
            case .volunteer: role = .volunteer
            case .unset, .none: role = nil
            }
            realtimeCoordinator.attach(to: webSocketService, role: role)
            liveEscortCoordinator.configure(
                identityKey: sessionIdentityKey,
                role: activeRole,
                webSocketService: webSocketService
            )
        }
    }

    /// WebSocket 连接状态的便捷访问
    var isWebSocketConnected: Bool {
        if case .connected = webSocketService?.connectionState {
            return true
        }
        return false
    }

    // MARK: - Environment

    /// 当前 API 环境
    @Published var currentEnvironment: APIEnvironment {
        didSet { persistEnvironment() }
    }

    // MARK: - Computed

    var isLoggedIn: Bool {
        accessToken != nil
    }

    // MARK: 盲人完成度（拆成互相独立、可单独测试的判断）

    /// 基础资料：目前只要求昵称非空。与紧急联系人、实名状态无关。
    var isBlindBasicProfileComplete: Bool {
        guard let name = blindProfile?.name else { return false }
        return !name.trimmed.isEmpty
    }

    /// 实名状态。**仅用于展示与语音引导，不参与下单门槛**——
    /// 后端 `OrderCreationService` 只校验紧急联系人存在，客户端再拦一道就是假门槛。
    var blindIdentityStatus: BlindVerifyStatus {
        blindProfile?.identityStatus ?? .unknown
    }

    var emergencyContactCount: Int {
        emergencyContacts.count
    }

    /// 恰好一个主联系人时返回它；0 个或多个都返回 nil。
    var primaryEmergencyContact: EmergencyContactResponse? {
        EmergencyContactResponse.singlePrimary(in: emergencyContacts)
    }

    var hasExactlyOnePrimaryEmergencyContact: Bool {
        primaryEmergencyContact != nil
    }

    /// 紧急联系人侧的硬门槛：至少 1 位，且恰好 1 位主联系人。
    var hasValidEmergencyContacts: Bool {
        emergencyContactCount >= EmergencyContactRules.minCount && hasExactlyOnePrimaryEmergencyContact
    }

    /// 下单硬门槛：基础资料 + 至少 1 个紧急联系人 + 恰好 1 个主联系人。实名状态不参与。
    var isBlindBookingReady: Bool {
        isBlindBasicProfileComplete && hasValidEmergencyContacts
    }

    /// 盲人引导流当前该停在哪一步；nil 表示可以直接进首页。
    var blindOnboardingStep: BlindOnboardingStep? {
        BlindOnboardingStep.first(
            isBasicProfileComplete: isBlindBasicProfileComplete,
            hasValidEmergencyContacts: hasValidEmergencyContacts,
            shouldPromptIdentity: blindIdentityStatus.shouldPromptVerification,
            didDismissIdentityPrompt: didDismissBlindIdentityPrompt
        )
    }

    /// 「稍后再说」：跳过实名软引导，直接进首页。
    func dismissBlindIdentityPrompt() {
        didDismissBlindIdentityPrompt = true
        persistence.set(true, forKey: AppConstants.UserDefaultsKeys.blindIdentityPromptDismissed)
    }

    var isVolunteerProfileComplete: Bool {
        guard let profile = volunteerProfile else {
            return false
        }
        return profile.isProfileCompleteForDispatch
    }

    var isVolunteerProfileApproved: Bool {
        guard let profile = volunteerProfile else { return false }
        if let volunteerRegistrationStatus {
            return volunteerRegistrationStatus.isRegistrationComplete
        }
        return profile.isMainRegistrationCompleteWhenStatusUnavailable && profile.isAdminReviewApprovedWhenAvailable
    }

    /// 根据当前环境返回对应的 API Client
    var apiClient: any APIClientProtocol {
        if let apiClientOverride { return apiClientOverride }
        switch currentEnvironment {
        case .mock where AppBuildChannel.current == .development:
            return mockAPIClient
        case .mock:
            return DisabledAPIClient()
        case .demoCloud:
            guard AppBuildChannel.current.allows(currentEnvironment) else {
                return DisabledAPIClient()
            }
            guard let baseURL = currentEnvironment.baseURL else {
                return DisabledAPIClient()
            }
            return URLSessionAPIClient(
                baseURL: baseURL,
                tokenProvider: { [weak self] in self?.accessToken }
            )
        }
    }

    // MARK: - Init

    init(
        apiClient: (any APIClientProtocol)? = nil,
        persistence: AppStatePersistence? = nil,
        tokenStore: (any TokenStoring)? = nil
    ) {
        let persistence = persistence ?? AppStatePersistenceFactory.makeDefault()
        let realtimeCoordinator = AppRealtimeCoordinator()
        self.realtimeCoordinator = realtimeCoordinator
        self.liveEscortCoordinator = LiveEscortSessionCoordinator(realtimeCoordinator: realtimeCoordinator)
        self.apiClientOverride = apiClient
        self.persistence = persistence
        self.tokenStore = tokenStore ?? TokenStoreFactory.makeDefault()
        if let envRaw = persistence.string(forKey: AppConstants.UserDefaultsKeys.apiEnvironment),
           let env = AppState.storedEnvironment(from: envRaw) {
            self.currentEnvironment = AppState.resolvedInitialEnvironment(env, channel: AppBuildChannel.current)
        } else {
            self.currentEnvironment = AppBuildChannel.current.defaultEnvironment
        }
        self.didDismissBlindIdentityPrompt =
            persistence.object(forKey: AppConstants.UserDefaultsKeys.blindIdentityPromptDismissed) as? Bool ?? false
    }

    private var sessionIdentityKey: String? {
        guard let accessToken, let userId else { return nil }
        return "\(userId):\(activeRole?.rawValue ?? "none"):\(accessToken)"
    }

    // MARK: - Session Management

    /// 启动时恢复会话（Token 从 Keychain 读取，兼容旧版本 UserDefaults 存量）
    func restoreSession() async {
        sessionRestorationState = .restoring
        accessToken = restoredToken()
        if let roleRaw = persistence.string(forKey: AppConstants.UserDefaultsKeys.activeRole) {
            activeRole = UserRole(rawValue: roleRaw)
        }
        if let savedUserId = persistence.object(forKey: AppConstants.UserDefaultsKeys.userId) as? NSNumber {
            userId = savedUserId.int64Value
        }
        guard accessToken != nil else {
            sessionRestorationState = .unauthenticated
            return
        }
        mockAPIClient.syncSessionFromAppState(token: accessToken, role: activeRole)
        do {
            let user: CurrentUserResponse = try await apiClient.get("/api/auth/me")
            guard user.roleResolution != .invalid else {
                performLocalSessionCleanup()
                sessionExpirationMessage = "登录角色信息异常，请重新登录。"
                return
            }
            currentUser = user
            userId = user.userId
            persistUserId()
            activeRole = user.resolvedRole
            if activeRole == nil {
                disconnectWebSocket()
                sessionRestorationState = .choosingRole
            } else {
                sessionRestorationState = .authenticated
                connectWebSocketIfNeeded()
            }
        } catch let error as APIError {
            switch error {
            case .unauthorized:
                performLocalSessionCleanup()
                sessionExpirationMessage = "登录状态已失效，请重新登录。"
            default:
                // 无法权威确认时不进入已认证页面，也不丢弃可能仍有效的凭据。
                disconnectWebSocket()
                sessionRestorationState = .validationFailed(message: error.localizedMessage)
            }
        } catch {
            disconnectWebSocket()
            sessionRestorationState = .validationFailed(message: "暂时无法验证登录状态，请检查网络后重试。")
        }
    }

    /// 登录成功后保存会话（新后端: LoginResponse{token, userId, role}）
    func handleLoginSuccess(response: LoginResponse) {
        accessToken = response.token
        userId = response.userId
        activeRole = Self.resolvedLoginRole(from: response.role)
        currentUser = CurrentUserResponse(userId: response.userId, phone: nil, role: response.role)
        persistUserId()
        sessionRestorationState = activeRole == nil ? .choosingRole : .authenticated
        connectWebSocketIfNeeded()
    }

    /// 角色切换成功后替换 token（新后端: SetRoleResponse 包含新 token）
    func handleRoleSwitchSuccess(response: SetRoleResponse, requestedRole: UserRole) {
        if let newToken = response.token {
            accessToken = newToken
        }
        activeRole = requestedRole
        if let currentUser {
            self.currentUser = CurrentUserResponse(userId: currentUser.userId, phone: currentUser.phone, role: requestedRole.rawValue)
        }
        sessionRestorationState = .authenticated
        connectWebSocketIfNeeded()
    }

    /// 清除会话（退出登录）
    func clearSession() {
        performLocalSessionCleanup()
    }

    /// 所有用户退出入口使用该服务端撤销操作。
    func logout() async {
        guard logoutState != .inProgress else { return }
        logoutState = .inProgress
        do {
            let _: LogoutResponse = try await apiClient.post("/api/auth/logout")
            performLocalSessionCleanup()
        } catch APIError.unauthorized {
            performLocalSessionCleanup()
        } catch let error as APIError {
            logoutState = .revocationFailed(message: error.localizedMessage)
        } catch {
            logoutState = .revocationFailed(message: "未能确认服务端退出，请重试。")
        }
    }

    /// 仅在服务端撤销失败且用户再次明确确认后调用。
    func confirmLocalOnlySignOut() {
        guard case .revocationFailed = logoutState else { return }
        performLocalSessionCleanup()
    }

    func dismissLogoutFailure() {
        if case .revocationFailed = logoutState { logoutState = .idle }
    }

    func dismissAccountDeletionFailure() {
        if case .revocationFailed = accountDeletionState { accountDeletionState = .idle }
    }

    func deleteCurrentAccount() async {
        guard accountDeletionState != .inProgress, let userId = currentUser?.userId ?? self.userId else { return }
        accountDeletionState = .inProgress
        do {
            let response: DeleteAccountResponse = try await apiClient.delete("/api/users/\(userId)")
            guard response.success else {
                accountDeletionState = .revocationFailed(message: response.message ?? "账户删除未完成。")
                return
            }
            performLocalSessionCleanup()
        } catch APIError.unauthorized {
            expireSession()
        } catch let error as APIError {
            accountDeletionState = .revocationFailed(message: error.localizedMessage)
        } catch {
            accountDeletionState = .revocationFailed(message: "账户删除未完成，请重试。")
        }
    }

    private func performLocalSessionCleanup() {
        disconnectWebSocket()
        accessToken = nil
        userId = nil
        currentUser = nil
        activeRole = nil
        blindProfile = nil
        volunteerProfile = nil
        volunteerRegistrationStatus = nil
        emergencyContacts = []
        didDismissBlindIdentityPrompt = false
        sessionExpirationMessage = nil
        logoutState = .idle
        accountDeletionState = .idle
        sessionRestorationState = .unauthenticated
        // Keychain 里的 Token 由上面 `accessToken = nil` 经 didSet -> persistToken 删除；
        // 这里只清理旧版本可能遗留在 UserDefaults 的 Token，避免退出后又被迁移回来。
        persistence.removeObject(forKey: AppConstants.UserDefaultsKeys.accessToken)
        persistence.removeObject(forKey: AppConstants.UserDefaultsKeys.activeRole)
        persistence.removeObject(forKey: AppConstants.UserDefaultsKeys.userId)
        persistence.removeObject(forKey: AppConstants.UserDefaultsKeys.emergencyRecoveryMetadata)
        // 实名软引导的「稍后再说」是按账号记的：换账号后应重新提示一次。
        persistence.removeObject(forKey: AppConstants.UserDefaultsKeys.blindIdentityPromptDismissed)
    }

    /// 会话过期：清除本地登录态并让登录页展示一次性提示。
    func expireSession(message: String = "登录已过期，请重新登录。") {
        clearSession()
        sessionExpirationMessage = message
    }

    func consumeSessionExpirationMessage() -> String? {
        let message = sessionExpirationMessage
        sessionExpirationMessage = nil
        return message
    }

    @discardableResult
    func handleAuthenticatedAPIError(_ error: APIError) -> Bool {
        guard case .unauthorized = error else { return false }
        expireSession()
        return true
    }

    /// 切换角色
    func switchRole(to role: UserRole) {
        activeRole = role
    }

    /// 更新盲人资料
    func updateBlindProfile(_ profile: BlindProfileResponse) {
        blindProfile = profile
    }

    /// 更新志愿者资料
    func updateVolunteerProfile(_ profile: VolunteerProfileResponse) {
        volunteerProfile = profile
    }

    /// 更新志愿者主注册流程状态
    func updateVolunteerRegistrationStatus(_ status: VolunteerRegistrationStatus) {
        volunteerRegistrationStatus = status
    }

    /// 更新紧急联系人
    func updateEmergencyContacts(_ contacts: [EmergencyContactResponse]) {
        emergencyContacts = contacts
    }

    #if DEBUG
    func returnToRoleSelectionForTesting() {
        activeRole = nil
    }

    func switchToNextEnvironmentForTesting() {
        let allEnvironments = AppState.debugTestEnvironments
        let currentEnvironment = AppState.resolvedInitialEnvironment(currentEnvironment, channel: .development)
        guard let currentIndex = allEnvironments.firstIndex(of: currentEnvironment) else {
            self.currentEnvironment = allEnvironments[0]
            clearSession()
            return
        }
        let nextIndex = (currentIndex + 1) % allEnvironments.count
        self.currentEnvironment = allEnvironments[nextIndex]
        clearSession()
    }
    #endif

    #if DEBUG || DEMO
    func resetUITestPersistence() {
        persistence.reset()
        performLocalSessionCleanup()
        // Keychain 不随 App 沙盒一起清除：只清 UserDefaults 的话，重置后 Token 仍会残留，
        // 「本该未登录」的 UI 用例会拿着上一轮的 Token 继续跑。必须显式删除。
        tokenStore.delete()
    }
    #endif

    static func isValidMainlandPhone(_ phoneNumber: String) -> Bool {
        let pattern = #"^1[3-9]\d{9}$"#
        return phoneNumber.range(of: pattern, options: .regularExpression) != nil
    }

    static func resolvedInitialEnvironment(
        _ environment: APIEnvironment,
        channel: AppBuildChannel = AppBuildChannel.current
    ) -> APIEnvironment {
        channel.allows(environment) ? environment : channel.defaultEnvironment
    }

    static func storedEnvironment(from rawValue: String) -> APIEnvironment? {
        return APIEnvironment(rawValue: rawValue)
    }

    static func resolvedLoginRole(from rawValue: String?) -> UserRole? {
        guard let rawValue,
              let role = UserRole(rawValue: rawValue),
              role != .unset else {
            return nil
        }
        return role
    }

    #if DEBUG
    static let debugTestEnvironments: [APIEnvironment] = [.mock, .demoCloud]
    #endif

    // MARK: - WebSocket (Private)

    /// 根据当前 token 和角色连接 WebSocket（mock 环境跳过）
    private func connectWebSocketIfNeeded() {
        #if DEBUG || DEMO
        if ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_DISABLE_WEBSOCKET"] == "1" {
            return
        }
        #endif

        guard currentEnvironment != .mock,
              AppBuildChannel.current.allows(currentEnvironment),
              let token = accessToken,
              let role = activeRole,
              role != .unset,
              let baseURL = currentEnvironment.baseURL else {
            return
        }

        let wsRole: WSRole = (role == .blind) ? .blind : .volunteer

        // 如果已有连接先断开
        webSocketService?.disconnect()

        let service = WebSocketService()
        webSocketService = service
        service.connect(baseURL: baseURL, token: token, role: wsRole)
    }

    /// 断开 WebSocket 并清除引用
    private func disconnectWebSocket() {
        webSocketService?.disconnect()
        webSocketService = nil
    }

    // MARK: - Persistence (Private)

    private func persistToken() {
        if let token = accessToken {
            tokenStore.save(token)
        } else {
            tokenStore.delete()
        }
    }

    /// Keychain 优先读取；只有命中旧版本遗留在 UserDefaults 的 Token 时才做一次性迁移
    /// （写入 Keychain 并清除旧值），保证老用户升级后不掉登录态。
    private func restoredToken() -> String? {
        if let token = tokenStore.read() {
            return token
        }
        guard let legacyToken = persistence.string(forKey: AppConstants.UserDefaultsKeys.accessToken),
              !legacyToken.isEmpty else {
            return nil
        }
        tokenStore.save(legacyToken)
        persistence.removeObject(forKey: AppConstants.UserDefaultsKeys.accessToken)
        return legacyToken
    }

    private func persistActiveRole() {
        if let role = activeRole {
            persistence.set(role.rawValue, forKey: AppConstants.UserDefaultsKeys.activeRole)
        } else {
            persistence.removeObject(forKey: AppConstants.UserDefaultsKeys.activeRole)
        }
    }

    private func persistUserId() {
        if let id = userId {
            persistence.set(id, forKey: AppConstants.UserDefaultsKeys.userId)
        }
    }

    private func persistEnvironment() {
        persistence.set(currentEnvironment.rawValue, forKey: AppConstants.UserDefaultsKeys.apiEnvironment)
    }
}

// MARK: - UserDefaults Keys Extension

extension AppConstants.UserDefaultsKeys {
    static let userId = "com.aidrun.mvp.userId"
    static let emergencyRecoveryMetadata = "com.aidrun.safety.emergencyRecoveryMetadata"
}

// MARK: - Disabled API Client

private final class DisabledAPIClient: APIClientProtocol, @unchecked Sendable {
    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
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
}
