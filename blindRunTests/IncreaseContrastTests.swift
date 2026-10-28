import UIKit
import XCTest
@testable import blindRun

/// 「增强对比度」（#579）。`AppColors.textSecondary` 此前只看明暗，开了开关跑后记录等页面的灰字纹丝不动。
/// 与 `Flow.secondaryText`、`HighContrastText` 同一个办法：开关打开时并到主文字。
final class IncreaseContrastTests: XCTestCase {

    func testSecondaryTextBecomesPrimaryTextWhenIncreaseContrastIsOn() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let high = UITraitCollection(traitsFrom: [.init(userInterfaceStyle: style), .init(accessibilityContrast: .high)])
            let normal = UITraitCollection(traitsFrom: [.init(userInterfaceStyle: style), .init(accessibilityContrast: .normal)])

            XCTAssertEqual(
                AppColors.textSecondaryUIColor.resolvedColor(with: high),
                UIColor.label.resolvedColor(with: high),
                "\(style.rawValue)：开了增强对比度，次级文字应与主文字同色"
            )
            // 验红：关着时仍是原来的灰，不能把两档做成同一个色（那样上一条恒真）。
            XCTAssertNotEqual(
                AppColors.textSecondaryUIColor.resolvedColor(with: normal),
                UIColor.label.resolvedColor(with: normal),
                "\(style.rawValue)：没开时应保留原来的次级灰"
            )
        }
    }
}
