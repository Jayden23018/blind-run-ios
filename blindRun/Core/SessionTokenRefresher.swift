import Foundation
import OSLog

// MARK: - refresh token 续期（#391，后端 #642 / #669）

/// 续期一次的结果。
enum SessionRenewalOutcome {
    /// 拿到了能用的 access（可能是这次换来的，也可能是别的请求 / 锁屏卡刚换好的）。
    case renewed(accessToken: String)
    /// 这次登录已经结束：refresh 返回 401 `REFRESH_TOKEN_INVALID` / 400，或本地根本没有 refresh token。
    /// 原请求按 401 交回调用方 —— 后面走现有的过期 / 跑步中暂缓逻辑（`AppState.handleAuthenticatedAPIError`）。
    case invalid
    /// 429 / 5xx / 网络 / 超时：**不是登录失效**，会话必须保留，原请求按这条错误失败。
    case unavailable(APIError)
    /// 被拒的那条请求属于**上一次登录**（期间登出了 / 换了账号）。不重试、也不能按 401 处理 ——
    /// 用新会话的 token 重发旧请求是身份串用，按 401 处理会把新会话踢掉。
    case sessionChanged
}

/// 按契约续期：到期前主动续，401 时被动续，并发只发一次（single-flight）。
///
/// 工程默认隔离是 MainActor，所以 single-flight 只是一个 `Task?` 字段，不用锁也不用 actor。
/// 续期请求本身走 `exchange`（生产是 `AuthService.refreshSession`，`requiresAuth: false`），
/// 不会递归回到这里。
///
/// 🔴 **refresh token 只出现在 `exchange` 的请求体里。** 这里不打日志、不拼 URL、不放进任何头。
final class SessionTokenRefresher {
    /// 拿 refresh token 换一组新 token。未设置时一律当「不能续期」。
    ///
    /// 显式标 `@MainActor`：未标隔离的 async 闭包属性在真机上会交出已释放的参数
    /// （记忆 `unannotated-async-closure-property-crashes-on-device`）。
    var exchange: (@MainActor (String) async throws -> LoginResponse)?
    /// 换到新 access 之后通知持有内存副本的一方（`AppState`）。锁屏卡那个独立实例不设。
    var onAccessTokenRenewed: (@MainActor (String) -> Void)?

    /// 续期暂时不可用之后多久内不再发续期。跑步中订单页每 5 秒轮询一次，
    /// 而续期端点每个出口 IP 每分钟只放 10 次、且与发码 / 登录共用（契约 429 那一行）——
    /// 不冷却的话一次服务端故障会把续期自己打成 429，连恢复后的那一次也被挡住。
    static let unavailableCooldown: TimeInterval = 15

    private let accessStore: any TokenStoring
    private let credentialStore: RefreshCredentialStore
    private let now: () -> Date
    private var inFlight: (epoch: UInt64, task: Task<SessionRenewalOutcome, Never>)?
    private var cooldown: (until: Date, error: APIError)?

    /// 「这是哪一次登录」。存 / 清凭据时加一。发请求时记下它，401 回来时对不上 = 这条请求属于上一次登录
    /// （code review 2026-10-17：只比 token 值的话，A 登出、B 登录后 A 的迟到 401 会拿 B 的 token 重发）。
    private(set) var sessionEpoch: UInt64 = 0

    private static let logger = Logger(subsystem: "com.culiu-tech.aidrun1", category: "session-renewal")

    /// App 里那个 `AppState` 持有的实例。锁屏卡按钮不经 `AppState`（它可能在 App 装好之前就跑），
    /// 有就借它的，好让 single-flight 与内存里的 token 都跟着走；没有就自己起一个只读写 Keychain 的。
    static weak var appSessionRenewer: SessionTokenRefresher?

    init(
        accessStore: any TokenStoring,
        credentialStore: RefreshCredentialStore,
        now: @escaping () -> Date = { Date() }
    ) {
        self.accessStore = accessStore
        self.credentialStore = credentialStore
        self.now = now
    }

    /// 只读写 Keychain 的独立实例（锁屏卡在 App 没装好时用）。
    static func standalone(baseURL: URL) -> SessionTokenRefresher {
        let refresher = SessionTokenRefresher(
            accessStore: TokenStoreFactory.makeDefault(),
            credentialStore: RefreshCredentialStore(storage: TokenStoreFactory.makeDefault(account: .refreshSession))
        )
        refresher.exchange = { refreshToken in
            try await AuthService(transport: URLSessionAPIClient(baseURL: baseURL, tokenProvider: { nil }))
                .refreshSession(refreshToken: refreshToken)
        }
        return refresher
    }

