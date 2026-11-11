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
    ///
    /// ⚠️ **按 UTF-16 计，不是按 `String.count`。** 后端那个 `maxLength` 由 Bean Validation
    /// 的 `@Size` 判，数的是 Java `String.length()` = UTF-16 code unit；而 Swift 的 `count`
    /// 数的是字素簇 —— 一个 emoji 在 Swift 里是 1，在 Java 里是 2。用 `count` 拦，
    /// 正好在「用户打了一堆表情」这一种输入上把闸放空，而那时后端仍会 400，
    /// 这道闸存在的理由（别让他白打一遍）就没了。
    static let maxContentLength = 1000

    /// 按后端口径数这段文字有多长。计数口径只在这里写一次 ——
    /// 校验与「还能写几个字」用同一个函数，否则会出现「提示还剩 3 个字、提交却被拦」。
    static func length(of text: String) -> Int { text.utf16.count }

    /// `nil` = 这条工单不该被发出去（正文只有空白）。
    ///
    /// 做成可失败构造而不是在视图里 `if` 一下：视图里那个 `if` 谁都验不了，
    /// 而「空正文提交成功」在屏幕上和正常提交长得一模一样 —— 用户以为说完了，客服收到一张空单。
    init?(category: SupportTicketCategory, content: String, orderId: Int64?) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard Self.length(of: trimmed) <= Self.maxContentLength else { return nil }
        self.category = category
        self.content = trimmed
        self.orderId = orderId
    }
}

// MARK: - 我的工单（`GET /api/support/tickets`，契约 operationId `listMine`）

/// 工单状态。**响应向枚举**：后端往里加值时解成 `.unknown`，不许让整页列表读不出来
/// （`AGENTS.md`「枚举解码遇未知值不许整条崩」）。
nonisolated enum SupportTicketStatus: String, Sendable, Equatable {
    case open = "OPEN"
    case replied = "REPLIED"
    case closed = "CLOSED"
    case unknown = "UNKNOWN"

    init(rawValueOrUnknown raw: String?) {
        self = raw.flatMap(SupportTicketStatus.init(rawValue:)) ?? .unknown
    }
}

/// 列表里的一条。只取这一页要显示的字段；`category`、`orderId`、举报相关字段都不解码。
///
/// 每个字段都宽容：一项形状不对只丢这一项（外层 `SkippingUndecodable`），
/// 一个字段形状不对不连累整条 —— 用户最想看的是「客服回了什么」，不是整页报错。
nonisolated struct SupportTicketSummary: Decodable, Sendable, Equatable, Identifiable {
    let id: Int64
    let content: String
    let status: SupportTicketStatus
    /// 未回复时为 null（契约）。空白串按没有回复处理。
    let csReply: String?
    let createdAt: String?
    let repliedAt: String?

    init(
        id: Int64,
        content: String,
        status: SupportTicketStatus,
        csReply: String? = nil,
        createdAt: String? = nil,
        repliedAt: String? = nil
    ) {
        self.id = id
        self.content = content
        self.status = status
        self.csReply = csReply
        self.createdAt = createdAt
        self.repliedAt = repliedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, content, status, csReply, createdAt, repliedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // `id` 是唯一不能缺的：没有它这一行既没法去重也没法区分，宁可整条跳过。
        id = try container.decode(Int64.self, forKey: .id)
        content = (try? container.decodeIfPresent(String.self, forKey: .content)) ?? ""
        status = SupportTicketStatus(
            rawValueOrUnknown: try? container.decodeIfPresent(String.self, forKey: .status)
        )
        csReply = (try? container.decodeIfPresent(String.self, forKey: .csReply))?.nilIfBlank
        createdAt = try? container.decodeIfPresent(String.self, forKey: .createdAt)
        repliedAt = try? container.decodeIfPresent(String.self, forKey: .repliedAt)
    }

    /// 有客服回复文字才算「已回复」。状态说 `REPLIED` 而回复为空，或反过来，都以文字为准 ——
    /// 用户看到的是那一段字，状态只是标签。
    var hasReply: Bool { csReply != nil }
}

/// `PageSupportTicketResponse`，只取 `content`。
nonisolated struct SupportTicketPage: Decodable, Sendable, Equatable {
    let content: [SupportTicketSummary]

    init(content: [SupportTicketSummary]) {
        self.content = content
    }

    private enum CodingKeys: String, CodingKey { case content }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = (try container.decodeIfPresent(SkippingUndecodable<SupportTicketSummary>.self, forKey: .content))?
            .wrappedValue ?? []
    }
}

// MARK: - 文案

enum SupportTicketCopy {
    /// 「我的」页的入口名、工单页标题、其他文案里指向它的名字，**都是这一个常量**。
    /// 2026-11-04 之前它叫「上报问题」，而 App 里别处都写「联系客服」，用户找不到名字对得上的入口（#656）。
    static let title = "联系客服"
    static let settingsHint = "账号或使用上的问题都可以写给客服"
    static let prompt = "说说发生了什么"
    /// 🔴 时效必须在写字之前就说清楚。工单不是求助，而「联系客服」这四个字
    /// 在一个刚结束陪跑、心里有事的人看来，很容易被当成「有人会马上来处理」。
    ///
    /// 🔴 **不承诺任何回复时限**（负责人 2026-11-04 定）：不写具体时间，不写「尽快」「马上」「回拨」。
    /// 后端 blind-run-backend#899 还没定谁来看工单，写了就是空头承诺。
    static let notice = "如果现在有危险，请直接拨打 120 或 110。"
    static let submit = "提交"
    static let submitted = "已收到你的反馈"
    static let emptyContent = "写一句发生了什么再提交"
    static func tooLong(limit: Int) -> String { "最多 \(limit) 个字，请精简一下" }
    static let failed = "提交失败，检查网络后再试一次"
    static func remaining(_ count: Int) -> String { "还能写 \(count) 个字" }

    // MARK: 我的工单

    static let myTicketsTitle = "我的工单"
    static let myTicketsHint = "查看你提交过的反馈，以及客服的回复"
    static let myTicketsLoading = "正在读取你的工单"
    static let myTicketsEmpty = "你还没有提交过工单。"
    static let myTicketsFailed = "没有读到你的工单，检查网络后再试一次"
    static let retry = "重试"
    /// 没回复时不写「会回复你」「请等待」：不承诺。
    static let noReplyYet = "暂时没有回复"
    static let replyLabel = "客服回复"
    static let yourWordsLabel = "你写的"

    /// 一行上显示的状态。**以有没有回复文字为准**：状态说 `REPLIED` 而回复是空白时，
    /// 不能一行里既写「已回复」又写「暂时没有回复」。
    static func displayStatus(_ ticket: SupportTicketSummary) -> String {
        if ticket.status == .replied, !ticket.hasReply { return statusLabel(.open) }
        return statusLabel(ticket.status)
    }

    static func statusLabel(_ status: SupportTicketStatus) -> String {
        switch status {
        case .open: return "已收到"
        case .replied: return "已回复"
        case .closed: return "已关闭"
        case .unknown: return "状态未知"
        }
    }

    /// 一行读屏文案：状态、时间、你写的、客服回复，一次读完。
    static func rowAccessibilityLabel(_ ticket: SupportTicketSummary, time: String?) -> String {
        var parts = [displayStatus(ticket)]
        if let time { parts.append(time) }
        if !ticket.content.isEmpty { parts.append("\(yourWordsLabel)：\(ticket.content)") }
        parts.append(ticket.csReply.map { "\(replyLabel)：\($0)" } ?? noReplyYet)
        return parts.joined(separator: "。")
    }
}
