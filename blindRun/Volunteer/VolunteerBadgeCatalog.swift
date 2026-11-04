import Foundation

// MARK: - 7 枚徽章的目录

/// 徽章所属的一类。每类一种形状和材质（照健身 App 奖章：挑战 = 金属边六边形、
/// 训练 = 金边深色圆章、竞赛 = 盾形），负责人 2026-11-04 批准。
enum VolunteerBadgeCategory: String, CaseIterable, Equatable {
    /// 银边蓝面六边形，正中刻次数。
    case runs
    /// 金边深色圆章，刻小时数。
    case hours
    /// 银边琥珀盾形，刻一颗心。
    case rating
    /// 服务端返回了目录里没有的 code（后端加了新徽章、App 还没跟上）。
    case other

    var title: String {
        switch self {
        case .runs: return "陪跑次数"
        case .hours: return "陪伴时长"
        case .rating: return "评价"
        case .other: return "其他"
        }
    }
}

/// 目录里的一枚。
struct VolunteerBadgeCatalogEntry: Equatable {
    let code: String
    /// 网格与弹层上的短名字。照批准的稿子写（「陪跑 10 次」），不用后端的长名字
    /// （「陪跑达人 · 10 次」）：一排四枚的格子放不下，且已获得与未获得要用同一套叫法。
    let name: String
    /// 网格格子下面的名字。半宽卡里放不下「陪伴 10 小时」，稿子写「10 小时」；类别标题已经说了是陪伴时长。
    var gridName: String?
    let category: VolunteerBadgeCategory
    /// 奖章正中的大字（「10」）。为 nil 时画 `glyph`。
    let engraving: String?
    /// 大字下面那个量词（「次」「小时」）。
    let engravingUnit: String?
    /// 刻图案的 SF Symbol（评价那枚是一颗心）。
    let glyph: String?
    /// 弹层里的「怎么获得」。
    ///
    /// 🔴 `HIGH_RATED` **不写 4.8 这个阈值**：后端刻意不下发，抄进客户端一改就漂移
    /// （同 `VolunteerNextBadgeDto.ratingShortNote`）。次数和小时数本来就写在名字里。
    let condition: String
}

/// **客户端写死的 7 枚**（#697）。
///
/// 为什么要写死：后端 `badges` 只含已解锁的，`nextBadge` 只有一枚 —— 要把没获得的也画出来，
/// 客户端必须知道一共有哪些。顺序 = 后端 `VolunteerBadge` 的声明顺序。
///
/// ⚠️ 后端加徽章时这里要同步（PR #697 交接里写了）。没同步时新徽章走 `.other`，
/// 照常显示服务端给的名字，不会丢、也不会让整页解码失败。
enum VolunteerBadgeCatalog {
    static let entries: [VolunteerBadgeCatalogEntry] = [
        VolunteerBadgeCatalogEntry(
            code: "FIRST_RUN", name: "首次陪跑", category: .runs,
            engraving: "1", engravingUnit: "次", glyph: nil,
            condition: "完成第一次陪跑服务。"
        ),
        VolunteerBadgeCatalogEntry(
            code: "RUNS_10", name: "陪跑 10 次", category: .runs,
            engraving: "10", engravingUnit: "次", glyph: nil,
            condition: "累计完成 10 次陪跑服务。"
        ),
        VolunteerBadgeCatalogEntry(
            code: "RUNS_50", name: "陪跑 50 次", category: .runs,
            engraving: "50", engravingUnit: "次", glyph: nil,
            condition: "累计完成 50 次陪跑服务。"
        ),
        VolunteerBadgeCatalogEntry(
            code: "RUNS_100", name: "陪跑 100 次", category: .runs,
            engraving: "100", engravingUnit: "次", glyph: nil,
            condition: "累计完成 100 次陪跑服务。"
        ),
        VolunteerBadgeCatalogEntry(
            code: "HOURS_10", name: "陪伴 10 小时", gridName: "10 小时", category: .hours,
            engraving: "10", engravingUnit: "小时", glyph: nil,
            condition: "累计陪伴满 10 小时。"
        ),
        VolunteerBadgeCatalogEntry(
            code: "HOURS_50", name: "陪伴 50 小时", gridName: "50 小时", category: .hours,
            engraving: "50", engravingUnit: "小时", glyph: nil,
            condition: "累计陪伴满 50 小时。"
        ),
        VolunteerBadgeCatalogEntry(
            code: "HIGH_RATED", name: "好评", category: .rating,
            engraving: nil, engravingUnit: nil, glyph: "heart.fill",
            condition: "评价条数和评分都达到要求后获得。"
        )
    ]

