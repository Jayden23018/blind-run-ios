import ActivityKit
import Foundation

// MARK: - 陪跑员实时活动的 App 侧控制器（#920，稿 `live-activity-v7-20261111` 第四、五节）
//
// 一张卡分两段（DECISION 第 3 条），同一时刻只留一张：
//
// - **第一段**（V1 商量见面 → V2 已交安排单 → V3 已约好）：响应派单成功时本地起
//   （`noteDispatchResponse`），通话页每拉到一次 `IntroCallView` 就本地更新（`showFirstSegment`），
//   成单推 V3 后收卡、锁屏留 15 分钟，没成直接收（`finishFirstSegment`）。
//   后端不为这三屏推送、也不收这段的 token ⇒ App 退到后台后卡停在最后一屏（倒计时照走）。
// - **第二段**（V4 开跑前 30 分钟 → V5 出发 → V6 已到达）：由手上的订单驱动（`sync(order:)`），
//   首页「即将开跑」列表与订单页都会喂。离开这几态就收卡；开跑后跑步卡（`RunLiveActivity*`）接上。
//   ActivityKit 不许后台本地起卡 ⇒ V4 只在开跑前 30 分钟内打开过 App 才会出现，
//   补全要后端 push-to-start（见 PR 描述的交接）。
//
// 出发 / 到达两态的更新有两条路，**后一条是兜底不是主路**：
// 1. 后端经 APNs 推 `update` / `end`（`pushType: .token`，token 由这里上传 —— 只在这两态传，
//    后端其余状态答 409）；
// 2. App 在前台时，订单页每拿到一份新订单就本地更新一次。

@available(iOS 16.2, *)
@MainActor
final class GuideRunActivityController {
    static let shared = GuideRunActivityController()

    /// 上传 push token。由 `AppState` 装配时注入（环境可以在运行时切换，必须打当下那一个）。
    var tokenUploader: (@MainActor @Sendable (_ orderID: Int64, _ hexToken: String) async throws -> Void)?

    private var activity: Activity<GuideRunAttributes>?
    private var lastContent: GuideRunAttributes.ContentState?
    private var tokenTask: Task<Void, Never>?
    /// 系统给的最新 token（十六进制）。V4 就拿到了，但要等出发才许传。
    private var pendingToken: String?
    private var uploadedToken: String?

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

    // MARK: 第二段（V4–V6）

    /// 开始 / 更新 / 结束第二段。**幂等**：同一单、内容没变时什么都不做。
    func sync(order: OrderDetailResponse, now: Date = Date()) {
        guard let content = GuideRunActivityContentBuilder.secondSegmentContent(from: order, now: now) else {
            endSecondSegment(orderID: order.orderId)
            return
        }
        adoptRunningActivityIfNeeded()
        if let activity, activity.attributes.orderID == order.orderId, lastContent?.phase.isFirstSegment != true {
            update(activity, to: content, orderID: order.orderId)
            uploadPendingTokenIfAllowed()
            return
        }
        // 别的单已经出发 / 到了：首页为下一单起 V4 不许把它挤掉（两单连着跑时会遇到）。
        if let activity, activity.attributes.orderID != order.orderId,
           lastContent?.phase.acceptsPushToken == true, content.phase == .preStart {
            #if DEBUG
            eventsForTesting.append("skipped:other-order-en-route")
            #endif
            return
        }
        // 同一单从第一段的卡升级上来时也重起：第一段的卡没要推送 token，留着它出发后后端就推不到。
        end()
        start(
            attributes: GuideRunActivityContentBuilder.attributes(from: order),
            content: content,
            wantsPushToken: true
        )
    }

    /// 手上的订单不该有第二段的卡：只收**这一单**的第二段卡。
    /// 第一段的卡由通话页管；别的单的卡（订单页正看着另一单时）也不碰。
    private func endSecondSegment(orderID: Int64) {
        adoptRunningActivityIfNeeded()
        if lastContent?.phase.isFirstSegment == true { return }
        if let activity, activity.attributes.orderID != orderID { return }
        end()
    }

    /// 首页每次拿到派单摘要时对一次账（审查 A2）：第一段的卡对应的单已不在通话中
    /// （窗口超时、对方换人、退到后台时成了单），就立即收掉 —— 后端不为这三屏推 `end`，
    /// 不对账的话卡会一直停在「商量见面」。成没成这里分不出来，一律按没成收，不画「没约成」。
    func reconcileFirstSegment(activeIntroCallOrderID: Int64?) {
        adoptRunningActivityIfNeeded()
        guard let activity,
              GuideRunActivityContentBuilder.firstSegmentIsOver(
                  cardOrderID: activity.attributes.orderID,
                  cardPhase: lastContent?.phase,
                  activeIntroCallOrderID: activeIntroCallOrderID
              ) else { return }
        end()
    }

