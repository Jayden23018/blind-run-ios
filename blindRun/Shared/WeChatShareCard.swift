import Foundation

// MARK: - 为什么这个文件里没有 SDK 调用

/// 微信分享卡片的**参数层**。只有纯函数和一张静态图，**不含微信 SDK**。
///
/// **微信不读页面的 `og` 标签。** 后端 SPEC-D §D2.0 已从官方文档确认：`thumbData` 是二进制
/// 且**不接受 URL**，缩略图是 App 打包进请求的字节 ⇒ 卡片的标题、描述、缩略图三样
/// 全部由 iOS 侧 SDK 传参，与页面元信息无关。后端补的那组 `og` 标签是给**短信 / QQ /
/// iMessage / Telegram** 这些真的读 og 的渠道用的。
///
/// **SDK 现在接不进来，卡在资质不在代码。** 微信开放平台的移动应用要求：
/// ① 有一个真正的官网，官方原文明写「官网不支持提供手机端小程序、公众号和 H5 等页面类型」；
/// ② **官网域名的备案主体必须与开放平台认证主体一致**，不一致要提供双方盖章的授权书。
/// 项目挂靠学校 / 公益组织，这两条是运营要办的事。办下来之前：
///
/// - 分享继续走 `ShareLinkSheet`（`UIActivityViewController`）发纯链接。用户仍能发到微信，
///   只是没有卡片预览。**这不是降级占位，是当前唯一合规可用的路径。**
/// - 这个文件里的参数与素材先备好并被单测钉住。资质下来后接 SDK 就是接线，
///   不用再重新决定标题该多长、缩略图能不能带地图。
///
/// ⚠️ 不要在这里加 `import WechatOpenSDK` 或 `WXApi` 调用：没有 AppID 与 Universal Link，
/// 那段代码一行都跑不了、也测不了，只会变成一段没人能验证的死代码。
enum WeChatShareCard {

    // MARK: - 官方硬上限（developers.weixin.qq.com 移动应用开发手册，核于 2026-08-13）

    /// `title` 的字节上限。**字节不是字符** —— 中文一个字 3 字节。
    static let titleByteLimit = 512

    /// `description` 的字节上限。
    static let descriptionByteLimit = 1024

    /// `thumbData` 的字节上限。新版 SDK 的日志显示或已放宽到 128 KB，
    /// 但旧客户端仍按 32 KB 卡，所以按 32 KB 备素材。
    static let thumbnailByteLimit = 32 * 1024

    /// 缩略图在卡片右侧按 1:1 展示，官方建议 300×300。
    static let thumbnailSide = 300

    // MARK: - 文案

    /// 卡片标题。
    ///
    /// 🔴 **必须能独立说清这是什么** —— 朋友圈场景**只显示 title，不显示 description**。
    /// 一个只写「实时位置」的标题在朋友圈里就是一条没有来源的链接。
    ///
    /// 卡片 UI 只显示一行（约 10–20 字），所以这句要短。字节上限 512 远不是瓶颈，
    /// 截断逻辑防的是姓名字段异常长时把这一行撑爆。
    static func title(maskedName: String?) -> String {
        let name = maskedName?.nilIfBlank
        let raw = name.map { "助盲跑 · \($0)的陪跑行程" } ?? "助盲跑 · 实时陪跑行程"
        return truncatedByBytes(raw, limit: titleByteLimit)
    }

    /// 卡片描述。卡片 UI 只显示两行（约 40–60 字）。
    ///
    /// 说清三件事：现在在跑、点开能看到什么、链接会失效。
    /// **不说「已通知」「家人已收到」** —— 那是 `guard.mjs` 的 `sos-copy` 红线，
    /// 分享面板的完成回调只代表用户选了一个目标应用，不代表对方收到了。
    static let description = "点开可以看到实时位置和跑步轨迹。链接会在行程结束后失效。"

