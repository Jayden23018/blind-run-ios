import Foundation

/// 同行会话里「精确位置」关着时，横幅显示、根视图朗读的那一句（盲人端 #373，两端 #407）。
/// 单独成文件：协调器文件已到 SwiftLint 棘轮的上限。
///
/// 关着时这一端不上报同行位置。后端在 `IN_PROGRESS` 读不到一方坐标时，先给双方发 `ESCORT_SIGNAL_LOST`，
/// 缺失满 `app.escort.signal-missing-grace-seconds` 再按 `AI_DETECTED` 升级求助（`websocket-protocol.md` §信号缺失）。
/// 所以文案要说清跑步中一直关着的后果。规则：
/// - 时长只说「几分钟后」：那是后端配置项（默认 180 秒），后端改了值客户端不知道。
/// - 只说将来会发生什么。不说「已发出」「已通知」，也不提短信（AGENTS.md §6）。
/// - 先说已经暂停、后果是什么，再说怎么办。「如果弹出提示」是因为系统可能不弹（App 在后台时）。
enum EscortPreciseLocationCopy {
    static func message(role: UserRole, running: Bool) -> String {
        // 「对方看不到你的位置」照抄拒绝共享那两句（`escortDeclinedFeedback`）：同一件事只用一种说法。
        // 盲人自己按求助发不出去（#380：云端求助要精确坐标）；陪跑员的求助不受这个开关影响，不许这样说。
        let paused = role == .blind
            ? "已暂停同行位置共享：对方看不到你的位置，紧急求助也会因此发不出去。"
            : "已暂停同行位置共享：对方看不到你的位置。"
        // 进 `IN_PROGRESS` 时换成这一句，状态随之变化，根视图再念一次（开跑前的那次提醒）。
        let escalation = running
            ? "跑步中一直关着的话，几分钟后系统会按失联处理，自动启动求助流程。"
            : "开始跑步后如果还关着，几分钟后系统会按失联处理，自动启动求助流程。"
        return "「精确位置」已关闭，只能拿到大致位置，可能偏差几公里，" + paused + escalation
            + "如果弹出提示请选允许，或到系统设置里为助盲跑打开「精确位置」。"
    }
}
