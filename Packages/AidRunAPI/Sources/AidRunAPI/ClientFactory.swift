import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

/// 装配一个带鉴权的生成客户端。
///
/// 存在的理由是让 App 侧不用 `import OpenAPIRuntime` / `OpenAPIURLSession`：
/// 主工程的 MainActor 默认隔离与 OpenAPI 那套类型相撞过一次
/// （见 Package.swift 顶部），把这层装配关在包里就不会再撞第二次。
///
/// - Parameters:
///   - serverURL: 真实后端地址。App 内不可配置（AGENTS.md 第 3 节），由调用方从
///     `EnvironmentConfig` 取，这里不设默认值，免得在包里落下第二个真实地址。
///   - tokenProvider: 每次请求现取 JWT，没有就返回 nil。见 `BearerTokenMiddleware`。
public func makeAidRunAPIClient(
    serverURL: URL,
    tokenProvider: @escaping @Sendable () -> String?
) -> Client {
    Client(
        serverURL: serverURL,
        transport: URLSessionTransport(),
        middlewares: [BearerTokenMiddleware(tokenProvider: tokenProvider)]
    )
}
