import XCTest
@testable import blindRun

/// 语音输入框回车（下单输入框截断的修复）。改成可折行的 `TextField(axis: .vertical)` 之后，回车默认插入换行；
/// 这里钉住每一类框的回车与改之前一样。每条都带换行输入：不拦截的实现会把 `\n` 留在文本里，这几条就红。
final class VoiceTextFieldReturnTests: XCTestCase {

    /// 搜索出发地点：键盘回车 = 提交（发起搜索），文本里不留换行。
    func testSearchFieldReturnSubmitsAndDropsTheLineBreak() {
        let result = VoiceTextFieldReturn.apply(to: "科技园\n", allowsLineBreaks: false, isTyping: true)
        XCTAssertEqual(result, .init(text: "科技园", submitted: true))
    }

    /// 出发地点补充描述（单行、没有提交动作）：回车收起键盘，文本里同样不留换行。
    func testPlainSingleLineFieldDropsTheLineBreak() {
        let result = VoiceTextFieldReturn.apply(to: "我在 A 口\n外侧等候", allowsLineBreaks: false, isTyping: true)
        XCTAssertEqual(result.text, "我在 A 口外侧等候")
    }

    /// 路线备注：本来就该多行，回车保留换行、不当提交。
    func testRouteNotesKeepTheLineBreak() {
        let result = VoiceTextFieldReturn.apply(to: "沿公园\n慢跑一圈", allowsLineBreaks: true, isTyping: true)
        XCTAssertEqual(result, .init(text: "沿公园\n慢跑一圈", submitted: false))
    }

    /// 语音填入：识别结果原样保留（没有换行时一个字不动），带了换行也只去掉、不替用户按「搜索」。
    func testVoiceInputIsNeverTreatedAsAReturnKeyPress() {
        XCTAssertEqual(
            VoiceTextFieldReturn.apply(to: "科技园地铁站 A 口", allowsLineBreaks: false, isTyping: false),
            .init(text: "科技园地铁站 A 口", submitted: false)
        )
        XCTAssertEqual(
            VoiceTextFieldReturn.apply(to: "科技园\n", allowsLineBreaks: false, isTyping: false),
            .init(text: "科技园", submitted: false)
        )
    }
}
