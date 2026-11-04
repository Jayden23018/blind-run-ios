//
//  APIError+ServerUnavailable.swift
//  blindRun
//
//  宕机、网关报错、连不上服务器时单独说清（#659，审计 F-7）。写法照 `APIError+SecureConnection.swift`。
//

import Foundation

extension APIError {
    /// 手机这边确实没有网络。**只有这一种**才叫用户去检查网络。
    static let offlineMessage = "网络连接失败，请检查网络设置。"

    /// 服务器连不上，或网关回 5xx。说清「不是你的手机」：盲人用户无从判断问题在哪一边，
    /// 一律说「检查网络」会让他去反复开关飞行模式。最后一句留给紧急情况，因为此刻 App 帮不上忙。
    static let serverUnavailableMessage = "服务暂时出了问题，不是你的手机，请稍后再试。紧急情况请拨打120。"

    /// 请求超时或连接中途断开。**两边都可能**：弱网（地下通道）和服务器卡住表现一样，
    /// 所以不说「不是你的手机」，也不只叫用户检查网络。
    static let ambiguousConnectionMessage = "暂时连不上服务器，可能是信号弱，也可能是服务出了问题，请稍后再试。紧急情况请拨打120。"

    enum NetworkFailureKind: Equatable {
        case secureConnection
        case offline
        case serverUnreachable
        case ambiguous
    }

    /// 按 `URLError` 分类。不认识的错误（含非 `NSURLErrorDomain`）退回 `.offline`，与改动前的文案一致。
    static func networkFailureKind(_ error: Error) -> NetworkFailureKind {
        if isSecureConnectionFailure(error) { return .secureConnection }
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return .offline }
        let code = URLError.Code(rawValue: nsError.code)
        if serverUnreachableCodes.contains(code) { return .serverUnreachable }
        if ambiguousCodes.contains(code) { return .ambiguous }
        return .offline
    }

    static func networkFailureMessage(_ error: Error) -> String {
        switch networkFailureKind(error) {
        case .secureConnection: return secureConnectionMessage
        case .offline: return offlineMessage
        case .serverUnreachable: return serverUnavailableMessage
        case .ambiguous: return ambiguousConnectionMessage
        }
    }

    /// 嵌进「求助未发出：<原因>。请重试，或直接拨打110。」这类整句里的原因短语。
    /// 整句自带下一步，`localizedMessage` 里的「请稍后再试」「拨打120」会和它打架 ——
    /// 求助场景尤其不能叫人「稍后」。断网与证书错误仍用原文，与改动前一致。
    var reasonClause: String {
        switch self {
        case .networkError(let underlying):
            switch Self.networkFailureKind(underlying) {
            case .secureConnection, .offline: return localizedMessage
            case .serverUnreachable: return Self.serverUnavailableReason
            case .ambiguous: return "暂时连不上服务器，可能是信号弱，也可能是服务出了问题"
            }
        case .unknown(let statusCode) where Self.isServerSideStatus(statusCode):
            return Self.serverUnavailableReason
        default:
            return localizedMessage
        }
    }

    private static let serverUnavailableReason = "服务暂时出了问题，不是你的手机"

    /// 网关和服务器报的 5xx。没有后端错误体时才会走到 `.unknown`（有错误体的走 `.serverError`）。
    /// 网关 502 / 503 / 504 就是这样到的，原来念「未知错误 (502)」—— 状态码对用户没有用。
    static func isServerSideStatus(_ statusCode: Int) -> Bool {
        (500...599).contains(statusCode)
    }

    /// 手机有网，但找不到或连不上服务器。`cannotFindHost` / `dnsLookupFailed` 放在这里：
    /// 手机真没网时系统先报 `notConnectedToInternet`，走不到域名解析这一步。
    private static let serverUnreachableCodes: Set<URLError.Code> = [
        .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .badServerResponse
    ]

    private static let ambiguousCodes: Set<URLError.Code> = [
        .timedOut, .networkConnectionLost
    ]
}
