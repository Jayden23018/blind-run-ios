import XCTest

/// 下单表单第 2 步（预约时间）的读屏可用性（#295）。此前审计只到第 1 步，这一步从没被审过。
extension AccessibilityAuditTests {

    /// 日期 / 时刻两行是给读屏一条不用开 compact `DatePicker` 弹层的路：
    /// 读屏把整行当一个可调节元素（上下滑），明眼人点两端 64pt 的「−」「＋」。
    /// 这里断言它们在、够高、两端按钮真的改得动值，再跑一遍审计（读屏上下滑只能人工验）。
    /// 落点由麦克风授权决定（授权成功时退出语音后表单停在确认页），所以按「下一步 / 上一步」走到第 2 步。
    @MainActor
    func testBlindBookingAppointmentStepOffersAdjustableRowsAndPassesAudit() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        let app = launchBlindHome()
        let start = app.descendants(matching: .any)["blindRunnerHomeStartBookingButton"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        start.tap()
        XCTAssertTrue(waitForBookingScreen(app), "下单页没起来")
        let stopVoice = app.descendants(matching: .any)["blindBookingStopVoiceButton"].firstMatch
        if stopVoice.waitForExistence(timeout: 5) { stopVoice.tap() }

        let time = app.descendants(matching: .any)["blindBookingTimeAdjuster"].firstMatch
        let date = app.descendants(matching: .any)["blindBookingDateAdjuster"].firstMatch
        let deadline = Date().addingTimeInterval(30)
        while !time.exists, Date() < deadline {
            let next = app.buttons["下一步：预约时间"].firstMatch
            let back = app.buttons["上一步"].firstMatch
            if next.exists, next.isEnabled { next.tap() } else if back.exists { back.tap() }
            _ = time.waitForExistence(timeout: 1)
        }
        XCTAssertTrue(time.exists, "没走到预约时间这一步")
        XCTAssertTrue(date.exists, "预约时间这一步缺少日期调节行")

        // 调节行在选择器与提示行下面，进来时压在底栏后面（`isHittable` 仍报 true），按 y 判。
        let barTop = app.buttons["重复当前状态"].firstMatch.frame.minY
        for _ in 0..<4 where time.frame.maxY > barTop - 8 { app.swipeUp() }
        for (row, name) in [(date, "日期"), (time, "时刻")] {
            XCTAssertGreaterThanOrEqual(
                row.frame.height + Self.layoutRoundingTolerance, Self.minimumBlindPrimaryButtonHeight,
                "「\(name)」调节行只有 \(row.frame.height)pt"
            )
        }

        // 明眼人那条路：点右端的「＋」（整行对读屏是一个元素，按钮不在树里，按坐标点）。
        let beforeTap = time.value as? String
        time.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(waitForValueChange(of: time, from: beforeTap), "点「＋」之后时刻没变（\(beforeTap ?? "nil")）")

        // 左端「−」：退回去（刚加的那 15 分钟一定在合法区间内，减得动）。
        // 读屏的上下滑（`accessibilityAdjustableAction`）XCUITest 模拟不了，要人开 VoiceOver 走一遍。
        let beforeDecrement = time.value as? String
        time.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).tap()
        XCTAssertTrue(waitForValueChange(of: time, from: beforeDecrement), "点「−」之后时刻没变")

        // 审计前滚回顶部：步骤标题压在半透明导航栏下时审计会取到糊掉的像素，报假的对比度不足。
        for _ in 0..<4 { app.swipeDown() }
        attachScreenshot(app, name: "booking-appointment-step")
        try audit(app)
    }

    private func waitForValueChange(of element: XCUIElement, from before: String?, timeout: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while (element.value as? String) == before, Date() < deadline {
            _ = element.waitForExistence(timeout: 0.3)
        }
        return (element.value as? String) != before
    }
}
