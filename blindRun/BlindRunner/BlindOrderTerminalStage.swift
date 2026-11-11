import Foundation

// MARK: - 订单页 v7 终态：已取消 / 暂无陪跑员（#946，定稿 `docs/ui/mockups/blind-order-terminal-v7-20261111/`）
//
// 与 ①–④ 同一个外壳（深色头 + 白色抽屉 + 竖线），竖线停在中断那一步，后面的步不画。
// 负责人 11-11 去掉了说明卡（原话「这种没必要的说明把它给去掉」），所以这里没有卡片内容。

enum BlindOrderTerminalCopy {
    static let backHome = "返回首页"
    static let backHomeHint = "回到首页"
    static let noVolunteerTitle = "这次没找到陪跑员"
    /// 暂无陪跑员那一步的小字。接 `blindRunnerDescription` 里的同一个原因，换成短句。
    static let noVolunteerDetail = "没有匹配到可用的陪跑员"
    static let cancelledFallbackTitle = "这次约跑已取消"

    nonisolated static func cancelledTitle(start: String) -> String { "\(start) 的约跑已取消" }
}

/// 订单页在「还没拿到订单 / 终态 / 未知态」三种情况下走哪一支（#946）。其余状态返回 `.stateful`，
/// 由 ①–④、⑤–⑧、骨架各自的判定接手。单测钉住：订单为空不许回到只读退路，`.unknown` 必须留在只读退路。
enum BlindOrderPageFallback: Equatable {
    /// 订单还没拿到：v7 外壳 + 转圈。
    case loadingShell
    /// 已取消 / 暂无陪跑员：v7 终态页。
    case terminal
    /// 改版前那条只读列表。只剩 `.unknown`：后端加状态时它是唯一落点。
    case readOnly
    case stateful

    static func resolve(_ status: RunOrderStatus?) -> BlindOrderPageFallback {
        guard let status else { return .loadingShell }
        if status.usesBlindTerminalPage { return .terminal }
        return status == .unknown ? .readOnly : .stateful
    }
}

/// 终态页一屏的全部内容。**纯值**，单测在 `BlindOrderTerminalStageTests`。
struct BlindOrderTerminalPresentation: Equatable {
    let eyebrow: String
    let title: String
    let place: String?
    let when: String?
    /// `nil` = 还不知道停在哪一步（已取消但状态变更记录没拿到），不画竖线，不猜。
    let timeline: BlindOrderTimelineInput?

    var headerAccessibilityLabel: String {
        "\(eyebrow)。\(title)"
    }

    /// `nil` = 这一态不走终态页。
    static func make(
        order: OrderDetailResponse,
        logs: [OrderStatusLog],
        now: Date = Date()
    ) -> BlindOrderTerminalPresentation? {
        guard order.status.usesBlindTerminalPage else { return nil }
        let start = order.blindRunnerShortStartText(now: now)
        let title: String
        if order.status == .noVolunteer {
            title = BlindOrderTerminalCopy.noVolunteerTitle
        } else {
            title = start.map(BlindOrderTerminalCopy.cancelledTitle(start:)) ?? BlindOrderTerminalCopy.cancelledFallbackTitle
        }
        let timeline = stoppedStep(status: order.status, logs: logs).map { step in
            BlindOrderTimelineInput(
                position: .stopped(step),
                details: stoppedDetail(status: order.status, logs: logs).map { [step: $0] } ?? [:]
            )
        }
        return BlindOrderTerminalPresentation(
            eyebrow: order.status.displayName,
            title: title,
            place: BlindOrderStagePresentation.placeLine(order: order, includesMeetSpot: true),
            when: start,
            timeline: timeline
        )
    }

    /// 竖线停在哪一步。
    ///
    /// - 暂无陪跑员：恒为第 1 步（就是没找到人）。
    /// - 已取消：取状态变更记录里**最新一条**转成 `CANCELLED` 的那条的 `fromStatus`，映射到五步。
    ///   记录按时间倒序（`OrderStatusLog` 的注释），所以取第一条匹配的。拿不到、或前一态不在竖线上 ⇒ `nil`。
    ///   订单本身没有「从哪一态取消」的字段（后端 spec 只有 `cancelledBy` 写在日志 remark 里），所以只能读日志。
    static func stoppedStep(status: RunOrderStatus, logs: [OrderStatusLog]) -> BlindOrderTimelineStep? {
        switch status {
        case .noVolunteer:
            return .matchVolunteer
        case .cancelled:
            guard let from = cancellationLog(in: logs)?.fromStatus,
                  case .current(let step)? = from.blindOrderTimelinePosition else { return nil }
            return step
        case .pendingMatch, .pendingIntroCall, .scheduledConfirmed, .pendingAccept, .inProgress,
             .driverEnRoute, .driverArrived, .completed, .rematching, .unknown:
            return nil
        }
    }

    /// 中断那一步的小字：谁取消的（取日志现有译文 `displayText`，不另写一份）。
    /// remark 为空时 `displayText` 退成「已取消」，头部已经说过，不再重复。
    static func stoppedDetail(status: RunOrderStatus, logs: [OrderStatusLog]) -> String? {
        if status == .noVolunteer { return BlindOrderTerminalCopy.noVolunteerDetail }
        guard let log = cancellationLog(in: logs) else { return nil }
        let text = log.displayText
        return text == log.toStatus.displayName ? nil : text
    }

    private static func cancellationLog(in logs: [OrderStatusLog]) -> OrderStatusLog? {
        logs.first { $0.toStatus == .cancelled }
    }
}
