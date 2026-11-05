import XCTest

/// 陪跑员「我的」下三个子页（个人资料、我的积分、资质证书，#700）的整页审计与截图。
///
/// 陪跑员端只测默认字号的亮 / 暗两遍（负责人 2026-11-05 定）：最大字号（AX5）只在盲人端测。
private let accountPageVariants: [(name: String, environment: [String: String])] = [
    ("light", ["AIDRUN_UI_TEST_COLOR_SCHEME": "light"]),
    ("dark", ["AIDRUN_UI_TEST_COLOR_SCHEME": "dark"])
]

extension AccessibilityAuditTests {

    /// 个人资料只读：有姓名 / 手机号 / 实名三行，没有输入框和「提交」；手机号读屏只念尾号。
    @MainActor
    func testVolunteerAccountProfileIsReadOnlyAndPassesAudit() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        for variant in accountPageVariants {
            let app = launchVolunteerHome(extraEnvironment: variant.environment)
            openAccountPage(app, entry: app.buttons["个人资料"].firstMatch, throughAccountPage: true)

            let page = accountElement(app, "volunteerAccountProfileView")
            XCTAssertTrue(page.waitForExistence(timeout: 15), "\(variant.name)：没有进到个人资料页")
            let name = accountElement(app, "volunteerAccountProfileRow.name")
            XCTAssertTrue(name.waitForExistence(timeout: 10), "\(variant.name)：没有姓名那一行")
            XCTAssertEqual(name.label, "姓名，测试志愿者")
            // Mock 的 `/api/auth/me` 与后端同形状：已经脱敏的「138****0002」。
            XCTAssertEqual(accountElement(app, "volunteerAccountProfileRow.phone").label, "手机号，尾号 0002")
            XCTAssertFalse(app.textFields.firstMatch.exists, "\(variant.name)：资料页不该再有输入框")
            XCTAssertFalse(app.buttons["提交"].exists, "\(variant.name)：资料页不该再有「提交」")
            XCTAssertTrue(accountElement(app, "volunteerAccountProfileReadOnlyNote").exists)

            attachScreenshot(app, name: "account-profile-\(variant.name)")
            try audit(app)
            app.terminate()
        }
    }

    /// 积分页：余额卡在最上，「最新记录」一张卡，合规文案在页脚且原文不变。
    @MainActor
    func testVolunteerPointsPageKeepsComplianceFooterAndPassesAudit() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        for variant in accountPageVariants {
            let app = launchVolunteerHome(extraEnvironment: variant.environment)
            openAccountPage(app, entry: app.buttons["volunteerPointsSettingsEntry"].firstMatch)

            let balance = accountElement(app, "volunteerPointsBalance")
            XCTAssertTrue(balance.waitForExistence(timeout: 15), "\(variant.name)：积分余额卡没出来")
            XCTAssertTrue(balance.label.hasPrefix("当前积分"), "余额卡要先念余额：\(balance.label)")
            attachScreenshot(app, name: "account-points-\(variant.name)-top")
            try audit(app)

            let footer = accountElement(app, "volunteerPointsDisclaimer")
            var drags = 0
            while !(footer.exists && footer.isHittable) && drags < 8 {
                app.swipeUp()
                drags += 1
            }
            XCTAssertTrue(footer.exists, "\(variant.name)：页脚没有合规文案")
            XCTAssertTrue(footer.label.contains("积分不能提现、不能转让、不能兑换现金"), footer.label)
            XCTAssertTrue(footer.label.contains("积分和志愿服务时长是两回事"), footer.label)
            attachScreenshot(app, name: "account-points-\(variant.name)-bottom")
            try audit(app)
            app.terminate()
        }
    }

    /// 资质证书四种后端状态各进一次：卡上写着状态；能上传的两态有三种来源；审核中能重新获取状态；
    /// 「重复当前状态」任何状态都在。亮色四态，暗色只跑空卡与红卡（卡色两档同值，暗色只换页底与行）。
    @MainActor
    func testVolunteerCertificatePageShowsEachStateAndPassesAudit() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        let cases: [(status: String, displayName: String, variant: Int)] = [
            ("NONE", "未提交", 0), ("PENDING", "审核中", 0), ("APPROVED", "已通过", 0), ("REJECTED", "未通过", 0),
            ("NONE", "未提交", 1), ("REJECTED", "未通过", 1)
        ]
        for item in cases {
            let variant = accountPageVariants[item.variant]
            var environment = variant.environment
            environment["AIDRUN_MOCK_VOLUNTEER_VERIFICATION_STATUS"] = item.status
            let app = launchVolunteerHome(extraEnvironment: environment)
            openAccountPage(app, entry: app.buttons["volunteerCertificateSettingsEntry"].firstMatch)
            let tag = "\(item.status)-\(variant.name)"

            let card = accountElement(app, "volunteerCertificateStatusCard")
            XCTAssertTrue(card.waitForExistence(timeout: 15), "\(tag)：证书卡没出来")
            let expectedLabel = "当前审核状态，\(item.displayName)"
            let settled = NSPredicate(format: "label == %@", expectedLabel)
            expectation(for: settled, evaluatedWith: card)
            waitForExpectations(timeout: 10)

            let allowsUpload = item.status == "NONE" || item.status == "REJECTED"
            XCTAssertEqual(app.buttons["从相册选择"].exists, allowsUpload, "\(tag)：三种来源只在能上传时出现")
            // 屏幕上的「5 MB」在合成焦点里读屏听不到，能上传时要另外念出来。
            XCTAssertEqual(
                (card.value as? String)?.contains("不超过 5 兆") ?? false, allowsUpload,
                "\(tag)：文件大小上限要在能上传时念出来：\(String(describing: card.value))"
            )
            XCTAssertEqual(
                app.buttons["volunteerCertificateRefreshButton"].exists, item.status == "PENDING",
                "\(tag)：「重新获取状态」只在审核中 / 状态未知时出现"
            )
            let repeatStatus = app.buttons["volunteerCertificateRepeatStatusButton"].firstMatch
            XCTAssertTrue(repeatStatus.exists, "\(tag)：没有「重复当前状态」")
            XCTAssertGreaterThanOrEqual(repeatStatus.frame.height + 0.5, 52, "\(tag)：「重复当前状态」行高 \(repeatStatus.frame.height)")

            attachScreenshot(app, name: "account-certificate-\(tag)")
            try audit(app)
            app.terminate()
        }
    }

    // MARK: - 辅助

    /// 「我的」标签就是设置页；先拖到入口露出来再点。个人资料在账户页（「我的」→ 头像卡，#700）。
    @MainActor
    private func openAccountPage(_ app: XCUIApplication, entry: XCUIElement, throughAccountPage: Bool = false) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 25), "标签栏没起来")
        tabBar.buttons["我的"].tap()
        if throughAccountPage { app.openVolunteerAccountPage() }
        _ = entry.waitForExistence(timeout: 8)
        for _ in 0..<24 {
            let bottom = tabBar.exists ? tabBar.frame.minY : app.frame.maxY - 60
            if entry.exists, entry.isHittable, entry.frame.maxY < bottom { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
        }
        XCTAssertTrue(entry.exists && entry.isHittable, "设置页没找到入口")
        entry.tap()
    }

    private func accountElement(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }
}
