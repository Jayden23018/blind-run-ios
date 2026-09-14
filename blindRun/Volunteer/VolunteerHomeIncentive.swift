// 只依赖 Foundation —— 与 `VolunteerPoints.swift` / `VolunteerPointsView.swift`、
// `VolunteerAchievements.swift` / 成就页那两对同一个分法：模型与文案一个文件，视图另一个。
//
// 🚩 这个分法在本文件上还多一层作用：`hero` 的取舍是这张卡**唯一会出错、
// 且出错时没有任何运行时信号**的地方（空态选错了只是一张看起来正常的卡）。
// 不带 SwiftUI 就能单独编译，真机不在手边时也验得了。
import Foundation

// MARK: - 展示口径

/// 首页「我的贡献」卡要显示的东西。
///
/// 抽成值类型而不是把逻辑写进 view：这张卡的取舍全在「显示哪个数当主角」上，
/// 而那是**唯一会出错、且出错时没有任何运行时信号**的部分 —— 空态选错了只是
/// 一张看起来正常的卡，谁都不会报障。写成纯函数才有可以验红的测试面。
///
/// 🔴 **这里没有积分，是决策不是遗漏。** `VolunteerNextBadgeDto` 的 `HOURS_10` /
/// `HOURS_50` 两个 code 展示的是**服务时长**（`VolunteerAchievements.swift` 的单位表），
/// 也就是说这张卡**有时候**会显示时长。积分与志愿服务时长「刻意分两屏」的理由
/// 逐字写在 `VolunteerPoints.swift` 顶部与 `VolunteerOrderFlowViews` 的设置页注释里
/// （中央网信办 2026-06-19 通知第 2 条）。把积分加进来就会**随数据**与时长同屏相邻，
/// 而那正是两屏分法要防的事 —— 且它时有时无，一次手测很可能撞不上。
struct VolunteerHomeIncentiveSummary: Equatable {
    /// 有几位跑者把我设为固定搭档。
    let favoritedByCount: Int

    /// 下一枚未解锁的勋章。七枚全解锁时后端返 null。
    let nextBadge: VolunteerNextBadgeDto?

    /// 最强的那条火花（后端已按 `currentWeeks` 倒序，取第一条）。
    /// 火花开关 `app.incentive.streak.enabled` 关着时恒为 nil。
    let streak: PartnerStreakDisplay?

    /// 火花那一对的对方姓名（后端已掩码）。
    let streakPartnerName: String?

    /// 卡上那个最大的数字。
    ///
    /// 🚩 **顺序是「关系优先于进度」，不是随手排的**：被别人选中是他人给的正反馈，
    /// 勋章进度是平台给的跑步机。调研（`volunteer-home-incentive-layer-20260914.md` §3.4）
    /// 的判据是「一屏只强调一个主指标，同等强调多个等于没强调」。
    ///
    /// 🚩 **0 位搭档时不显示「0 位跑者把你设为固定搭档」** —— 新人第一天打开 App
    /// 看到的第一个数字是 0，那是负激励。这种情况下让位给勋章进度（他的第一枚是
    /// 「首次陪跑」，天然就是「下一步差多少」）。
    enum Hero: Equatable {
        case partners(count: Int)
        case badgeProgress(current: Int64, target: Int64, suffix: String, badgeName: String)
    }

    var hero: Hero? {
        if favoritedByCount > 0 {
            return .partners(count: favoritedByCount)
        }
        // 未知 `code` 的勋章拿不到量词，契约要求整块进度隐藏 —— 那就更不能拿它当主角。
        if let nextBadge,
           let unit = nextBadge.progressUnit,
           let target = nextBadge.target, target > 0,
           let current = nextBadge.current, current >= 0 {
            return .badgeProgress(
                current: unit.display(current),
                target: unit.display(target),
                suffix: unit.suffix,
                badgeName: nextBadge.displayName
            )
        }
        return nil
    }

    /// `hero` 拿不到东西时**整张卡不渲染**，不留一个写着 0 的空壳。
    /// 发生在「七枚勋章全解锁 + 还没有人收藏我」这种组合上，那是老手，他不需要这张卡。
    var isRenderable: Bool { hero != nil }

