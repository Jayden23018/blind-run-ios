import XCTest
@testable import blindRun

/// 下单硬门槛与盲人引导流的顺序判定。两者都是纯函数，直接驱动。
final class BlindBookingGateTests: XCTestCase {

    // MARK: - 下单门槛

    func testAllSatisfiedReturnsNoGate() {
        XCTAssertNil(
            BlindBookingGate.firstMissing(
                isBasicProfileComplete: true,
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
            .basicProfile, .emergencyContacts, .locationPermission, .startPoint, .appointmentTime
        ]
        var flags = [false, false, true, false, false] // profile, contacts, locationDenied, startPoint, timeValid

        for expected in expectedSequence {
            let gate = BlindBookingGate.firstMissing(
                isBasicProfileComplete: flags[0],
                hasValidEmergencyContacts: flags[1],
                isLocationDenied: flags[2],
                hasStartPoint: flags[3],
                isAppointmentTimeValid: flags[4]
            )
            XCTAssertEqual(gate, expected)

            switch expected {
            case .basicProfile: flags[0] = true
            case .emergencyContacts: flags[1] = true
            case .locationPermission: flags[2] = false
            case .startPoint: flags[3] = true
            case .appointmentTime: flags[4] = true
            }
        }

        XCTAssertNil(
            BlindBookingGate.firstMissing(
                isBasicProfileComplete: flags[0],
                hasValidEmergencyContacts: flags[1],
                isLocationDenied: flags[2],
                hasStartPoint: flags[3],
                isAppointmentTimeValid: flags[4]
            )
        )
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

    /// 实名是软引导：跳过后不再拦，直接进首页。
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
