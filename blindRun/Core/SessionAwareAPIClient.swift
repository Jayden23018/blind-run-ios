import Foundation

extension APIError {
    /// 这次失败是不是「会话已结束」（续期也救不回来的 401）。会话本身已由 `SessionAwareAPIClient` 处理过（#873）：
    /// 调用方看到 true 就停下，不显示一般失败文案，**不要**自己再去碰会话。
    var endsSession: Bool {
        if case .unauthorized = self { return true }
        return false
    }
}

/// 会话失效的统一出口（OpenSpec `centralize-session-expiry-handling`，#872）。
///
/// 包在 `AppState.apiClient` 外面。需要登录的请求最终抛出 `.unauthorized` 时，先交给 `onSessionEnded`
/// （`AppState.handleAuthenticatedAPIError`：跑步中暂缓，否则登出），再把**同一个错误**原样抛给调用方。
/// 调用方据此停下、不显示一般失败文案；它不需要知道会话怎么处理。
///
/// 到这里的 `.unauthorized` 已经是「续期也救不回来」（`URLSessionAPIClient.withSessionRenewal`）：
/// 暂时续不了抛的是别的错误，换了账号抛 `.networkError(CancellationError())`。所以不用再判一次。
///
/// 不处理：`requiresAuth == false` 的请求（登录、发验证码的 401 不是会话失效）；`.missingCredentials`
/// （本地没 token，见 `APIError` 那条注释）。登出与补撤用未包的客户端（`AppState.sessionUnawareAPIClient`）。
final class SessionAwareAPIClient: APIClientProtocol, @unchecked Sendable {
    /// 被包的客户端。只给要认出具体实现的地方读（Mock 判定、UI 测试钩子），发请求一律走 `self`。
    let base: any APIClientProtocol
    // 显式标 `@MainActor`：未标隔离的异步闭包属性在真机上会交出已释放的对象（记忆
    // unannotated-async-closure-property-crashes-on-device）。
    private let onSessionEnded: @MainActor @Sendable () -> Void

    init(base: any APIClientProtocol, onSessionEnded: @escaping @MainActor @Sendable () -> Void) {
        self.base = base
        self.onSessionEnded = onSessionEnded
    }

    /// 包一层之后再包不会重复处理：已经是 adapter 就原样返回。
    static func wrapping(
        _ client: any APIClientProtocol,
        onSessionEnded: @escaping @MainActor @Sendable () -> Void
    ) -> any APIClientProtocol {
        if client is SessionAwareAPIClient { return client }
        return SessionAwareAPIClient(base: client, onSessionEnded: onSessionEnded)
    }

    /// 去掉 adapter，拿到最里面那个客户端。没包过就原样返回。
    static func unwrapped(_ client: any APIClientProtocol) -> any APIClientProtocol {
        (client as? SessionAwareAPIClient)?.base ?? client
    }

    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        do {
            return try await base.request(method: method, path: path, query: query, body: body, requiresAuth: requiresAuth)
        } catch APIError.unauthorized where requiresAuth {
            await onSessionEnded()
            throw APIError.unauthorized
        }
    }

    func upload<T: Decodable>(
        path: String,
        query: [String: String]?,
        fields: [String: String]?,
        files: [MultipartFile],
        requiresAuth: Bool
    ) async throws -> T {
        do {
            return try await base.upload(path: path, query: query, fields: fields, files: files, requiresAuth: requiresAuth)
        } catch APIError.unauthorized where requiresAuth {
            await onSessionEnded()
            throw APIError.unauthorized
        }
    }
}
