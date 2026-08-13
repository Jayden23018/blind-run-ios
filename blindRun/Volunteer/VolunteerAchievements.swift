import Foundation

// MARK: - Contract

/// `GET /api/volunteer/achievements` 的响应。
///
/// ⚠️ **不套 `ApiResponse` 信封**（与同控制器的 `GET /api/volunteer/profile` 一致，
/// 但与 `GET /api/volunteer/dispatch-summary` **不同** —— 后者是套的。
/// `api_spec.yaml` 那条 description 逐字写着「别照抄解析代码」）。
///
/// 全部字段可选：这份响应喂的是一个低频只读页面，缺一个字段该少显示一行，
/// 而不是整页空白 —— 对志愿者是体验问题，但同一套解码习惯在盲人端就是事故。
struct VolunteerAchievementsResponse: Decodable, Sendable, Equatable {
    let totalCompleted: Int?
    let totalServiceMinutes: Int64?
    let avgRating: Double?
    let totalRatings: Int?

    /// **只含已解锁的勋章**（契约：「未解锁的不出现在列表里」）。
    ///
    /// 🔴 **不要按「全量 + unlocked 布尔」去理解它。** 后端 SPEC-D §D1.2 把这条列为整份
    /// SPEC 最容易出事的地方：真改成全量的话，已发版客户端不认识 `unlocked`，
    /// 会把七枚勋章一律当已解锁渲染，而 `openapi-diff` 只看到「加了两个可选字段」，判绿。
    let badges: [VolunteerBadgeDto]?

    /// 下一枚未解锁的勋章；**七枚全解锁时为 `null`**（后端 `9f8606d` 已上线）。
    ///
    /// 「下一枚」= 勋章**声明顺序**里第一枚未解锁的，不是「最接近达成的那枚」——
    /// 按达成率重排会让这个字段在两枚勋章之间反复横跳。
    let nextBadge: VolunteerNextBadgeDto?

    /// 国标星级。契约里**恒非 null**，未达一星时 `current = 0`（不是「没有星级数据」）。
    ///
    /// 这里仍收成 optional 并配本地兜底：少一个字段不该让整栏空白。
    /// 兜底算的是同一套公开国标门槛，与后端算出同一个数，不构成第二个真相源。
    let starLevel: VolunteerStarLevelDto?

    /// 服务端给了就用服务端的。走到 `derive` 说明契约承诺的「恒非 null」没兑现，
    /// 是防御路径不是常规路径。
    var resolvedStarLevel: VolunteerStarLevelDto {
        starLevel ?? VolunteerStarLevel.derive(totalServiceMinutes: totalServiceMinutes ?? 0)
    }

    var completedCount: Int { totalCompleted ?? 0 }

    /// 已解锁勋章。丢掉既没有 `code` 也没有 `name` 的条目：那种条目渲染出来是一个空格子，
    /// 对读屏用户则是一个没有内容的可聚焦元素。
    var unlockedBadges: [VolunteerBadgeDto] {
        (badges ?? []).filter { $0.identity != nil }
    }
}

/// 一枚已解锁的勋章。`code` 是**开放枚举** —— 遇到不认识的值照常显示 `name`，
/// 只是图标退回默认，绝不因此让整条响应解析失败（AGENTS.md「未知枚举值不许整条崩」）。
struct VolunteerBadgeDto: Decodable, Sendable, Equatable, Identifiable {
    let code: String?
    let name: String?

    /// 去掉空白后的稳定标识。两个都缺时为 `nil`，该条目应被丢弃。
    var identity: String? {
        code?.nilIfBlank ?? name?.nilIfBlank
    }

    var id: String { identity ?? "" }

    var displayName: String { name?.nilIfBlank ?? code?.nilIfBlank ?? "未知勋章" }

    /// SF Symbol。未知 `code` 落到通用图标而不是空白 —— 图标是这一栏区分档位的
    /// 非颜色手段之一（WCAG 1.4.1），缺了它低视力用户只剩一片同色文字。
    var symbolName: String {
        switch code {
        case "FIRST_RUN": return "figure.run"
        case "RUNS_10": return "star.fill"
        case "RUNS_50": return "trophy.fill"
        case "RUNS_100": return "crown.fill"
        case "HOURS_10": return "clock.fill"
        case "HOURS_50": return "clock.badge.checkmark.fill"
        case "HIGH_RATED": return "heart.fill"
        default: return "rosette"
        }
    }
}