    /// 勋章那一段要不要单独画一行。
    ///
    /// 主角已经是勋章进度时**不再重复画** —— 同一个数在一张卡上出现两次，
    /// 读屏用户会听两遍。
    var showsBadgeRow: Bool {
        guard nextBadge != nil else { return false }
        if case .badgeProgress = hero { return false }
        return true
    }
}

// MARK: - 文案

/// 首页激励卡的文案。
///
/// 🔴 **只陈述已经做到了什么，不催促。** 不得出现「还差 N 单就…」「今天再跑一单」
/// 这类句式，也不得在志愿者关掉「可服务」开关时弹任何挽留 ——
/// 依据是 Motivation Crowding Theory（Frey & Jegen 2001）：外在激励被感知为
/// **controlling** 时会挤出内在动机，被感知为 **supportive** 时才叠加。
/// 我们的志愿者是**无偿**的，即纯内在动机人群，落在挤出风险最高的一侧。
/// Uber 在司机点下线时弹当日目标挽留的做法被 NYT 点名、在 gig 平台设计分类法里
/// 归入 dark pattern（「Moving Targets」）。详见
/// `docs/research/volunteer-home-incentive-layer-20260914.md` §3。
///
/// 🔴 **不得把服务时长折算成金额。** 志愿者管理平台的通行做法是按 Independent Sector
/// 的费率折算成美元展示，我们不能 —— 中央网信办 2026-06-19 通知第 2 条。
enum VolunteerHomeIncentiveCopy {
    static let sectionTitle = "我的贡献"

    static let partnersCaption = "位跑者把你设为固定搭档"

    static let achievementsLinkTitle = "查看服务成就"

    static let achievementsLinkHint = "查看已完成的服务次数、累计时长、国标星级和平台勋章"

    /// 勋章那一行的前缀。
    ///
    /// 🔴 **不写「还差 N 就解锁」** —— `HIGH_RATED` 是「均分 ≥ 4.8 **且** ≥ 10 条评价」
    /// 的双条件，进度条满格也可能没解锁，那句话会变成我们兑现不了的承诺
    /// （理由逐字在 `VolunteerNextBadgeDto` 与 `VolunteerAchievementsCopy` 顶部）。
    static let nextBadgePrefix = "下一枚勋章"

    static func partnersSpoken(_ count: Int) -> String {
        "有 \(count) \(partnersCaption)"
    }

    static func badgeProgressSpoken(badgeName: String, current: Int64, target: Int64, suffix: String) -> String {
        "\(nextBadgePrefix)，\(badgeName)，已完成 \(current) / \(target) \(suffix)"
    }

    /// 整张卡合成一个 VoiceOver 焦点后念的那句话。
    ///
    /// 合成的理由与 `IncentiveHeroCard` 同：主数字和它的说明是同一件事的两种说法，
    /// 分开念会让读屏用户为一张卡划四五次、并听两遍同一个数。
    ///
    /// ⚠️ 「查看服务成就」按钮**不在**这句话里，它是 combine 之外的兄弟节点 ——
    /// 塞进合成元素里 VoiceOver 就点不到它了（同 `VolunteerDispatchSummaryCard`
    /// 的「去培训」按钮踩过的那个坑）。
    static func accessibilityLabel(_ summary: VolunteerHomeIncentiveSummary) -> String {
        var parts = [sectionTitle]

        switch summary.hero {
        case .partners(let count):
            parts.append(partnersSpoken(count))
        case .badgeProgress(let current, let target, let suffix, let badgeName):
            parts.append(badgeProgressSpoken(
                badgeName: badgeName,
                current: current,
                target: target,
                suffix: suffix
            ))
        case nil:
            break
        }

        if let streak = summary.streak {
            let partner = summary.streakPartnerName?.nilIfBlank ?? PartnerStreakCopy.unknownBlindName
            parts.append(streak.headline(partner: partner))
            parts.append(streak.progressText)
        }

        if summary.showsBadgeRow,
           let next = summary.nextBadge {
            if let progress = next.progressText {
                parts.append("\(nextBadgePrefix)，\(next.displayName)，\(progress)")
            } else {
                parts.append("\(nextBadgePrefix)，\(next.displayName)")
            }
        }

        return parts.joined(separator: "。") + "。"
    }
}
