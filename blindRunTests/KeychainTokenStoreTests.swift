//
//  KeychainTokenStoreTests.swift
//  blindRunTests
//
//  Token 持久化：Keychain 往返 + 旧 UserDefaults 存量一次性迁移 + UI 测试重置。
//

import XCTest
@testable import blindRun

private final class UnreachableAPIClient: APIClientProtocol, @unchecked Sendable {
    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        throw APIError.networkError(URLError(.notConnectedToInternet))
    }

    func upload<T: Decodable>(
        path: String,
        query: [String: String]?,
        fields: [String: String]?,
        files: [MultipartFile],
        requiresAuth: Bool
    ) async throws -> T {
        throw APIError.networkError(URLError(.notConnectedToInternet))
    }
}

@MainActor
final class KeychainTokenStoreTests: XCTestCase {

    /// 单元测试专用 service，绝不碰生产凭据。
    private func makeKeychainStore() -> KeychainTokenStore {
        KeychainTokenStore(service: AppCredentialNamespace.unitTestService)
    }

    override func tearDown() {
        makeKeychainStore().delete()
        super.tearDown()
    }

    // MARK: - Keychain 往返

    func testSaveThenReadReturnsSameToken() throws {
        let store = makeKeychainStore()
        store.delete()

        store.save("keychain-token")

        guard let readBack = store.read() else {
            throw XCTSkip("当前测试环境无 Keychain 访问权限（无 host application / entitlement 时常见），迁移逻辑另由内存 fake 覆盖")
        }
        XCTAssertEqual(readBack, "keychain-token")
    }

    func testDeleteRemovesToken() throws {
        let store = makeKeychainStore()
        store.save("keychain-token")
        try XCTSkipIf(store.read() == nil, "当前测试环境无 Keychain 访问权限")

        store.delete()

        XCTAssertNil(store.read())
    }

    // MARK: - accessibility：仅限本机 + 锁屏后仍可读

    /// 记录 `SecItemAdd` 收到的属性表与失败回调，供下面几条用例断言。
    private final class WriteRecorder {
        var attributes: [String: Any]?
        var failures: [OSStatus] = []
    }

    private func makeStore(addResult: OSStatus, recorder: WriteRecorder) -> KeychainTokenStore {
        KeychainTokenStore(
            service: AppCredentialNamespace.unitTestService,
            itemAdd: { attributes in
                recorder.attributes = attributes as? [String: Any]
                return addResult
            },
            onWriteFailure: { recorder.failures.append($0) }
        )
    }

    /// 不碰真实 Keychain：核对交给 `SecItemAdd` 的属性表。
    /// 旧实现写的是 `kSecAttrAccessibleAfterFirstUnlock`（取值 "ck"），新实现是 "cku"，两者字符串不等，
    /// 所以改回旧常量这条会红。
    func testSaveAsksKeychainForAfterFirstUnlockThisDeviceOnly() {
        let recorder = WriteRecorder()
        let store = makeStore(addResult: errSecSuccess, recorder: recorder)

        store.save("device-bound-token")

        let accessible = recorder.attributes?[kSecAttrAccessible as String] as? String
        XCTAssertEqual(
            accessible,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String,
            "Token 必须是 ThisDeviceOnly，否则会随加密备份恢复到别的手机"
        )
        XCTAssertNotEqual(
            accessible,
            kSecAttrAccessibleAfterFirstUnlock as String,
            "不得退回会被备份迁移的旧常量"
        )
        XCTAssertNotEqual(
            accessible,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String,
            "不得用锁屏后读不到的 WhenUnlocked*：后台定位与 WebSocket 需要锁屏后仍能读 Token"
        )
        XCTAssertNil(
            recorder.attributes?[kSecAttrSynchronizable as String],
            "不得设置 iCloud 同步"
        )
    }

