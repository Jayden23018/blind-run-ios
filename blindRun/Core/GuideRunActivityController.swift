import ActivityKit
import Foundation

// MARK: - 陪跑员「出发 / 汇合」锁屏卡的 App 侧控制器（决定源 V3）
//
// 起停由 `VolunteerInServiceViewModel.order` 驱动：手上这份订单进了 `DRIVER_EN_ROUTE` /
// `DRIVER_ARRIVED` 就起卡或更新，离开这两态就结束。按下「我出发了」成功后订单落到
// `DRIVER_EN_ROUTE`，卡随之出现 —— 冷启动打开一张出发中的单也会把卡认回来或补起来。
//
// 更新有两条路，**后一条是兜底不是主路**：
// 1. 后端经 APNs 推 `update` / `end`（`pushType: .token`，token 由这里上传）；
// 2. App 在前台时，订单页每拿到一份新订单（轮询 / WS `ORDER_ETA_UPDATED` /
//    `MEET_DISTANCE_BUCKET`）就本地更新一次。
// 仓库没有 APNs 能力文件（V2 ②本期不做）时第 1 条拿不到 token，只剩第 2 条 ——
// 那时卡在 App 退到后台后会停在最后一次的样子，直到 App 回到前台。

/// 订单 → 卡片内容。**抽成纯函数只为可测**。
@available(iOS 16.2, *)
enum GuideRunActivityContentBuilder {
    /// 这张卡只在这两态存在（后端 `live-activity-token` 也只在这两态收 token）。
    static func showsCard(for status: RunOrderStatus) -> Bool {
        status == .driverEnRoute || status == .driverArrived
    }

    static func attributes(from order: OrderDetailResponse) -> GuideRunAttributes {
        GuideRunAttributes(
            orderID: order.orderId,
            // ponytail: 后端 BE-2 的姓氏字段还没到。到了就在这里接上 —— **不要拿 `blindName`
            // 的首字顶替**：那是掩码串，决定源 V11「不念掩码」。
            runnerSurname: nil,
            meetingPointName: order.startAddress?.nilIfBlank ?? "",
            plannedStart: order.plannedStart?.backendTimestamp
        )
    }

    /// 与后端推送的 `content-state` 同口径（后端 `docs/live-activity.md`「ContentState」一节），
    /// 这样本地更新与推送更新交替到达时卡片不会来回跳。
    static func contentState(from order: OrderDetailResponse) -> GuideRunAttributes.ContentState {
        if order.status == .driverArrived {
            return GuideRunAttributes.ContentState(
                phase: .arrived,
                etaMinutes: nil,
                arriveAt: nil,
                progress: 0.85,
                runnerNearMeetingPoint: order.runnerAtMeetingPoint ?? false,
                distanceBucket: order.meet?.distanceBucket.rawValue
            )
        }
        let eta = order.eta
        return GuideRunAttributes.ContentState(
            phase: eta?.late == true ? .late : .departed,
            etaMinutes: eta?.remainingMinutes,
            arriveAt: eta?.arriveAt?.backendTimestamp,
            progress: eta?.progress ?? 0.1,
            // 三态字段：`nil`（跑者位置未知）按 `false`，与后端推送同一条口径。
            runnerNearMeetingPoint: order.runnerAtMeetingPoint ?? false,
            distanceBucket: nil
        )
    }

    /// APNs 的 token 是 `Data`，后端要十六进制串（`^[0-9a-fA-F]{32,512}$`）。
    static func hexString(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }
}

@available(iOS 16.2, *)
@MainActor
final class GuideRunActivityController {
    static let shared = GuideRunActivityController()

    /// 上传 push token。由 `AppState` 装配时注入（环境可以在运行时切换，必须打当下那一个）。
    var tokenUploader: (@MainActor @Sendable (_ orderID: Int64, _ hexToken: String) async throws -> Void)?

    private var activity: Activity<GuideRunAttributes>?
    private var lastContent: GuideRunAttributes.ContentState?
    private var tokenTask: Task<Void, Never>?

    #if DEBUG
    private(set) var eventsForTesting: [String] = []
    func resetEventsForTesting() { eventsForTesting = [] }
    #endif

    private init() {}

