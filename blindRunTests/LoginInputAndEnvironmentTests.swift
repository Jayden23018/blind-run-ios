import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class LoginInputAndEnvironmentTests: XCTestCase, BlindRunTestSupport {
    func testLoginPhoneInputKeepsOnlyFirstElevenDigits() {
        let viewModel = LoginViewModel()

        viewModel.sanitizePhoneInput(" 138 0013 8000 999")

        XCTAssertEqual(viewModel.phoneNumber, "13800138000")
    }

    func testLoginPhoneInputDropsNonDigits() {
        let viewModel = LoginViewModel()

        viewModel.sanitizePhoneInput("abc138-0013-8000xyz")

        XCTAssertEqual(viewModel.phoneNumber, "13800138000")
    }

    func testLoginPhoneDirectAssignmentKeepsOnlyFirstElevenDigits() {
        let viewModel = LoginViewModel()

        viewModel.phoneNumber = "13800138000999"

        XCTAssertEqual(viewModel.phoneNumber, "13800138000")
    }

    func testLoginPhoneInputKeepsScreenshotLongValueToElevenDigits() {
        let viewModel = LoginViewModel()

        viewModel.sanitizePhoneInput("13800000001000000")

        XCTAssertEqual(viewModel.phoneNumber, "13800000001")
    }

    func testLoginPhoneSanitizeAlreadyCompleteValueKeepsElevenDigits() {
        let viewModel = LoginViewModel()
        viewModel.phoneNumber = "13800138000"

        viewModel.sanitizePhoneInput("138001380009")

        XCTAssertEqual(viewModel.phoneNumber, "13800138000")
    }

    func testLoginVerificationCodeInputKeepsOnlyFirstSixDigits() {
        let viewModel = LoginViewModel()

        viewModel.sanitizeVerificationCodeInput("000000789")

        XCTAssertEqual(viewModel.verificationCode, "000000")
    }

    func testLoginVerificationCodeInputDropsNonDigits() {
        let viewModel = LoginViewModel()

        viewModel.sanitizeVerificationCodeInput("abc 000-000 xyz")

        XCTAssertEqual(viewModel.verificationCode, "000000")
    }

    func testLoginVerificationCodeDirectAssignmentKeepsOnlyFirstSixDigits() {
        let viewModel = LoginViewModel()

        viewModel.verificationCode = "000000789"

        XCTAssertEqual(viewModel.verificationCode, "000000")
    }

    func testLoginVerificationCodeSanitizeAlreadyCompleteValueKeepsSixDigits() {
        let viewModel = LoginViewModel()
        viewModel.verificationCode = AppConstants.Auth.demoVerificationCode

        viewModel.sanitizeVerificationCodeInput("0000007")

        XCTAssertEqual(viewModel.verificationCode, "000000")
    }

    func testSubmitLoginWithCompleteInputsDoesNotReenterVerificationCodeSetter() {
        let viewModel = LoginViewModel()
        viewModel.phoneNumber = "13800138000"
        viewModel.verificationCode = AppConstants.Auth.demoVerificationCode

        viewModel.submitLogin()

        XCTAssertEqual(viewModel.phoneNumber, "13800138000")
        XCTAssertEqual(viewModel.verificationCode, "000000")
    }

    func testRequestCodeShowsInputOnlyAfterSendCodeSucceeds() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let viewModel = LoginViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())
        viewModel.phoneNumber = "13800138000"

        viewModel.requestCode()

        XCTAssertTrue(viewModel.isSendingCode)
        XCTAssertFalse(viewModel.showCodeInput)
        XCTAssertNil(viewModel.countdown)

        let didSend = await waitUntil {
            viewModel.showCodeInput &&
            viewModel.countdown != nil &&
            !viewModel.isSendingCode
        }

        XCTAssertTrue(didSend)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testRequestCodeFailureDoesNotStartCountdownOrShowInput() async {
        let viewModel = LoginViewModel(apiClient: FailingAPIClient(error: APIError.networkError(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)
        )))
        viewModel.phoneNumber = "13800138000"

        viewModel.requestCode()

        let didFail = await waitUntil {
            viewModel.errorMessage != nil && !viewModel.isSendingCode
        }

        XCTAssertTrue(didFail)
        XCTAssertEqual(viewModel.errorMessage, APIError.serverUnavailableMessage)
        XCTAssertFalse(viewModel.showCodeInput)
        XCTAssertNil(viewModel.countdown)
    }

    /// send-code 响应里没有任何验证码字段（后端 `AuthService.sendCode` 返回 void），
    /// 提交的必须永远是用户自己输入的那 6 位，不做任何替换。
    func testVerifyCodeSubmitsExactlyWhatUserTyped() async {
        let client = LoginCodeCaptureAPIClient(sendCodeResponse: SendCodeResponse(
            success: true,
            message: "验证码已发送",
            code: "654321"
        ))
        let viewModel = LoginViewModel(apiClient: client)
        viewModel.phoneNumber = "13800000001"

        viewModel.requestCode()
        let didShowInput = await waitUntil { viewModel.showCodeInput }
        XCTAssertTrue(didShowInput)
        viewModel.sanitizeVerificationCodeInput(AppConstants.Auth.demoVerificationCode)

        let didCaptureTypedCode = await waitUntil { client.capturedVerifyCodeRequest?.code == AppConstants.Auth.demoVerificationCode }
        XCTAssertTrue(didCaptureTypedCode)
        XCTAssertEqual(client.capturedVerifyCodeRequest?.phone, "13800000001")
    }

    func testDevelopmentInitialEnvironmentKeepsSupportedDebugChoices() {
        XCTAssertEqual(AppState.resolvedInitialEnvironment(.mock, channel: .development), .mock)
        XCTAssertEqual(AppState.resolvedInitialEnvironment(.demoCloud, channel: .development), .demoCloud)
    }

    func testDemoReleaseLocksInitialEnvironmentToDemoCloud() {
        XCTAssertEqual(AppState.resolvedInitialEnvironment(.mock, channel: .demo), .demoCloud)
        XCTAssertEqual(AppState.resolvedInitialEnvironment(.demoCloud, channel: .demo), .demoCloud)
    }

    func testProductionReleaseLocksInitialEnvironmentToDemoCloud() {
        XCTAssertEqual(AppState.resolvedInitialEnvironment(.mock, channel: .production), .demoCloud)
        XCTAssertEqual(AppState.resolvedInitialEnvironment(.demoCloud, channel: .production), .demoCloud)
    }

    func testUnknownStoredEnvironmentIsRejected() {
        XCTAssertNil(AppState.storedEnvironment(from: "unsupported"))
    }

    /// **scheme 也是断言的一部分。** 退回 `http` 会让实时位置与 SOS 重新走明文，
    /// 而那一步在界面上没有任何症状：请求照常成功，只是所有人都能看。
    func testDemoCloudBaseURLUsesFiledDomain() {
        XCTAssertEqual(APIEnvironment.demoCloud.baseURL?.absoluteString, "https://blindrun.culiu-tech.com")
    }

    func testWebSocketUsesFixedCloudHost() throws {
        let baseURL = try XCTUnwrap(APIEnvironment.demoCloud.baseURL)
        let webSocketURL = try XCTUnwrap(WebSocketService.connectionURL(baseURL: baseURL, token: "jwt", role: .blind))

        // `wss` 没有独立的配置项，它是 `baseURL` 的 scheme 推导出来的
        // （`WebSocketService.connectionURL`）—— 所以这一条同时守着「WS 不许退回明文」。
        XCTAssertEqual(webSocketURL.scheme, "wss")
        XCTAssertEqual(webSocketURL.host, "blindrun.culiu-tech.com")
        XCTAssertEqual(webSocketURL.path, "/ws/blind")
        XCTAssertTrue(webSocketURL.absoluteString.contains("token=jwt"))
    }

    func testDebugEnvironmentSwitcherCyclesMockAndDemoCloud() {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        persistence.set(APIEnvironment.mock.rawValue, forKey: AppConstants.UserDefaultsKeys.apiEnvironment)
        let appState = AppState(persistence: persistence)

        XCTAssertEqual(appState.currentEnvironment, .mock)
        appState.switchToNextEnvironmentForTesting()
        XCTAssertEqual(appState.currentEnvironment, .demoCloud)
        appState.switchToNextEnvironmentForTesting()
        XCTAssertEqual(appState.currentEnvironment, .mock)
    }

    func testInjectedTestPersistenceNeverChangesStandardAppDomain() {
        let keys = AppStatePersistenceKeys.all
        let before = Dictionary(uniqueKeysWithValues: keys.map { ($0, UserDefaults.standard.object(forKey: $0).map(String.init(describing:))) })
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let appState = AppState(persistence: persistence)

        appState.currentEnvironment = .mock
        appState.accessToken = "unit-test-token"
        appState.userId = 4242
        appState.activeRole = .volunteer
        appState.clearSession()

        let after = Dictionary(uniqueKeysWithValues: keys.map { ($0, UserDefaults.standard.object(forKey: $0).map(String.init(describing:))) })
        XCTAssertEqual(before, after)
    }

    func testDefaultHostedXCTestPersistenceNeverChangesStandardAppDomain() {
        let keys = AppStatePersistenceKeys.all
        let before = Dictionary(uniqueKeysWithValues: keys.map { ($0, UserDefaults.standard.object(forKey: $0).map(String.init(describing:))) })
        let appState = AppState()

        appState.currentEnvironment = .mock
        appState.accessToken = "hosted-test-token"
        appState.userId = 4343
        appState.activeRole = .blind
        appState.clearSession()

        let after = Dictionary(uniqueKeysWithValues: keys.map { ($0, UserDefaults.standard.object(forKey: $0).map(String.init(describing:))) })
        XCTAssertEqual(before, after)
    }

    func testUITestPersistenceUsesDedicatedResettableDomain() {
        let persistence = UserDefaultsAppStatePersistence(suiteName: AppStatePersistenceFactory.uiTestSuiteName)
        defer { persistence.reset() }
        persistence.set("ui-token", forKey: AppConstants.UserDefaultsKeys.accessToken)
        XCTAssertEqual(persistence.string(forKey: AppConstants.UserDefaultsKeys.accessToken), "ui-token")
        persistence.reset()
        XCTAssertNil(persistence.string(forKey: AppConstants.UserDefaultsKeys.accessToken))
    }

    private final class LoginCodeCaptureAPIClient: APIClientProtocol, @unchecked Sendable {
        private let sendCodeResponse: SendCodeResponse
        private(set) var capturedVerifyCodeRequest: VerifyCodeRequest?

        init(sendCodeResponse: SendCodeResponse) {
            self.sendCodeResponse = sendCodeResponse
        }

        func request<T: Decodable>(
            method: HTTPMethod,
            path: String,
            query: [String: String]?,
            body: (any Encodable & Sendable)?,
            requiresAuth: Bool
        ) async throws -> T {
            if method == .post, path == "/api/auth/send-code" {
                guard let response = sendCodeResponse as? T else {
                    throw APIError.decodingError(NSError(domain: "LoginCodeCaptureAPIClient", code: 1))
                }
                return response
            }

            if method == .post, path == "/api/auth/verify-code" {
                guard let request = decodeBody(VerifyCodeRequest.self, from: body) else {
                    throw APIError.decodingError(NSError(domain: "LoginCodeCaptureAPIClient", code: 2))
                }
                capturedVerifyCodeRequest = request
                guard let response = LoginResponse(token: "test-token", userId: 1, role: nil) as? T else {
                    throw APIError.decodingError(NSError(domain: "LoginCodeCaptureAPIClient", code: 3))
                }
                return response
            }

            throw APIError.invalidURL
        }

        func upload<T: Decodable>(
            path: String,
            query: [String: String]?,
            fields: [String: String]?,
            files: [MultipartFile],
            requiresAuth: Bool
        ) async throws -> T {
            throw APIError.invalidURL
        }

        private func decodeBody<T: Decodable>(_ type: T.Type, from body: (any Encodable & Sendable)?) -> T? {
            body as? T
        }
    }
}
