import XCTest

extension XCUIApplication {
    /// 「我的」→ 头像卡 → 账户页。#700 起陪跑员的个人资料、隐私与授权、已拉黑的人、退出登录、删除账户都在这一页。
    /// 调用前要已经在陪跑员「我的」上。
    func openVolunteerAccountPage(file: StaticString = #filePath, line: UInt = #line) {
        let card = buttons["volunteerAccountCardEntry"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "「我的」没有头像卡", file: file, line: line)
        card.tap()
        XCTAssertTrue(
            descendants(matching: .any)["volunteerAccountView"].firstMatch.waitForExistence(timeout: 10),
            "点头像卡没进到账户页",
            file: file,
            line: line
        )
    }
}

/// 陪跑员「我的」与账户页（#700，定稿 `docs/ui/mockups/volunteer-settings-20261104/`）：入口一个不少、方块念名称和按钮、整页审计。
///
/// 陪跑员端只测默认字号的亮 / 暗两遍（负责人 2026-11-05 定）。AX3 起改单列由单测 `VolunteerSettingsTileTests` 守。
private let settingsVariants: [(name: String, environment: [String: String])] = [
    ("light", ["AIDRUN_UI_TEST_COLOR_SCHEME": "light"]),
    ("dark", ["AIDRUN_UI_TEST_COLOR_SCHEME": "dark"])
]

/// 方块的标识与读屏名称，顺序同屏幕。
private let settingsTiles: [(identifier: String, label: String)] = [
    ("volunteerTrainingSettingsEntry", "陪跑培训"),
    ("volunteerScheduleSettingsEntry", "空闲时间"),
    ("volunteerCertificateSettingsEntry", "资质证书"),
    ("volunteerPartnersSettingsEntry", "固定搭档"),
    ("volunteerPointsSettingsEntry", "我的积分"),
    ("volunteerInviteCodeSettingsEntry", "邀请好友")
]

extension AccessibilityAuditTests {

    @MainActor
    func testVolunteerSettingsTabAndAccountPageKeepEveryEntryAndPassAudit() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        for variant in settingsVariants {
            let app = launchVolunteerHome(extraEnvironment: variant.environment)
            let tabBar = app.tabBars.firstMatch
            XCTAssertTrue(tabBar.waitForExistence(timeout: 25), "\(variant.name)：标签栏没起来")
            tabBar.buttons["我的"].tap()
            XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 10), "\(variant.name)：没进到「我的」")

            // 第一屏：头像卡 + 六个方块。方块是按钮，读屏标签只是名称（资质证书的审核状态在值里）。
            let card = app.buttons["volunteerAccountCardEntry"].firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 10), "\(variant.name)：没有头像卡")
            XCTAssertTrue(card.label.hasSuffix("个人资料、实名与账户"), card.label)
            XCTAssertGreaterThanOrEqual(card.frame.height, 63.5, "头像卡可点高度不足 64pt：\(card.frame)")
            for tile in settingsTiles {
                let button = app.buttons[tile.identifier].firstMatch
                XCTAssertTrue(button.exists, "\(variant.name)：第一屏没有「\(tile.label)」方块")
                XCTAssertEqual(button.label, tile.label, "方块读屏只念名称")
                XCTAssertTrue(button.isHittable, "\(variant.name)：「\(tile.label)」方块点不到")
            }
            sleep(1) // 服务成就那一行是异步加载的，等它落定再截图
            attachScreenshot(app, name: "volunteer-settings-\(variant.name)-top")
            try audit(app)

            // 列表：服务成就（第一行）、联系客服、我的工单、通知、使用帮助、关于。
            let listEntries = [
                app.buttons["volunteerProfileAchievementsCard"].firstMatch,
                app.buttons["supportTicketSettingsEntry"].firstMatch,
                app.buttons["mySupportTicketsSettingsEntry"].firstMatch,
                app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "通知：")).firstMatch,
                app.buttons["volunteerSettingsHelpLink"].firstMatch,
                app.buttons["关于"].firstMatch
            ]
            let about = app.buttons["关于"].firstMatch
            for _ in 0..<6 where !(about.exists && about.isHittable) { app.swipeUp() }
            for entry in listEntries {
                XCTAssertTrue(entry.exists, "\(variant.name)：「我的」列表缺一项：\(entry)")
            }
            XCTAssertTrue(
                listEntries[0].label.hasPrefix("服务成就"),
                "列表第一行是服务成就：\(listEntries[0].label)"
            )
            attachScreenshot(app, name: "volunteer-settings-\(variant.name)-bottom")
            try audit(app)

            for _ in 0..<6 { app.swipeDown() }
            app.openVolunteerAccountPage()
            let accountEntries = [
                app.buttons["个人资料"].firstMatch,
                app.descendants(matching: .any)["volunteerAccountCertificateRow"].firstMatch,
                app.buttons["volunteerPrivacyAuthorizationSettingsEntry"].firstMatch,
                app.buttons["blockedUsersSettingsEntry"].firstMatch,
                app.buttons["退出登录"].firstMatch,
                app.buttons["删除账户"].firstMatch
            ]
            for entry in accountEntries {
                XCTAssertTrue(entry.waitForExistence(timeout: 5), "\(variant.name)：账户页缺一项：\(entry)")
            }
            XCTAssertFalse(tabBar.exists, "账户页要藏标签栏，免得盖住最后一行")
            attachScreenshot(app, name: "volunteer-account-\(variant.name)")
            try audit(app)
            app.terminate()
        }
    }
}
