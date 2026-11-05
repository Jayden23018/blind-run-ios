import SwiftUI
import XCTest
@testable import blindRun

/// 陪跑员「我的」六个方块（#700）：白字对比度、大字号单列门槛、入口标识。
final class VolunteerSettingsTileTests: XCTestCase {
    /// 方块是纯色底压白字，过 4.5:1（正文门槛）。
    func testTileColoursKeepWhiteTextReadable() {
        for tile in VolunteerSettingsTile.allCases {
            XCTAssertGreaterThanOrEqual(LowVisionChannelTests.contrastRatio(0xFFFFFF, tile.rgb), 4.5, tile.title)
        }
    }

    /// AX3 及以上单列，以下两列。取门槛两侧的 AX2 / AX3，挡住「门槛被挪到 AX1 或 AX5」。
    func testTilesSwitchToOneColumnFromAccessibility3() {
        XCTAssertEqual(SettingsTileLayout.tileColumnCount(for: .large), 2)
        XCTAssertEqual(SettingsTileLayout.tileColumnCount(for: .xxxLarge), 2)
        XCTAssertEqual(SettingsTileLayout.tileColumnCount(for: .accessibility2), 2)
        XCTAssertEqual(SettingsTileLayout.tileColumnCount(for: .accessibility3), 1)
        XCTAssertEqual(SettingsTileLayout.tileColumnCount(for: .accessibility5), 1)
    }

    /// UI 用例按标识找入口：改版前六个入口的标识原样保留，且互不重复。
    func testTilesKeepTheirPreRedesignIdentifiers() {
        XCTAssertEqual(
            VolunteerSettingsTile.allCases.map(\.identifier),
            [
                "volunteerTrainingSettingsEntry",
                "volunteerScheduleSettingsEntry",
                "volunteerCertificateSettingsEntry",
                "volunteerPartnersSettingsEntry",
                "volunteerPointsSettingsEntry",
                "volunteerInviteCodeSettingsEntry",
            ]
        )
    }
}