/// 下一枚未解锁的勋章及其进度。
///
/// ⚠️ **`current` / `target` 的单位随 `code` 变，契约里没有 `unit` 字段。**
/// 后端的说法是：客户端本来就要按 `code` 选图标，顺带选量词是同一次查表。
///
/// | code | 单位 |
/// |---|---|
/// | `FIRST_RUN` / `RUNS_*` | 次 |
/// | `HOURS_10` / `HOURS_50` | **分钟**（不是小时）—— 展示前要换算 |
/// | `HIGH_RATED` | 条评价 |
///
/// 🔴 **`HIGH_RATED` 的进度只反映「评价条数」一维。** 它是双条件（均分 ≥ 4.8 **且**
/// ≥ 10 条评价），进度条跟的是条数，所以会出现**进度条满格但勋章仍未解锁**
/// （20 条评价、均分 4.0）。因此这一栏的文案**一律不写「还差 N 就解锁」** ——
/// 只陈述已完成多少，不承诺达到分母就会解锁。
struct VolunteerNextBadgeDto: Decodable, Sendable, Equatable {
    let code: String?
    let name: String?
    let current: Int64?
    let target: Int64?

    var displayName: String { name?.nilIfBlank ?? code?.nilIfBlank ?? "下一枚勋章" }

    /// 进度的量词与换算方式。未知 `code` 为 `nil` ——
    /// 契约要求此时**把整块进度条隐藏**，而不是拿一个猜的量词硬拼。
    enum ProgressUnit {
        /// 次。原值直接用。
        case runs
        /// 后端给的是**分钟**，展示成小时（向下取整，与 `currentHours` 同口径）。
        case minutes
        /// 条评价。
        case ratings

        var suffix: String {
            switch self {
            case .runs: return "次"
            case .minutes: return "小时"
            case .ratings: return "条评价"
            }
        }

        func display(_ raw: Int64) -> Int64 {
            switch self {
            case .minutes: return raw / 60
            case .runs, .ratings: return raw
            }
        }
    }

    var progressUnit: ProgressUnit? {
        switch code {
        case "FIRST_RUN", "RUNS_10", "RUNS_50", "RUNS_100": return .runs
        case "HOURS_10", "HOURS_50": return .minutes
        case "HIGH_RATED": return .ratings
        default: return nil
        }
    }

    /// 只有单位已知、`target > 0` 且 `current` 可比时才画进度。
    /// 未知 `code` 或分母为 0 时整块隐藏 —— 不显示 `0/0`，也不拼一个猜的量词。
    var progressFraction: Double? {
        guard progressUnit != nil, let target, target > 0, let current, current >= 0 else { return nil }
        return min(1, Double(current) / Double(target))
    }

    /// **不写「还差 N 就解锁」** —— `HIGH_RATED` 满格也可能不解锁。
    var progressText: String? {
        guard let unit = progressUnit, let target, target > 0, let current, current >= 0 else {
            return nil
        }
        return "已完成 \(unit.display(current)) / \(unit.display(target)) \(unit.suffix)"
    }
}

/// 国标星级。字段与后端 SPEC-D §D1.3 一致。
struct VolunteerStarLevelDto: Decodable, Sendable, Equatable {
    /// 0 = 未达一星，1...5。
    let current: Int?
    let currentHours: Int64?
    /// 下一星门槛（小时）；五星后为 `null`。
    let nextTarget: Int64?
}

// MARK: - 国标星级

/// 国家标准 **GB/T 40143—2021** 的志愿服务星级门槛（累计小时）。
///
/// **为什么这个能放在客户端算，而平台勋章的阈值不能：**
///
/// - 星级门槛是**公开的国家标准**，不随平台业务代码变。后端已发布 `starLevel`
///   （契约里恒非 null），这里只是字段缺失时的防御路径，两边算出同一个数，不构成漂移。
/// - 平台勋章的阈值住在后端 `VolunteerBadge.isUnlockedBy` 的穷举 switch 里，
///   那段代码的注释写着「要改阈值时改这里一行即可」—— 客户端镜像它必然漂移。
///   而且 `HIGH_RATED` 是「均分 ≥ 4.8 **且** 评价 ≥ 10 条」的双条件，
///   单一阈值根本表达不了。所以那一栏一律用 `nextBadge`，不本地编。
///
/// 这也是国标星级与平台勋章**必须分两栏**的原因：平台最高的时长勋章是 50 小时，
/// 够不着一星的 100 小时。合并展示会让志愿者以为拿了最高勋章就能去学校评星。
enum VolunteerStarLevel {
    /// 一到五星的门槛（小时）。
    static let hourThresholds: [Int64] = [100, 300, 600, 1000, 1500]

    static let maximumStar = hourThresholds.count

    static func derive(totalServiceMinutes: Int64) -> VolunteerStarLevelDto {
        // 向下取整：51 分钟不是 1 小时。少算而不是多算，与后端 `totalServiceMinutes`
        // 的口径注释同一个方向。
        let hours = max(0, totalServiceMinutes) / 60
        let current = hourThresholds.filter { hours >= $0 }.count
        return VolunteerStarLevelDto(
            current: current,
            currentHours: hours,
            nextTarget: current < hourThresholds.count ? hourThresholds[current] : nil
        )
    }
}

// MARK: - 文案

