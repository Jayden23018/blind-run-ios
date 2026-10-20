//
//  KeychainTokenStore.swift
//  blindRun
//
//  JWT 访问令牌的安全持久化（系统 Security 框架，无第三方依赖）。
//

import Foundation
import os
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
/// accessibility 固定为 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`：陪跑过程中 App 会在后台
/// 甚至锁屏状态下读取 Token 去建立 WebSocket 连接和上报位置。若用 `kSecAttrAccessibleWhenUnlocked`，
/// 锁屏时读不到 Token，后台续跑会静默失效而不报错。`AfterFirstUnlock` 表示设备开机后首次解锁过即可读取，
/// 且不随 iCloud 同步（未设置 `kSecAttrSynchronizable`，默认不同步）。
/// `ThisDeviceOnly` 再加一道：条目不进加密备份的可迁移部分，恢复到另一台手机时不会带过去，
/// 否则备份里的有效 JWT 能在别的设备上直接当登录态用。
///
/// service 由 `AppCredentialNamespace` 提供：生产、UI 测试、单元测试必须落在不同 service，
/// 否则测试会读写到真实用户的凭据。
final class KeychainTokenStore: TokenStoring {
    static let shared = KeychainTokenStore()

    /// 写入条目时使用的 accessibility。单独成常量，是为了让测试能直接断言取值。
    static let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    private static let logger = Logger(subsystem: "com.culiu-tech.blindrun", category: "keychain")

    /// 同一个 service 下的两条条目：access token，以及 refresh token 连同签发时刻（`RefreshCredentialStore`）。
    /// 两条用同一个 accessibility —— 锁屏后台续期同样要读得到 refresh token。
    enum Account: String {
        case accessToken
        case refreshSession
    }

    private let service: String
    private let account: String
    private let itemAdd: (CFDictionary) -> OSStatus
    private let onWriteFailure: (OSStatus) -> Void

    /// - Parameters:
    ///   - itemAdd: 真正落盘的那一步。生产为 `SecItemAdd`；测试注入替身来制造写入失败。
    ///   - onWriteFailure: 写入失败的留痕出口。默认写系统日志；测试注入闭包来断言它被调用。
    init(
        service: String = AppCredentialNamespace.productionService,
        account: Account = .accessToken,
        itemAdd: ((CFDictionary) -> OSStatus)? = nil,
        onWriteFailure: ((OSStatus) -> Void)? = nil
    ) {
        self.service = service
        self.account = account.rawValue
        self.itemAdd = itemAdd ?? { SecItemAdd($0, nil) }
        self.onWriteFailure = onWriteFailure ?? KeychainTokenStore.logWriteFailure
    }

    /// 日志只记状态码，**不得**带 Token。状态码含义见 `SecBase.h`（如 -34018 缺 entitlement、-25308 设备锁屏）。
    private static func logWriteFailure(_ status: OSStatus) {
        logger.error("Keychain 写入 Token 失败 status=\(status, privacy: .public)")
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    /// `SecItemAdd` 的完整属性表。拆出来是为了让测试不碰真实 Keychain 也能核对写入的内容。
    func addAttributes(for data: Data) -> [String: Any] {
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = Self.accessibility
        return attributes
    }

    func save(_ token: String) {
        guard let data = token.data(using: .utf8) else { return }
        // 先删再写：避免同一条目已存在时 SecItemAdd 返回 errSecDuplicateItem。
        _ = SecItemDelete(baseQuery as CFDictionary)
        let status = itemAdd(addAttributes(for: data) as CFDictionary)
        // 写入失败时旧条目已被上一行删掉，用户下次冷启动会被要求重新登录；
        // 这里至少留下状态码，别让它静默发生。
        if status != errSecSuccess {
            onWriteFailure(status)
        }
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
        account: KeychainTokenStore.Account = .accessToken,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> any TokenStoring {
        // UI 测试跑的是真 App，必须走真实 Keychain 才能覆盖"重启后仍登录"的路径，
        // 但落在独立 service，且由 `AppState.resetUITestPersistence()` 显式清除。
        if environment["AIDRUN_UI_TEST_RESET_STATE"] == "1" {
            return KeychainTokenStore(service: AppCredentialNamespace.uiTestService, account: account)
        }
        if environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil {
            return InMemoryTokenStore()
        }
        return account == .accessToken ? KeychainTokenStore.shared : KeychainTokenStore(account: account)
    }
}

// MARK: - Refresh token（#391）

/// refresh token 与「这一对 token 是什么时候收到的、access 能用多久」。三者一起换、一起删，所以存一条。
///
/// `issuedAt` 是**本地收到响应的时刻**，不是解析 JWT 得到的签发时间（契约：不必解析 JWT）。
/// 本机时钟被拨过只会让续期早一点或晚一点；晚了也有 401 那条路兜住。
struct RefreshCredential: Codable, Equatable {
    let refreshToken: String
    let issuedAt: Date
    let expiresIn: TimeInterval

    /// 契约：「`token` 剩余有效期不足一半时」主动续期。
    var renewalDueAt: Date { issuedAt.addingTimeInterval(expiresIn / 2) }
}

/// `RefreshCredential` 的读写。底层就是又一条 `TokenStoring`（Keychain 的 `refreshSession` 条目），
/// 存的是 JSON —— 这样单测照旧用 `InMemoryTokenStore`，不用再多一种 fake。
final class RefreshCredentialStore {
    private let storage: any TokenStoring

    init(storage: any TokenStoring) {
        self.storage = storage
    }

    func save(_ credential: RefreshCredential) {
        guard let data = try? JSONEncoder().encode(credential),
              let json = String(data: data, encoding: .utf8) else { return }
        storage.save(json)
    }

    /// 解不开（例如以后改了格式）就当没有 —— 结果是这次登录不能续期，401 时回登录页，
    /// 与接续期之前一样，不会更糟。
    func read() -> RefreshCredential? {
        guard let json = storage.read(), let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(RefreshCredential.self, from: data)
    }

    func delete() {
        storage.delete()
    }
}
