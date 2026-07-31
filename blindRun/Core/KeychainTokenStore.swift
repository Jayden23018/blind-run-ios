//
//  KeychainTokenStore.swift
//  blindRun
//
//  JWT 访问令牌的安全持久化（系统 Security 框架，无第三方依赖）。
//

import Foundation
import Security

/// 访问令牌读写抽象。
/// - Note: 生产只有 `KeychainTokenStore` 一个实现。协议存在的理由有两个：让"旧 UserDefaults 存量迁移"
///   这段逻辑能在没有 Keychain 访问权限的单元测试环境里用内存 fake 验证；以及让单元测试之间互不串味
///   （Keychain 不随测试进程隔离，见 `TokenStoreFactory`）。不是为了支持多种后端存储。
protocol TokenStoring: AnyObject {
    func save(_ token: String)
    func read() -> String?
    func delete()
}

/// 用 Keychain 保存 JWT 访问令牌。
///
/// accessibility 固定为 `kSecAttrAccessibleAfterFirstUnlock`：陪跑过程中 App 会在后台甚至锁屏状态下
/// 读取 Token 去建立 WebSocket 连接和上报位置。若用 `kSecAttrAccessibleWhenUnlocked`，锁屏时读不到
/// Token，后台续跑会静默失效而不报错。`AfterFirstUnlock` 表示设备开机后首次解锁过即可读取，
/// 且不随 iCloud 同步（未设置 `kSecAttrSynchronizable`，默认不同步）。
///
/// service 由 `AppCredentialNamespace` 提供：生产、UI 测试、单元测试必须落在不同 service，
/// 否则测试会读写到真实用户的凭据。
final class KeychainTokenStore: TokenStoring {
    static let shared = KeychainTokenStore()

    private let service: String
    private let account = "accessToken"

    init(service: String = AppCredentialNamespace.productionService) {
        self.service = service
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    func save(_ token: String) {
        guard let data = token.data(using: .utf8) else { return }
        // 先删再写：避免同一条目已存在时 SecItemAdd 返回 errSecDuplicateItem。
        _ = SecItemDelete(baseQuery as CFDictionary)
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        _ = SecItemAdd(attributes as CFDictionary, nil)
    }

    func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            return nil
        }
        return token
    }

    func delete() {
        _ = SecItemDelete(baseQuery as CFDictionary)
    }
}

/// 仅存在于进程内存中的实现。单元测试默认使用它：Keychain 不随测试进程隔离，
/// 若单元测试都写同一个 service，用例之间会互相读到对方遗留的 Token。
final class InMemoryTokenStore: TokenStoring {
    private var token: String?

    init(token: String? = nil) {
        self.token = token
    }

    func save(_ token: String) { self.token = token }
    func read() -> String? { token }
    func delete() { token = nil }
}

/// 与 `AppStatePersistenceFactory.makeDefault` 一一对应的凭据侧工厂。
enum TokenStoreFactory {
    static func makeDefault(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> any TokenStoring {
        // UI 测试跑的是真 App，必须走真实 Keychain 才能覆盖"重启后仍登录"的路径，
        // 但落在独立 service，且由 `AppState.resetUITestPersistence()` 显式清除。
        if environment["AIDRUN_UI_TEST_RESET_STATE"] == "1" {
            return KeychainTokenStore(service: AppCredentialNamespace.uiTestService)
        }
        if environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil {
            return InMemoryTokenStore()
        }
        return KeychainTokenStore.shared
    }
}
