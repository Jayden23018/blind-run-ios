import Combine
import Foundation

// 陪跑员首页 v3 的卡片取值（负责人 2026-11-04 定稿，#694；样例 `docs/ui/mockups/volunteer-home-v3-20261104/`）。
//
// 视图在 `VolunteerProfileFirstScreenView+*.swift`。这里只放会悄悄出错的取舍：
// 半宽卡没有火花时退到哪、最近陪跑本月为空退到哪、缩略图什么时候不画。
// 这些出错时屏幕上仍是一张排版正常的卡片，所以写成纯函数，留给单测钉住。

// MARK: - 陪伴时长卡右侧的星级进度

/// 陪伴时长卡右侧那行小字和进度条：「一星 1 / 100 小时」。
///
/// 星级卡（改版前单独一张）并进了陪伴时长卡，所以这一行要短 —— 半屏宽里放不下
/// 「已累计 1 / 100 小时 · 还差 99 小时」。差多少由读屏那句说（`VolunteerProfileCopy.starCardAccessibilityLabel`）。
struct VolunteerHomeStarProgress: Equatable {
    let label: String
    /// 0...1。只是视觉辅助，`label` 才是读得到的那一份。
    let fraction: Double

    init(_ level: VolunteerStarLevelDto) {
        let current = max(0, level.current ?? 0)
        let hours = max(0, level.currentHours ?? 0)
        guard let target = level.nextTarget, target > 0 else {
            // 五星之后没有下一档：说当前星级，进度条满格。
            label = "\(VolunteerAchievementsCopy.starTitle(current: current)) · \(hours) 小时"
            fraction = 1
            return
        }
        label = "\(VolunteerAchievementsCopy.starTitle(current: current + 1)) \(hours) / \(target) 小时"
        fraction = min(1, Double(hours) / Double(target))
    }
}

// MARK: - 半宽卡

/// 陪伴时长卡下面那两张半宽卡之一。
struct VolunteerHomeHalfCard: Equatable {
    enum Kind: Equatable {
        /// 有已点亮的双人火花。去固定搭档页。
        case streak
        /// 没有火花时退到固定搭档人数。同样去固定搭档页。
        case partners
        /// 评分。**没有去处**（仓库里没有评价列表页），所以不画箭头。
        case rating
    }

    let kind: Kind
    let title: String
    let symbol: String
    /// 大号数字。没有数据时是 `--`。
    let value: String
    let unit: String?
    let caption: String
    let spoken: String

    /// 只有真有去处的卡才画箭头、才可点（#694 验收：「没有去处就不画箭头」）。
    var hasDestination: Bool { kind != .rating }

    /// 左边那张。🚩 **火花开关在后端默认是关的**（`PartnerStreakResponse` 注释），
    /// 所以多数人拿不到火花 —— 那时不画一张「连续陪跑 --」的空卡（那是在说「你没做到」），
    /// 退到固定搭档人数：同一个去处、同一类信息（「谁愿意继续跟我跑」）。
    static func left(
        streak: PartnerStreakDisplay?,
        streakPartnerName: String?,
        favoritedByCount: Int
    ) -> VolunteerHomeHalfCard {
        if let streak {
            // 只念不显示，所以去掉掩码星号（同改版前 `StreakStrip` 的口径）。
            let partner = streakPartnerName?.unmaskedForSpeech.nilIfBlank ?? PartnerStreakCopy.unknownBlindName
            return VolunteerHomeHalfCard(
                kind: .streak,
                title: VolunteerProfileCopy.streakCardTitle,
                symbol: "flame.fill",
                value: "\(streak.currentWeeks)",
                unit: VolunteerProfileCopy.streakWeeksUnit,
                caption: VolunteerProfileCopy.streakBestCaption(streak.bestWeeks),
                spoken: "\(VolunteerProfileCopy.streakCardTitle)。\(streak.headline(partner: partner))。\(streak.progressText)"
            )
        }
        let stat = VolunteerProfileStats.partners(favoritedByCount)
        return VolunteerHomeHalfCard(
            kind: .partners,
            title: VolunteerProfileCopy.partnersCaption,
            symbol: "person.2.fill",
            value: stat.value,
            unit: stat.unit,
            caption: max(0, favoritedByCount) > 0
                ? VolunteerProfileCopy.partnersCardCaption
                : VolunteerProfileCopy.partnersCardEmptyCaption,
            spoken: stat.spoken
        )
    }

    /// 右边那张：评分。没有评价时 `--` + 「还没有评价」，不编一个数。
    static func rating(average: Double?, total: Int?) -> VolunteerHomeHalfCard {
        let stat = VolunteerProfileStats.rating(average: average, total: total)
        let count = max(0, total ?? 0)
        let caption: String
        if average == nil {
            caption = VolunteerProfileCopy.ratingCardEmptyCaption
        } else if count > 0 {
            caption = "\(count) \(VolunteerProfileCopy.ratingCountUnit)评价"
        } else {
            caption = VolunteerProfileCopy.ratingCaption
        }
        return VolunteerHomeHalfCard(
            kind: .rating,
            title: VolunteerProfileCopy.ratingCaption,
            symbol: "star.fill",
            value: stat.value,
            unit: nil,
            caption: caption,
            spoken: stat.spoken
        )
    }
}

// MARK: - 最近陪跑

