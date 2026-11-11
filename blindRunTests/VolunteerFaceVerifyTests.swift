import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class VolunteerFaceVerifyTests: XCTestCase, BlindRunTestSupport {
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
        XCTAssertEqual(viewModel.errorMessage, "刷脸暂时用不了，请稍后重试")
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
}