    // MARK: - 凭据

    /// 登录成功时调。`response` 不带 refresh token（老后端 / Mock）就把旧的删掉 —— 留着别人的旧 refresh
    /// 等于让下一次 401 去续一个不属于这次登录的会话。
    func storeCredential(from response: LoginResponse) {
        beginNewSession()
        guard let credential = Self.credential(from: response, receivedAt: now()) else {
            credentialStore.delete()
            return
        }
        credentialStore.save(credential)
    }

    /// 登出 / 注销 / 会话失效时调。进行中的续期不取消（它不持有调用方的任何东西），
    /// 但它回来时会发现 Keychain 里的 refresh 没了，结果被丢弃（见 `perform`）。
    func clearCredential() {
        beginNewSession()
        credentialStore.delete()
    }

    /// 在途的续期属于上一次登录：新请求不许再去等它（它可能回一个 `.invalid`，把新会话踢掉）。
    /// 它自己跑完时发现 epoch 变了，结果丢弃。
    private func beginNewSession() {
        sessionEpoch &+= 1
        inFlight = nil
        cooldown = nil
    }

    var hasCredential: Bool { credentialStore.read() != nil }

    // MARK: - 主动续期

    /// 过了半衰期就起一个续期任务，**不等它**：此刻旧 access 还能用，没必要让手上这条请求跟着等。
    /// 真过期了的那条路由 `renewAfterUnauthorized` 兜住，它会等同一个任务。
    func scheduleRenewalIfDue() {
        guard inFlight?.epoch != sessionEpoch, isCoolingDown == false,
              let credential = credentialStore.read(), now() >= credential.renewalDueAt else { return }
        _ = startRenewal()
    }

    /// 测试与回前台用：过了半衰期就续，并等结果。
    @discardableResult
    func renewIfDue() async -> SessionRenewalOutcome? {
        if let inFlight, inFlight.epoch == sessionEpoch { return await inFlight.task.value }
        guard isCoolingDown == false,
              let credential = credentialStore.read(), now() >= credential.renewalDueAt else { return nil }
        return await startRenewal().value
    }

    // MARK: - 被动续期

    /// 需要登录的请求被 401 打回时调。`rejectedAccessToken` 是那条请求带出去的 access，
    /// `requestEpoch` 是发请求那一刻的 `sessionEpoch`（nil = 调用方没记，按当前会话算）。
    func renewAfterUnauthorized(rejectedAccessToken: String, requestEpoch: UInt64? = nil) async -> SessionRenewalOutcome {
        if let requestEpoch, requestEpoch != sessionEpoch { return .sessionChanged }
        // 同一次登录里，别的请求或锁屏卡已经换好了：直接用新的重试，不再续一次。
        if let current = accessStore.read(), !current.isEmpty, current != rejectedAccessToken {
            onAccessTokenRenewed?(current)
            return .renewed(accessToken: current)
        }
        if let inFlight, inFlight.epoch == sessionEpoch { return await inFlight.task.value }
        if let cooldown, now() < cooldown.until { return .unavailable(cooldown.error) }
        return await startRenewal().value
    }

    // MARK: - 内部

    private var isCoolingDown: Bool {
        guard let cooldown else { return false }
        return now() < cooldown.until
    }

    private func startRenewal() -> Task<SessionRenewalOutcome, Never> {
        let epoch = sessionEpoch
        let task = Task { [weak self] () -> SessionRenewalOutcome in
            guard let self else { return .invalid }
            let outcome = await self.perform(epoch: epoch)
            if self.inFlight?.epoch == epoch { self.inFlight = nil }
            return outcome
        }
        inFlight = (epoch, task)
        return task
    }

