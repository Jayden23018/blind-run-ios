import UIKit
import XCTest
@testable import blindRun

/// 首启登录与建档的可听反馈与防误触（#657，OpenSpec `add-onboarding-audible-feedback`）。
///
/// 断言打在 `spokenHistoryForTesting` 上，不打在 `lastSpokenText` 上：
/// 这一轮修的全是「一声不响」，要证明的是**这一句真的被送进了合成器**。
@MainActor
final class OnboardingAudibleFeedbackTests: XCTestCase {

    // MARK: - 登录（B-8）

    func testSendingTheCodeAnnouncesThatItWasSent() async {
        let transport = RecordingTransport()
        transport.nextResponse = SendCodeResponse(success: true, message: "", code: nil)
        let speech = SpeechService()
        let appState = AppState(persistence: AppStatePersistenceFactory.makeIsolatedTest())
        let viewModel = LoginViewModel(apiClient: transport)
        viewModel.configure(with: appState, speechService: speech)
        viewModel.phoneNumber = "13800138000"

        viewModel.requestCode()
        await waitUntil { viewModel.showCodeInput }

        XCTAssertTrue(
            speech.spokenHistoryForTesting.contains(LoginViewModel.codeSentAnnouncement),
            "发送成功没有播报，实际播过：\(speech.spokenHistoryForTesting)"
        )
    }

    func testLoggingInWithAnEmptyCodeSpeaksAndRefocusesWithoutARequest() async {
        let transport = RecordingTransport()
        let speech = SpeechService()
        let viewModel = makeLoginViewModel(transport: transport, speech: speech)
        viewModel.verificationCode = ""

        viewModel.submitLogin()
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(transport.requests.isEmpty, "空验证码不该发登录请求")
        XCTAssertEqual(viewModel.errorMessage, "请输入验证码。验证码是 6 位数字。")
        XCTAssertEqual(speech.spokenHistoryForTesting, ["请输入验证码。验证码是 6 位数字。"])
        XCTAssertEqual(viewModel.codeFieldFocusRequest, 1, "焦点没有被请求回验证码输入框")
    }

    func testLoggingInWithAShortCodeSaysHowManyDigitsWereTyped() {
        let speech = SpeechService()
        let viewModel = makeLoginViewModel(transport: RecordingTransport(), speech: speech)
        viewModel.verificationCode = "1234"

        viewModel.submitLogin()

        XCTAssertEqual(viewModel.errorMessage, "验证码是 6 位数字，现在输入了 4 位。")
        XCTAssertEqual(speech.spokenHistoryForTesting, ["验证码是 6 位数字，现在输入了 4 位。"])
        XCTAssertEqual(viewModel.codeFieldFocusRequest, 1)
    }

    func testAWrongCodeIsSpokenAndFocusReturnsToTheField() async {
        let transport = RecordingTransport()
        transport.nextError = APIError.serverError(
            ErrorResponse(code: ErrorCode.invalidVerificationCode.rawValue, message: "验证码错误")
        )
        let speech = SpeechService()
        let viewModel = makeLoginViewModel(transport: transport, speech: speech)
        viewModel.verificationCode = "123456"

        viewModel.submitLogin()
        await waitUntil { viewModel.errorMessage != nil && !viewModel.isLoading }

        XCTAssertEqual(viewModel.errorMessage, "验证码错误，请重新输入")
        XCTAssertTrue(viewModel.verificationCode.isEmpty)
        XCTAssertTrue(speech.spokenHistoryForTesting.contains("验证码错误，请重新输入"))
        XCTAssertEqual(viewModel.codeFieldFocusRequest, 1, "填错后焦点没有回到验证码输入框")
    }

    // MARK: - 选角色（B-7 / V-25）

    func testTappingARoleCardOnlyAsksForConfirmation() async {
        let transport = RecordingTransport()
        let (viewModel, appState) = makeRoleViewModel(transport: transport)

        viewModel.requestRole(.blind)
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(viewModel.pendingRole, .blind)
        XCTAssertTrue(transport.requests.isEmpty, "点一次卡片就提交了，没有确认这一步")
        _ = appState
    }

    func testConfirmingSubmitsTheChosenRoleOnce() async {
        let transport = RecordingTransport()
        let (viewModel, appState) = makeRoleViewModel(transport: transport)

        viewModel.requestRole(.volunteer)
        viewModel.confirmPendingRole()
        await waitUntil { !transport.requests.isEmpty && !viewModel.isLoading }

        XCTAssertNil(viewModel.pendingRole)
        XCTAssertEqual(transport.requests.map(\.path), ["/api/user/role"])
        XCTAssertEqual((transport.requests.first?.body as? SetRoleRequest)?.role, .volunteer)
        _ = appState
    }

