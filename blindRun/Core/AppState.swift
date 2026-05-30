import Combine
import Foundation
import SwiftUI

// MARK: - AppState

/// 全局应用状态，管理用户会话、Token 和环境配置。
/// 作为 @EnvironmentObject 注入整个应用的 View 层级。
final class AppState: ObservableObject {
    private let mockAPIClient = MockAPIClient()

    // MARK: - Session

    /// JWT 访问令牌
    /// - Note: MVP 暂存 UserDefaults。正式版必须迁移至 Keychain 存储。
    @Published var accessToken: String? {
        didSet { persistToken() }
    }

    /// 当前用户 ID
    @Published var userId: Int64?

    /// 当前激活角色（首次登录可能为 nil，需路由到角色选择）
    @Published var activeRole: UserRole? {
        didSet { persistActiveRole() }
    }

    /// 当前用户的盲人跑者资料
    @Published var blindProfile: BlindProfileResponse?

    /// 当前用户的志愿者资料
    @Published var volunteerProfile: VolunteerProfileResponse?

    /// 紧急联系人列表
    @Published var emergencyContacts: [EmergencyContactResponse] = []

    // MARK: - WebSocket

    /// WebSocket 服务实例（登录后创建，登出时销毁）
    @Published var webSocketService: WebSocketService?

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
        guard let profile = volunteerProfile,
              let name = profile.name,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return true
    }

    var isVolunteerProfileApproved: Bool {
        guard let profile = volunteerProfile else { return false }
        return profile.verificationStatus?.lowercased() == "approved"
    }

    /// 根据当前环境返回对应的 API Client
    var apiClient: any APIClientProtocol {
        switch currentEnvironment {
        case .mock where AppBuildChannel.current == .development:
            return mockAPIClient
        case .mock:
            return DisabledAPIClient()
        case .localBackend, .demoCloud, .production:
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

    init() {
        // 从 UserDefaults 恢复环境设置
        if let envRaw = UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.apiEnvironment),
           let env = AppState.storedEnvironment(from: envRaw, channel: AppBuildChannel.current) {
            self.currentEnvironment = AppState.resolvedInitialEnvironment(env, channel: AppBuildChannel.current)
        } else {
            self.currentEnvironment = AppBuildChannel.current.defaultEnvironment
        }
    }

    // MARK: - Session Management

    /// 启动时恢复会话（从 UserDefaults 读取 Token）
    func restoreSession() {
        // TODO: 正式版必须从 Keychain 读取 Token
        accessToken = UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.accessToken)
        if let roleRaw = UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.activeRole) {
            activeRole = UserRole(rawValue: roleRaw)
        }
        if let savedUserId = UserDefaults.standard.object(forKey: AppConstants.UserDefaultsKeys.userId) as? Int64 {
            userId = savedUserId
        }
        connectWebSocketIfNeeded()
    }

    /// 登录成功后保存会话（新后端: LoginResponse{token, userId, role}）
    func handleLoginSuccess(response: LoginResponse) {
        accessToken = response.token
        userId = response.userId
        if let roleStr = response.role, let role = UserRole(rawValue: roleStr) {
            activeRole = role
        }
        persistUserId()
        connectWebSocketIfNeeded()
    }

    /// 角色切换成功后替换 token（新后端: SetRoleResponse 包含新 token）
    func handleRoleSwitchSuccess(response: SetRoleResponse, requestedRole: UserRole) {
        if let newToken = response.token {
            accessToken = newToken
        }
        activeRole = requestedRole
        connectWebSocketIfNeeded()
    }

    /// 清除会话（退出登录）
    func clearSession() {
        disconnectWebSocket()
        accessToken = nil
        userId = nil
        activeRole = nil
        blindProfile = nil
        volunteerProfile = nil
        emergencyContacts = []
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.accessToken)
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.activeRole)
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.userId)
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

    static func storedEnvironment(from rawValue: String, channel: AppBuildChannel = AppBuildChannel.current) -> APIEnvironment? {
        if rawValue == "production", channel != .production {
            return .demoCloud
        }
        return APIEnvironment(rawValue: rawValue)
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
              let baseURL = currentEnvironment.baseURL else {
            return
        }

        let wsRole: WSRole = (role == .blind) ? .blind : .volunteer

        // 如果已有连接先断开
        webSocketService?.disconnect()

        let service = WebSocketService()
        service.connect(baseURL: baseURL, token: token, role: wsRole)
        webSocketService = service
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
            UserDefaults.standard.set(token, forKey: AppConstants.UserDefaultsKeys.accessToken)
        } else {
            UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.accessToken)
        }
    }

    private func persistActiveRole() {
        if let role = activeRole {
            UserDefaults.standard.set(role.rawValue, forKey: AppConstants.UserDefaultsKeys.activeRole)
        } else {
            UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.activeRole)
        }
    }

    private func persistUserId() {
        if let id = userId {
            UserDefaults.standard.set(id, forKey: AppConstants.UserDefaultsKeys.userId)
        }
    }

    private func persistEnvironment() {
        UserDefaults.standard.set(currentEnvironment.rawValue, forKey: AppConstants.UserDefaultsKeys.apiEnvironment)
    }
}

// MARK: - UserDefaults Keys Extension

extension AppConstants.UserDefaultsKeys {
    static let userId = "com.aidrun.mvp.userId"
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
}
