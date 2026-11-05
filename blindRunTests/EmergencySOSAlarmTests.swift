import Combine
import CoreLocation
import XCTest
@testable import blindRun

@MainActor
final class EmergencySOSAlarmTests: XCTestCase, EmergencySOSTestSupport {

    // MARK: - 警报音与震动（code review A10）

    /// 倒计时每一秒**恰好**响一次、震一次。
    ///
    /// ⚠️ code review 指出 `EmergencyAlarm.observerForTesting` / `playerForTesting` 此前
    /// 只被装成 no-op、一条断言都没有，而它们的存在理由被逐字写在实现里：
    /// 「没有断言的实现，和不存在的实现在下一个人眼里是一样的 ——
    /// 而这是盲人判断「倒计时开始了没有」的唯一非视觉信号」。
    ///
    /// 屏幕上那个圆环对一个戴着骨传导耳机、手机绑在腰上的跑者不存在；
    /// 声音和震动**就是**倒计时本身。
    @MainActor
    func testCountdownSoundsAndVibratesOncePerSecond() async {
        var ticks: [EmergencyAlarm.Kind] = []
        var vibrations = 0
        EmergencyAlarm.observerForTesting = { ticks.append($0) }
        EmergencyHaptics.observerForTesting = { _ in vibrations += 1 }
        defer { Self.teardownAlarmObservers() }

        let coordinator = EmergencyCoordinator()
        let safety = FakeSafetyService()
        safety.triggerEmergencyResult = .success(Self.countdownResponse(eventId: 903))
        coordinator.beginCountdown(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate(latitude: 39.915, longitude: 116.404) }
        )
        try? await Task.sleep(nanoseconds: 4_500_000_000)

        XCTAssertEqual(
            ticks.count,
            EmergencyCoordinator.countdownSeconds,
            "倒计时响了 \(ticks.count) 声，应当是每秒一声共 \(EmergencyCoordinator.countdownSeconds) 声"
        )
        XCTAssertEqual(vibrations, EmergencyCoordinator.countdownSeconds, "震动次数和声音对不上")
        // 用的是倒计时那一声，不是连续警报 —— 后者是志愿者端强提醒用的，会一直循环。
        XCTAssertTrue(ticks.allSatisfy { $0 == .countdownTick })
    }

    /// 🔴 **同一种警报音始终是同一个播放器对象。**
    ///
    /// 这条不是优化，是防崩：2026-08-16 `RecordingCue` 曾经「每次发声 new 一个播放器、
    /// 覆盖同一个静态槽」，于是上一声还在播时就被释放，音频队列随后把
    /// `-[AVAudioPlayer finishedPlaying:]` 派回主线程、打在已被复用的内存上 ——
    /// 真机表现是**崩在任意一条与音频无关的用例上**
    /// （记忆 `finishedplaying-crash-means-player-freed-not-delegate`）。
    ///
    /// 倒计时这一声每秒触发一次、而一声只有 0.17 秒，**正是同一个形状**。
    @MainActor
    func testEmergencyAlarmReusesOnePlayerPerKind() throws {
        // 这条要真的建播放器，所以不能装 observer（装了就被接管、一个播放器都不会创建）。
        EmergencyAlarm.observerForTesting = nil
        EmergencyHaptics.observerForTesting = { _ in }
        defer { Self.teardownAlarmObservers() }

        EmergencyAlarm.countdownTick()
        let first = try XCTUnwrap(
            EmergencyAlarm.playerForTesting(.countdownTick),
            "第一次触发之后没有留下播放器 —— 出了作用域就停，提示音等于没响"
        )
        EmergencyAlarm.countdownTick()
        let second = try XCTUnwrap(EmergencyAlarm.playerForTesting(.countdownTick))

        XCTAssertTrue(
            first === second,
            "同一种警报音换了播放器对象 —— 上一声还在播时被释放，就是那次 use-after-free 的形状"
        )
        EmergencyAlarm.stopAll()
    }

    /// 🔴 **还在等定位时会话结束，一个字节都不许发。**
    ///
    /// 漏掉的后果：上一个账号退出登录之后，那条求助带着新登录账号的 token 发出去 ——
    /// 事件挂在错误的人身上，短信发给错误的家属。
    @MainActor
    func testResetWhileLocatingSendsNothing() async {
        let (coordinator, safety) = Self.makeCountdownFixture()
        defer { Self.teardownAlarmObservers() }
        safety.triggerEmergencyResult = .success(Self.countdownResponse(eventId: 902))

        coordinator.beginCountdown(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: {
                try? await Task.sleep(nanoseconds: 800_000_000)
                return Self.coordinate(latitude: 39.915, longitude: 116.404)
            }
        )
        try? await Task.sleep(nanoseconds: 100_000_000)
        coordinator.reset()
        XCTAssertEqual(coordinator.state, .idle)

        try? await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertTrue(safety.calls.isEmpty, "退出登录之后那条求助仍然发了出去：\(safety.calls)")
    }

    /// 发不出去的状态**不该白数三秒**。那三秒里用户以为求助在路上。
    @MainActor
    func testCountdownIsRefusedOutsideInProgress() async {
        let (coordinator, safety) = Self.makeCountdownFixture()
        defer { Self.teardownAlarmObservers() }

        for status in RunOrderStatus.allCases where status != .inProgress {
            coordinator.reset()
            coordinator.beginCountdown(
                order: Self.makeOrder(status: status),
                role: .blind,
                userID: 7,
                safety: safety,
                locate: { Self.coordinate(latitude: 39.915, longitude: 116.404) }
            )
            XCTAssertFalse(
                coordinator.state.isCountingDown,
                "\(status) 不能发起求助，却进了倒计时"
            )
            XCTAssertTrue(coordinator.state.isFailure, "\(status) 下按求助没有给出任何失败反馈")
        }
        XCTAssertTrue(safety.calls.isEmpty)
    }

    /// 没在倒计时的时候取消是**空操作**，不是「撤销已经发出的求助」。
    ///
    /// 两个动作打的是完全不同的后端：取消倒计时零请求，撤销求助走
    /// `PUT /api/emergency/{id}/cancel` 并给联系人补发解除短信。混掉的表现是
    /// 「我只是想收起这一屏，结果把一个真的求助撤了」。
    @MainActor
    func testCancellingWhenNotCountingDownDoesNothing() async {
        let coordinator = EmergencyCoordinator()
        let safety = FakeSafetyService()
        let outcome = await coordinator.cancelCountdown(safety: safety)
        XCTAssertNil(outcome)
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertTrue(safety.calls.isEmpty)
    }
}
