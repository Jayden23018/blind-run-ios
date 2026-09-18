import XCTest
@testable import blindRun

/// 陪跑员结束那一刻，盲人端到底**说了几句、说了什么**。
///
/// 与 `BlindRunPhaseTests` 的分工：那边验的是纯函数（这一句该怎么拼、该不该拼），
/// 这边验的是**整条链路真的走通了** —— 拉终值、只播一句、播的那句里有里程。
///
/// 🔴 **为什么必须有这一层而不能只验纯函数**：这条链路上最贵的两个缺陷都在纯函数之外。
///
/// 1. `apply()` 在看到终态时会调 `stopPolling()`，而 `pollingTask` **就是当前正在跑的
///    这个任务** —— 自我取消。取消之后 `loadOrder` 后面几个 `await`（含终值轨迹）
///    都在一个已取消的任务里跑，`URLSession` 会立刻抛 cancelled ⇒ 那一句里
///    **永远没有里程**，而纯函数测试全绿（它拿的是手工传进去的 stats）。
/// 2. 两句变一句这件事，只有数**调用次数**才看得出来：`SpeechService.speak` 会先
///    `stopSpeaking(.immediate)`，所以后到的那句把先到的从半句切断，
///    而 `lastSpokenText` 照样等于期望值（记忆 `later-speak-silently-cuts-the-earlier-one`）。
///    所以这里断言的是 `spokenHistoryForTesting` **整个数组**，不是它的最后一项。
final class BlindRunFinishAnnouncementTests: XCTestCase {

    /// 设计稿 ④ 那一屏的取值：5.20 公里 / 33:41 / 6'28"。
    private static let finalStats = TrackStats(
        distanceMeters: 5_204,
        durationSeconds: 2_021,
        avgPaceSecPerKm: 388
    )

    @MainActor
    func testFinishingTheRunSpeaksExactlyOneSentenceCarryingTheFinalDistance() async {
        let orders = FakeOrderService()
        let safety = FakeSafetyService()
        orders.orderDetailResult = .success(Self.order(status: .completed))
        safety.orderTrackResult = .success(Self.track(status: .completed))

        let appState = AppState(safety: safety, orders: orders)
        appState.currentEnvironment = .mock
        let speech = SpeechService()
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: speech)
        // 上一轮轮询看到的还是「跑步中」—— 这一轮才是陪跑员按下结束的那一刻。
        viewModel.order = Self.order(status: .inProgress)

        viewModel.startPolling(orderId: Self.orderId)
        await Self.waitUntil { !speech.spokenHistoryForTesting.isEmpty }
        // 再等一会儿，好让「第二句」如果存在的话有机会冒出来。
        try? await Task.sleep(nanoseconds: 200_000_000)
        viewModel.stopPolling()

