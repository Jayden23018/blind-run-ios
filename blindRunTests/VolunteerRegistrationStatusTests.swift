import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class VolunteerRegistrationStatusTests: XCTestCase, BlindRunTestSupport {
    func testVolunteerRegistrationLoadStatusUnauthorizedExpiresSession() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        appState.accessToken = "expired-token"
        appState.userId = 12
        appState.activeRole = .volunteer
        let speechService = SpeechService()
        let viewModel = VolunteerRegistrationViewModel(apiClient: FailingAPIClient(error: APIError.unauthorized))
        viewModel.currentStep = .faceVerify
        viewModel.configure(appState: appState, speechService: speechService)

        await viewModel.loadStatus()

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(appState.accessToken)
        XCTAssertNil(appState.userId)
        XCTAssertNil(appState.activeRole)
        XCTAssertEqual(appState.consumeSessionExpirationMessage(), "登录已过期，请重新登录。")
    }

    func testVolunteerRegistrationStatusRoutesStringStepToFaceVerify() throws {
        let data = #"{"registrationStep":"STEP_3_FACE_VERIFY","step1Completed":true}"#
            .data(using: .utf8)!
        let status = try JSONDecoder().decode(VolunteerRegistrationStatus.self, from: data)
        let viewModel = VolunteerRegistrationViewModel()

        viewModel.applyRegistrationStatus(status)

        XCTAssertEqual(viewModel.currentStep, .faceVerify)
    }

    func testVolunteerRegistrationExposesOnlyTwoUserFacingSteps() {
        XCTAssertEqual(RegistrationStep.allCases.map(\.title), ["基本信息与身份核验", "活体认证"])
        XCTAssertEqual(RegistrationStep.allCases.map(\.displayIndex), [1, 2])
    }

    /// 回归门：走完注册但没过资质审核的志愿者，必须能离开注册流程去传证书。
    /// 后端 2026-07-31 起 `canAcceptOrders` = 资质审核结果（不再是注册完成度），
    /// 若这里退回用 `canAcceptOrders` 判完成，新注册志愿者会被锁死在注册流程里，
    /// 而证书上传入口在流程之外 —— `verified` 永远翻不了真，账号报废。
    func testRegistrationCompleteWhenRegistrationDoneButNotYetVerified() {
        let status = VolunteerRegistrationStatus(
            registrationStep: "STEP_3_FACE_VERIFY",
            registrationCompleted: true,
            canAcceptOrders: false,
            faceVerifyStatus: "APPROVED"
        )

        XCTAssertTrue(status.isRegistrationComplete)
    }

    /// 回归门：`STEP_3_FACE_VERIFY` 这个步骤位在「正在做活体」时也是它
    /// （后端 step1 二要素一过就置这个值），光看步骤位会把没做活体的人判成已完成。
    /// 他随后会被资质审核以「活体认证未通过」永久拒绝。
    func testRegistrationIncompleteWhenParkedAtFaceVerifyButLivenessNotDone() {
        let notStarted = VolunteerRegistrationStatus(
            registrationStep: "STEP_3_FACE_VERIFY",
            registrationCompleted: false,
            canAcceptOrders: false,
            faceVerifyStatus: "NOT_STARTED"
        )
        XCTAssertFalse(notStarted.isRegistrationComplete)

        // 旧服务端不返回 registrationCompleted，客户端必须自己按 faceVerifyStatus 推
        let legacyServer = VolunteerRegistrationStatus(
            registrationStep: "STEP_3_FACE_VERIFY",
            canAcceptOrders: true,          // 旧服务端这里恒为 true，正是不能信它的原因
            faceVerifyStatus: "NOT_STARTED"
        )
        XCTAssertFalse(legacyServer.isRegistrationComplete)

        let legacyServerPassed = VolunteerRegistrationStatus(
            registrationStep: "STEP_3_FACE_VERIFY",
            canAcceptOrders: true,
            faceVerifyStatus: "APPROVED"
        )
        XCTAssertTrue(legacyServerPassed.isRegistrationComplete)
    }

    func testVolunteerRegistrationLegacyTrainingStatusCompletesWithoutPolling() {
        let viewModel = VolunteerRegistrationViewModel()

        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(
            currentStepCode: "STEP_4_TRAINING",
            canAcceptOrders: false,
            step3Completed: true,
            faceVerifyStatus: "APPROVED"
        ))

        XCTAssertEqual(viewModel.currentStep, .faceVerify)
        XCTAssertFalse(viewModel.isAwaitingRegistrationCompletion)
        XCTAssertTrue(viewModel.isRegistrationCompleted)
        XCTAssertFalse(viewModel.shouldPollRegistrationStatus)
        XCTAssertFalse(viewModel.canStartFaceVerify)
    }

    func testVolunteerRegistrationCompletedStatusShowsBackendAuthoritativeCompletion() {
        let viewModel = VolunteerRegistrationViewModel()

        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(
            currentStepCode: "STEP_4_COMPLETED",
            canAcceptOrders: true,
            step3Completed: true
        ))

        XCTAssertTrue(viewModel.isRegistrationCompleted)
        XCTAssertFalse(viewModel.isAwaitingRegistrationCompletion)
        XCTAssertFalse(viewModel.shouldPollRegistrationStatus)
        XCTAssertFalse(viewModel.canStartFaceVerify)
    }

    func testVolunteerRegistrationStaleStatusKeepsFaceVerificationSyncingScreen() {
        let viewModel = VolunteerRegistrationViewModel()

        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(
            currentStepCode: "STEP_3_FACE_VERIFY",
            canAcceptOrders: false,
            step3Completed: true,
            faceVerifyStatus: "APPROVED"
        ))
        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(
            currentStepCode: "STEP_1_BASIC_INFO",
            canAcceptOrders: false,
            step1Completed: true
        ))

        XCTAssertEqual(viewModel.currentStep, .faceVerify)
        XCTAssertTrue(viewModel.isAwaitingRegistrationCompletion)
        XCTAssertTrue(viewModel.shouldPollRegistrationStatus)
        XCTAssertFalse(viewModel.canStartFaceVerify)

        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(
            currentStepCode: "STEP_4_COMPLETED",
            canAcceptOrders: true,
            step3Completed: true
        ))

        XCTAssertTrue(viewModel.isRegistrationCompleted)
        XCTAssertFalse(viewModel.isAwaitingRegistrationCompletion)
        XCTAssertFalse(viewModel.shouldPollRegistrationStatus)
    }

    func testVolunteerRegistrationLegacyStep2StatusRoutesBackToBasicInfo() throws {
        let data = #"{"registrationStep":"STEP_2_ID_UPLOAD","step1Completed":true,"idVerifyStatus":"PENDING"}"#
            .data(using: .utf8)!
        let status = try JSONDecoder().decode(VolunteerRegistrationStatus.self, from: data)
        let viewModel = VolunteerRegistrationViewModel()

        viewModel.applyRegistrationStatus(status)

        XCTAssertEqual(viewModel.currentStep, .basicInfo)
    }

    func testVolunteerRegistrationStatusDecodesNestedStepDetails() throws {
        let data = """
        {
          "currentStep": "STEP_2_ID_UPLOAD",
          "canAcceptOrders": false,
          "stepDetails": {
            "idVerifyStatus": "REJECTED",
            "faceVerifyStatus": "NONE",
            "totalTrainingMinutes": 0,
            "completedCoursesCount": 0,
            "currentCourseId": null,
            "idVerifyRejectionReason": "照片不清晰"
          }
        }
        """.data(using: .utf8)!

        let status = try JSONDecoder().decode(VolunteerRegistrationStatus.self, from: data)
        let viewModel = VolunteerRegistrationViewModel()
        viewModel.applyRegistrationStatus(status)

        XCTAssertEqual(status.currentStepCode, "STEP_2_ID_UPLOAD")
        XCTAssertEqual(status.idVerifyStatus, "REJECTED")
        XCTAssertEqual(status.stepDetails?.idVerifyRejectionReason, "照片不清晰")
        XCTAssertFalse(status.isRegistrationComplete)
        XCTAssertEqual(viewModel.currentStep, .basicInfo)
    }

    func testVolunteerRegistrationStep1TwoFactorFailureStaysOnBasicInfo() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let client = BasicInfoFailingAPIClient(
            error: APIError.serverError(ErrorResponse(code: "ID_CARD_CHECK_FAILED", message: "身份证二要素核验未通过，请更新身份证信息"))
        )
        let viewModel = VolunteerRegistrationViewModel(apiClient: client)
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.name = "赵冉杰"
        viewModel.idCardName = "赵冉杰"
        viewModel.idCardNumber = "110101199001011234"

        await viewModel.submitBasicInfo()

        XCTAssertEqual(viewModel.currentStep, .basicInfo)
        XCTAssertEqual(viewModel.errorMessage, "身份证二要素核验未通过，请更新身份证信息")
        XCTAssertEqual(speechService.lastSpokenText, "身份证二要素核验未通过，请更新身份证信息")
    }

    /// 一证一个志愿者（#768）：从经历那一屏提交被拒，要回到填身份证号的那一屏，且不引导「核对证件」。
    func testVolunteerRegistrationIdCardAlreadyRegisteredReturnsToIdentityPage() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let client = BasicInfoFailingAPIClient(
            error: APIError.serverError(ErrorResponse(code: "ID_CARD_ALREADY_REGISTERED", message: "该身份证号已注册"))
        )
        let viewModel = VolunteerRegistrationViewModel(apiClient: client)
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.startIdentityEntry(prefersAlternativePath: false)
        viewModel.name = "赵冉杰"
        viewModel.idCardNumber = "110101199001011234"
        viewModel.advanceToExperiencePage()
        XCTAssertEqual(viewModel.basicInfoPage, .experience)

        await viewModel.submitBasicInfo()

        let expected = ErrorCode.idCardAlreadyRegistered.localizedMessage
        XCTAssertEqual(viewModel.basicInfoPage, .identity)
        XCTAssertEqual(viewModel.errorMessage, expected)
        XCTAssertEqual(speechService.lastSpokenText, expected)
        XCTAssertFalse(expected.contains("核对"), "证件没问题，不能让他去核对证件")
    }

    func testVolunteerRegistrationStep1SuccessRefreshesToFaceVerifyStatus() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let client = BasicInfoStatusAPIClient(
            status: VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true, idVerifyStatus: "APPROVED")
        )
        let viewModel = VolunteerRegistrationViewModel(apiClient: client)
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.name = "赵冉杰"
        viewModel.idCardName = "赵冉杰"
        viewModel.idCardNumber = "110101199001011234"

        await viewModel.submitBasicInfo()

        XCTAssertEqual(client.submitCount, 1)
        XCTAssertEqual(client.statusRefreshCount, 1)
        XCTAssertEqual(viewModel.currentStep, .faceVerify)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(speechService.lastSpokenText, "身份核验通过，请开始刷脸")
    }

    private final class BasicInfoFailingAPIClient: APIClientProtocol, @unchecked Sendable {
        private let error: APIError

        init(error: APIError) {
            self.error = error
        }

        func request<T: Decodable>(
            method: HTTPMethod,
            path: String,
            query: [String: String]?,
            body: (any Encodable & Sendable)?,
            requiresAuth: Bool
        ) async throws -> T {
            if method == .post, path == "/api/volunteer/registration/step1" {
                throw error
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
