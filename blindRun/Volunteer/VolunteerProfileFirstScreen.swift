// 志愿者「我」首屏的展示口径与文案。
//
// 只 import Foundation —— 与 `VolunteerHomeIncentive.swift` / `VolunteerAchievements.swift`
// 同一个分法：这一屏**唯一会出错、且出错时没有任何运行时信号**的部分全在取舍上
// （新人看到「0 次陪跑」、徽章一排少一格、评分没有时念出「破折号破折号」），
// 那种缺陷渲染出来只是「一张看起来正常的页面」，谁都不会报障。写成纯函数才有可以验红的测试面。
//
// 设计稿 `docs/ui/mockups/volunteer-profile-first-screen-20260914/01-final-screen.html`，
// 外部依据 `docs/research/volunteer-profile-first-screen-20260914.md`。
import Foundation

// MARK: - 主指标

/// 首屏那个 3× 于其他数字的主指标。
///
/// 🔴 **`totalCompleted == 0` 时不显示「0 次陪跑」。**
/// 新人第一天打开 App，一屏上最大、最粗、最显眼的那个数字是 0 —— 那是负激励，
/// 而这一屏存在的理由恰恰是正反馈。
///
/// 这条判据本仓库已经定过一次：`VolunteerHomeIncentiveSummary.hero` 对「0 位固定搭档」
/// 做的是同一件事（`VolunteerHomeIncentive.swift:43`），只是那时让位给勋章进度。
/// 这里换成一句邀请语，因为主指标这一格没有别的东西可以顶上。
///
/// ⛔ 邀请语**不带压力句式**：不写「还差 1 单就解锁首枚勋章」「今天就开始吧」——
/// Motivation Crowding（`docs/research/volunteer-home-incentive-layer-20260914.md` §3.2），
/// 我们的志愿者是无偿的，落在挤出风险最高的一侧。
enum VolunteerProfileHeadline: Equatable {
    case newcomer
    case completed(count: Int)

    static func resolve(totalCompleted: Int?) -> VolunteerProfileHeadline {
        guard let totalCompleted, totalCompleted > 0 else { return .newcomer }
        return .completed(count: totalCompleted)
    }

    /// 新人态下**整个影响力区（3 列统计 + 星级进度）都不画**。
    ///
    /// 不是为了省地方：那三个数字此刻全是 0 / `--` / 0 小时，而「一屏只强调一个主指标」
    /// 的反面不是「强调多个」，是「把一排 0 摆出来」。星级同理 —— 一星门槛是 100 小时，
    /// 新人看到「0 / 100 小时 · 还差 100 小时」得到的信息是「你离得很远」。
    var showsImpactSections: Bool {
        if case .completed = self { return true }
        return false
    }
}

// MARK: - 作业区的两道闸

/// 「需要你处理」里那两个条件入口该不该出现。
///
/// 抽成纯函数而不是留在 View 里，理由与本文件其余部分同源：**它们出错时没有任何运行时信号**。
/// 培训闸写成 `!reasons.isEmpty` 的话，一个已经学完培训、只是临时下线的人会看到
/// 「尚未完成必修培训」—— 屏幕上仍然是一张排版正常的页面，没人会报障。
/// 同屋的 `VolunteerProfileHeadline.resolve` / `BlindHomeSOSMode.resolve` 是同一个写法。
enum VolunteerProfileTodoGate {
    /// 资质入口的条件是**两个来源的并集**，不是二选一：
    /// - `apiRejectedAsUnapproved`（`VolunteerHomeViewModel.needsCertificateUpload`）
    ///   只在某次 API 调用回了 `VOLUNTEER_NOT_APPROVED` 之后才为真；
    /// - `.notVerified` 是派单摘要里的常态原因，人没做任何操作时也在。
    ///
    /// 调用方必须把它用在**一个** `if` 上 —— 分两个 `if` 写会在两者同时成立时把入口画两遍。
    static func needsCertificateEntry(
        summary: VolunteerDispatchSummaryResponse?,
        apiRejectedAsUnapproved: Bool
    ) -> Bool {
        apiRejectedAsUnapproved || reasons(summary).contains(.notVerified)
    }