        XCTAssertEqual(
            speech.spokenHistoryForTesting,
            ["张结束了本次陪跑，共跑 5.20 公里。"],
            """
            结束那一刻必须**只有一句、且带里程**。
            · 多出一句 ⇒ 后到的把先到的从半句切断（设计稿：变形为总结状态时不再播第二遍）
            · 少了里程 ⇒ 终值那次 `/track` 没拉到（最可能的原因是它跑在一个已被
              `stopPolling()` 自我取消的任务里）
            """
        )
        XCTAssertEqual(
            viewModel.trackStats?.distanceMeters, 5_204,
            "④ 那一屏的三个数字就是这个 stats —— 它为 nil 时屏幕上是三个 `--`"
        )
    }

    /// 终值那次拉不到轨迹时，**那句话照样要出声**（只是没有里程那半句）。
    ///
    /// 「这件事结束了」比「跑了多远」要紧得多：跑者已经停下来了，而他看不见屏幕。
    @MainActor
    func testTheSentenceStillFiresWhenTheFinalTrackIsUnavailable() async {
        let orders = FakeOrderService()
        let safety = FakeSafetyService()
        orders.orderDetailResult = .success(Self.order(status: .completed))
        safety.orderTrackResult = .failure(
            APIError.serverError(ErrorResponse(code: "TRACK_UNAVAILABLE", message: "轨迹暂时不可用"))
        )

        let appState = AppState(safety: safety, orders: orders)
        appState.currentEnvironment = .mock
        let speech = SpeechService()
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: speech)
        viewModel.order = Self.order(status: .inProgress)

        viewModel.startPolling(orderId: Self.orderId)
        await Self.waitUntil { !speech.spokenHistoryForTesting.isEmpty }
        viewModel.stopPolling()

        XCTAssertEqual(speech.spokenHistoryForTesting, ["张结束了本次陪跑。"])
    }

    /// 冷启动进一张已完成的单（从历史记录点进来）：**也只有一句**，
    /// 而且是「状态句 + 三个数字」那一句，不说「刚刚结束」。
    @MainActor
    func testColdStartIntoAFinishedOrderSpeaksTheMergedSentenceOnce() async {
        let orders = FakeOrderService()
        let safety = FakeSafetyService()
        orders.orderDetailResult = .success(Self.order(status: .completed))
        safety.orderTrackResult = .success(Self.track(status: .completed))

        let appState = AppState(safety: safety, orders: orders)
        appState.currentEnvironment = .mock
        let speech = SpeechService()
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: speech)
        // 冷启动：`order` 还是 nil。

        viewModel.startPolling(orderId: Self.orderId)
        await Self.waitUntil { !speech.spokenHistoryForTesting.isEmpty }
        try? await Task.sleep(nanoseconds: 200_000_000)
        viewModel.stopPolling()

        XCTAssertEqual(speech.spokenHistoryForTesting.count, 1, "冷启动也只该有一句")
        let spoken = speech.spokenHistoryForTesting.first ?? ""
        XCTAssertTrue(spoken.contains("服务已完成"), "状态那一半丢了：\(spoken)")
        XCTAssertTrue(spoken.contains("已跑 5.20 公里"), "数字那一半丢了：\(spoken)")
        XCTAssertTrue(spoken.contains("平均配速 6 分 28 秒每公里"), "配速标签或数值不对：\(spoken)")
        XCTAssertFalse(spoken.contains("结束了本次陪跑"), "三天前的事不该说成刚刚发生：\(spoken)")
    }

    /// 🔴 **连着看两张已完成的单，两张都要出声。**
    ///
    /// `SpeechService` 是全 App 一份（`blindRunApp` 上的 `@StateObject`），而它的
    /// `speakStatusChange` 用 `status != lastSpokenStatus` 去重 —— 第二张单的状态
    /// 还是 `COMPLETED`，走那个 funnel 就会被**静默吞掉**。
    /// 这条用例钉的就是「完成播报不许依赖那个全局 guard」。
    ///
    /// 改版前这一场景由 `.task` 里那句轨迹总结兜着（它走普通 `speak`、不看状态），
    /// 而那句已经被删掉了 —— 也就是说这里不补，就是一次**由本次改动引入的**静默回退。
    @MainActor
    func testTwoFinishedOrdersInARowBothSpeak() async {
        let speech = SpeechService()

        for orderId in [Self.orderId, Self.orderId + 1] {
            let orders = FakeOrderService()
            let safety = FakeSafetyService()
            orders.orderDetailResult = .success(
                .preview(orderId: orderId, status: .completed, volunteerName: "张*")
            )
            safety.orderTrackResult = .success(Self.track(status: .completed))
            let appState = AppState(safety: safety, orders: orders)
            appState.currentEnvironment = .mock
            // 每次点开一张单都是一个新的 view model（`@StateObject` 跟着页面走）。
            let viewModel = BlindOrderStatusViewModel()
            viewModel.configure(appState: appState, speechService: speech)

            viewModel.startPolling(orderId: orderId)
            await Self.waitUntil { speech.spokenHistoryForTesting.count >= (orderId == Self.orderId ? 1 : 2) }
            viewModel.stopPolling()
        }

        XCTAssertEqual(
            speech.spokenHistoryForTesting.count, 2,
            "第二张已完成的单一个字都没播 —— 被 `lastSpokenStatus` 那个全局 guard 吞了"
        )
    }

    // MARK: - 辅助

    private static let orderId: Int64 = 777

    /// 🚩 **`orderId` 必须与 `startPolling` 传的那个一致。** 对不上时
    /// `AppRealtimeCoordinator.reconcileOrderDetail` 判「这是别人家的响应」直接返回 nil，
    /// `loadOrder` 原地 return —— 于是 `apply` 不跑、播报不发、而用例只会红在
    /// 「一句都没播」上，看着像功能坏了（第一版就这么误判过一次）。
    private static func order(status: RunOrderStatus) -> OrderDetailResponse {
        .preview(orderId: orderId, status: status, volunteerName: "张*", volunteerPhone: "13800000001")
    }

    private static func track(status: RunOrderStatus) -> OrderTrackResponse {
        OrderTrackResponse(
            status: status,
            volunteerTrack: [],
            volunteerStats: TrackStats(distanceMeters: nil, durationSeconds: nil, avgPaceSecPerKm: nil),
            blindTrack: [],
            blindStats: finalStats
        )
    }

    /// 轮询是异步的，条件满足就立刻返回。**超时不在这里断言** ——
    /// 让调用处那条 `XCTAssertEqual` 去报「一句都没播」，那句失败信息更有用。
    private static func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await MainActor.run(body: condition) { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
