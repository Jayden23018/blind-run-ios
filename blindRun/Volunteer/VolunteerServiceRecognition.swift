import Foundation

/// 志愿者服务成就的一档。
///
/// **每一档都必须能靠名称和图标区分，不能只靠颜色**（WCAG 1.4.1：颜色不得作为唯一指示）。
/// 志愿者端同样有低视力用户，而本仓库的视觉通道此前从没被系统性检查过 ——
/// 这是新写的页面，不该再欠一笔。
struct ServiceRecognitionTier: Identifiable, Equatable, Sendable {
    /// 解锁需要的**完成单数**。
    let threshold: Int
    let name: String
    /// SF Symbol 名。与 `name` 一起构成非颜色的区分手段。
    let symbolName: String

    var id: Int { threshold }
}

/// 某一档对当前志愿者的状态。
struct ServiceRecognitionProgress: Identifiable, Equatable, Sendable {
    let tier: ServiceRecognitionTier
    let isUnlocked: Bool
    /// 还差几单解锁；已解锁时为 0。
    let remaining: Int

    var id: Int { tier.threshold }

    /// 未解锁的档位**说清还差几单**，而不是只置灰 —— 置灰对读屏用户不存在，
    /// 对低视力用户也只是「看不清的那个」。规则写在页面上，志愿者能自己算出下一档。
    var accessibilityLabel: String {
        isUnlocked
            ? "\(tier.name)，已解锁"
            : "\(tier.name)，还差 \(remaining) 单解锁"
    }

    var statusText: String {
        isUnlocked ? "已解锁" : "还差 \(remaining) 单"
    }
}

/// 服务成就的分层规则。**全部基于后端真有的 `totalCompleted`**，没有任何合成出来的数字。
///
/// 门槛是**完成单数**，不是调研推荐的服务小时数（25/50/100/250/500，
/// `docs/research/live-trip-sharing-and-volunteer-incentives-20260813.md` §2）——
/// `dispatch-summary` 没有时长字段，把小时数的阈值直接套到单数上，会让「50 单」和
/// 「50 小时」看起来是同一件事。后端补上时长后可以再加一条并行的维度，不必推翻这套。
enum VolunteerServiceRecognition {
    static let tiers: [ServiceRecognitionTier] = [
        // 首单完成是留存曲线上最陡的一段，必须当场有反馈。
        ServiceRecognitionTier(threshold: 1, name: "首次陪跑", symbolName: "figure.run"),
        // UIS 的结论是每位盲人跑者需要 6–8 名固定陪跑员；10 单意味着这个人已经能撑起
        // 一个人的固定供给（`blind-app-feature-landscape-20260812.md` §2.2）。
        ServiceRecognitionTier(threshold: 10, name: "熟练陪跑员", symbolName: "star.fill"),
        ServiceRecognitionTier(threshold: 25, name: "资深陪跑员", symbolName: "rosette"),
        ServiceRecognitionTier(threshold: 50, name: "金牌陪跑员", symbolName: "trophy.fill"),
        // 高层要看起来值得挣，间距刻意拉开。
        ServiceRecognitionTier(threshold: 100, name: "荣誉陪跑员", symbolName: "crown.fill")
    ]

    static func progress(completedCount: Int) -> [ServiceRecognitionProgress] {
        let completed = max(0, completedCount)
        return tiers.map { tier in
            ServiceRecognitionProgress(
                tier: tier,
                isUnlocked: completed >= tier.threshold,
                remaining: max(0, tier.threshold - completed)
            )
        }
    }

    /// 当前所处的最高档；一单都没完成时为 `nil`。
    static func currentTier(completedCount: Int) -> ServiceRecognitionTier? {
        tiers.last { completedCount >= $0.threshold }
    }

    /// 下一档还差几单；已到顶时为 `nil`。
    static func nextTierRemaining(completedCount: Int) -> (tier: ServiceRecognitionTier, remaining: Int)? {
        guard let next = tiers.first(where: { completedCount < $0.threshold }) else { return nil }
        return (next, next.threshold - max(0, completedCount))
    }

    static func headlineText(completedCount: Int) -> String {
        guard let tier = currentTier(completedCount: completedCount) else {
            return "还没有完成的服务"
        }
        return tier.name
    }

    /// 顶部那句话。**不出现「积分」二字** —— 页面上每个数字都要能追溯到后端字段。
    static func summarySpeech(completedCount: Int) -> String {
        let base = completedCount > 0
            ? "已完成 \(completedCount) 次陪跑服务，当前称号\(headlineText(completedCount: completedCount))。"
            : "还没有完成的服务。"
        guard let next = nextTierRemaining(completedCount: completedCount) else {
            return base + "已经是最高一档。"
        }
        return base + "再完成 \(next.remaining) 单解锁\(next.tier.name)。"
    }
}
