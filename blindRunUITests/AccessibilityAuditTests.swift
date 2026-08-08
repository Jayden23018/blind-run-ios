//
//  AccessibilityAuditTests.swift
//  blindRunUITests
//
//  这是一个盲人 App。AGENTS.md 第 8 节和 skill `aidrun-a11y-voice` 对 VoiceOver、
//  64pt 触达、「重复当前状态」按钮有硬性要求，但此前**没有一条自动检查**。
//
//  `performAccessibilityAudit`（Xcode 15+）做的是 Accessibility Inspector 那套静态检查：
//  缺 label、文本被截断、对比度不足、不支持 Dynamic Type。它不驱动 VoiceOver，
//  所以「遍历顺序」「重复当前状态存在」这类语义要求仍需单独断言 —— 见本文件后半。
//
//  只能真机跑（高德无 arm64-sim slice，模拟器通道永久不可用）：
//    scripts/device-test.sh -only-testing:blindRunUITests/AccessibilityAuditTests
//

import XCTest

final class AccessibilityAuditTests: XCTestCase {

    override func setUpWithError() throws {
        // 默认 false 会在第一个问题就停下，那样一次只能看见一条。
        // 无障碍审计的价值恰恰在于一次列全，所以这里反过来。
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: - 静态审计

    @MainActor
    func testBlindRunnerHomePassesAccessibilityAudit() throws {
        // 内联 guard 而不是抽成 helper：只有内联的 `#available` 才能让编译器
        // 在后续语句里窄化可用性，helper 里 throw XCTSkip 编译不过。
        guard #available(iOS 17.0, *) else {
            throw XCTSkip("performAccessibilityAudit 需要 iOS 17+ 运行时")
        }
        let app = launchBlindHome()
        XCTAssertTrue(
            app.descendants(matching: .any)["blindRunnerHomeStartBookingButton"].firstMatch
                .waitForExistence(timeout: 20),
            "盲人首页没起来，后面的审计结果没有意义"
        )
        try audit(app)
    }

