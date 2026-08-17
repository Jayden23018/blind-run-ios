import XCTest
@testable import blindRun

/// `BlindLayout` 的算术部分。
///
/// 布局本身（列宽真的收了没有、横屏有没有裁切）只有真机
/// `blindRunUITests/AccessibilityAuditTests` 的横屏审计能验 —— 这里守的是那条**分支**：
/// 矮窗口要压、压完不能反过来比原来还高、宽窗口不许动。
final class BlindLayoutTests: XCTestCase {

    /// 竖屏（`.regular` 高度）原样返回。iPad 横屏也走这一支：那里高度充裕，
    /// 压扁只会让地图小到看不出东西。
    func testRegularHeightWindowKeepsTheDeclaredMapHeight() {
        XCTAssertEqual(
            BlindLayout.decorativeMapHeight(regular: 180, isCompactHeight: false),
            180
        )
        XCTAssertEqual(
            BlindLayout.decorativeMapHeight(regular: 160, isCompactHeight: false),
            160
        )
    }

    /// iPhone 横屏：两张装饰地图都压到 96pt。
    ///
    /// 数值本身就是这条用例的意义 —— iPhone 横屏可用高度约 390pt，180pt 占 46%，
    /// 而这两张地图都是 `allowsHitTesting(false)` 的纯装饰层。
    func testCompactHeightWindowShrinksDecorativeMaps() {
        XCTAssertEqual(
            BlindLayout.decorativeMapHeight(regular: 180, isCompactHeight: true),
            BlindLayout.compactDecorativeMapHeight,
            "订单状态页的同行地图横屏没压扁"
        )
        XCTAssertEqual(
            BlindLayout.decorativeMapHeight(regular: 160, isCompactHeight: true),
            BlindLayout.compactDecorativeMapHeight,
            "下单页的辅助地图横屏没压扁"
        )
    }

    /// 「压扁」不许把本来就矮的地图撑高 —— 去掉 `min` 这条就红。
    func testCompactHeightNeverEnlargesAShorterMap() {
        XCTAssertEqual(
            BlindLayout.decorativeMapHeight(regular: 60, isCompactHeight: true),
            60,
            "原本 60pt 的地图在横屏被撑到 96pt —— 压扁规则只能往小压"
        )
    }

    /// 可读列宽必须比 iPhone 竖屏最宽的机型还宽，否则这条规则会在**竖屏**上误伤：
    /// 内容列在 iPhone 上收窄等于凭空多出左右两条空白。
    /// iPhone 16 Pro Max 竖屏 440pt 是当前最宽的一档。
    func testReadableWidthDoesNotClampPortraitIPhones() {
        XCTAssertGreaterThan(
            BlindLayout.readableContentWidth,
            440,
            "可读列宽窄于 iPhone 竖屏宽度，会在竖屏上凭空收窄内容"
        )
    }
}
