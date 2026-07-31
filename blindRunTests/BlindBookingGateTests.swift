import XCTest
@testable import blindRun

/// 下单硬门槛与盲人引导流的顺序判定。两者都是纯函数，直接驱动。
final class BlindBookingGateTests: XCTestCase {

    // MARK: - 下单门槛

    func testAllSatisfiedReturnsNoGate() {
        XCTAssertNil(
            BlindBookingGate.firstMissing(
                isBasicProfileComplete: true,
                isIdentityVerified: true,
                hasValidEmergencyContacts: true,
                isLocationDenied: false,
                hasStartPoint: true,
                isAppointmentTimeValid: true
            )
        )
    }

    func testFirstMissingFollowsDeclaredOrder() {
        // 全部缺失时只报第一个可操作项，逐个补齐后依次推进。
        let expectedSequence: [BlindBookingGate] = [
            .basicProfile, .identityVerification, .emergencyContacts,
            .locationPermission, .startPoint, .appointmentTime
        ]
        // profile, identity, contacts, locationDenied, startPoint, timeValid
        var flags = [false, false, false, true, false, false]

        for expected in expectedSequence {
            let gate = BlindBookingGate.firstMissing(
                isBasicProfileComplete: flags[0],
                isIdentityVerified: flags[1],
                hasValidEmergencyContacts: flags[2],
                isLocationDenied: flags[3],
                hasStartPoint: flags[4],
                isAppointmentTimeValid: flags[5]
            )
            XCTAssertEqual(gate, expected)

            switch expected {
            case .basicProfile: flags[0] = true
            case .identityVerification: flags[1] = true
            case .emergencyContacts: flags[2] = true
            case .locationPermission: flags[3] = false
            case .startPoint: flags[4] = true
            case .appointmentTime: flags[5] = true
            }
        }

        XCTAssertNil(
            BlindBookingGate.firstMissing(
                isBasicProfileComplete: flags[0],
                isIdentityVerified: flags[1],
                hasValidEmergencyContacts: flags[2],
                isLocationDenied: flags[3],
                hasStartPoint: flags[4],
                isAppointmentTimeValid: flags[5]
            )
        )
    }

    /// 后端 `OrderCreationService` 先查实名再查紧急联系人；两者同时缺失时
    /// 客户端**不能**先播报紧急联系人，否则用户补完联系人还是会被 403 挡回来。
    func testIdentityGateIsReportedBeforeEmergencyContacts() {
        let gate = BlindBookingGate.firstMissing(
            isBasicProfileComplete: true,
            isIdentityVerified: false,
            hasValidEmergencyContacts: false,
            isLocationDenied: false,
            hasStartPoint: true,
            isAppointmentTimeValid: true
        )
        XCTAssertEqual(gate, .identityVerification)
        XCTAssertNotEqual(gate, .emergencyContacts)

        // 只有实名补上之后，紧急联系人才成为下一个被播报的缺失项。
        XCTAssertEqual(
            BlindBookingGate.firstMissing(
                isBasicProfileComplete: true,
                isIdentityVerified: true,
                hasValidEmergencyContacts: false,
                isLocationDenied: false,
                hasStartPoint: true,
                isAppointmentTimeValid: true
            ),
            .emergencyContacts
        )
    }

    /// 实名档的播报必须给出能走通的下一步（设置 → 实名认证），不能只说"不行"。
    func testIdentityGateMessagePointsToIdentityPage() {
        let message = BlindBookingGate.identityVerification.message
        XCTAssertTrue(message.contains("实名认证"))
        XCTAssertTrue(message.contains("设置"))
    }

    // MARK: - 引导流步骤

    func testOnboardingStepOrder() {
        XCTAssertEqual(
            BlindOnboardingStep.first(
                isBasicProfileComplete: false,
                hasValidEmergencyContacts: false,
                shouldPromptIdentity: true,
                didDismissIdentityPrompt: false
            ),
            .basicProfile
        )

        XCTAssertEqual(
            BlindOnboardingStep.first(
                isBasicProfileComplete: true,
                hasValidEmergencyContacts: false,
                shouldPromptIdentity: true,
                didDismissIdentityPrompt: false
            ),
            .emergencyContacts
        )

        XCTAssertEqual(
            BlindOnboardingStep.first(
                isBasicProfileComplete: true,
                hasValidEmergencyContacts: true,
                shouldPromptIdentity: true,
                didDismissIdentityPrompt: false
            ),
            .identityPrompt
        )
    }

    /// 引导流的「稍后再说」只放行进首页（还能看历史订单、进设置），
    /// **不等于放行下单**——下单拦截在 `BlindBookingGate.identityVerification`。
    func testDismissedIdentityPromptLetsUserThrough() {
        XCTAssertNil(
            BlindOnboardingStep.first(
                isBasicProfileComplete: true,
                hasValidEmergencyContacts: true,
                shouldPromptIdentity: true,
                didDismissIdentityPrompt: true
            )
        )

        XCTAssertNil(
            BlindOnboardingStep.first(
                isBasicProfileComplete: true,
                hasValidEmergencyContacts: true,
                shouldPromptIdentity: false,
                didDismissIdentityPrompt: false
            )
        )
    }
}
