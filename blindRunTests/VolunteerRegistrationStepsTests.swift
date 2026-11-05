import XCTest
@testable import blindRun

/// 注册第 1 步拆成「说明页 → 身份 → 经历」之后的走向（#699，OpenSpec `split-volunteer-identity-into-steps`）。
///
/// 守三件事：
/// 1. 身份那一屏三项必填没齐，「下一步」放不过去，并且能说出还差哪几项。
/// 2. 接口不变：身份和经历仍是**一次**提交。
/// 3. 说明页选了「改为上传身份材料」的人，身份核验一通过就走现有的拒绝人脸接口，不再被引去刷脸。
@MainActor
final class VolunteerRegistrationStepsTests: XCTestCase {

    // MARK: - 身份那一屏

    func testIdentityPageListsWhatIsStillMissingInScreenOrder() {
        let viewModel = VolunteerRegistrationViewModel(apiClient: StepsFlowAPIClient(statuses: []))
        XCTAssertEqual(viewModel.identityPageMissingFields, ["姓名", "身份证号"], "手机号登录时已核验，不再要（#768）")

        viewModel.name = "测试志愿者"
        // 17 位：差一位也要算「还差身份证号」，不是只看有没有填。
        viewModel.idCardNumber = "11010119900101123"
        XCTAssertEqual(viewModel.identityPageMissingFields, ["正确的 18 位身份证号"])

        viewModel.idCardNumber = "110101199001011234"
        XCTAssertEqual(viewModel.identityPageMissingFields, [])
    }

    func testNextOnIdentityPageWaitsForAllRequiredFieldsAndBackKeepsWhatWasTyped() {
        let viewModel = VolunteerRegistrationViewModel(apiClient: StepsFlowAPIClient(statuses: []))
        XCTAssertEqual(viewModel.basicInfoPage, .intro, "进注册先看说明页")

        viewModel.startIdentityEntry(prefersAlternativePath: false)
        XCTAssertEqual(viewModel.basicInfoPage, .identity)

        viewModel.name = "测试志愿者"
        viewModel.advanceToExperiencePage()
        XCTAssertEqual(viewModel.basicInfoPage, .identity, "身份证号没填，不能进经历那一屏")

        fillIdentity(viewModel)
        viewModel.advanceToExperiencePage()
        XCTAssertEqual(viewModel.basicInfoPage, .experience)

        viewModel.runningExperience = "每周跑 3 次"
        viewModel.returnToIdentityPage()
        XCTAssertEqual(viewModel.basicInfoPage, .identity)
        XCTAssertEqual(viewModel.name, "测试志愿者", "上一步不能清掉已填的内容")
        XCTAssertEqual(viewModel.runningExperience, "每周跑 3 次")
    }

    // MARK: - 一次提交

    func testExperienceIsSubmittedTogetherWithIdentityInOneRequest() async {
        let client = StepsFlowAPIClient(statuses: [Self.stepThreeStatus])
        let appState = makeAppState()
        let speech = SpeechService()
        let viewModel = VolunteerRegistrationViewModel(apiClient: client)
        viewModel.configure(appState: appState, speechService: speech)
        viewModel.startIdentityEntry(prefersAlternativePath: false)
        fillIdentity(viewModel)
        viewModel.advanceToExperiencePage()
        viewModel.hasGuidedBefore = true
        viewModel.runningExperience = "每周跑 3 次"
        viewModel.emergencyExperience = "有急救证"

        await viewModel.submitBasicInfo()

        XCTAssertEqual(client.submittedRequests.count, 1, "接口不变：身份和经历只发一次")
        let request = client.submittedRequests.first
        XCTAssertEqual(request?.idCardNumber, "110101199001011234")
        XCTAssertEqual(request?.hasGuidedBefore, true)
        XCTAssertEqual(request?.runningExperience, "每周跑 3 次")
        XCTAssertEqual(request?.emergencyExperience, "有急救证")
        XCTAssertEqual(viewModel.currentStep, .faceVerify)
        XCTAssertEqual(client.declineCount, 0, "没在说明页选人工审核，不能代他拒绝人脸")
        XCTAssertEqual(speech.lastSpokenText, "身份核验通过，请开始刷脸")
    }

    // MARK: - 说明页选了「改为上传身份材料」

