import UserNotifications
import XCTest
@testable import blindRun

/// #521：推送权限用到时再问。启动时不弹（那时还没过隐私同意、也没登录）；第一个需要推送的时刻先说明用途再问；
/// 拒绝过就给去系统设置的入口；每个角色在本机只主动提示一次。
final class PushPermissionPromptTests: XCTestCase {

    func testNotYetAskedExplainsThenAsks() {
        XCTAssertEqual(PushPermissionPrompt.decide(status: .notDetermined, alreadyPrompted: false), .explainThenAsk)
    }

    func testDeniedOffersSystemSettings() {
        XCTAssertEqual(PushPermissionPrompt.decide(status: .denied, alreadyPrompted: false), .offerSettings)
    }

    /// 对照：已授权不打扰；提示过一次就不再主动弹（拒绝了还反复弹是打扰）。
    func testAuthorizedOrAlreadyPromptedStaysQuiet() {
        XCTAssertNil(PushPermissionPrompt.decide(status: .authorized, alreadyPrompted: false))
        XCTAssertNil(PushPermissionPrompt.decide(status: .notDetermined, alreadyPrompted: true))
        XCTAssertNil(PushPermissionPrompt.decide(status: .denied, alreadyPrompted: true))
    }

    /// 两个角色分开记：同一台手机上先当盲人被问过，换成陪跑员第一次开开关时仍要说明一次（用途不同）。
    func testEachRoleIsPromptedSeparately() {
        XCTAssertNotEqual(PushPermissionPrompt.promptedKey(for: .blind), PushPermissionPrompt.promptedKey(for: .volunteer))
    }

    /// 精确位置关着时，陪跑员打开接单开关先只出精确位置那条提示（念一句、弹临时精确位置框）；
    /// 通知说明等派单位置恢复上报再出 —— 同时出的话后一句会切断前一句，两个弹窗叠在一起。
    @MainActor
    func testVolunteerPushAskWaitsWhilePreciseLocationBlocksDispatch() {
        let location = EscortPreciseLocationGateTests.locationService(accuracy: 5000)
        location.simulatePreciseLocationOffForTesting()
        XCTAssertFalse(PushPermissionPrompt.volunteerNeedsPush(isAvailable: true, location: location), "精确位置关着时不该同时问通知")

        location.simulatePreciseLocationOffForTesting(false)
        XCTAssertTrue(PushPermissionPrompt.volunteerNeedsPush(isAvailable: true, location: location), "打开精确位置后照常问")
        XCTAssertFalse(PushPermissionPrompt.volunteerNeedsPush(isAvailable: false, location: location), "没开接单开关不问")
    }

    /// UI 用例（进程内 Mock）默认不弹，专测这道提示的用例能强制打开；真实安装不受影响。
    func testPromptIsSuppressedOnlyForUITestLaunches() {
        XCTAssertTrue(PushPermissionPrompt.isSuppressedForUITests(environment: ["AIDRUN_UI_TEST_RESET_STATE": "1"]))
        XCTAssertFalse(PushPermissionPrompt.isSuppressedForUITests(environment: [
            "AIDRUN_UI_TEST_RESET_STATE": "1", "AIDRUN_UI_TEST_FORCE_PUSH_PROMPT": "1"
        ]))
        XCTAssertFalse(PushPermissionPrompt.isSuppressedForUITests(environment: [:]), "真实安装照常提示")
    }

    /// 说明要讲清用途（两端各自的提醒），拒绝那句要讲后果与出路。
    func testCopyStatesPurposeConsequenceAndWayOut() {
        XCTAssertTrue(PushPermissionCopy.explanation(for: .blind).contains("到达"))
        XCTAssertTrue(PushPermissionCopy.explanation(for: .volunteer).contains("邀请"))
        for role in [UserRole.blind, .volunteer] {
            XCTAssertTrue(PushPermissionCopy.denied(for: role).contains("收不到"))
            XCTAssertTrue(PushPermissionCopy.denied(for: role).contains("系统设置"))
        }
    }
}
