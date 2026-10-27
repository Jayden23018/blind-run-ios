import Foundation

// 不碰实例状态的静态判定（环境、登录角色、手机号）。从 `AppState.swift` 原样搬出，行为零改动 ——
// 那个文件与类体只许变短（SwiftLint 棘轮 #488）。
extension AppState {
    /// 纯函数、无状态；`MockAPIClient` 等非 MainActor 上下文也要用它做与后端
    /// `@Pattern(^1[3-9]\d{9}$)` 同源的校验，所以显式 nonisolated。
    nonisolated static func isValidMainlandPhone(_ phoneNumber: String) -> Bool {
        let pattern = #"^1[3-9]\d{9}$"#
        return phoneNumber.range(of: pattern, options: .regularExpression) != nil
    }

    static func resolvedInitialEnvironment(
        _ environment: APIEnvironment,
        channel: AppBuildChannel = AppBuildChannel.current
    ) -> APIEnvironment {
        channel.allows(environment) ? environment : channel.defaultEnvironment
    }

    /// 启动时该用哪个环境。锁屏按钮的 intent 在 `AppState` 装好之前就可能跑
    /// （`GuideRunActivityController.installIntentHandler`），与这里读同一份。
    static func initialEnvironment(persistence: AppStatePersistence) -> APIEnvironment {
        guard let envRaw = persistence.string(forKey: AppConstants.UserDefaultsKeys.apiEnvironment),
              let env = storedEnvironment(from: envRaw) else {
            return AppBuildChannel.current.defaultEnvironment
        }
        return resolvedInitialEnvironment(env, channel: AppBuildChannel.current)
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
}
