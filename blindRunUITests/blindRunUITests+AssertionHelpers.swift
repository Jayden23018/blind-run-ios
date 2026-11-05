import XCTest

extension blindRunUITests {
    func assertVolunteerTopStatusBlockPosition(
        _ topStatusBlock: XCUIElement,
        app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let appStatusBar = app.statusBars.firstMatch
        let springboardStatusBar = XCUIApplication(bundleIdentifier: "com.apple.springboard").statusBars.firstMatch
        if appStatusBar.exists || springboardStatusBar.exists {
            let statusBar = appStatusBar.exists ? appStatusBar : springboardStatusBar
            XCTAssertGreaterThanOrEqual(
                topStatusBlock.frame.minY,
                statusBar.frame.maxY - 1,
                "Volunteer status block should remain below the system status area",
                file: file,
                line: line
            )
        } else {
            XCTAssertGreaterThanOrEqual(
                topStatusBlock.frame.minY,
                20,
                "Volunteer status block should preserve a conservative top safe area when iPadOS does not expose a status-bar accessibility element",
                file: file,
                line: line
            )
        }
        XCTAssertLessThan(
            topStatusBlock.frame.minY,
            100,
            "Volunteer status block should remain at the top instead of double-counting the safe area",
            file: file,
            line: line
        )
    }

    func assertNoEmergencyAction(
        _ app: XCUIApplication,
        _ why: String = "SOS 只在服务进行中出现，任何一方都一样",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertFalse(
            app.buttons["一键求助，遇到紧急情况时点击"].firstMatch.exists, why, file: file, line: line
        )
        XCTAssertFalse(app.buttons["一键求助"].firstMatch.exists, why, file: file, line: line)
        // 跑步中那一枚（2026-09-26 起打开求助面板，读屏念「求助与安全」）按 identifier 判 ——
        // 按文案判会和 v2 页面上同样念「求助与安全」的本地拨号胶囊混在一起。
        XCTAssertFalse(app.buttons["volunteerServiceSOSButton"].firstMatch.exists, why, file: file, line: line)
    }

    /// 求助按钮必须**点得到**，不只是存在于无障碍树里。
    ///
    /// `exists` 只说明控件被渲染进了树，一个被面板挤出屏幕、或被其它视图盖住的按钮同样 `exists`。
    /// 志愿者「服务中」页是 ZStack + 有高度预算的底部面板，求助入口是后加进去的 —— 这一条断言就是
    /// 那次布局改动唯一的把关：安全按钮点不到等于没有。
    func assertEmergencyActionIsUsable(
        _ app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // 跑步中那一枚 2026-09-26 起打开求助面板（DECISIONS-v2 V5），读屏文案随之改成「求助与安全」。
        // 按 identifier 找再断言文案：只按文案找会和 v2 页面上念同一句的本地拨号胶囊混在一起。
        let button = app.buttons["volunteerServiceSOSButton"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 8), "服务进行中必须提供求助入口", file: file, line: line)
        XCTAssertEqual(button.label, "求助与安全", "读屏念的不是求助面板入口", file: file, line: line)
        // 失败时把几何和截图带出来：「被面板挤出屏幕」「被导航栏盖住」「被别的层压住」是三种修法，
        // 只看 exists / isHittable 分不出。
        if !button.isHittable { attachScreenshot(named: "sos-not-hittable", app: app) }
        XCTAssertTrue(
            button.isHittable,
            "求助按钮存在但点不到 —— 按钮 \(button.frame)，导航栏 \(app.navigationBars.firstMatch.exists ? "\(app.navigationBars.firstMatch.frame)" : "无")",
            file: file,
            line: line
        )
    }

    /// 盲人端陪跑中贴底的那块求助中心。
    ///
    /// 🚩 它的标签**刻意不含「一键求助」** —— 那四个字在本 App 里专指云端链路（记事件、
    /// 通知同行志愿者与客服），而按开这一层菜单一个字节都没发出去。两者用同一个词，
    /// 看不见屏幕的人会以为求助已经发出。
    func blindSafetyHub(_ app: XCUIApplication) -> XCUIElement {
        // 逐字对应 `EmergencySafetyCopy.hubAccessibilityLabel`。
        app.buttons["求助与安全，打开求助选项"].firstMatch
    }

    func dismissKeyboardIfPresent(app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }

        let dismissButton = app.buttons["收起键盘"].firstMatch
        if dismissButton.waitForExistence(timeout: 1) {
            dismissButton.tap()
            if app.keyboards.firstMatch.waitForNonExistence(timeout: 2) {
                return
            }
        }

        for button in [
            app.keyboards.buttons["Return"].firstMatch,
            app.keyboards.buttons["Done"].firstMatch,
            app.keyboards.buttons["完成"].firstMatch
        ] where button.exists && button.isHittable {
            button.tap()
        }
        if app.keyboards.firstMatch.waitForNonExistence(timeout: 1) {
            return
        }

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 1)
    }

    func dismissSystemAlertsIfPresent(app: XCUIApplication, activateWhenNoAlert: Bool = true) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: 0.2) else {
            if activateWhenNoAlert {
                app.activate()
            }
            return
        }

        for title in [
            "允许使用 App 时", "允许使用App时", "使用 App 时允许", "使用App时允许", "允许一次",
            "Allow While Using App", "Allow Once",
            "允许", "Allow", "好", "OK", "继续", "Continue"
        ] {
            let button = alert.buttons[title].firstMatch
            if button.exists {
                if button.isHittable {
                    button.tap()
                } else {
                    button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                }
                app.activate()
                return
            }
        }

        app.activate()
    }
}

extension String {
    func leftPadded(toLength length: Int, withPad character: Character = "0") -> String {
        if count >= length {
            return String(suffix(length))
        }
        return String(repeating: String(character), count: length - count) + self
    }
}
