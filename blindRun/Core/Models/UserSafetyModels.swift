import Foundation

// MARK: - 举报（`POST /api/reports`）

/// 举报原因。**请求向的闭合枚举**：取值与契约 `ReportRequest.reason` 逐字一致，客户端不加细分。
/// 响应里的 `reportReason` 不解码（`UserReportTicket` 只取 `id`），所以这里不需要 `.unknown`。
nonisolated enum UserReportReason: String, Codable, CaseIterable, Sendable {
    case harassment = "HARASSMENT"
    case unsafeBehavior = "UNSAFE_BEHAVIOR"
    case falseInfo = "FALSE_INFO"
    case other = "OTHER"

    var displayName: String {
        switch self {
        case .harassment: return "骚扰"
        case .unsafeBehavior: return "不安全行为"
        case .falseInfo: return "虚假信息"
        case .other: return "其他"
        }
    }
}

/// 🚨 **这不是紧急求助**（契约端点 description）：现在有危险走 `/api/emergency/*`。
nonisolated struct UserReportRequest: Encodable, Sendable, Equatable {
    let targetUserId: Int64
    let reason: UserReportReason
    let orderId: Int64?
    let messageId: Int64?
    let detail: String?

    /// 契约 `maxLength: 1000`，计数口径同 `SupportTicketRequest`（UTF-16，与 Java `String.length()` 一致）。
    static let maxDetailLength = 1000

    static func length(of text: String) -> Int { text.utf16.count }

    /// `nil` = 补充说明超长，这条举报不该发出去。空白说明按没写处理，后端收到的是缺键。
    init?(target: CounterpartSafetyTarget, reason: UserReportReason, detail: String) {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.length(of: trimmed) <= Self.maxDetailLength else { return nil }
        self.targetUserId = target.userId
        self.reason = reason
        self.orderId = target.orderId
        self.messageId = target.messageId
        self.detail = trimmed.isEmpty ? nil : trimmed
    }
}

/// `POST /api/reports` 的 201 响应是整张工单，客户端只用工单号。
///
/// 宽容解码：举报已经成功，`id` 形状不对也不许让用户以为没提交。
nonisolated struct UserReportTicket: Decodable, Sendable, Equatable {
    @LenientOptionalInt64 var id: Int64?
}

// MARK: - 拉黑（`/api/users/{userId}/block`、`GET /api/users/blocked`）

/// `GET /api/users/blocked` 的一项。只列我拉黑的人，**谁拉黑了我任何接口都不下发**。
nonisolated struct BlockedUserResponse: Decodable, Sendable, Equatable, Identifiable {
    let userId: Int64
    /// 后端掩码（`张*`）；注销等情况下可空。
    let maskedName: String?
    @LenientOptionalString var blockedAt: String?

    var id: Int64 { userId }

    var displayName: String { maskedName?.nilIfBlank ?? UserSafetyCopy.unknownPerson }
    var spokenName: String { maskedName?.nilIfBlank?.unmaskedForSpeech ?? UserSafetyCopy.unknownPerson }
}

// MARK: - 举报与拉黑的目标

/// 一个举报或拉黑入口指向谁。只能由 `CounterpartSafetyGate` 造出来，视图里不判条件。
struct CounterpartSafetyTarget: Equatable, Sendable {
    let userId: Int64
    let orderId: Int64?
    /// 只有举报留言时有值。
    let messageId: Int64?
    /// 举报留言时原样显示给举报人看，确认举报的是哪一句。
    let quotedText: String?
}

/// 入口显示的全部判定。
///
/// 🚨 `counterpartUserId` **只传给举报和拉黑**（契约 `OrderDetailResponse.counterpartUserId`）：
/// 不拼展示文案、不拨号，也不用它有没有值判断任何别的事。
enum CounterpartSafetyGate {
    /// `nil` = 不显示入口。后端没给 id 时绝不显示后再报错，也绝不换别的字段顶替。
    static func target(userId: Int64?, orderId: Int64?) -> CounterpartSafetyTarget? {
        guard let userId, userId > 0 else { return nil }
        return CounterpartSafetyTarget(userId: userId, orderId: orderId, messageId: nil, quotedText: nil)
    }

    /// 订单页的入口。跑步中这一屏只留求助（`design-direction.md` §6），跑完在完成页和记录页举报。
    static func orderPageTarget(_ order: OrderDetailResponse) -> CounterpartSafetyTarget? {
        guard order.status != .inProgress else { return nil }
        return target(userId: order.counterpartUserId, orderId: order.orderId)
    }

    /// 这条留言能不能举报。只有对方写的才能（契约：`messageId` 须是对方写的），角色认不出时不放。
    static func messageTarget(
        messageId: Int64,
        fromRole: RunRecordRole,
        text: String?,
        viewerRole: RunRecordRole,
        counterpart: CounterpartSafetyTarget?
    ) -> CounterpartSafetyTarget? {
        guard let counterpart,
              viewerRole != .unknown,
              fromRole != .unknown,
              fromRole != viewerRole else { return nil }
        return CounterpartSafetyTarget(
            userId: counterpart.userId,
            orderId: counterpart.orderId,
            messageId: messageId,
            quotedText: text?.nilIfBlank
        )
    }
}

// MARK: - 文案

