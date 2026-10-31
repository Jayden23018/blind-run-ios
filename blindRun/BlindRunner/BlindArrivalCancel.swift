import Foundation

// MARK: - 汇合态取消（后端 #682，iOS #395）

/// 跑者在汇合态（`DRIVER_ARRIVED`）那一行「取消本单」此刻是什么样子。
///
/// 只有跑者知道陪跑员到底在不在现场，这是给「陪跑员标了已到达、人却一直没出现」的出口。
/// 可取消的时刻由后端给（`OrderDetailResponse.earliestBlindCancelAt`），**客户端不自己拿到达时间加**。
///
/// 交互是项目负责人 2026-10-17 拍板的：没到点**置灰不可按**、读屏说出几点可以取消并建议先打电话；
/// 到点可按，走既有二次确认。不做「按下去再念 409 的 message」那一种 ——
/// 那等于让盲人每隔几分钟按一次来问「到了没有」。
enum BlindArrivalCancelGate: Equatable {
    /// 还没到点。`opensAt` 是「10:10」这样的钟点。
    case locked(opensAt: String)
    /// 可以取消。
    case open

    var isEnabled: Bool { self == .open }

    /// `nil` = 这一刻不出现这一行：不在汇合态，或后端没给时刻（它把这条出口关了）。
    ///
    /// 字段有值但解析不出 ⇒ `.open`：不锁，由后端判（按早了会 409 并念出时刻）。
    /// 与「开始跑步」的 `startRunOpensAt` 同一个口径。
    static func resolve(order: OrderDetailResponse, now: Date) -> Self? {
        guard order.status == .driverArrived,
              let raw = order.earliestBlindCancelAt?.nilIfBlank else { return nil }
        guard let opensAt = raw.backendTimestamp, now < opensAt else { return .open }
        return .locked(opensAt: DateFormatter.aidRunDisplayClock.string(from: opensAt))
    }

    /// 页面开着跨过可取消时刻时播的那一句。`nil` = 不播。
    ///
    /// 只认 `.locked → .open`：冷启动直接是 `.open` 不播（没有「刚刚变了」这件事），
    /// 每 5 秒一次的同态刷新不重播，订单离开汇合态（`→ nil`）也不播。
    static func unlockAnnouncement(from previous: Self?, to current: Self?) -> String? {
        guard case .locked = previous, current == .open else { return nil }
        return BlindArrivalCancelCopy.unlockedAnnouncement
    }
}

/// 这一行与它的朗读。**不在视图里写中文字面量**（同 `BlindRunCopy`）。
enum BlindArrivalCancelCopy {
    static let rowTitle = "取消本单"
    /// 置灰时行内第二行的小字，也是读屏标签的后半句。
    static func lockedDetail(opensAt: String) -> String { "\(opensAt) 之后可以取消，先给陪跑员打电话" }
    static func lockedAccessibilityLabel(opensAt: String) -> String { "\(rowTitle)，\(lockedDetail(opensAt: opensAt))" }
    static let openDetail = "陪跑员一直没出现时用"
    static let openAccessibilityLabel = "\(rowTitle)，\(openDetail)"
    static let openAccessibilityHint = "双击后会先确认一次"

    /// 二次确认弹窗的正文。不说「取消预约」—— 这一刻人已经到了集合点，取消的是一次见面。
    static let confirmationMessage = "确认取消本单？陪跑员会收到通知，此订单就结束了。"

    static let unlockedAnnouncement = "已经等满了。如果还没碰上陪跑员，现在可以取消本单。"

    /// 409 `BLIND_CANCEL_TOO_EARLY` 且后端 message 为空时的兜底。说不出时刻，所以把人引回那一行。
    static let tooEarlyFallback = "陪跑员刚到不久，还不能取消。请先打电话联系对方，到时间后「取消本单」会变成可按。"

    /// 跑者取消这一路撞上 409 `ORDER_HAS_ACTIVE_EMERGENCY`。
    ///
    /// `ErrorCode.orderHasActiveEmergency.localizedMessage` 是写给陪跑员「结束服务」的，
    /// 而且刻意不提撤销（撤销对陪跑员恒 403）。跑者本人有撤销权，所以这里说出这条路。
    static let activeEmergency = "此订单还有没结束的求助，现在还不能取消。可以先撤销求助，或者等客服处理完再取消。"
}
