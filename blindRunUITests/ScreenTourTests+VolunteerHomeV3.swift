import XCTest

/// 陪跑员首页 v3（#694）的验收截图：没在接单 / 接单中 / 有待确认预约 / 新用户 / AX5 / 深色 / 接单页。
/// 截图框架与跑法见 `ScreenTourTests` 顶部。拆在这里是为了不让主文件超过 SwiftLint 的长度上限。
extension ScreenTourTests {
    /// 本月跑过三次（有公里数和路线缩略图），给最近陪跑卡一条可拍的记录。
    static let homeHistory = ["AIDRUN_UI_TEST_SEED_HOME_HISTORY": "this"]

    @MainActor func testTour_V05_HomeV3Off() {
        let app = launchVolunteer(available: false, env: Self.homeHistory)
        shoot(app, "V05-home-v3-off", anchor: "volunteerProfileRecentRunCard", scroll: true)
    }

    @MainActor func testTour_V06_HomeV3On() {
        let app = launchVolunteer(env: Self.homeHistory)
        shoot(app, "V06-home-v3-on", anchor: "volunteerProfileRecentRunCard", scroll: true)
    }

    /// 有一张约好的预约：「需要你处理」那张卡（#463）仍在首页最上方。
    @MainActor func testTour_V07_HomeV3Scheduled() {
        let app = launchVolunteer(seed: "SCHEDULED_CONFIRMED")
        // 有约好的单时冷启动会直接进订单页（§4.1 三岔路），先退回首页。
        let home = app.descendants(matching: .any)["volunteerProfileIdentityRow"].firstMatch
        if !home.waitForExistence(timeout: 15) {
            // 订单页的返回键是页面自己画的（标签「返回」），不在系统导航栏里。
            let back = app.buttons["返回"].firstMatch
            if back.waitForExistence(timeout: 10) { back.tap() }
        }
        shoot(app, "V07-home-v3-scheduled", anchor: "volunteerProfileIdentityRow", scroll: true)
    }

    /// 新用户 0 次：陪伴时长卡是新人态，没有半宽卡，最近陪跑是空态。
    @MainActor func testTour_V08_HomeV3Newcomer() {
        let app = launchVolunteer(available: false, env: ["AIDRUN_UI_TEST_EMPTY_MOCK_ORDERS": "1"])
        shoot(app, "V08-home-v3-newcomer", anchor: "volunteerProfileRecentEmpty", scroll: true)
    }

    @MainActor func testTour_V09_HomeV3AX5() {
        let app = launchVolunteer(
            env: Self.homeHistory,
            arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        )
        shoot(app, "V09-home-v3-ax5", anchor: "volunteerProfileIdentityRow", scroll: true)
    }

    @MainActor func testTour_V09b_HomeV3Dark() {
        XCUIDevice.shared.appearance = .dark
        addTeardownBlock { await MainActor.run { XCUIDevice.shared.appearance = .light } }
        let app = launchVolunteer(env: Self.homeHistory)
        shoot(app, "V09b-home-v3-dark", anchor: "volunteerProfileRecentRunCard", scroll: true)
    }

    @MainActor func testTour_V20_DispatchHub() {
        let app = launchVolunteer(env: Self.homeHistory)
        let enter = app.buttons["进入接单"].firstMatch
        if enter.waitForExistence(timeout: 25) { enter.tap() }
        shoot(app, "V20-dispatch-hub", anchor: "volunteerDispatchHubAcceptingPill", scroll: true)
    }
}
