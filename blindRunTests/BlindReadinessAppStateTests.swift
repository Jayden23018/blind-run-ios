import XCTest
@testable import blindRun

/// AppState 盲人完成度拆分：基础资料 / 实名状态 / 紧急联系人三者互相独立，
/// 只有前者与联系人不变量构成下单硬门槛，实名永远不阻塞。
@MainActor
final class BlindReadinessAppStateTests: XCTestCase {

    private func contact(_ id: Int64, primary: Bool) -> EmergencyContactResponse {
        EmergencyContactResponse(id: id, name: "联系人\(id)", phone: "1390013900\(id)", relationship: "家人", isPrimary: primary)
    }

    private func makeAppState() -> AppState {
        AppState(persistence: AppStatePersistenceFactory.makeIsolatedTest())
    }

    func testBasicProfileIsIndependentOfContactsAndIdentity() {
        let appState = makeAppState()
        XCTAssertFalse(appState.isBlindBasicProfileComplete)

        appState.updateBlindProfile(BlindProfileResponse(name: "  "))
        XCTAssertFalse(appState.isBlindBasicProfileComplete)

        appState.updateBlindProfile(BlindProfileResponse(name: "测试用户"))
        XCTAssertTrue(appState.isBlindBasicProfileComplete)
        XCTAssertEqual(appState.emergencyContactCount, 0)
    }

    func testIdentityStatusIsDisplayOnlyAndDoesNotBlockBooking() {
        let appState = makeAppState()
        appState.updateBlindProfile(BlindProfileResponse(name: "测试用户", verifyStatus: "FAILED"))
        appState.updateEmergencyContacts([contact(1, primary: true)])

        XCTAssertEqual(appState.blindIdentityStatus, .failed)
        XCTAssertTrue(appState.isBlindBookingReady, "实名未通过不得阻塞下单")
    }

    func testBookingReadinessRequiresExactlyOnePrimaryContact() {
        let appState = makeAppState()
        appState.updateBlindProfile(BlindProfileResponse(name: "测试用户"))

        appState.updateEmergencyContacts([contact(1, primary: false)])
        XCTAssertEqual(appState.emergencyContactCount, 1)
        XCTAssertFalse(appState.hasExactlyOnePrimaryEmergencyContact)
        XCTAssertFalse(appState.isBlindBookingReady)

        appState.updateEmergencyContacts([contact(1, primary: true), contact(2, primary: true)])
        XCTAssertNil(appState.primaryEmergencyContact)
        XCTAssertFalse(appState.isBlindBookingReady)

        appState.updateEmergencyContacts([contact(1, primary: true), contact(2, primary: false)])
        XCTAssertEqual(appState.primaryEmergencyContact?.id, 1)
        XCTAssertTrue(appState.isBlindBookingReady)
    }

    // MARK: - 引导流步骤（AppState 侧接线）

    func testOnboardingStepAdvancesAsRequirementsAreSatisfied() {
        let appState = makeAppState()
        XCTAssertEqual(appState.blindOnboardingStep, .basicProfile)

        appState.updateBlindProfile(BlindProfileResponse(name: "测试用户", verifyStatus: "NOT_VERIFIED"))
        XCTAssertEqual(appState.blindOnboardingStep, .emergencyContacts)

        appState.updateEmergencyContacts([contact(1, primary: true)])
        XCTAssertTrue(appState.isBlindBookingReady)
        XCTAssertEqual(appState.blindOnboardingStep, .identityPrompt)

        appState.dismissBlindIdentityPrompt()
        XCTAssertNil(appState.blindOnboardingStep, "实名是软引导，跳过后必须放行进首页")
    }

    func testVerifiedIdentityNeedsNoPromptStep() {
        let appState = makeAppState()
        appState.updateBlindProfile(BlindProfileResponse(name: "测试用户", verifyStatus: "VERIFIED"))
        appState.updateEmergencyContacts([contact(1, primary: true)])

        XCTAssertFalse(appState.didDismissBlindIdentityPrompt)
        XCTAssertNil(appState.blindOnboardingStep)
    }

    /// 「稍后再说」是按账号记的：退出登录后换账号必须重新提示一次。
    func testDismissedPromptIsPersistedAndClearedOnSignOut() {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        let appState = AppState(persistence: persistence)
        appState.dismissBlindIdentityPrompt()

        let restored = AppState(persistence: persistence)
        XCTAssertTrue(restored.didDismissBlindIdentityPrompt, "跳过标记必须跨启动保留")

        appState.clearSession()
        XCTAssertFalse(appState.didDismissBlindIdentityPrompt)
        XCTAssertFalse(AppState(persistence: persistence).didDismissBlindIdentityPrompt)
    }
}
