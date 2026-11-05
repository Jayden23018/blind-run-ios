import XCTest
@testable import blindRun

/// AppState 盲人完成度拆分：基础资料 / 紧急联系人互相独立地判定，两者都进 `isBlindBookingReady`。
/// 2026-11-05 起视障跑者不再实名（#767），实名状态不参与。
@MainActor
final class BlindReadinessAppStateTests: XCTestCase {

    private func contact(_ id: Int64, primary: Bool) -> EmergencyContactResponse {
        EmergencyContactResponse(id: id, name: "联系人\(id)", phone: "1390013900\(id)", relationship: "家人", isPrimary: primary)
    }

    private func makeAppState() -> AppState {
        AppState(persistence: AppStatePersistenceFactory.makeIsolatedTest())
    }

    func testBasicProfileIsIndependentOfContacts() {
        let appState = makeAppState()
        XCTAssertFalse(appState.isBlindBasicProfileComplete)

        appState.updateBlindProfile(BlindProfileResponse(name: "  "))
        XCTAssertFalse(appState.isBlindBasicProfileComplete)

        appState.updateBlindProfile(BlindProfileResponse(name: "测试用户"))
        XCTAssertTrue(appState.isBlindBasicProfileComplete)
        XCTAssertEqual(appState.emergencyContactCount, 0)
    }

    /// 后端还会照旧下发 `verifyStatus`，不管它是什么值都不能再挡下单。
    func testIdentityStatusNoLongerAffectsBooking() {
        for status in ["FAILED", "NOT_VERIFIED", "VERIFIED", nil] {
            let appState = makeAppState()
            appState.updateBlindProfile(BlindProfileResponse(name: "测试用户", verifyStatus: status))
            appState.updateEmergencyContacts([contact(1, primary: true)])

            XCTAssertTrue(appState.isBlindBookingReady, "\(status ?? "nil") 不应阻塞下单")
        }
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

    // MARK: - 约跑页「约跑前还差 N 项」（#781）

    /// 新用户不再有引导页，缺什么由约跑页顶部那张卡列出来。
    /// 三种紧急联系人状态各取一值：一个都没有、有人但没有唯一主联系人、齐了 ——
    /// 若实现把后两种塌成同一句，或「齐了」仍出一行，这里会红。
    func testMissingSetupCardListsOnlyWhatIsStillMissing() {
        let appState = makeAppState()
        var card = BlindBookingMissingSetupCard(appState: appState)
        XCTAssertTrue(card.needsNickname)
        XCTAssertEqual(card.emergencyContactsValue, "未添加")

        appState.updateBlindProfile(BlindProfileResponse(name: "测试用户"))
        appState.updateEmergencyContacts([contact(1, primary: false)])
        card = BlindBookingMissingSetupCard(appState: appState)
        XCTAssertFalse(card.needsNickname)
        XCTAssertEqual(card.emergencyContactsValue, "未设主联系人")

        appState.updateEmergencyContacts([contact(1, primary: true)])
        card = BlindBookingMissingSetupCard(appState: appState)
        XCTAssertFalse(card.needsNickname)
        XCTAssertNil(card.emergencyContactsValue, "齐了就不再列这一行")
        XCTAssertTrue(appState.isBlindBookingReady)
    }
}
