import CoreLocation
import SwiftUI

extension BlindOrderStatusViewModel {
    /// 订单跟踪送来的、已过新鲜度判据与 GCJ-02 边界的陪跑员位置（`PeerLocationFreshness.accept`）。
    /// 角色、单号、15 秒、过期任务都在跟踪里判，这里只落到页面状态。
    func handleVolunteerLocation(_ peer: FreshPeerLocation) {
        latestVolunteerWebSocketDate = peer.located.capturedAt
        latestVolunteerSample = peer.located
        latestVolunteerCoordinate = peer.located.coordinate
        refreshVolunteerDistance()
    }

    // `shouldSuppressDirectNotificationSpeech(_:)` 已于 2026-08-09 删除（连同 31 条中文片段表）。
    //
    // 它按通知正文的中文片段决定要不要抑制播报，而**生产代码里一个调用点都没有** ——
    // 唯一的调用者是它自己的那条测试。抑制实际发生在 `AppRealtimeCoordinator`，
    // 那边已经改成按 `eventType` 判定（`lifecycleStatus(forEventType:)`）。
    //
    // 删掉而不是留着的理由不是「没人用」，是**它会被照抄**：按正文匹配意味着后端改任何一条
    // 通知模板的正文都会静默改变 iOS 的播报行为，后端新增的 `REMATCH_ACCEPTED` 就是这么被吞掉的。
    // 片段表里还混着 `"测试志愿者"` / `"志愿者测试"` 两条——测试数据渗进产品代码，
    // 本身就是这段代码只为测试而活的证据。

    var activeOrderId: Int64? {
        order?.orderId ?? currentOrderId
    }

    func clearPeerLocation() {
        latestVolunteerSample = nil
        latestVolunteerCoordinate = nil
        latestVolunteerWebSocketDate = nil
        refreshVolunteerDistance()
    }

    func refreshVolunteerDistance() {
        defer { syncOrderLiveActivity() }
        guard let order, order.status.offersVolunteerDistanceToStart else {
            volunteerDistanceToStartText = nil
            return
        }
        volunteerDistanceToStartText = order.volunteerDistanceToStartText(from: latestVolunteerCoordinate)
    }

    /// 锁屏「约跑进度」卡（#919）。订单、磨合安排单、陪跑员位置任一变了都走这里；内容没变时控制器什么都不做。
    ///
    /// 磨合数据还没拉回来（`introCall == nil`）时按首页口径喂：卡上已是 B3 的不会被冲回 B2。
    func syncOrderLiveActivity() {
        guard #available(iOS 16.2, *), let order else { return }
        let introCallKnown = order.status == .pendingIntroCall && introCall != nil
        let snapshot = introCallKnown
            ? BlindOrderActivityController.IntroCallSnapshot(
                reviewingPlan: introCallRunnerStep == .reviewingPlan,
                deadline: introCall?.windowEndsAt?.backendTimestamp
            )
            : nil
        let distance = order.status.offersVolunteerDistanceToStart
            ? BlindOrderActivityController.volunteerDistanceMeters(
                volunteer: latestVolunteerCoordinate,
                meetingPoint: order.startCoordinate
            )
            : nil
        BlindOrderActivityController.shared.sync(
            order: order,
            source: order.status == .pendingIntroCall && !introCallKnown ? .home : .orderPage,
            introCall: snapshot,
            volunteerDistanceMeters: distance
        )
    }

    /// 🚩 判据是 `fetchesVolunteerLocation`（后端 `sharesLiveLocation()` 那三态），
    /// **不是** `offersVolunteerDistanceToStart`（念不念距离那两态）。两者 2026-08-31 拆开，
    /// 拆之前这里用后者，于是 `PENDING_ACCEPT` 每 5 秒白调一次、`IN_PROGRESS` 一次都不调 ——
    /// 而 `IN_PROGRESS` 正是走散检测唯一需要兜底的那一段。
    func refreshVolunteerLocationFallbackIfNeeded(for order: OrderDetailResponse, appState: AppState) async {
        guard order.status.fetchesVolunteerLocation else { return }
        let freshness = PeerLocationFreshness(threshold: peerFreshness)
        let websocketSampleIsFresh = latestVolunteerWebSocketDate.map { freshness.isFresh(capturedAt: $0, now: Date()) } ?? false
        guard !appState.isWebSocketConnected || !websocketSampleIsFresh else { return }

        do {
            let response = try await appState.orders.volunteerLocation()
            guard let coordinate = Self.volunteerFallbackCoordinate(from: response.data, matching: order) else { return }
            latestVolunteerCoordinate = coordinate
            refreshVolunteerDistance()
            feedEscortPeerLocation(from: response.data, coordinate: coordinate, order: order, appState: appState)
        } catch {
            // 订单轮询才是权威源，兜底拿不到位置不致命 —— 所以这里既不清空已知位置，也不播报。
            //
            // **404 尤其不是错误**：位置 key 不存在（志愿者超过 TTL 没上报）后端就返 404，
            // 契约明写「这是正常情况，客户端应静默保持上一个已知位置，别念报错」
            // （`api_spec.yaml:2365-2366`）。对盲人来说，陪跑途中每隔几秒念一次
            // 「获取位置失败」既没有可执行的动作，又会占住他用来听环境和陪跑员说话的通道。
        }
    }