/// 成就页文案。
///
/// 🔴 **禁用「证明」「证书」「已认证」。** 可出具、可查验的志愿服务记录须经志愿服务信息系统
/// 出具（民政部令第 67 号），第三方平台的时长要有法律效力必须先与全国志愿服务信息系统完成
/// 数据对接 —— 我们没有。把这页写成一份凭据是违规的，不是措辞问题。
/// 守卫规则 `volunteer-hours-credential`（`scripts/hooks/guard.mjs`）拦这类措辞。
enum VolunteerAchievementsCopy {
    static let navigationTitle = "服务成就"

    static let starSectionTitle = "国标星级"
    static let starSectionStandard = "国家标准 GB/T 40143—2021"
    static let badgeSectionTitle = "平台勋章"

    /// 这一页是展示，不是凭据。**不出现「证明」「证书」「已认证」**，
    /// 同时要说清对外申报走哪条路，否则志愿者会以为在这里就办完了。
    static let disclaimer = "以上数据来自平台记录，供你自己查看。向学校或单位申报星级需要通过全国志愿服务信息系统办理。"

    static let badgeSectionEmpty = "还没有解锁的勋章。完成第一次陪跑服务就会解锁「首次陪跑」。"

    /// 平台勋章的进度来自后端 `nextBadge`；七枚全解锁时该字段为 null，这一段整条不显示。
    ///
    /// 🔴 标题**不带「还差…就解锁」**：`HIGH_RATED` 是双条件，进度条满格也可能没解锁，
    /// 那句话会变成一个我们兑现不了的承诺。
    static let nextBadgeSectionTitle = "下一枚勋章"

    static func starTitle(current: Int) -> String {
        guard current > 0 else { return "尚未达到一星" }
        let numerals = ["一", "二", "三", "四", "五"]
        let index = min(current, numerals.count) - 1
        return "\(numerals[index])星"
    }

    /// 进度那一行。**必须是真实文本节点**：进度条对 VoiceOver 是空的，
    /// 把「还差 58 小时」只画进进度条等于对读屏用户什么都没说。
    static func starProgressText(_ level: VolunteerStarLevelDto) -> String {
        let hours = max(0, level.currentHours ?? 0)
        guard let nextTarget = level.nextTarget, nextTarget > 0 else {
            return "累计 \(hours) 小时，已达最高星级。"
        }
        let remaining = max(0, nextTarget - hours)
        return "\(hours) / \(nextTarget) 小时 · 还差 \(remaining) 小时"
    }

    /// 星级栏合成一个 VoiceOver 焦点后的完整朗读文本。
    /// 标题、门槛、进度三样都在里面 —— 分开念会让用户听三遍同一件事，
    /// 但少念任何一样，「还差多少」就丢了。
    static func starAccessibilityLabel(_ level: VolunteerStarLevelDto) -> String {
        let current = max(0, level.current ?? 0)
        let hours = max(0, level.currentHours ?? 0)
        guard let nextTarget = level.nextTarget, nextTarget > 0 else {
            return "\(starSectionTitle)，\(starTitle(current: current))，累计 \(hours) 小时，已达最高星级。"
        }
        let remaining = max(0, nextTarget - hours)
        return "\(starSectionTitle)，\(starTitle(current: current))，累计 \(hours) 小时，还差 \(remaining) 小时到\(starTitle(current: min(current + 1, VolunteerStarLevel.maximumStar)))。"
    }

    static func badgeAccessibilityLabel(_ badge: VolunteerBadgeDto) -> String {
        "\(badge.displayName)，已解锁"
    }

    static func nextBadgeAccessibilityLabel(_ next: VolunteerNextBadgeDto) -> String {
        guard let progress = next.progressText else {
            return "\(nextBadgeSectionTitle)，\(next.displayName)"
        }
        return "\(nextBadgeSectionTitle)，\(next.displayName)，\(progress)"
    }

    static func summarySpeech(_ response: VolunteerAchievementsResponse) -> String {
        let level = response.resolvedStarLevel
        let completed = response.completedCount
        let head = completed > 0
            ? "已完成 \(completed) 次陪跑服务。"
            : "还没有完成的服务。"
        return head + starAccessibilityLabel(level)
    }
}

// MARK: - 主页只露 4 枚

/// 成就页主页最多露几枚勋章，其余收进二级页。
///
/// 抄 Strava：勋章全铺开会变成一片图标噪音，前几枚的意义随之被稀释。
/// 后端最多七枚（`VolunteerBadge` 七个值），所以二级页只在解锁 5 枚以上时才出现。
enum VolunteerBadgeWall {
    static let previewLimit = 4

    static func preview(_ badges: [VolunteerBadgeDto]) -> [VolunteerBadgeDto] {
        Array(badges.prefix(previewLimit))
    }

    static func hasMore(_ badges: [VolunteerBadgeDto]) -> Bool {
        badges.count > previewLimit
    }

    static func moreLinkTitle(_ badges: [VolunteerBadgeDto]) -> String {
        "查看全部 \(badges.count) 枚勋章"
    }
}
