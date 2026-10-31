import SwiftUI
import UIKit
import XCTest
@testable import blindRun

/// 语音下单读回轮整单的一行（#527）：长地址折行而不是缩到 60%，无障碍字号下上下排。
final class BookingRecapRowTests: XCTestCase {

    private static let rowWidth: CGFloat = 350
    private static let longAddress = "北京市朝阳区奥林匹克森林公园南园南门东侧停车场入口旁边的长椅"

    /// 旧写法 `lineLimit(1)` + `minimumScaleFactor(0.6)` 下长短地址一样高（都是一行），这条就是靠这个区分的。
    func testLongAddressWrapsInsteadOfShrinkingToOneLine() {
        let short = Self.height(BookingRecapRow(name: "出发", value: "公园"))
        let long = Self.height(BookingRecapRow(name: "出发", value: Self.longAddress))
        XCTAssertGreaterThan(long, short * 1.5, "长地址应折成多行，实际 \(long)pt vs 单行 \(short)pt")
    }

    func testAccessibilitySizesStackTheNameAboveTheValue() {
        let nameOnly = Self.height(Text("出发").font(AppFonts.body()).environment(\.dynamicTypeSize, .accessibility5))
        let row = Self.height(BookingRecapRow(name: "出发", value: "公园").environment(\.dynamicTypeSize, .accessibility5))
        XCTAssertGreaterThan(row, nameOnly * 1.6, "AX5 下名字和值应上下两行，实际 \(row)pt vs 一行 \(nameOnly)pt")
    }

    func testValueEndingWithFullWidthParenGetsANarrowSpaceOnScreenOnly() {
        XCTAssertEqual(BookingRecapRow.displayValue("公园南门（未定位到）"), "公园南门（未定位到）\u{202F}")
        XCTAssertEqual(BookingRecapRow.displayValue("公园南门"), "公园南门")
    }

    private static func height<V: View>(_ view: V) -> CGFloat {
        UIHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: rowWidth, height: .greatestFiniteMagnitude))
            .height
    }
}
