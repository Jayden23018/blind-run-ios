import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class VolunteerFaceVerifyCompletionTests: XCTestCase, BlindRunTestSupport {
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
}
