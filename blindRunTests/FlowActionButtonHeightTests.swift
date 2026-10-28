import SwiftUI
import UIKit
import XCTest
@testable import blindRun

/// `FlowActionButton` 的 `minHeight`（#446）：盲人端 B3「确认见面安排」「有异议，致电沟通」两枚 84pt，
/// 此前为了高度复制了一份按钮外观（`PlanDecisionButton`）。参数没接进 frame 时 `.call` 只有 80，这条会红。
final class FlowActionButtonHeightTests: XCTestCase {

    private static let width: CGFloat = 350

    func testExplicitMinHeightOverridesTheStyleDefault() {
        for style in [FlowActionButton.Style.primary, .call] {
            let height = Self.height(FlowActionButton("确认见面安排", style: style, minHeight: 84) {})
            XCTAssertGreaterThanOrEqual(height, 84, "\(style)：实际 \(height)pt")
        }
    }

    func testStyleDefaultsStayWhenNoMinHeightIsGiven() {
        let call = Self.height(FlowActionButton("打电话给陪跑员", style: .call) {})
        XCTAssertEqual(call, FlowMetrics.callButtonMinHeight, accuracy: 0.5)
        let primary = Self.height(FlowActionButton("开始跑步", style: .primary) {})
        XCTAssertEqual(primary, FlowMetrics.actionButtonMinHeight, accuracy: 0.5)
    }

    private static func height<V: View>(_ view: V) -> CGFloat {
        UIHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
            .height
    }
}
