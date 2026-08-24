import Foundation

// MARK: - 双人火花

/// `GET /api/blind/partners/streaks` / `GET /api/volunteer/partners/streaks` 的一条（SPEC-E 第 2 步）。
///
/// ⚠️ **数组里只有已点亮的**（默认门槛连续 2 周）。未点亮的一对**根本不在数组里**，
/// 不是「返回了但周数小」⇒ 客户端不做门槛判断，拿到几条就念几条
/// （Strava 口径：未达成不显示，而非灰显）。
///
/// ⚠️ 数组已按 `currentWeeks` 倒序，**客户端不要重排** —— 读屏是顺序播报的，
/// 排在后面等于不存在。
///
/// ⚠️ 空数组 = 这个人没有已点亮的火花（或后端开关 `app.incentive.streak.enabled` 关着，
/// 默认就是关的），**不是错误态**。
struct PartnerStreakResponse: Decodable, Sendable, Equatable {
    let id: Int64?

    /// 对方的 userId。盲人侧是志愿者，志愿者侧是盲人。
    let partnerUserId: Int64?

    /// 对方姓名，**后端已掩码**（`张*`）。对方已注销时为 `nil`。
    let partnerName: String?

    /// 当前连续周数。断裂后从 **1** 重新开始（那一周他们确实跑了），不是 0。
    let currentWeeks: Int?

    /// 历史最佳，**断裂时不清零**。
    let bestWeeks: Int?

    /// ISO 周字符串（`2026-W34`）。
    ///
    /// 🚨 **这不是日期，不要拿去做日期解析** —— `2025-12-29` 属于 `2026-W01`，
    /// 用日期做「是不是上一周」的判断必出错。只展示的话根本不用碰它，所以本仓库不解析它。
    let lastCreditedWeek: String?
}

/// 火花的展示口径。抽成独立类型是因为**两侧共用**（盲人端固定搭档列表、志愿者端固定搭档页），
/// 各写各的必然漂移。
struct PartnerStreakDisplay: Equatable {
    let currentWeeks: Int
    let bestWeeks: Int

    /// `nil` 表示这一对没有已点亮的火花 —— 那一行**整段不显示、不播报**。
    ///
    /// 🔴 判据是 `streakWeeks == nil`，**不是** `== 0`。契约里「未点亮」就是 `null`，
    /// 显示「连续 0 周」是错的：0 周意味着「一起跑过但没连续」，而实际含义是「还没点亮」。
    init?(currentWeeks: Int?, bestWeeks: Int?) {
        guard let currentWeeks, currentWeeks > 0 else { return nil }
        self.currentWeeks = currentWeeks
        self.bestWeeks = max(bestWeeks ?? currentWeeks, currentWeeks)
    }

    var isPersonalBest: Bool { currentWeeks >= bestWeeks }

    /// 距离历史最佳的进度。**只是视觉辅助**，下面 `progressText` 才是读屏拿得到的那一份。
    var progressFraction: Double {
        guard bestWeeks > 0 else { return 1 }
        return min(1, Double(currentWeeks) / Double(bestWeeks))
    }

    /// 主句。用后端定的说法（「你和张师傅已经连续 7 周一起跑步」），
    /// **刻意不做等级名称**（不叫「聊得火热」那套）——中文等级名对读屏是一串无信息的词，
    /// 而周数本身既是数字又是进度。
    func headline(partner: String) -> String {
        "\(partner)，已经连续 \(currentWeeks) 周一起跑步"
    }

    /// 进度那一行。**必须是真实文本节点** —— 进度条对 VoiceOver 是空的，
    /// 只画进度条等于对读屏用户什么都没说。
    ///
    /// ⚠️ 刻意**不提「暂停周」**（每季度 2 个、自动消耗）。用户感知不到它，
    /// 说出来会变成新的压力源（「你还有 2 次机会」）。
    var progressText: String {
        if isPersonalBest {
            return "这是你们最好的成绩"
        }
        return "距离你们最好的 \(bestWeeks) 周还差 \(bestWeeks - currentWeeks) 周"
    }
}

// MARK: - 固定搭档（盲人侧）

