import Foundation

// 屏 3b「求助已发出」页的文案（#506，负责人 2026-10-22 看过目视稿后批准）。
// 单独成文件：`SafetyModule.swift` 已超 SwiftLint 的长度上限，CI 棘轮不许它再变长。
extension EmergencySafetyCopy {
    /// 唯一主按钮下面那一行小字。按钮本身沿用 `homeCallMedicalTitle`「拨打120」。
    static let sentCallMedicalSubtitle = "急救电话"

    /// 110 与主紧急联系人收进这一个按钮，点开是全 App 共用的拨号选择（`emergencyCallOptionsDialog`）。
    static let sentOtherCallsTitle = "打 110 或紧急联系人"
    /// 没有可拨的主联系人时弹窗里没有联系人这一项，提示也不能念它（#506 code review B2）。
    static func sentOtherCallsAccessibilityHint(hasContact: Bool) -> String {
        hasContact ? "打开号码选择：紧急联系人、120、110" : "打开号码选择：120、110"
    }
    /// 那个拨号选择在这一屏的正文（`EmergencyCallContext.cloudSent`）。
    /// 🔴 只说「已经发出」，不说客服或家属已收到（`AGENTS.md` §6）。
    static let sentCallDialogMessage = "求助已经发出。你也可以自己打电话，请选择要拨打的号码。"
    /// 发没发出不确定、或已撤销时的那一句（`EmergencyCallContext.cloudUncertain`）。负责人 2026-10-22 批准。
    static let uncertainCallDialogMessage = "请选择要拨打的号码。"

    /// 撤销降为底部一行弱化文字。可点高度仍是 64pt，点后照旧二次确认（`cancelOwnerConfirmation`）。
    static let sentQuietCancelTitle = "误触了？撤销求助"

    /// 再按一次被并入同一条时的两行时间线（对读屏隐藏，正文那句已经说过）。
    static let sentTimelineFirstRow = "发出求助"
    static let sentTimelineMergedRow = "又按了一次，并入这一条"

    /// 标题下那一行：屏幕上「10:02 发出 · 3 分钟前」，读屏「10点02分发出，3分钟前」。
    ///
    /// 「多久以前」：不到 1 分钟「刚刚」，之后「N 分钟前」，满 1 小时「N 小时 M 分钟前」（整点时省掉分钟）。
    /// 发出时刻可能来自后端时钟（冷启动恢复取 `triggeredAt`），比本机快时夹到「刚刚」，不说「-2 分钟前」。
    static func sentSince(_ sentAt: Date, now: Date, calendar: Calendar = .current) -> (text: String, spoken: String) {
        let parts = calendar.dateComponents([.hour, .minute], from: sentAt)
        let hour = parts.hour ?? 0
        let minute = parts.minute ?? 0
        let clock = String(format: "%02d:%02d", hour, minute)
        let spokenClock = "\(hour)点" + String(format: "%02d分", minute)
        let ago = sentAgo(seconds: now.timeIntervalSince(sentAt))
        return ("\(clock) 发出 · \(ago)", "\(spokenClock)发出，\(ago)")
    }

    /// 时间线每一行左边的时刻。
    static func sentClock(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    static func sentAgo(seconds: TimeInterval) -> String {
        let minutes = Int(max(seconds, 0) / 60)
        if minutes < 1 { return "刚刚" }
        if minutes < 60 { return "\(minutes) 分钟前" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) 小时前" : "\(hours) 小时 \(rest) 分钟前"
    }
}