    /// 只有「必修培训没完成」这一条原因才给那张卡。
    ///
    /// 🚩 其余原因**刻意不给**：`OFFLINE` / `DISPATCH_DISABLED` 的去处是底部那条可服务 CTA
    /// 和定位提示，就在同一屏上；`NOT_VERIFIED` 走上面的资质入口。
    ///
    /// 🚩 **`summary == nil` 时返回 false，是决定不是疏漏。** 摘要拉不到意味着我们
    /// **不知道**培训做没做完，此刻画一张「尚未完成必修培训」对已经学完的人就是假话。
    /// 作业区末尾已经有错误文案 + 「重试加载」在说真话；学完之后的常驻入口在
    /// 「设置 → 陪跑培训」（`VolunteerProfileCopy.settingsHint` 已把它列进齿轮的读屏提示）。
    static func needsTrainingEntry(summary: VolunteerDispatchSummaryResponse?) -> Bool {
        reasons(summary).contains(.trainingIncomplete)
    }

    private static func reasons(
        _ summary: VolunteerDispatchSummaryResponse?
    ) -> [VolunteerDispatchNotAvailableReason] {
        summary?.notAvailableReasons ?? []
    }
}

// MARK: - 三列统计

/// 主指标下面那一行的一格。
///
/// `spoken` 与视觉分开，因为视觉上的占位符号从来不是给耳朵用的：
/// 没有评价时屏幕上是 `--`，念出来必须是「还没有收到评价」而不是「破折号破折号」
/// （成就页为这条被无障碍审计判过 `Label not human-readable`，
/// `VolunteerOrderFlowViews.swift:1979-1986` 是既有范例）。
struct VolunteerProfileStat: Equatable, Identifiable {
    /// 大字号那部分，只有数字。
    let value: String
    /// 紧跟在数字后面的小号量词；没有量词时为 `nil`（评分那格）。
    let unit: String?
    /// 数字下面那行小灰字。
    let caption: String
    let spoken: String

    var id: String { caption }
}

enum VolunteerProfileStats {
    /// 中文跑步产品的统计网格是**数值在上、小标签在下**，与 Strava 的标签在上方向相反
    /// （悦跑圈路段页，调研 §1.5 C1）。中文语境按中文的来。
    ///
    /// 三格固定顺序：陪伴时长 → 固定搭档 → 评分。前两个是「我付出了多少」，
    /// 第三个是「别人怎么看」，顺序即优先级，读屏按这个顺序念。
    static func row(
        achievements: VolunteerAchievementsResponse?,
        favoritedByCount: Int
    ) -> [VolunteerProfileStat] {
        [
            hours(achievements?.totalServiceMinutes),
            partners(favoritedByCount),
            rating(average: achievements?.avgRating, total: achievements?.totalRatings)
        ]
    }

    /// 后端给的是**分钟**，向下取整成小时 —— 51 分钟不是 1 小时。
    /// 少算而不是多算，与后端 `totalServiceMinutes` 的口径注释同一个方向。
    static func hours(_ totalServiceMinutes: Int64?) -> VolunteerProfileStat {
        let hours = max(0, totalServiceMinutes ?? 0) / 60
        return VolunteerProfileStat(
            value: "\(hours)",
            unit: VolunteerProfileCopy.hoursUnit,
            caption: VolunteerProfileCopy.hoursCaption,
            spoken: "\(VolunteerProfileCopy.hoursCaption) \(hours) \(VolunteerProfileCopy.hoursUnit)"
        )
    }

    static func partners(_ count: Int) -> VolunteerProfileStat {
        let safe = max(0, count)
        return VolunteerProfileStat(
            value: "\(safe)",
            unit: VolunteerProfileCopy.partnersUnit,
            caption: VolunteerProfileCopy.partnersCaption,
            // 播报复用既有那句完整的话（「有 8 位跑者把你设为固定搭档」）——
            // 视觉上「8 位 / 固定搭档」够了，听觉上「固定搭档 8 位」说不清是谁选了谁。
            spoken: VolunteerHomeIncentiveCopy.partnersSpoken(safe)
        )
    }

    /// 没有评价时显示 `--` 而不是编一个数（同成就页）。
    /// 副标题里的条数在 `avgRating == nil` 时**整段不出现** —— 「4.9 · 32 条」有意义，
    /// 「-- · 0 条」只是两个占位符并排。
    static func rating(average: Double?, total: Int?) -> VolunteerProfileStat {
        guard let average else {
            return VolunteerProfileStat(
                value: VolunteerProfileCopy.ratingPlaceholder,
                unit: nil,
                caption: VolunteerProfileCopy.ratingCaption,
                spoken: VolunteerProfileCopy.ratingSpokenWhenEmpty
            )
        }
        let value = String(format: "%.1f", average)
        let count = max(0, total ?? 0)
        let caption = count > 0
            ? "\(VolunteerProfileCopy.ratingCaption) · \(count) \(VolunteerProfileCopy.ratingCountUnit)"
            : VolunteerProfileCopy.ratingCaption
        return VolunteerProfileStat(
            value: value,
            unit: nil,
            caption: caption,
            spoken: count > 0
                ? "\(VolunteerProfileCopy.ratingCaption) \(value)，共 \(count) \(VolunteerProfileCopy.ratingCountUnit)"
                : "\(VolunteerProfileCopy.ratingCaption) \(value)"
        )
    }
}