/// 最近陪跑卡上的全部文字与路线。
///
/// 🔴 **只用接口给了的东西。** 样例写的「陪伴 42 分钟」在契约 `RunHistoryItem` 里**没有**
/// （单次陪伴分钟数只在跑后详情里；月度列表只有 `monthSummary.serviceMin`），
/// 所以副标题用对方姓名 + 地点，不拿月度分钟数冒充单次的。
struct VolunteerHomeRecentRunContent: Equatable {
    let orderId: Int64
    /// 「11月3日」。解析失败时为 nil，那一格不画（不显示 `--`，也不拿今天顶上）。
    let dateText: String?
    /// 「5.00」，单位另画。`distanceM` 为 nil 时整段不画。
    let distanceText: String?
    /// 「和王* · 奥林匹克森林公园」。两样都没有时为 nil。
    let detailText: String?
    /// 画得出路线才有值；`thumbnail` 为 null、空、或点全部重合（只跑了几秒）时为 nil ⇒ 右侧不画图。
    let route: [RunLatLng]?
    let spoken: String

    init(item: RunHistoryItem) {
        orderId = item.orderId
        let date = item.finishedAt.backendTimestamp
        dateText = date.map { DateFormatter.aidRunDisplayMonthDay.string(from: $0) }
        distanceText = item.distanceM.map { RunRecordHistoryViewModel.kilometres($0) }

        func detail(spoken: Bool) -> String? {
            let name = item.partnerName?.nilIfBlank.map { spoken ? $0.unmaskedForSpeech : $0 }
            let parts = [name.map { "和\($0)" }, item.place?.nilIfBlank].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: spoken ? "，" : " · ")
        }
        detailText = detail(spoken: false)

        if let points = item.thumbnail, RunRouteShape.hasExtent(points) {
            route = points
        } else {
            route = nil
        }

        spoken = [
            VolunteerProfileCopy.recentSectionTitle,
            dateText,
            item.distanceM.map { "\(RunRecordHistoryViewModel.kilometres($0, spoken: true)) 公里" },
            detail(spoken: true)
        ]
        .compactMap { $0 }
        .joined(separator: "，")
    }

    /// 本月第一条；本月一条都没有时取上月第一条。
    ///
    /// 契约：`items` 按完成时间**倒序**，所以第一条就是最近的一条，这里不再排一次。
    /// 每月 1 号本月必然为空 —— 不退上月的话，这张卡每个月初都会消失。
    static func pick(current: [RunHistoryItem], previous: [RunHistoryItem]?) -> RunHistoryItem? {
        current.first ?? previous?.first
    }
}

/// 最近陪跑卡的数据。**刻意不并进 `VolunteerHomeViewModel`**：那份带着一条 10 秒轮询，
/// 而跑后记录只在跑完一单后才会变（理由同 `VolunteerHomeIncentiveViewModel`）。
///
/// 不复用 `RunRecordHistoryViewModel`：那一份每次还要多拉一条 `GET /api/orders/mine`
/// （给「未完成的预约」用），首页用不上。
@MainActor
final class VolunteerHomeRecentRunModel: ObservableObject {
    enum State: Equatable {
        case loading
        /// `nil` = 本月和上月都没有记录。
        case loaded(VolunteerHomeRecentRunContent?)
        case failed
    }

    @Published private(set) var state: State = .loading
    /// 「这一轮算加载过了」只在拿到结果（内容或失败）时置位。
    /// 🚩 **取消不算结果**：志愿者一进首页就点进别的页很常见，`.task` 随之取消；
    /// 在请求前就置位的话，这张卡会整个会话停在「加载中」（同 `VolunteerHomeIncentiveViewModel`）。
    private var hasLoaded = false
    private var observedCompletedCount: Int?
    /// 每次 `load` 领一个号，只有最新那一次的结果写回 —— 首次加载、下拉刷新、跑完一单三条路径会重叠，
    /// 后发的先回来时，先发的那份旧结果不能把它盖掉。
    private var latestLoad = 0

    func loadIfNeeded(appState: AppState) async {
        guard !hasLoaded else { return }
        await load(appState: appState)
    }

    /// 派单摘要里的完成次数变了（刚跑完一单）时重拉。口径同 `VolunteerHomeIncentiveViewModel.summaryVersionChanged`：
    /// 摘要没到不记，第一个值只记不拉（首次加载归 `loadIfNeeded`）。
    func completedCountChanged(_ count: Int?, appState: AppState) async {
        guard let count else { return }
        guard let previous = observedCompletedCount else {
            observedCompletedCount = count
            return
        }
        guard previous != count else { return }
        observedCompletedCount = count
        await load(appState: appState)
    }

    func load(appState: AppState, now: Date = Date()) async {
        latestLoad += 1
        let ticket = latestLoad
        let requestedUserId = appState.userId
        let month = RunRecordMonth(containing: now)
        do {
            let current = try await appState.runRecord.monthlyRecords(year: month.year, month: month.month)
            var previous: RunRecordHistoryResponse?
            if current.items.isEmpty {
                previous = try await appState.runRecord.monthlyRecords(
                    year: month.previous.year,
                    month: month.previous.month
                )
            }
            // 请求途中退出登录时不写回，否则上一个账号的记录会留给下一个账号（同盲人首页）。
            guard BlindHomeIdleModel.isStillCurrent(
                requestedUserId: requestedUserId,
                currentUserId: appState.userId,
                isCancelled: Task.isCancelled
            ), ticket == latestLoad else { return }
            let item = VolunteerHomeRecentRunContent.pick(current: current.items, previous: previous?.items)
            state = .loaded(item.map(VolunteerHomeRecentRunContent.init(item:)))
            hasLoaded = true
        } catch {
            guard !Task.isCancelled, !(error is CancellationError), ticket == latestLoad else { return }
            hasLoaded = true
            // 已经有内容时网络一抖不清掉它：上一份仍然是真的。
            if case .loaded = state { return }
            state = .failed
        }
    }
}
