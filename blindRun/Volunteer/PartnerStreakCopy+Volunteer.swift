import Foundation

// 陪跑员端固定搭档列表与搭档详情页的文案（#697，照健康 · 共享）。
// 与 `PartnerStreakCopy` 主体分开放：那个文件已经很长，这些只给陪跑员端用。

extension PartnerStreakCopy {
    /// 列表一行的第二行。🔴 退出了就只说退出，不再说连续周数 —— 那一对已经不累积了。
    /// 没有连续记录时说设为搭档的日期；两样都没有时为 nil（这一行只剩名字）。
    static func volunteerRowDetail(_ row: PartnerRow) -> String? {
        if row.hasOptedOut { return selfOptedOutSuffix }
        if let streak = row.streak {
            return "连续 \(streak.currentWeeks) 周 · \(volunteerBestText(streak))"
        }
        return favoritedAtText(row.favoritedAt)
    }

    /// 「最好 7 周」，当前就是最好成绩时说「最好成绩」。
    static func volunteerBestText(_ streak: PartnerStreakDisplay) -> String {
        streak.isPersonalBest ? "最好成绩" : "最好 \(streak.bestWeeks) 周"
    }

    /// 一行一个焦点：「李，连续 3 周一起跑步，最好 7 周」（名字去掉星号）。
    static func volunteerRowSpoken(_ row: PartnerRow) -> String {
        var parts = [row.spokenName(fallback: unknownBlindName)]
        if row.hasOptedOut {
            parts.append(selfOptedOutSuffix)
        } else if let streak = row.streak {
            parts.append("连续 \(streak.currentWeeks) 周一起跑步")
            parts.append(volunteerBestText(streak))
        } else if let favoritedAt = favoritedAtText(row.favoritedAt) {
            parts.append(favoritedAt)
        }
        return parts.joined(separator: "，")
    }

    static let volunteerRowHint = "点击查看这位搭档"
    static let volunteerListSectionTitle = "搭档"
    static let volunteerListFootnote = "退出、举报、不再匹配都在每位搭档的页面里。"
    static let volunteerAboutTitle = "关于固定搭档"
    static let volunteerHeroCaption = "跑者把你设为固定搭档"

    /// 说明卡的三条（空状态三条全用，列表底部「关于」只用后两条）。
    struct Explainer: Equatable {
        let symbol: String
        let title: String
        let detail: String
    }

    static let explainerHowItStarts = Explainer(
        symbol: "figure.run",
        title: "跑者来选",
        detail: "跑者和你一起跑完之后，可以把你设为固定搭档。"
    )
    /// 🔴 不写「优先派给你」：收藏只是派单加分，不是承诺（同 `favoriteExplanation`）。
    static let explainerAskFirst = Explainer(
        symbol: "megaphone.fill",
        title: "先问你",
        detail: "派这位跑者的订单时，先问你。"
    )
    static let explainerStreak = Explainer(
        symbol: "flame.fill",
        title: "连续陪跑",
        detail: "你们每周一起跑完一次，就多记一周。"
    )

    // 搭档详情页

    static let streakCardTitle = "连续陪跑"
    static let streakWeeksUnit = "周"

    /// 「最好 7 周 · 还差 4 周追平」/「这是你们最好的成绩」。
    static func detailStreakProgress(_ streak: PartnerStreakDisplay) -> String {
        if streak.isPersonalBest { return streak.progressText }
        return "最好 \(streak.bestWeeks) 周 · 还差 \(streak.bestWeeks - streak.currentWeeks) 周追平"
    }

    /// 格子下面那行小字。
    static func detailStreakLegend(_ streak: PartnerStreakDisplay) -> String {
        if streak.isPersonalBest { return "一格一周，每一格都是你们一起跑完的一周" }
        return "一格一周，满 \(streak.bestWeeks) 格追平最好成绩"
    }

    static let detailStreakRule = "你们每周至少一起跑完一次，就多记一周。断了从第 1 周重新算，最好成绩会保留。"
    static let detailOptOutTitle = "退出固定搭档"
    static let detailOptOutFootnote = "退出后不能撤销：派这位跑者的订单时不再先问你，连续陪跑也停止累积。"
    static let detailOptedOutFootnote = "你已退出这位跑者的固定搭档。"
}

/// 列表里的一行带上稳定身份：有 userId 用 userId，已注销（nil）才退回下标。
struct KeyedPartnerRow: Identifiable {
    let index: Int
    let row: PartnerRow

    var id: String { row.userId.map { "user.\($0)" } ?? "offset.\(index)" }

    static func make(_ rows: [PartnerRow]) -> [KeyedPartnerRow] {
        rows.enumerated().map { KeyedPartnerRow(index: $0.offset, row: $0.element) }
    }
}

/// 搭档详情页火花卡的格子：画 `bestWeeks` 格、点亮 `currentWeeks` 格。
///
/// ponytail: 格子数等于最好周数，不封顶。连续 52 周以上的一对会画出几行格子，真出现了再改成「满一年折一行」。
struct PartnerStreakCells: Equatable {
    let total: Int
    let lit: Int

    init(_ streak: PartnerStreakDisplay) {
        total = max(streak.bestWeeks, streak.currentWeeks)
        lit = streak.currentWeeks
    }
}
