import XCTest
@testable import blindRun

/// 微信分享卡片的参数层（SPEC-D D2 的 iOS 侧）。
///
/// 这一组用例存在的理由：卡片的三个参数**在 SDK 接进来之前就已经定死了**，而它们各自
/// 有一条不看官方文档就会写错的硬约束 ——
///
/// - 字节不是字符（中文一字 3 字节），按 `count` 截会超限，按 `Data` 硬切会切碎汉字
/// - 朋友圈**只显示 title**，标题不能依赖描述补语境
/// - 缩略图会出现在**聊天列表预览**里，可见范围比分享页本身更大，所以里面绝不能有位置
///
/// 资质（真官网 + 备案主体一致）办下来之前一行 SDK 代码都跑不了，但这三条现在就能验。
final class WeChatShareCardTests: XCTestCase {

    // MARK: - 字节截断

    /// 按 `String.count` 截是错的：171 个中文字就超 512 字节了。
    func testTruncationCountsUTF8BytesNotCharacters() {
        let text = String(repeating: "跑", count: 200)   // 600 字节
        let truncated = WeChatShareCard.truncatedByBytes(text, limit: 512)
        XCTAssertLessThanOrEqual(truncated.utf8.count, 512)
        XCTAssertEqual(truncated.count, 170, "512 / 3 = 170 个汉字")
    }

    /// 按字节硬切会把一个汉字切成两半，微信收到的是无法解码的字节 ——
    /// 表现是标题整条丢失，不是显示半个字。截断后必须仍是合法字符串。
    func testTruncationNeverSplitsAMultibyteCharacter() {
        let text = "助盲跑陪跑行程"
        // 10 字节切不下第 4 个汉字（3×4 = 12 > 10）
        let truncated = WeChatShareCard.truncatedByBytes(text, limit: 10)
        XCTAssertEqual(truncated, "助盲跑")
        XCTAssertEqual(truncated.utf8.count, 9)
    }

    func testTruncationLeavesShortTextAlone() {
        XCTAssertEqual(WeChatShareCard.truncatedByBytes("助盲跑", limit: 512), "助盲跑")
    }

    func testZeroLimitProducesEmptyStringRatherThanCrashing() {
        XCTAssertEqual(WeChatShareCard.truncatedByBytes("助盲跑", limit: 0), "")
    }

    // MARK: - 标题必须能独立成立

    /// 朋友圈场景**只显示 title，不显示 description**。标题里没有「助盲跑」和「陪跑行程」，
    /// 朋友圈里就是一条没有来源的链接。
    func testTitleStandsOnItsOwnBecauseMomentsHidesTheDescription() {
        let title = WeChatShareCard.title(maskedName: "张*")
        XCTAssertTrue(title.contains("助盲跑"))
        XCTAssertTrue(title.contains("陪跑行程"))
    }

    func testTitleWorksWithoutAName() {
        let title = WeChatShareCard.title(maskedName: nil)
        XCTAssertTrue(title.contains("助盲跑"))
        XCTAssertTrue(title.contains("陪跑行程"))
    }

    /// 卡片 UI 只显示一行（约 10–20 字）。字节上限 512 不是瓶颈，这条防的是排版。
    func testTitleStaysWithinOneRenderedLine() {
        let title = WeChatShareCard.title(maskedName: "张*")
        XCTAssertLessThanOrEqual(title.count, 20)
        XCTAssertLessThanOrEqual(title.utf8.count, WeChatShareCard.titleByteLimit)
    }

    /// 姓名字段异常长时标题也不能撑爆字节上限。
    func testAbsurdlyLongNameStillFitsTheByteLimit() {
        let title = WeChatShareCard.title(maskedName: String(repeating: "长", count: 400))
        XCTAssertLessThanOrEqual(title.utf8.count, WeChatShareCard.titleByteLimit)
    }

    // MARK: - 描述

    func testDescriptionFitsTwoRenderedLines() {
        XCTAssertLessThanOrEqual(WeChatShareCard.description.count, 60)
        XCTAssertLessThanOrEqual(
            WeChatShareCard.description.utf8.count,
            WeChatShareCard.descriptionByteLimit
        )
    }

