import Combine
import CoreLocation
import XCTest
@testable import blindRun

@MainActor
final class EmergencySOSCountdownTests: XCTestCase, EmergencySOSTestSupport {

    // MARK: - 倒计时（屏 3）· 服务端计时（后端 #388 ③）



    /// 🔴 **按下之后立刻登记一条服务端倒计时，而且必须带 `useCountdown`。**
    ///
    /// 不带的话后端是**立即触发**：家属短信当场发出，而屏幕上还在数「3、2、1，现在取消还来得及」。
    /// 取消走 `PUT /cancel`，服务端回 `CANCELLED` 时文案只说「没有发出、没有通知任何人」。
    @MainActor
    func testCountdownRegistersAServerCountdownAndCancelWithdrawsIt() async {
        let (coordinator, safety) = Self.makeCountdownFixture()
        defer { Self.teardownAlarmObservers() }
        safety.triggerEmergencyResult = .success(Self.countdownResponse(eventId: 950))
        safety.cancelEmergencyResult = .success(EmergencyCancelResponse(success: true, eventId: 950, status: "CANCELLED"))

        coordinator.beginCountdown(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate(latitude: 39.915, longitude: 116.404) }
        )
        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(safety.calls, ["triggerEmergency(_:)"])
        XCTAssertEqual(safety.lastTriggerRequest?.useCountdown, true, "没带 useCountdown = 立即发出，倒计时成了摆设")
        XCTAssertTrue(coordinator.state.isCountingDown, "服务端回了 COUNTDOWN，却没进倒计时")
        XCTAssertTrue(coordinator.state.isBusy, "倒计时期间必须挡住重复触发")
        XCTAssertFalse(coordinator.state.isFailure)
        XCTAssertEqual(coordinator.activeEvent?.status, .countdown)

        let outcome = await coordinator.cancelCountdown(safety: safety)

        XCTAssertEqual(safety.lastEventId, 950, "撤的不是这一条")
        XCTAssertEqual(outcome?.state, .withdrawnBeforeSending)
        XCTAssertEqual(outcome?.message, "已撤回。求助没有发出，没有通知任何人。")
        for word in ["短信", "联系人", "家属", "解除"] {
            XCTAssertFalse(outcome?.message.contains(word) ?? true, "从未发出的求助却提到了「\(word)」")
        }
        XCTAssertNil(coordinator.activeEvent)

