import XCTest

/// 「关于」页（`AboutAidRunView`）的备案公示（#620）。两端共用这一页，所以两端各走一遍入口。
extension AccessibilityAuditTests {
    /// 最大字号下「关于」页的屏数上限，超过就当滚动失败，不无限滑。
    private static let aboutPageMaxScreens = 8

    @MainActor
    private func openAboutPage(_ app: XCUIApplication) -> XCUIElement {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 25), "标签栏没起来")
        tabBar.buttons["我的"].tap()

        let entry = app.buttons["关于"].firstMatch
        // 只滑到「整行露在标签栏上方」：贴着底部点会落到常驻栏上。
        let tabBarTop = tabBar.frame.minY
        for _ in 0..<12 where !(entry.exists && entry.frame.maxY < tabBarTop - 120) {
            app.swipeUp()
        }
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "设置页没有「关于」入口")
        entry.tap()

        let number = app.descendants(matching: .any)["aboutAppFilingNumber"].firstMatch
        XCTAssertTrue(number.waitForExistence(timeout: 10), "「关于」页没有备案编号")
        return number
    }

    @MainActor
    func testAboutPageShowsFilingDisclosureOnBothSides() throws {
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .portrait
        for (role, launch) in [("blind", { self.launchBlindHome() }), ("volunteer", { self.launchVolunteerHome() })] {
            let app = launch()
            let number = openAboutPage(app)

            XCTAssertEqual(number.label, "App 备案编号：粤ICP备20047259号-4A", "\(role)：读屏没有念完整编号")

            let link = app.descendants(matching: .any)["aboutFilingQueryLink"].firstMatch
            XCTAssertTrue(link.exists, "\(role)：没有备案查询链接")
            XCTAssertEqual(link.elementType, .link, "\(role)：备案查询不是读屏可激活的链接")
            XCTAssertEqual(link.label, "工信部备案查询网站 beian.miit.gov.cn", "\(role)：链接读屏标签不对")
            XCTAssertGreaterThanOrEqual(link.frame.minY, number.frame.maxY - 0.5, "\(role)：网址要在编号下方")
            // 63.5 而不是 64：真机浮点噪声，口径同 `testPrivacyAuthorizationRevokeButtonsAreTallAndSayWhatTheyRevoke`。
            XCTAssertGreaterThanOrEqual(link.frame.height, 63.5, "\(role)：链接可点高度不足 64pt：\(link.frame)")

            let any = app.descendants(matching: .any)
            XCTAssertEqual(any["aboutAppName"].firstMatch.label, "助盲跑", "\(role)：App 名称不对")
            XCTAssertTrue(any["aboutAppVersion"].firstMatch.label.hasPrefix("版本 "), "\(role)：没有版本号")
            XCTAssertFalse(app.staticTexts["助盲跑 MVP"].exists, "\(role)：MVP 字样还在")
            XCTAssertFalse(app.staticTexts["iOS SwiftUI Demo"].exists, "\(role)：Demo 字样还在")

            let modelName = any["aboutVoiceOrderModelName"].firstMatch
            XCTAssertTrue(modelName.exists, "\(role)：没有公示大模型名称")
            XCTAssertEqual(modelName.label, "语音下单使用的大模型：通义千问大模型", "\(role)：模型名称读屏不对")
            let modelNumber = any["aboutVoiceOrderModelFilingNumber"].firstMatch
            XCTAssertTrue(modelNumber.exists, "\(role)：没有公示大模型备案号")
            XCTAssertEqual(modelNumber.label, "大模型备案号：ZheJiang-TongYiQianWen-20230901", "\(role)：模型备案号读屏不对")

            attachScreenshot(app, name: "about-filing-\(role)")
            app.terminate()
        }
    }

    @MainActor
    func testAboutFilingLinkOpensTheSystemBrowser() throws {
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .portrait
        let app = launchBlindHome()
        _ = openAboutPage(app)

        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        addTeardownBlock { await MainActor.run { safari.terminate() } }
        safari.terminate()
        app.activate()

        let link = app.descendants(matching: .any)["aboutFilingQueryLink"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5), "没有备案查询链接")
        link.tap()
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 15), "点链接后系统浏览器没有打开")

        // 给页面留时间加载，截图用来看是不是工信部查询页。
        sleep(6)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "about-filing-link-safari"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testAboutPagePassesAuditInLightDarkAndLargestText() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .portrait
        for variant in Self.appearanceVariants {
            let app = launchBlindHome(extraEnvironment: variant.environment, extraArguments: variant.arguments)
            let number = openAboutPage(app)
            waitUntilSettled(number)

            attachScreenshot(app, name: "about-filing-audit-\(variant.name)-0")
            try audit(app)

            // 滑到底才能确认最后一行露在求助条上方（盲人端的求助条不让开二级页内容，#620 踩过）。
            // 这里不再审计：`.dynamicType` 那遍会把页面滚回顶部，边滑边审永远到不了底。
            let lastRow = app.descendants(matching: .any)["用户协议"].firstMatch
            let sosBar = app.descendants(matching: .any)["blindTabBottomSOSBar"].firstMatch
            func isLastRowVisible() -> Bool {
                let bottomLimit = sosBar.exists ? sosBar.frame.minY : app.tabBars.firstMatch.frame.minY
                return lastRow.exists && lastRow.frame.maxY <= bottomLimit
            }
            var screen = 0
            while !isLastRowVisible() {
                screen += 1
                guard screen < Self.aboutPageMaxScreens else {
                    return XCTFail("\(variant.name)：滑了 \(screen) 屏，「用户协议」仍被盖住")
                }
                app.swipeUp()
                sleep(1)
                attachScreenshot(app, name: "about-filing-audit-\(variant.name)-\(screen)")
            }
            app.terminate()
        }
    }
}
