import Foundation

// MARK: - 一条待回复的邀请

/// 设计交付文档 v3 §4.4.2 / §4.4.3 的那张卡背后的状态。
///
/// 🚩 **它不是 `RealtimeDispatchPrompt` 的副本**，多出来的是「这一条已经有结果了」：
/// §4.4.3 要求结果**原地**变化（接下成功 / 已失效），不关掉再弹一个新弹层。
/// 所以回复成功之后这条邀请不能直接从队列里删掉 —— 删了卡片就跟着消失，
/// 而那正是设计稿点名不要的那种「弹层套弹层」。
struct VolunteerInviteState: Identifiable {
    enum Outcome {
        /// 已接下（`ACCEPT` 成功）。卡片原地变「已约好」。
        case accepted
        /// 回复期限已过。卡片原地变「这个邀请已失效」。
        case expired
    }

    let order: WSNewOrder
    let receivedAt: Date
    let expiresAt: Date
    /// 每秒由 view model 的 ticker 刷新。
    var remainingSeconds: Int
    /// `nil` = 还等着回复。
    var outcome: Outcome?

    var id: Int64 { order.orderId }
    var isAwaitingReply: Bool { outcome == nil }

    /// 进度条的分母。**取 `expiresAt - receivedAt` 而不是 `dispatchTimeoutSeconds`**：
    /// 后端把窗口算在**发出**那一刻（`timestamp`），推送在路上耗掉的时间是真的少掉了，
    /// 拿标称值当分母会让进度条一上来就跳一段。
    var totalSeconds: Int {
        max(1, Int(ceil(expiresAt.timeIntervalSince(receivedAt))))
    }

    /// 剩余占比，0…1。
    var remainingFraction: Double {
        min(1, max(0, Double(remainingSeconds) / Double(totalSeconds)))
    }

    /// 进度条与剩余时间文字转「深黄」的那一刻（设计交付 v3 §4.4.2 第 3 项）。
    ///
    /// ⚠️ 设计稿的判据是「剩余 < 15 **分钟**」，那是按 §10「回复期限 1 小时 / 15 分钟」写的。
    /// 后端目前只有 `app.dispatch.per-volunteer-timeout-seconds=30`，一整个窗口才 30 秒 ——
    /// 照 15 分钟写等于**从第一帧就是深黄**，那条视觉提示就没有了。
    /// 所以沿用弹窗原有的 10 秒阈值（`VolunteerOrderFlowCopy.urgentCountdownSeconds`），
    /// 与「查看详情」那一页说同一句话。预约单的分钟级回复期限已投 handoff。
    var isUrgent: Bool {
        remainingSeconds <= VolunteerOrderFlowCopy.urgentCountdownSeconds
    }
}

// MARK: - 连续「去不了」的本地计数

/// 设计交付 v3 §4.4.3：「连续 3 次去不了后，下次打开接单主页询问『要不要调整空闲时间』，
/// **不做任何惩罚**」。
///
/// 🚩 **后端没有这个计数**（它自己那套「30 天内 3 次 → 暂停邀请 14 天」是另一回事，
/// 口径与触发后果都不同），所以只能本地计。
///
/// 重装 App 计数归零是**可接受**的：它触发的全部后果只有一句不带惩罚的询问，
/// 归零的代价是「少问一次」，不会误判任何人。反过来如果它带惩罚，本地存就不能用了。
struct VolunteerDeclineStreak {
    /// 设计交付 v3 §10「询问调整空闲时间 = 连续 3 次去不了」。
    static let threshold = 3
    private static let storageKey = "aidrun.volunteer.consecutiveDeclineCount"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var count: Int { defaults.integer(forKey: Self.storageKey) }

    var shouldAskAboutAvailability: Bool { count >= Self.threshold }

    /// **只在 `DECLINE` 真的发出去之后调**。5 秒撤销窗口内点了撤销的那次不算 ——
    /// 他并没有拒绝这一单。
    func recordDecline() {
        defaults.set(count + 1, forKey: Self.storageKey)
    }

    /// 接下任一单即清零；询问过一次也清零（问一次就够，反复问就成了惩罚）。
    func reset() {
        defaults.removeObject(forKey: Self.storageKey)
    }
}

// MARK: - 文案

/// 逐字取自《陪跑员端首页与接单 设计交付文档 v3》§4.4.2 / §4.4.3。
/// 与订单页共用的那几句（「接下这次陪跑」「这次去不了」「还剩 X 秒回复」）
/// **不在这里重写一遍**，直接用 `VolunteerOrderFlowCopy` —— 两份必然漂移。
enum VolunteerInviteCopy {
    static let sheetTitle = "新的陪跑邀请"
    static func sheetTitle(count: Int) -> String {
        count > 1 ? "\(count) 个新邀请" : sheetTitle
    }

    static let distanceToStartLabel = "离你"
    static let detail = "查看详情"

    // §4.4.3 「接下成功」
    static let acceptedTitle = "已约好"
    static let acceptedDetail = "跑者的全名和电话已放进订单"
    static let acceptedPrimary = "查看订单"
    static let acceptedSecondary = "回到接单"

    // §4.4.3 「接下失败：已过期」与「在卡片打开期间过期」是同一张卡
    static let expiredTitle = "这个邀请已失效"
    static let expiredDetail = "回复时间已过"
    static let expiredPrimary = "知道了"

    // §4.4.3 「这次去不了」的撤销 toast
    static let declineToastText = "已回复这次去不了"
    static let declineToastUndo = "撤销"

    // §4.4.3 连续 3 次去不了后的询问（接单主页）
    static let adjustAvailabilityTitle = "要不要调整空闲时间"
    static let adjustAvailabilitySubtitle = "最近几次邀请你都去不了。改一下空闲时间，可能更容易碰上合适的。"

    /// 接单主页上「收起之后回来」的那个入口。
    static func pendingInvitesTitle(count: Int) -> String {
        count > 1 ? "\(count) 个新邀请" : "1 个新邀请"
    }
}
