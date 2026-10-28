import Foundation
import Network

// MARK: - 待撤销的那一次登录（#459）

/// 退出登录时服务端没撤成的那一次登录。
///
/// #391 起退出登录无论服务端成败都清本地会话（契约 blind-run-backend#669）。断网时解绑本机推送 token
/// 与服务端登出都会失败，而清掉本地会话之后，本机就再没有凭据去补：旧账号的求助 / 走散 / 到达推送
/// 继续送到这台手机，换人登录后可能被念出来。这条记录就是补撤的凭据。
///
/// **只存撤销要用的最少数据**，只用于 `DELETE /api/devices/apns` 与 `POST /api/auth/logout`，
/// 从不拿它恢复会话、也不发任何业务请求。
struct PendingSessionRevocation: Codable, Equatable {
    /// 两个撤销请求都要它当 Bearer（契约：解绑与登出都要求 access 有效）。
    var accessToken: String
    /// access 过期时只为撤销换一个新的 access；换到的只写回这条记录。
    var refreshToken: String?
    /// 还绑在旧账号上的本机推送 token。nil = 已解绑或本来就没有。
    var deviceToken: String?
    /// 服务端登出还没成。
    var needsLogout: Bool
    let recordedAt: Date
    /// 这次登录的账号。同一账号又登录了，推送 token 就属于新会话，补撤不许再解绑它。
    /// 可选：旧版本写下的记录没有这一项。
    var userId: Int64?

    var isFinished: Bool { deviceToken == nil && !needsLogout }
}

/// 存成 JSON 数组放进 Keychain 的 `pendingSessionRevocation` 条目，写法同 `RefreshCredentialStore`：
/// 底层还是一条 `TokenStoring`，单测照旧用 `InMemoryTokenStore`。
final class PendingSessionRevocationStore {
    private let storage: any TokenStoring

    init(storage: any TokenStoring) {
        self.storage = storage
    }

    func read() -> [PendingSessionRevocation] {
        guard let json = storage.read(), let data = json.data(using: .utf8) else { return [] }
        do {
            return try JSONDecoder().decode([PendingSessionRevocation].self, from: data)
        } catch {
            // 解不开就当没有，但要留痕：静默降级是本仓库反复出现的那类缺陷（记忆 silent-decode-degradation-bug-class）。
            ClientFlowDiagnostics.record(event: "decode_failed", operation: "session-revocation-store")
            return []
        }
    }

    func save(_ items: [PendingSessionRevocation]) {
        guard !items.isEmpty else {
            storage.delete()
            return
        }
        guard let data = try? JSONEncoder().encode(items), let json = String(data: data, encoding: .utf8) else { return }
        storage.save(json)
    }
}

// MARK: - 补撤

/// 补撤上一次（或几次）登录：先解绑推送 token，再登出 —— 与登出流程同一个顺序（登出会把 JWT 拉黑，
/// 反过来解绑必然 401，契约 `unregisterApnsToken` 的 description）。
///
/// 触发：联网恢复（`NWPathMonitor`，只在有待撤记录时开）、回到前台、下次登录前。同一时刻只跑一轮。
@MainActor
final class PendingSessionRevoker {
    /// 给定 access 造一个**不带续期器**的 transport；nil = 当前环境不该补撤（Mock、发布构建禁用的环境）。
    /// 不能用 `AppState.apiClient`：它的续期器属于当前会话，拿它去续上一个人的 token 会把两次登录搅在一起。
    typealias TransportFactory = @MainActor (_ accessToken: String?) -> (any APIClientProtocol)?

    /// refresh 的有效期（契约 `POST /api/auth/logout`：只删本地的话，服务器上的 refresh 还能用 30 天）。
    /// 过了这个期限服务端会话已自然结束，记录没有用了。
    static let retention: TimeInterval = 30 * 24 * 60 * 60
    /// 连着几次登出都没联网才会攒多条；只留最近几条，防止无限长。
    static let capacity = 5

    private let store: PendingSessionRevocationStore
    private let transport: TransportFactory
    /// 此刻登录着的账号（没人登录为 nil）。
    private let currentUserID: @MainActor () -> Int64?
    /// 解绑落地时同一账号已经又登录了：新会话那份绑定被删掉了，要让它重报。
    private let onSameAccountUnbound: @MainActor () -> Void
    private let now: () -> Date
    private let monitorsNetwork: Bool
    private var inFlight: Task<Void, Never>?
    private var pathMonitor: NWPathMonitor?
    private var isNetworkSatisfied = false

    init(
        store: PendingSessionRevocationStore,
        transport: @escaping TransportFactory,
        currentUserID: @escaping @MainActor () -> Int64? = { nil },
        onSameAccountUnbound: @escaping @MainActor () -> Void = {},
        now: @escaping () -> Date = { Date() },
        monitorsNetwork: Bool = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    ) {
        self.store = store
        self.transport = transport
        self.currentUserID = currentUserID
        self.onSameAccountUnbound = onSameAccountUnbound
        self.now = now
        self.monitorsNetwork = monitorsNetwork
        if !store.read().isEmpty { startMonitoringNetwork() }
    }

    var pending: [PendingSessionRevocation] { store.read() }

