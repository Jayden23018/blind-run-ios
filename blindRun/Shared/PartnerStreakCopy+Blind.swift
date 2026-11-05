import Foundation

// 盲人端固定搭档列表与搭档详情页的文案（#752，照健康 · 共享，定稿 `docs/ui/mockups/blind-partners-20261105/`）。
// 与 `PartnerStreakCopy` 主体分开放：那个文件已经很长，这些只给盲人端用。

extension PartnerStreakCopy {
    // MARK: 列表

    /// 顶部说明卡的标题。只数**没退出**的固定搭档：已退出的那位不会再给派单加分。
    static func blindHeroTitle(_ count: Int) -> String { "\(count) 位固定搭档" }

    /// 🔴 不写「优先派给他」：收藏只是派单加分（理由见 `favoriteExplanation`）。
    static let blindHeroCaption = "设为固定搭档后，派单时更可能派给他，但不保证一定是他。"

    static let blindFavoritesSectionTitle = "固定搭档"
    static let blindRanTogetherSectionTitle = "一起跑过的人"
    static let blindNotFavoriteYet = "还不是固定搭档"
    static let blindEmptyTitle = "还没有固定搭档"
    static let blindRowHint = "点击查看这位搭档"

    /// 「一起跑完 5 次」。0 或没给时为 nil（那一段不出现）。
    static func blindTogetherText(_ count: Int?) -> String? {
        guard let count, count > 0 else { return nil }
        return "一起跑完 \(count) 次"
    }

    /// 列表一行第二行的「连续」之后那一段（火焰与「连续 N 周」由视图画）。
    ///
    /// - 退出了：只说退出，不说周数 —— 那一对已经不累积了。
    /// - 固定搭档：一起跑完几次。
    /// - 只一起跑过：「还不是固定搭档」。
    static func blindRowTrailing(_ row: PartnerRow) -> String? {
        if row.hasOptedOut { return partnerOptedOutSuffix }
        if !row.isFavorite { return blindNotFavoriteYet }
        return blindTogetherText(row.completedRunsTogether)
    }

    /// 一行一个焦点：「张，连续 3 周一起跑步，一起跑完 12 次」（名字去掉星号）。
    ///
    /// 🔴 连续周数为 nil 时**整段不念**，不念「连续 0 周」（契约里未点亮是 null）。
    static func blindRowSpoken(_ row: PartnerRow) -> String {
        var parts = [row.spokenName(fallback: unknownVolunteerName)]
        if !row.hasOptedOut, let streak = row.streak {
            parts.append("连续 \(streak.currentWeeks) 周一起跑步")
        }
        if let trailing = blindRowTrailing(row) {
            parts.append(trailing)
        }
        return parts.joined(separator: "，")
    }

    // MARK: 详情页

    static let blindStreakCardTitle = "连续一起跑"
    static let blindStreakRule = "每周至少一起跑一次，就多记一周。"
    static let blindTogetherRowTitle = "一起跑完"

    static func blindTogetherRowValue(_ count: Int) -> String { "\(count) 次" }

    /// 连续周数卡念的那一句。格子对读屏是空的，进度全靠这句。
    static func blindStreakSpoken(_ streak: PartnerStreakDisplay) -> String {
        "\(blindStreakCardTitle)，\(streak.currentWeeks) 周，\(streak.progressText)"
    }

    static let blindRemoveTitle = "取消固定搭档"
    static let blindRemoveFootnote = "取消前会再问你一次。"

    /// 上屏不带名字（页面顶部就是名字），念出来那份带上，免得读屏用户不知道取消的是谁。
    static func blindRemoveSpoken(_ name: String) -> String { "取消\(name)的固定搭档" }

    static let blindAddTitle = "设为固定搭档"
    static let blindAddFootnote = "派单时更可能派给他，但不保证一定是他。"
}
