import XCTest
@testable import blindRun

/// AppState 盲人完成度拆分：基础资料 / 实名状态 / 紧急联系人三者互相独立地判定，
/// 但三者都进 `isBlindBookingReady`——2026-07-30 起实名是服务端硬门槛
/// （`OrderCreationService` → 403 `IDENTITY_NOT_VERIFIED`）。
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

    /// 后端 `OrderCreationService` 要求 `verifyStatus == VERIFIED`，
    /// 其余三态（含字段缺失导致的 unknown）都会被 403 挡回来，客户端必须同样判定为未就绪。
    func testIdentityStatusBlocksBookingUnlessVerified() {
        for status in ["FAILED", "NOT_VERIFIED"] {
            let appState = makeAppState()
            appState.updateBlindProfile(BlindProfileResponse(name: "测试用户", verifyStatus: status))
            appState.updateEmergencyContacts([contact(1, primary: true)])

            XCTAssertFalse(appState.isBlindIdentityVerified, "\(status) 不是 VERIFIED")
            XCTAssertFalse(appState.isBlindBookingReady, "\(status) 必须阻塞下单")
        }

        // 后端没返回 verifyStatus 时按未通过处理，不猜测放行。
        let unknownState = makeAppState()
        unknownState.updateBlindProfile(BlindProfileResponse(name: "测试用户"))
        unknownState.updateEmergencyContacts([contact(1, primary: true)])
        XCTAssertEqual(unknownState.blindIdentityStatus, .unknown)
        XCTAssertFalse(unknownState.isBlindBookingReady)

        let verified = makeAppState()
        verified.updateBlindProfile(BlindProfileResponse(name: "测试用户", verifyStatus: "VERIFIED"))
        verified.updateEmergencyContacts([contact(1, primary: true)])
        XCTAssertTrue(verified.isBlindBookingReady)
    }

    func testBookingReadinessRequiresExactlyOnePrimaryContact() {
        let appState = makeAppState()
        appState.updateBlindProfile(BlindProfileResponse(name: "测试用户", verifyStatus: "VERIFIED"))

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
        XCTAssertFalse(appState.isBlindBookingReady, "未实名不得视为可下单")
        XCTAssertEqual(appState.blindOnboardingStep, .identityPrompt)

        appState.dismissBlindIdentityPrompt()
        XCTAssertNil(appState.blindOnboardingStep, "「稍后再说」放行进首页")
        XCTAssertFalse(
            appState.isBlindBookingReady,
            "跳过引导只是进首页，绝不能顺带把下单门槛也放过"
        )
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