    // MARK: 第一段（V1–V3）

    /// 响应派单成功（稿第五节「第一段 · 陪跑员」）。`INTERESTED` 起 V1；`ACCEPT` 直接成单，推 V3 后收卡。
    func noteDispatchResponse(_ action: OrderRespondAction, attributes: GuideRunAttributes) {
        switch action {
        case .interested:
            showFirstSegment(
                attributes: attributes,
                content: GuideRunActivityContentBuilder.introCallState(step: .awaitingCall, windowEndsAt: nil)
            )
        case .accept:
            finishFirstSegment(orderID: attributes.orderID, bookedAs: attributes)
        case .decline:
            return
        }
    }

    /// 起或更新第一段。第二段的卡在时不为别的单起第一段（第二段更要紧，稿第五节「多张卡并存」）。
    func showFirstSegment(attributes: GuideRunAttributes, content: GuideRunAttributes.ContentState) {
        adoptRunningActivityIfNeeded()
        if let activity {
            if activity.attributes.orderID == attributes.orderID {
                update(activity, to: content, orderID: attributes.orderID)
                return
            }
            if lastContent?.phase.isFirstSegment == false {
                #if DEBUG
                eventsForTesting.append("skipped:second-segment")
                #endif
                return
            }
        }
        end()
        start(attributes: attributes, content: content, wantsPushToken: false)
    }

