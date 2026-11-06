#if DEBUG
import XCTest
@testable import blindRun

/// Debug 包顶部调试标记的文字规则（`DebugBuildStamp`）。
/// 值来自 `scripts/preview-build.sh` 写进 Info.plist 的 `AidRunPreviewPRs`。
@MainActor
final class DebugBuildStampTests: XCTestCase {

    func testXcodeBuildWithoutPreviewValueShowsMockOnlyInMockEnvironment() {
        let contents = DebugBuildStamp.parse("")

        XCTAssertFalse(contents.isPreviewBuild)
        XCTAssertEqual(DebugBuildStamp.label(isMock: true, contents: contents), "Mock")
        XCTAssertNil(DebugBuildStamp.label(isMock: false, contents: contents))
    }

    func testUnexpandedOrForeignValueIsNotTreatedAsPreview() {
        // 没传构建设置时 Xcode 展开成空串；万一原样留着 `$(...)`，也不能当成预览包。
        XCTAssertFalse(DebugBuildStamp.parse("$(AIDRUN_PREVIEW_PRS)").isPreviewBuild)
        XCTAssertFalse(DebugBuildStamp.parse("784,790").isPreviewBuild)
        XCTAssertFalse(DebugBuildStamp.parse(nil).isPreviewBuild)
    }

    func testPreviewOfPlainMainShowsMain() {
        let contents = DebugBuildStamp.parse("main")

        XCTAssertEqual(contents, .init(isPreviewBuild: true, prNumbers: []))
        XCTAssertEqual(DebugBuildStamp.label(isMock: false, contents: contents), "main")
        XCTAssertEqual(DebugBuildStamp.label(isMock: true, contents: contents), "Mock main")
    }

    func testSinglePRIsListedByNumber() {
        let contents = DebugBuildStamp.parse("main,784")

        XCTAssertEqual(DebugBuildStamp.label(isMock: true, contents: contents), "Mock #784")
    }

    func testTwoOrMorePRsCollapseToACountSoTheLabelStaysLeftOfTheDynamicIsland() {
        // 2 个是分界：maxListedPRs = 1，放宽成 2 时这条会变成「#784 #790」而失败。
        let two = DebugBuildStamp.parse("main,784,790")
        let three = DebugBuildStamp.parse(" main , 784, 790 ,801 ")

        XCTAssertEqual(DebugBuildStamp.label(isMock: false, contents: two), "2 个 PR")
        XCTAssertEqual(DebugBuildStamp.label(isMock: true, contents: three), "Mock 3 个 PR")
    }

    func testMalformedNumbersAreDropped() {
        let contents = DebugBuildStamp.parse("main,784,abc,-3,0,,790")

        XCTAssertEqual(contents.prNumbers, [784, 790])
    }

    func testAccessibilityLabelListsEveryPR() {
        let contents = DebugBuildStamp.parse("main,784,790,801")

        XCTAssertEqual(
            DebugBuildStamp.accessibilityLabel(isMock: true, contents: contents),
            "调试标记，Mock 本地模拟，不连接云端，预览包，包含 PR 784、790、801"
        )
    }
}
#endif
