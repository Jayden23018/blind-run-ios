//
//  APIError+SecureConnection.swift
//  blindRun
//
//  服务器证书 / TLS 出错时单独说清（#522）。放在扩展文件里：`APIClient.swift` 已超 SwiftLint 行数基线。
//

import Foundation

extension APIError {
    /// 服务器证书或 TLS 握手出错时的文案。这类错误是服务端的事（证书过期、续期失败），
    /// 一律说「检查网络」会让每个用户都去折腾自己的网络，而盲人用户无从判断问题在哪一边。
    static let secureConnectionMessage = "服务器的安全连接出了问题，不是你的网络问题，我们正在处理，请稍后再试。"

    /// 证书类与 TLS 握手类的 `URLError`。`NSError(domain: NSURLErrorDomain, …)` 同样认。
    static func isSecureConnectionFailure(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        return secureConnectionCodes.contains(URLError.Code(rawValue: nsError.code))
    }

    /// `.networkError` 且底层是证书 / TLS 错误。给各页面自己的「网络错误」文案分支先认这一种用。
    var isSecureConnectionFailure: Bool {
        if case .networkError(let underlying) = self { return Self.isSecureConnectionFailure(underlying) }
        return false
    }

    private static let secureConnectionCodes: Set<URLError.Code> = [
        .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
        .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
        .clientCertificateRejected, .clientCertificateRequired
    ]
}
