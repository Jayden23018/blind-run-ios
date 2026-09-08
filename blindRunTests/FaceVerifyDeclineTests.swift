import XCTest
@testable import blindRun

/// 「拒绝人脸 → 身份证二要素核验 + 人工审核」替代认证路径。
///
/// **这不是体验优化，是合规缺口。**《人脸识别技术应用安全管理办法》第十条：
/// 存在其他非人脸方式的，不得将人脸识别作为唯一验证方式；个人不同意人脸验证的，
/// 应当提供其他合理、便捷的方式。后端仓库三处对外法律文本（隐私政策 `:64`、
/// 用户协议 `:62` / `:194`）都写了这条路径存在 —— 用户与 App 审核员会照着文本去 App 里找它。
///
/// 所以这组用例守的是**两件在代码里看不出来、但一旦破就是合规事故**的事：
/// 1. `DECLINED` 绝不能被当成失败态展示（后端契约 `api_spec.yaml:4059-4064` 整段禁止）
/// 2. 文案不得编造审核时长，且必须与法律文本的「审核时间较长，但结果等效」一致
@MainActor
final class FaceVerifyDeclineTests: XCTestCase {

    // MARK: - 成功路径

    /// 拒绝成功后：注册流程放人出去（`registrationCompleted=true`），
    /// 但**不能**顺带把人当成「已完成认证」——他还欠一次人工审核。
    func testDeclineReleasesRegistrationFlowAndMarksAlternativePath() async {
        let client = DeclineFlowAPIClient(
            statuses: [Self.stepThreeStatus, Self.declinedStatus]
        )
        let (viewModel, _) = makeViewModel(client: client)

        await viewModel.declineFaceVerify()

        XCTAssertEqual(
            client.requestedPaths.filter { $0.hasSuffix("/face-verify/decline") }.count, 1,
            "拒绝必须真的打后端那条端点，不能只改本地状态"
        )
        XCTAssertTrue(viewModel.hasDeclinedFaceVerification)
        XCTAssertTrue(
            viewModel.isRegistrationCompleted,
            "DECLINED 时后端 registrationCompleted=true；卡住不放人的话，证书上传入口在注册流程之外，他永远够不到"
        )
        XCTAssertFalse(
            viewModel.isAwaitingRegistrationCompletion,
            "他没有在等活体结果，不能显示「活体已通过，注册状态同步中」那一屏"
        )
    }

    /// 🚨 **全流程只能播一句。**
    ///
    /// 合成器全进程只有一个且 `speak` 先 `stopSpeaking`，谁后说谁赢。
    /// `declineFaceVerify` 播完之后紧接着 `loadStatus` → `applyRegistrationStatus`，
    /// 那里在「注册完成」时**也**会播一句 —— 两处都播的表现是用户只听到半句就被切掉，
    /// 而且听到的是错的那半句（「请返回首页开启可服务状态」，可他根本开不了）。
    func testDeclineAnnouncesTheAlternativePathAndNotTheGenericCompletionLine() async {
        let client = DeclineFlowAPIClient(
            statuses: [Self.stepThreeStatus, Self.declinedStatus],
            declineMessage: "已为你改用身份证二要素核验加人工审核。"
        )
        let (viewModel, speech) = makeViewModel(client: client)

        await viewModel.declineFaceVerify()

        XCTAssertEqual(
            speech.lastSpokenText, "已为你改用身份证二要素核验加人工审核。",
            "最后一句必须是拒绝的那句。若这里变成通用完成语，说明 applyRegistrationStatus 把它盖掉了"
        )
        XCTAssertNotEqual(speech.lastSpokenText, "注册完成，请返回首页开启可服务状态")
    }

    /// 后端 200 但 `data` 为 null / 不是字符串时**不算失败** —— 端点已经成功了。
    ///
    /// `APIPayloadDecoder` 是「信封优先、裸解兜底」：`envelope.data` 为 nil 时会退回拿整个
    /// 信封对象去解 `String`，直接把返回类型写成 `String` 必然抛 `decodingError`。
    /// 而这个端点是**幂等**的，用户看到「失败」只会反复点，每一次其实都成功了。
    func testDeclineSucceedsWhenBackendOmitsTheSpokenMessage() async {
        let client = DeclineFlowAPIClient(
            statuses: [Self.stepThreeStatus, Self.declinedStatus],
            declineMessage: nil
        )
        let (viewModel, speech) = makeViewModel(client: client)

        await viewModel.declineFaceVerify()

        XCTAssertNil(viewModel.errorMessage, "文案缺失是可降级的，不能报错")
        XCTAssertTrue(viewModel.hasDeclinedFaceVerification)
        XCTAssertEqual(
            speech.lastSpokenText, VolunteerRegistrationViewModel.declineFallbackAnnouncement,
            "拿不到后端文案时要用本地兜底那句，而不是不吭声"
        )
    }