    /// 卡片正文里绝不能出现的东西。
    ///
    /// 卡片会出现在**聊天列表预览**里 —— 可见范围比页面本身更大：不用点开、不用有链接，
    /// 同一个群里的所有人扫一眼列表就看到了。所以起终点地址、未掩码姓名、手机号一律不进卡片。
    /// 这与后端给 `og` 标签定的边界是同一条（SPEC-D §D2.1）。
    static func maskedName(_ fullName: String?) -> String? {
        guard let name = fullName?.nilIfBlank else { return nil }
        guard let first = name.first else { return nil }
        return String(first) + String(repeating: "*", count: max(1, name.count - 1))
    }

    // MARK: - 缩略图

    static let thumbnailResourceName = "WeChatShareThumbnail"
    static let thumbnailResourceExtension = "jpg"

    /// 🔴 **静态品牌图，绝不动态生成含地图的缩略图。**
    ///
    /// 动态生成一张带轨迹或当前位置的缩略图，等于把盲人的位置烧进一张会出现在
    /// **聊天列表预览**里的公开图片 —— 那张图的可见范围比分享页本身更大，
    /// 而分享页至少还有令牌和 2 小时 TTL 挡着，图片一旦发出去就永远在那条会话里。
    ///
    /// 读的是 bundle 里的原始字节，不是 `UIImage` 再编码：`thumbData` 要的就是二进制，
    /// 而且原始字节的大小是提交时就确定的，可以被测试钉死（走资源目录而不是
    /// `Assets.xcassets`，正是因为 asset catalog 会在构建期重新压缩，字节数不可预测）。
    static func thumbnailData(bundle: Bundle = .main) -> Data? {
        guard let url = bundle.url(
            forResource: thumbnailResourceName,
            withExtension: thumbnailResourceExtension
        ) else { return nil }
        return try? Data(contentsOf: url)
    }

    // MARK: - 组装

    /// 卡片的全部参数。SDK 接进来后，这个结构原样喂给 `WXMediaMessage` + `WXWebpageObject`。
    struct Payload: Equatable {
        let title: String
        let description: String
        let webpageURL: String
        /// `nil` 表示素材缺失。此时**不要退化成无缩略图分享**，走 `ShareLinkSheet` 发纯链接：
        /// 微信对无缩略图的网页卡片行为不一致，宁可用一条确定可用的路径。
        let thumbnailData: Data?
    }

    /// ⚠️ `webpageURL` 必须**原样**用后端返回的 `shareUrl`，一个字符都不许改写。
    /// 令牌在 fragment 里（`.../share.html#<token>`）而不是 query，是后端刻意的：
    /// fragment 不进 `Referer`、不上服务端访问日志，而分享页要加载高德 JS SDK 这个第三方脚本。
    /// 详见 `RunPlanLiveShareMessage.compose` 上方那段。
    static func payload(
        shareURL: String,
        runnerName: String?,
        bundle: Bundle = .main
    ) -> Payload {
        Payload(
            title: title(maskedName: maskedName(runnerName)),
            description: truncatedByBytes(description, limit: descriptionByteLimit),
            webpageURL: shareURL,
            thumbnailData: thumbnailData(bundle: bundle)
        )
    }

    // MARK: - 字节截断

    /// 按 **UTF-8 字节数**截断，且不切开一个多字节字符。
    ///
    /// 按 `String.count` 截是错的：中文一个字 3 字节，171 个中文字就超 512 字节了。
    /// 而按字节直接切 `Data` 会把一个汉字切成两半 —— 微信收到的是一段无法解码的字节，
    /// 表现是标题整条丢失，不是显示半个字。
    static func truncatedByBytes(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        guard text.utf8.count > limit else { return text }
        var result = ""
        var used = 0
        for character in text {
            let size = String(character).utf8.count
            if used + size > limit { break }
            result.append(character)
            used += size
        }
        return result
    }
}