    /// 登出没撤完：记下来，等联网 / 回前台 / 下次登录前补。
    func record(_ item: PendingSessionRevocation) {
        guard !item.isFinished else { return }
        store.save(Array((store.read() + [item]).suffix(Self.capacity)))
        startMonitoringNetwork()
    }

    /// 补撤一轮。正在补时等那一轮跑完，不另起。
    func retryIfPending() async {
        if let inFlight {
            await inFlight.value
            return
        }
        guard !store.read().isEmpty else {
            stopMonitoringNetwork()
            return
        }
        let task = Task { await self.drain() }
        inFlight = task
        await task.value
        inFlight = nil
    }

    /// 哪些失败值得下次再试：断网、限流、服务端错误。401 = 这次登录在服务端已经结束（续期也救不回），
    /// 再试也一样；解码失败 = 请求其实成功了。
    nonisolated static func isWorthRetrying(_ error: Error) -> Bool {
        guard let apiError = error as? APIError else { return true }
        switch apiError {
        case .networkError, .rateLimited, .serverError:
            return true
        case .unknown(let statusCode):
            return statusCode == 408 || (500...599).contains(statusCode)
        case .unauthorized, .missingCredentials, .decodingError, .invalidURL:
            return false
        }
    }

    /// 每撤完一条就写回一次：一轮跑到一半被杀，已撤的不会重来，换到的新 access 也不会丢。
    /// 按条替换而不是整表覆盖：这一轮跑着的时候可能又记了一条新的（又一次登出没联网）。
    private func drain() async {
        for item in store.read() {
            // `abs`：本机时钟被往回拨时，差值是负数，记录永远不会过期。
            let left = abs(now().timeIntervalSince(item.recordedAt)) < Self.retention ? await attempt(item) : nil
            var current = store.read()
            guard let index = current.firstIndex(of: item) else { continue }
            if let left { current[index] = left } else { current.remove(at: index) }
            store.save(current)
        }
        if store.read().isEmpty { stopMonitoringNetwork() }
    }

    /// 撤一条。返回还剩的部分；nil = 撤完了，或再也撤不了（服务端那次登录已结束）。
    private func attempt(_ original: PendingSessionRevocation) async -> PendingSessionRevocation? {
        var item = original
        var renewed = false
        while true {
            guard let client = transport(item.accessToken) else { return item }
            let auth = AuthService(transport: client)
            do {
                try await unbindDeviceIfStillOld(&item, auth: auth)
                if item.needsLogout {
                    try await Self.ignoringDecodingFailure { _ = try await auth.logout() }
                    item.needsLogout = false
                }
                ClientFlowDiagnostics.record(event: "finished", operation: "session-revocation-retry")
                return nil
            } catch APIError.unauthorized where !renewed {
                renewed = true
                guard let refreshToken = item.refreshToken, let refreshClient = transport(nil) else { return nil }
                do {
                    let response = try await AuthService(transport: refreshClient).refreshSession(refreshToken: refreshToken)
                    item.accessToken = response.token
                    if let rotated = response.refreshToken { item.refreshToken = rotated }
                } catch {
                    // refresh 也 401 = 这次登录在服务端已结束，没有可撤的了；别的错留到下次。
                    return Self.isWorthRetrying(error) ? item : nil
                }
            } catch {
                ClientFlowDiagnostics.record(event: "failed", operation: "session-revocation-retry")
                return Self.isWorthRetrying(error) ? item : nil
            }
        }
    }

    /// 解绑记录里的推送 token。同一账号又登录了就不解：这个 token 现在是新会话的绑定，
    /// 删了它推送就静默失效（契约：同一用户的 token 会被真删）。
    private func unbindDeviceIfStillOld(_ item: inout PendingSessionRevocation, auth: AuthService) async throws {
        guard let deviceToken = item.deviceToken else { return }
        if !isSignedInAgain(as: item.userId) {
            try await Self.ignoringDecodingFailure { try await auth.unregisterDeviceToken(deviceToken) }
            // 请求在路上时同一账号登录了、新会话已经上报：刚才那一下删掉的就是新绑定，让它重报。
            if isSignedInAgain(as: item.userId) { onSameAccountUnbound() }
        }
        item.deviceToken = nil
    }

    private func isSignedInAgain(as userId: Int64?) -> Bool {
        guard let userId else { return false }
        return currentUserID() == userId
    }

    /// 后端回 200 但响应体对不上时，请求本身已经生效。
    private static func ignoringDecodingFailure(_ body: @MainActor () async throws -> Void) async throws {
        do {
            try await body()
        } catch APIError.decodingError {
            return
        }
    }

    // MARK: 联网恢复

    private func startMonitoringNetwork() {
        guard monitorsNetwork, pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in self?.networkDidChange(satisfied: satisfied) }
        }
        monitor.start(queue: DispatchQueue(label: "com.culiu-tech.blindrun.session-revocation"))
        pathMonitor = monitor
    }

    private func stopMonitoringNetwork() {
        pathMonitor?.cancel()
        pathMonitor = nil
        isNetworkSatisfied = false
    }

    private func networkDidChange(satisfied: Bool) {
        let becameReachable = satisfied && !isNetworkSatisfied
        isNetworkSatisfied = satisfied
        guard becameReachable else { return }
        Task { await retryIfPending() }
    }
}
