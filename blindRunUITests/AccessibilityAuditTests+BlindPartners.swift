import XCTest

/// 盲人端「固定搭档」列表与搭档详情页（#752，定稿 `docs/ui/mockups/blind-partners-20261105/`）。
///
/// Mock 的四行（收藏时间倒序，再接只有连续记录的）：
/// 0 = 李*（没点亮、一起跑完 3 次）、1 = 张*（连续 3 周 / 最好 7 周、12 次）、
/// 2 = 王*（对方已退出）、3 = 王*（只一起跑过，连续 2 周）。按标识找行，不按名字（两个王*）。
private let blindPartnersVariants: [(name: String, environment: [String: String], arguments: [String])] = [
    ("light", ["AIDRUN_UI_TEST_COLOR_SCHEME": "light"], []),
    ("dark", ["AIDRUN_UI_TEST_COLOR_SCHEME": "dark"], []),
    ("ax5-light", ["AIDRUN_UI_TEST_COLOR_SCHEME": "light"],
     ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]),
    ("ax5-dark", ["AIDRUN_UI_TEST_COLOR_SCHEME": "dark"],
     ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
]

extension AccessibilityAuditTests {

    /// 列表只放人（没有任何操作按钮）、两组、64pt；详情页两种人各一页；四种外观整页审计。
    @MainActor
    func testBlindPartnersListAndDetailPassAuditInEveryAppearance() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .portrait
        for variant in blindPartnersVariants {
            let app = launchBlindHome(
                emptyOrders: false,
                extraEnvironment: variant.environment,
                extraArguments: variant.arguments
            )
            openBlindPartners(app, variant: variant.name)
            try checkBlindPartnersList(app, variant: variant.name)

            // 有连续记录的固定搭档：连续周数卡、一起跑完、举报 / 不再匹配、红字取消。
            openBlindPartnerRow(app, index: 1)
            try checkBlindPartnerDetail(app, variant: variant.name, isFavorite: true)
            app.navigationBars.buttons.firstMatch.tap()

            // 还不是固定搭档：64pt「设为固定搭档」，没有取消。
            openBlindPartnerRow(app, index: 3)
            try checkBlindPartnerDetail(app, variant: variant.name, isFavorite: false)
            app.terminate()
        }
    }

    /// 取消固定搭档每次都先确认（负责人 2026-11-05 定）。
    ///
    /// 改版前没退出过的搭档点了直接取消 —— 把 `BlindPartnerDetailView` 的确认绕掉（直接 `perform(false)`），
    /// 第二段「弹窗出现」那一句就红。已退出那一档要用长文案：换成短文案的话「不作数」那一句红。
    @MainActor
    func testBlindPartnerDetailConfirmsEveryRemoval() throws {
        let app = launchBlindHome(emptyOrders: false)
        openBlindPartners(app, variant: "default")

        // 已退出的王*：长文案。
        openBlindPartnerRow(app, index: 2)
        XCTAssertEqual(
            app.descendants(matching: .any)["blindPartnerDetailSubtitle"].firstMatch.label,
            "对方已退出固定搭档"
        )
        revealBlindPartnerButton(app, "blindRemoveFavoriteButton").tap()
        var alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "对方已退出时取消要先确认")
        XCTAssertTrue(
            alert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "不作数")).firstMatch.exists,
            "对方已退出时要警告会撤销他的退出"
        )
        alert.buttons["保留收藏"].tap()
        app.navigationBars.buttons.firstMatch.tap()

        // 没退出的李*：也要确认；点「保留固定搭档」什么都不发生。
        openBlindPartnerRow(app, index: 0)
        let remove = revealBlindPartnerButton(app, "blindRemoveFavoriteButton")
        XCTAssertGreaterThanOrEqual(remove.frame.height, 63.5, "取消固定搭档可点高度不足 64pt：\(remove.frame)")
        remove.tap()
        alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "没退出的搭档取消也要先确认")
        alert.buttons["保留固定搭档"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["blindPartnerDetailView"].firstMatch.waitForExistence(timeout: 3),
            "点「保留固定搭档」要留在详情页"
        )
        XCTAssertFalse(app.descendants(matching: .any)["blindFavoriteActionNotice"].firstMatch.exists)

        // 确认后回到列表，结果上屏。
        revealBlindPartnerButton(app, "blindRemoveFavoriteButton").tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["取消固定搭档"].tap()
        let notice = app.descendants(matching: .any)["blindFavoriteActionNotice"].firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 10), "取消后要回到列表并显示结果")
        XCTAssertTrue(notice.label.hasPrefix("已取消收藏李"), notice.label)
    }

    // MARK: - 步骤

    /// 「我的」→「固定搭档」方块。按读屏名找：方块的标识是计算出来的，守卫认不出。
    @MainActor
    func openBlindPartners(_ app: XCUIApplication, variant: String) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 25), "\(variant)：标签栏没起来")
        tabBar.buttons["我的"].tap()
        let entry = app.buttons["固定搭档"].firstMatch
        for _ in 0..<8 where !(entry.exists && entry.isHittable) { app.swipeUp() }
        entry.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["blindFavoriteHeroCard"].firstMatch.waitForExistence(timeout: 15),
            "\(variant)：固定搭档页没有顶部说明卡"
        )
    }

    @MainActor
    func openBlindPartnerRow(_ app: XCUIApplication, index: Int) {
        let row = app.buttons["blindPartnerRow.\(index)"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "没有第 \(index) 行")
        for _ in 0..<8 where !row.isHittable { app.swipeUp() }
        row.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["blindPartnerDetailView"].firstMatch.waitForExistence(timeout: 10),
            "点第 \(index) 行没进到详情页"
        )
    }

    @available(iOS 17.0, *)
    @MainActor
    private func checkBlindPartnersList(_ app: XCUIApplication, variant: String) throws {
        let hero = app.descendants(matching: .any)["blindFavoriteHeroCard"].firstMatch
        XCTAssertTrue(hero.label.contains("2 位固定搭档"), "\(variant)：只数没退出的：\(hero.label)")
        XCTAssertTrue(app.staticTexts["一起跑过的人"].exists, "\(variant)：没有「一起跑过的人」组")

        // 列表上不放任何操作（定稿：操作全在详情页）。
        for identifier in ["blindRemoveFavoriteButton", "blindAddFavoriteButton", "counterpartReportButton", "counterpartBlockButton"] {
            XCTAssertFalse(app.buttons[identifier].firstMatch.exists, "\(variant)：列表上不该有 \(identifier)")
        }

        let streakRow = app.buttons["blindPartnerRow.1"].firstMatch
        XCTAssertEqual(streakRow.label, "张，连续 3 周一起跑步，一起跑完 12 次", "\(variant)：一行一句话、名字不带星号")
        XCTAssertEqual(app.buttons["blindPartnerRow.2"].firstMatch.label, "王，对方已退出固定搭档")
        XCTAssertFalse(
            app.buttons["blindPartnerRow.0"].firstMatch.label.contains("连续"),
            "\(variant)：未点亮的不念「连续」"
        )
        attachScreenshot(app, name: "blind-partners-\(variant)-list")
        try audit(app)

        for index in 0..<4 {
            let row = app.buttons["blindPartnerRow.\(index)"].firstMatch
            for _ in 0..<6 where !row.isHittable { app.swipeUp() }
            XCTAssertGreaterThanOrEqual(row.frame.height, 63.5, "\(variant)：第 \(index) 行可点高度不足 64pt：\(row.frame)")
        }
        if variant.hasPrefix("ax5") {
            attachScreenshot(app, name: "blind-partners-\(variant)-list-bottom")
            try audit(app, contentScrolledUnderNavigationBar: true)
        }
        for _ in 0..<8 { app.swipeDown() }
    }

    @available(iOS 17.0, *)
    @MainActor
    private func checkBlindPartnerDetail(_ app: XCUIApplication, variant: String, isFavorite: Bool) throws {
        let suffix = isFavorite ? "favorite" : "not-favorite"
        let streak = app.descendants(matching: .any)["blindPartnerStreakCard"].firstMatch
        XCTAssertTrue(streak.waitForExistence(timeout: 5), "\(variant)：没有连续周数卡")
        attachScreenshot(app, name: "blind-partner-detail-\(variant)-\(suffix)")
        try audit(app)

        if isFavorite {
            XCTAssertTrue(streak.label.hasPrefix("连续一起跑，3 周"), streak.label)
            XCTAssertTrue(app.descendants(matching: .any)["blindPartnerTogetherRow"].firstMatch.exists)
            XCTAssertFalse(app.buttons["blindAddFavoriteButton"].firstMatch.exists)
            for identifier in ["counterpartReportButton", "counterpartBlockButton", "blindRemoveFavoriteButton"] {
                let button = revealBlindPartnerButton(app, identifier)
                XCTAssertGreaterThanOrEqual(button.frame.height, 63.5, "\(variant)：\(identifier) 可点高度不足 64pt：\(button.frame)")
            }
            attachScreenshot(app, name: "blind-partner-detail-\(variant)-\(suffix)-bottom")
            try audit(app, contentScrolledUnderNavigationBar: true)
        } else {
            let add = revealBlindPartnerButton(app, "blindAddFavoriteButton")
            XCTAssertGreaterThanOrEqual(add.frame.height, 63.5, "\(variant)：设为固定搭档可点高度不足 64pt：\(add.frame)")
            XCTAssertFalse(app.buttons["blindRemoveFavoriteButton"].firstMatch.exists, "\(variant)：还不是搭档不该有取消")
            if variant.hasPrefix("ax5") {
                revealBlindPartnerButton(app, "counterpartBlockButton")
                attachScreenshot(app, name: "blind-partner-detail-\(variant)-\(suffix)-bottom")
                try audit(app, contentScrolledUnderNavigationBar: true)
            }
        }
    }

    /// 拖到按钮露出。每次拖四分之一屏，免得拖过头。
    @discardableResult
    @MainActor
    func revealBlindPartnerButton(_ app: XCUIApplication, _ identifier: String, maxDrags: Int = 12) -> XCUIElement {
        let element = app.buttons[identifier].firstMatch
        _ = element.waitForExistence(timeout: 8)
        for _ in 0..<maxDrags {
            if element.exists, element.isHittable, element.frame.maxY < app.frame.maxY - 40 { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
        }
        XCTAssertTrue(element.exists && element.isHittable, "\(identifier) 没有露出来")
        return element
    }
}
