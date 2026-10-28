import XCTest
@testable import blindRun

/// 服务器证书或 TLS 出错时，不再让用户「检查网络」（#522）。
///
/// 背景：上线检查单 C6 / E11 —— 证书过期或续期失败时，全 App 所有请求都失败，而文案一律是
/// 「网络连接失败，请检查网络设置」。每个用户都会去折腾自己的网络，盲人用户更无从判断问题在哪一边。
///
/// **验红方式**：把 `APIError.isSecureConnectionFailure(_:)` 改成恒返回 `false`，
/// 前四条必须失败、最后一条照样通过（它守的是「普通断网不受影响」）。
@MainActor
final class SecureConnectionErrorCopyTests: XCTestCase {

    private static let tlsCodes: [URLError.Code] = [
        .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
        .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
        .clientCertificateRejected, .clientCertificateRequired
    ]

    private static let ordinaryNetworkCodes: [URLError.Code] = [
        .notConnectedToInternet, .timedOut, .networkConnectionLost, .cannotConnectToHost
    ]

    func testCertificateAndTLSErrorsSayItIsNotTheUsersNetwork() {
        for code in Self.tlsCodes {
            let error = APIError.networkError(URLError(code))
            XCTAssertTrue(error.isSecureConnectionFailure, "\(code.rawValue) 应认作证书 / TLS 错误")
            XCTAssertEqual(error.localizedMessage, APIError.secureConnectionMessage, "\(code.rawValue)")
        }
    }

    func testBridgedURLSessionErrorIsRecognisedOnlyInTheURLErrorDomain() {
        let fromURLSession = NSError(domain: NSURLErrorDomain, code: NSURLErrorServerCertificateUntrusted)
        XCTAssertTrue(APIError.isSecureConnectionFailure(fromURLSession))
        let sameNumberOtherDomain = NSError(domain: "com.example.other", code: NSURLErrorServerCertificateUntrusted)
        XCTAssertFalse(APIError.isSecureConnectionFailure(sameNumberOtherDomain))
    }

    func testRunRecordMessageFailureUsesTheSecureConnectionCopy() {
        XCTAssertEqual(
            RunRecordViewModel.sendFailureReason(.networkError(URLError(.serverCertificateHasBadDate))),
            APIError.secureConnectionMessage
        )
    }

    func testLoginCodeRequestFailureUsesTheSecureConnectionCopy() async {
        let viewModel = LoginViewModel(apiClient: ThrowingAPIClient(error: APIError.networkError(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorServerCertificateHasBadDate)
        )))
        viewModel.phoneNumber = "13800138000"

        viewModel.requestCode()
        await waitUntil { viewModel.errorMessage != nil && !viewModel.isSendingCode }

        XCTAssertEqual(viewModel.errorMessage, APIError.secureConnectionMessage)
    }

    func testOrdinaryNetworkErrorsStillAskToCheckTheNetwork() {
        for code in Self.ordinaryNetworkCodes {
            let error = APIError.networkError(URLError(code))
            XCTAssertFalse(error.isSecureConnectionFailure, "\(code.rawValue) 不是证书错误")
            XCTAssertEqual(error.localizedMessage, "网络连接失败，请检查网络设置。", "\(code.rawValue)")
        }
        XCTAssertEqual(
            RunRecordViewModel.sendFailureReason(.networkError(URLError(.notConnectedToInternet))),
            "请检查网络后再发一次。"
        )
    }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private final class ThrowingAPIClient: APIClientProtocol, @unchecked Sendable {
        private let error: Error

        init(error: Error) {
            self.error = error
        }

        func request<T: Decodable>(
            method: HTTPMethod,
            path: String,
            query: [String: String]?,
            body: (any Encodable & Sendable)?,
            requiresAuth: Bool
        ) async throws -> T {
            throw error
        }

        func upload<T: Decodable>(
            path: String,
            query: [String: String]?,
            fields: [String: String]?,
            files: [MultipartFile],
            requiresAuth: Bool
        ) async throws -> T {
            throw error
        }
    }
}
