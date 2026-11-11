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

/// 订单 → 卡片内容。**抽成纯函数只为可测**。
@available(iOS 16.2, *)
enum GuideRunActivityContentBuilder {
    /// 开跑前多久起第二段（DECISION 第 2 条）。
    static let preStartLeadTime: TimeInterval = 30 * 60
    /// 第一段 V3「已约好」推完之后锁屏留多久（稿第五节）。
    static let bookedLingerTime: TimeInterval = 15 * 60

    /// 出发 / 汇合两态（后端 `live-activity-token` 也只在这两态收 token）。
    static func showsCard(for status: RunOrderStatus) -> Bool {
        status == .driverEnRoute || status == .driverArrived
    }

    /// V4 的门槛：已约好（含临期确认 `PENDING_ACCEPT`）且离开跑不到 30 分钟（含已过开跑时刻还没出发）。
    static func isInPreStartWindow(status: RunOrderStatus, plannedStart: Date?, now: Date) -> Bool {
        guard status == .scheduledConfirmed || status == .pendingAccept, let plannedStart else { return false }
        return now >= plannedStart.addingTimeInterval(-preStartLeadTime)
    }

    /// 第二段这一刻该画什么；`nil` = 这份订单不该有第二段的卡。
    static func secondSegmentContent(from order: OrderDetailResponse, now: Date) -> GuideRunAttributes.ContentState? {
        if showsCard(for: order.status) { return contentState(from: order) }
        guard isInPreStartWindow(status: order.status, plannedStart: order.plannedStart?.backendTimestamp, now: now) else {
            return nil
        }
        return preStartState(from: order)
    }

    static func attributes(from order: OrderDetailResponse) -> GuideRunAttributes {
        GuideRunAttributes(
            orderID: order.orderId,
            // 卡上不写名字（DECISION 第 7 条），字段照旧只取 `blindSurname`、**不拿掩码名顶替**，
            // 以免以后有人重新把它画上卡时画出「李*」。
            runnerSurname: order.blindSurname?.nilIfBlank,
            meetingPointName: order.startAddress?.nilIfBlank ?? "",
            plannedStart: order.plannedStart?.backendTimestamp
        )
    }

    /// 第一段起卡时还没有订单详情（通话期 `GET /api/orders/{id}` 对陪跑员恒 403），
    /// 只有派单推送或 `IntroCallView` 里的地址与时间。
    static func attributes(orderID: Int64, startAddress: String?, plannedStart: String?) -> GuideRunAttributes {
        GuideRunAttributes(
            orderID: orderID,
            runnerSurname: nil,
            meetingPointName: startAddress?.nilIfBlank ?? "",
            plannedStart: plannedStart?.nilIfBlank?.backendTimestamp
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

    /// V4。`suggestedDepartAt` / `travelMinutes` 只在陪跑员有位置记录时下发，缺了卡上退到「7:00 开跑」。
    static func preStartState(from order: OrderDetailResponse) -> GuideRunAttributes.ContentState {
        GuideRunAttributes.ContentState(
            phase: .preStart,
            etaMinutes: nil,
            arriveAt: nil,
            progress: 0.1,
            runnerNearMeetingPoint: false,
            distanceBucket: nil,
            leaveBy: order.suggestedDepartAt?.nilIfBlank?.backendTimestamp,
            travelMinutes: order.travelMinutes
        )
    }

    /// V1 / V2。子状态的判据与通话页同一个（`VolunteerIntroCallViewModel.step`）。
    static func introCallState(step: IntroCallVolunteerStep, windowEndsAt: Date?) -> GuideRunAttributes.ContentState {
        GuideRunAttributes.ContentState(
            phase: step == .awaitingCall ? .introCall : .planSubmitted,
            etaMinutes: nil,
            arriveAt: nil,
            progress: 0.1,
            runnerNearMeetingPoint: false,
            distanceBucket: nil,
            deadline: step == .awaitingCall ? windowEndsAt : nil
        )
    }

    /// V3。
    static let bookedState = GuideRunAttributes.ContentState(
        phase: .scheduled, etaMinutes: nil, arriveAt: nil, progress: 0.1,
        runnerNearMeetingPoint: false, distanceBucket: nil
    )

    /// 到点后卡片该换样子的那一刻：V1 商量截止、V4 建议出发时刻。widget 读 `context.isStale`。
    static func staleDate(for content: GuideRunAttributes.ContentState) -> Date? {
        switch content.phase {
        case .introCall: return content.deadline
        case .preStart: return content.leaveBy
        default: return nil
        }
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
            endSecondSegment()
            return
        }
        adoptRunningActivityIfNeeded()
        if let activity, activity.attributes.orderID == order.orderId {
            update(activity, to: content, orderID: order.orderId)
            uploadPendingTokenIfAllowed()
            return
        }
        end()
        start(
            attributes: GuideRunActivityContentBuilder.attributes(from: order),
            content: content,
            wantsPushToken: true
        )
    }

    /// 手上的订单不该有第二段的卡：只收第二段的卡。第一段的卡由通话页管，这里不碰
    /// （订单页拿着一张还没到 30 分钟的已约好订单时，不能把另一单正在商量的卡收掉）。
    private func endSecondSegment() {
        adoptRunningActivityIfNeeded()
        if lastContent?.phase.isFirstSegment == true { return }
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
