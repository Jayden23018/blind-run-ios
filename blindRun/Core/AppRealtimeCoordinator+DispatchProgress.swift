import Foundation

// MARK: - 派单进度（#949）
//
// `DISPATCH_STARTED` / `DISPATCH_EXPANDING` 以前走前台浮层队列。附近没人时后端在同一个事务里
// 瞬时扩完三轮，三条几乎同时到：浮层挡住订单页，点「关闭」又冒出下一条，三句连念互相切断。
//
// 负责人 2026-11-11 定：进度不弹浮层，写进订单页 ①「已等 N 分钟」那一行（原位替换）；
// 不说「第 N 轮」；读屏只念一连串里的最后一条。依据 HIG《Alerts》《Notifications》、
// Material Snackbar「一次一条」、WCAG 4.1.3（`docs/research/dispatch-progress-notice-20261111.md`）。

/// 一条派单进度播报。`id` 让视图层的闸门分得清「新的一条」与「订阅重建后重放的同一条」。
struct DispatchProgressAnnouncement: Equatable, Sendable {
    let id = UUID()
    let text: String
}

enum DispatchProgressCopy {
    /// 扩大范围那一句。后端原文带「（第N轮）」，用户用不上这个数。
    static let wideningSpeech = "附近暂时没有陪跑员，正在扩大范围找"
}

extension AppRealtimeCoordinator {
    static let dispatchStartedEventType = "DISPATCH_STARTED"
    static let dispatchExpandingEventType = "DISPATCH_EXPANDING"

    /// 派单进度事件的统一入口。返回 `true` = 已处理，调用方不再进浮层队列。
    ///
    /// - `speak`: 实时推送念；重连补读的是过去的进度，只更新那一行，不念。
    @discardableResult
    func routeDispatchProgress(
        eventType: String,
        orderID: Int64?,
        ttsText: String?,
        body: String,
        speak: Bool
    ) -> Bool {
        let widening: Bool
        switch eventType {
        case Self.dispatchStartedEventType: widening = false
        case Self.dispatchExpandingEventType: widening = true
        default: return false
        }
        if let resolved = resolveDispatchProgressOrderID(orderID) {
            // 新一次派单（含重新匹配）从 STARTED 开始，上一次的「扩大范围」不再成立。
            if widening {
                widenedDispatchOrderIDs.insert(resolved)
            } else {
                widenedDispatchOrderIDs.remove(resolved)
            }
        }
        guard speak else { return true }
        let text = widening ? DispatchProgressCopy.wideningSpeech : (ttsText?.nilIfBlank ?? body)
        scheduleDispatchProgressAnnouncement(text)
        return true
    }

    /// 模板推送的信封不带 `orderId`（后端 issue 已开）。不带时只在「正好一张单在匹配」时认得出是哪一单，
    /// 认不出就不写进任何一单的那一行（仍然念）—— 多张预约同时在等时，写错单比不写更糟。
    private func resolveDispatchProgressOrderID(_ orderID: Int64?) -> Int64? {
        if let orderID { return orderID }
        let matching = activeOrderStatuses.filter { BlindOrderStage.resolve($0.value) == .matching }
        return matching.count == 1 ? matching.first?.key : nil
    }

    /// 一连串进度只念最后一条：每来一条就重新计时，静下来 `dispatchProgressSettleDelay` 秒才念。
    private func scheduleDispatchProgressAnnouncement(_ text: String) {
        dispatchProgressTask?.cancel()
        let delay = dispatchProgressSettleDelay
        dispatchProgressTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.dispatchProgressAnnouncement = DispatchProgressAnnouncement(text: text)
        }
    }
}
