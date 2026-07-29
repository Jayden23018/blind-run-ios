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
    let realtimeCoordinator: AppRealtimeCoordinator
    let liveEscortCoordinator: LiveEscortSessionCoordinator

    // MARK: - Session

    /// JWT 访问令牌
    /// - Note: MVP 暂存 UserDefaults。正式版必须迁移至 Keychain 存储。
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

    var isBlindProfileComplete: Bool {
        guard let profile = blindProfile,
              let name = profile.name,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return !emergencyContacts.isEmpty
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
        persistence: AppStatePersistence? = nil
    ) {
        let persistence = persistence ?? AppStatePersistenceFactory.makeDefault()
        let realtimeCoordinator = AppRealtimeCoordinator()
        self.realtimeCoordinator = realtimeCoordinator
        self.liveEscortCoordinator = LiveEscortSessionCoordinator(realtimeCoordinator: realtimeCoordinator)
        self.apiClientOverride = apiClient
        self.persistence = persistence
        if let envRaw = persistence.string(forKey: AppConstants.UserDefaultsKeys.apiEnvironment),
           let env = AppState.storedEnvironment(from: envRaw) {
            self.currentEnvironment = AppState.resolvedInitialEnvironment(env, channel: AppBuildChannel.current)
        } else {
            self.currentEnvironment = AppBuildChannel.current.defaultEnvironment
        }
    }

    private var sessionIdentityKey: String? {
        guard let accessToken, let userId else { return nil }
        return "\(userId):\(activeRole?.rawValue ?? "none"):\(accessToken)"
    }

    // MARK: - Session Management

    /// 启动时恢复会话（从 UserDefaults 读取 Token）
    func restoreSession() async {
        sessionRestorationState = .restoring
        // TODO: 正式版必须从 Keychain 读取 Token，并使用 AppCredentialNamespace 隔离测试服务。
        accessToken = persistence.string(forKey: AppConstants.UserDefaultsKeys.accessToken)
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
        sessionExpirationMessage = nil
        logoutState = .idle
        accountDeletionState = .idle
        sessionRestorationState = .unauthenticated
        persistence.removeObject(forKey: AppConstants.UserDefaultsKeys.accessToken)
        persistence.removeObject(forKey: AppConstants.UserDefaultsKeys.activeRole)
        persistence.removeObject(forKey: AppConstants.UserDefaultsKeys.userId)
        persistence.removeObject(forKey: AppConstants.UserDefaultsKeys.emergencyRecoveryMetadata)
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
        // TODO: 正式版必须迁移至 Keychain 存储
        if let token = accessToken {
            persistence.set(token, forKey: AppConstants.UserDefaultsKeys.accessToken)
        } else {
            persistence.removeObject(forKey: AppConstants.UserDefaultsKeys.accessToken)
        }
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