    func testChoosingAgainSubmitsNothing() async {
        let transport = RecordingTransport()
        let (viewModel, appState) = makeRoleViewModel(transport: transport)

        viewModel.requestRole(.blind)
        viewModel.cancelPendingRole()
        viewModel.confirmPendingRole()
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNil(viewModel.pendingRole)
        XCTAssertTrue(transport.requests.isEmpty)
        _ = appState
    }

    func testConfirmationNamesTheRoleAndSaysItCannotBeChanged() {
        let blind = RoleSelectionViewModel.confirmationMessage(for: .blind)
        XCTAssertTrue(blind.contains("盲人跑者"), blind)
        XCTAssertTrue(blind.contains("不能更改"), blind)

        let volunteer = RoleSelectionViewModel.confirmationMessage(for: .volunteer)
        XCTAssertTrue(volunteer.contains("志愿者"), volunteer)
        XCTAssertFalse(volunteer.contains("盲人跑者"), "志愿者的确认里念成了盲人跑者：\(volunteer)")
        XCTAssertEqual(RoleSelectionViewModel.confirmButtonTitle(for: .blind), "确认，我是盲人跑者")
    }

    // MARK: - 保存资料（B-6）

    func testSavingTheProfileShowsAndSpeaksSaved() async {
        let transport = RecordingTransport()
        transport.nextResponse = BlindProfileResponse(name: "测试昵称")
        let speech = SpeechService()
        let appState = AppState(apiClient: transport, persistence: AppStatePersistenceFactory.makeIsolatedTest())
        let viewModel = BlindRunnerProfileViewModel()
        viewModel.configure(with: appState, speechService: speech)
        viewModel.name = "测试昵称"

        viewModel.submit()
        await waitUntil { viewModel.savedNotice != nil || viewModel.errorMessage != nil }

        XCTAssertEqual(viewModel.savedNotice, "资料已保存。")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(speech.spokenHistoryForTesting.contains("资料已保存。"))
    }

    // MARK: - 紧急联系人（B-10、B-32）

    func testPickedPhoneDropsCountryCodeAndSeparators() {
        XCTAssertEqual(ContactPhonePick.normalizedPhone("+86 138-0013-8000"), "13800138000")
        XCTAssertEqual(ContactPhonePick.normalizedPhone("0086 13800138000"), "13800138000")
        XCTAssertEqual(ContactPhonePick.normalizedPhone("138 0013 8000"), "13800138000")
        // 座机不是 11 位手机号：原样给出数字，让表单校验去拦，不能硬凑成手机号。
        XCTAssertEqual(ContactPhonePick.normalizedPhone("(010) 6512-3456"), "01065123456")
        // 恰好以 86 开头的 11 位号码不能被误剥。
        XCTAssertEqual(ContactPhonePick.normalizedPhone("86123456789"), "86123456789")
    }

    func testPickAnnouncementReadsOnlyTheLastFourDigits() {
        let ok = EmergencyContactFormView.pickAnnouncement(name: "王芳", phone: "13800138000")
        XCTAssertTrue(ok.contains("王芳"), ok)
        XCTAssertTrue(ok.contains("8000"), ok)
        XCTAssertFalse(ok.contains("13800138000"), "播报里出现了完整号码：\(ok)")

        let landline = EmergencyContactFormView.pickAnnouncement(name: "王芳", phone: "01065123456")
        XCTAssertTrue(landline.contains("不是 11 位手机号"), landline)
    }

    func testEditSaveHintNeverPromisesANotificationSms() {
        let edit = EmergencyContactFormView.saveHint(isEditing: true, validationMessage: nil)
        XCTAssertFalse(edit.contains("会向该号码发送"), "编辑态的保存提示又说会发短信：\(edit)")
        XCTAssertTrue(edit.contains("不会"), edit)

        let add = EmergencyContactFormView.saveHint(isEditing: false, validationMessage: nil)
        XCTAssertTrue(add.contains("会向该号码发送一条告知短信"), add)

        XCTAssertEqual(
            EmergencyContactFormView.saveHint(isEditing: true, validationMessage: "请填写联系人姓名。"),
            "请填写联系人姓名。"
        )
    }

    // MARK: - 实名（B-11）

