import Combine
import Foundation
import SwiftUI

extension AppState {
    // MARK: - Persistence (Private)

    /// `accessToken` 的 `didSet` 唯一调用点：落 Keychain，并让 Mock 跟着本地会话走。
    func persistToken() {
        if let token = accessToken {
            tokenStore.save(token)
        } else {
            tokenStore.delete()
        }
        // 角色在 `activeRole` 里同样这么同步。不同步的话，直接给 `accessToken` 赋值的路径上 Mock 会对需要登录的端点回 401，
        // 而 `apiClient` 外面那层（#872）会把这个假 401 当成会话失效、把人登出。
        mockAPIClient.syncSessionFromAppState(token: accessToken, role: activeRole)
    }

    /// Keychain 优先读取；只有命中旧版本遗留在 UserDefaults 的 Token 时才做一次性迁移
    /// （写入 Keychain 并清除旧值），保证老用户升级后不掉登录态。
    func restoredToken() -> String? {
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

    func persistActiveRole() {
        if let role = activeRole {
            persistence.set(role.rawValue, forKey: AppConstants.UserDefaultsKeys.activeRole)
        } else {
            persistence.removeObject(forKey: AppConstants.UserDefaultsKeys.activeRole)
        }
    }

    func persistUserId() {
        if let id = userId {
            persistence.set(id, forKey: AppConstants.UserDefaultsKeys.userId)
        }
    }

    func persistEnvironment() {
        persistence.set(currentEnvironment.rawValue, forKey: AppConstants.UserDefaultsKeys.apiEnvironment)
    }
}