// MARK: - 徽章一排

/// 首屏那一排徽章。**只放一排，其余进成就页**（Strava Overview 的 Trophies 行 + `View more`，
/// 调研 §1.2 S8）—— 徽章铺满首屏会变成一片图标噪音，前几枚的意义随之被稀释。
enum VolunteerProfileBadgeRow {
    /// 一排四格。与成就页 `VolunteerBadgeWall.previewLimit` 的 4 是同一个视觉密度，
    /// 但这里最后一格**可能**让给「下一枚」的虚线圈，所以不能直接复用那个常量。
    static let cellCount = 4

    enum Cell: Equatable, Identifiable {
        /// 已解锁。
        case unlocked(VolunteerBadgeDto)
        /// 下一枚未解锁的，画成虚线圈 + 进度（「夜跑守护 3/5」）。
        case next(VolunteerNextBadgeDto)

        var id: String {
            switch self {
            case .unlocked(let badge): return "unlocked-\(badge.id)"
            case .next(let badge): return "next-\(badge.displayName)"
            }
        }
    }

    /// 已解锁的排前面，末位留给「下一枚」。
    ///
    /// 🚩 **「下一枚」只在拿得到给人看的名字时才占那一格**（`hasDisplayableName`）：
    /// 后端没发 `name` 时 `displayName` 会退到 `code`（`HOURS_10` 这种英文枚举）或
    /// 「下一枚勋章」，两者上屏都是噪音。判据与首页那张卡的 `showsBadgeRow` 一致
    /// （`VolunteerHomeIncentive.swift:88`），不新造一套。
    ///
    /// 七枚全解锁时 `next` 为 null，四格全给已解锁的。
    static func cells(
        unlocked: [VolunteerBadgeDto],
        next: VolunteerNextBadgeDto?
    ) -> [Cell] {
        let showsNext = next?.hasDisplayableName == true
        let unlockedLimit = showsNext ? cellCount - 1 : cellCount
        var cells = unlocked.prefix(unlockedLimit).map(Cell.unlocked)
        if showsNext, let next {
            cells.append(.next(next))
        }
        return cells
    }

    /// 「下一枚」格子上的那行小字：`夜跑守护 3/5`。
    ///
    /// 🔴 **不写「还差 N 就解锁」** —— `HIGH_RATED` 是「均分 ≥ 4.8 **且** ≥ 10 条评价」的
    /// 双条件，进度条满格也可能没解锁，那句话会变成我们兑现不了的承诺
    /// （理由逐字在 `VolunteerNextBadgeDto` 顶部）。
    ///
    /// 未知 `code` 拿不到量词时只给名字，不拼一个猜的分母。
    static func nextBadgeCaption(_ next: VolunteerNextBadgeDto) -> String {
        guard let unit = next.progressUnit,
              let target = next.target, target > 0,
              let current = next.current, current >= 0 else {
            return next.displayName
        }
        return "\(next.displayName) \(unit.display(current))/\(unit.display(target))"
    }

    /// 「全部 N 枚 ›」里的 N 是**已解锁的枚数**，不是勋章总数。
    ///
    /// 🚩 后端 `badges[]` **只含已解锁的**（契约：「未解锁的不出现在列表里」），
    /// 客户端**拿不到总数**。设计稿上写的「全部 7 枚」是拿后端枚举的个数填的 ——
    /// 那个 7 住在后端 `VolunteerBadge` 里，客户端镜像它必然漂移，
    /// 而且解锁 3 枚的人点进去只会看到 3 枚，标题却说 7 枚。
    static func allLinkTitle(unlockedCount: Int) -> String {
        let count = max(0, unlockedCount)
        guard count > 0 else { return VolunteerProfileCopy.badgesLinkTitleWhenEmpty }
        return "全部 \(count) 枚"
    }
}

// MARK: - 最近陪跑

/// 「最近陪跑」左侧那个日期格：大号日 + 小号月（`13` / `9月`）。
enum VolunteerProfileRecentDate {
    /// 解析失败时返回 `nil`，那一格整块不画 —— 不显示 `--` 也不拿今天顶上。
    ///
    /// ponytail: 走 `Calendar` 取两个数字，不新配 `DateFormatter`。
    /// 多一个格式器就多一处「同一个月在两个地方写法不同」的来源。
    static func parts(from timestamp: String?) -> (day: String, month: String)? {
        guard let date = timestamp?.nilIfBlank?.backendTimestamp else { return nil }
        let components = Calendar.current.dateComponents([.day, .month], from: date)
        guard let day = components.day, let month = components.month else { return nil }
        return ("\(day)", "\(month)月")
    }
}