/// `GET /api/blind/favorite-volunteers` 的一条。SPEC-E 第 3 步给它加了两个字段。
///
/// 刻意**不含电话**：这个列表是「我跟谁跑得来」不是通讯录。要拨号走订单详情的
/// `volunteerPhone`，那里有状态门；把号码放进长期列表等于绕开那道门。
struct FavoriteVolunteerResponse: Decodable, Sendable, Equatable {
    let volunteerId: Int64?
    /// 掩码姓名（`李*`）。志愿者已注销时为 `nil`。
    let volunteerName: String?
    let completedRunsTogether: Int?
    let favoritedAt: String?

    /// 双人火花的连续周数。🚨 **未点亮时是 `null`，不是 0。** 火花开关关着时全部为 `null`。
    let streakWeeks: Int?

    /// 对方已单方面退出这一对。
    ///
    /// 🚨 **为 `true` 的条目仍然留在列表里**，不是从列表消失 —— 删掉会让盲人以为收藏丢了、
    /// 于是重新收藏一次，**把志愿者刚做的退出无声地撤销掉**，而志愿者那边不会收到任何提示。
    /// 所以这里要念成「对方已退出固定搭档」，**不能只做一个灰色态**：
    /// 一个只有视觉差异的状态，对我们的用户等于不存在。
    let partnerOptedOut: Bool?

    var hasOptedOut: Bool { partnerOptedOut == true }

    var streak: PartnerStreakDisplay? {
        PartnerStreakDisplay(currentWeeks: streakWeeks, bestWeeks: nil)
    }
}

// MARK: - 固定搭档（志愿者侧）

/// `GET /api/volunteer/favorites` 的一条：「谁把我设为固定搭档」。
///
/// 告知形式是**拉取式，不推送** —— 收藏的准入门槛是两人已经一起跑完过至少一单，
/// 志愿者本来就认识对方，这是零时效信息。
struct VolunteerFavoritedByResponse: Decodable, Sendable, Equatable {
    let blindUserId: Int64?
    /// 掩码姓名（`李*`）。盲人已注销时为 `nil`。
    let blindName: String?
    let favoritedAt: String?

    /// 我已经单方面退出这一对。
    ///
    /// ⚠️ **我已退出的条目仍然在数组里**，否则志愿者点完退出那个人就消失了，
    /// 他无从确认自己刚才做了什么。
    let optedOut: Bool?

    var hasOptedOut: Bool { optedOut == true }
}

// MARK: - 两个端点的合并（两侧共用）

/// 固定搭档页的一行 —— **盲人侧与志愿者侧共用一个类型**。
///
/// 两个端点讲的是同一批人的两件事：固定搭档列表说「谁和谁绑定了」，
/// 火花列表说「我和谁跑得久」。**分两段展示会让同一个人出现两次**，所以按 userId 合并成一行。
///
/// 🚩 **为什么必须合并两个端点，而不是只读固定搭档列表**（2026-08-23 核实后改的口径）：
/// 本仓库**根本没有**「收藏这位志愿者」的入口 —— 全仓 `favorite` 只有本地的常用出发地点
/// （`FavoritePlaceStore`），与后端的 `favorite_volunteer` 无关。
/// 所以只读固定搭档列表的话，盲人侧这一屏在 App 里**永远是空的**。
/// 而火花是由「一起跑完的订单」结算出来的，与收藏无关，不需要任何前置入口。
///
/// 覆盖面因此不完全重合，两个方向都成立：有收藏但没点亮火花、有火花但没被收藏。
struct PartnerRow: Equatable {
    let userId: Int64?
    /// 后端已掩码的姓名（`张*`）。对方已注销时为 `nil`。
    let name: String?
    /// 一起跑完过几次。只有固定搭档列表有这个数（火花列表不含）。
    let completedRunsTogether: Int?
    let favoritedAt: String?
    /// 这一对已经被单方面退出。盲人侧是「对方退出了」，志愿者侧是「我退出了」。
    let hasOptedOut: Bool
    let streak: PartnerStreakDisplay?
    /// 这一行是不是来自固定搭档列表（`false` = 只有火花，没有收藏关系）。
    let isFavorite: Bool
}