    func testANetworkFailureKeepsTheTypedIdentity() async {
        let transport = RecordingTransport()
        transport.nextError = APIError.networkError(URLError(.notConnectedToInternet))
        let appState = AppState(apiClient: transport, persistence: AppStatePersistenceFactory.makeIsolatedTest())
        let viewModel = BlindIdentityVerificationViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())
        viewModel.idCardName = "张三"
        viewModel.idCardNumber = "11010119900307123X"

        viewModel.submit()
        await waitUntil { viewModel.errorMessage != nil && !viewModel.isSubmitting }

        XCTAssertEqual(viewModel.idCardName, "张三", "断网就把姓名清了")
        XCTAssertEqual(viewModel.idCardNumber, "11010119900307123X", "断网就把身份证号清了")
        XCTAssertTrue(
            viewModel.errorMessage?.contains(BlindIdentityVerificationViewModel.keptAfterNetworkFailureSuffix) == true,
            viewModel.errorMessage ?? ""
        )
    }

    func testReturningAfterTheBackgroundClearSaysWhy() async {
        let speech = SpeechService()
        let appState = AppState(persistence: AppStatePersistenceFactory.makeIsolatedTest())
        let viewModel = BlindIdentityVerificationViewModel()
        viewModel.configure(with: appState, speechService: speech)
        viewModel.idCardName = "张三"
        viewModel.idCardNumber = "1101011990"

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        await waitUntil { viewModel.idCardNumber.isEmpty }
        XCTAssertNil(viewModel.clearedOnBackgroundNotice, "还在后台就说话了")

        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        await waitUntil { viewModel.clearedOnBackgroundNotice != nil }

        XCTAssertEqual(viewModel.clearedOnBackgroundNotice, BlindIdentityVerificationViewModel.clearedOnBackgroundMessage)
        XCTAssertTrue(speech.spokenHistoryForTesting.contains(BlindIdentityVerificationViewModel.clearedOnBackgroundMessage))
    }

    func testReturningWithNothingClearedStaysQuiet() async {
        let speech = SpeechService()
        let appState = AppState(persistence: AppStatePersistenceFactory.makeIsolatedTest())
        let viewModel = BlindIdentityVerificationViewModel()
        viewModel.configure(with: appState, speechService: speech)

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertNil(viewModel.clearedOnBackgroundNotice, "什么都没填也说「已清空」，用户会以为丢了东西")
    }

    func testTrailingXIsOnlyAcceptedAsTheEighteenthCharacter() {
        let speech = SpeechService()
        let appState = AppState(persistence: AppStatePersistenceFactory.makeIsolatedTest())
        let viewModel = BlindIdentityVerificationViewModel()
        viewModel.configure(with: appState, speechService: speech)

        viewModel.idCardNumber = "1101011990"
        XCTAssertNotNil(viewModel.appendTrailingX())
        XCTAssertEqual(viewModel.idCardNumber, "1101011990", "X 被追加到了中间")
        XCTAssertTrue(speech.spokenHistoryForTesting.last?.contains("第 18 位") == true)

        viewModel.idCardNumber = "11010119900307123"
        XCTAssertNil(viewModel.appendTrailingX())
        XCTAssertEqual(viewModel.idCardNumber, "11010119900307123X")
        XCTAssertTrue(viewModel.isIdCardNumberValid)
    }

    func testSpelledOutIdCardSplitsIntoRegionBirthdayAndRest() {
        XCTAssertEqual(
            BlindIdentityVerificationViewModel.spelledOutIdCard("11010119900307123X"),
            "1 1 0 1 0 1，1 9 9 0 0 3 0 7，1 2 3 X"
        )
        XCTAssertEqual(BlindIdentityVerificationViewModel.spelledOutIdCard("1101"), "1 1 0 1")
    }

    // MARK: - Helpers

    private func makeLoginViewModel(transport: RecordingTransport, speech: SpeechService) -> LoginViewModel {
        let viewModel = LoginViewModel(apiClient: transport)
        // weak 依赖：AppState 要活到用例结束，挂在实例上。
        let appState = AppState(persistence: AppStatePersistenceFactory.makeIsolatedTest())
        retainedAppStates.append(appState)
        viewModel.configure(with: appState, speechService: speech)
        viewModel.phoneNumber = "13800138000"
        speech.resetSpokenHistoryForTesting()
        return viewModel
    }

    private func makeRoleViewModel(transport: RecordingTransport) -> (RoleSelectionViewModel, AppState) {
        let appState = AppState(persistence: AppStatePersistenceFactory.makeIsolatedTest())
        let viewModel = RoleSelectionViewModel(apiClient: transport)
        viewModel.configure(with: appState, speechService: SpeechService())
        return (viewModel, appState)
    }

    private var retainedAppStates: [AppState] = []

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