    @MainActor
    func testBlindBookingPassesAccessibilityAudit() throws {
        guard #available(iOS 17.0, *) else {
            throw XCTSkip("performAccessibilityAudit 需要 iOS 17+ 运行时")
        }
        let app = launchBlindHome()
        let start = app.descendants(matching: .any)["blindRunnerHomeStartBookingButton"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        start.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["blindBookingVoiceOrderButton"].firstMatch
                .waitForExistence(timeout: 20),
            "下单页没起来"
        )
        try audit(app)
    }

    // MARK: - 静态审计抓不到的语义要求

    /// `AGENTS.md`：盲人端关键主按钮高度 ≥ 64pt。
    /// audit 查不到这个 —— 一个 20pt 高但有完整 label 的按钮能通过全部静态检查。
    @MainActor
    func testBlindRunnerPrimaryButtonMeetsMinimumTouchTarget() throws {
        let app = launchBlindHome()
        let start = app.descendants(matching: .any)["blindRunnerHomeStartBookingButton"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 20))

        XCTAssertGreaterThanOrEqual(
            start.frame.height,
            Self.minimumBlindPrimaryButtonHeight,
            "盲人端主按钮实测 \(start.frame.height)pt，低于硬性要求的 \(Self.minimumBlindPrimaryButtonHeight)pt"
        )
    }

    /// `AGENTS.md`：每个关键盲人页面必须有「重复当前状态」。
    /// 它不冗余 —— 系统 Speak Screen 读不到一次性的 announcement，没有这个按钮，
    /// 盲人错过一次播报就再也拿不回来。
    @MainActor
    func testBlindRunnerHomeOffersRepeatCurrentStatus() throws {
        let app = launchBlindHome()
        XCTAssertTrue(
            app.descendants(matching: .any)["blindRunnerHomeStartBookingButton"].firstMatch
                .waitForExistence(timeout: 20)
        )

        let repeatControl = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "重复当前状态"))
            .firstMatch
        XCTAssertTrue(
            repeatControl.waitForExistence(timeout: 10),
            "盲人首页缺少「重复当前状态」。可以降视觉权重，但不能删。"
        )
    }

    /// 主按钮必须**看起来**就是主按钮，不只是够得着。
    ///
    /// 上一条只查 64pt，而 64pt 正是它此前和「重复当前状态」同高时的值 —— 那一版全绿，
    /// 用户看到的却是「约跑的按钮还是小」。对标 Be My Eyes 的 `Call a volunteer` 占内容区约 75%
    /// （`docs/research/blind-ui-visual-benchmark-20260808.md` §1）。
    ///
    /// 阈值取窗口高度的 25% 而不是 55%：内容区在窗口里还要扣掉地图、SOS 条与次级按钮，
    /// 这里要抓的是「有没有被缩回次级按钮那一档」，不是精确复刻某个比例。
    @MainActor
    func testBlindRunnerPrimaryButtonDominatesTheScreen() throws {
        let app = launchBlindHome()
        let start = app.descendants(matching: .any)["blindRunnerHomeStartBookingButton"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 20))

        let windowHeight = app.windows.firstMatch.frame.height
        XCTAssertGreaterThan(windowHeight, 0, "拿不到窗口高度，这条断言等于没跑")

        let share = start.frame.height / windowHeight
        XCTAssertGreaterThanOrEqual(
            share,
            Self.minimumBlindPrimaryButtonScreenShare,
            """
            主按钮实测 \(start.frame.height)pt，只占屏高 \(Int(share * 100))%，\
            低于 \(Int(Self.minimumBlindPrimaryButtonScreenShare * 100))%。\
            低视力用户找不到它。要改这个阈值先看对标文档 §1。
            """
        )
    }

    // MARK: - Helpers

    private static let minimumBlindPrimaryButtonHeight: CGFloat = 64
    private static let minimumBlindPrimaryButtonScreenShare: CGFloat = 0.25

    /// 低版本设备上明确 skip 而不是静默通过 —— 「没跑」和「跑过了」必须可区分。
    @available(iOS 17.0, *)
    private func audit(_ app: XCUIApplication) throws {
        try app.performAccessibilityAudit(
            for: [.contrast, .dynamicType, .elementDetection, .hitRegion, .sufficientElementDescription]
        ) { issue in
            // 高德地图图层无法承载有意义的 label，且它已被显式降权为辅助内容
            // （视觉可以铺满，读屏遍历顺序必须操作优先）。这是唯一的白名单项 ——
            // 每加一条都要写清为什么，否则白名单会慢慢把审计架空。
            let identifier = issue.element?.identifier ?? ""
            return identifier == "blindRunnerHomeAuxiliaryMap" || identifier == "blindBookingAuxiliaryMap"
        }
    }

    @MainActor
    private func launchBlindHome() -> XCUIApplication {
        let app = XCUIApplication()
        addTeardownBlock {
            await MainActor.run { app.terminate() }
        }
        app.launchEnvironment["AIDRUN_UI_TEST_RESET_STATE"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_RESET_TOKEN"] = UUID().uuidString
        app.launchEnvironment["AIDRUN_UI_TEST_FORCE_DEMO_LOCATION"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_API_ENV"] = "mock"
        app.launchEnvironment["AIDRUN_UI_TEST_ACTIVE_ROLE"] = "blind_runner"
        app.launchEnvironment["AIDRUN_UI_TEST_ACCESS_TOKEN"] = "mock_jwt_token_for_testing"
        // 注意是 PRESEEDED 不是 PRESEED —— 与 blindRunUITests.launchApp 保持一致，
        // 写错不会报错，只会静默进到「资料未填」分支，然后审计的是错的那一页。
        app.launchEnvironment["AIDRUN_UI_TEST_PRESEEDED_BLIND_PROFILE"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_EMPTY_MOCK_ORDERS"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_PREFILL_PROFILE_FORM"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_DISABLE_WEBSOCKET"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_DISABLE_MAP"] = "1"

        addUIInterruptionMonitor(withDescription: "系统权限弹窗") { alert in
            for title in ["允许", "好", "使用App时允许", "OK", "Allow"] {
                let button = alert.buttons[title]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }

        app.launch()
        app.tap() // 触发一次 interruption monitor，否则弹窗要等下一次交互才被处理
        return app
    }
}
