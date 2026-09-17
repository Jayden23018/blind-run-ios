import XCTest
@testable import blindRun

/// 掩码姓名**不许进朗读通道**。
///
/// 后端下发的姓名一律掩码（`张*`，`NameMaskUtils.mask()`）。原样交给 VoiceOver 或 TTS
/// 会念成「张星号」—— 而本 App 的读屏是**外放**的，「星号」还会被周围的人当成名字的一部分。
///
/// 🔴 **这类缺陷在屏幕上完全看不出来**：念出来的东西不上屏，上屏的东西不被念。
/// 所以每条用例都同时钉两半 —— 念出来的**不含**星号、屏幕上那份**仍然含**星号。
/// 只钉前一半的话，「把可见文字也去掉星号」会全绿通过，而那是隐私方向反了的改动
/// （去星号之后看着像拿到了全名）。
final class MaskedNameSpeechTests: XCTestCase {

    // MARK: - 共享助手

    /// `String.unmaskedForSpeech` 本身。**全角 `＊` 单独钉一条** ——
    /// 后端换一次掩码字符，只处理半角的实现会静默漏掉一半，而屏幕上看不出区别。
    func testUnmaskedForSpeechDropsBothAsteriskWidths() {
        XCTAssertEqual("张*".unmaskedForSpeech, "张")
        XCTAssertEqual("欧阳**".unmaskedForSpeech, "欧阳")
        XCTAssertEqual("李＊".unmaskedForSpeech, "李")
        XCTAssertEqual("王＊*".unmaskedForSpeech, "王", "半角全角混在一起也要全去掉")
    }

    /// 没有星号的串必须**原样返回**，不是「顺手 trim 一下」以外的任何改写。
    ///
    /// 这条挡的是把它误用成通用清洗函数：它只负责去掩码占位符。
    func testUnmaskedForSpeechLeavesOrdinaryNamesAlone() {
        XCTAssertEqual("张伟".unmaskedForSpeech, "张伟")
        XCTAssertEqual("  张伟  ".unmaskedForSpeech, "张伟", "两端空白仍然要去掉")
    }

    /// 整个名字只剩星号时，去完就是空串 —— 调用方要能靠 `nilIfBlank` 落到兜底名。
    func testUnmaskedForSpeechCollapsesAnAllAsteriskNameToEmpty() {
        XCTAssertEqual("**".unmaskedForSpeech, "")
        XCTAssertNil("＊＊".unmaskedForSpeech.nilIfBlank, "全是星号时要能被 nilIfBlank 判空")
    }

    // MARK: - 固定搭档 / 火花列表

    /// `PartnerRow` 的两条通道。**两半一起断言**：可见留星号、念出来不留。
    ///
    /// 提到模型上而不是留在 `PartnerRowCard` 里，就是为了这条够得着 ——
    /// 视图里那两个属性是 `private`，规则错了没有任何东西会红。
    func testPartnerRowKeepsTheMaskOnScreenAndDropsItForSpeech() {
        let row = Self.partnerRow(name: "张*")

        XCTAssertEqual(row.displayName(fallback: "这位志愿者"), "张*", "屏幕上那份不许被改写")
        XCTAssertEqual(row.spokenName(fallback: "这位志愿者"), "张")
        XCTAssertNotEqual(
            row.displayName(fallback: "这位志愿者"),
            row.spokenName(fallback: "这位志愿者"),
            "两条通道取值必须不同，相同说明有一条走错了"
        )
    }

    /// 对方已注销（`name == nil`）与名字只剩星号，两边都要落到**同一个**兜底名。
    ///
    /// 只剩星号那一档是真实会发生的：单字姓名掩码之后就只有一个星号。
    func testPartnerRowFallsBackOnBothChannelsWhenThereIsNoUsableName() {
        for name in [nil, "", "  ", "*", "＊"] as [String?] {
            let row = Self.partnerRow(name: name)
            XCTAssertEqual(
                row.spokenName(fallback: PartnerStreakCopy.unknownBlindName),
                PartnerStreakCopy.unknownBlindName,
                "name = \(String(describing: name)) 时朗读通道没落到兜底名"
            )
        }
    }

    // MARK: - 志愿者端念盲人姓名

    /// 服务记录那一行的读屏标签。**这是一个真实调用点**，不是纯函数的重复检查 ——
    /// 把实现换回 `order.blindName` 原串，这条立刻红。
    func testVolunteerServiceRecordLabelNeverSpeaksTheMask() {
        let record = VolunteerServiceRecord(order: .preview(status: .completed))

        XCTAssertFalse(
            record.accessibilityLabel.contains("*"),
            "服务记录的读屏标签里还留着掩码星号，VoiceOver 会念出「星号」"
        )
        XCTAssertFalse(record.accessibilityLabel.contains("＊"), "全角星号同样不许进朗读通道")
        XCTAssertTrue(
            record.accessibilityLabel.contains("李"),
            "去星号不该把姓氏一起去掉 —— 那样读屏就不知道是谁了"
        )
    }

    /// 🔴 上一条的另一半：**渲染用的原串仍然带星号**。
    ///
    /// 没有这条，「把 `blindName` 本身在解码时就去掉星号」会让上一条全绿通过 ——
    /// 而那等于在屏幕上也抹掉了掩码。
    func testTheBlindRunnerNameStillCarriesItsMaskOnScreen() {
        let order = OrderDetailResponse.preview(status: .completed)
        XCTAssertEqual(order.blindName, "李*", "渲染用的原串不许被改写")
    }

    // MARK: - 兜底名本身

    /// 两个兜底常量自己**不能**含星号 —— 它们是朗读通道的终点。
    func testFallbackPlaceholdersAreThemselvesSpeakable() {
        for placeholder in [
            PartnerStreakCopy.unknownVolunteerName,
            PartnerStreakCopy.unknownBlindName
        ] {
            XCTAssertFalse(placeholder.contains("*"), "兜底名里有星号：\(placeholder)")
            XCTAssertFalse(placeholder.isEmpty, "兜底名不能是空串，否则读屏这一段整个消失")
        }
    }

    // MARK: - Helpers

    private static func partnerRow(name: String?) -> PartnerRow {
        PartnerRow(
            userId: 42,
            name: name,
            completedRunsTogether: 3,
            favoritedAt: nil,
            hasOptedOut: false,
            streak: nil,
            isFavorite: true
        )
    }
}
