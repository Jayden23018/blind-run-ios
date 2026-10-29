import Foundation

// 从 `IntroCallModels.swift` 旁边另起一个文件：那个文件只许变短（SwiftLint 棘轮 #488）。
extension IntroCallCopy {
    /// 这条「跑者正在来电」显示到几点（后端发出时刻 + 2 分钟）；已经过了返回 `nil`。**通话页与横幅共用这一条判据**（#448）：
    /// 重连补读会把几分钟前的那条再投一次，过了就既不显示也不念。发出时刻晚于本机「现在」（两端时钟偏差）按现在算。
    static func incomingCallDisplayUntil(sentAt: Date, now: Date) -> Date? {
        let until = min(sentAt, now).addingTimeInterval(incomingCallDisplaySeconds)
        return until > now ? until : nil
    }
}