enum PartnerRowMerge {
    /// 盲人侧：`GET /api/blind/favorite-volunteers` ⋈ `GET /api/blind/partners/streaks`。
    ///
    /// 火花以 `/partners/streaks` 那条为准 —— 它多一个 `bestWeeks`，
    /// 而固定搭档列表里的 `streakWeeks` 只有当前周数。两处的当前周数口径一致（契约明说）。
    static func blindRows(
        favorites: [FavoriteVolunteerResponse],
        streaks: [PartnerStreakResponse]
    ) -> [PartnerRow] {
        merge(
            favorites: favorites.map {
                Favorite(
                    userId: $0.volunteerId,
                    name: $0.volunteerName,
                    completedRunsTogether: $0.completedRunsTogether,
                    favoritedAt: $0.favoritedAt,
                    hasOptedOut: $0.hasOptedOut,
                    fallbackStreakWeeks: $0.streakWeeks
                )
            },
            streaks: streaks
        )
    }

    /// 志愿者侧：`GET /api/volunteer/favorites` ⋈ `GET /api/volunteer/partners/streaks`。
    ///
    /// 志愿者侧的固定搭档条目**不带** `streakWeeks`（契约里就没有），所以 fallback 是 `nil`。
    static func volunteerRows(
        favorites: [VolunteerFavoritedByResponse],
        streaks: [PartnerStreakResponse]
    ) -> [PartnerRow] {
        merge(
            favorites: favorites.map {
                Favorite(
                    userId: $0.blindUserId,
                    name: $0.blindName,
                    completedRunsTogether: nil,
                    favoritedAt: $0.favoritedAt,
                    hasOptedOut: $0.hasOptedOut,
                    fallbackStreakWeeks: nil
                )
            },
            streaks: streaks
        )
    }

    private struct Favorite {
        let userId: Int64?
        let name: String?
        let completedRunsTogether: Int?
        let favoritedAt: String?
        let hasOptedOut: Bool
        let fallbackStreakWeeks: Int?
    }

    /// - 顺序：先固定搭档列表（后端按收藏时间倒序），再「只有火花」的那些（后端按周数倒序）。
    ///   两段各自保持后端给的顺序，**不重排** —— 读屏顺序播报，排序就是优先级。
    /// - `userId` 为 `nil` 的火花条目对不上任何一条收藏，仍然单独成行而不是丢弃：
    ///   丢一条就是让一段真实的关系从用户眼前消失。
    private static func merge(favorites: [Favorite], streaks: [PartnerStreakResponse]) -> [PartnerRow] {
        var streakByUser: [Int64: PartnerStreakResponse] = [:]
        for streak in streaks {
            guard let userId = streak.partnerUserId, streakByUser[userId] == nil else { continue }
            streakByUser[userId] = streak
        }

        var consumed: Set<Int64> = []
        var rows: [PartnerRow] = favorites.map { favorite in
            let matched = favorite.userId.flatMap { streakByUser[$0] }
            if let userId = favorite.userId, matched != nil { consumed.insert(userId) }
            return PartnerRow(
                userId: favorite.userId,
                name: favorite.name,
                completedRunsTogether: favorite.completedRunsTogether,
                favoritedAt: favorite.favoritedAt,
                hasOptedOut: favorite.hasOptedOut,
                streak: PartnerStreakDisplay(
                    currentWeeks: matched?.currentWeeks ?? favorite.fallbackStreakWeeks,
                    bestWeeks: matched?.bestWeeks
                ),
                isFavorite: true
            )
        }

        for streak in streaks {
            if let userId = streak.partnerUserId, consumed.contains(userId) { continue }
            rows.append(
                PartnerRow(
                    userId: streak.partnerUserId,
                    name: streak.partnerName,
                    completedRunsTogether: nil,
                    favoritedAt: nil,
                    hasOptedOut: false,
                    streak: PartnerStreakDisplay(
                        currentWeeks: streak.currentWeeks,
                        bestWeeks: streak.bestWeeks
                    ),
                    isFavorite: false
                )
            )
        }
        return rows
    }
}

// MARK: - 文案

enum PartnerStreakCopy {
    static let blindNavigationTitle = "我的固定搭档"
    static let volunteerNavigationTitle = "固定搭档"