// MARK: - 文案

/// 志愿者「我」首屏的文案。
///
/// 🔴 **禁用「证明」「证书」「已认证」**（民政部令第 67 号，守卫 `volunteer-hours-credential`）。
/// 这一屏把服务时长和国标星级摆在最显眼的位置，是这条红线最容易被踩到的地方。
///
/// 🔴 **不催促、不倒计时、不设会变的门槛、不折算金额**
/// （`docs/research/volunteer-home-incentive-layer-20260914.md` §3）。
/// 星级那条「还差 N 小时」是允许的，因为门槛是**国家标准定的外部固定值**、不随用户表现漂移
/// ——「本月 8/10 次」那种自己跟自己比的目标才是 Moving Target。
enum VolunteerProfileCopy {
    // 身份行
    static let roleTitle = "陪跑志愿者"
    static let settingsTitle = "设置"
    /// 🔴 **这句必须把设置里真有的东西列全。** 它是「陪跑培训」的**常驻**入口
    /// （`VolunteerOrderFlowViews.swift` 的设置列表里）唯一的可发现性来源 ——
    /// 首屏那个显眼的培训卡只在 `TRAINING_INCOMPLETE` 时出现，学完就消失，
    /// 而选修课和复习要靠这一条进。2026-09-15 补上「培训」二字：在此之前它逐条列了
    /// 六样却独独漏了培训，读屏用户按 hint 根本不知道能从这儿进去。
    static let settingsHint = "昵称、资质、培训、积分、固定搭档、邀请码和账号"

    static func roleSubtitle(starLevel: Int?) -> String {
        let current = max(0, starLevel ?? 0)
        guard current > 0 else { return roleTitle }
        return "\(roleTitle) · \(VolunteerAchievementsCopy.starTitle(current: current))"
    }

    // 主指标
    static let impactSectionTitle = "我的陪伴"
    static let heroUnit = "次陪跑"

    /// 新人那句话。陈述现状 + 说清下一步在哪，**不催**。
    static let newcomerHeadline = "还没有完成的陪跑"
    static let newcomerDetail = "开启下面的\(VolunteerAvailabilityCopy.toggleTitle)后，系统会给你派第一单。"

    static func heroSpoken(_ headline: VolunteerProfileHeadline) -> String {
        switch headline {
        case .newcomer:
            return "\(impactSectionTitle)。\(newcomerHeadline)。\(newcomerDetail)"
        case .completed(let count):
            return "\(impactSectionTitle)。已完成 \(count) \(heroUnit)。"
        }
    }

    // 三列统计
    static let hoursCaption = "陪伴时长"
    static let hoursUnit = "小时"
    static let partnersCaption = "固定搭档"
    static let partnersUnit = "位"
    static let ratingCaption = "评分"
    static let ratingCountUnit = "条"
    static let ratingPlaceholder = "--"
    static let ratingSpokenWhenEmpty = "还没有收到评价"

    // 徽章
    static let badgesSectionTitle = "我的徽章"
    static let badgesLinkTitleWhenEmpty = "查看全部"
    static let badgesLinkHint = "打开服务成就，查看国标星级、全部勋章和累计服务时长"
    static let badgesEmpty = "完成第一次陪跑就会解锁第一枚徽章。"

    // 最近陪跑
    static let recentSectionTitle = "最近陪跑"
    static let recentLinkTitle = "全部"
    static let recentLinkHint = "打开服务记录，查看全部已完成和已取消的陪跑"
    static let recentEmpty = "完成陪跑后会显示在这里。"

    static func recentRowTitle(blindName: String?) -> String {
        "与 \(blindName?.nilIfBlank ?? "跑者") 同跑"
    }

    // 作业区
    static let todoSectionTitle = "需要你处理"

    // 必修培训入口
    //
    // 🔴 **标题不在这里定义。** 它复用
    // `VolunteerDispatchNotAvailableReason.trainingIncomplete.displayText`（「尚未完成必修培训」）
    // —— 那是「为什么接不到单」的权威说法，在这里抄第二份就会和派单卡里的原因列表漂移。

    /// 说明句。陈述规则 + 说清点下去会发生什么，**不催**（激励层红线，见类型注释）。
    static let trainingEntryDetail = "完成必修课程后才会收到系统派单。点这里开始学，学完即可接单。"
    static let trainingEntryHint = "打开陪跑培训，完成必修课程后即可接单"
}
