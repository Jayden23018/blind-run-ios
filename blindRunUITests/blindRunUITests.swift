//
//  blindRunUITests.swift
//  blindRunUITests
//
//  Created by Jerry on 5/18/26.
//

import XCTest

final class blindRunUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    private var isPhysicalDevice: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        true
        #endif
    }

    var shouldRunRealAMapSmoke: Bool {
        ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_REAL_AMAP"] == "1" || isPhysicalDevice
    }

    var shouldRunCloudSmoke: Bool {
        ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_RUN_CLOUD_SMOKE"] == "1" || isPhysicalDevice
    }

    func launchApp(
        apiEnvironment: String,
        accessToken: String? = nil,
        activeRole: String? = "blind_runner",
        preseedBlindProfile: Bool = false,
        preseedVolunteerProfile: Bool = false,
        preseedVolunteerAvailable: Bool = false,
        preseedVolunteerActiveOrder: Bool = false,
        /// 直接把预置订单落在某个状态上（`AIDRUN_UI_TEST_SEED_ORDER_STATUS`），
        /// 免得为了验一个 `IN_PROGRESS` 的行为先走完出发 / 到达 / 开始三步。
        /// 走那三步的用例会连带吃掉沿途每一条断言的红灯，验的东西就不是自己那一条了。
        seedOrderStatus: String? = nil,
        /// 预置几条待回复邀请（`AIDRUN_UI_TEST_SEED_INVITES`）。派单只从 WebSocket 来，
        /// 而这里默认 `disableWebSocket` —— 没有这个种子，邀请卡在 UI 测试里根本到不了。
        seedInvites: Int? = nil,
        /// 种子订单的 `earliestDepartureAt` = 现在 + 这么多分钟（`AIDRUN_UI_TEST_SEED_EARLIEST_DEPARTURE_MINUTES`，#340）。
        seedEarliestDepartureMinutes: Int? = nil,
        forceRealVolunteerRegistration: Bool = false,
        unregisteredVolunteer: Bool = false,
        legacyTrainingStatusAfterFaceVerify: Bool = false,
        emptyMockOrders: Bool = false,
        /// 默认开跑时间固定成北京时间明天 10:00（`AIDRUN_UI_TEST_DAYTIME_APPOINTMENT`）。
        /// 「现在 + 31 分钟」在晚上跑会撞夜间窗口，要提交预约的用例都该打开（#418）。
        daytimeAppointment: Bool = false,
        disableMap: Bool = true,
        disableWebSocket: Bool = true,
        mockLogoutFailure: Bool = false,
        /// 退出登录 / 删除账户请求先等这么多秒（`AIDRUN_UI_TEST_SLOW_SESSION_END_SECONDS`），让进度遮罩停得住。
        slowSessionEndSeconds: Int? = nil,
        realtimePriorityTest: Bool = false,
        hangHomeRequests: Bool = false,
        hangTransitionConfirmation: Bool = false,
        confirmTransitionViaRealtime: Bool = false,
        hangEscortLocationSend: Bool = false,
        homeLoadTimeout: TimeInterval? = nil,
        forcePrivacyConsent: Bool = false,
        contentSizeCategory: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        addTeardownBlock {
            await MainActor.run { app.terminate() }
        }
        app.launchEnvironment["AIDRUN_UI_TEST_RESET_STATE"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_RESET_TOKEN"] = UUID().uuidString
        // 误触求助条 = 真的拨 110（2026-08-14 差一层双卡选号单就拨出去了）。
        // DEBUG 构建里这个开关让 `EmergencyDialer.dial` 只记一次痕迹、不真的拨号。
        // 别的启动 helper 不必重复这一行：没显式设时 `EmergencyDialer.resolveDialBlock`
        // 认 `AIDRUN_UI_TEST_RESET_STATE` 就默认拦。
        app.launchEnvironment["AIDRUN_UI_TEST_BLOCK_TEL_DIAL"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_FORCE_DEMO_LOCATION"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_API_ENV"] = apiEnvironment
        if let activeRole {
            app.launchEnvironment["AIDRUN_UI_TEST_ACTIVE_ROLE"] = activeRole
        }
        app.launchEnvironment["AIDRUN_UI_TEST_PREFILL_PROFILE_FORM"] = "1"
        if disableWebSocket {
            app.launchEnvironment["AIDRUN_UI_TEST_DISABLE_WEBSOCKET"] = "1"
        }
        if disableMap {
            app.launchEnvironment["AIDRUN_UI_TEST_DISABLE_MAP"] = "1"
        }
        if realtimePriorityTest {
            app.launchEnvironment["AIDRUN_UI_TEST_REALTIME_PRIORITY"] = "1"
        }
        if hangHomeRequests {
            app.launchEnvironment["AIDRUN_UI_TEST_HANG_HOME_REQUESTS"] = "1"
        }
        if hangTransitionConfirmation {
            app.launchEnvironment["AIDRUN_UI_TEST_HANG_TRANSITION_CONFIRMATION"] = "1"
        }
        if confirmTransitionViaRealtime {
            app.launchEnvironment["AIDRUN_UI_TEST_CONFIRM_TRANSITION_VIA_REALTIME"] = "1"
        }
        if hangEscortLocationSend {
            app.launchEnvironment["AIDRUN_UI_TEST_HANG_ESCORT_SEND"] = "1"
        }
        if let homeLoadTimeout {
            app.launchEnvironment["AIDRUN_UI_TEST_HOME_LOAD_TIMEOUT"] = String(homeLoadTimeout)
        }
        if let accessToken {
            app.launchEnvironment["AIDRUN_UI_TEST_ACCESS_TOKEN"] = accessToken
        }
        if preseedBlindProfile {
            app.launchEnvironment["AIDRUN_UI_TEST_PRESEEDED_BLIND_PROFILE"] = "1"
        }
        if preseedVolunteerProfile {
            app.launchEnvironment["AIDRUN_UI_TEST_PRESEEDED_VOLUNTEER_PROFILE"] = "1"
        }
        if preseedVolunteerAvailable {
            app.launchEnvironment["AIDRUN_UI_TEST_PRESEEDED_VOLUNTEER_AVAILABLE"] = "1"
        }
        if let seedInvites {
            app.launchEnvironment["AIDRUN_UI_TEST_SEED_INVITES"] = String(seedInvites)
        }
        if preseedVolunteerActiveOrder {
            app.launchEnvironment["AIDRUN_UI_TEST_PRESEEDED_VOLUNTEER_ACTIVE_ORDER"] = "1"
        }
        if let seedOrderStatus {
            app.launchEnvironment["AIDRUN_UI_TEST_SEED_ORDER_STATUS"] = seedOrderStatus
        }
        if let seedEarliestDepartureMinutes {
            app.launchEnvironment["AIDRUN_UI_TEST_SEED_EARLIEST_DEPARTURE_MINUTES"] = String(seedEarliestDepartureMinutes)
        }
        if forceRealVolunteerRegistration {
            app.launchEnvironment["AIDRUN_UI_TEST_FORCE_REAL_REGISTRATION"] = "1"
        }
        if unregisteredVolunteer {
            app.launchEnvironment["AIDRUN_UI_TEST_UNREGISTERED_VOLUNTEER"] = "1"
        }
        if legacyTrainingStatusAfterFaceVerify {
            app.launchEnvironment["AIDRUN_UI_TEST_LEGACY_TRAINING_STATUS"] = "1"
        }
        if emptyMockOrders {
            app.launchEnvironment["AIDRUN_UI_TEST_EMPTY_MOCK_ORDERS"] = "1"
        }
        if daytimeAppointment {
            app.launchEnvironment["AIDRUN_UI_TEST_DAYTIME_APPOINTMENT"] = "1"
        }
        if mockLogoutFailure {
            app.launchEnvironment["AIDRUN_MOCK_LOGOUT_FAILURE"] = "1"
        }
        if let slowSessionEndSeconds {
            app.launchEnvironment["AIDRUN_UI_TEST_SLOW_SESSION_END_SECONDS"] = String(slowSessionEndSeconds)
        }
        // 同意门默认跳过（判定在 `AppState.resolveInitialPrivacyConsent`）：UI 用例一律
        // `RESET_STATE`，不跳过的话每一条都会被挡在告知页，断言全红。只有专测它的用例打开这一条。
        if forcePrivacyConsent {
            app.launchEnvironment["AIDRUN_UI_TEST_FORCE_PRIVACY_CONSENT"] = "1"
        }
        if let contentSizeCategory {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSizeCategory]
        }
        app.launch()
        dismissSystemAlertsIfPresent(app: app)
        return app
    }

    /// 打开设置。**两端通用** —— 陪跑员端 2026-09-17 也有了标签栏（设计交付 v3 §4.1），
    /// 两边的第三个标签都叫「我的」，根页标题也叫「我的」（2026-10-05 起顶上多一张个人卡）；陪跑员首页齿轮进去的那一页仍叫「设置」。
    ///
    /// 🔄 **2026-09-16 起走「我的」tab，不再是首页右上角的悬浮齿轮。**
    /// 盲人端的齿轮已随首页改版删除（设计稿的首页只有问候 + 订单卡 + 预约块）；
    /// 陪跑员首屏那枚齿轮还在，但这里一律走标签栏那条 —— 它是两端唯一都有的入口。
    /// 抽成 helper 的价值就在这里：入口换了一次，所有调用点一起跟上。
    /// 每处先 `.exists` 再 `waitForExistence`：后者即使元素早已在树里，首次判定也要约 1 秒
    /// （真机 result bundle 时间线实测 1.0–1.1s）。本函数和 `assertLogoutRequiresConfirmation`
    /// 被多条用例共用，每次调用都付这笔底价。元素真不在时照样走满超时，失败判据不变。
    func openSettings(_ app: XCUIApplication) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.exists || tabBar.waitForExistence(timeout: 12), "标签栏没起来，够不到设置")
        let profileTab = tabBar.buttons["我的"]
        XCTAssertTrue(profileTab.exists || profileTab.waitForExistence(timeout: 5), "标签栏缺少「我的」")
        profileTab.tap()
        let settingsBar = app.navigationBars["我的"]
        XCTAssertTrue(
            settingsBar.exists || settingsBar.waitForExistence(timeout: 10),
            "「我的」tab 里没有设置页"
        )
    }

}
