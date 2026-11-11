import ActivityKit
import CoreLocation
import Foundation

// MARK: - 盲人端「约跑进度」锁屏卡的 App 侧控制器（#919）
//
// 起卡、更新、收卡都由 App 本地做（`pushType: nil`）：后端还没有给这张卡推送的能力，
// 远程起卡（push-to-start）与远程更新见后端 issue（PR 描述里有链接）。
//
// 喂它订单的有两处：订单页 `BlindOrderStatusViewModel.apply`（拿得到磨合安排单与陪跑员实时距离）、
// 首页 `BlindRunnerHomeViewModel`（只有订单本身）。首页那一路**不许把订单页给的细节冲掉**，见 `Source`。
//
// 🔴 与另外两个控制器同一个难点：卡活在系统进程里，App 被杀之后照样在锁屏上。
// 所以每次都从 `Activity.activities` 里找，不假设手上那个引用就是屏幕上那张。
//
// 🔴 Apple：「In general, your app needs to be in the foreground to start a Live Activity」。
// 开跑前 30 分钟那一刻 App 不在前台就起不了卡 —— 只能等 App 回前台（首页会重拉订单）再补起。

@available(iOS 16.2, *)
@MainActor
final class BlindOrderActivityController {
    static let shared = BlindOrderActivityController()

    /// 谁喂的订单。首页拿不到磨合安排单与陪跑员距离，那两样沿用卡上已有的值。
    enum Source: Equatable {
        case orderPage
        case home
    }

    /// 订单页的磨合子状态（B3 要用）。
    struct IntroCallSnapshot: Equatable {
        /// 安排单已到、盲人还没确认（`IntroCallRunnerStep.reviewingPlan`）。
        let reviewingPlan: Bool
        /// 磨合窗口结束时刻（`IntroCallView.windowEndsAt`）。
        let deadline: Date?
    }

    /// 这一份订单对卡意味着什么。
    enum Decision: Equatable {
        /// 画这一屏（有卡就更新，没卡且该起就起）。
        case show(BlindOrderActivityPhase)
        /// 开跑了 / 跑完了：这张卡立刻收，跑步卡接上。
        case end
        /// 认不出的状态：什么都不动。
        case ignore
    }

    #if DEBUG
    private(set) var eventsForTesting: [String] = []
    func resetEventsForTesting() { eventsForTesting = [] }
    #endif

    private let defaults: UserDefaults
    /// 开跑前 30 分钟那一刻的定时器。只在 App 活着时有用。
    private var preRunTask: Task<Void, Never>?
    /// 现在排着的那一刻。同一单同一时刻不重排（订单页每次位置更新都会走 `sync`）。
    private var preRunFireAt: (orderID: Int64, date: Date)?

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 单测与 UI 测试里**都不起真卡**（同 `GuideRunActivityController.isRunningUnderTests`）：
    /// 用例进程被杀之后卡会留在锁屏上，而且清不掉。
    static var isRunningUnderTests: Bool {
        GuideRunActivityController.isRunningUnderTests
    }

    // MARK: - 纯函数（单测直接调）

    /// 订单状态 → 卡上哪一屏。穷举 switch：后端加状态时编译器逼一次决策。
    static func decision(
        status: RunOrderStatus,
        plannedStart: Date?,
        reviewingPlan: Bool,
        now: Date
    ) -> Decision {
        switch status {
        case .pendingMatch, .rematching:
            return .show(.matching)
        case .pendingIntroCall:
            return .show(reviewingPlan ? .confirmPlan : .talking)
        case .scheduledConfirmed, .pendingAccept:
            guard let plannedStart, now >= plannedStart.addingTimeInterval(-BlindOrderActivityTiming.preRunLead) else {
                return .show(.scheduled)
            }
            return .show(.preRun)
        case .driverEnRoute:
            return .show(.enRoute)
        case .driverArrived:
            return .show(.arrived)
        case .inProgress, .completed:
            return .end
        case .cancelled:
            return .show(.cancelled)
        case .noVolunteer:
            return .show(.noVolunteer)
        case .unknown:
            return .ignore
        }
    }