    static let highRatedCode = "HIGH_RATED"

    static func entry(for code: String?) -> VolunteerBadgeCatalogEntry? {
        guard let code else { return nil }
        return entries.first { $0.code == code }
    }
}

// MARK: - 每一枚现在的状态

/// 一枚徽章此刻的样子。
enum VolunteerBadgeState: Equatable {
    case earned
    /// 只有 `nextBadge` 那一枚有进度（后端只给这一枚）。
    case inProgress(fraction: Double, shortText: String, detailText: String)
    case locked

    var isEarned: Bool { self == .earned }

    /// 网格上名字下面那一行：「已获得」「7 / 10」「未获得」。
    var shortText: String {
        switch self {
        case .earned: return "已获得"
        case .inProgress(_, let shortText, _): return shortText
        case .locked: return "未获得"
        }
    }
}

/// 网格里的一格。
struct VolunteerBadgeItem: Identifiable, Equatable {
    let id: String
    let name: String
    /// 网格上的短名字；读屏和弹层仍用 `name`。
    var gridName: String
    let category: VolunteerBadgeCategory
    let engraving: String?
    let engravingUnit: String?
    let glyph: String?
    let condition: String
    let state: VolunteerBadgeState

    /// 一枚一个焦点：「陪跑 10 次，未获得，已完成 7 次，共需 10 次」（稿子「读屏」那一栏）。
    var spoken: String {
        switch state {
        case .earned:
            return "\(name)，已获得"
        case .inProgress(_, _, let detail):
            return "\(name)，未获得，\(detail)"
        case .locked:
            return "\(name)，未获得，\(condition)"
        }
    }

    /// 弹层里状态下面那一行。已获得说怎么获得的；有进度说进度；没进度说条件。
    var detailLine: String {
        switch state {
        case .earned, .locked: return condition
        case .inProgress(_, _, let detail): return detail
        }
    }
}

/// 徽章页上的一块（一类）。
struct VolunteerBadgeSection: Identifiable, Equatable {
    let category: VolunteerBadgeCategory
    let items: [VolunteerBadgeItem]

    var id: VolunteerBadgeCategory { category }
}

/// 把 `GET /api/volunteer/achievements` 摆成整面徽章墙。纯函数，单测直接打这里。
enum VolunteerBadgeBoard {
    /// 目录里 7 枚按声明顺序，后面接服务端返回的、目录里没有的已解锁徽章（`.other`）。
    static func items(_ response: VolunteerAchievementsResponse) -> [VolunteerBadgeItem] {
        let unlocked = response.unlockedBadges
        let unlockedCodes = Set(unlocked.compactMap { $0.code?.nilIfBlank })
        let next = response.nextBadge

        let known = VolunteerBadgeCatalog.entries.map { entry -> VolunteerBadgeItem in
            let state: VolunteerBadgeState
            if unlockedCodes.contains(entry.code) {
                state = .earned
            } else if let next, next.code == entry.code {
                state = progressState(next)
            } else {
                state = .locked
            }
            return VolunteerBadgeItem(
                id: entry.code,
                name: entry.name,
                gridName: entry.gridName ?? entry.name,
                category: entry.category,
                engraving: entry.engraving,
                engravingUnit: entry.engravingUnit,
                glyph: entry.glyph,
                condition: entry.condition,
                state: state
            )
        }

        // 🔴 未知 code 不许丢：服务端说你拿到了，这一页就要有它（AGENTS.md「枚举遇未知值不许整条崩」）。
        let unknown = unlocked
            .filter { VolunteerBadgeCatalog.entry(for: $0.code) == nil }
            .enumerated()
            .map { index, badge in
                VolunteerBadgeItem(
                    // 带上下标：两条同名的未知徽章也不会撞 id。
                    id: "other.\(index).\(badge.id)",
                    name: badge.displayName,
                    gridName: badge.displayName,
                    category: .other,
                    engraving: nil,
                    engravingUnit: nil,
                    glyph: "rosette",
                    condition: unknownCondition,
                    state: .earned
                )
            }
        return known + unknown
    }

