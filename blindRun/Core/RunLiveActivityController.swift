import ActivityKit
import Foundation

// MARK: - 锁屏实时活动的 App 侧控制器
//
// 起停由 `LiveEscortSessionCoordinator` 驱动 —— 它是 App 生命周期内唯一的同行会话所有者，
// **两端共用**（`updateOwnedOrder` 的 9 个调用点里盲人端 5 个、志愿者端 4 个）。
// 挂在那里而不是挂在各自的订单页上，是因为「一道闸放在共用漏斗里」比「每个调用点各放一道」
// 少写代码，也不会漏掉哪一端。
//
// 🔴 **本类的全部难点是「卡片不活在 App 进程里」**：实时活动由系统进程托管，
// App 被杀 / 崩溃 / 用户上滑退出之后，锁屏与灵动岛上那张卡**照样在**。
// 所以下面每一处都不能假设「我手上的那个 `activity` 就是屏幕上那张」，
// 必须每次都去 `Activity.activities` 里对一遍。2026-09-16 真机上因此出过一张清不掉的卡。

/// 把 `TrackStats` 的六个计算属性打包成锁屏卡要的那一份内容。
///
/// **抽成纯函数只为可测**：唯一调用点在 `@MainActor` 的协调器里，而这里要验的是
/// 「数字缺失时给的是占位串而不是 0.00」这类分支。
@available(iOS 16.2, *)
enum RunLiveActivityContentBuilder {
    /// - Parameters:
    ///   - targetDistanceMeters: 订单计划距离。陪跑员端 v2 的「/ 5.00 公里」与进度条用它。
    ///   - rhythmSignal / rhythmSignalAt / isPaused: 后端 `run` 对象的字段（BE-1 / BE-2 在做）。
    ///     **ponytail: 现在没有调用方传**，全是 `nil` ⇒ 卡上不出现节奏与暂停；
    ///     FE-3 接上 `run` 对象时从 `LiveEscortSessionCoordinator.syncLiveActivity` 传进来即可。
    static func contentState(
        from stats: TrackStats?,
        partnerName: String?,
        targetDistanceMeters: Int? = nil,
        rhythmSignal: String? = nil,
        rhythmSignalAt: Date? = nil,
        isPaused: Bool? = nil,
        now: Date = Date()
    ) -> RunLiveActivityAttributes.ContentState {
        let targetKm = targetDistanceMeters.flatMap { $0 > 0 ? Double($0) / 1_000 : nil }
        let progress = zip(stats?.distanceMeters, targetKm).map { min(max($0 / 1_000 / $1, 0), 1) }
        // 5 分钟没更新的信号不算数（交付包 04）。没有时间戳的信号同样不算 —— 分不出新旧。
        let freshRhythm = rhythmSignalAt.flatMap {
            now.timeIntervalSince($0) <= RunLiveActivityCopy.rhythmFreshness ? rhythmSignal : nil
        }
        return RunLiveActivityAttributes.ContentState(
            partnerName: partnerName,
            distanceText: stats?.distanceKilometersText ?? RunLiveActivityCopy.pendingValue,
            durationText: stats?.durationClockText ?? RunLiveActivityCopy.pendingValue,
            paceText: stats?.paceClockText ?? RunLiveActivityCopy.pendingValue,
            spokenDistance: stats?.distanceText ?? RunLiveActivityCopy.pendingSpokenValue,
            spokenDuration: stats?.durationText ?? RunLiveActivityCopy.pendingSpokenValue,
            spokenPace: stats?.averagePaceText ?? RunLiveActivityCopy.pendingSpokenValue,
            targetDistanceText: targetKm.map { String(format: "%.2f", $0) },
            progress: progress,
            rhythmSignal: freshRhythm,
            isPaused: isPaused
        )
    }

    private static func zip(_ a: Double?, _ b: Double?) -> (Double, Double)? {
        guard let a, let b else { return nil }
        return (a, b)
    }
}

@available(iOS 16.2, *)
@MainActor
final class RunLiveActivityController {
    static let shared = RunLiveActivityController()

    private var activity: Activity<RunLiveActivityAttributes>?

    /// 当前这张卡属于哪一单。换单时必须先结束旧的 —— 同一个 `ActivityAttributes` 类型
    /// 可以同时存在多张卡，不结束的话锁屏上会并排出现两张。
    private(set) var activeOrderID: Int64?

    #if DEBUG
    /// 真机之外没法看锁屏，所以留一条调用历史给用例。
    private(set) var eventsForTesting: [String] = []
    func resetEventsForTesting() { eventsForTesting = [] }
    #endif

