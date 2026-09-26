import CoreLocation
import XCTest
@testable import blindRun

/// 跑步中节奏信号 / 暂停 / 提示条 / 求助面板 / 电量（OpenSpec `add-running-rhythm-pause-and-help-panel`）。
/// 手势、触感、真实朗读只能真机验；这里钉的是它们之前的每一个判定。
@MainActor
final class RunningRhythmAndHelpTests: XCTestCase {

    private let formatter = DateFormatter.aidRunBackendLocalDateTime
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func stamp(_ secondsAgo: TimeInterval) -> String {
        formatter.string(from: now.addingTimeInterval(-secondsAgo))
    }

    private func order(_ json: String) throws -> OrderDetailResponse {
        try JSONDecoder().decode(OrderDetailResponse.self, from: Data(json.utf8))
    }

    private func inProgress(run: RunView?, surname: String? = "李") throws -> OrderDetailResponse {
        var detail = try order(#"{"orderId":7,"status":"IN_PROGRESS"}"#)
        detail.run = run
        detail.blindSurname = surname
        return detail
    }

    // MARK: - 解码降级

    func testRunObjectDecodesAndBadFieldsDegradeWithoutBreakingTheOrder() throws {
        let good = try order(#"{"orderId":7,"status":"IN_PROGRESS","blindSurname":"李","run":{"paused":true,"lastSignal":"SLOWER","lastSignalAt":"2026-09-19T07:19:10","runnerBatteryLow":false}}"#)
        XCTAssertEqual(good.run?.lastSignal, .slower)
        XCTAssertTrue(good.isRunPaused)
        XCTAssertEqual(good.runnerShortName, "李")

        let paused = try order(#"{"orderId":7,"status":"IN_PROGRESS","run":{"paused":true,"elapsedSeconds":1112}}"#)
        XCTAssertEqual(paused.run?.elapsedClockText, "18:32", "暂停灰条的「计时停在」读 run.elapsedSeconds")

        let odd = try order(#"{"orderId":7,"status":"IN_PROGRESS","run":{"paused":"yes","lastSignal":"WAVE","lastSignalAt":123}}"#)
        XCTAssertEqual(odd.run?.lastSignal, .unknown, "不认识的信号降级，不许整条崩")
        XCTAssertNil(odd.run?.paused)
        XCTAssertNil(odd.run?.lastSignalAt)
        XCTAssertFalse(odd.isRunPaused)
        XCTAssertEqual(odd.runnerShortName, "跑者", "没有姓氏时退回「跑者」，不念掩码全名")
    }

    func testReplacingStatusKeepsRunAndSurnames() throws {
        var detail = try inProgress(run: RunView(paused: true, lastSignal: .faster, lastSignalAt: stamp(5)))
        detail.volunteerSurname = "张"
        let replaced = detail.replacingStatus(with: .inProgress)
        XCTAssertEqual(replaced.run, detail.run)
        XCTAssertEqual(replaced.blindSurname, "李")
        XCTAssertEqual(replaced.volunteerSurname, "张")
    }

    // MARK: - 节奏卡

    func testRhythmCardWithoutAnySignalSaysSo() {
        let card = VolunteerRhythmCardPresentation.make(run: nil, name: "李", highlightUntil: nil, now: now)
        XCTAssertEqual(card.style, .empty)
        XCTAssertEqual(card.title, "李还没有发来节奏")
        XCTAssertNil(card.trailing)
    }

    func testRhythmCardTurnsStaleJustAfterFiveMinutes() {
        let fresh = VolunteerRhythmCardPresentation.make(
            run: RunView(lastSignal: .slower, lastSignalAt: stamp(299)), name: "李", highlightUntil: nil, now: now
        )
        XCTAssertEqual(fresh.style, .fresh)
        XCTAssertEqual(fresh.label, "李的节奏")
        XCTAssertEqual(fresh.title, "稍慢一点")
        XCTAssertEqual(fresh.trailing, "4 分钟前")

        let stale = VolunteerRhythmCardPresentation.make(
            run: RunView(lastSignal: .slower, lastSignalAt: stamp(301)), name: "李", highlightUntil: nil, now: now
        )
        XCTAssertEqual(stale.style, .stale)
        XCTAssertEqual(stale.label, "上次反馈")
    }

    func testSignalCardShowsOnlyForEightSecondsAndNeverForOK() {
        let run = RunView(lastSignal: .slower, lastSignalAt: stamp(1))
        let during = VolunteerRhythmCardPresentation.make(run: run, name: "李", highlightUntil: now.addingTimeInterval(0.5), now: now)
        XCTAssertEqual(during.style, .signal(.slower))
        XCTAssertEqual(during.title, "李：稍慢一点")

        let after = VolunteerRhythmCardPresentation.make(run: run, name: "李", highlightUntil: now, now: now)
        XCTAssertEqual(after.style, .fresh)

        let ok = VolunteerRhythmCardPresentation.make(
            run: RunView(lastSignal: .ok, lastSignalAt: stamp(1)), name: "李", highlightUntil: now.addingTimeInterval(5), now: now
        )
        XCTAssertEqual(ok.style, .fresh, "「刚刚好」不变黄")
    }

    // MARK: - 信号到达判定

    func testArrivalFiresOnlyForANewFreshSignalAfterTheFirstLoad() throws {
        let before = try inProgress(run: RunView(lastSignal: .ok, lastSignalAt: stamp(120)))
        let arrived = try inProgress(run: RunView(lastSignal: .slower, lastSignalAt: stamp(29)))

        XCTAssertNil(RunSignalArrival.detect(previous: nil, updated: arrived, now: now), "首次加载只显示不提醒")
        XCTAssertEqual(RunSignalArrival.detect(previous: before, updated: arrived, now: now), .slower)
        XCTAssertNil(RunSignalArrival.detect(previous: arrived, updated: arrived, now: now), "同一条不重复提醒")

        let late = try inProgress(run: RunView(lastSignal: .slower, lastSignalAt: stamp(31)))
        XCTAssertNil(RunSignalArrival.detect(previous: before, updated: late, now: now), "切回前台补拉到的旧信号不是「刚刚」")
    }

    // MARK: - 提示条

    func testTipBarShowsOnlyTheHighestPriority() {
        let weakLongAgo = now.addingTimeInterval(-60)
        XCTAssertEqual(
            VolunteerRunTip.resolve(separationAlertAt: now.addingTimeInterval(-59), runnerBatteryLow: true, weakLocationSince: weakLongAgo, now: now),
            .separated
        )
        XCTAssertEqual(
            VolunteerRunTip.resolve(separationAlertAt: now.addingTimeInterval(-61), runnerBatteryLow: true, weakLocationSince: weakLongAgo, now: now),
            .runnerBatteryLow,
            "走散提示 60 秒后收起"
        )
        XCTAssertEqual(
            VolunteerRunTip.resolve(separationAlertAt: nil, runnerBatteryLow: false, weakLocationSince: weakLongAgo, now: now),
            .weakLocation
        )
    }

    func testWeakLocationNeedsTwentySustainedSecondsAboveFiftyMeters() {
        var since = VolunteerRunTip.weakSince(previous: nil, accuracy: 60, now: now)
        XCTAssertEqual(since, now)
        since = VolunteerRunTip.weakSince(previous: since, accuracy: 80, now: now.addingTimeInterval(10))
        XCTAssertEqual(since, now, "持续期间起点不动")
        XCTAssertNil(VolunteerRunTip.resolve(separationAlertAt: nil, runnerBatteryLow: false, weakLocationSince: since, now: now.addingTimeInterval(19)))
        XCTAssertEqual(
            VolunteerRunTip.resolve(separationAlertAt: nil, runnerBatteryLow: false, weakLocationSince: since, now: now.addingTimeInterval(20)),
            .weakLocation
        )
        XCTAssertEqual(VolunteerRunTip.weakSince(previous: since, accuracy: nil, now: now), since, "没有精度读数不改变状态")
        XCTAssertNil(VolunteerRunTip.weakSince(previous: since, accuracy: 50, now: now), "恰好 50 米不算差")
    }

    // MARK: - 陪跑员 VM

    func testPauseCallsTheEndpointAndFlipsThePageAtOnce() async throws {
        let service = FakeOrderService()
        service.pauseRunResult = .success(())
        let appState = AppState(orders: service)
        let speech = SpeechService()
        let viewModel = VolunteerInServiceViewModel()
        viewModel.configure(with: appState, speechService: speech, initialOrder: try inProgress(run: nil))

        await viewModel.pauseRun()

        XCTAssertEqual(service.callCount("pauseRun(orderId:)"), 1)
        XCTAssertEqual(service.lastOrderId, 7)
        XCTAssertTrue(viewModel.order?.isRunPaused == true)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isTogglingPause)
    }

    /// security review A1：面板在 `IN_PROGRESS` 打开，按下去时订单可能已经结束。
    func testPauseIsNotSentOnceTheRunHasEnded() async throws {
        let service = FakeOrderService()
        service.pauseRunResult = .success(())
        let appState = AppState(orders: service)
        let speech = SpeechService()
        let viewModel = VolunteerInServiceViewModel()
        var completed = try inProgress(run: nil)
        completed = completed.replacingStatus(with: .completed)
        viewModel.configure(with: appState, speechService: speech, initialOrder: completed)

        await viewModel.pauseRun()

        XCTAssertEqual(service.callCount("pauseRun(orderId:)"), 0)
    }

    func testFailedResumeStaysPausedAndSaysSo() async throws {
        let service = FakeOrderService()
        service.resumeRunResult = .failure(APIError.serverError(
            ErrorResponse(code: "ORDER_STATUS_NOT_ALLOWED", message: "当前订单状态不允许该操作")
        ))
        let appState = AppState(orders: service)
        let speech = SpeechService()
        let viewModel = VolunteerInServiceViewModel()
        viewModel.configure(with: appState, speechService: speech, initialOrder: try inProgress(run: RunView(paused: true)))

        await viewModel.resumeRun()

        XCTAssertTrue(viewModel.order?.isRunPaused == true, "失败时不许假装已继续")
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testContactSupportSubmitsOneTicketWithTheOrderId() async throws {
        let safety = FakeSafetyService()
        let orders = FakeOrderService()
        let appState = AppState(safety: safety, orders: orders)
        let speech = SpeechService()
        let viewModel = VolunteerInServiceViewModel()
        viewModel.configure(with: appState, speechService: speech, initialOrder: try inProgress(run: nil))

        await viewModel.requestSupportCallback()
        await viewModel.requestSupportCallback()

        XCTAssertEqual(safety.lastSupportTicket?.orderId, 7)
        XCTAssertEqual(safety.calls.filter { $0 == "submitSupportTicket(_:)" }.count, 1, "已提交之后不重复提交")
        XCTAssertEqual(viewModel.supportRequestState, .submitted)
    }

    func testContactSupportFailureCanBeRetried() async throws {
        let safety = FakeSafetyService()
        safety.submitSupportTicketResult = .failure(URLError(.notConnectedToInternet))
        let orders = FakeOrderService()
        let appState = AppState(safety: safety, orders: orders)
        let speech = SpeechService()
        let viewModel = VolunteerInServiceViewModel()
        viewModel.configure(with: appState, speechService: speech, initialOrder: try inProgress(run: nil))

        await viewModel.requestSupportCallback()
        XCTAssertEqual(viewModel.supportRequestState, .failed)
        safety.submitSupportTicketResult = .success(())
        await viewModel.requestSupportCallback()
        XCTAssertEqual(viewModel.supportRequestState, .submitted)
    }

    func testKilometerIsAnnouncedOnlyWhenCrossedAndOnlyWithTheToggleOn() throws {
        var enabled = true
        let speech = SpeechService()
        let orders = FakeOrderService()
        let appState = AppState(orders: orders)
        let viewModel = VolunteerInServiceViewModel(voiceBroadcastEnabled: { enabled })
        viewModel.configure(with: appState, speechService: speech, initialOrder: try inProgress(run: nil))

        viewModel.announceKilometerIfNeeded(TrackStats(distanceMeters: 1_200, durationSeconds: 463, avgPaceSecPerKm: 386))
        XCTAssertNil(speech.lastSpokenText, "进页时已经跑过的公里不补念")

        viewModel.announceKilometerIfNeeded(TrackStats(distanceMeters: 2_010, durationSeconds: 900, avgPaceSecPerKm: 448))
        XCTAssertEqual(speech.lastSpokenText, "2 公里，用时 15 分 0 秒")

        enabled = false
        viewModel.announceKilometerIfNeeded(TrackStats(distanceMeters: 3_010, durationSeconds: 1_300, avgPaceSecPerKm: 432))
        XCTAssertEqual(speech.lastSpokenText, "2 公里，用时 15 分 0 秒", "开关关着不念")
    }

    // MARK: - 跑者端

    func testRunnerRhythmSuccessSpeaksWhatWasSent() async throws {
        let service = FakeOrderService()
        service.rhythmResult = .success(RhythmSignalResponse(delivered: true))
        let appState = AppState(orders: service)
        let viewModel = RunnerRhythmViewModel()
        var spoken: [String] = []

        await viewModel.send(.slower, orderId: 7, appState: appState, speak: { spoken.append($0) }, speakError: { spoken.append($0) })

        XCTAssertEqual(service.lastRhythmSignal, .slower)
        XCTAssertEqual(spoken, ["已告诉陪跑员：稍慢一点"])
        XCTAssertEqual(viewModel.notice?.isProblem, false)
    }

    func testRunnerRhythmNotDeliveredIsNotSpokenAsSuccess() async throws {
        let service = FakeOrderService()
        service.rhythmResult = .success(RhythmSignalResponse(delivered: false))
        let appState = AppState(orders: service)
        let viewModel = RunnerRhythmViewModel()
        var spoken: [String] = []

        await viewModel.send(.slower, orderId: 7, appState: appState, speak: { spoken.append($0) }, speakError: { spoken.append($0) })

        XCTAssertEqual(spoken, ["陪跑员可能没收到，可以直接跟对方说"])
        XCTAssertEqual(viewModel.notice?.isProblem, true)
    }

    func testRunnerRhythmRateLimitIsVisibleAndAudible() async throws {
        let service = FakeOrderService()
        service.rhythmResult = .failure(APIError.rateLimited(RateLimitInfo(message: "too many", retryAfterSeconds: 10)))
        let appState = AppState(orders: service)
        let viewModel = RunnerRhythmViewModel()
        var spoken: [String] = []

        await viewModel.send(.faster, orderId: 7, appState: appState, speak: { spoken.append($0) }, speakError: { spoken.append($0) })

        XCTAssertEqual(spoken, ["刚发过，稍等再按"])
        XCTAssertEqual(viewModel.notice?.text, "刚发过，稍等再按")
        XCTAssertEqual(viewModel.notice?.isProblem, true)
        XCTAssertNil(viewModel.sending)
    }

    func testRhythmRequestEncodesTheContractValue() throws {
        let data = try JSONEncoder().encode(RunRhythmRequest(signal: .faster))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"signal":"FASTER"}"#)
    }

    // MARK: - 电量

    func testBatteryLevelIsOmittedWhenUnknown() throws {
        XCTAssertNil(RunMotionSnapshot.normalizedBatteryLevel(-1))
        XCTAssertEqual(RunMotionSnapshot.normalizedBatteryLevel(0.18) ?? -1, 0.18, accuracy: 0.0001)

        let sample = LocatedCoordinate(
            coordinate: .init(latitude: 22.5, longitude: 113.9),
            system: .gcj02Backend,
            capturedAt: now
        )
        let without = try JSONEncoder().encode(LiveEscortSessionCoordinator.locationMessage(sample: sample, motion: nil))
        XCTAssertFalse(String(decoding: without, as: UTF8.self).contains("batteryLevel"))

        var motion = RunMotionSnapshot()
        motion.batteryLevel = 0.5
        let with = try JSONEncoder().encode(LiveEscortSessionCoordinator.locationMessage(sample: sample, motion: motion))
        XCTAssertTrue(String(decoding: with, as: UTF8.self).contains(#""batteryLevel":0.5"#))
    }
}
