import XCTest

extension XCUIApplication {
    /// 「我的」→ 头像卡 → 账户页。#711 起盲人端的个人资料、实名认证、隐私与授权、已拉黑的人、退出登录、删除账户都在这一页。
    /// 调用前要已经在盲人端「我的」上。
    func openBlindAccountPage(file: StaticString = #filePath, line: UInt = #line) {
        let card = buttons["blindAccountCardEntry"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "「我的」没有头像卡", file: file, line: line)
        card.tap()
        XCTAssertTrue(
            descendants(matching: .any)["blindAccountView"].firstMatch.waitForExistence(timeout: 10),
            "点头像卡没进到账户页",
            file: file,
            line: line
        )
    }
}

extension blindRunUITests {
    /// 「我的」tab → 头像卡 → 账户页（盲人端，#711）。单独成文件：`blindRunUITests.swift` 已超长。
    func openBlindAccount(_ app: XCUIApplication) {
        openSettings(app)
        app.openBlindAccountPage()
    }
}

/// 盲人端「我的」与账户页（#711，定稿 `docs/ui/mockups/blind-profile-20261105/`）：
/// 入口一个不少、没有紧急呼叫行、方块念名称和按钮、64pt、AX5 单列、整页审计。盲人端要测最大字号。
private let blindSettingsVariants: [(name: String, environment: [String: String], arguments: [String])] = [
    ("light", ["AIDRUN_UI_TEST_COLOR_SCHEME": "light"], []),
    ("dark", ["AIDRUN_UI_TEST_COLOR_SCHEME": "dark"], []),
    ("ax5-light", ["AIDRUN_UI_TEST_COLOR_SCHEME": "light"],
     ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
]

/// 方块的标识与读屏名称，顺序同屏幕。
private let blindSettingsTiles: [(identifier: String, label: String)] = [
    ("blindFavoriteVolunteersSettingsEntry", "固定搭档"),
    ("blindInviteCodeSettingsEntry", "邀请好友"),
    ("blindRunnerSettingsHelpLink", "使用帮助"),
    ("supportTicketSettingsEntry", "联系客服")
]

extension AccessibilityAuditTests {

    @MainActor
    func testBlindSettingsTabAndAccountPageKeepEveryEntryAndPassAudit() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .portrait
        for variant in blindSettingsVariants {
            let app = launchBlindHome(extraEnvironment: variant.environment, extraArguments: variant.arguments)
            let tabBar = app.tabBars.firstMatch
            XCTAssertTrue(tabBar.waitForExistence(timeout: 25), "\(variant.name)：标签栏没起来")
            tabBar.buttons["我的"].tap()
            XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 10), "\(variant.name)：没进到「我的」")

            let largestText = !variant.arguments.isEmpty
            try checkBlindSettingsTop(app, variant: variant.name, largestText: largestText)
            try checkBlindSettingsTiles(app, variant: variant.name, largestText: largestText)
            try checkBlindSettingsList(app, variant: variant.name)
            for _ in 0..<10 { app.swipeDown() }
            try checkBlindAccountPage(app, variant: variant.name)
            app.terminate()
        }
    }

    /// 顶部：头像卡；没有紧急呼叫行（负责人 2026-11-05，#711）；默认字号下第一排方块不滚动就点得到。
    @available(iOS 17.0, *)
    @MainActor
    private func checkBlindSettingsTop(_ app: XCUIApplication, variant: String, largestText: Bool) throws {
        let card = app.buttons["blindAccountCardEntry"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "\(variant)：没有头像卡")
        XCTAssertTrue(card.label.hasSuffix("个人资料、实名与账户"), card.label)
        XCTAssertGreaterThanOrEqual(card.frame.height, 63.5, "头像卡可点高度不足 64pt：\(card.frame)")
        XCTAssertFalse(
            app.descendants(matching: .any)["blindProfileEmergencyRow"].firstMatch.exists,
            "\(variant)：「我的」不放紧急呼叫行"
        )
        if !largestText {
            let partners = app.buttons[blindSettingsTiles[0].identifier].firstMatch
            XCTAssertTrue(partners.exists && partners.isHittable, "\(variant)：默认字号下第一排方块要不滚动就点得到")
            XCTAssertGreaterThan(partners.frame.minY, card.frame.maxY - 1, "\(variant)：方块要在头像卡下面")
        }
        assertLargeTitleIsDrawn(app, title: "我的", variant: variant)
        attachScreenshot(app, name: "blind-settings-\(variant)-top")
        try audit(app)
    }

    /// 方块：按钮，读屏只念名称，64pt 以上；默认字号两列，AX5 单列。
    @available(iOS 17.0, *)
    @MainActor
    private func checkBlindSettingsTiles(_ app: XCUIApplication, variant: String, largestText: Bool) throws {
        for tile in blindSettingsTiles {
            let button = app.buttons[tile.identifier].firstMatch
            for _ in 0..<8 where !(button.exists && button.isHittable) { app.swipeUp() }
            XCTAssertTrue(button.exists, "\(variant)：没有「\(tile.label)」方块")
            XCTAssertEqual(button.label, tile.label, "方块读屏只念名称")
            XCTAssertGreaterThanOrEqual(button.frame.height, 63.5, "\(tile.label) 方块可点高度不足 64pt：\(button.frame)")
        }
        // 两块的位置要在同一个滚动位置读：上面逐块滚动时各自记下的 frame 不可比（AX5 单列时中间可能又滑过一次）。
        let partners = app.buttons[blindSettingsTiles[0].identifier].firstMatch.frame
        let invite = app.buttons[blindSettingsTiles[1].identifier].firstMatch.frame
        if largestText {
            XCTAssertEqual(partners.minX, invite.minX, accuracy: 1, "\(variant)：AX5 下方块要单列：\(partners) / \(invite)")
            XCTAssertGreaterThan(invite.minY, partners.maxY - 1, "\(variant)：AX5 下邀请好友要在固定搭档下面")
        } else {
            XCTAssertEqual(partners.minY, invite.minY, accuracy: 1, "\(variant)：默认字号下方块两列：\(partners) / \(invite)")
            XCTAssertGreaterThan(invite.minX, partners.maxX - 1, "\(variant)：邀请好友要在固定搭档右边")
        }
        if largestText {
            attachScreenshot(app, name: "blind-settings-\(variant)-tiles")
            try audit(app, contentScrolledUnderNavigationBar: true)
        }
    }

    /// 列表：我的工单、通知、关于。行高 64pt。
    @available(iOS 17.0, *)
    @MainActor
    private func checkBlindSettingsList(_ app: XCUIApplication, variant: String) throws {
        let tickets = app.buttons["mySupportTicketsSettingsEntry"].firstMatch
        let about = app.buttons["关于"].firstMatch
        let notification = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "通知：")).firstMatch
        for _ in 0..<10 where !(about.exists && about.isHittable) { app.swipeUp() }
        for entry in [tickets, notification, about] {
            XCTAssertTrue(entry.exists, "\(variant)：「我的」列表缺一项：\(entry)")
        }
        for row in [tickets, about] {
            XCTAssertGreaterThanOrEqual(row.frame.height, 63.5, "\(variant)：列表行可点高度不足 64pt：\(row)")
        }
        attachScreenshot(app, name: "blind-settings-\(variant)-bottom")
        // 上推之后「类别」和方块滚到了导航栏的模糊区里，看不见（同陪跑员版 #700）。
        try audit(app, contentScrolledUnderNavigationBar: true)
    }

    /// 账户页：个人资料、实名认证、隐私与授权、已拉黑的人、退出登录、删除账户；标签栏藏起来。
    @available(iOS 17.0, *)
    @MainActor
    private func checkBlindAccountPage(_ app: XCUIApplication, variant: String) throws {
        app.openBlindAccountPage()
        let identity = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "实名认证，当前状态")).firstMatch
        let delete = app.buttons["删除账户"].firstMatch
        let accountEntries = [
            app.buttons["个人资料"].firstMatch,
            identity,
            app.buttons["blindPrivacyAuthorizationSettingsEntry"].firstMatch,
            app.buttons["blockedUsersSettingsEntry"].firstMatch,
            app.buttons["退出登录"].firstMatch,
            delete
        ]
        XCTAssertFalse(app.tabBars.firstMatch.exists, "账户页要藏标签栏，免得盖住最后一行")
        attachScreenshot(app, name: "blind-account-\(variant)-top")
        try audit(app)
        for _ in 0..<10 where !(delete.exists && delete.isHittable) { app.swipeUp() }
        for entry in accountEntries {
            XCTAssertTrue(entry.exists, "\(variant)：账户页缺一项：\(entry)")
        }
        XCTAssertGreaterThanOrEqual(delete.frame.height, 63.5, "删除账户可点高度不足 64pt：\(delete.frame)")
        attachScreenshot(app, name: "blind-account-\(variant)-bottom")
        try audit(app, contentScrolledUnderNavigationBar: true)
    }

    /// 大标题不光要在无障碍树里，还要真的画在屏上：截图里标题那一块要有和底色不同的像素。
    /// 只断言导航栏存在会假绿 —— #700 / #711 的导航栏实底把大标题整个盖住，树里照样有「我的」（2026-11-05 真机）。
    @MainActor
    private func assertLargeTitleIsDrawn(_ app: XCUIApplication, title: String, variant: String) {
        let label = app.navigationBars[title].staticTexts[title].firstMatch
        XCTAssertTrue(label.waitForExistence(timeout: 5), "\(variant)：导航栏里没有标题「\(title)」")
        let frame = label.frame
        let image = app.screenshot().image
        guard let cgImage = image.cgImage, !frame.isEmpty else {
            XCTFail("\(variant)：拿不到截图或标题位置：\(frame)")
            return
        }
        let scale = CGFloat(cgImage.width) / app.frame.width
        let rect = CGRect(x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale, height: frame.height * scale).integral
        guard let crop = cgImage.cropping(to: rect) else {
            XCTFail("\(variant)：标题位置超出截图：\(frame)")
            return
        }
        XCTAssertGreaterThan(Self.distinctInkPixels(in: crop), 50, "\(variant)：标题「\(title)」在 \(frame) 没有画出来（只有底色）")
    }

    /// 和左上角像素（当作底色）的 RGB 差之和超过 120 的像素数。
    private static func distinctInkPixels(in image: CGImage) -> Int {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let base = (Int(pixels[0]), Int(pixels[1]), Int(pixels[2]))
        var count = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let diff = abs(Int(pixels[index]) - base.0) + abs(Int(pixels[index + 1]) - base.1) + abs(Int(pixels[index + 2]) - base.2)
            if diff > 120 { count += 1 }
        }
        return count
    }
}
