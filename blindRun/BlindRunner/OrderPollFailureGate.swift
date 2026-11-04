import Foundation

/// 订单页轮询失败的播报闸（#659，审计 F-9）。
///
/// 订单页每 5 秒拉一次。跑步中进地下通道时每一轮都失败，原来每次都 `speakError` 并震动：
/// 同一句话一直占着盲人听车流的耳朵，还会切断别的普通播报。
/// 现在**一段连续失败只播第一次**，恢复时播一次。屏幕上的错误文字照旧每轮更新（调用方负责）。
///
/// 放在单独的文件里：`BlindOrderStatusView.swift` 已超 SwiftLint 行数基线，棘轮不许它再变长。
/// 单测直接调 `BlindOrderStatusViewModel.loadOrder` 模拟一轮轮询（`OrderPollFailureSpeechTests`）。
struct OrderPollFailureGate {
    static let recoveredAnnouncement = "连接恢复了，订单状态已更新。"

    /// 正在连续失败的那一单。`nil` = 没在失败。按单记：换单后新单的第一次失败照样要播。
    private(set) var failingOrderId: Int64?

    /// 一轮失败。只有这一段失败的第一轮才念（并震动）。
    ///
    /// 轮询任务被取消（换单、页面重进时 `startPolling` 先 `cancel()` 旧任务）不算失败：
    /// 记成失败的话，下一轮成功会念一句不存在的「连接恢复了」。
    mutating func reportFailure(_ message: String, orderId: Int64, to speech: SpeechService?) {
        guard !Task.isCancelled else { return }
        defer { failingOrderId = orderId }
        guard failingOrderId != orderId else { return }
        speech?.speakError(message)
    }

    /// 一轮成功，**在 `apply` 之前调**。刚从失败里恢复时念一次恢复。
    ///
    /// `statusWillBeSpoken`：这一轮状态变了、`apply` 马上要念新状态。那句本身就说明连上了，
    /// 这里再念一句只会被它切断（记忆 `later-speak-silently-cuts-the-earlier-one`），所以不念。
    /// 调用方要把 `lastSpokenStatus` 去重算进去：状态句被去重掉时，这里必须照念恢复。
    mutating func reportSuccess(orderId: Int64, statusWillBeSpoken: Bool, to speech: SpeechService?) {
        defer { failingOrderId = nil }
        guard failingOrderId == orderId, !statusWillBeSpoken else { return }
        speech?.speak(Self.recoveredAnnouncement)
    }
}
