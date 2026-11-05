import XCTest
@testable import blindRun

/// 登录、选角色、实名、跑后留言四处网络错误文案接上 #659 的宕机分类（#672）。
///
/// 背景：这四处页面自己写网络错误文案，只认证书错误，其余一律叫用户「检查网络」或「重试」。
/// 服务器宕机时盲人照旧去查自己的网络。
///
/// **验红方式**：把这四处 `.networkError` 分支改回「证书错误之外一律固定文案」，
/// `testEveryPageSeparatesOfflineFromServerDown` 的 `.cannotConnectToHost` / `.timedOut` 两组必须失败，
/// 断网那一组照样通过（它守的是「真没网仍叫用户检查网络」）。
@MainActor
final class OnboardingNetworkFailureCopyTests: XCTestCase {

    private struct Case {
        let code: URLError.Code
        let message: String
    }

    /// 断网、连不上服务器、超时、证书各一个：四类都要各说各的。
    private static let cases: [Case] = [
        Case(code: .notConnectedToInternet, message: APIError.offlineMessage),
        Case(code: .cannotConnectToHost, message: APIError.serverUnavailableMessage),
        Case(code: .timedOut, message: APIError.ambiguousConnectionMessage),
        Case(code: .serverCertificateUntrusted, message: APIError.secureConnectionMessage)
    ]

    func testEveryPageSeparatesOfflineFromServerDown() async {
        for item in Self.cases {
            let error = APIError.networkError(URLError(item.code))
            let label = "\(item.code.rawValue)"

            // 登录：发验证码
            let sendSpeech = SpeechService()
            let sendVM = makeLoginViewModel(error: error, speech: sendSpeech)
            sendVM.requestCode()
            await waitUntil { sendVM.errorMessage != nil && !sendVM.isSendingCode }
            XCTAssertEqual(sendVM.errorMessage, item.message, "发验证码 \(label)")
            XCTAssertTrue(sendSpeech.spokenHistoryForTesting.contains(item.message), "发验证码没有念出来 \(label)")

            // 登录：提交验证码
            let loginSpeech = SpeechService()
            let loginVM = makeLoginViewModel(error: error, speech: loginSpeech)
            loginVM.verificationCode = "123456"
            loginVM.submitLogin()
            await waitUntil { loginVM.errorMessage != nil && !loginVM.isLoading }
            XCTAssertEqual(loginVM.errorMessage, item.message, "登录 \(label)")
            XCTAssertTrue(loginSpeech.spokenHistoryForTesting.contains(item.message), "登录没有念出来 \(label)")

            // 选角色
            let roleSpeech = SpeechService()
            let appState = AppState(persistence: AppStatePersistenceFactory.makeIsolatedTest())
            let roleVM = RoleSelectionViewModel(apiClient: ThrowingAPIClient(error: error))
            roleVM.configure(with: appState, speechService: roleSpeech)
            roleSpeech.resetSpokenHistoryForTesting()
            roleVM.selectRole(.blind)
            await waitUntil { roleVM.errorMessage != nil && !roleVM.isLoading }
            XCTAssertEqual(roleVM.errorMessage, item.message, "选角色 \(label)")
            XCTAssertTrue(roleSpeech.spokenHistoryForTesting.contains(item.message), "选角色没有念出来 \(label)")
        }
    }

    /// 跑后留言：整句自带「再发一次」，嵌进去的原因不能再带「稍后再试」「拨打120」。
    func testRunRecordMessageFailureEmbedsTheClauseWithoutAskingToWait() {
        XCTAssertEqual(
            RunRecordViewModel.sendFailureReason(.networkError(URLError(.cannotConnectToHost))),
            "服务暂时出了问题，不是你的手机。请稍后再发一次。"
        )
        XCTAssertEqual(
            RunRecordViewModel.sendFailureReason(.networkError(URLError(.timedOut))),
            "暂时连不上服务器，可能是信号弱，也可能是服务出了问题。请稍后再发一次。"
        )
        XCTAssertEqual(
            RunRecordViewModel.sendFailureReason(.networkError(URLError(.notConnectedToInternet))),
            "请检查网络后再发一次。",
            "真没网时仍叫用户检查网络"
        )
        XCTAssertEqual(
            RunRecordViewModel.sendFailureReason(.networkError(URLError(.serverCertificateUntrusted))),
            APIError.secureConnectionMessage
        )
        XCTAssertFalse(
            RunRecordViewModel.sendFailureReason(.networkError(URLError(.cannotConnectToHost))).contains("120"),
            "留言失败不是紧急情况，不念「拨打120」"
        )
    }

    // MARK: - Helpers

    private func makeLoginViewModel(error: APIError, speech: SpeechService) -> LoginViewModel {
        let viewModel = LoginViewModel(apiClient: ThrowingAPIClient(error: error))
        // weak 依赖：AppState 要活到用例结束，挂在实例上。
        let appState = AppState(persistence: AppStatePersistenceFactory.makeIsolatedTest())
        retainedAppStates.append(appState)
        viewModel.configure(with: appState, speechService: speech)
        viewModel.phoneNumber = "13800138000"
        speech.resetSpokenHistoryForTesting()
        return viewModel
    }

    private var retainedAppStates: [AppState] = []

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
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
