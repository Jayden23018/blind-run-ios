import Foundation

// 从 `VolunteerInviteQueue.swift` 挪出（#552）：那个文件超过 400 行的上限。

/// 设计交付 v3 §4.4.3：「连续 3 次去不了后，下次打开接单主页询问『要不要调整空闲时间』，
/// **不做任何惩罚**」。
///
/// 🔄 2026-10-28（#338，SPEC D11）：**次数以后端为准** —— `pending-invites` 的 `consecutiveDeclineCount`
/// （拒绝、过期 +1，接单、有意向清零，撤回不计）。本地原先只数「去不了」，漏了过期、算错了撤回，重装还归零。
/// 两次对账之间本地先 +1（他刚按的「去不了」），下一次快照以后端的数为准。
///
/// 「问过一次就不再问」仍由客户端记：存下问的那一刻的次数，**再涨 3 才再问**；后端清零后从头算。
///
/// 🔄 2026-10-28（#552）：**按账号记**。两个数原来存在全局 `UserDefaults`，登出不清、也不分账号：
/// A 登出、B 在同一台手机登录，B 的第一份快照到之前会被 A 的次数问一句「要不要调整空闲时间」。
/// 现在键里带 userId、走 `AppState` 的持久化域（测试自动隔离），登出时由
/// `AppState.performLocalSessionCleanup` 调 `clearStoredCounts` 清掉这个账号的两个键。
struct VolunteerDeclineStreak {
    /// 设计交付 v3 §10「询问调整空闲时间 = 连续 3 次去不了」。
    static let threshold = 3
    /// 键名前缀沿用全局计数时代的；后面接 `.<userId>`。前缀本身（不带 userId 的旧键）不知道是谁的，只删不读。
    private static let countKeyPrefix = "aidrun.volunteer.consecutiveDeclineCount"
    private static let askedAtKeyPrefix = "aidrun.volunteer.consecutiveDeclineCountAskedAt"

    private let persistence: (any AppStatePersistence)?
    private let userID: Int64?

    /// `userID == nil`（没登录、会话还没恢复）：读到 0，写入丢弃 —— 记不到任何人名下的数不该留下。
    init(persistence: (any AppStatePersistence)?, userID: Int64?) {
        self.persistence = persistence
        self.userID = userID
    }

    private var keys: (count: String, askedAt: String)? {
        guard persistence != nil, let userID else { return nil }
        return ("\(Self.countKeyPrefix).\(userID)", "\(Self.askedAtKeyPrefix).\(userID)")
    }

    var count: Int { keys.flatMap { persistence?.object(forKey: $0.count) as? Int } ?? 0 }
    /// 上一次问的时候次数是多少。
    var askedAt: Int { keys.flatMap { persistence?.object(forKey: $0.askedAt) as? Int } ?? 0 }

    var shouldAskAboutAvailability: Bool { count - askedAt >= Self.threshold }

    /// **只在 `DECLINE` 真的发出去之后调**。5 秒撤销窗口内点了撤销的那次不算 —— 他并没有拒绝这一单。
    func recordDecline() {
        guard let keys else { return }
        persistence?.set(count + 1, forKey: keys.count)
    }

    /// 待回复快照带回来的后端次数。比上次问时还小 = 后端清零过（接了单 / 有意向），问过的记号一起归零。
    /// 顺手删掉全局计数时代那两个不带 userId 的旧键：后端的数已经接替了它们，留着只是一份认不出主人的数。
    func adoptServerCount(_ serverCount: Int) {
        guard let persistence, let keys else { return }
        let serverCount = max(0, serverCount)
        persistence.set(serverCount, forKey: keys.count)
        if serverCount < askedAt { persistence.removeObject(forKey: keys.askedAt) }
        Self.removeLegacyKeys(in: persistence)
    }

    /// 问过了：记下此刻的次数（问一次就够，反复问就成了惩罚）。
    func acknowledgeAsked() {
        guard let keys else { return }
        persistence?.set(count, forKey: keys.askedAt)
    }

    /// 接下任一单 / 有意向：后端会清零，本地先跟上。
    func reset() {
        guard let keys else { return }
        persistence?.removeObject(forKey: keys.count)
        persistence?.removeObject(forKey: keys.askedAt)
    }

    /// 会话结束（登出、注销、过期）时清掉这个账号的两个数，连同不带 userId 的旧键。
    static func clearStoredCounts(for userID: Int64?, in persistence: any AppStatePersistence) {
        VolunteerDeclineStreak(persistence: persistence, userID: userID).reset()
        removeLegacyKeys(in: persistence)
    }

    private static func removeLegacyKeys(in persistence: any AppStatePersistence) {
        persistence.removeObject(forKey: countKeyPrefix)
        persistence.removeObject(forKey: askedAtKeyPrefix)
    }
}
