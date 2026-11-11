import Foundation

/// 服务成就、评分、徽章三页的文案（#697）。
///
/// 🔴 与 `VolunteerAchievementsCopy` 同一条红线：**禁用「证明」「证书」「已认证」**
/// （守卫 `volunteer-hours-credential` 拦）。这一页是展示，不是凭据。
enum VolunteerSecondaryPagesCopy {
    // MARK: 服务成就

    static let durationTitle = "陪伴时长"
    static let durationRange = "近 \(VolunteerServiceTrend.monthCount) 个月"

    static func durationCaption(completed: Int) -> String {
        completed > 0 ? "累计 · 共陪跑 \(completed) 次" : "累计 · 还没有完成的陪跑"
    }

    static func durationSpoken(minutes: Int64, completed: Int) -> String {
        let head = "\(durationTitle)，累计 \(VolunteerServiceTrend.duration(minutes))"
        return completed > 0 ? "\(head)，共陪跑 \(completed) 次" : "\(head)，还没有完成的陪跑"
    }

    /// 柱状图下面那行：「虚线：前 5 个月平均 1 小时 32 分钟」。
    static func averageLegend(_ minutes: Int64) -> String {
        "虚线：前 \(VolunteerServiceTrend.previousMonthCount) 个月平均 \(VolunteerServiceTrend.duration(minutes))"
    }

    static var previousAverageLabel: String {
        "前 \(VolunteerServiceTrend.previousMonthCount) 个月平均"
    }

    static func highlightSpoken(sentence: String, month: Int, current: Int64, average: Int64) -> String {
        "\(durationTitle)。\(sentence)\(month) 月 \(VolunteerServiceTrend.duration(current))，"
            + "\(previousAverageLabel) \(VolunteerServiceTrend.duration(average))"
    }

    static let mileageTitle = "累计里程"
    static let mileageUnit = "公里"

    /// 米 → 「36.4」。契约：取整成公里由客户端做；2026-08-14 前的订单没有里程快照，会少算。
    static func kilometres(_ meters: Int64?) -> String {
        RunPlanFormat.kilometresValue(Double(max(0, meters ?? 0)) / 1000)
    }

    static func mileageSpoken(_ meters: Int64?) -> String {
        "\(mileageTitle) \(kilometres(meters)) \(mileageUnit)"
    }

    static let ratingTitle = "评分"
    static let ratingEmptyValue = "--"

    static func ratingValue(_ average: Double?) -> String {
        average.map { String(format: "%.1f", $0) } ?? ratingEmptyValue
    }

    static func ratingCaption(average: Double?, total: Int?) -> String {
        guard average != nil else { return "还没有评价" }
        return "\(max(0, total ?? 0)) 条评价"
    }

    /// 屏幕上的 `--` 念出来是「破折号破折号」，没有评价时念一句话。
    static func ratingSpoken(average: Double?, total: Int?) -> String {
        guard let average else { return "\(ratingTitle)，还没有收到评价" }
        return "\(ratingTitle) \(String(format: "%.1f", average))，\(max(0, total ?? 0)) 条评价"
    }

    static let ratingCardHint = "点击查看评分"

    static let starStandard = "GB/T 40143—2021"
    static let starThresholds = "一星 100 · 二星 300 · 三星 600 小时"

    static let badgeSectionTitle = "徽章"
    static let badgeShowAll = "全部显示"
    static let badgeShowAllHint = "点击查看全部徽章"
    static let nextBadgeCaption = "下一枚"
    static let badgeEmpty = "还没有获得徽章。完成第一次陪跑服务就会获得「首次陪跑」。"

    static let aboutTitle = "关于服务成就"
    /// 口径逐字对契约 `totalServiceMinutes`：从「开始服务」到订单完成，减去手动暂停。
    static let aboutText = "陪伴时长从你点「开始服务」算到订单完成，减去暂停的时间。"
        + VolunteerAchievementsCopy.disclaimer

    // MARK: 评分页