    /// `guard.mjs` 的 `sos-copy` 红线：分享面板的完成回调只代表用户选了一个目标应用，
    /// 不代表对方收到了。卡片描述同样不许写成完成时。
    func testDescriptionNeverClaimsDelivery() {
        for word in ["已通知", "已发送", "已送达", "已收到"] {
            XCTAssertFalse(
                WeChatShareCard.description.contains(word),
                "卡片描述不得宣称送达：\(word)"
            )
        }
    }

    // MARK: - 姓名掩码

    func testFullNameIsMaskedBeforeItEntersTheCard() {
        XCTAssertEqual(WeChatShareCard.maskedName("张伟"), "张*")
        XCTAssertEqual(WeChatShareCard.maskedName("欧阳建国"), "欧***")
    }

    /// 单字姓名不能原样透出去 —— 掩码位至少一个。
    func testSingleCharacterNameStillGetsAMaskCharacter() {
        XCTAssertEqual(WeChatShareCard.maskedName("张"), "张*")
    }

    func testBlankNameProducesNil() {
        XCTAssertNil(WeChatShareCard.maskedName("   "))
        XCTAssertNil(WeChatShareCard.maskedName(nil))
    }

    // MARK: - 卡片正文的隐私边界

    /// 🔴 卡片会出现在**聊天列表预览**里：不用点开、不用有链接，同一个群里的人扫一眼就看到。
    /// 所以未掩码姓名、起终点地址、手机号一律不进卡片 —— 这条比分享页本身的可见范围更宽。
    func testPayloadCarriesNoUnmaskedNameAndNoAddress() {
        let payload = WeChatShareCard.payload(
            shareURL: "https://example.com/share.html#tok",
            runnerName: "张伟"
        )
        let visibleText = payload.title + payload.description
        XCTAssertFalse(visibleText.contains("张伟"), "未掩码姓名进了卡片")
        XCTAssertTrue(payload.title.contains("张*"))
        for address in ["奥体中心", "南门", "路", "号"] {
            XCTAssertFalse(visibleText.contains(address), "地址片段进了卡片：\(address)")
        }
    }

    /// 令牌在 fragment 里而不是 query 是后端刻意的（fragment 不进 `Referer`、
    /// 不上服务端访问日志，而分享页要加载高德 JS SDK 这个第三方脚本）。
    /// 「让链接更规整」地改写它，等于把一个免登录凭据交给第三方脚本和一路上的日志。
    func testShareURLIsCarriedVerbatim() {
        let url = "https://blindrun.example.com/share.html#7cV3nQ8pR2sT5uW9xY0zA1bC4dE6fG8hJ0kL2mN4oP6"
        let payload = WeChatShareCard.payload(shareURL: url, runnerName: nil)
        XCTAssertEqual(payload.webpageURL, url)
    }

    // MARK: - 缩略图素材

    /// `thumbData` 上限 32 KB。素材是提交进仓库的静态文件，所以这条在**提交时**就该成立，
    /// 不靠运行时压缩循环 —— 我们从不用网络图，压缩循环没有输入。
    ///
    /// 走资源目录而不是 `Assets.xcassets`：asset catalog 会在构建期重新压缩，
    /// 字节数不可预测，这条断言就失去意义了。
    func testBundledThumbnailFitsTheThirtyTwoKilobyteLimit() throws {
        let data = try XCTUnwrap(
            WeChatShareCard.thumbnailData(bundle: Bundle(for: Self.self))
                ?? WeChatShareCard.thumbnailData(),
            "缩略图素材没打进 bundle：检查 blindRun/Resources/WeChatShareThumbnail.jpg"
        )
        XCTAssertLessThanOrEqual(data.count, WeChatShareCard.thumbnailByteLimit)
        XCTAssertGreaterThan(data.count, 0)
    }

    /// JPEG 魔数。素材被换成 PNG 或被工具链改写时这条会红 ——
    /// 微信对 `thumbData` 的格式要求不含 PNG 的全部特性，别在真机联调时才发现。
    func testBundledThumbnailIsAJPEG() throws {
        let data = try XCTUnwrap(
            WeChatShareCard.thumbnailData(bundle: Bundle(for: Self.self))
                ?? WeChatShareCard.thumbnailData()
        )
        XCTAssertEqual(Array(data.prefix(3)), [0xFF, 0xD8, 0xFF], "不是 JPEG")
    }
}