    /// 第一段收卡。`bookedAs` 有值 = 已约好：推 V3 那一屏后结束，锁屏留 15 分钟；
    /// `nil` = 这一单没约成：**立即**收，不画「没约成」之类的卡（不暗示谁拒绝了谁，同通话页的无声拒绝）。
    ///
    /// 已约好时用成单后的 attributes 重新起一张再结束：时段单（#806）的开跑时刻在安排单里才定下来，
    /// 而 attributes 起卡后改不了 —— 沿用旧卡会把「明早 7:00」写成跑者当初选的时段起点。
    func finishFirstSegment(orderID: Int64, bookedAs attributes: GuideRunAttributes?) {
        adoptRunningActivityIfNeeded()
        let current = activity.flatMap { $0.attributes.orderID == orderID ? $0 : nil }
        if activity != nil, current == nil, lastContent?.phase.isFirstSegment == false {
            // 别的单的第二段卡正在锁屏上，不让一张「已约好」把它挤掉。
            return
        }
        #if DEBUG
        eventsForTesting.append("finish:\(orderID):\(attributes == nil ? "closed" : "booked")")
        #endif
        guard let attributes else {
            end()
            return
        }
        let dismissal = ActivityUIDismissalPolicy.after(Date().addingTimeInterval(GuideRunActivityContentBuilder.bookedLingerTime))
        let booked = ActivityContent(state: GuideRunActivityContentBuilder.bookedState, staleDate: nil)
        if let current, current.attributes == attributes {
            forget()
            Task { await current.end(booked, dismissalPolicy: dismissal) }
            return
        }
        end()
        guard !Self.isRunningUnderTests, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            let fresh = try Activity.request(attributes: attributes, content: booked, pushType: nil)
            Task { await fresh.end(booked, dismissalPolicy: dismissal) }
        } catch {
            NSLog("[AidRun] 「已约好」实时活动启动失败：%@", String(describing: error))
        }
    }

    // MARK: 共用

    /// 结束并从锁屏移除。**结束这个类型全部还在跑的卡片**，理由同 `RunLiveActivityController.end`：
    /// App 被杀过之后手上的引用是 nil，只结束自己那张会留下清不掉的僵尸卡。
    /// 已经结束、正在锁屏上停留的（V3 的 15 分钟、后端 `end` 的 5 分钟）不动。
    ///
    /// `.immediate`：离开这几态只有三种去向 —— 开跑（跑步卡马上接上）、取消 / 重派 / 结束等待
    /// （App 自己会播报），锁屏上再留一张「8 分钟后到」只会说错话。
    func end() {
        forget()
        #if DEBUG
        eventsForTesting.append("end")
        #endif
        // 🔴 **名单在这里同步取，不在 Task 里取。** 换单时是 `end()` 紧跟 `start()`，
        // 而这个 Task 要等调用方返回后才跑 —— 在 Task 里读 `activities` 会把刚起的新卡一起结束。
        let running = Self.runningActivities()
        guard !running.isEmpty else { return }
        Task {
            for card in running {
                await card.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private func forget() {
        tokenTask?.cancel()
        tokenTask = nil
        activity = nil
        lastContent = nil
        pendingToken = nil
        uploadedToken = nil
    }

    private static func runningActivities() -> [Activity<GuideRunAttributes>] {
        Activity<GuideRunAttributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }
    }

    private func update(_ activity: Activity<GuideRunAttributes>, to content: GuideRunAttributes.ContentState, orderID: Int64) {
        guard content != lastContent else { return }
        lastContent = content
        let staleDate = GuideRunActivityContentBuilder.staleDate(for: content)
        Task { await activity.update(ActivityContent(state: content, staleDate: staleDate)) }
        #if DEBUG
        eventsForTesting.append("update:\(orderID):\(content.phase.rawValue)")
        #endif
    }

    private func adoptRunningActivityIfNeeded() {
        guard activity == nil, let running = Self.runningActivities().first else { return }
        activity = running
        lastContent = running.content.state
        observePushToken(of: running)
        #if DEBUG
        eventsForTesting.append("adopt:\(running.attributes.orderID)")
        #endif
    }

    private func start(
        attributes: GuideRunAttributes,
        content: GuideRunAttributes.ContentState,
        wantsPushToken: Bool
    ) {
        guard !Self.isRunningUnderTests else {
            #if DEBUG
            eventsForTesting.append("skipped:tests")
            #endif
            return
        }
        // 用户在系统设置里关了实时活动：不提示、不播报。锁屏卡是冗余通道，订单页才是主通道。
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let initial = ActivityContent(state: content, staleDate: GuideRunActivityContentBuilder.staleDate(for: content))
        do {
            activity = try wantsPushToken
                ? Self.requestWithPushToken(attributes: attributes, content: initial)
                : Activity.request(attributes: attributes, content: initial, pushType: nil)
            lastContent = content
            if let activity, wantsPushToken { observePushToken(of: activity) }
        } catch {
            NSLog("[AidRun] 陪跑员实时活动启动失败：%@", String(describing: error))
        }
    }

    /// 先要推送 token；系统拒绝（例如没有 APNs 能力、个人开发团队）就退回纯本地卡，**卡照样起**。
    private static func requestWithPushToken(
        attributes: GuideRunAttributes,
        content: ActivityContent<GuideRunAttributes.ContentState>
    ) throws -> Activity<GuideRunAttributes> {
        do {
            return try Activity.request(attributes: attributes, content: content, pushType: .token)
        } catch {
            NSLog("[AidRun] 陪跑员实时活动拿不到推送 token，改为本地更新：%@", String(describing: error))
            return try Activity.request(attributes: attributes, content: content, pushType: nil)
        }
    }

    /// token 到了先存；轮换了就换新的。真正上传在 `uploadPendingTokenIfAllowed`。
    private func observePushToken(of activity: Activity<GuideRunAttributes>) {
        tokenTask?.cancel()
        tokenTask = Task { [weak self] in
            for await token in activity.pushTokenUpdates {
                let hex = GuideRunActivityContentBuilder.hexString(token)
                NSLog("[AidRun] 陪跑员实时活动拿到推送 token（%d 位）", hex.count)
                self?.pendingToken = hex
                self?.uploadPendingTokenIfAllowed()
            }
        }
    }

    /// 只在出发 / 到达两态传（后端其余状态答 409）。上传失败只留日志、下次 `sync` 再试 ——
    /// 后果只是锁屏不随后端刷新，App 内不受影响。
    private func uploadPendingTokenIfAllowed() {
        guard let activity,
              let token = pendingToken, token != uploadedToken,
              lastContent?.phase.acceptsPushToken == true,
              let uploader = tokenUploader else { return }
        let orderID = activity.attributes.orderID
        uploadedToken = token
        Task { [weak self] in
            do {
                try await uploader(orderID, token)
            } catch {
                NSLog("[AidRun] 上传实时活动推送 token 失败：%@", String(describing: error))
                if self?.uploadedToken == token { self?.uploadedToken = nil }
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
              TokenStoreFactory.makeDefault().read() != nil else { return nil }
        // 每次发请求都重读 Keychain，并接上续期器（#391）：跑步中锁屏卡的请求遇到 401 也要能续期，
        // 否则会一直 401。App 已装好就借 `AppState` 那个续期器（single-flight 与内存 token 一起走），
        // 没装好就起一个只读写 Keychain 的。
        // ponytail: 独立实例每次按钮都新建，两次并发的锁屏动作会各续一次（契约允许，结果一致，只是多一次请求）；
        // 真成问题时把独立实例缓存成静态单例。
        let renewer = SessionTokenRefresher.appSessionRenewer ?? SessionTokenRefresher.standalone(baseURL: baseURL)
        let tokenStore = TokenStoreFactory.makeDefault()
        return OrderService(transport: URLSessionAPIClient(
            baseURL: baseURL,
            tokenProvider: { tokenStore.read() },
            sessionRenewer: renewer
        ))
    }
}