    /// 没有卡时这一屏要不要起一张。
    ///
    /// - 第一段（找人那三屏）只起一次：负责人 11-11 定「超 8 小时变灰收起，**不再起新卡**」，
    ///   所以系统到点结束之后、或用户自己划掉之后，App 回前台不能又起一张。
    /// - 第二段（开跑前 30 分钟起）同样只起一次。
    /// - 已约好 / 取消 / 没找到 **从不起卡**：它们只是推给已有那张卡的最后一屏。
    static func startsCard(for phase: BlindOrderActivityPhase, alreadyStarted: (Int) -> Bool) -> Bool {
        if phase.isFindingStage { return !alreadyStarted(1) }
        if phase.isSecondStage { return !alreadyStarted(2) }
        return false
    }

    /// 首页喂的订单没有磨合细节与陪跑员距离：同一屏时沿用卡上已有的值，别把 B3 冲回 B2、把距离冲掉。
    static func merge(
        _ fresh: BlindOrderActivityAttributes.ContentState,
        keeping previous: BlindOrderActivityAttributes.ContentState?,
        source: Source
    ) -> BlindOrderActivityAttributes.ContentState {
        guard source == .home, let previous else { return fresh }
        var merged = fresh
        if fresh.phase == .talking, previous.phase == .confirmPlan {
            merged.phase = .confirmPlan
            merged.confirmDeadline = previous.confirmDeadline
        }
        if fresh.phase == previous.phase, fresh.phase == .enRoute, fresh.distanceMeters == nil {
            merged.distanceMeters = previous.distanceMeters
        }
        return merged
    }

    static func content(
        phase: BlindOrderActivityPhase,
        order: OrderDetailResponse,
        introCall: IntroCallSnapshot?,
        volunteerDistanceMeters: Int?,
        previous: BlindOrderActivityAttributes.ContentState?
    ) -> BlindOrderActivityAttributes.ContentState {
        // 出发时距离：进 B6 后第一次拿到的距离，之后一直沿用（小人从这里走向你）。
        let departure = previous?.phase == .enRoute ? (previous?.departureDistanceMeters ?? volunteerDistanceMeters) : volunteerDistanceMeters
        let carriesDistance = phase == .enRoute
        return BlindOrderActivityAttributes.ContentState(
            phase: phase,
            plannedStart: order.plannedStart?.backendTimestamp,
            confirmDeadline: phase == .confirmPlan ? introCall?.deadline : nil,
            placeName: BlindOrderActivityPresentation.trimmed(order.meetSpotNote)
                ?? BlindOrderActivityPresentation.trimmed(order.startAddress),
            volunteerTopColor: order.volunteerTopColor?.spokenName,
            distanceMeters: carriesDistance ? volunteerDistanceMeters : nil,
            departureDistanceMeters: carriesDistance ? departure : nil
        )
    }

    /// 第一段找人那三屏 8 小时变灰（B10）；别的屏不设。
    static func staleDate(for phase: BlindOrderActivityPhase, startedAt: Date) -> Date? {
        phase.isFindingStage ? startedAt.addingTimeInterval(BlindOrderActivityTiming.findingStaleAfter) : nil
    }

    static func relevance(for phase: BlindOrderActivityPhase) -> Double {
        phase.isSecondStage ? BlindOrderActivityTiming.secondStageRelevance : BlindOrderActivityTiming.firstStageRelevance
    }

    /// 陪跑员离见面点多远（米）。坐标缺一个就是 `nil`（卡上写「陪跑员已出发」）。
    static func volunteerDistanceMeters(
        volunteer: CLLocationCoordinate2D?,
        meetingPoint: CLLocationCoordinate2D?
    ) -> Int? {
        guard let volunteer, let meetingPoint else { return nil }
        return Int(DistanceCalculator.distance(from: volunteer, to: meetingPoint).rounded())
    }

    // MARK: - 起 / 更新 / 收

    func sync(
        order: OrderDetailResponse,
        source: Source,
        introCall: IntroCallSnapshot? = nil,
        volunteerDistanceMeters: Int? = nil,
        now: Date = Date()
    ) {
        let decision = Self.decision(
            status: order.status,
            plannedStart: order.plannedStart?.backendTimestamp,
            reviewingPlan: introCall?.reviewingPlan ?? false,
            now: now
        )
        schedulePreRunTimer(for: order, decision: decision, now: now)
        switch decision {
        case .ignore:
            return
        case .end:
            // 只收**这一单**的卡：打开一张已完成的历史单不能把正在进行那单的卡收掉。
            endCards(of: order.orderId)
            return
        case .show(let phase):
            show(phase, order: order, source: source, introCall: introCall, volunteerDistanceMeters: volunteerDistanceMeters, now: now)
        }
    }

