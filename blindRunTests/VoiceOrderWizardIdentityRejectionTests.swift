import XCTest
@testable import blindRun

/// 后端 #852：未实名的盲人调 `/api/orders/voice/parse` 收到 403 `IDENTITY_NOT_VERIFIED`。
///
/// 开麦前 `VoiceOrderWizard.start()` 已经按本地实名状态拦过一次，所以只有本地记的状态过期时
/// 才会走到这里。重说多少遍都不会变好，所以要和开麦前被拦**念同一句**、交回表单。
/// 不许当成普通失败（「下面念的是默认值」「这次没能听明白」「暂时没听清」）——
/// 那会让人以为是自己没说清，一直重说。
@MainActor
final class VoiceOrderWizardIdentityRejectionTests: XCTestCase {
    private static let identityRejection = APIError.serverError(
        ErrorResponse(code: "IDENTITY_NOT_VERIFIED", message: "请先完成实名认证再使用语音输入")
    )

    func testIdentityRejectionOnTheFreeformRoundSpeaksTheIdentityGate() async {
        let stub = VoiceOrderAPIClientStub()
        stub.error = Self.identityRejection
        let bookingViewModel = BlindBookingViewModel()
        let wizard = makeWizard(stub: stub, bookingViewModel: bookingViewModel, startingAt: .freeform)

        await wizard.submitTranscript("明天早上七点从小区门口出发，跑一个小时")

        let gateMessage = BlindBookingGate.identityVerification.message
        XCTAssertFalse(wizard.isRunning, "没实名重说也没用，不该留在语音里")
        XCTAssertEqual(wizard.fallbackMessage, gateMessage, "屏幕上要留着去哪实名的说明")
        XCTAssertEqual(wizard.lastSpokenPrompt, gateMessage, "念的必须和开麦前被拦时同一句")
        XCTAssertNil(wizard.endedMessage)
        XCTAssertEqual(stub.paths, [VoiceOrderEndpoint.parseOrder], "被拒之后不许再发请求")
    }

    func testIdentityRejectionOnTheConfirmRoundIsNotTreatedAsANetworkFailure() async {
        let stub = VoiceOrderAPIClientStub()
        stub.error = Self.identityRejection
        let bookingViewModel = BlindBookingViewModel()
        let wizard = makeWizard(
            stub: stub, bookingViewModel: bookingViewModel, startingAt: .confirm, didCaptureStartTime: true
        )

        await wizard.submitTranscript("把时间往后挪一挪吧")

        let gateMessage = BlindBookingGate.identityVerification.message
        XCTAssertFalse(wizard.isRunning, "确认轮被拒也不许原地重问")
        XCTAssertEqual(wizard.lastSpokenPrompt, gateMessage)
        XCTAssertEqual(wizard.fallbackMessage, gateMessage)
        XCTAssertNil(wizard.createdOrder)
        XCTAssertEqual(stub.paths, [VoiceOrderEndpoint.parseOrder], "这句话必须真的交给了后端，否则测的不是 403 分支")
    }

    /// 被拒之后从后端重新拉实名状态：下单页的门槛要从「紧急联系人」变成「实名」，
    /// 「不用填，直接下单」按钮（`firstMissingGate == nil` 才出现）才不会留着一条必被 403 的路。
    func testIdentityRejectionRefreshesTheProfileSoTheBookingGateCatchesUp() async {
        let profileClient = BlindProfileAPIClientStub(verifyStatus: BlindVerifyStatus.notVerified.rawValue)
        let appState = AppState(apiClient: profileClient, tokenStore: InMemoryTokenStore())
        appState.updateBlindProfile(BlindProfileResponse(name: "张三", verifyStatus: BlindVerifyStatus.verified.rawValue))
        let bookingViewModel = BlindBookingViewModel()
        bookingViewModel.configureForTesting(speechService: SpeechService(), locationService: nil, appState: appState)
        XCTAssertEqual(bookingViewModel.firstMissingGate, .emergencyContacts, "前提：本地以为已实名")
        let stub = VoiceOrderAPIClientStub()
        stub.error = Self.identityRejection
        let wizard = makeWizard(stub: stub, bookingViewModel: bookingViewModel, startingAt: .freeform)

        await wizard.submitTranscript("明天早上七点从小区门口出发")
        await waitUntil { appState.blindIdentityStatus != .verified }

        XCTAssertEqual(profileClient.profileFetchCount, 1)
        XCTAssertEqual(appState.blindIdentityStatus, .notVerified)
        XCTAssertEqual(bookingViewModel.firstMissingGate, .identityVerification)
    }