    /// 解码层单独钉一遍：畸形/缺失的 `data` 一律给 nil，**绝不抛**。
    func testDeclineResponseNeverThrowsOnNonStringPayload() throws {
        let decoder = JSONDecoder()

        let plain = try decoder.decode(
            FaceVerifyDeclineResponse.self, from: Data(#""已切换认证方式""#.utf8)
        )
        XCTAssertEqual(plain.message, "已切换认证方式")

        // 信封里 data 为 null → APIPayloadDecoder 会拿整个信封对象来裸解这个类型
        let envelope = try decoder.decode(
            FaceVerifyDeclineResponse.self,
            from: Data(#"{"success":true,"code":200,"data":null}"#.utf8)
        )
        XCTAssertNil(envelope.message)

        let unexpected = try decoder.decode(
            FaceVerifyDeclineResponse.self, from: Data(#"{"foo":1}"#.utf8)
        )
        XCTAssertNil(unexpected.message)
    }

    // MARK: - 三种错误情形（409 两种 + 400 一种）

    /// 409 之一：活体**已经通过**了。这一句尤其不能说成失败 —— 他其实已经认证完了。
    func testDeclineAfterFaceApprovedSaysAlreadyVerifiedRatherThanFailed() async {
        let client = DeclineFlowAPIClient(
            statuses: [Self.stepThreeStatus, Self.approvedStatus],
            declineError: APIError.serverError(
                ErrorResponse(code: "REGISTRATION_STEP_INVALID", message: "活体认证已通过，无需使用替代认证方式")
            )
        )
        let (viewModel, speech) = makeViewModel(client: client)

        await viewModel.declineFaceVerify()

        XCTAssertEqual(viewModel.errorMessage, VolunteerRegistrationViewModel.declineAlreadyVerifiedMessage)
        XCTAssertFalse(viewModel.hasDeclinedFaceVerification)
        // 409 的两个子情形共用同一个 errorCode，只能靠刷新后的状态区分——所以必须真的去刷新。
        XCTAssertEqual(client.statusRefreshCount, 1)

        // 🚨 **这一支是全流程唯一会双重播报的地方**，也是最容易被漏掉的：
        // 刷回来的状态恰好是「注册已完成」，`applyRegistrationStatus` 会先播
        // 「注册完成，请返回首页开启可服务状态」，紧接着被这里的 speakError 从半句切断，
        // 而那句残片本身还是错的引导 —— 他刚点的是「不同意人脸认证」。
        //
        // ⚠️ 只断言 `lastSpokenText` **抓不到**这个回归：`speakError` 内部也走 `speak(text:)`，
        // 最后一句永远是对的那句。必须数**播了几次**。
        XCTAssertEqual(
            speech.spokenHistoryForTesting,
            [VolunteerRegistrationViewModel.declineAlreadyVerifiedMessage],
            "整条失败路径只许播一句。多出「注册完成…」说明 loadStatus 的播报没被压住"
        )
    }

    /// 409 之二：步骤位对不上。刷新对齐，但同样不许说「失败，请重试」。
    func testDeclineWithStaleStepRealignsInsteadOfClaimingFailure() async {
        let client = DeclineFlowAPIClient(
            statuses: [Self.stepThreeStatus, Self.stepThreeStatus],
            declineError: APIError.serverError(
                ErrorResponse(code: "REGISTRATION_STEP_INVALID", message: "当前步骤不允许选择替代认证方式")
            )
        )
        let (viewModel, _) = makeViewModel(client: client)

        await viewModel.declineFaceVerify()

        XCTAssertEqual(viewModel.errorMessage, VolunteerRegistrationViewModel.declineStepChangedMessage)
        XCTAssertNotEqual(
            viewModel.errorMessage, VolunteerRegistrationViewModel.declineAlreadyVerifiedMessage,
            "活体没通过的人不能被告知「你已完成人脸认证」"
        )
        XCTAssertEqual(client.statusRefreshCount, 1)
    }

    /// 400：二要素不是 `APPROVED`。后端**已经**把步骤位回退到 `STEP_1_BASIC_INFO`。
    ///
    /// 这一条必须**真的把界面跳回基本信息页**，不能只播一句提示 ——
    /// step1 是跑二要素的唯一入口，停在活体页的话他没有任何可点的东西能解决这个问题。
    func testDeclineWithoutApprovedIdVerificationReturnsToBasicInfoStep() async {
        let client = DeclineFlowAPIClient(
            statuses: [Self.stepThreeStatus, Self.rolledBackToStepOneStatus],
            declineError: APIError.serverError(
                ErrorResponse(code: "ID_INFO_INVALID", message: "身份信息未通过核验，请重新提交基本信息")
            )
        )
        let (viewModel, _) = makeViewModel(client: client)

        await viewModel.declineFaceVerify()

        XCTAssertEqual(
            viewModel.currentStep, .basicInfo,
            "后端已回退到 STEP_1，界面必须跟着回去，否则他卡在一个解决不了的页面上"
        )
        XCTAssertEqual(viewModel.errorMessage, VolunteerRegistrationViewModel.declineNeedsIdVerificationMessage)
        XCTAssertFalse(viewModel.hasDeclinedFaceVerification)
    }

    // MARK: - 回到人脸路径

    /// 后端允许「先拒绝、后来又想做人脸」（幂等、不锁死），客户端也必须给得回去。
    func testReturnToFaceVerificationReopensTheFacePath() async {
        let client = DeclineFlowAPIClient(statuses: [Self.stepThreeStatus, Self.declinedStatus])
        let (viewModel, _) = makeViewModel(client: client)
        await viewModel.declineFaceVerify()
        XCTAssertFalse(
            viewModel.canStartFaceVerify,
            "前提：拒绝之后注册已算完成，此时活体入口本来是关着的"
        )

        viewModel.returnToFaceVerification()

        XCTAssertEqual(viewModel.currentStep, .faceVerify)
        XCTAssertTrue(
            viewModel.canStartFaceVerify,
            "回头入口必须真的把活体按钮打开；只切页面不放开 canStartFaceVerify 的表现是「点了没反应」"
        )
    }

    /// 拒绝入口的开放条件必须与活体入口**一致** —— 监管口径要求替代方式「同等便捷」，
    /// 不能比人脸那条更难够到。
    func testDeclineEntryIsExactlyAsAvailableAsTheFaceEntry() {
        let client = DeclineFlowAPIClient(statuses: [Self.stepThreeStatus])
        let (viewModel, _) = makeViewModel(client: client)

        viewModel.applyRegistrationStatus(Self.stepThreeStatus)
        XCTAssertTrue(viewModel.canStartFaceVerify)
        XCTAssertEqual(viewModel.canDeclineFaceVerify, viewModel.canStartFaceVerify)

        viewModel.applyRegistrationStatus(Self.approvedStatus)
        XCTAssertFalse(viewModel.canStartFaceVerify)
        XCTAssertEqual(viewModel.canDeclineFaceVerify, viewModel.canStartFaceVerify)
    }

    // MARK: - 上传页文案的路径判定

    /// 🚨 **刚 decline 完直接点「去上传身份材料」时，`AppState` 必然还是旧快照。**
    ///
    /// `applyRegistrationStatus` 在「注册已完成」时**刻意不立刻**把状态发布给 AppState
    /// （发布会翻 `isVolunteerProfileApproved`，根路由当场把注册流连同那一页一起拆掉），
    /// 要等用户点「返回志愿者首页」才发布。于是上传页的自动判定会读到拒绝前的旧值，
    /// 把整页显示成「资质证书」—— 而他手上根本没有资质证书。
    /// 这个错**不会自愈**：上传页的 `.task` 只刷证书审核状态，从不刷注册状态。
    func testUploadPageEnteredStraightFromDeclineStillShowsTheIdentityMaterialCopy() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        // 复现那一刻的真实状态：注册状态还停在拒绝之前。
        appState.updateVolunteerRegistrationStatus(Self.stepThreeStatus)
        let viewModel = VolunteerCertificateUploadViewModel()

        viewModel.configure(with: appState, speechService: SpeechService())
        XCTAssertFalse(
            viewModel.isAlternativeIdentityPath,
            "前提：只看 AppState 的话，这一刻判出来就是错的（旧快照里还没有 DECLINED）"
        )

        let overridden = VolunteerCertificateUploadViewModel()
        overridden.configure(
            with: appState,
            speechService: SpeechService(),
            forcesAlternativeIdentityPath: true
        )

        XCTAssertTrue(overridden.isAlternativeIdentityPath)
        XCTAssertEqual(overridden.materialNoun, "身份材料")
        XCTAssertFalse(
            overridden.currentGuidance.contains("资质证书"),
            "走替代路径的人被要求去找一份自己没有的资质证书，就是这个 bug 的表现"
        )
    }

    /// AppState 已经同步过之后，**不传** override 也必须判对 —— 首页/订单流那三个入口走的是这条。
    func testUploadPageDerivesTheAlternativePathFromAppStateWhenItIsFresh() {
        let appState = AppState()
        appState.currentEnvironment = .mock
        appState.updateVolunteerRegistrationStatus(Self.declinedStatus)
        let viewModel = VolunteerCertificateUploadViewModel()

        viewModel.configure(with: appState, speechService: SpeechService())

        XCTAssertTrue(viewModel.isAlternativeIdentityPath)
        XCTAssertEqual(viewModel.materialNoun, "身份材料")
    }

    // MARK: - 文案红线

    /// 🚨 **`DECLINED` 不是失败态。** 后端契约用整段文字禁止显示成「人脸认证失败，请重试」。
    /// 这条用例是那段禁令在客户端唯一的机器执行点。
    func testAlternativePathCopyNeverFramesTheChoiceAsAFailure() {
        let forbidden = ["失败", "重试", "认证不通过", "人脸识别失败"]
        let copy = [
            VolunteerRegistrationViewModel.declineFallbackAnnouncement,
            VolunteerRegistrationViewModel.declineAlreadyVerifiedMessage,
        ] + VolunteerCertificateDisplayState.allCasesForCopyAudit.map {
            $0.guidance(isAlternativeIdentityPath: true)
        }

        for line in copy {
            for word in forbidden {
                XCTAssertFalse(
                    line.contains(word),
                    "替代路径文案不得出现「\(word)」——他是依法作出的选择，不是没通过认证。命中的是：\(line)"
                )
            }
        }
    }

    /// 🚨 **不得编造审核时长。** 用户协议 `:194` 写的是「审核较慢但等效」，没有承诺任何具体时间，
    /// 后端也没有 SLA 字段。客户端自己写一个「1 个工作日」就是对外口径不一致。
    func testAlternativePathCopyMatchesTheLegalTextAndInventsNoSLA() {
        let notSubmitted = VolunteerCertificateDisplayState.notSubmitted
            .guidance(isAlternativeIdentityPath: true)
        let pending = VolunteerCertificateDisplayState.pending
            .guidance(isAlternativeIdentityPath: true)

        for line in [notSubmitted, pending] {
            XCTAssertTrue(
                line.contains("审核时间较长") && line.contains("结果等效"),
                "必须与法律文本「该方式审核时间较长，但结果等效」一致。实际：\(line)"
            )
        }

        let inventedSLA = ["工作日", "小时内", "分钟内", "24 小时", "尽快"]
        for line in VolunteerCertificateDisplayState.allCasesForCopyAudit.map({
            $0.guidance(isAlternativeIdentityPath: true)
        }) {
            for phrase in inventedSLA {
                XCTAssertFalse(
                    line.contains(phrase),
                    "不得承诺审核时长（后端没有这个字段，法律文本也没写）。命中「\(phrase)」：\(line)"
                )
            }
        }
    }

    /// 走替代路径的人手上**没有**资质证书。照着「上传资质证书」找，他会以为自己走错了页面。
    func testAlternativePathCopyNeverAsksForAQualificationCertificate() {
        for state in VolunteerCertificateDisplayState.allCasesForCopyAudit {
            let alternative = state.guidance(isAlternativeIdentityPath: true)
            XCTAssertFalse(
                alternative.contains("资质证书"),
                "替代路径要传的是能证明本人身份的材料，不是资质证书。命中的是：\(alternative)"
            )
            XCTAssertNotEqual(
                alternative, state.guidance(isAlternativeIdentityPath: false),
                "两条路径的文案必须真的不同——相等说明分支根本没接上"
            )
        }
    }

    // MARK: - Helpers

    private func makeViewModel(
        client: DeclineFlowAPIClient
    ) -> (VolunteerRegistrationViewModel, SpeechService) {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speech = SpeechService()
        let viewModel = VolunteerRegistrationViewModel(
            apiClient: client,
            metaInfoProvider: FixedCloudAuthMetaInfoProvider(metaInfo: #"{"device":"test"}"#)
        )
        viewModel.configure(appState: appState, speechService: speech)
        viewModel.applyRegistrationStatus(Self.stepThreeStatus)
        return (viewModel, speech)
    }

    private static let stepThreeStatus = VolunteerRegistrationStatus(
        registrationStep: "STEP_3_FACE_VERIFY",
        registrationCompleted: false,
        canAcceptOrders: false,
        stepDetails: VolunteerRegistrationStepDetails(
            idVerifyStatus: "APPROVED",
            faceVerifyStatus: "NOT_STARTED"
        ),
        step1Completed: true
    )

    /// 后端 decline 成功后的样子：`registrationCompleted=true` 但 `canAcceptOrders` 仍是 false。
    private static let declinedStatus = VolunteerRegistrationStatus(
        registrationStep: "STEP_3_FACE_VERIFY",
        registrationCompleted: true,
        canAcceptOrders: false,
        stepDetails: VolunteerRegistrationStepDetails(
            idVerifyStatus: "APPROVED",
            faceVerifyStatus: "DECLINED"
        ),
        step1Completed: true
    )

    private static let approvedStatus = VolunteerRegistrationStatus(
        registrationStep: "STEP_3_FACE_VERIFY",
        registrationCompleted: true,
        canAcceptOrders: true,
        stepDetails: VolunteerRegistrationStepDetails(
            idVerifyStatus: "APPROVED",
            faceVerifyStatus: "APPROVED"
        ),
        step1Completed: true
    )

    /// 二要素不合格时后端会把步骤位回退到 STEP_1 再抛 400。
    private static let rolledBackToStepOneStatus = VolunteerRegistrationStatus(
        registrationStep: "STEP_1_BASIC_INFO",
        registrationCompleted: false,
        canAcceptOrders: false,
        stepDetails: VolunteerRegistrationStepDetails(
            idVerifyStatus: "NOT_STARTED",
            faceVerifyStatus: "NOT_STARTED"
        ),
        step1Completed: false
    )
}

// MARK: - Stub

/// 只认三条路径：拒绝、状态回读、活体发起。
/// `statuses` 是一条**队列**而不是单个值 —— 拒绝前后的状态必然不同，
/// 用固定值就演不出「调完 decline 再回读拿到 DECLINED」这条唯一要验的时序。
private final class DeclineFlowAPIClient: APIClientProtocol, @unchecked Sendable {
    private var statuses: [VolunteerRegistrationStatus]
    private let declineMessage: String?
    private let declineError: APIError?

    private(set) var requestedPaths: [String] = []
    private(set) var statusRefreshCount = 0

    init(
        statuses: [VolunteerRegistrationStatus],
        declineMessage: String? = "已切换到替代认证方式",
        declineError: APIError? = nil
    ) {
        self.statuses = statuses
        self.declineMessage = declineMessage
        self.declineError = declineError
    }

    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        requestedPaths.append(path)

        if method == .post, path == "/api/volunteer/registration/step3/face-verify/decline" {
            XCTAssertNil(body, "契约上这条端点没有请求体")
            if let declineError { throw declineError }
            guard let response = FaceVerifyDeclineResponse(message: declineMessage) as? T else {
                throw APIError.invalidURL
            }
            return response
        }

        if method == .get, path == "/api/volunteer/registration/status" {
            statusRefreshCount += 1
            // 队列走完就一直返回最后一个，避免用例因为多刷一次而红。
            let next = statuses.count > 1 ? statuses.removeFirst() : (statuses.first ?? .init())
            guard let response = next as? T else { throw APIError.invalidURL }
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

// MARK: - Copy audit helper

extension VolunteerCertificateDisplayState {
    /// 文案审计要**穷举**五个状态。写死数组是为了新增状态时这里编译不过 ——
    /// 漏掉一个状态的表现是那一态的替代路径文案没人看过，而它照样会上屏。
    static var allCasesForCopyAudit: [VolunteerCertificateDisplayState] {
        [.notSubmitted, .pending, .approved, .rejected, .statusUnavailable]
    }
}
