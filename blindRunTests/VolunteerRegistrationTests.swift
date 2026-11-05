import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class VolunteerRegistrationTests: XCTestCase, BlindRunTestSupport {
    func testMockFormalTwoRoleHappyPathThroughReview() async throws {
        let client = MockAPIClient()
        let plannedStart = Date().addingTimeInterval(45 * 60)
        let plannedEnd = plannedStart.addingTimeInterval(60 * 60)
        let createResponse: OrderResponse = try await client.post(
            "/api/orders",
            body: CreateOrderRequest(
                startLatitude: 39.9342,
                startLongitude: 116.4740,
                startAddress: "朝阳公园南门",
                endAddress: nil,
                endLatitude: nil,
                endLongitude: nil,
                plannedStartTime: DateFormatter.aidRunBackendLocalDateTime.string(from: plannedStart),
                plannedEndTime: DateFormatter.aidRunBackendLocalDateTime.string(from: plannedEnd),
                expectedDurationMinutes: 60,
                pacePreference: .moderate,
                routePreference: .parkTrail,
                routeNotes: nil,
                hasGuideDogThisRun: false,
                specialNotes: nil
            )
        )
        let orderId = try XCTUnwrap(createResponse.id)
        XCTAssertEqual(createResponse.status, .pendingMatch)

        let _: EmptyResponse = try await client.put(
            "/api/volunteer/dispatch-status",
            body: DispatchStatusRequest(wantsDispatch: true)
        )
        let _: EmptyResponse = try await client.post(
            "/api/orders/\(orderId)/respond",
            body: OrderRespondRequest(action: .accept)
        )
        var detail: OrderDetailResponse = try await client.get("/api/orders/\(orderId)")
        XCTAssertEqual(detail.status, .pendingAccept)

        let _: EmptyResponse = try await client.post("/api/orders/\(orderId)/en-route")
        let _: EmptyResponse = try await client.post("/api/orders/\(orderId)/arrived")
        detail = try await client.get("/api/orders/\(orderId)")
        XCTAssertEqual(detail.status, .driverArrived)

        let _: EmptyResponse = try await client.post("/api/orders/\(orderId)/start-service")
        let _: EmptyResponse = try await client.post("/api/orders/\(orderId)/finish")
        detail = try await client.get("/api/orders/\(orderId)")
        XCTAssertEqual(detail.status, .completed)

        let _: EmptyResponse = try await client.post(
            "/api/orders/\(orderId)/review",
            body: CreateReviewRequest(rating: 5, comment: "顺利完成")
        )
    }

    func testVolunteerRegistrationCloudAuthPathsUseCloudContract() async throws {
        // 前置状态必须自己安排，不要改回裸 `MockAPIClient()`：
        // Mock 的种子志愿者 `verificationStatus` 默认是 APPROVED（大量用例依赖「种子志愿者可接单」
        // 这一人设，改默认值会连锁打红一片），而后端 `VolunteerService.submitVerification`
        // （VolunteerService.java:314）在 APPROVED 时直接 400 拒绝重传，Mock 已逐条对齐。
        // 这条用例走的是「首次提交资质证书」路径，所以先把状态压回后端枚举的 NONE，
        // 否则测到的根本不是首次上传。
        // APPROVED 重传被拒的另一面由 `testMockRejectsReuploadAfterApprovalLikeBackend` 钉死。
        setenv("AIDRUN_MOCK_VOLUNTEER_VERIFICATION_STATUS", "NONE", 1)
        defer { unsetenv("AIDRUN_MOCK_VOLUNTEER_VERIFICATION_STATUS") }

        let client = MockAPIClient()

        let submittedVerification: VolunteerVerificationStatusResponse = try await client.upload(
            "/api/volunteer/verification",
            files: [MultipartFile(fieldName: "file", fileName: "cert.jpg", mimeType: "image/jpeg", data: Data([0xFF, 0xD8]))]
        )
        XCTAssertEqual(
            VolunteerCertificateStatus.parse(submittedVerification.status),
            .pending,
            "NONE 状态下首次上传资质证书必须成功并置 PENDING"
        )

        do {
            let _: EmptyResponse = try await client.upload(
                "/api/volunteer/registration/step2/id-card",
                fields: [
                    "idCardName": "测试志愿者",
                    "idCardNumber": "110101199001011234"
                ],
                files: []
            )
            XCTFail("旧身份证照片上传路径不应继续可用")
        } catch {
            // Expected: Step2 ID photo upload was removed from the main registration flow.
        }

        let _: EmptyResponse = try await client.post(
            "/api/volunteer/registration/step1",
            body: BasicInfoRequest(
                name: "测试志愿者",
                phone: "13800000002",
                idCardName: "测试志愿者",
                idCardNumber: "110101199001011234",
                runningExperience: nil,
                hasGuidedBefore: true,
                emergencyExperience: nil
            )
        )
        let initResponse: FaceVerifyInitResponse = try await client.post(
            "/api/volunteer/registration/step3/face-verify/init",
            body: FaceVerifyInitRequest(metaInfo: #"{"mock":true}"#)
        )
        XCTAssertEqual(initResponse.certifyId, "mock-certify-id")

        let result: FaceVerifyResponse = try await client.post(
            "/api/volunteer/registration/step3/face-verify/result",
            body: FaceVerifyResultRequest(certifyId: "mock-certify-id")
        )
        XCTAssertTrue(result.isPassed)

        let status: VolunteerRegistrationStatus = try await client.get("/api/volunteer/registration/status")
        let profile: VolunteerProfileResponse = try await client.get("/api/volunteer/profile")
        XCTAssertEqual(status.registrationStep, "STEP_4_COMPLETED")
        XCTAssertTrue(status.canAcceptOrders == true)
        XCTAssertTrue(status.isRegistrationComplete)
        XCTAssertEqual(profile.registrationStep, "STEP_4_COMPLETED")
        XCTAssertTrue(profile.canAcceptOrders == true)
        XCTAssertFalse(profile.isAvailable ?? true, "Registration completion must not automatically enable availability")

        do {
            let _: EmptyResponse = try await client.get("/api/volunteer/registration/training/courses")
            XCTFail("iOS Mock must not expose removed training routes")
        } catch {
            // Expected: training remains an external deprecated contract, not an iOS Mock route.
        }
    }

    func testVolunteerRegistrationBasicInfoRequestEncodesIdCardFields() throws {
        let request = BasicInfoRequest(
            name: "赵冉杰",
            phone: "18314551097",
            idCardName: "赵冉杰",
            idCardNumber: "110101199001011234",
            runningExperience: "3年跑步经验",
            hasGuidedBefore: true,
            emergencyExperience: nil
        )

        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["idCardName"] as? String, "赵冉杰")
        XCTAssertEqual(object["idCardNumber"] as? String, "110101199001011234")
    }

    func testVolunteerRegistrationStep1UsesNameAsIdCardName() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let client = BasicInfoStatusAPIClient(
            status: VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true, idVerifyStatus: "APPROVED")
        )
        let viewModel = VolunteerRegistrationViewModel(apiClient: client)
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.name = "赵冉杰"
        viewModel.phone = "13800138000"
        viewModel.idCardName = "不应提交的旧姓名"
        viewModel.idCardNumber = "110101199001011234"

        await viewModel.submitBasicInfo()

        XCTAssertEqual(client.capturedRequest?.name, "赵冉杰")
        XCTAssertEqual(client.capturedRequest?.idCardName, "赵冉杰")
        XCTAssertEqual(client.capturedRequest?.idCardNumber, "110101199001011234")
    }

    func testVolunteerRegistrationStep1AcceptsGenericSuccessResponse() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = VolunteerRegistrationViewModel()
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.name = "测试志愿者"
        viewModel.phone = "13800000002"
        viewModel.idCardName = "测试志愿者"
        viewModel.idCardNumber = "110101199001011234"

        await viewModel.submitBasicInfo()

        XCTAssertEqual(viewModel.currentStep, .faceVerify)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(speechService.lastSpokenText, "身份核验通过，请开始刷脸")
    }

    func testVolunteerRegistrationBasicInfoShowsBlockedReasonForInvalidPhone() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = VolunteerRegistrationViewModel()
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.name = "赵冉杰"
        viewModel.phone = "1831455097"
        viewModel.idCardName = "赵冉杰"
        viewModel.idCardNumber = "110101199001011234"

        XCTAssertFalse(viewModel.canSubmitBasicInfo)
        XCTAssertEqual(viewModel.basicInfoValidationMessage, "请输入 11 位中国大陆手机号")

        await viewModel.submitBasicInfo()

        XCTAssertEqual(viewModel.currentStep, .basicInfo)
        XCTAssertEqual(viewModel.errorMessage, "请输入 11 位中国大陆手机号")
        XCTAssertEqual(speechService.lastSpokenText, "请输入 11 位中国大陆手机号")
    }

    func testVolunteerRegistrationPhoneDirectAssignmentKeepsOnlyFirstElevenDigits() {
        let viewModel = VolunteerRegistrationViewModel()

        viewModel.phone = "13800138000999"

        XCTAssertEqual(viewModel.phone, "13800138000")
    }

    func testVolunteerRegistrationPhoneInputDropsNonDigits() {
        let viewModel = VolunteerRegistrationViewModel()

        viewModel.phone = "abc 138-0013-8000 xyz"

        XCTAssertEqual(viewModel.phone, "13800138000")
    }

    func testVolunteerRegistrationIdCardDirectAssignmentKeepsOnlyFirstEighteenCharacters() {
        let viewModel = VolunteerRegistrationViewModel()

        viewModel.idCardNumber = "1101011990010112345678"

        XCTAssertEqual(viewModel.idCardNumber, "110101199001011234")
    }

    func testVolunteerRegistrationIdCardAllowsLowercaseXCheckDigit() {
        let viewModel = VolunteerRegistrationViewModel()

        viewModel.name = "赵冉杰"
        viewModel.phone = "13800138000"
        viewModel.idCardName = "赵冉杰"
        viewModel.idCardNumber = "11010119900101123x"

        XCTAssertNil(viewModel.identityInfoValidationMessage)
        XCTAssertTrue(viewModel.canSubmitBasicInfo)
    }

    func testVolunteerRegistrationInvalidIdCardNumberBlocksStep1Submit() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = VolunteerRegistrationViewModel()
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.name = "赵冉杰"
        viewModel.phone = "13800138000"
        viewModel.idCardName = "赵冉杰"
        viewModel.idCardNumber = "123"

        XCTAssertFalse(viewModel.canSubmitBasicInfo)
        XCTAssertEqual(viewModel.basicInfoValidationMessage, "请输入18位有效身份证号码")

        await viewModel.submitBasicInfo()

        XCTAssertEqual(viewModel.currentStep, .basicInfo)
        XCTAssertEqual(viewModel.errorMessage, "请输入18位有效身份证号码")
    }

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
        viewModel.phone = "13800138000"
        viewModel.idCardName = "赵冉杰"
        viewModel.idCardNumber = "110101199001011234"

        await viewModel.submitBasicInfo()

        XCTAssertEqual(viewModel.currentStep, .basicInfo)
        XCTAssertEqual(viewModel.errorMessage, "身份证二要素核验未通过，请更新身份证信息")
        XCTAssertEqual(speechService.lastSpokenText, "身份证二要素核验未通过，请更新身份证信息")
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
        viewModel.phone = "13800138000"
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

    private final class BasicInfoStatusAPIClient: APIClientProtocol, @unchecked Sendable {
        private let status: VolunteerRegistrationStatus
        private(set) var submitCount = 0
        private(set) var statusRefreshCount = 0
        private(set) var capturedRequest: BasicInfoRequest?

        init(status: VolunteerRegistrationStatus) {
            self.status = status
        }

        func request<T: Decodable>(
            method: HTTPMethod,
            path: String,
            query: [String: String]?,
            body: (any Encodable & Sendable)?,
            requiresAuth: Bool
        ) async throws -> T {
            if method == .post, path == "/api/volunteer/registration/step1" {
                submitCount += 1
                guard let request = body as? BasicInfoRequest else {
                    throw APIError.invalidURL
                }
                capturedRequest = request
                guard let response = EmptyResponse() as? T else {
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