/// 账号停用的提示。四件事都要说到：发生了什么、为什么、能做什么、谁能帮。
enum AccountSuspensionCopy {
    /// 后端 message 已经说了「不能下单或接单」和「仍可紧急求助」，这里补另外两件。
    static let supplement = "这是平台对账号的限制，不是这次操作出了错。想了解原因或有异议，可以在「我的」页的「联系客服」里留言。"
    static let fallback = "你的账号已被平台限制，暂时不能下单或接单。遇到危险仍可以使用紧急求助。\(supplement)"
    /// 陪跑员首页滑块下面那一句。
    static let dispatchNotice = "账号已被平台限制。想了解原因，可以在「我的」页的「联系客服」里留言"
}

enum UserSafetyCopy {
    static let reportTitle = "举报"
    static let reportMessageTitle = "举报这条留言"
    static let reportHint = "向客服说明发生了什么，对方不会知道"
    static let reportMessageHint = "举报上面这条留言，对方不会知道"
    /// 🔴 时效要在写字之前说清楚：举报不是求助。这一句只说事实，不放任何求助按钮。
    static let reportNotice = "举报由客服事后处理，不会立刻有人联系你，对方也不会知道。如果现在有危险，请直接拨打 120 或 110。"
    static let reasonPrompt = "选择举报原因"
    static let detailPrompt = "补充说明，选填"
    static let reasonRequired = "先选一个举报原因再提交。"
    static func detailTooLong(limit: Int) -> String { "补充说明最多 \(limit) 个字，请精简一下。" }
    static func remaining(_ count: Int) -> String { "还能写 \(count) 个字" }
    static let submitReport = "提交举报"
    static let reportFailed = "举报没有提交，请检查网络后再试一次。"
    static let done = "知道了"
    static let close = "关闭"

    static func reportSubmitted(ticketId: Int64?) -> String {
        let number = ticketId.map { "，工单号 \($0)" } ?? ""
        return "举报已提交\(number)。客服回复后你会收到通知。"
    }

    static func quoted(_ text: String) -> String { "你要举报的留言：\(text)" }

    static let blockTitle = "不再匹配此人"
    static let blockHint = "之后不再和对方匹配，需要再次确认"
    static let blockConfirmTitle = "不再匹配此人？"
    static func blockConfirmTitle(_ name: String) -> String { "不再匹配\(name)？" }
    static func blockLabel(_ name: String) -> String { "不再匹配\(name)" }
    static let blockConfirmAction = "不再匹配"
    static let cancel = "取消"
    static let blockFailed = "没有设置成功，请检查网络后再试一次。"
    /// 操作人自己要知道结果和解除位置。这句话只在操作人这一端出现。
    static let blockSucceeded = "已设为不再匹配。可以在「我的」页的「已拉黑的人」里解除。"

    /// 🔴 后果写进正文：已成立的单照常进行，通话这一轮会结束，这两句都是后端行为。
    enum BlockContext: Equatable {
        case standard
        case introCall

        var confirmMessage: String {
            switch self {
            case .standard:
                return "确认后，你们之后不会再被匹配到一起，对方不会收到任何提示。已经约好的订单照常进行，从下一单起生效。可以在「我的」页的「已拉黑的人」里解除。"
            case .introCall:
                return "确认后，这一轮通话确认会结束，你们之后不会再被匹配到一起，对方不会收到任何提示。可以在「我的」页的「已拉黑的人」里解除。"
            }
        }
    }

    static let blockedListTitle = "已拉黑的人"
    static let blockedListHint = "查看你选择不再匹配的人，可以解除"
    /// 空态卡：标题 + 一句说明（#755 定稿）。
    static let blockedListEmptyTitle = "没有拉黑的人"
    static let blockedListEmptyDetail = "在订单或跑步记录里选「不再匹配此人」，对方就会出现在这里。"
    static let blockedListFootnote = "拉黑后不会再和对方匹配。解除前会再问你一次。"
    static let blockedListLoading = "正在加载已拉黑的人"
    static let blockedListFailed = "已拉黑的人加载失败，请检查网络后重试。"
    static let retry = "重试"
    static let unknownPerson = "这位用户"
    static func blockedAt(_ time: String) -> String { "拉黑于 \(time)" }
    static let unblockTitle = "解除"
    static func unblockLabel(_ name: String) -> String { "解除\(name)" }
    static let unblockHint = "解除后可能再次和对方匹配，需要再次确认"
    static let unblockConfirmTitle = "解除拉黑？"
    static let unblockConfirmMessage = "解除后，从下一单起你们可能再次被匹配到一起。之前撤回的邀请不会恢复。"
    static let unblockConfirmAction = "确认解除"
    static let unblockSucceeded = "已解除。从下一单起你们可能再次被匹配到一起。"
    static let unblockFailed = "没有解除成功，请检查网络后再试一次。"

    /// 对象不符合条件的 404。契约要求一句通用文案，不区分对方不存在、没有交集、订单或留言对不上。
    static let targetUnavailable = "现在无法完成这个操作。如果需要帮助，可以在「我的」页的「联系客服」里留言。"

    /// 举报和拉黑共用的失败文案选择。`fallback` 是网络类失败那一句。
    static func failureMessage(for error: APIError, fallback: String) -> String {
        if error.errorCode == .resourceNotFound { return targetUnavailable }
        switch error {
        case .serverError, .rateLimited: return error.localizedMessage
        default: return fallback
        }
    }
}
