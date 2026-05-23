//
//  blindRunTests.swift
//  blindRunTests
//
//  Created by Jerry on 5/18/26.
//

import XCTest
@testable import blindRun

@MainActor
final class blindRunTests: XCTestCase {

    func testPhoneLoginRequestUsesOpenAPICamelCaseKeys() throws {
        let request = PhoneLoginRequest(
            phoneNumber: "13800138000",
            verificationCode: "123456"
        )

        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])

        XCTAssertEqual(json["phoneNumber"], "13800138000")
        XCTAssertEqual(json["verificationCode"], "123456")
        XCTAssertNil(json["phone_number"])
        XCTAssertNil(json["code"])
    }

    func testAuthResponseDecodesOpenAPICamelCaseKeys() throws {
        let json = """
        {
          "accessToken": "token",
          "tokenType": "Bearer",
          "user": {
            "id": "00000000-0000-0000-0000-000000000001",
            "phoneNumber": "13800138000",
            "nickname": "测试用户",
            "roles": ["blind_runner", "volunteer"],
            "activeRole": null,
            "createdAt": "2024-01-01T00:00:00Z",
            "updatedAt": "2024-01-01T00:00:00Z"
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(AuthResponse.self, from: json)

        XCTAssertEqual(response.accessToken, "token")
        XCTAssertEqual(response.user.id, "00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(response.user.phoneNumber, "13800138000")
        XCTAssertEqual(response.user.roles, [.blindRunner, .volunteer])
    }

    func testLoginPhoneInputKeepsOnlyFirstElevenDigits() {
        let viewModel = LoginViewModel()

        viewModel.sanitizePhoneInput(" 138 0013 8000 999")

        XCTAssertEqual(viewModel.phoneNumber, "13800138000")
    }

    func testLoginPhoneInputDropsNonDigits() {
        let viewModel = LoginViewModel()

        viewModel.sanitizePhoneInput("abc138-0013-8000xyz")

        XCTAssertEqual(viewModel.phoneNumber, "13800138000")
    }

    func testLoginPhoneDirectAssignmentKeepsOnlyFirstElevenDigits() {
        let viewModel = LoginViewModel()

        viewModel.phoneNumber = "13800138000999"

        XCTAssertEqual(viewModel.phoneNumber, "13800138000")
    }

    func testLoginPhoneSanitizeAlreadyCompleteValueKeepsElevenDigits() {
        let viewModel = LoginViewModel()
        viewModel.phoneNumber = "13800138000"

        viewModel.sanitizePhoneInput("138001380009")

        XCTAssertEqual(viewModel.phoneNumber, "13800138000")
    }

    func testLoginVerificationCodeInputKeepsOnlyFirstSixDigits() {
        let viewModel = LoginViewModel()

        viewModel.sanitizeVerificationCodeInput("123456789")

        XCTAssertEqual(viewModel.verificationCode, "123456")
    }

    func testLoginVerificationCodeInputDropsNonDigits() {
        let viewModel = LoginViewModel()

        viewModel.sanitizeVerificationCodeInput("abc 123-456 xyz")

        XCTAssertEqual(viewModel.verificationCode, "123456")
    }

    func testLoginVerificationCodeDirectAssignmentKeepsOnlyFirstSixDigits() {
        let viewModel = LoginViewModel()

        viewModel.verificationCode = "123456789"

        XCTAssertEqual(viewModel.verificationCode, "123456")
    }

    func testLoginVerificationCodeSanitizeAlreadyCompleteValueKeepsSixDigits() {
        let viewModel = LoginViewModel()
        viewModel.verificationCode = "123456"

        viewModel.sanitizeVerificationCodeInput("1234567")

        XCTAssertEqual(viewModel.verificationCode, "123456")
    }

    func testSubmitLoginWithCompleteInputsDoesNotReenterVerificationCodeSetter() {
        let viewModel = LoginViewModel()
        viewModel.phoneNumber = "13800138000"
        viewModel.verificationCode = "123456"

        viewModel.submitLogin()

        XCTAssertEqual(viewModel.phoneNumber, "13800138000")
        XCTAssertEqual(viewModel.verificationCode, "123456")
    }

    func testDebugInitialEnvironmentFallsBackFromProductionToMock() {
        XCTAssertEqual(AppState.resolvedInitialEnvironment(.production), .mock)
    }

    func testDebugEnvironmentSwitcherCyclesOnlyMockAndLocalBackend() {
        let previousEnvironment = UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.apiEnvironment)
        defer {
            if let previousEnvironment {
                UserDefaults.standard.set(previousEnvironment, forKey: AppConstants.UserDefaultsKeys.apiEnvironment)
            } else {
                UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.apiEnvironment)
            }
        }

        UserDefaults.standard.set(APIEnvironment.mock.rawValue, forKey: AppConstants.UserDefaultsKeys.apiEnvironment)
        let appState = AppState()

        XCTAssertEqual(appState.currentEnvironment, .mock)
        appState.switchToNextEnvironmentForTesting()
        XCTAssertEqual(appState.currentEnvironment, .localBackend)
        appState.switchToNextEnvironmentForTesting()
        XCTAssertEqual(appState.currentEnvironment, .mock)
    }

    func testLocalBackendAddressNormalizationSupportsDeviceLANIP() {
        XCTAssertEqual(
            AppConstants.LocalBackend.normalizedDisplayString(from: "192.168.1.23"),
            "http://192.168.1.23:8080"
        )
        XCTAssertEqual(
            AppConstants.LocalBackend.normalizedDisplayString(from: "http://192.168.1.23:8081"),
            "http://192.168.1.23:8081"
        )
    }

    func testOrderRequestUsesOpenAPIWireValues() throws {
        let request = CreateOrderRequest(
            startLocation: LocationPoint(
                latitude: 31.2304,
                longitude: 121.4737,
                addressText: "人民广场",
                source: .deviceLocation
            ),
            destinationText: "公园慢跑一圈",
            appointmentTime: "2026-05-22T09:00:00Z",
            estimatedDurationMinutes: 60,
            estimatedDistanceKm: 5.0,
            pacePreference: "慢跑",
            preferSameGender: true,
            remark: "请在地铁口见面"
        )

        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let location = try XCTUnwrap(json["startLocation"] as? [String: Any])

        XCTAssertEqual(json["destinationText"] as? String, "公园慢跑一圈")
        XCTAssertEqual(location["addressText"] as? String, "人民广场")
        XCTAssertEqual(location["source"] as? String, "device_location")
        XCTAssertNil(json["routeNotes"])
        XCTAssertNil(location["address"])
    }

    func testBlindBookingResolvedStartLocationKeepsCoordinatesAndAppendsManualDescription() {
        let viewModel = BlindBookingViewModel()
        viewModel.currentResolvedPlace = ResolvedPlace(
            id: "current",
            title: "当前位置",
            addressText: "上海市黄浦区人民广场",
            latitude: 31.2304,
            longitude: 121.4737,
            source: .deviceLocation
        )
        viewModel.startLocationDescription = "我在地铁口外侧"

        XCTAssertEqual(viewModel.resolvedStartPlace?.latitude, 31.2304)
        XCTAssertEqual(viewModel.resolvedStartPlace?.longitude, 121.4737)
        XCTAssertEqual(viewModel.resolvedStartPlace?.source, .deviceLocation)
        XCTAssertEqual(viewModel.resolvedStartLocationDescription, "上海市黄浦区人民广场；补充：我在地铁口外侧")
    }

    func testManualCancellationReasonKeepsOpenAPIWireValueAndChineseLabel() throws {
        let request = CancelOrderRequest(
            cancelledBy: .blindRunner,
            cancelledReason: .wrongLocation,
            otherReasonText: nil
        )

        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])

        XCTAssertEqual(json["cancelledBy"], "blind_runner")
        XCTAssertEqual(json["cancelledReason"], "wrong_location")
        XCTAssertEqual(ManualCancellationReason.wrongLocation.displayName, "地点填写错误")
    }

    func testBlindBookingRequiresAppointmentAtLeastThirtyMinutesLater() {
        let viewModel = BlindBookingViewModel()

        viewModel.appointmentTime = Date().addingTimeInterval(10 * 60)

        XCTAssertFalse(viewModel.isAppointmentTimeValid)

        viewModel.appointmentTime = Date().addingTimeInterval(31 * 60)

        XCTAssertTrue(viewModel.isAppointmentTimeValid)
    }

    func testBlindBookingDurationPaceAndDistanceAreNotSpeechFields() {
        XCTAssertEqual(BookingDurationOption.sixty.minutes, 60)
        XCTAssertNil(BookingDurationOption.none.minutes)
        XCTAssertEqual(PacePreferenceOption.slow.requestValue, "慢跑")
        XCTAssertNil(PacePreferenceOption.none.requestValue)

        let viewModel = BlindBookingViewModel()
        viewModel.sanitizeDistanceInput("5公里")
        XCTAssertEqual(viewModel.estimatedDistanceText, "5")
    }

    func testEmergencyButtonStatusGate() {
        XCTAssertFalse(RunOrderStatus.matching.canEnterEmergency)
        XCTAssertTrue(RunOrderStatus.accepted.canEnterEmergency)
        XCTAssertTrue(RunOrderStatus.arrived.canEnterEmergency)
        XCTAssertTrue(RunOrderStatus.inProgress.canEnterEmergency)
        XCTAssertFalse(RunOrderStatus.completed.canEnterEmergency)
        XCTAssertFalse(RunOrderStatus.cancelled.canEnterEmergency)
        XCTAssertFalse(RunOrderStatus.emergency.canEnterEmergency)
    }

    func testArrivedIsOnlyBlindConfirmStartStatus() {
        let viewModel = BlindOrderStatusViewModel()

        viewModel.order = makeOrder(status: .accepted)
        XCTAssertFalse(viewModel.canShowConfirmStart)

        viewModel.order = makeOrder(status: .arrived)
        XCTAssertTrue(viewModel.canShowConfirmStart)

        viewModel.order = makeOrder(status: .inProgress)
        XCTAssertFalse(viewModel.canShowConfirmStart)
    }

    func testBlindOrderPollingUsesFiveSecondsAndStopsOnTerminalStates() {
        XCTAssertEqual(AppConstants.Timing.orderPollingInterval, 5.0)
        XCTAssertTrue(RunOrderStatus.matching.shouldPollOnBlindRunnerPage)
        XCTAssertTrue(RunOrderStatus.accepted.shouldPollOnBlindRunnerPage)
        XCTAssertTrue(RunOrderStatus.arrived.shouldPollOnBlindRunnerPage)
        XCTAssertTrue(RunOrderStatus.inProgress.shouldPollOnBlindRunnerPage)
        XCTAssertFalse(RunOrderStatus.completed.shouldPollOnBlindRunnerPage)
        XCTAssertFalse(RunOrderStatus.cancelled.shouldPollOnBlindRunnerPage)
        XCTAssertFalse(RunOrderStatus.emergency.shouldPollOnBlindRunnerPage)
    }

    func testVolunteerAcceptGuardRequiresCompleteProfile() {
        XCTAssertEqual(
            VolunteerOrderActionGuard.acceptBlockMessage(profile: nil),
            "请先完善志愿者资料"
        )

        XCTAssertEqual(
            VolunteerOrderActionGuard.acceptBlockMessage(profile: makeVolunteerProfile(nickname: "")),
            "请先完善志愿者资料"
        )

        XCTAssertEqual(
            VolunteerOrderActionGuard.acceptBlockMessage(profile: makeVolunteerProfile(phoneNumber: "123")),
            "请先完善志愿者资料"
        )
    }

    func testVolunteerAcceptGuardRequiresApprovalAndAvailability() {
        XCTAssertEqual(
            VolunteerOrderActionGuard.acceptBlockMessage(profile: makeVolunteerProfile()),
            "请先完成志愿者认证"
        )

        XCTAssertEqual(
            VolunteerOrderActionGuard.acceptBlockMessage(profile: makeApprovedVolunteerProfile(isAvailable: false)),
            "请先开启可服务状态"
        )

        XCTAssertNil(
            VolunteerOrderActionGuard.acceptBlockMessage(profile: makeApprovedVolunteerProfile(isAvailable: true))
        )
    }

    func testAppStateVolunteerComputedPropertiesRequireCompleteApprovedAvailableProfile() {
        let appState = AppState()
        appState.volunteerProfile = nil
        XCTAssertFalse(appState.isVolunteerProfileComplete)
        XCTAssertFalse(appState.isVolunteerProfileApproved)
        XCTAssertFalse(appState.canVolunteerAcceptOrders)

        appState.volunteerProfile = makeVolunteerProfile(phoneNumber: "123")
        XCTAssertFalse(appState.isVolunteerProfileComplete)
        XCTAssertFalse(appState.isVolunteerProfileApproved)
        XCTAssertFalse(appState.canVolunteerAcceptOrders)

        appState.volunteerProfile = makeVolunteerProfile()
        XCTAssertTrue(appState.isVolunteerProfileComplete)
        XCTAssertFalse(appState.isVolunteerProfileApproved)
        XCTAssertFalse(appState.canVolunteerAcceptOrders)

        appState.volunteerProfile = makeApprovedVolunteerProfile(isAvailable: false)
        XCTAssertTrue(appState.isVolunteerProfileComplete)
        XCTAssertTrue(appState.isVolunteerProfileApproved)
        XCTAssertFalse(appState.canVolunteerAcceptOrders)

        appState.volunteerProfile = makeApprovedVolunteerProfile(isAvailable: true)
        XCTAssertTrue(appState.canVolunteerAcceptOrders)
    }

    private func makeVolunteerProfile(
        nickname: String = "测试志愿者",
        phoneNumber: String = "13800138000",
        verificationStatus: VerificationStatus = .notSubmitted,
        adminReviewStatus: AdminReviewStatus = .notSubmitted,
        isAvailable: Bool = false
    ) -> VolunteerProfileDto {
        VolunteerProfileDto(
            id: "20000000-0000-0000-0000-000000000001",
            userId: "00000000-0000-0000-0000-000000000001",
            nickname: nickname,
            phoneNumber: phoneNumber,
            verificationStatus: verificationStatus,
            adminReviewStatus: adminReviewStatus,
            isAvailable: isAvailable,
            pointsBalance: 0,
            createdAt: "2024-01-01T00:00:00Z",
            updatedAt: "2024-01-01T00:00:00Z"
        )
    }

    private func makeApprovedVolunteerProfile(isAvailable: Bool) -> VolunteerProfileDto {
        makeVolunteerProfile(
            verificationStatus: .approved,
            adminReviewStatus: .approved,
            isAvailable: isAvailable
        )
    }

    private func makeOrder(status: RunOrderStatus) -> RunOrderDto {
        RunOrderDto(
            id: "30000000-0000-0000-0000-000000000001",
            blindRunnerUserId: "00000000-0000-0000-0000-000000000001",
            blindRunnerNickname: "测试跑者",
            blindRunnerPhone: "13800138000",
            volunteerUserId: status == .matching ? nil : "20000000-0000-0000-0000-000000000001",
            volunteerNickname: status == .matching ? nil : "测试志愿者",
            status: status,
            startLocation: LocationPoint(
                latitude: 39.9042,
                longitude: 116.4074,
                addressText: "当前位置",
                source: .demoDefault
            ),
            destinationText: nil,
            appointmentTime: "2026-05-22T09:00:00Z",
            estimatedDurationMinutes: nil,
            estimatedDistanceKm: nil,
            pacePreference: nil,
            preferSameGender: nil,
            remark: nil,
            cancellation: nil,
            emergencyEvent: nil,
            serviceSummary: nil,
            rating: nil,
            createdAt: "2026-05-22T08:00:00Z",
            updatedAt: "2026-05-22T08:00:00Z",
            acceptedAt: nil,
            arrivedAt: nil,
            startedAt: nil,
            completedAt: nil,
            cancelledAt: nil,
            emergencyAt: nil
        )
    }
}
