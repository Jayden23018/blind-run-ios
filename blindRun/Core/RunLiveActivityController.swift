import ActivityKit
import Foundation

// MARK: - 锁屏实时活动的 App 侧控制器
//
// 起停由 `LiveEscortSessionCoordinator` 驱动 —— 它是 App 生命周期内唯一的同行会话所有者，
// **两端共用**（`updateOwnedOrder` 的 9 个调用点里盲人端 5 个、志愿者端 4 个）。
// 挂在那里而不是挂在各自的订单页上，是因为「一道闸放在共用漏斗里」比「每个调用点各放一道」
// 少写代码，也不会漏掉哪一端。

/// 把 `TrackStats` 的六个计算属性打包成锁屏卡要的那一份内容。
///
/// **抽成纯函数只为可测**：唯一调用点在 `@MainActor` 的协调器里，而这里要验的是
/// 「数字缺失时给的是占位串而不是 0.00」这类分支。
@available(iOS 16.2, *)
enum RunLiveActivityContentBuilder {
    static func contentState(from stats: TrackStats?) -> RunLiveActivityAttributes.ContentState {
        RunLiveActivityAttributes.ContentState(
            distanceText: stats?.distanceKilometersText ?? RunLiveActivityCopy.pendingValue,
            durationText: stats?.durationClockText ?? RunLiveActivityCopy.pendingValue,
            paceText: stats?.paceClockText ?? RunLiveActivityCopy.pendingValue,
            spokenDistance: stats?.distanceText ?? RunLiveActivityCopy.pendingSpokenValue,
            spokenDuration: stats?.durationText ?? RunLiveActivityCopy.pendingSpokenValue,
            spokenPace: stats?.averagePaceText ?? RunLiveActivityCopy.pendingSpokenValue
        )
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

    /// 开始 / 更新 / 结束一张卡。**幂等**：同一单重复调用只做更新。
    ///
    /// `side` 决定卡片长相：跑者端多一行顶行与一枚播报按钮，陪跑员端只有三个数字
    /// （状态清单 §17，且项目负责人 2026-09-16 决定陪跑员端不显示对方姓名）。
    func sync(
        orderID: Int64,
        side: RunLiveActivitySide,
        partnerName: String?,
        stats: TrackStats?
    ) {
        let content = RunLiveActivityContentBuilder.contentState(from: stats)
        if let activity, activeOrderID == orderID {
            Task { await activity.update(ActivityContent(state: content, staleDate: nil)) }
            #if DEBUG
            eventsForTesting.append("update:\(orderID)")
            #endif
            return
        }
        if activity != nil { end() }
        start(orderID: orderID, side: side, partnerName: partnerName, content: content)
    }

    /// 结束并从锁屏移除。
    ///
    /// `.immediate` 而不是留一会儿：跑完那一刻 App 自己会播「本次陪跑结束」，
    /// 锁屏上再留一张停住的卡只会让人以为还在跑（设计稿「不播报的情况」里
    /// 「变形为总结状态时」同一条理由）。
    func end() {
        guard let activity else { return }
        self.activity = nil
        activeOrderID = nil
        #if DEBUG
        eventsForTesting.append("end")
        #endif
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    private func start(
        orderID: Int64,
        side: RunLiveActivitySide,
        partnerName: String?,
        content: RunLiveActivityAttributes.ContentState
    ) {
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
                attributes: RunLiveActivityAttributes(side: side, partnerName: partnerName),
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