    /// 真实 Keychain 读回：核对条目**实际存下的** accessibility，而不是我们传了什么。
    func testStoredItemReallyCarriesThisDeviceOnlyAccessibility() throws {
        let store = makeKeychainStore()
        store.delete()
        store.save("keychain-token")
        try XCTSkipIf(store.read() == nil, "当前测试环境无 Keychain 访问权限")

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppCredentialNamespace.unitTestService,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &item), errSecSuccess)
        let attributes = item as? [String: Any]

        XCTAssertEqual(
            attributes?[kSecAttrAccessible as String] as? String,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )
    }

    // MARK: - 写入失败不得静默

    func testFailedKeychainWriteIsReportedWithStatusAndLeavesNoToken() {
        let recorder = WriteRecorder()
        let store = makeStore(addResult: errSecInteractionNotAllowed, recorder: recorder)
        store.delete()

        store.save("will-not-be-stored")

        XCTAssertEqual(
            recorder.failures,
            [errSecInteractionNotAllowed],
            "SecItemAdd 失败必须带着状态码走到留痕出口，不能被吞掉"
        )
        XCTAssertNil(store.read(), "写入失败后不应读到 Token（旧条目已在写入前删除）")
    }

    /// 防止「无论成败都报失败」的错误实现也能通过上一条。
    func testSuccessfulKeychainWriteReportsNoFailure() {
        let recorder = WriteRecorder()
        let store = makeStore(addResult: errSecSuccess, recorder: recorder)

        store.save("stored-token")

        XCTAssertTrue(recorder.failures.isEmpty, "写入成功不得误报失败")
    }

    func testProductionAndTestServicesAreDistinct() {
        XCTAssertNotEqual(AppCredentialNamespace.productionService, AppCredentialNamespace.unitTestService)
        XCTAssertNotEqual(AppCredentialNamespace.productionService, AppCredentialNamespace.uiTestService)
        XCTAssertNotEqual(AppCredentialNamespace.unitTestService, AppCredentialNamespace.uiTestService)
    }

    func testDefaultTokenStoreUnderUITestResetIsIsolatedFromProduction() {
        let store = TokenStoreFactory.makeDefault(environment: ["AIDRUN_UI_TEST_RESET_STATE": "1"])
        XCTAssertTrue(store is KeychainTokenStore, "UI 测试必须走真实 Keychain，才能覆盖重启后仍登录的路径")
        XCTAssertFalse(store === KeychainTokenStore.shared, "UI 测试不得写入生产 service")
    }

    // MARK: - 旧 UserDefaults 存量迁移（最关键的一条）

    func testLegacyPersistedTokenIsMigratedIntoStoreAndClearedFromPersistence() async {
        let store = InMemoryTokenStore()
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        persistence.set("legacy-token", forKey: AppConstants.UserDefaultsKeys.accessToken)
        // 网络失败分支：会话校验不通过但不丢弃凭据，正好用来观察迁移结果。
        let appState = AppState(apiClient: UnreachableAPIClient(), persistence: persistence, tokenStore: store)

        await appState.restoreSession()

        XCTAssertEqual(appState.accessToken, "legacy-token", "老用户升级后不应掉登录态")
        XCTAssertEqual(store.read(), "legacy-token", "旧值必须写入 Keychain 存储")
        XCTAssertNil(
            persistence.string(forKey: AppConstants.UserDefaultsKeys.accessToken),
            "迁移后必须清空 UserDefaults 中的旧 Token"
        )
    }

    func testStoredTokenTakesPrecedenceOverLegacyPersistedValue() async {
        let store = InMemoryTokenStore()
        store.save("current-token")
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        persistence.set("stale-legacy-token", forKey: AppConstants.UserDefaultsKeys.accessToken)
        let appState = AppState(apiClient: UnreachableAPIClient(), persistence: persistence, tokenStore: store)

        await appState.restoreSession()

        XCTAssertEqual(appState.accessToken, "current-token")
    }

    func testClearSessionRemovesTokenFromStore() {
        let store = InMemoryTokenStore()
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let appState = AppState(apiClient: UnreachableAPIClient(), persistence: persistence, tokenStore: store)
        appState.handleLoginSuccess(response: LoginResponse(token: "session-token", userId: 42, role: "BLIND"))
        XCTAssertEqual(store.read(), "session-token")

        appState.clearSession()

        XCTAssertNil(store.read(), "退出后 Token 不得残留在 Keychain")
        XCTAssertNil(appState.accessToken)
    }

    // MARK: - 切换环境等于换后端，必须做同级清理

    /// 真机复现：mock 下产生的订单 ID 残留到真实后端，查询报「订单不存在」，
    /// 而实时侧又按残留状态把新派单显示成「已接单」。换环境必须回到干净状态。
    func testSwitchingEnvironmentClearsSessionAndActiveOrderState() {
        let store = InMemoryTokenStore()
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let appState = AppState(apiClient: UnreachableAPIClient(), persistence: persistence, tokenStore: store)
        XCTAssertEqual(appState.currentEnvironment, .mock, "开发构建默认落在 mock，本用例覆盖 mock -> 真实后端")

        appState.handleLoginSuccess(response: LoginResponse(token: "mock-session-token", userId: 7, role: "BLIND"))
        appState.updateBlindProfile(BlindProfileResponse(name: "测试跑者"))
        appState.updateEmergencyContacts([
            EmergencyContactResponse(id: 1, name: "联系人", phone: "13800000000", relationship: "朋友", isPrimary: true)
        ])
        appState.dismissBlindIdentityPrompt()
        appState.liveEscortCoordinator.updateOwnedOrder(orderID: 8_801, status: .driverEnRoute)
        XCTAssertEqual(appState.liveEscortCoordinator.activeOrderID, 8_801)
        XCTAssertEqual(appState.sessionRestorationState, .authenticated)

        appState.currentEnvironment = .demoCloud

        XCTAssertEqual(appState.currentEnvironment, .demoCloud, "新环境本身必须保留")
        XCTAssertEqual(
            persistence.string(forKey: AppConstants.UserDefaultsKeys.apiEnvironment),
            APIEnvironment.demoCloud.rawValue,
            "清理不得把刚切换的环境一起抹掉"
        )
        XCTAssertNil(appState.accessToken, "上一个环境的 Token 对新后端毫无意义")
        XCTAssertNil(store.read(), "Keychain 里的 Token 也必须一并删除")
        XCTAssertNil(appState.userId)
        XCTAssertNil(appState.activeRole)
        XCTAssertNil(appState.currentUser)
        XCTAssertNil(appState.blindProfile)
        XCTAssertTrue(appState.emergencyContacts.isEmpty)
        XCTAssertFalse(appState.didDismissBlindIdentityPrompt)
        XCTAssertNil(appState.liveEscortCoordinator.activeOrderID, "订单 ID 不得跨后端残留")
        XCTAssertNil(appState.liveEscortCoordinator.activeStatus)
        XCTAssertFalse(appState.realtimeCoordinator.pendingOrderRefreshIDs.contains(8_801))
        XCTAssertNil(appState.webSocketService, "旧环境的 WebSocket 必须断开")
        XCTAssertEqual(appState.sessionRestorationState, .unauthenticated, "路由回登录页才能销毁持有订单的 ViewModel")
        XCTAssertNil(persistence.string(forKey: AppConstants.UserDefaultsKeys.lastSeenNotificationTimestamp))
    }

    /// didSet 在赋同值时也会触发：不能把用户正在用的会话误清掉。
    func testAssigningTheSameEnvironmentKeepsTheCurrentSession() {
        let store = InMemoryTokenStore()
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let appState = AppState(apiClient: UnreachableAPIClient(), persistence: persistence, tokenStore: store)
        appState.handleLoginSuccess(response: LoginResponse(token: "same-env-token", userId: 9, role: "BLIND"))
        appState.liveEscortCoordinator.updateOwnedOrder(orderID: 9_902, status: .driverEnRoute)

        let unchangedEnvironment = appState.currentEnvironment
        appState.currentEnvironment = unchangedEnvironment

        XCTAssertEqual(appState.accessToken, "same-env-token")
        XCTAssertEqual(store.read(), "same-env-token")
        XCTAssertEqual(appState.userId, 9)
        XCTAssertEqual(appState.activeRole, .blind)
        XCTAssertEqual(appState.sessionRestorationState, .authenticated)
        XCTAssertEqual(appState.liveEscortCoordinator.activeOrderID, 9_902)
    }

    // MARK: - UI 测试重置必须同时清 Keychain

    func testResetUITestPersistenceAlsoClearsTokenStore() async {
        let store = InMemoryTokenStore()
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let appState = AppState(apiClient: UnreachableAPIClient(), persistence: persistence, tokenStore: store)
        appState.handleLoginSuccess(response: LoginResponse(token: "ui-reset-token", userId: 43, role: "BLIND"))
        XCTAssertEqual(store.read(), "ui-reset-token")

        appState.resetUITestPersistence()

        XCTAssertNil(store.read(), "Keychain 不随 App 沙盒清除，UI 测试重置必须显式删除 Token")
        XCTAssertNil(appState.accessToken)

        // 重置后重新恢复会话，必须落在未登录态，而不是捡回上一轮的 Token。
        await appState.restoreSession()
        XCTAssertNil(appState.accessToken)
        XCTAssertEqual(appState.sessionRestorationState, .unauthenticated)
    }
}
