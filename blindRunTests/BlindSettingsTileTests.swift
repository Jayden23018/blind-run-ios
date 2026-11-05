import XCTest
@testable import blindRun

/// 盲人端「我的」四个方块（#711）：白字对比度、入口标识、读屏名称。
final class BlindSettingsTileTests: XCTestCase {
    /// 方块是纯色底压白字，过 4.5:1（正文门槛）。
    func testTileColoursKeepWhiteTextReadable() {
        for tile in BlindSettingsTile.allCases {
            XCTAssertGreaterThanOrEqual(LowVisionChannelTests.contrastRatio(0xFFFFFF, tile.rgb), 4.5, tile.title)
        }
    }

    /// UI 用例按标识找入口：改版前四个入口的标识原样保留，且互不重复。
    func testTilesKeepTheirPreRedesignIdentifiers() {
        XCTAssertEqual(
            BlindSettingsTile.allCases.map(\.identifier),
            [
                "blindFavoriteVolunteersSettingsEntry",
                "blindInviteCodeSettingsEntry",
                "blindRunnerSettingsHelpLink",
                "supportTicketSettingsEntry",
            ]
        )
    }

    /// 定稿的顺序与名字。「联系客服」要和账号停用提示里指向它的名字一致。
    func testTilesFollowTheApprovedOrderAndNames() {
        XCTAssertEqual(BlindSettingsTile.allCases.map(\.title), ["固定搭档", "邀请好友", "使用帮助", "联系客服"])
    }
}