    static let ratingsNavigationTitle = "评分"
    static let averageTitle = "平均评分"
    static let ratingScale = "/ 5"
    static let ratingRule = "评分来自跑者跑完后的评价。"
    static let highRatedTitle = "好评徽章"
    static let recentTitle = "最近的评价"
    static let recentFootnote = "点一行查看那次的跑后记录。"
    static let recentEmpty = "最近还没有完成的陪跑。"
    static let recentRowHint = "点击查看那次的跑后记录"

    static func ratingsSpoken(average: Double?, total: Int?) -> String {
        guard let average else { return "\(averageTitle)，还没有收到评价。\(ratingRule)" }
        return "\(averageTitle) \(String(format: "%.1f", average)) 分，满分 5 分，"
            + "\(max(0, total ?? 0)) 条评价。\(ratingRule)"
    }

    /// 好评徽章那一行状态。🔴 只有 `nextBadge` 正好是 `HIGH_RATED` 时才写进度，
    /// 否则只说条件 —— 别的徽章的进度不是这一枚的。
    static func highRatedStatus(_ achievements: VolunteerAchievementsResponse) -> String {
        let item = VolunteerBadgeBoard.items(achievements).first { $0.id == VolunteerBadgeCatalog.highRatedCode }
        switch item?.state {
        case .earned:
            return "已获得"
        case .inProgress(_, _, let detail):
            return "未获得 · \(detail)"
        case .locked, .none:
            return "未获得 · \(VolunteerBadgeCatalog.entry(for: VolunteerBadgeCatalog.highRatedCode)?.condition ?? "")"
        }
    }

    /// 最近的评价那一行的第二行：「和李* · 奥林匹克森林公园」。
    ///
    /// 🔴 跑者名**客户端再掩码一次**：契约没写死这个字段一定是掩码的，多掩一次对已掩码的名字没有影响。
    static func recentRowDetail(blindName: String?, address: String?) -> String {
        let name = WeChatShareCard.maskedName(blindName) ?? PartnerStreakCopy.unknownBlindName
        guard let address = address?.nilIfBlank else { return "和\(name)" }
        return "和\(name) · \(address)"
    }

    static func recentRowSpoken(date: String?, blindName: String?, address: String?, level: VolunteerRatingLevel) -> String {
        let name = (WeChatShareCard.maskedName(blindName) ?? PartnerStreakCopy.unknownBlindName).unmaskedForSpeech
        return [date, "和\(name)", address?.nilIfBlank, "评价：\(level.label)"]
            .compactMap { $0 }
            .joined(separator: "，")
    }

    /// 「11月3日」。
    static func recentDate(_ order: VolunteerDispatchSummaryRecentOrder) -> String? {
        guard let date = (order.completedAt ?? order.plannedStartTime)?.backendTimestamp else { return nil }
        return DateFormatter.aidRunDisplayMonthDay.string(from: date)
    }

    // MARK: 徽章页

    static let badgeWallTitle = "徽章"
    static let encourageTitle = "加油"
    static let badgeTapHint = "点击查看这枚徽章"
    static let badgeDetailClose = "关闭"
    static let badgeDetailEarnedText = "已获得"
    static let badgeDetailLockedText = "未获得"
}

/// 一单的评价档位。契约：三档折算成分数，`GOOD` = 5、`OK` = 4，**`PROBLEM` 对陪跑员为 null**；
/// 旧五星评价对被评人可见，所以 1–3 分也可能出现 —— 那时照实说「N 分」，不硬归到哪一档。
enum VolunteerRatingLevel: Equatable {
    case good
    case ok
    case none
    case score(Int)

    init(rating: Int?) {
        switch rating {
        case 5: self = .good
        case 4: self = .ok
        case nil: self = .none
        case let value?: self = .score(value)
        }
    }

    var label: String {
        switch self {
        case .good: return "很好"
        case .ok: return "一般"
        case .none: return "无评分"
        case .score(let value): return "\(value) 分"
        }
    }
}
