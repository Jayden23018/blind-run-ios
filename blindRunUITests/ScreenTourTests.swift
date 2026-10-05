import XCTest

/// 两端全流程截图巡游：把盲人跑者与陪跑员各自会走到的每一屏都截一张（长页面再截一张滚到底的），
/// 给界面评审与「改前 / 改后」逐屏对比用。
///
/// 只断「这一屏到了」，不断长相。**设了锚点的**那几屏到不了时照样截图，名字带 `MISSING`，并记一条失败 ——
/// 一屏没到不该挡住后面几十屏，所以每屏是一条独立用例（各自冷启动）。
/// ⚠️ 锚点为 `nil` 的那几屏（订单各状态、帮助页、「我的」等）**不会**标 `MISSING`：到没到要看图判断。
/// 它会主动 `XCTFail`，**别放进全量批次**（`device-test-all.sh`）—— 已知的锚点失败会盖住新的红灯。
///
/// 全部走进程内 Mock（`AIDRUN_UI_TEST_API_ENV=mock`），不连真实后端；地图默认关
/// （记忆 `ui-test-defaults-verify-the-degraded-path`），只有 `testTour_Z*` 两条打开真地图，
/// 用来留一张带高德审图号的图。
///
/// 跑法与取图：
///
///     scripts/device-test.sh -only-testing:blindRunUITests/ScreenTourTests
///
/// 截图按名字从脚本打印的 `attachments/` 目录取（`manifest.json` 记了归属）。
final class ScreenTourTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: - 盲人跑者：进 App 之前

    @MainActor func testTour_B01_PrivacyConsent() {
        let app = launch(role: nil, token: nil, env: ["AIDRUN_UI_TEST_FORCE_PRIVACY_CONSENT": "1"])
        shoot(app, "B01-privacy-consent", anchor: "rootRoute.privacyConsent")
    }

    @MainActor func testTour_B02_Login() {
        let app = launch(role: nil, token: nil)
        shoot(app, "B02-login", anchor: app.textFields["手机号输入框，请输入 11 位手机号"].firstMatch)
    }

    @MainActor func testTour_B03_RoleSelection() {
        let app = launch(role: nil, token: "roleless-token", env: ["AIDRUN_UI_TEST_EMPTY_MOCK_ORDERS": "1"])
        shoot(app, "B03-role-selection", anchor: app.buttons["我是盲人跑者，预约志愿者陪我跑步"].firstMatch, scroll: true)
    }

    @MainActor func testTour_B04_FirstRunHelp() {
        let app = launchBlind(env: ["AIDRUN_UI_TEST_FORCE_FIRST_RUN_HELP": "1"])
        sleep(3)
        shoot(app, "B04-first-run-help", anchor: nil, scroll: true)
    }

    // MARK: - 盲人跑者：首页与下单

    @MainActor func testTour_B05_HomeEmpty() {
        let app = launchBlind()
        shoot(app, "B05-home-empty", anchor: "blindRunnerHomeStartBookingButton")
    }

    @MainActor func testTour_B06_BookingForm() {
        let app = launchBlind()
        guard tapIfAppears(app, "blindRunnerHomeStartBookingButton") else {
            return shoot(app, "B06-booking", anchor: "blindRunnerHomeStartBookingButton")
        }
        dismissSystemAlerts()
        shoot(app, "B06-booking", anchor: anyOf(app, ["blindBookingVoiceOrderButton", "blindBookingFinishSpeakingSurface"]), scroll: true)
    }

    @MainActor func testTour_B07_BookingVoice() {
        let app = launchBlind(env: ["AIDRUN_UI_TEST_FORCE_VOICE_STAGE": "1"])
        guard tapIfAppears(app, "blindRunnerHomeStartBookingButton") else {
            return shoot(app, "B07-booking-voice", anchor: "blindRunnerHomeStartBookingButton")
        }
        dismissSystemAlerts()
        shoot(app, "B07-booking-voice", anchor: "blindBookingFinishSpeakingSurface")
    }

    @MainActor func testTour_B08_HomeWithOrder() {
        let app = launchBlind(emptyOrders: false)
        shoot(app, "B08-home-with-order", anchor: "blindRunnerHomeOrderCard", scroll: true)
    }

    // MARK: - 盲人跑者：订单各状态（从首页订单卡点进去）

    @MainActor func testTour_B10_OrderPendingMatch() { blindOrder("PENDING_MATCH", "B10") }
    @MainActor func testTour_B11_OrderPendingIntroCall() { blindOrder("PENDING_INTRO_CALL", "B11") }
    @MainActor func testTour_B12_OrderScheduledConfirmed() { blindOrder("SCHEDULED_CONFIRMED", "B12") }
    @MainActor func testTour_B13_OrderPendingAccept() { blindOrder("PENDING_ACCEPT", "B13") }
    @MainActor func testTour_B14_OrderDriverEnRoute() { blindOrder("DRIVER_EN_ROUTE", "B14") }
    @MainActor func testTour_B15_OrderDriverArrived() { blindOrder("DRIVER_ARRIVED", "B15") }
    @MainActor func testTour_B16_OrderInProgress() { blindOrder("IN_PROGRESS", "B16") }
    @MainActor func testTour_B17_OrderRematching() { blindOrder("REMATCHING", "B17") }
    /// 「已完成」在订单页上原地变形（与跑步中同一格，`BlindOrderFlowStep`），首页不列已结束的订单 ——
    /// 直接种 `COMPLETED` 从首页点不进去。从跑步中点 Mock 的「模拟服务完成」走进去才是真实那一屏。
    /// （「无人接单」同理到不了：首页没有入口、Mock 也没有对应按钮，所以这一屏不在巡游里。）
    @MainActor func testTour_B19_OrderCompleted() {
        let app = launchBlind(emptyOrders: false, seed: "IN_PROGRESS")
        _ = tapIfAppears(app, "blindRunnerHomeOrderCard", timeout: 15)
        let finish = app.buttons["模拟服务完成"].firstMatch
        var drags = 0
        while !finish.waitForExistence(timeout: drags == 0 ? 10 : 1) && drags < 4 {
            app.swipeUp()
            drags += 1
        }
        guard finish.exists else {
            return shoot(app, "B19-blind-COMPLETED", anchor: finish)
        }
        finish.tap()
        sleep(3)
        app.swipeDown()
        app.swipeDown()
        shoot(app, "B19-blind-COMPLETED", anchor: nil, scroll: true)
    }

    @MainActor func testTour_B20_SafetyHub() {
        let app = launchBlind(emptyOrders: false)
        guard tapIfAppears(app, "blindRunnerHomeOrderCard"),
              tapIfAppears(app, "blindOrderFlowSafetyHubButton") else {
            return shoot(app, "B20-safety-hub", anchor: "blindSafetyHub")
        }
        shoot(app, "B20-safety-hub", anchor: "blindSafetyHub", scroll: true)
    }

    @MainActor func testTour_B21_IntroCall() {
        let app = launchBlind(emptyOrders: false, seed: "PENDING_INTRO_CALL")
        _ = tapIfAppears(app, "blindRunnerHomeOrderCard")
        guard tapIfAppears(app, "blindOrderStatusIntroCallEntryButton") else {
            return shoot(app, "B21-intro-call", anchor: "blindIntroCallTitle")
        }
        shoot(app, "B21-intro-call", anchor: "blindIntroCallTitle", scroll: true)
    }

    // MARK: - 盲人跑者：其余三个标签

    @MainActor func testTour_B30_Xinghuo() {
        let app = launchBlind()
        tapTab(app, "星火")
        shoot(app, "B30-xinghuo", anchor: "xinghuoSummary", scroll: true)
    }

    @MainActor func testTour_B31_Records() {
        let app = launchBlind(emptyOrders: false, env: ["AIDRUN_UI_TEST_SEED_HISTORY": "1"])
        tapTab(app, "记录")
        shoot(app, "B31-records", anchor: "runRecordHistorySummary", scroll: true)
    }

    @MainActor func testTour_B32_RecordDetail() {
        let app = launchBlind(emptyOrders: false, env: ["AIDRUN_UI_TEST_SEED_HISTORY": "1"])
        tapTab(app, "记录")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "和", "公里")).firstMatch
        if row.waitForExistence(timeout: 15) { row.tap() }
        shoot(app, "B32-record-detail", anchor: "runnerRunRecordHeader", scroll: true)
    }

    @MainActor func testTour_B33_Profile() {
        let app = launchBlind()
        tapTab(app, "我的")
        sleep(2)
        shoot(app, "B33-profile", anchor: nil, scroll: true)
    }

    // MARK: - 陪跑员：首页

    @MainActor func testTour_V01_HomeOff() {
        let app = launchVolunteer(available: false)
        shoot(app, "V01-home-off", anchor: app.buttons["向右滑动，我现在有空陪跑"].firstMatch, scroll: true)
    }

    @MainActor func testTour_V02_HomeOn() {
        let app = launchVolunteer()
        shoot(app, "V02-home-on", anchor: app.buttons["进入接单"].firstMatch, scroll: true)
    }

    @MainActor func testTour_V03_InviteSheet() {
        let app = launchVolunteer(env: ["AIDRUN_UI_TEST_SEED_INVITES": "1"])
        shoot(app, "V03-invite", anchor: app.buttons["接下这次陪跑"].firstMatch)
    }

    @MainActor func testTour_V04_Achievements() {
        let app = launchVolunteer()
        let entry = app.descendants(matching: .any)["查看服务成就"].firstMatch
        var drags = 0
        while !entry.waitForExistence(timeout: drags == 0 ? 15 : 1) && drags < 8 {
            app.swipeUp()
            drags += 1
        }
        if entry.exists { entry.tap() }
        shoot(app, "V04-achievements", anchor: "volunteerServiceRecognitionView", scroll: true)
    }

    // MARK: - 陪跑员：订单各状态（有在途订单时打开 App 直接进订单页）

    @MainActor func testTour_V10_OrderPendingIntroCall() { volunteerOrder("PENDING_INTRO_CALL", "V10") }
    @MainActor func testTour_V11_OrderScheduledConfirmed() { volunteerOrder("SCHEDULED_CONFIRMED", "V11") }
    @MainActor func testTour_V12_OrderPendingAccept() { volunteerOrder("PENDING_ACCEPT", "V12") }
    @MainActor func testTour_V13_OrderDriverEnRoute() { volunteerOrder("DRIVER_EN_ROUTE", "V13") }
    @MainActor func testTour_V14_OrderDriverArrived() { volunteerOrder("DRIVER_ARRIVED", "V14") }
    @MainActor func testTour_V15_OrderInProgress() { volunteerOrder("IN_PROGRESS", "V15") }

    @MainActor func testTour_V16_RunHelpPanel() {
        let app = launchVolunteer(seed: "IN_PROGRESS")
        guard tapIfAppears(app, "volunteerServiceSOSButton", timeout: 25) else {
            return shoot(app, "V16-run-help-panel", anchor: "volunteerServiceSOSButton")
        }
        sleep(1)
        shoot(app, "V16-run-help-panel", anchor: nil)
    }

    /// 直接种 `COMPLETED`：Mock 只在这条路上带完赛三项与 `completedTogetherCount`，拍的是满配的完成页。
    /// 下面 V17（从跑步中长按结束进来）这几项留空，拍的是降级样子 —— 两张都要。
    @MainActor func testTour_V18_CompletedWithRunData() { volunteerOrder("COMPLETED", "V18") }

    @MainActor func testTour_V17_Completed() {
        let app = launchVolunteer(seed: "IN_PROGRESS")
        let finish = app.descendants(matching: .any)["volunteerFinishEscortButton"].firstMatch
        if finish.waitForExistence(timeout: 25) { finish.press(forDuration: 2.6) }
        shoot(app, "V17-completed", anchor: "volunteerOrderFlowRow-runRecord", scroll: true)
    }

    // MARK: - 陪跑员：其余标签

    @MainActor func testTour_V30_Records() {
        let app = launchVolunteer(env: ["AIDRUN_UI_TEST_SEED_HISTORY": "1"])
        tapTab(app, "记录")
        shoot(app, "V30-records", anchor: "runRecordHistorySummary", scroll: true)
    }

    @MainActor func testTour_V31_RecordDetail() {
        let app = launchVolunteer(env: ["AIDRUN_UI_TEST_SEED_HISTORY": "1"])
        tapTab(app, "记录")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "陪", "公里")).firstMatch
        if row.waitForExistence(timeout: 15) { row.tap() }
        shoot(app, "V31-record-detail", anchor: "runRecordDistance", scroll: true)
    }

    /// 陪跑员的「我的」标签直接是设置列表（个人主页并进了首页，见 V02）。
    @MainActor func testTour_V32_Profile() {
        let app = launchVolunteer()
        tapTab(app, "我的")
        sleep(2)
        shoot(app, "V32-profile", anchor: nil, scroll: true)
    }

    // MARK: - 真地图（高德审图号要带真 key 的构建才看得到，见后端 #382）

    @MainActor func testTour_Z01_BlindInProgressWithMap() {
        blindOrder("IN_PROGRESS", "Z01-map", env: ["AIDRUN_UI_TEST_DISABLE_MAP": "0"])
    }

    @MainActor func testTour_Z02_RecordDetailWithMap() {
        let app = launchBlind(emptyOrders: false, env: ["AIDRUN_UI_TEST_SEED_HISTORY": "1", "AIDRUN_UI_TEST_DISABLE_MAP": "0"])
        tapTab(app, "记录")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "和", "公里")).firstMatch
        if row.waitForExistence(timeout: 15) { row.tap() }
        sleep(4)
        shoot(app, "Z02-map-record-detail", anchor: "runnerRunRecordHeader")
    }

    // MARK: - 流程

    @MainActor private func blindOrder(_ status: String, _ prefix: String, env: [String: String] = [:]) {
        let app = launchBlind(emptyOrders: false, seed: status, env: env)
        // 跑步中与部分状态打开 App 就直接在订单页上，没有首页订单卡可点 —— 两条路都算到了。
        _ = tapIfAppears(app, "blindRunnerHomeOrderCard", timeout: 15)
        sleep(2)
        shoot(app, "\(prefix)-blind-\(status)", anchor: nil, scroll: true)
    }

    @MainActor private func volunteerOrder(_ status: String, _ prefix: String) {
        let app = launchVolunteer(seed: status)
        let page = anyOf(app, ["volunteerOrderFlowStatusCard", "volunteerRunningStatsCard", "volunteerIntroCallHeader"])
        if !page.waitForExistence(timeout: 20) {
            // 回落：从首页「当前订单」卡点进去。
            let card = app.staticTexts["当前订单"].firstMatch
            if card.waitForExistence(timeout: 5) { card.tap() }
        }
        shoot(app, "\(prefix)-volunteer-\(status)", anchor: page, scroll: true)
    }

    // MARK: - 启动

    @MainActor private func launchBlind(
        emptyOrders: Bool = true,
        seed: String? = nil,
        env: [String: String] = [:]
    ) -> XCUIApplication {
        var base = ["AIDRUN_UI_TEST_PRESEEDED_BLIND_PROFILE": "1"]
        if emptyOrders { base["AIDRUN_UI_TEST_EMPTY_MOCK_ORDERS"] = "1" }
        if let seed { base["AIDRUN_UI_TEST_SEED_ORDER_STATUS"] = seed }
        return launch(role: "blind_runner", token: "mock_jwt_token_for_testing", env: base.merging(env) { _, new in new })
    }

    @MainActor private func launchVolunteer(
        available: Bool = true,
        seed: String? = nil,
        env: [String: String] = [:]
    ) -> XCUIApplication {
        var base = ["AIDRUN_UI_TEST_PRESEEDED_VOLUNTEER_PROFILE": "1"]
        if available { base["AIDRUN_UI_TEST_PRESEEDED_VOLUNTEER_AVAILABLE"] = "1" }
        if let seed {
            base["AIDRUN_UI_TEST_PRESEEDED_VOLUNTEER_ACTIVE_ORDER"] = "1"
            base["AIDRUN_UI_TEST_SEED_ORDER_STATUS"] = seed
        }
        return launch(role: "volunteer", token: "mock_jwt_token_for_testing", env: base.merging(env) { _, new in new })
    }

    @MainActor private func launch(role: String?, token: String?, env: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        addTeardownBlock { await MainActor.run { app.terminate() } }
        var base = [
            "AIDRUN_UI_TEST_RESET_STATE": "1",
            "AIDRUN_UI_TEST_RESET_TOKEN": UUID().uuidString,
            "AIDRUN_UI_TEST_BLOCK_TEL_DIAL": "1",
            "AIDRUN_UI_TEST_FORCE_DEMO_LOCATION": "1",
            "AIDRUN_UI_TEST_API_ENV": "mock",
            "AIDRUN_UI_TEST_PREFILL_PROFILE_FORM": "1",
            "AIDRUN_UI_TEST_DISABLE_WEBSOCKET": "1",
            "AIDRUN_UI_TEST_DISABLE_MAP": "1",
        ]
        if let role { base["AIDRUN_UI_TEST_ACTIVE_ROLE"] = role }
        if let token { base["AIDRUN_UI_TEST_ACCESS_TOKEN"] = token }
        // "0" 表示这条用例要真地图：从环境里拿掉开关，而不是传一个 App 不认识的值。
        for (key, value) in env where value == "0" { base.removeValue(forKey: key) }
        for (key, value) in env where value != "0" { base[key] = value }
        app.launchEnvironment = base
        app.launch()
        dismissSystemAlerts()
        return app
    }

    // MARK: - 小工具

    /// 系统权限弹窗属于 SpringBoard，不在 App 的树里。只点「允许」一类按钮，不碰 App 本身。
    @MainActor private func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<3 {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: 2) else { return }
            let allow = ["允许", "使用App时允许", "好", "OK", "Allow", "Allow While Using App"]
                .map { alert.buttons[$0] }
                .first { $0.exists }
            guard let allow else { return }
            allow.tap()
        }
    }

    @MainActor private func anyOf(_ app: XCUIApplication, _ identifiers: [String]) -> XCUIElement {
        let predicate = NSPredicate(format: "identifier IN %@", identifiers)
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    @MainActor private func tapIfAppears(_ app: XCUIApplication, _ identifier: String, timeout: TimeInterval = 20) -> Bool {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        guard element.waitForExistence(timeout: timeout) else { return false }
        element.tap()
        return true
    }

    /// iPad（iPadOS 18 起）的标签栏不是 `TabBar` —— 退回按名字找按钮。
    @MainActor private func tapTab(_ app: XCUIApplication, _ title: String) {
        let bar = app.tabBars.firstMatch
        let button = bar.waitForExistence(timeout: 20) ? bar.buttons[title] : app.buttons[title].firstMatch
        if button.waitForExistence(timeout: 5) {
            button.tap()
        } else {
            XCTFail("标签「\(title)」不在")
        }
    }

    @MainActor private func shoot(_ app: XCUIApplication, _ name: String, anchor identifier: String, scroll: Bool = false) {
        shoot(app, name, anchor: app.descendants(matching: .any)[identifier].firstMatch, scroll: scroll)
    }

    /// 等锚点出现再截。锚点没出现照样截（名字带 `MISSING`）并记一条失败。
    /// `scroll` 为真时再上划两次截一张 `-bottom`：SwiftUI 不渲染屏外的行，首屏图看不到下半页。
    @MainActor private func shoot(_ app: XCUIApplication, _ name: String, anchor: XCUIElement?, scroll: Bool = false) {
        var label = name
        if let anchor, !anchor.waitForExistence(timeout: 20) {
            label += "-MISSING"
            XCTFail("\(name)：锚点没出现，截到的是当时的屏幕")
        }
        sleep(1) // 等转场动画落定，免得截到半透明的中间帧
        attach(app, label)
        guard scroll else { return }
        let scrollable = app.scrollViews.firstMatch.exists ? app.scrollViews.firstMatch
            : app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch
            : app.tables.firstMatch
        guard scrollable.exists else { return }
        scrollable.swipeUp()
        scrollable.swipeUp()
        sleep(1)
        attach(app, label + "-bottom")
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
