import Foundation

// MARK: - 事后工单（`POST /api/support/tickets`）

/// 工单分类。**请求向的闭合枚举**（客户端只发已知值），所以这里**没有** `.unknown` ——
/// 「未知枚举值不许整条崩」那条红线管的是**响应**里冒出来的新值，
/// 而这个类型永远不参与解码后端下发的内容。
///
/// 契约对取值少而粗有一句解释，抄在这里免得下次有人「顺手」加细分：
/// 分类是给客服**分流**用的，不是给用户做选择题 —— 每多一个选项，
/// 读屏用户提交一次投诉就多听一句。
enum SupportTicketCategory: String, Codable, Sendable {
    case orderService = "ORDER_SERVICE"
    case safety = "SAFETY"
    case account = "ACCOUNT"
    case appIssue = "APP_ISSUE"
    case other = "OTHER"
}

/// 🚨 **这不是紧急求助。** 契约在端点 description 上逐字写着：
/// 工单是「事后有异议」，可以慢；「现在有危险」走 `/api/emergency/*`，
/// 两条路的时效差着一个数量级，**客户端文案不得把用户从 SOS 引到这里**。
struct SupportTicketRequest: Codable, Sendable, Equatable {
    let category: SupportTicketCategory
    let content: String
    /// 可空。给了就必须是自己的订单，否则后端 404。
    let orderId: Int64?

    /// 契约 `maxLength: 1000`。
    ///
    /// 客户端在**提交前**就把它拦住，而不是等后端 400：这一屏多半是在路边写的，
    /// 打了一千多字再被退回来，那些字就没了。
    static let maxContentLength = 1000

    /// `nil` = 这条工单不该被发出去（正文只有空白）。
    ///
    /// 做成可失败构造而不是在视图里 `if` 一下：视图里那个 `if` 谁都验不了，
    /// 而「空正文提交成功」在屏幕上和正常提交长得一模一样 —— 用户以为说完了，客服收到一张空单。
    init?(category: SupportTicketCategory, content: String, orderId: Int64?) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count <= Self.maxContentLength else { return nil }
        self.category = category
        self.content = trimmed
        self.orderId = orderId
    }
}

// MARK: - 文案

enum SupportTicketCopy {
    static let title = "上报问题"
    static let prompt = "说说发生了什么"
    /// 🔴 时效必须在写字之前就说清楚。工单不是求助，而「上报问题」这四个字
    /// 在一个刚结束陪跑、心里有事的人看来，很容易被当成「有人会马上来处理」。
    static let notice = "这是事后反馈，不会立刻有人联系你。如果现在有危险，请直接拨打 120 或 110。"
    static let submit = "提交"
    static let submitted = "已收到你的反馈"
    static let emptyContent = "写一句发生了什么再提交"
    static func tooLong(limit: Int) -> String { "最多 \(limit) 个字，请精简一下" }
    static let failed = "提交失败，检查网络后再试一次"
    static func remaining(_ count: Int) -> String { "还能写 \(count) 个字" }
}
