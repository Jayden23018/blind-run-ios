import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class VolunteerAcceptGuardTests: XCTestCase, BlindRunTestSupport {
    func testVolunteerAcceptGuardRequiresCompleteProfile() {
        XCTAssertEqual(
            VolunteerOrderActionGuard.acceptBlockMessage(profile: nil),
            "请先完善陪跑员资料"
        )

        XCTAssertEqual(
            VolunteerOrderActionGuard.acceptBlockMessage(profile: makeVolunteerProfile(name: "")),
            "请先完善陪跑员资料"
        )
    }

    func testVolunteerAcceptGuardRequiresApproval() {
        XCTAssertEqual(
            VolunteerOrderActionGuard.acceptBlockMessage(profile: makeVolunteerProfile()),
            "请先完成陪跑员注册"
        )

        XCTAssertNil(
            VolunteerOrderActionGuard.acceptBlockMessage(profile: makeApprovedVolunteerProfile())
        )
    }

    func testVolunteerAcceptGuardUsesMainRegistrationStatusBeforeOptionalCertificate() {
        let completedStatus = VolunteerRegistrationStatus(
            currentStepCode: "STEP_4_COMPLETED",
            canAcceptOrders: true
        )

        XCTAssertNil(
            VolunteerOrderActionGuard.acceptBlockMessage(
                profile: makeVolunteerProfile(
                    verificationStatus: "rejected",
                    adminReviewStatus: "pending",
                    isAvailable: true
                ),
                registrationStatus: completedStatus
            )
        )
    }

    func testVolunteerAcceptGuardRequiresLegacyAdminReviewOnlyWithoutRegistrationStatus() {
        XCTAssertEqual(
            VolunteerOrderActionGuard.acceptBlockMessage(
                profile: makeVolunteerProfile(
                    verificationStatus: "approved",
                    adminReviewStatus: "pending",
                    isAvailable: true
                )
            ),
            "请等待管理员审核通过"
        )

        XCTAssertNil(
            VolunteerOrderActionGuard.acceptBlockMessage(
                profile: makeVolunteerProfile(
                    verificationStatus: "approved",
                    adminReviewStatus: nil,
                    isAvailable: true
                )
            )
        )
    }

    func testVolunteerAcceptGuardRequiresAvailability() {
        XCTAssertEqual(
            VolunteerOrderActionGuard.acceptBlockMessage(
                profile: makeApprovedVolunteerProfile(isAvailable: false),
                registrationStatus: VolunteerRegistrationStatus(currentStepCode: "STEP_4_COMPLETED", canAcceptOrders: true)
            ),
            "请先开启可服务状态"
        )
    }

    func testVolunteerAcceptGuardTreatsLegacyTrainingAsCompleteButStillRequiresAvailability() {
        let legacyStatus = VolunteerRegistrationStatus(
            currentStepCode: "STEP_4_TRAINING",
            canAcceptOrders: false,
            step3Completed: true,
            faceVerifyStatus: "APPROVED"
        )

        XCTAssertEqual(
            VolunteerOrderActionGuard.acceptBlockMessage(
                profile: makeVolunteerProfile(isAvailable: false),
                registrationStatus: legacyStatus
            ),
            "请先开启可服务状态"
        )
        XCTAssertTrue(legacyStatus.isRegistrationComplete)
    }

    func testVolunteerProfileFallbackTreatsLegacyTrainingAsComplete() {
        let profile = makeVolunteerProfile(
            registrationStep: "STEP_4_TRAINING",
            canAcceptOrders: false
        )

        XCTAssertTrue(profile.isMainRegistrationCompleteWhenStatusUnavailable)
    }

    func testVolunteerRegistrationCompletionCreatesUnavailableProfileSnapshotWhenMissing() {
        let appState = AppState()
        let viewModel = VolunteerRegistrationViewModel()
        viewModel.configure(appState: appState, speechService: SpeechService())
        viewModel.name = "测试志愿者"
        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(
            currentStepCode: "STEP_4_TRAINING",
            canAcceptOrders: false,
            step3Completed: true,
            faceVerifyStatus: "APPROVED"
        ))

        // 人脸通过的完成态当场发布（#768），不用点「返回志愿者首页」。
        XCTAssertEqual(appState.volunteerProfile?.name, "测试志愿者")
        XCTAssertEqual(appState.volunteerProfile?.registrationStep, "STEP_4_TRAINING")
        XCTAssertFalse(appState.volunteerProfile?.isAvailable ?? true)
        XCTAssertFalse(appState.volunteerProfile?.wantsDispatch ?? true)
        XCTAssertTrue(appState.isVolunteerProfileApproved)
    }

    func testAppStateVolunteerComputedPropertiesRequireCompleteApprovedProfile() {
        let appState = AppState()
        appState.volunteerProfile = nil
        XCTAssertFalse(appState.isVolunteerProfileComplete)
        XCTAssertFalse(appState.isVolunteerProfileApproved)

        appState.volunteerProfile = makeVolunteerProfile(name: "")
        XCTAssertFalse(appState.isVolunteerProfileComplete)
        XCTAssertFalse(appState.isVolunteerProfileApproved)

        appState.volunteerProfile = makeVolunteerProfile()
        XCTAssertTrue(appState.isVolunteerProfileComplete)
        XCTAssertFalse(appState.isVolunteerProfileApproved)

        appState.volunteerProfile = makeApprovedVolunteerProfile()
        XCTAssertTrue(appState.isVolunteerProfileComplete)
        XCTAssertTrue(appState.isVolunteerProfileApproved)

        appState.volunteerProfile = makeVolunteerProfile(
            verificationStatus: "approved",
            adminReviewStatus: "pending",
            isAvailable: true
        )
        XCTAssertTrue(appState.isVolunteerProfileComplete)
        XCTAssertFalse(appState.isVolunteerProfileApproved)
    }

    func testVolunteerProfileDecodesAdminReviewStatus() throws {
        let data = #"{"name":"测试志愿者","verificationStatus":"approved","adminReviewStatus":"approved","wantsDispatch":true}"#
            .data(using: .utf8)!
        let profile = try JSONDecoder().decode(VolunteerProfileResponse.self, from: data)

        XCTAssertEqual(profile.adminReviewStatus, "approved")
        XCTAssertTrue(profile.isCertificationApproved)
        XCTAssertTrue(profile.isAdminReviewApprovedWhenAvailable)
        XCTAssertTrue(profile.hasManualDispatchOptIn)
    }

    func testVolunteerInServiceBlocksFinishBeforeInProgress() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = VolunteerInServiceViewModel()
        viewModel.configure(
            with: appState,
            speechService: speechService,
            initialOrder: makeOrder(orderId: 1, status: .driverArrived)
        )

        await viewModel.complete()

        XCTAssertEqual(viewModel.errorMessage, RunOrderStatus.driverArrived.finishBlockedMessage)
        XCTAssertEqual(speechService.lastSpokenText, RunOrderStatus.driverArrived.finishBlockedMessage)
    }

    func testVolunteerInServiceStartsServiceFromDriverArrived() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let client = appState.apiClient
        try await setMockRole(.volunteer, appState: appState)
        let _: EmptyResponse = try await client.post(
            "/api/orders/1/respond",
            body: OrderRespondRequest(action: .accept)
        )
        let _: EmptyResponse = try await client.post("/api/orders/1/en-route")
        let _: EmptyResponse = try await client.post("/api/orders/1/arrived")
        let detail: OrderDetailResponse = try await client.get("/api/orders/1")

        let viewModel = VolunteerInServiceViewModel()
        viewModel.configure(with: appState, speechService: speechService, initialOrder: detail)

        await viewModel.startService()

        let didConfirmStart = await waitUntil {
            viewModel.order?.status == .inProgress
        }
        XCTAssertTrue(didConfirmStart)
        XCTAssertNil(viewModel.errorMessage)
    }
}