    /// 把兜底坐标喂给走散检测（`LiveEscortSessionCoordinator` 只读
    /// `AppRealtimeCoordinator` 的对方样本存量，没有自己的 REST 兜底）。
    ///
    /// 🚩 **与上面那句 `latestVolunteerCoordinate = coordinate` 是两件事，故意分开写：**
    ///
    /// | | 念距离（上面那条） | 走散检测（这一条） |
    /// |---|---|---|
    /// | 问的是 | 屏幕上/播报里那个数字 | 两个人还在不在一起 |
    /// | `updatedAt` 缺失 | **放行**（`volunteerFallbackCoordinate` 的既有口径，失败开放） | **不喂** |
    /// | 新鲜度 | 30 秒（后端 Redis TTL） | 15 秒（`peerFreshness`，由 coordinator 判） |
    ///
    /// 缺 `updatedAt` 时不喂，是因为这一条唯一能凑的替代值是「现在」——
    /// 那会让一个 29 秒前的坐标伪装成刚采的，把「已经走散了」演成「一切正常」。
    /// 念距离那条允许缺失是相反方向的选择：那里拦一次的后果只是数字不出现，
    /// 而这条链路已经因为两道失败闭合的闸各坏过一次（见 `volunteerFallbackCoordinate`）。
    private func feedEscortPeerLocation(
        from data: VolunteerLocationData?,
        coordinate: CLLocationCoordinate2D,
        order: OrderDetailResponse,
        appState: AppState
    ) {
        guard let capturedAtMilliseconds = data?.updatedAt else { return }
        appState.realtimeCoordinator.ingestFallbackPeerLocation(
            RealtimePeerLocationSample(
                orderId: order.orderId,
                ownerRole: .volunteer,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                timestampMilliseconds: capturedAtMilliseconds
            )
        )
    }

    /// 志愿者位置 REST 兜底的新鲜度阈值。与后端 Redis `vol:loc:{id}` 的 TTL
    /// （`app.volunteer.location-ttl-seconds`）取同一个数：key 还在 ⇒ 志愿者这么久内上报过。
    static let volunteerFallbackFreshness: TimeInterval = 30

    /// REST 兜底拿到的坐标能不能采信。抽成静态方法只为**可测** —— 唯一调用点埋在 async 网络分支里。
    ///
    /// **这个方法只做一件事：判坐标能不能用。它的每一道闸都必须失败开放**，因为它拦掉一次
    /// 的后果不是「显示旧值」而是「『志愿者距出发地点约 X』整个不出现，且没有任何日志」——
    /// 这条链路已经因为两道失败闭合的闸各坏过一次：
    ///
    /// - `updatedAt` 曾是 `String?` + `ISO8601DateFormatter`，而后端当时**压根不发这个字段**
    ///   ⇒ `flatMap` 恒 nil ⇒ 恒 return。对真实后端 100% 静默失效，而 Mock 自己造了一个
    ///   `updatedAt`，于是开发期永远看不到。
    /// - `status` 曾因后端键名是 `orderStatus` 而恒为 nil，那条比较从未真正执行过。
    ///
    /// 两个字段都在 2026-08-20（后端 `119c810`）对齐了，所以两道闸会**第一次真的开始工作** ——
    /// 这正是最危险的时刻：把它们原样留着，等于在这一刻新增两条能否掉坐标的分支，
    /// 而失败表现与它们各自修的那个 bug 一模一样。因此：
    ///
    /// 1. **`status` 不再参与判定。** 契约原话：「拿它做交叉校验时应『不一致以本条为准并刷新订单』，
    ///    **不要用它否掉坐标** —— 坐标是这个端点存在的唯一理由」（`api_spec.yaml:2355-2357`）。
    ///    不一致时也不额外发一次刷新请求：本方法由 `loadOrder` 调用，递归回去会死循环；
    ///    而订单本来就 5 秒轮询一次（`AppConstants.Timing.orderPollingInterval`），
    ///    最多晚一轮就拿到权威状态。多一条立即刷新路径的风险大于那 5 秒。
    /// 2. **`updatedAt` 缺失一律放行**，只在它真的有值时判新鲜度。后端 2026-08-20 才补上这个字段，
    ///    生产未必已部署 —— 失败闭合就会原地重演上面第一条。
    /// 3. 时间戳落在**未来**（设备时钟偏差）按「刚采样」处理，不因此丢坐标。与 WebSocket 那条
    ///    `PeerLocationFreshness.accept` 的 `max(0, ...)` 口径一致。
    static func volunteerFallbackCoordinate(
        from data: VolunteerLocationData?,
        matching order: OrderDetailResponse,
        now: Date = Date()
    ) -> CLLocationCoordinate2D? {
        guard let data,
              data.coordinateIsValid,
              data.orderId == nil || data.orderId == order.orderId,
              let lat = data.lat,
              let lng = data.lng else { return nil }
        if let updatedAt = data.updatedAt {
            let capturedAt = Date(timeIntervalSince1970: TimeInterval(updatedAt) / 1_000)
            let age = max(0, now.timeIntervalSince(capturedAt))
            guard age <= volunteerFallbackFreshness else { return nil }
        }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}