    /// 一类一块，空的块不出现。
    static func sections(_ items: [VolunteerBadgeItem]) -> [VolunteerBadgeSection] {
        VolunteerBadgeCategory.allCases.compactMap { category in
            let inCategory = items.filter { $0.category == category }
            return inCategory.isEmpty ? nil : VolunteerBadgeSection(category: category, items: inCategory)
        }
    }

    static func earnedCount(_ items: [VolunteerBadgeItem]) -> Int {
        items.filter { $0.state.isEarned }.count
    }

    /// 「已获得 2 枚 / 共 7 枚」。
    static func countText(_ items: [VolunteerBadgeItem]) -> String {
        "已获得 \(earnedCount(items)) 枚 / 共 \(items.count) 枚"
    }

    static let unknownCondition = "平台新增的徽章，更新 App 后可以看到获得条件。"

    /// `nextBadge` → 进度。单位未知或分母为 0 时没有进度，按未获得画（契约：整块进度隐藏）。
    static func progressState(_ next: VolunteerNextBadgeDto) -> VolunteerBadgeState {
        guard let unit = next.progressUnit,
              let fraction = next.progressFraction,
              let current = next.current,
              let target = next.target else {
            return .locked
        }
        let shown = unit.display(current)
        let goal = unit.display(target)
        // 🔴 评价那枚是双条件，「共需 10 条」会被读成「够 10 条就能拿到」，所以只说已有多少。
        var detail = unit == .ratings
            ? "已有 \(shown) / \(goal) \(unit.suffix)"
            : "已完成 \(shown) \(unit.suffix)，共需 \(goal) \(unit.suffix)"
        if next.isBlockedByRating {
            detail += "，\(VolunteerNextBadgeDto.ratingShortNote)"
        }
        return .inProgress(fraction: fraction, shortText: "\(shown) / \(goal)", detailText: detail)
    }

    /// 「加油」卡第二行：「7 / 10 次 · 再陪跑 3 次」。
    ///
    /// 🔴 只有单条件的次数 / 时长徽章才说「再 …」。`HIGH_RATED` 是双条件，
    /// 条数够了也可能拿不到，那句话会变成兑现不了的承诺（`VolunteerNextBadgeDto` 顶部）。
    static func encouragementText(_ next: VolunteerNextBadgeDto) -> String? {
        guard let unit = next.progressUnit,
              let current = next.current,
              let target = next.target,
              target > 0, current >= 0 else {
            return nil
        }
        let progress = "\(unit.display(current)) / \(unit.display(target)) \(unit.suffix)"
        let remaining = max(0, target - current)
        switch unit {
        case .runs where remaining > 0:
            return "\(progress) · 再陪跑 \(remaining) 次"
        case .minutes where remaining > 0:
            return "\(progress) · 再陪伴 \(RunRecordHistoryViewModel.serviceDuration(remaining))"
        case .ratings where next.isBlockedByRating:
            return "\(progress) · \(VolunteerNextBadgeDto.ratingShortNote)"
        default:
            return progress
        }
    }

    /// 「加油」卡的名字：目录里的短名字优先，目录里没有时用服务端的名字。
    static func nextName(_ next: VolunteerNextBadgeDto) -> String {
        VolunteerBadgeCatalog.entry(for: next.code)?.name ?? next.displayName
    }
}
