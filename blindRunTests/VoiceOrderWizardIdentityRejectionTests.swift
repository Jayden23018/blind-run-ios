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
}