    private func perform(epoch: UInt64) async -> SessionRenewalOutcome {
        guard let credential = credentialStore.read(), let exchange else { return .invalid }
        let response: LoginResponse
        do {
            response = try await exchange(credential.refreshToken)
        } catch {
            guard epoch == sessionEpoch else { return .sessionChanged }
            return handleFailure(error, sentRefreshToken: credential.refreshToken)
        }
        guard epoch == sessionEpoch else {
            Self.logger.info("续期结果被丢弃：期间换了一次登录")
            return .sessionChanged
        }

        // 写回前再看一眼：续期在路上时用户登出了（refresh 已删）或换了账号（refresh 已换），
        // 这时写回去就是把凭据复活进 Keychain。丢弃结果，按 Keychain 里现在的东西作答。
        guard credentialStore.read()?.refreshToken == credential.refreshToken else {
            Self.logger.info("续期结果被丢弃：期间凭据已变")
            guard credentialStore.read() != nil, let current = accessStore.read(), !current.isEmpty else { return .invalid }
            return .renewed(accessToken: current)
        }
        guard !response.token.isEmpty else {
            return markUnavailable(.decodingError(SessionRenewalError.emptyAccessToken))
        }

        cooldown = nil
        accessStore.save(response.token)
        // 契约每次都换发新的 refresh 并带 `expiresIn`；万一缺了哪个，旧值在各自有效期内仍能用，补上旧的。
        let renewed = Self.credential(from: response, receivedAt: now())
            ?? RefreshCredential(
                refreshToken: response.refreshToken.flatMap { $0.isEmpty ? nil : $0 } ?? credential.refreshToken,
                issuedAt: now(),
                // ≤0 不收：那会让 `renewalDueAt` 永远在过去，之后每条请求都触发一次续期。
                expiresIn: response.expiresIn.flatMap { $0 > 0 ? TimeInterval($0) : nil } ?? credential.expiresIn
            )
        credentialStore.save(renewed)
        Self.logger.info("续期成功")
        onAccessTokenRenewed?(response.token)
        return .renewed(accessToken: response.token)
    }

    private func handleFailure(_ error: Error, sentRefreshToken: String) -> SessionRenewalOutcome {
        guard let apiError = error as? APIError else {
            return markUnavailable(.networkError(error))
        }
        guard Self.meansSessionEnded(apiError) else {
            return markUnavailable(apiError)
        }
        Self.logger.info("续期被拒：这次登录已结束")
        // 只删我们发出去的那一个：并发里别的实例刚存下的新 refresh 不该被这次的失败带走。
        if credentialStore.read()?.refreshToken == sentRefreshToken {
            credentialStore.delete()
        }
        return .invalid
    }

    private func markUnavailable(_ error: APIError) -> SessionRenewalOutcome {
        var wait = Self.unavailableCooldown
        if case .rateLimited(let info) = error, let seconds = info.retryAfterSeconds {
            wait = max(wait, TimeInterval(seconds))
        }
        cooldown = (now().addingTimeInterval(wait), error)
        Self.logger.info("续期暂时不可用，保留会话，\(Int(wait), privacy: .public) 秒后再试")
        return .unavailable(error)
    }

    /// 只有这几种是「这次登录已经结束」：续期端点的 401 只有 `REFRESH_TOKEN_INVALID` 一种
    /// （`APIClient` 在 401 时不解 body，所以这里拿不到 errorCode，按状态码判）；400 是请求体为空或过长，
    /// 契约说按 401 处理。**其余一律保留会话** —— 跑步中把一次 503 当成登录失效，就是把盲人踢回登录页。
    static func meansSessionEnded(_ error: APIError) -> Bool {
        switch error {
        case .unauthorized:
            return true
        case .serverError(let response):
            // `serverError` 不带状态码：网关 / 框架默认的 400 会落成 `BAD_REQUEST` 或合成的 `HTTP_400`
            // （`APIErrorEnvelope.resolvedErrorResponse`）。漏判的话一个永远续不上的 refresh 会每 15 秒打一次。
            return response.errorCode == .validationFailed
                || response.errorCode == .badRequest
                || response.code == "HTTP_400"
        case .unknown(let statusCode):
            return statusCode == 400
        case .rateLimited, .missingCredentials, .networkError, .decodingError, .invalidURL:
            return false
        }
    }

    private static func credential(from response: LoginResponse, receivedAt: Date) -> RefreshCredential? {
        guard let refreshToken = response.refreshToken, !refreshToken.isEmpty,
              let expiresIn = response.expiresIn, expiresIn > 0 else { return nil }
        return RefreshCredential(refreshToken: refreshToken, issuedAt: receivedAt, expiresIn: TimeInterval(expiresIn))
    }
}

enum SessionRenewalError: Error {
    case emptyAccessToken
}