    /// 拉资料期间换了账号（`sessionGeneration` 变了）：旧会话的资料不许写进新会话。
    func testProfileRefreshIsDroppedWhenTheSessionChangedMeanwhile() async {
        let profileClient = BlindProfileAPIClientStub(verifyStatus: BlindVerifyStatus.notVerified.rawValue)
        let appState = AppState(apiClient: profileClient, tokenStore: InMemoryTokenStore())
        appState.updateBlindProfile(BlindProfileResponse(name: "张三", verifyStatus: BlindVerifyStatus.verified.rawValue))
        profileClient.onProfileFetch = { appState.accessToken = "another-account-token" }
        let bookingViewModel = BlindBookingViewModel()
        bookingViewModel.configureForTesting(speechService: SpeechService(), locationService: nil, appState: appState)

        await bookingViewModel.refreshIdentityAfterServerRejection()

        XCTAssertEqual(profileClient.profileFetchCount, 1, "前提：请求确实发出、并在途中换了会话")
        XCTAssertNotEqual(appState.blindIdentityStatus, .notVerified, "旧会话拉到的资料写进了新会话")
    }

    /// 只认这一个错误码：别的 403 / 5xx 仍按原来的「偶发失败」处理，不许被一起带走。
    func testOtherServerErrorsOnTheFreeformRoundStillReadBackTheDefaults() async {
        let stub = VoiceOrderAPIClientStub()
        stub.error = .serverError(ErrorResponse(code: "ORDER_PERMISSION_DENIED", message: "无权限"))
        let bookingViewModel = BlindBookingViewModel()
        let wizard = makeWizard(stub: stub, bookingViewModel: bookingViewModel, startingAt: .freeform)

        await wizard.submitTranscript("明天早上七点从小区门口出发")

        XCTAssertTrue(wizard.isRunning, "偶发失败照旧读回默认值，让用户决定改不改")
        XCTAssertNil(wizard.fallbackMessage)
        XCTAssertTrue(
            wizard.lastSpokenPrompt?.contains(VoiceOrderWizard.parseFailureNotice) == true,
            "偶发失败的读回要先说明念的是默认值：\(wizard.lastSpokenPrompt ?? "")"
        )
    }

    /// 与 `VoiceOrderWizardTests.makeWizard` 同一套接线。`bookingViewModel` 由调用方持有：
    /// 向导里它是 weak，在这里当场构造就等于传 nil。
    private func makeWizard(
        stub: VoiceOrderAPIClientStub,
        bookingViewModel: BlindBookingViewModel,
        startingAt step: VoiceOrderWizard.Step,
        didCaptureStartTime: Bool = false
    ) -> VoiceOrderWizard {
        let wizard = VoiceOrderWizard()
        wizard.configure(
            bookingViewModel: bookingViewModel,
            speechService: SpeechService(),
            // 同上：weak，临时对象等于传 nil。用例走 `startForTesting(at:)`，不经过真正的开麦路径。
            speechInputService: SpeechInputService(), // guard:allow weak-temporary
            voiceOrderService: VoiceOrderService(transport: stub),
            currentCoordinate: nil
        )
        wizard.startForTesting(at: step, didCaptureStartTime: didCaptureStartTime)
        return wizard
    }

    /// 刷新跑在向导另起的 `Task` 里，`submitTranscript` 返回时它可能还没落地。最多等 2 秒。
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

/// 只接 `GET /api/blind/profile`。`onProfileFetch` 在返回前于主线程执行，用来模拟「请求途中换了账号」。
private final class BlindProfileAPIClientStub: APIClientProtocol, @unchecked Sendable {
    private let verifyStatus: String
    private(set) var profileFetchCount = 0
    var onProfileFetch: (@MainActor () -> Void)?

    init(verifyStatus: String) {
        self.verifyStatus = verifyStatus
    }

    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        guard method == .get, path == "/api/blind/profile" else { throw APIError.invalidURL }
        profileFetchCount += 1
        if let onProfileFetch { await onProfileFetch() }
        guard let response = BlindProfileResponse(name: "张三", verifyStatus: verifyStatus) as? T else {
            throw APIError.invalidURL
        }
        return response
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
}
