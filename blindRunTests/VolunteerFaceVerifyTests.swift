import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class VolunteerFaceVerifyTests: XCTestCase, BlindRunTestSupport {
    func testVolunteerFaceVerifyInitPostsMetaInfoAndStartsNativeSDK() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let verifier = CloudAuthVerifierSpy(outcome: .cancelled)
        let client = FaceVerifyFlowAPIClient(
            initResponse: FaceVerifyInitResponse(
                certifyId: "cert-1",
                status: "PENDING",
                message: "请完成活体认证"
            ),
            resultResponses: []
        )
        let viewModel = VolunteerRegistrationViewModel(
            apiClient: client,
            metaInfoProvider: FixedCloudAuthMetaInfoProvider(metaInfo: #"{"device":"test"}"#),
            cloudAuthVerifier: verifier
        )
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true))

        await viewModel.startFaceVerify()

        XCTAssertEqual(client.initCount, 1)
        XCTAssertEqual(client.capturedMetaInfo, #"{"device":"test"}"#)
        XCTAssertEqual(verifier.receivedCertifyIds, ["cert-1"])
        XCTAssertEqual(verifier.receivedEnvironments, [.mock])
        XCTAssertNil(viewModel.activeCertifyId)
        XCTAssertEqual(viewModel.errorMessage, "已取消活体认证，可重新开始")
        XCTAssertTrue(viewModel.canStartFaceVerify)
        XCTAssertEqual(client.resultCount, 0)
    }

    func testCloudAuthMetaInfoSerializerEncodesAliyunDictionary() throws {
        let metaInfo: [AnyHashable: Any] = [
            "apdidToken": "token-123",
            "sdkVersion": "2.3.50",
            "device": [
                "platform": "ios",
                "features": ["camera", "liveness"]
            ]
        ]

        let json = try DefaultCloudAuthMetaInfoProvider.serializedMetaInfo(from: metaInfo)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let device = try XCTUnwrap(object["device"] as? [String: Any])
        let features = try XCTUnwrap(device["features"] as? [String])

        XCTAssertEqual(object["apdidToken"] as? String, "token-123")
        XCTAssertEqual(object["sdkVersion"] as? String, "2.3.50")
        XCTAssertEqual(device["platform"] as? String, "ios")
        XCTAssertEqual(features, ["camera", "liveness"])
    }

    func testCloudAuthRequiredResourcesAreBundled() throws {
        let requiredBundles = [
            "APBToygerFacade",
            "APBToygerFacadeSuitable",
            "BioAuthEngine",
            "ToygerService"
        ]

        for bundleName in requiredBundles {
            XCTAssertNotNil(
                Bundle.main.url(forResource: bundleName, withExtension: "bundle"),
                "Missing required CloudAuth resource bundle: \(bundleName).bundle"
            )
        }

        let toygerBundleURL = try XCTUnwrap(
            Bundle.main.url(forResource: "ToygerService", withExtension: "bundle")
        )
        let modelURL = toygerBundleURL.appendingPathComponent("toyger.face.dat")
        let attributes = try FileManager.default.attributesOfItem(atPath: modelURL.path)
        let modelSize = try XCTUnwrap(attributes[.size] as? NSNumber)

        XCTAssertGreaterThan(modelSize.intValue, 0, "CloudAuth face model must not be empty")
    }

    func testCloudAuthUnusedOptionalModulesAreExcluded() {
#if canImport(OCRDetectSDKForTech)
        XCTFail("OCR CloudAuth module must remain excluded from the ID_PRO-only target")
#endif
#if canImport(DTFNFCIdentityManager)
        XCTFail("NFC CloudAuth module must remain excluded from the ID_PRO-only target")
#endif
#if canImport(MultiFactorFacade)
        XCTFail("MultiFactor CloudAuth module must remain excluded from the ID_PRO-only target")
#endif
#if canImport(DTFBeauty)
        XCTFail("Beauty CloudAuth module must remain excluded from the ID_PRO-only target")
#endif
    }

    func testCloudAuthMetaInfoSerializerRejectsEmptyDictionary() {
        XCTAssertThrowsError(try DefaultCloudAuthMetaInfoProvider.serializedMetaInfo(from: [:])) { error in
            guard let metaInfoError = error as? CloudAuthMetaInfoError else {
                return XCTFail("Expected CloudAuthMetaInfoError")
            }
            XCTAssertEqual(metaInfoError.localizedDescription, "活体认证 SDK 初始化失败，请重试")
        }
    }

    func testDefaultCloudAuthVerifierMapsSDKCompletionCodes() {
        XCTAssertEqual(DefaultCloudAuthVerifier.outcome(forSDKCode: 1000), .submitted)
        XCTAssertEqual(DefaultCloudAuthVerifier.outcome(forSDKCode: 2006), .submitted)
        XCTAssertEqual(DefaultCloudAuthVerifier.outcome(forSDKCode: 1003), .cancelled)
        XCTAssertEqual(failureKind(for: DefaultCloudAuthVerifier.outcome(forSDKCode: 1001)), .internalError)
        XCTAssertEqual(failureKind(for: DefaultCloudAuthVerifier.outcome(forSDKCode: 2002)), .networkError)
        XCTAssertEqual(failureKind(for: DefaultCloudAuthVerifier.outcome(forSDKCode: 2003)), .deviceTimeError)
        XCTAssertEqual(failureKind(for: DefaultCloudAuthVerifier.outcome(forSDKCode: 9999)), .unknown(code: 9999))
    }

    func testCloudAuthDiagnosticsKeepOnlyBoundedTechnicalFields() {
        let diagnostics = CloudAuthSDKDiagnostics(
            code: 1001,
            retCode: 1001,
            retCodeSub: " z1014 ",
            retMessageSub: "raw-message-must-not-be-logged",
            sdkVersion: "2.3.50"
        )

        XCTAssertEqual(diagnostics.retCodeSub, "Z1014")
        XCTAssertTrue(diagnostics.retMessageSubPresent)
        XCTAssertEqual(diagnostics.retMessageSubLength, 30)
        XCTAssertEqual(diagnostics.sdkVersion, "2.3.50")
        XCTAssertTrue(diagnostics.debugSummary.contains("retCodeSub=Z1014"))
        XCTAssertTrue(diagnostics.debugSummary.contains("retMessageSubLength=30"))
        XCTAssertFalse(diagnostics.debugSummary.contains("raw-message"))
    }

    func testCloudAuthDiagnosticsRejectUnsafeSubcodeAndVersion() {
        let diagnostics = CloudAuthSDKDiagnostics(
            code: 1001,
            retCode: 1001,
            retCodeSub: "Z1014 certify-secret",
            retMessageSub: nil,
            sdkVersion: "2.3.50 secret"
        )

        XCTAssertNil(diagnostics.retCodeSub)
        XCTAssertNil(diagnostics.sdkVersion)
        XCTAssertFalse(diagnostics.retMessageSubPresent)
        XCTAssertEqual(diagnostics.retMessageSubLength, 0)
        XCTAssertFalse(diagnostics.debugSummary.contains("secret"))
    }

    func testDefaultCloudAuthVerifierMapsDetailedSubcodes() {
        let mappings: [(String, CloudAuthVerificationFailure.Kind)] = [
            ("Z1014", .internalError),
            ("Z1023", .internalError),
            ("I4001", .moduleIntegration),
            ("Z1010", .businessParameter),
            ("Z1037", .businessParameter),
            ("Z1001", .cameraUnavailable),
            ("Z1002", .cameraUnavailable),
            ("Z1020", .cameraUnavailable),
            ("Z1024", .duplicateFlow)
        ]

        for (subcode, expectedKind) in mappings {
            let diagnostics = CloudAuthSDKDiagnostics(
                code: 1001,
                retCode: 1001,
                retCodeSub: subcode,
                retMessageSub: "not retained",
                sdkVersion: "2.3.50"
            )
            let outcome = DefaultCloudAuthVerifier.outcome(for: diagnostics)
            XCTAssertEqual(failureKind(for: outcome), expectedKind, "Unexpected mapping for \(subcode)")
        }
    }

    func testDefaultCloudAuthVerifierTopLevelCodesTakePrecedenceOverDiagnosticSubcodes() {
        func outcome(code: Int) -> CloudAuthVerificationOutcome {
            DefaultCloudAuthVerifier.outcome(for: CloudAuthSDKDiagnostics(
                code: code,
                retCode: code,
                retCodeSub: "Z1014",
                retMessageSub: "not retained",
                sdkVersion: "2.3.50"
            ))
        }

        XCTAssertEqual(outcome(code: 1000), .submitted)
        XCTAssertEqual(outcome(code: 2006), .submitted)
        XCTAssertEqual(outcome(code: 1003), .cancelled)
        XCTAssertEqual(failureKind(for: outcome(code: 2002)), .networkError)
        XCTAssertEqual(failureKind(for: outcome(code: 2003)), .deviceTimeError)
    }

    func testCloudAuthSDKRuntimeInitializesOnlyOnce() {
        var initializeCalls = 0
        var versionCalls = 0
        let runtime = CloudAuthSDKRuntime(
            initializeSDK: { initializeCalls += 1 },
            versionProvider: {
                versionCalls += 1
                return "2.3.50"
            }
        )

        XCTAssertNil(runtime.sdkVersion)
        runtime.initializeIfNeeded()
        runtime.initializeIfNeeded()

        XCTAssertEqual(initializeCalls, 1)
        XCTAssertEqual(runtime.initializationCount, 1)
        XCTAssertEqual(runtime.sdkVersion, "2.3.50")
        XCTAssertEqual(versionCalls, 1)
    }

    func testCloudAuthOneShotGateAcceptsOnlyFirstCallback() {
        let gate = CloudAuthOneShotGate()

        XCTAssertTrue(gate.claim())
        XCTAssertFalse(gate.claim())
    }

    func testVolunteerFaceVerifyMissingCertifyIdDoesNotStartNativeSDK() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let verifier = CloudAuthVerifierSpy(outcome: .submitted)
        let client = FaceVerifyFlowAPIClient(
            initResponse: FaceVerifyInitResponse(certifyId: nil, status: "PENDING", message: nil),
            resultResponses: []
        )
        let viewModel = VolunteerRegistrationViewModel(
            apiClient: client,
            metaInfoProvider: FixedCloudAuthMetaInfoProvider(metaInfo: #"{"device":"test"}"#),
            cloudAuthVerifier: verifier
        )
        viewModel.configure(appState: appState, speechService: SpeechService())
        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true))

        await viewModel.startFaceVerify()

        XCTAssertTrue(verifier.receivedCertifyIds.isEmpty)
        XCTAssertEqual(client.resultCount, 0)
        XCTAssertEqual(viewModel.errorMessage, "活体认证服务返回不完整，请稍后重试")
    }

    func testVolunteerFaceVerifyInitErrorDoesNotPollOrEnterTraining() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let client = FaceVerifyFlowAPIClient(
            initResponse: FaceVerifyInitResponse(certifyId: nil, status: "ERROR", message: "发起失败"),
            resultResponses: []
        )
        let viewModel = VolunteerRegistrationViewModel(
            apiClient: client,
            metaInfoProvider: FixedCloudAuthMetaInfoProvider(metaInfo: #"{"device":"test"}"#)
        )
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true))

        await viewModel.startFaceVerify()

        XCTAssertEqual(viewModel.currentStep, .faceVerify)
        XCTAssertNil(viewModel.activeCertifyId)
        XCTAssertEqual(client.resultCount, 0)
        XCTAssertEqual(viewModel.errorMessage, "发起失败")
    }

    func testVolunteerFaceVerifyIdentityErrorAllowsReturnToBasicInfoEdit() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let client = FaceVerifyFlowAPIClient(
            initResponse: FaceVerifyInitResponse(certifyId: nil, status: "ERROR", message: nil),
            initError: APIError.serverError(ErrorResponse(code: "ID_INFO_INVALID", message: "身份信息格式不正确")),
            resultResponses: [],
            status: VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true)
        )
        let viewModel = VolunteerRegistrationViewModel(
            apiClient: client,
            metaInfoProvider: FixedCloudAuthMetaInfoProvider(metaInfo: #"{"device":"test"}"#)
        )
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true))

        await viewModel.startFaceVerify()

        XCTAssertEqual(client.statusRefreshCount, 1)
        XCTAssertEqual(viewModel.currentStep, .faceVerify)
        XCTAssertNil(viewModel.activeCertifyId)
        XCTAssertTrue(viewModel.canReturnToBasicInfoForIdentityEdit)
        // `ID_INFO_INVALID` 现在能解析成 `ErrorCode`，因此展示的是本地稳定文案而不是回显后端
        // message —— 实名接口的 message 可能把提交的身份证信息带回来，绝不能展示或朗读。
        XCTAssertEqual(viewModel.errorMessage, ErrorCode.idInfoInvalid.localizedMessage)

        viewModel.returnToBasicInfoForIdentityEdit()

        XCTAssertEqual(viewModel.currentStep, .basicInfo)
        XCTAssertFalse(viewModel.canReturnToBasicInfoForIdentityEdit)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testVolunteerFaceVerifyPendingResultKeepsWaiting() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let client = FaceVerifyFlowAPIClient(
            initResponse: FaceVerifyInitResponse(certifyId: "cert-1", status: "PENDING", message: nil),
            resultResponses: [FaceVerifyResponse(passed: false, status: "PENDING", message: "结果处理中")]
        )
        let viewModel = VolunteerRegistrationViewModel(
            apiClient: client,
            metaInfoProvider: FixedCloudAuthMetaInfoProvider(metaInfo: #"{"device":"test"}"#)
        )
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true))

        viewModel.activeCertifyId = "cert-1"
        let finished = await viewModel.pollFaceVerifyResultOnce()

        XCTAssertFalse(finished)
        XCTAssertEqual(viewModel.currentStep, .faceVerify)
        XCTAssertEqual(viewModel.activeCertifyId, "cert-1")
        XCTAssertEqual(viewModel.faceVerifyMessage, "结果处理中")
    }

    func testVolunteerFaceVerifyRejectedResultAllowsRetry() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let client = FaceVerifyFlowAPIClient(
            initResponse: FaceVerifyInitResponse(certifyId: "cert-1", status: "PENDING", message: nil),
            resultResponses: [FaceVerifyResponse(passed: false, status: "REJECTED", message: "认证未通过")]
        )
        let viewModel = VolunteerRegistrationViewModel(
            apiClient: client,
            metaInfoProvider: FixedCloudAuthMetaInfoProvider(metaInfo: #"{"device":"test"}"#)
        )
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true))

        viewModel.activeCertifyId = "cert-1"
        let finished = await viewModel.pollFaceVerifyResultOnce()

        XCTAssertTrue(finished)
        XCTAssertEqual(viewModel.currentStep, .faceVerify)
        XCTAssertNil(viewModel.activeCertifyId)
        XCTAssertTrue(viewModel.canStartFaceVerify)
        XCTAssertEqual(viewModel.errorMessage, "认证未通过")
    }

    func testVolunteerFaceVerifySubmittedSDKPollsApprovedResultAndCompletesRegistration() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let verifier = CloudAuthVerifierSpy(outcome: .submitted)
        let client = FaceVerifyFlowAPIClient(
            initResponse: FaceVerifyInitResponse(certifyId: "cert-1", status: "PENDING", message: nil),
            resultResponses: [FaceVerifyResponse(passed: true, status: "APPROVED", message: "认证通过")],
            status: VolunteerRegistrationStatus(
                currentStepCode: "STEP_4_COMPLETED",
                canAcceptOrders: true,
                step1Completed: true,
                step3Completed: true
            )
        )
        let viewModel = VolunteerRegistrationViewModel(
            apiClient: client,
            metaInfoProvider: FixedCloudAuthMetaInfoProvider(metaInfo: #"{"device":"test"}"#),
            cloudAuthVerifier: verifier
        )
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true))

        await viewModel.startFaceVerify()

        XCTAssertEqual(verifier.receivedCertifyIds, ["cert-1"])
        XCTAssertEqual(client.resultCount, 1)
        XCTAssertEqual(viewModel.currentStep, .faceVerify)
        XCTAssertNil(viewModel.activeCertifyId)
        XCTAssertTrue(viewModel.isRegistrationCompleted)
        XCTAssertFalse(viewModel.isAwaitingRegistrationCompletion)
        XCTAssertEqual(client.statusRefreshCount, 1)
        XCTAssertFalse(client.requestedPaths.contains { $0.contains("/training/") })
        XCTAssertEqual(speechService.lastSpokenText, VolunteerReadinessCopy.completionAnnouncement)
    }

    func testVolunteerFaceVerifyApprovedResultAcceptsLegacyTrainingCompletion() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let client = FaceVerifyFlowAPIClient(
            initResponse: FaceVerifyInitResponse(certifyId: "cert-1", status: "PENDING", message: nil),
            resultResponses: [FaceVerifyResponse(passed: true, status: "APPROVED", message: "认证通过")],
            status: VolunteerRegistrationStatus(currentStepCode: "STEP_4_TRAINING", canAcceptOrders: false, step3Completed: true)
        )
        let viewModel = VolunteerRegistrationViewModel(
            apiClient: client,
            metaInfoProvider: FixedCloudAuthMetaInfoProvider(metaInfo: #"{"device":"test"}"#),
            cloudAuthVerifier: CloudAuthVerifierSpy(outcome: .submitted)
        )
        viewModel.configure(appState: appState, speechService: SpeechService())
        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true))

        await viewModel.startFaceVerify()

        XCTAssertFalse(viewModel.isAwaitingRegistrationCompletion)
        XCTAssertTrue(viewModel.isRegistrationCompleted)
        XCTAssertFalse(viewModel.shouldPollRegistrationStatus)
        XCTAssertFalse(viewModel.canStartFaceVerify)
        XCTAssertNil(viewModel.faceVerifyMessage)
        XCTAssertFalse(client.requestedPaths.contains { $0.contains("/training/") })

        // 完成态刻意不在此刻发布：一旦 AppState 认定注册完成，ContentView 的根路由会重跑并切到
        // 志愿者首页，把注册流连同「注册完成」页一起拆掉，用户只听到 TTS 却看不到确认页。
        // 未完成的中间态照常发布，AppState 这时停在进流程前的 STEP_3_FACE_VERIFY。
        XCTAssertFalse(
            appState.volunteerRegistrationStatus?.isRegistrationComplete == true,
            "注册完成态不能在用户还停留在注册流时就推给 AppState"
        )

        // 用户点「返回志愿者首页」时才发布，根路由这时切走才是对的。
        viewModel.prepareReturnToVolunteerHome()
        XCTAssertTrue(appState.volunteerRegistrationStatus?.isRegistrationComplete == true)
    }

    func testVolunteerFaceVerifySDKFailureClearsCertifyIdAndAllowsRetry() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let client = FaceVerifyFlowAPIClient(
            initResponse: FaceVerifyInitResponse(certifyId: "cert-1", status: "PENDING", message: nil),
            resultResponses: []
        )
        let viewModel = VolunteerRegistrationViewModel(
            apiClient: client,
            metaInfoProvider: FixedCloudAuthMetaInfoProvider(metaInfo: #"{"device":"test"}"#),
            cloudAuthVerifier: CloudAuthVerifierSpy(outcome: .failed(.networkError))
        )
        viewModel.configure(appState: appState, speechService: SpeechService())
        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true))

        await viewModel.startFaceVerify()

        XCTAssertNil(viewModel.activeCertifyId)
        XCTAssertTrue(viewModel.canStartFaceVerify)
        XCTAssertEqual(client.resultCount, 0)
        XCTAssertEqual(viewModel.errorMessage, "活体认证网络连接失败，请检查网络后重试")
    }

    func testVolunteerFaceVerifyBusinessParameterSubcodeIsSafeAndRetryable() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let diagnostics = CloudAuthSDKDiagnostics(
            code: 1001,
            retCode: 1001,
            retCodeSub: "Z1010",
            retMessageSub: "certifyId must never be shown",
            sdkVersion: "2.3.50"
        )
        let failure = CloudAuthVerificationFailure(kind: .businessParameter, diagnostics: diagnostics)
        let client = FaceVerifyFlowAPIClient(
            initResponse: FaceVerifyInitResponse(certifyId: "cert-1", status: "PENDING", message: nil),
            resultResponses: []
        )
        let viewModel = VolunteerRegistrationViewModel(
            apiClient: client,
            metaInfoProvider: FixedCloudAuthMetaInfoProvider(metaInfo: #"{"device":"test"}"#),
            cloudAuthVerifier: CloudAuthVerifierSpy(outcome: .failed(failure))
        )
        viewModel.configure(appState: appState, speechService: SpeechService())
        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true))

        await viewModel.startFaceVerify()

        XCTAssertNil(viewModel.activeCertifyId)
        XCTAssertTrue(viewModel.canStartFaceVerify)
        XCTAssertEqual(client.resultCount, 0)
        XCTAssertEqual(viewModel.errorMessage, "活体认证参数或流程配置异常，请重新发起认证（错误码 Z1010）")
        XCTAssertFalse(viewModel.errorMessage?.contains("certifyId") == true)
    }

    func testVolunteerRegistrationRefreshesStatusWhenBasicInfoAlreadyCompleted() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let _: EmptyResponse = try await appState.apiClient.post(
            "/api/volunteer/registration/step1",
            body: BasicInfoRequest(
                name: "赵冉杰",
                phone: "13800138000",
                idCardName: "赵冉杰",
                idCardNumber: "110101199001011234",
                runningExperience: nil,
                hasGuidedBefore: true,
                emergencyExperience: nil
            )
        )
        let viewModel = VolunteerRegistrationViewModel()
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.name = "赵冉杰"
        viewModel.phone = "18314555097"
        viewModel.idCardName = "赵冉杰"
        viewModel.idCardNumber = "110101199001011234"

        await viewModel.submitBasicInfo()

        XCTAssertEqual(viewModel.currentStep, .faceVerify)
        XCTAssertEqual(viewModel.errorMessage, "已同步注册进度，请继续完成活体认证")
        XCTAssertEqual(speechService.lastSpokenText, "已同步注册进度，请继续完成活体认证")
    }

    func testVolunteerFaceCameraPermissionUsageDescriptionIsConfigured() throws {
        let cameraUsageDescription = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String
        )

        XCTAssertFalse(cameraUsageDescription.trimmed.isEmpty)
    }

    func testVolunteerCertificationEntryDoesNotRequireSeparateNicknameSubmit() {
        let appState = AppState()
        appState.currentEnvironment = .demoCloud
        appState.updateVolunteerProfile(makeVolunteerProfile(name: "", verificationStatus: "not_submitted"))
        let viewModel = VolunteerProfileViewModel()

        viewModel.configure(with: appState, speechService: SpeechService())

        XCTAssertEqual(viewModel.certificationButtonTitle, "开始认证")
        XCTAssertEqual(viewModel.certificationAccessibilityHint, "点击后进入志愿者注册认证流程")
        XCTAssertFalse(viewModel.canSubmit)
    }

    private func failureKind(for outcome: CloudAuthVerificationOutcome) -> CloudAuthVerificationFailure.Kind? {
        guard case .failed(let failure) = outcome else { return nil }
        return failure.kind
    }

    private final class CloudAuthVerifierSpy: CloudAuthVerifying, @unchecked Sendable {
        private let outcome: CloudAuthVerificationOutcome
        private(set) var receivedCertifyIds: [String] = []
        private(set) var receivedEnvironments: [APIEnvironment] = []

        init(outcome: CloudAuthVerificationOutcome) {
            self.outcome = outcome
        }

        func verify(certifyId: String, environment: APIEnvironment) async -> CloudAuthVerificationOutcome {
            receivedCertifyIds.append(certifyId)
            receivedEnvironments.append(environment)
            return outcome
        }
    }

    private final class FaceVerifyFlowAPIClient: APIClientProtocol, @unchecked Sendable {
        private let initResponse: FaceVerifyInitResponse
        private let initError: APIError?
        private var resultResponses: [FaceVerifyResponse]
        private let status: VolunteerRegistrationStatus
        private(set) var capturedMetaInfo: String?
        private(set) var initCount = 0
        private(set) var resultCount = 0
        private(set) var statusRefreshCount = 0
        private(set) var requestedPaths: [String] = []

        init(
            initResponse: FaceVerifyInitResponse,
            initError: APIError? = nil,
            resultResponses: [FaceVerifyResponse],
            status: VolunteerRegistrationStatus = VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true)
        ) {
            self.initResponse = initResponse
            self.initError = initError
            self.resultResponses = resultResponses
            self.status = status
        }

        func request<T: Decodable>(
            method: HTTPMethod,
            path: String,
            query: [String: String]?,
            body: (any Encodable & Sendable)?,
            requiresAuth: Bool
        ) async throws -> T {
            requestedPaths.append(path)
            if method == .post, path == "/api/volunteer/registration/step3/face-verify/init" {
                initCount += 1
                if let initError {
                    throw initError
                }
                guard let request = body as? FaceVerifyInitRequest,
                      let response = initResponse as? T else {
                    throw APIError.invalidURL
                }
                capturedMetaInfo = request.metaInfo
                return response
            }
            if method == .post, path == "/api/volunteer/registration/step3/face-verify/result" {
                resultCount += 1
                guard let response = (resultResponses.isEmpty ? FaceVerifyResponse(passed: false, status: "PENDING", message: nil) : resultResponses.removeFirst()) as? T else {
                    throw APIError.invalidURL
                }
                return response
            }
            if method == .get, path == "/api/volunteer/registration/status" {
                statusRefreshCount += 1
                guard let response = status as? T else {
                    throw APIError.invalidURL
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
    }
}