    /// 结束并立刻移除这个类型的全部卡片（开跑交给跑步卡、退出登录、换角色）。
    /// 名单同步取，不在 `Task` 里取 —— 理由同 `RunLiveActivityController.end()`（#230）。
    func endAll() {
        preRunTask?.cancel()
        preRunTask = nil
        preRunFireAt = nil
        #if DEBUG
        eventsForTesting.append("end")
        #endif
        let live = Activity<BlindOrderActivityAttributes>.activities
        guard !live.isEmpty else { return }
        Task {
            for activity in live {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private func endCards(of orderID: Int64) {
        let mine = Activity<BlindOrderActivityAttributes>.activities.filter {
            $0.attributes.orderID == orderID && $0.activityState != .ended && $0.activityState != .dismissed
        }
        guard !mine.isEmpty else { return }
        #if DEBUG
        eventsForTesting.append("end:\(orderID)")
        #endif
        Task {
            for activity in mine {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// 首页拉不到活跃订单（取消 / 没找到 / 跑完，且这一跳没被看见）：收掉还在更新的那张。
    /// **已结束、只在锁屏上多留一会儿的不动**（B4 已约好那 15 分钟）。
    func endLive() {
        preRunTask?.cancel()
        preRunTask = nil
        preRunFireAt = nil
        guard let live = Self.liveActivity() else { return }
        #if DEBUG
        eventsForTesting.append("endLive:\(live.attributes.orderID)")
        #endif
        Task { await live.end(nil, dismissalPolicy: .immediate) }
    }

    private func show(
        _ phase: BlindOrderActivityPhase,
        order: OrderDetailResponse,
        source: Source,
        introCall: IntroCallSnapshot?,
        volunteerDistanceMeters: Int?,
        now: Date
    ) {
        var live = Self.liveActivity()
        if let other = live, other.attributes.orderID != order.orderId {
            // 另一单：只有这一单真要起卡时才换（盲人同一时刻只跟一单）。
            // 打开一张已取消 / 已约好的旧单只是看看，不许把正在进行那单的卡收掉。
            guard Self.startsCard(for: phase, alreadyStarted: { hasStarted(orderID: order.orderId, stage: $0) }) else { return }
            Task { await other.end(nil, dismissalPolicy: .immediate) }
            live = nil
        }
        let previous = live?.content.state
        let content = Self.merge(
            Self.content(phase: phase, order: order, introCall: introCall, volunteerDistanceMeters: volunteerDistanceMeters, previous: previous),
            keeping: previous,
            source: source
        )

        guard let live else {
            start(content: content, orderID: order.orderId, now: now)
            return
        }
        guard content != previous else { return }
        let alert = content.phase.alertsOnEntry && previous?.phase != content.phase
        let shownPhase = content.phase
        if shownPhase.endsCard {
            // 推完最后一屏就结束，锁屏留 15 分钟（B4 已约好、B11 取消 / 没找到）。
            let final = ActivityContent(state: content, staleDate: nil, relevanceScore: Self.relevance(for: shownPhase))
            let dismissAt = now.addingTimeInterval(BlindOrderActivityTiming.lingerAfterEnd)
            Task { await live.end(final, dismissalPolicy: .after(dismissAt)) }
            #if DEBUG
            eventsForTesting.append("end:\(order.orderId):\(shownPhase.rawValue)")
            #endif
            return
        }
        let update = ActivityContent(
            state: content,
            staleDate: Self.staleDate(for: shownPhase, startedAt: live.attributes.startedAt),
            relevanceScore: Self.relevance(for: shownPhase)
        )
        let configuration = alert ? Self.alertConfiguration(for: content, now: now) : nil
        Task { await live.update(update, alertConfiguration: configuration) }
        #if DEBUG
        eventsForTesting.append("update:\(order.orderId):\(shownPhase.rawValue)\(alert ? ":alert" : "")")
        #endif
    }

    private func start(content: BlindOrderActivityAttributes.ContentState, orderID: Int64, now: Date) {
        guard Self.startsCard(for: content.phase, alreadyStarted: { hasStarted(orderID: orderID, stage: $0) }) else { return }
        guard !Self.isRunningUnderTests else {
            #if DEBUG
            eventsForTesting.append("skipped:tests:\(content.phase.rawValue)")
            #endif
            return
        }
        // 用户在系统设置里关了实时活动：不提示。锁屏卡是冗余通道，订单页与推送才是主通道。
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = BlindOrderActivityAttributes(orderID: orderID, startedAt: now)
        do {
            _ = try Activity.request(
                attributes: attributes,
                content: ActivityContent(
                    state: content,
                    staleDate: Self.staleDate(for: content.phase, startedAt: now),
                    relevanceScore: Self.relevance(for: content.phase)
                ),
                pushType: nil
            )
            markStarted(orderID: orderID, stage: content.phase.isSecondStage ? 2 : 1)
            #if DEBUG
            eventsForTesting.append("start:\(orderID):\(content.phase.rawValue)")
            #endif
        } catch {
            NSLog("[AidRun] 约跑进度锁屏卡启动失败：%@", String(describing: error))
        }
    }

    /// 屏幕上那张（还没结束的）。已结束、只是在锁屏上多留一会儿的不算 —— 它们不能再更新。
    private static func liveActivity() -> Activity<BlindOrderActivityAttributes>? {
        Activity<BlindOrderActivityAttributes>.activities.first {
            $0.activityState != .ended && $0.activityState != .dismissed
        }
    }

    /// 带一次提醒（亮屏 + 声音）。标题写 App 名，正文写卡上的标题。
    private static func alertConfiguration(
        for content: BlindOrderActivityAttributes.ContentState,
        now: Date
    ) -> AlertConfiguration {
        let presentation = BlindOrderActivityPresentation(state: content, isStale: false, now: now)
        return AlertConfiguration(
            title: LocalizedStringResource(String.LocalizationValue(BlindOrderActivityCopy.appName)),
            body: LocalizedStringResource(String.LocalizationValue(presentation.title)),
            sound: .default
        )
    }

    // MARK: - 开跑前 30 分钟

    /// App 活着（在前台）时，到开跑前 30 分钟那一刻再判一次。App 在后台时这个 Task 会被挂起，
    /// 到点起不了卡（系统限制），等 App 回前台由首页重拉订单补起。
    private func schedulePreRunTimer(for order: OrderDetailResponse, decision: Decision, now: Date) {
        let fireAt = order.plannedStart?.backendTimestamp?.addingTimeInterval(-BlindOrderActivityTiming.preRunLead)
        let wanted = decision == .show(.scheduled) && (fireAt.map { $0 > now } ?? false)
        if wanted, let current = preRunFireAt, current.orderID == order.orderId, current.date == fireAt {
            return
        }
        // 只换掉同一单的定时器；看别的单（`.ignore` 之外的任何一份）不动当前单排着的那个。
        if wanted || preRunFireAt?.orderID == order.orderId {
            preRunTask?.cancel()
            preRunTask = nil
            preRunFireAt = nil
        }
        guard wanted, let fireAt else { return }
        let delay = fireAt.timeIntervalSince(now)
        let orderID = order.orderId
        preRunFireAt = (orderID, fireAt)
        preRunTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.preRunFireAt = nil
            // 用排定时器时那份订单：到点时它的状态若已变（取消、陪跑员出发），首页 / 订单页早已喂过新的、这个 Task 已被取消。
            self.sync(order: order, source: .home)
        }
    }

    // MARK: - 每单每段只起一次

    private static let startedKey = "blindOrderActivity.startedStages"
    /// 只留最近这么多条，别让这个列表无限长。
    private static let startedLimit = 40

    private func hasStarted(orderID: Int64, stage: Int) -> Bool {
        (defaults.stringArray(forKey: Self.startedKey) ?? []).contains("\(orderID)-\(stage)")
    }

    private func markStarted(orderID: Int64, stage: Int) {
        var list = defaults.stringArray(forKey: Self.startedKey) ?? []
        list.removeAll { $0 == "\(orderID)-\(stage)" }
        list.append("\(orderID)-\(stage)")
        defaults.set(Array(list.suffix(Self.startedLimit)), forKey: Self.startedKey)
    }
}
