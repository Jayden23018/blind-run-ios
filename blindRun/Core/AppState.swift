import Combine
import Foundation
import SwiftUI

// MARK: - AppState

/// 全局应用状态，管理用户会话、Token 和环境配置。
/// 作为 @EnvironmentObject 注入整个应用的 View 层级。
final class AppState: ObservableObject {

    // MARK: - Session

    /// JWT 访问令牌
    /// - Note: MVP 暂存 UserDefaults。正式版必须迁移至 Keychain 存储。
    @Published var accessToken: String? {
        didSet { persistToken() }
    }

    /// 当前登录用户信息
    @Published var currentUser: UserDto?

    /// 当前激活角色（首次登录可能为 nil，需路由到角色选择）
    @Published var activeRole: UserRole? {
        didSet { persistActiveRole() }
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

    /// 根据当前环境返回对应的 API Client
    var apiClient: any APIClientProtocol {
        switch currentEnvironment {
        case .mock:
            return MockAPIClient()
        case .localBackend, .production:
            guard let baseURL = currentEnvironment.baseURL else {
                return MockAPIClient()
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
           let env = APIEnvironment(rawValue: envRaw) {
            self.currentEnvironment = env
        } else {
            self.currentEnvironment = .mock
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
    }

    /// 登录成功后保存会话
    func handleLoginSuccess(response: AuthResponse) {
        accessToken = response.accessToken
        currentUser = response.user
        activeRole = response.user.activeRole
    }

    /// 清除会话（退出登录）
    func clearSession() {
        accessToken = nil
        currentUser = nil
        activeRole = nil
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.accessToken)
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.activeRole)
    }

    /// 切换角色
    func switchRole(to role: UserRole) {
        activeRole = role
    }

    /// 用后端返回的用户数据同步当前用户和激活角色。
    func updateCurrentUser(_ user: UserDto, fallbackActiveRole: UserRole? = nil) {
        let resolvedActiveRole = user.activeRole ?? fallbackActiveRole
        currentUser = UserDto(
            id: user.id,
            phoneNumber: user.phoneNumber,
            nickname: user.nickname,
            roles: user.roles,
            activeRole: resolvedActiveRole,
            createdAt: user.createdAt,
            updatedAt: user.updatedAt
        )
        activeRole = resolvedActiveRole
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

    private func persistEnvironment() {
        UserDefaults.standard.set(currentEnvironment.rawValue, forKey: AppConstants.UserDefaultsKeys.apiEnvironment)
    }
}