    static let unknownVolunteerName = "这位志愿者"
    static let unknownBlindName = "这位跑者"

    /// ⚠️ 空态文案**不承诺 App 里有「收藏这位志愿者」的按钮** —— 本仓库没有这个入口
    /// （理由见 `PartnerRowMerge` 顶部）。所以这里只说火花怎么来的：那条路不需要任何前置操作，
    /// 一起跑完订单就会结算。写成「就可以把他设为固定搭档」是承诺一个不存在的功能。
    static let blindEmpty = "还没有可以显示的搭档。和同一位志愿者连续两周一起跑步之后，这里会显示你们的连续记录。"
    static let volunteerEmpty = "还没有跑者把你设为固定搭档，也还没有连续一起跑步的记录。"

    /// 🔴 逐字念得出来的表述，不是灰色态。
    static let partnerOptedOutSuffix = "对方已退出固定搭档"
    static let selfOptedOutSuffix = "你已退出"

    static let loadFailure = "暂时没能读到固定搭档，请稍后重试。"
    static let retry = "重新加载"

    // MARK: 收藏 / 取消收藏（盲人侧）

    /// 🔴 **不得写「优先派给他」。** 契约逐字：收藏只影响派单排序、不影响资格，
    /// 加分（默认 15 分）加在满分 100 的五维加权和之外，**不是压倒一切** ——
    /// 附近有个不错的陌生人时，很远的固定搭档仍然会输。
    /// 所以只能说「更可能」。承诺「优先」就是承诺一件系统做不到的事。
    static let favoriteExplanation = "设为固定搭档后，系统派单时会更可能派给他，但不保证一定是他。"

    /// 🚨 「没一起跑完过」与「这个 id 根本不是志愿者」后端**同码同文案**，
    /// 客户端不要试图区分 —— 区分开就等于确认了这个 id 是个志愿者。
    /// 所以这句只说门槛，不说「这个人不存在」。
    static let favoriteNotEligible = "还不能设为固定搭档。需要先和这位志愿者一起跑完至少一次。"

    static let favoriteLimitExceeded = "固定搭档的数量已经到上限了，先取消一位再添加。"

    static let favoriteFailed = "操作没有成功，请稍后重试。"

    static func addFavoriteTitle(_ name: String) -> String { "把\(name)设为固定搭档" }

    static func removeFavoriteTitle(_ name: String) -> String { "取消收藏\(name)" }

    static func favoriteAdded(_ name: String) -> String {
        "已把\(name)设为固定搭档。\(favoriteExplanation)"
    }

    static func favoriteRemoved(_ name: String) -> String {
        "已取消收藏\(name)。"
    }

    static func togetherText(_ count: Int?) -> String? {
        guard let count, count > 0 else { return nil }
        return "一起跑完过 \(count) 次"
    }

    static func favoritedAtText(_ raw: String?) -> String? {
        guard let day = raw?.nilIfBlank?.backendTimestamp else { return nil }
        return "\(DateFormatter.aidRunDisplayDay.string(from: day))设为固定搭档"
    }

    static func favoritedByCountText(_ count: Int) -> String {
        "有 \(count) 位跑者把你设为固定搭档"
    }

    // MARK: 退出

    static let optOutButtonTitlePrefix = "退出与"
    static let optOutButtonTitleSuffix = "的固定搭档"

    static let optOutConfirmTitle = "退出固定搭档？"

    /// 🔴 后端点名要求：**不要只做一个「确定/取消」弹窗**，后果要写进正文，
    /// 而且必须是读屏能念清楚的一整句。退出是单方面且当前不可撤销的。
    static let optOutConfirmMessage = "退出后你将不再被优先派给这位跑者，且需要重新一起跑一单才能恢复。"

    static let optOutConfirmAction = "确认退出"
    static let optOutCancel = "取消"

    static func optOutButtonTitle(_ name: String) -> String {
        "\(optOutButtonTitlePrefix)\(name)\(optOutButtonTitleSuffix)"
    }

    static func optOutSucceeded(_ name: String) -> String {
        "已退出与\(name)的固定搭档。"
    }

    static let optOutFailed = "退出没有成功，请稍后重试。"
}