        // 撤回之后再等过原截止时刻 —— 本机倒数真的停了，不会再到点去念「已记录」。
        try? await Task.sleep(nanoseconds: 3_500_000_000)
        XCTAssertEqual(coordinator.state, .withdrawnBeforeSending)
        XCTAssertEqual(safety.calls, ["triggerEmergency(_:)", "cancelEmergencyByOwner(eventId:)"])
    }

    /// 照服务端的截止时刻倒数，每秒一句且句句带「可以取消」；到点**只说已记录**，不说送达。
    @MainActor
    func testCountdownFollowsTheServerDeadlineThenReportsRecordedNotDelivered() async {
        let (coordinator, safety) = Self.makeCountdownFixture()
        defer { Self.teardownAlarmObservers() }
        safety.triggerEmergencyResult = .success(Self.countdownResponse(eventId: 900))

        var spoken: [String] = []
        coordinator.beginCountdown(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate(latitude: 39.915, longitude: 116.404) },
            announce: { spoken.append($0) }
        )
        try? await Task.sleep(nanoseconds: 3_700_000_000)

        XCTAssertEqual(safety.calls.count, 1, "倒数期间客户端又发了请求：\(safety.calls)")
        XCTAssertEqual(coordinator.activeEvent?.eventID, 900)
        XCTAssertEqual(coordinator.state, .acknowledged(.pending))
        let countdownLines = spoken.filter { $0.contains("秒后发出") }
        XCTAssertEqual(countdownLines.count, EmergencyCoordinator.countdownSeconds)
        for line in countdownLines {
            XCTAssertTrue(line.contains("取消"), "这一句没告诉用户还能取消：\(line)")
        }
        XCTAssertEqual(spoken.first, EmergencySafetyCopy.countdownTitle, "进倒计时那一刻没有播报")
        XCTAssertEqual(spoken.last, EmergencySafetyCopy.submitted(.pending))
    }

    /// 服务端没采纳倒计时（`countdownEndsAt` 为 null）= 已经立即发出。**不许再自己数三秒** ——
    /// 那就是后端注释里说的「屏幕还在倒数，求助其实已经发出去了」。
    @MainActor
    func testUnacceptedCountdownIsReportedAsSentImmediately() async {
        let (coordinator, safety) = Self.makeCountdownFixture()
        defer { Self.teardownAlarmObservers() }
        safety.triggerEmergencyResult = .success(
            EmergencyTriggerResponse(success: true, eventId: 904, status: "CONTACT_NOTIFIED", countdownEndsAt: nil)
        )
        var spoken: [String] = []
        coordinator.beginCountdown(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate(latitude: 39.915, longitude: 116.404) },
            announce: { spoken.append($0) }
        )
        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(coordinator.state, .acknowledged(.contactNotified))
        XCTAssertFalse(spoken.contains { $0.contains("秒后发出") }, "已经发出去了还在念倒计时：\(spoken)")
    }

    /// 撤回请求在路上时服务端已经开火：回的是 `FALSE_ALARM`，这是一次**撤销已发出的求助**，
    /// 文案必须提解除通知，不能说「没有发出」。
    @MainActor
    func testWithdrawThatArrivesAfterTheServerFiredIsReportedAsCancellation() async {
        let (coordinator, safety) = Self.makeCountdownFixture()
        defer { Self.teardownAlarmObservers() }
        safety.triggerEmergencyResult = .success(Self.countdownResponse(eventId: 951))
        safety.cancelEmergencyResult = .success(EmergencyCancelResponse(success: true, eventId: 951, status: "FALSE_ALARM"))
        coordinator.beginCountdown(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate(latitude: 39.915, longitude: 116.404) }
        )
        try? await Task.sleep(nanoseconds: 300_000_000)

        let outcome = await coordinator.cancelCountdown(safety: safety)

        XCTAssertEqual(outcome?.state, .cancelledByOwner)
        XCTAssertFalse(outcome?.message.contains("没有发出") ?? true)
    }

    /// 🔴 撤回没成功：服务端倒计时照走。**必须说可能已经发出**，事件留着以便再撤、并露出 120/110。
    @MainActor
    func testFailedWithdrawSaysTheRequestMayStillGoOut() async {
        let (coordinator, safety) = Self.makeCountdownFixture()
        defer { Self.teardownAlarmObservers() }
        safety.triggerEmergencyResult = .success(Self.countdownResponse(eventId: 952))
        safety.cancelEmergencyResult = .failure(URLError(.notConnectedToInternet))
        coordinator.beginCountdown(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate(latitude: 39.915, longitude: 116.404) }
        )
        try? await Task.sleep(nanoseconds: 300_000_000)

        let outcome = await coordinator.cancelCountdown(safety: safety)

        XCTAssertEqual(outcome?.state, .withdrawFailed(nil))
        XCTAssertTrue(outcome?.isFailure ?? false)
        XCTAssertTrue(outcome?.message.contains("可能已经发出") ?? false)
        XCTAssertFalse(outcome?.message.contains("已取消") ?? true)
        XCTAssertEqual(coordinator.activeEvent?.eventID, 952, "事件丢了，「撤销求助」就没了")
        XCTAssertNotEqual(
            EmergencySafetyCopy.screenTitle(for: coordinator.state, hasActiveEvent: true),
            EmergencySafetyCopy.unsentTitle,
            "撤回失败时标题不许说「求助未发出」"
        )
    }

    /// 🔴 重连 / 冷启动读到自己的 `COUNTDOWN` 事件：**接着倒数，不许写成「已发出」**。
    /// 写成 `.acknowledged` 的话取消按钮会变成「撤销求助」、圆环消失 —— 而这是唯一还能反悔的状态。
    @MainActor
    func testRecoveredCountdownResumesInsteadOfClaimingSent() async throws {
        EmergencyAlarm.observerForTesting = { _ in }
        EmergencyHaptics.observerForTesting = { _ in }
        defer { Self.teardownAlarmObservers() }
        let safety = FakeSafetyService()
        let json = """
        {"success":true,"code":200,"data":{"id":953,"orderId":4242,"userId":7,
         "triggeredAt":"2026-09-25T10:00:00","triggerType":"BUTTON","status":"COUNTDOWN",
         "hasGpsLocation":true,"countdownEndsAt":"\(Self.backendTime(secondsFromNow: 3))"}}
        """
        safety.activeEmergencyResult = .success(
            try APIPayloadDecoder.decodePayload(EmergencyActiveEnvelope.self, from: Data(json.utf8), decoder: JSONDecoder())
        )
        let coordinator = Self.makeRecoverableCoordinator(safety: safety)

        await coordinator.refreshActiveEvent(userID: 7)

        XCTAssertTrue(coordinator.state.isCountingDown, "恢复出来的倒计时被写成了 \(coordinator.state)")
        XCTAssertEqual(coordinator.activeEvent?.eventID, 953)
        coordinator.reset()
    }

    /// 倒计时期间再按一下**不该叠出第二个倒计时，也不该把倒计时重新计到 3**。
    /// 三次按下拉开 1.2 秒，数「3 秒后发出」念了几次：正确实现一次，重启实现三次。
    @MainActor
    func testSecondPressDuringCountdownNeitherResendsNorRestartsTheCountdown() async {
        let (coordinator, safety) = Self.makeCountdownFixture()
        defer { Self.teardownAlarmObservers() }
        // 截止时刻按整秒截断，写 3 秒实际只有 2.x 秒 —— 第三下（2.4 秒）会落在倒计时**之后**，
        // 那时再按本来就该发起新的一次。给 4 秒，三下都落在倒计时里。
        safety.triggerEmergencyResult = .success(Self.countdownResponse(eventId: 901, secondsFromNow: 4))
        let order = Self.makeOrder(status: .inProgress)
        var spoken: [String] = []
        let press = {
            coordinator.beginCountdown(
                order: order,
                role: .blind,
                userID: 7,
                safety: safety,
                locate: { Self.coordinate(latitude: 39.915, longitude: 116.404) },
                announce: { spoken.append($0) }
            )
        }

        press()
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        press()
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        press()

        try? await Task.sleep(nanoseconds: 1_500_000_000)

        XCTAssertEqual(safety.calls.count, 1, "连按三下发出了 \(safety.calls.count) 条求助")
        let restarts = spoken.filter { $0 == EmergencySafetyCopy.countdown(secondsRemaining: 3) }
        XCTAssertEqual(restarts.count, 1, "倒计时被重新计到 3 了 \(restarts.count) 次")
    }

    // MARK: - 屏 3 / 3b 的标题（code review A2 / A3）

    /// 🔴 **顶部那句大标题必须与此刻的真实状态一致。**
    ///
    /// code review 抓到的原缺陷：`.locating` / `.submitting` 落进 `else` 分支，
    /// 于是在**一个字节都还没发出去**的那最长约 20 秒里（等定位 5 秒 + 请求超时 15 秒），
    /// 屏幕顶部 44pt 的红色大标题写着「求助已发出」，正文写着「正在获取当前位置」。
    /// 标题带 `.isHeader`，VoiceOver 滑到页首听到的就是这句。
    ///
    /// 这条用例**逐状态穷举**，而不是只挑两三个 —— `testNoEmergencyCopyClaimsAnSMSWasDelivered`
    /// 扫的是字符串常量，扫不到一个 `if/else` 的取值，那正是它漏掉这个缺陷的原因。
    func testScreenTitleNeverClaimsSentBeforeAnythingWasSent() {
        let notSentYet: [EmergencySOSState] = [
            .countingDown(secondsRemaining: 3),
            .locating,
            .submitting,
            .unsentNoLocation(nil),
            .unsentNoLocation(.permissionDenied),
            .failed("网络异常"),
            .cooldown(retryAfterSeconds: 42),
        ]
        for state in notSentYet {
            let title = EmergencySafetyCopy.screenTitle(for: state, hasActiveEvent: false)
            XCTAssertNotEqual(
                title,
                EmergencySafetyCopy.sentTitle,
                "\(state) 时一个字节都还没发出去，标题却写着「\(title)」"
            )
        }

        // 还在路上的两态：**进行时**，不能是将来时的承诺、也不能是完成时。
        XCTAssertEqual(EmergencySafetyCopy.screenTitle(for: .locating, hasActiveEvent: false), EmergencySafetyCopy.sendingTitle)
        XCTAssertEqual(EmergencySafetyCopy.screenTitle(for: .submitting, hasActiveEvent: false), EmergencySafetyCopy.sendingTitle)

        // 失败三态：**不许回落成「即将发出」**。那是一句将来时的承诺，而这条求助已经死了，
        // 必须靠用户自己按「再发一次求助」。
        for state in [EmergencySOSState.unsentNoLocation(nil), .failed("网络异常"), .cooldown(retryAfterSeconds: 1)] {
            XCTAssertEqual(
                EmergencySafetyCopy.screenTitle(for: state, hasActiveEvent: false),
                EmergencySafetyCopy.unsentTitle,
                "\(state) 的标题应当直说没发出去"
            )
        }

        // 真的发出去了的才准用完成时。`contactNotifyFailed` 也在内：
        // 失败的是**通知联系人**，求助本身已经发出去了。
        for state in [EmergencySOSState.acknowledged(.contactNotified), .contactSmsDelivered, .contactNotifyFailed] {
            XCTAssertEqual(EmergencySafetyCopy.screenTitle(for: state, hasActiveEvent: true), EmergencySafetyCopy.sentTitle)
        }

        XCTAssertEqual(
            EmergencySafetyCopy.screenTitle(for: .cancelledByOwner, hasActiveEvent: false),
            EmergencySafetyCopy.cancelledTitle
        )
        // 倒计时内撤回：求助从未发出。撤回失败：发没发出不知道，两个完成时都不许用。
        XCTAssertEqual(
            EmergencySafetyCopy.screenTitle(for: .withdrawnBeforeSending, hasActiveEvent: false),
            EmergencySafetyCopy.unsentTitle
        )
        let withdrawFailedTitle = EmergencySafetyCopy.screenTitle(for: .withdrawFailed(nil), hasActiveEvent: true)
        XCTAssertNotEqual(withdrawFailedTitle, EmergencySafetyCopy.sentTitle)
        XCTAssertNotEqual(withdrawFailedTitle, EmergencySafetyCopy.unsentTitle)
        // `.idle` 只由「有没有事件」决定，不猜。
        XCTAssertEqual(EmergencySafetyCopy.screenTitle(for: .idle, hasActiveEvent: true), EmergencySafetyCopy.sentTitle)
        XCTAssertEqual(EmergencySafetyCopy.screenTitle(for: .idle, hasActiveEvent: false), EmergencySafetyCopy.unsentTitle)
    }
}
