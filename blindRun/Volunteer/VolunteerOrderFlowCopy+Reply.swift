import Foundation

// 邀请回复倒计时的文案与「紧迫」判据。从 `VolunteerOrderFlowStep.swift` 挪出（SwiftLint 棘轮 #488：那个文件只许变短）。
extension VolunteerOrderFlowCopy {
    /// 「还剩 52 分钟回复」（设计稿 `volunteer-order-page-v2/02-ios-screens.md` 逐字的形状）。
    ///
    /// 🔄 2026-10-06：原先按秒（「还剩 25 秒回复」），因为后端是串行派单、每人 30 秒。
    /// 后端 #371 起改成分批并行、期限 60 / 15 分钟，按秒显示就成了「还剩 3599 秒回复」。
    /// 一分钟以上按分钟、**向上取整**（还剩 61 秒说「2 分钟」—— 往少说会让人以为比实际更急，
    /// 往多说最多多给一分钟的错觉，而那一分钟里卡片仍可接）；最后一分钟按秒，
    /// 那时人在盯着它，秒数才是有用的信息。
    static func replyCountdown(seconds: Int) -> String {
        let seconds = max(seconds, 0)
        guard seconds >= 60 else { return "还剩 \(seconds) 秒回复" }
        return "还剩 \(Int((Double(seconds) / 60).rounded(.up))) 分钟回复"
    }

    /// 倒计时转「紧迫」的阈值：**显示出来的分钟数**不到 15（设计稿「剩余不到 15 分钟，进度条和剩余时间变深黄」）。
    /// 分钟向上取整，所以剩 841–900 秒时字上是「还剩 15 分钟」—— 按秒判 `< 900` 会让这一分钟里
    /// 字写着 15、颜色却已经是深黄。判据因此是 `remainingSeconds <= 14 * 60`（字上显示 14 或更少）。
    /// 同时决定颜色和那个感叹号 —— 两处各写一个数，改一处漏一处的表现是「图标出现了但字还是蓝的」。
    /// 🔄 原先是 10 秒（每人 30 秒的串行派单时代），见 `replyCountdown` 的说明。
    static let urgentCountdownSeconds = 14 * 60

    static func isReplyUrgent(remainingSeconds: Int) -> Bool {
        remainingSeconds <= urgentCountdownSeconds
    }
}
