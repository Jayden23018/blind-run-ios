import XCTest

/// 陪跑员「连续陪跑」跑步数据页（#710）：首页卡点进来、里程四档切换、亮 / 暗整页审计。
/// 数据用 Mock 的近半年样例（`AIDRUN_UI_TEST_SEED_RUN_DATA=1`，照定稿脚本生成），否则每单 1.04 公里，图上看不出起伏。
extension AccessibilityAuditTests {
    static let runDataSeed = ["AIDRUN_UI_TEST_SEED_RUN_DATA": "1"]

    /// 从首页点「连续陪跑」半宽卡进数据页。卡在底部接单栏后面时先滚上来，免得点到栏上。
    @MainActor
    func openVolunteerRunData(environment: [String: String] = [:], arguments: [String] = []) -> XCUIApplication {
        let app = launchVolunteerHome(
            extraEnvironment: Self.runDataSeed.merging(environment) { _, new in new },
            extraArguments: arguments
        )
        let card = app.descendants(matching: .any)["volunteerHomeHalfCard.streak"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 25), "首页没有「连续陪跑」卡（样例里李* 连续 3 周）")
        let bar = app.descendants(matching: .any)["volunteerHomeBottomBar"].firstMatch
        for _ in 0..<8 where !card.isHittable || (bar.exists && card.frame.maxY > bar.frame.minY) {
            app.swipeUp()
        }
        card.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["volunteerRunDataView"].firstMatch.waitForExistence(timeout: 10),
            "点「连续陪跑」卡没有进跑步数据页"
        )
        return app
    }

    /// 首页「连续陪跑」卡进的是跑步数据页，不是固定搭档列表；结论卡与首页卡是同一对搭档、同一个周数。
    /// 页底「固定搭档」仍能进固定搭档页。
    @MainActor
    func testStreakCardOpensRunDataPageInsteadOfPartners() {
        let app = openVolunteerRunData()
        XCTAssertFalse(app.descendants(matching: .any)["volunteerPartnersView"].firstMatch.exists, "不该再进固定搭档列表")

        let streak = app.descendants(matching: .any)["volunteerRunData.streak"].firstMatch
        XCTAssertTrue(streak.waitForExistence(timeout: 5))
        // 首页卡读的是 Mock 火花第一条「李*，3 周，最好 7 周」；样例本周和李*跑过 ⇒ 记上了。
        XCTAssertTrue(streak.label.contains("和 李 连续陪跑 3 周"), streak.label)
        XCTAssertTrue(streak.label.contains("这一周记上了"), streak.label)

        let calendar = app.descendants(matching: .any)["volunteerRunData.calendar"].firstMatch
        XCTAssertTrue(calendar.waitForExistence(timeout: 15), "陪跑日历没出来（12 个月的记录一个都没回来？）")
        XCTAssertTrue(calendar.value.map { "\($0)" }?.hasPrefix("近半年陪跑 ") == true, "日历读屏摘要不对：\(String(describing: calendar.value))")

        let link = app.descendants(matching: .any)["volunteerRunData.partnersLink"].firstMatch
        for _ in 0..<12 where !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.isHittable, "滚到底了「固定搭档」入口仍点不到")
        XCTAssertGreaterThanOrEqual(link.frame.height, 64 - Self.layoutRoundingTolerance, "固定搭档入口可点区不到 64pt")
        link.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["volunteerPartnersView"].firstMatch.waitForExistence(timeout: 10),
            "页底「固定搭档」没进固定搭档页"
        )
    }

    /// 里程默认「半年」，四档都切得过去，读屏摘要跟着换。每档截一张图给定稿对照。
    @MainActor
    func testRunDataMileageDefaultsToHalfYearAndSwitchesRanges() {
        let app = openVolunteerRunData()
        let chart = app.descendants(matching: .any)["volunteerRunData.mileageChart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 15), "里程图没出来")
        // 把分段切换顶到导航栏下面：切换与整张图同屏，截图才看得到图。
        scrollRunDataSection(app, "volunteerRunDataRange.week")
        XCTAssertTrue(chart.label.hasPrefix("里程，半年"), "默认应当是半年档：\(chart.label)")

        for (range, title) in [("week", "周"), ("month", "月"), ("year", "年"), ("halfYear", "半年")] {
            let button = app.buttons["volunteerRunDataRange.\(range)"].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5), "没有「\(title)」档")
            button.tap()
            XCTAssertTrue(button.isSelected, "点了「\(title)」档没有选中")
            XCTAssertTrue(chart.label.hasPrefix("里程，\(title)，"), "切到「\(title)」后摘要没跟着换：\(chart.label)")
            attachScreenshot(app, name: "volunteer-run-data-mileage-\(range)")
        }
    }

    /// 页面从上到下的分节锚点。审计会把页面滚回顶部（`.dynamicType` / `.textClipped`，见 `audit`），
    /// 所以不能「审一屏、滑一下」地往下走，要每次按锚点重新定位。
    static let runDataSections = [
        "volunteerRunData.streak",
        "volunteerRunData.calendar",
        "volunteerRunDataRange.week",
        "volunteerRunData.durationChart",
        "volunteerRunData.comparison",
        "volunteerRunData.longest",
        "volunteerRunData.partners",
        "volunteerRunData.record.0",
        "volunteerRunData.partnersLink"
    ]

    /// 把一节的上沿拖到导航栏下沿下面一点（按住再拖，不带惯性）；到页底拖不动了就停。
    @MainActor
    @discardableResult
    func scrollRunDataSection(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 10), "跑步数据页没有「\(identifier)」")
        let bar = app.navigationBars.firstMatch
        let target = (bar.exists ? bar.frame.maxY : 120) + 12
        var previous: CGRect?
        for _ in 0..<12 {
            let frame = element.frame
            if abs(frame.minY - target) < 8 || frame == previous { break }
            previous = frame
            let shift = max(-480, min(480, target - frame.minY))
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: shift < 0 ? 0.85 : 0.3))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: shift)))
        }
        waitUntilSettled(element)
        return element
    }

    /// 默认字号的亮 / 暗逐节过审计，每节截一张。
    /// 陪跑员端不测最大字号（负责人 2026-11-05 定，记忆 `volunteer-side-no-largest-text-tests`）。
    ///
    /// 审计只看屏幕上的元素，所以按 `runDataSections` 逐节滚到导航栏下面再审。
    /// 滚到导航栏后面的上一节内容由 `audit` 的导航栏遮挡判据放过（几何上看不见）。
    @MainActor
    func testVolunteerRunDataPassesAuditInLightAndDark() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .portrait
        for variant in Self.appearanceVariants where variant.arguments.isEmpty {
            let app = openVolunteerRunData(environment: variant.environment, arguments: variant.arguments)
            let calendar = app.descendants(matching: .any)["volunteerRunData.calendar"].firstMatch
            XCTAssertTrue(calendar.waitForExistence(timeout: 15), "\(variant.name)：陪跑日历没出来")
            for (index, section) in Self.runDataSections.enumerated() {
                let element = scrollRunDataSection(app, section)
                XCTAssertLessThanOrEqual(element.frame.maxY, app.frame.maxY, "\(variant.name)：「\(section)」滚不进屏幕")
                attachScreenshot(app, name: "volunteer-run-data-\(variant.name)-\(index + 1)")
                try audit(app)
            }
            app.terminate()
        }
    }
}