    func testAlternativeChoiceOnIntroDeclinesFaceRightAfterIdentityPasses() async {
        let client = StepsFlowAPIClient(
            statuses: [Self.stepThreeStatus, Self.declinedStatus],
            declineMessage: "已为你改用身份证二要素核验加人工审核。"
        )
        let appState = makeAppState()
        let speech = SpeechService()
        let viewModel = VolunteerRegistrationViewModel(apiClient: client)
        viewModel.configure(appState: appState, speechService: speech)
        viewModel.startIdentityEntry(prefersAlternativePath: true)
        XCTAssertTrue(viewModel.prefersAlternativeIdentityPath)
        fillIdentity(viewModel)
        viewModel.advanceToExperiencePage()

        await viewModel.submitBasicInfo()

        XCTAssertEqual(client.submittedRequests.count, 1, "二要素照样要提交：拒绝接口要求它先通过")
        XCTAssertEqual(client.declineCount, 1, "身份通过后要真的打拒绝接口，不能只改本地状态")
        XCTAssertTrue(viewModel.hasDeclinedFaceVerification)
        XCTAssertTrue(viewModel.isRegistrationCompleted, "落到现有的「已选择替代认证方式」页")
        XCTAssertEqual(
            speech.lastSpokenText, "已为你改用身份证二要素核验加人工审核。",
            "最后一句必须是拒绝的那句，不能是「请开始刷脸」"
        )
        XCTAssertNil(viewModel.faceVerifyMessage, "不该再显示「身份核验通过，请开始刷脸」")
    }

    // MARK: - 后端退回第 1 步

    func testRollbackFromFaceStepLandsOnIdentityPageNotIntro() {
        let viewModel = VolunteerRegistrationViewModel(apiClient: StepsFlowAPIClient(statuses: []))
        viewModel.applyRegistrationStatus(Self.stepOneStatus)
        XCTAssertEqual(viewModel.basicInfoPage, .intro, "第一次进来停在说明页")

        viewModel.applyRegistrationStatus(Self.stepThreeStatus)
        XCTAssertEqual(viewModel.currentStep, .faceVerify)

        viewModel.applyRegistrationStatus(Self.stepOneStatus)
        XCTAssertEqual(viewModel.currentStep, .basicInfo)
        XCTAssertEqual(viewModel.basicInfoPage, .identity, "要改的是姓名和身份证号，不该让他从说明页重走")
    }

    // MARK: - Helpers

    private func fillIdentity(_ viewModel: VolunteerRegistrationViewModel) {
        viewModel.name = "测试志愿者"
        viewModel.idCardNumber = "110101199001011234"
    }

    /// 调用方作用域里的 `let`：view model 对 AppState 是 weak 引用，临时对象会当场释放。
    private func makeAppState() -> AppState {
        let appState = AppState()
        appState.currentEnvironment = .mock
        return appState
    }

    private static let stepOneStatus = VolunteerRegistrationStatus(
        registrationStep: "STEP_1_BASIC_INFO",
        registrationCompleted: false,
        canAcceptOrders: false,
        stepDetails: VolunteerRegistrationStepDetails(idVerifyStatus: "NOT_STARTED", faceVerifyStatus: "NOT_STARTED"),
        step1Completed: false
    )

    private static let stepThreeStatus = VolunteerRegistrationStatus(
        registrationStep: "STEP_3_FACE_VERIFY",
        registrationCompleted: false,
        canAcceptOrders: false,
        stepDetails: VolunteerRegistrationStepDetails(idVerifyStatus: "APPROVED", faceVerifyStatus: "NOT_STARTED"),
        step1Completed: true
    )

    private static let declinedStatus = VolunteerRegistrationStatus(
        registrationStep: "STEP_3_FACE_VERIFY",
        registrationCompleted: true,
        canAcceptOrders: false,
        stepDetails: VolunteerRegistrationStepDetails(idVerifyStatus: "APPROVED", faceVerifyStatus: "DECLINED"),
        step1Completed: true
    )
}

// MARK: - Stub

/// 三条路径：提交第 1 步、拒绝人脸、状态回读。`statuses` 是**每一次 GET 依次返回什么**的队列。
private final class StepsFlowAPIClient: APIClientProtocol, @unchecked Sendable {
    private var statuses: [VolunteerRegistrationStatus]
    private var lastServedStatus = VolunteerRegistrationStatus()
    private let declineMessage: String?

    private(set) var submittedRequests: [BasicInfoRequest] = []
    private(set) var declineCount = 0

    init(statuses: [VolunteerRegistrationStatus], declineMessage: String? = nil) {
        self.statuses = statuses
        self.declineMessage = declineMessage
    }

    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        if method == .post, path == "/api/volunteer/registration/step1" {
            guard let request = body as? BasicInfoRequest, let response = EmptyResponse() as? T else {
                throw APIError.invalidURL
            }
            submittedRequests.append(request)
            return response
        }
        if method == .post, path == "/api/volunteer/registration/step3/face-verify/decline" {
            declineCount += 1
            guard let response = FaceVerifyDeclineResponse(message: declineMessage) as? T else {
                throw APIError.invalidURL
            }
            return response
        }
        if method == .get, path == "/api/volunteer/registration/status" {
            if !statuses.isEmpty { lastServedStatus = statuses.removeFirst() }
            guard let response = lastServedStatus as? T else { throw APIError.invalidURL }
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
}
