import Foundation

/// AppState 的持久化边界。测试必须注入独立域，不能写入正常 App 的标准域。
protocol AppStatePersistence: AnyObject {
    func string(forKey key: String) -> String?
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
    func reset()
}

final class UserDefaultsAppStatePersistence: AppStatePersistence {
    let suiteName: String?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, suiteName: String? = nil) {
        self.defaults = defaults
        self.suiteName = suiteName
    }

    convenience init(suiteName: String) {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("无法创建持久化域：\(suiteName)")
        }
        self.init(defaults: defaults, suiteName: suiteName)
    }

    func string(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    func object(forKey key: String) -> Any? {
        defaults.object(forKey: key)
    }

    func set(_ value: Any?, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    func removeObject(forKey key: String) {
        defaults.removeObject(forKey: key)
    }

    func reset() {
        guard let suiteName else {
            AppStatePersistenceKeys.all.forEach(defaults.removeObject(forKey:))
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
    }
}

enum AppStatePersistenceFactory {
    static let uiTestSuiteName = "com.jerry.aidrun.ui-tests"

    static func makeDefault(environment: [String: String] = ProcessInfo.processInfo.environment) -> AppStatePersistence {
        if environment["AIDRUN_UI_TEST_RESET_STATE"] == "1" {
            return UserDefaultsAppStatePersistence(suiteName: uiTestSuiteName)
        }
        if environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil {
            let suite = "com.jerry.aidrun.unit-tests.\(ProcessInfo.processInfo.processIdentifier)"
            return UserDefaultsAppStatePersistence(suiteName: suite)
        }
        return UserDefaultsAppStatePersistence()
    }

    static func makeIsolatedTest(name: String = UUID().uuidString) -> UserDefaultsAppStatePersistence {
        UserDefaultsAppStatePersistence(suiteName: "com.jerry.aidrun.tests.\(name)")
    }
}

enum AppStatePersistenceKeys {
    static let uiTestLastResetToken = "com.aidrun.mvp.uiTestLastResetToken"
    static let mockSnapshot = "com.aidrun.mvp.mockAPIStore.snapshot"

    static let all = [
        AppConstants.UserDefaultsKeys.accessToken,
        AppConstants.UserDefaultsKeys.activeRole,
        AppConstants.UserDefaultsKeys.apiEnvironment,
        AppConstants.UserDefaultsKeys.userId,
        AppConstants.UserDefaultsKeys.emergencyRecoveryMetadata,
        uiTestLastResetToken,
        mockSnapshot
    ]
}

/// Keychain 迁移时生产与测试必须继续使用不同 service/access group。
enum AppCredentialNamespace {
    static let productionService = "com.jerry.aidrun.credentials"
    static let unitTestService = "com.jerry.aidrun.credentials.unit-tests"
    static let uiTestService = "com.jerry.aidrun.credentials.ui-tests"
}
