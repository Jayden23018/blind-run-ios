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

    // MARK: 取消固定搭档的确认（2026-11-05 从 `PartnerStreaks.swift` 挪来，那个文件超了 400 行）

    /// 取消收藏前要不要拦一道，以及拦下来说什么。
    struct RemoveFavoriteConfirmation: Equatable {
        let title: String
        let message: String
        let confirm: String
        let cancel: String
    }

    /// **每次都弹窗**（负责人 2026-11-05 定，#752）。两档文案不同：
    ///
    /// 没退出过的那一档确实可逆（再收藏一次即可），短文案只说后果和「还能设回来」。
    /// 2026-11-05 之前这一档不弹窗，理由是「可逆动作不加负担」；改版后取消挪进了详情页，
    /// 一次误触就让一位常跑的搭档从派单加分里消失，负责人选了每次都问。
    ///
    /// 🔴 **对方已退出时它不可逆，而且不可逆的后果落在对方身上。**
    ///
    /// 后端 `FavoriteVolunteerService.optOut()` 是**打标记不删行**，注释逐字写着理由：
    /// 「删了盲人会以为收藏丢了、于是重新收藏一次，把志愿者刚做的退出撤销掉」。
    /// 但同一个 service 的 `remove()` 就是 `deleteByBlindUserIdAndVolunteerUserId` ——
    /// **硬删整行，连同 `volunteer_opted_out_at` 一起**；随后 `add()` 建一条
    /// `optedOut = null` 的新行，门槛只有「一起跑完过至少一单」（那还成立）。
    /// 于是那个被防住的后果，由取消收藏按钮自己提供了入口。
    ///
    /// 🚩 **警告只能放在取消这一刻，放不到别处。** 行被删之后，「他曾经退出过」这个事实
    /// 在客户端就不存在了 —— 订单详情页那条收藏入口
    /// （`BlindOrderStatusView.favoriteVolunteerSection`）根本拿不到它，无从警告。
    static func removeFavoriteConfirmation(
        name: String,
        hasOptedOut: Bool
    ) -> RemoveFavoriteConfirmation {
        guard hasOptedOut else {
            return RemoveFavoriteConfirmation(
                title: "取消\(name)的固定搭档？",
                message: "取消后，派单时不再把\(name)当作你的固定搭档。以后还可以再设回来。",
                confirm: "取消固定搭档",
                // 不写「取消」：同下面那一档的「保留收藏」。
                cancel: "保留固定搭档"
            )
        }
        return RemoveFavoriteConfirmation(
            title: "\(removeFavoriteTitle(name))？",
            // 后果必须写进正文、且是读屏能一口气念清楚的一整句 —— 只给「确定 / 取消」
            // 等于把一个会影响**别人**的决定做成了一次无声点击。
            message: "\(name)已经退出了你们的固定搭档。取消收藏会把这条退出记录一起删掉："
                + "之后你如果再把\(name)设为固定搭档，他的退出就不作数了，而他不会收到任何提示。",
            confirm: "仍然取消收藏",
            // 🚩 **不写「取消」**：在一个讲「取消收藏」的弹窗里，「取消」有两种读法
            // （取消这个动作？还是确认取消收藏？）。念出来尤其分不清。
            cancel: "保留收藏"
        )
    }
}