    private init() {}

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// 🔴 **单测里绝不真的起卡。**
    ///
    /// 2026-09-16 真机实测的事故：`LiveEscortTrackTests` 有 33 处
    /// `updateOwnedOrder(orderID: 901, status: .inProgress)`，起停钩子挂上去之后，
    /// **跑一次单测就在用户手机上留下好几张真实的实时活动**。它们没有数字（用例不带 stats，
    /// 全是占位 `--`），而且**清不掉** —— 测试宿主进程退出后，任何新进程都不认识它们。
    /// 用户的原话是「我不管怎么退出它都常驻，销不掉」「锁屏和灵动岛都没有任何数值」。
    ///
    /// 判据用 `XCTestConfigurationFilePath`：XCTest 宿主进程一定有，生产进程一定没有。
    /// **不放在 `#if DEBUG` 里** —— Release 下这个环境变量本来就是空的，而把它编译掉
    /// 只会让「哪种构建会起真卡」多一个变量。
    static var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// 开始 / 更新 / 结束一张卡。**幂等**：同一单重复调用只做更新。
    ///
    /// `side` 决定卡片长相：跑者端多一行顶行与一枚播报按钮，陪跑员端只有三个数字
    /// （状态清单 §17，且项目负责人 2026-09-16 决定陪跑员端不显示对方姓名）。
    func sync(
        orderID: Int64,
        side: RunLiveActivitySide,
        partnerName: String?,
        stats: TrackStats?,
        targetDistanceMeters: Int? = nil
    ) {
        adoptRunningActivityIfNeeded()
        let content = RunLiveActivityContentBuilder.contentState(
            from: stats,
            partnerName: partnerName,
            targetDistanceMeters: targetDistanceMeters
        )

        // 认回来的那张只要是同一单、同一端，就接着用 —— 这是进程重启后**不出现两张卡**
        // 的唯一办法。`partnerName` 住在 `ContentState` 里，所以这条路径也能把顶行补上。
        if let activity, activeOrderID == orderID, activity.attributes.side == side {
            Task { await activity.update(ActivityContent(state: content, staleDate: nil)) }
            #if DEBUG
            eventsForTesting.append("update:\(orderID)")
            #endif
            return
        }
        end()
        start(orderID: orderID, side: side, content: content)
    }

    /// 结束并从锁屏移除。
    ///
    /// 🔴 **结束的是这个类型的全部卡片，不只是自己手上那张。**
    /// `guard let activity else { return }` 是原来的写法，它的后果是：
    /// App 被杀过之后 `activity` 是 nil，于是这个函数**什么都不做**，
    /// 而屏幕上那张卡永远留着（直到系统 8 小时上限）。
    ///
    /// `.immediate` 而不是留一会儿：跑完那一刻 App 自己会播「本次陪跑结束」，
    /// 锁屏上再留一张停住的卡只会让人以为还在跑（设计稿「不播报的情况」里
    /// 「变形为总结状态时」同一条理由）。
    func end() {
        activity = nil
        activeOrderID = nil
        #if DEBUG
        eventsForTesting.append("end")
        #endif
        Task {
            for running in Activity<RunLiveActivityAttributes>.activities {
                await running.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// 进程重启后把系统里still活着的那张卡认回来。
    ///
    /// 不认的话有两种坏结局，真机上都出现过：① 还在跑 ⇒ `sync` 以为没有卡，
    /// 再 `request` 一张，锁屏上两张并排，一张的数字冻在被杀那一刻；
    /// ② 已经跑完 ⇒ `end()` 找不到东西可结束，卡片变成清不掉的僵尸。
    private func adoptRunningActivityIfNeeded() {
        guard activity == nil else { return }
        guard let running = Activity<RunLiveActivityAttributes>.activities.first else { return }
        activity = running
        activeOrderID = running.attributes.orderID
        #if DEBUG
        eventsForTesting.append("adopt:\(running.attributes.orderID)")
        #endif
    }

    private func start(
        orderID: Int64,
        side: RunLiveActivitySide,
        content: RunLiveActivityAttributes.ContentState
    ) {
        guard !Self.isRunningUnderXCTest else {
            #if DEBUG
            eventsForTesting.append("skipped:xctest")
            #endif
            return
        }
        // 用户在系统设置里关掉了「实时活动」时 `request` 会抛。这不是错误分支：
        // 不弹提示、不播报 —— 锁屏卡是**冗余**通道，App 内那一屏才是主通道。
        guard isSupported else {
            #if DEBUG
            eventsForTesting.append("unsupported")
            #endif
            return
        }
        do {
            activity = try Activity.request(
                attributes: RunLiveActivityAttributes(orderID: orderID, side: side),
                content: ActivityContent(state: content, staleDate: nil),
                pushType: nil
            )
            activeOrderID = orderID
            #if DEBUG
            eventsForTesting.append("start:\(orderID):\(side.rawValue)")
            #endif
        } catch {
            NSLog("[AidRun] 锁屏实时活动启动失败：%@", error.localizedDescription)
        }
    }
}