    /// 单测与 UI 测试里**都不起真卡**。
    ///
    /// 跑步卡只挡了单测（`RunLiveActivityController.isRunningUnderXCTest`）；这张卡多挡 UI 测试，
    /// 因为订单页 v2 的 UI 用例大量停在出发 / 汇合两态，而用例进程被杀之后卡会留在锁屏上。
    static var isRunningUnderTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return RunLiveActivityController.isRunningUnderXCTest
            || environment.keys.contains { $0.hasPrefix("AIDRUN_UI_TEST_") }
    }

    /// 开始 / 更新 / 结束。**幂等**：同一单、内容没变时什么都不做。
    func sync(order: OrderDetailResponse) {
        guard GuideRunActivityContentBuilder.showsCard(for: order.status) else {
            end()
            return
        }
        adoptRunningActivityIfNeeded()
        let content = GuideRunActivityContentBuilder.contentState(from: order)
        if let activity, activity.attributes.orderID == order.orderId {
            guard content != lastContent else { return }
            lastContent = content
            Task { await activity.update(ActivityContent(state: content, staleDate: nil)) }
            #if DEBUG
            eventsForTesting.append("update:\(order.orderId):\(content.phase.rawValue)")
            #endif
            return
        }
        end()
        start(attributes: GuideRunActivityContentBuilder.attributes(from: order), content: content)
    }

    /// 结束并从锁屏移除。**结束这个类型的全部卡片**，理由同 `RunLiveActivityController.end`：
    /// App 被杀过之后手上的引用是 nil，只结束自己那张会留下清不掉的僵尸卡。
    ///
    /// `.immediate`：离开这两态只有三种去向 —— 开跑（跑步卡马上接上）、取消 / 重派 / 结束等待
    /// （App 自己会播报），锁屏上再留一张「8 分钟后到」只会说错话。
    /// 后端推的 `end` 带 5 分钟 `dismissal-date`，那是 App 不在前台时的另一条路。
    func end() {
        tokenTask?.cancel()
        tokenTask = nil
        let hadActivity = activity != nil
        activity = nil
        lastContent = nil
        #if DEBUG
        if hadActivity { eventsForTesting.append("end") }
        #endif
        // 🔴 **名单在这里同步取，不在 Task 里取。** `sync` 换单时是 `end()` 紧跟 `start()`，
        // 而这个 Task 要等 `sync` 返回后才跑 —— 在 Task 里读 `activities` 会把刚起的新卡一起结束。
        let stale = Activity<GuideRunAttributes>.activities
        guard !stale.isEmpty else { return }
        Task {
            for running in stale {
                await running.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private func adoptRunningActivityIfNeeded() {
        guard activity == nil, let running = Activity<GuideRunAttributes>.activities.first else { return }
        activity = running
        lastContent = running.content.state
        observePushToken(of: running)
        #if DEBUG
        eventsForTesting.append("adopt:\(running.attributes.orderID)")
        #endif
    }

    private func start(attributes: GuideRunAttributes, content: GuideRunAttributes.ContentState) {
        guard !Self.isRunningUnderTests else {
            #if DEBUG
            eventsForTesting.append("skipped:tests")
            #endif
            return
        }
        // 用户在系统设置里关了实时活动：不提示、不播报。锁屏卡是冗余通道，订单页才是主通道。
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            activity = try Self.request(attributes: attributes, content: content)
            lastContent = content
            if let activity { observePushToken(of: activity) }
        } catch {
            NSLog("[AidRun] 出发/汇合锁屏卡启动失败：%@", String(describing: error))
        }
    }

    /// 先要推送 token；系统拒绝（例如没有 APNs 能力）就退回纯本地卡，**卡照样起**。
    private static func request(
        attributes: GuideRunAttributes,
        content: GuideRunAttributes.ContentState
    ) throws -> Activity<GuideRunAttributes> {
        let initial = ActivityContent(state: content, staleDate: nil)
        do {
            return try Activity.request(attributes: attributes, content: initial, pushType: .token)
        } catch {
            NSLog("[AidRun] 出发/汇合锁屏卡拿不到推送 token，改为本地更新：%@", String(describing: error))
            return try Activity.request(attributes: attributes, content: initial, pushType: nil)
        }
    }

    /// token 到了就传；轮换了就再传一次（后端覆盖写）。上传失败只留日志 ——
    /// 后果只是锁屏不随后端刷新，App 内不受影响（后端 Redis 不可用时也是同一个后果）。
    private func observePushToken(of activity: Activity<GuideRunAttributes>) {
        tokenTask?.cancel()
        let orderID = activity.attributes.orderID
        tokenTask = Task { [weak self] in
            for await token in activity.pushTokenUpdates {
                let hex = GuideRunActivityContentBuilder.hexString(token)
                NSLog("[AidRun] 出发/汇合锁屏卡拿到推送 token（%d 位）", hex.count)
                guard let uploader = self?.tokenUploader else { continue }
                do {
                    try await uploader(orderID, hex)
                } catch {
                    NSLog("[AidRun] 上传锁屏卡推送 token 失败：%@", String(describing: error))
                }
            }
        }
    }
}

// MARK: - 锁屏按钮 → 接口

@available(iOS 16.2, *)
extension GuideRunActivityController {
    /// 在 `blindRunApp.init` 里挂一次。锁屏按钮按下时 App 多半在后台、甚至是被系统冷启动的，
    /// `AppState` 不保证已经装好 —— 所以这里**不经 `AppState`**，直接用持久化的环境与 Keychain 里的 token。
    static func installIntentHandler() {
        GuideRunActivityActions.handler = { action, orderID in
            guard let orders = await backgroundOrderService() else {
                throw GuideRunActivityActions.NotConfigured()
            }
            let response: OrderNudgeResponse
            switch action {
            case .almostThere:
                response = try await orders.sendQuickMessage(.almostThere, orderId: orderID)
            case .waitFiveMinutes:
                response = try await orders.sendQuickMessage(.waitFiveMinutes, orderId: orderID)
            case .ringRunner:
                response = try await orders.ringRunner(orderId: orderID)
            }
            if response.delivered == false {
                NSLog("[AidRun] 锁屏按钮 %@ 已受理但推送没发出去", action.rawValue)
            }
        }
    }

    /// 只在 Demo Cloud 下有真的服务可打。Mock 是进程内设施，锁屏按钮在 Mock 下不做事。
    @MainActor
    private static func backgroundOrderService() -> (any OrderServing)? {
        let environment = AppState.initialEnvironment(persistence: AppStatePersistenceFactory.makeDefault())
        guard environment == .demoCloud,
              AppBuildChannel.current.allows(environment),
              let baseURL = environment.baseURL,
              let token = TokenStoreFactory.makeDefault().read() else { return nil }
        return OrderService(transport: URLSessionAPIClient(baseURL: baseURL, tokenProvider: { token }))
    }
}
