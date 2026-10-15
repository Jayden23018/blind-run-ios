import SwiftUI
import XCTest
@testable import blindRun

/// 盲人端「先通个电话」B1–B3（#434，OpenSpec `add-intro-call-meetup-plan` 第 4 组）。
///
/// 每条用例都挑了**能分出偷懒实现**的输入：
/// - 回前台喂 `(.inactive → .active)`（拨号确认框点取消），断言**不**进 B2；
/// - 409 走「重新收听」，断言红条没亮、也没走错误播报；
/// - 10 分钟提醒连续轮询多次，断言只响一次；
/// - 节流在 59 秒与 61 秒两侧各打一次。
@MainActor
final class BlindIntroCallMeetupPlanTests: XCTestCase {

    private static let orderId: Int64 = 434

    // MARK: - 场景搭建

    private final class FakeReminderNotifier: IntroCallPlanReminderNotifying {
        private(set) var scheduled: [Date] = []
        private(set) var cancelCount = 0
        func schedule(orderId: Int64, at dueAt: Date) { scheduled.append(dueAt) }
        func cancel(orderId: Int64) { cancelCount += 1 }
    }

    private struct Harness {
        let orders: FakeOrderService
        let speech: SpeechService
        let viewModel: BlindOrderStatusViewModel
        let notifier: FakeReminderNotifier
        let clock: Clock
    }

    /// 可拨的时钟。
    private final class Clock {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    private static let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeHarness(view: IntroCallView?) async -> Harness {
        let orders = FakeOrderService()
        if let view { orders.introCallViewResult = .success(view) }
        orders.notifyIntroCallIncomingResult = .success(())
        let appState = AppState(safety: FakeSafetyService(), orders: orders)
        appState.currentEnvironment = .mock
        let speech = SpeechService()
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: speech)
        let notifier = FakeReminderNotifier()
        viewModel.introCallPlanReminderNotifier = notifier
        let clock = Clock(Self.start)
        viewModel.introCallNow = { clock.now }
        viewModel.order = Self.order(status: .pendingIntroCall)
        if view != nil { await viewModel.reloadIntroCall() }
        return Harness(orders: orders, speech: speech, viewModel: viewModel, notifier: notifier, clock: clock)
    }

    private static func view(
        plan: IntroCallPlanView? = nil,
        myDecision: String? = nil,
        windowEndsAt: Date? = nil
    ) -> IntroCallView {
        IntroCallView(
            counterpartName: "李*",
            counterpartPhone: "13800000002",
            counterpartPhoneMasked: nil,
            myDecision: myDecision,
            windowEndsAt: windowEndsAt.map { DateFormatter.aidRunBackendLocalDateTime.string(from: $0) },
            startAddress: "朝阳公园南门",
            plannedStartTime: "2026-10-16T07:00:00",
            plannedEndTime: "2026-10-16T08:00:00",
            startLatitude: 39.9300,
            startLongitude: 116.4700,
            plan: plan
        )
    }

    private static func plan(version: Int, submittedAt: Date? = nil) -> IntroCallPlanView {
        IntroCallPlanView(
            version: version,
            meetSpotNote: "东门保安亭左侧",
            volunteerTopColor: .red,
            submittedAt: submittedAt.map { DateFormatter.aidRunBackendLocalDateTime.string(from: $0) }
        )
    }

    private static func order(status: RunOrderStatus) -> OrderDetailResponse {
        var order = OrderDetailResponse(
            orderId: orderId,
            status: status,
            startAddress: "朝阳公园东门",
            startLatitude: nil,
            startLongitude: nil,
            endAddress: nil,
            endLatitude: nil,
            endLongitude: nil,
            plannedStart: nil,
            plannedEnd: nil,
            blindName: nil,
            blindPhone: nil,
            volunteerPhone: nil,
            acceptedAt: nil,
            createdAt: nil,
            expectedDurationMinutes: nil,
            pacePreference: nil,
            routePreference: nil,
            routeNotes: nil,
            hasGuideDogThisRun: nil,
            specialNotes: nil,
            visionLevel: nil,
            tetherPreference: nil,
            chatPreference: nil
        )
        order.volunteerName = "李*"
        return order
    }

    // MARK: - B2 只在「从后台回来」时进入（修审查 #8）

    /// 🚨 拨号确认框点「取消」走的是 `.inactive → .active`。这一路**不许**进 B2 ——
    /// 用户根本没打这通电话，B2 却会告诉他「陪跑员将按通话内容填写」。
    func testDialConfirmationCancelledIsNotTreatedAsReturningFromTheCall() async {
        let h = await makeHarness(view: Self.view())
        XCTAssertNotNil(h.viewModel.introCallDialURL())

        h.viewModel.observeScenePhase(.inactive)
        h.viewModel.observeScenePhase(.active)

        XCTAssertFalse(h.viewModel.hasReturnedFromIntroCallDialer)
        XCTAssertEqual(h.viewModel.introCallRunnerStep, .awaitingCall)
    }

    /// 真打出去了：`background → inactive → active`。这一路进 B2。
    /// 与上一条成对：两条一起才说明判据认的是「进过后台」而不是「回到 active」。
    func testComingBackFromTheBackgroundAfterDialingEntersAwaitingPlan() async {
        let h = await makeHarness(view: Self.view())
        XCTAssertNotNil(h.viewModel.introCallDialURL())

        h.viewModel.observeScenePhase(.inactive)
        h.viewModel.observeScenePhase(.background)
        h.viewModel.observeScenePhase(.inactive)
        h.viewModel.observeScenePhase(.active)

        XCTAssertTrue(h.viewModel.hasReturnedFromIntroCallDialer)
        XCTAssertEqual(h.viewModel.introCallRunnerStep, .awaitingPlan)
    }

    /// 没拨过号、只是切出去又回来（看了眼微信）：不是「打完电话回来」，仍是 B1。
    func testBackgroundRoundTripWithoutDialingStaysOnAwaitingCall() async {
        let h = await makeHarness(view: Self.view())

        h.viewModel.observeScenePhase(.background)
        h.viewModel.observeScenePhase(.active)

        XCTAssertEqual(h.viewModel.introCallRunnerStep, .awaitingCall)
    }

    /// 服务端安排单优先于本地标记：B2 的标记没置起（例如杀进程重启），有安排单照样是 B3（修审查 #4）。
    func testServerPlanWinsOverTheLocalForegroundMarker() async {
        let h = await makeHarness(view: Self.view(plan: Self.plan(version: 1)))

        XCTAssertFalse(h.viewModel.hasReturnedFromIntroCallDialer)
        XCTAssertEqual(h.viewModel.introCallRunnerStep, .reviewingPlan)
    }

    // MARK: - 确认：新入口、409、失败

    /// 「合适」只走带版本的新入口；老入口 `submitIntroCallDecision`（不带版本）不再被调用。
    func testConfirmingUsesTheVersionedEndpointAndNeverTheLegacyAccept() async {
        let h = await makeHarness(view: Self.view(plan: Self.plan(version: 3)))
        h.orders.confirmIntroCallPlanResult = .success(.confirmed)
        h.orders.orderDetailResult = .success(Self.order(status: .pendingAccept))

        await h.viewModel.confirmIntroCallPlan()

        XCTAssertEqual(h.orders.lastConfirmedPlanVersion, 3, "确认的不是屏幕上那一版")
        XCTAssertTrue(h.orders.calls.contains("confirmIntroCallPlan(orderId:version:)"))
        XCTAssertFalse(
            h.orders.calls.contains("submitIntroCallDecision(_:orderId:)"),
            "又走了不带版本的老入口 —— 开关打开后会被 409 INTRO_CALL_PLAN_REQUIRED"
        )
    }

    /// 409 `INTRO_CALL_PLAN_STALE`（服务层转成 `.planChanged`）**不是错误**：
    /// 不亮红条、不走错误播报，念「请重新收听」、焦点回标题；紧接着的刷新看到新版本**不再念第二遍**。
    func testStalePlanIsRelistenedNotTreatedAsAnError() async {
        let h = await makeHarness(view: Self.view(plan: Self.plan(version: 1)))
        let focusBefore = h.viewModel.introCallPlanFocusRequest
        h.orders.confirmIntroCallPlanResult = .success(.planChanged)
        h.orders.introCallViewResult = .success(Self.view(plan: Self.plan(version: 2)))
        let spokenBefore = h.speech.spokenHistoryForTesting.count

        await h.viewModel.confirmIntroCallPlan()

        XCTAssertFalse(h.viewModel.introCallConfirmFailed, "版本过期亮了「确认未送达」红条")
        XCTAssertNil(h.viewModel.errorMessage)
        XCTAssertTrue(h.viewModel.introCallPlanChangedNotice)
        XCTAssertGreaterThan(h.viewModel.introCallPlanFocusRequest, focusBefore, "焦点没回标题")
        let spoken = Array(h.speech.spokenHistoryForTesting.dropFirst(spokenBefore))
        XCTAssertEqual(spoken, [IntroCallMeetupCopy.planChangedRelisten], "409 之后该且只该念一遍「请重新收听」")
        XCTAssertFalse(spoken.contains(IntroCallMeetupCopy.confirmNotDelivered))
        XCTAssertEqual(h.viewModel.introCallRunnerStep, .reviewingPlan)
    }

    /// 确认没送到：留在 B3，屏幕红条**与**播报同时出现（修审查 #3：此前只有语音）。
    func testConfirmFailureShowsTheBannerAndSpeaks() async {
        let h = await makeHarness(view: Self.view(plan: Self.plan(version: 1)))
        h.orders.confirmIntroCallPlanResult = .failure(APIError.networkError(URLError(.timedOut)))

        await h.viewModel.confirmIntroCallPlan()

        XCTAssertTrue(h.viewModel.introCallConfirmFailed)
        XCTAssertEqual(h.speech.lastSpokenText, IntroCallMeetupCopy.confirmNotDelivered)
        XCTAssertEqual(h.viewModel.introCallRunnerStep, .reviewingPlan)
    }

    /// 盲人在 B3 时陪跑员又改了一版：轮询看到版本变了 ⇒ 念「请重新收听」、焦点回标题。
    func testVolunteerRevisingThePlanWhileListeningAsksToRelisten() async {
        let h = await makeHarness(view: Self.view(plan: Self.plan(version: 1)))
        let focusBefore = h.viewModel.introCallPlanFocusRequest
        h.orders.introCallViewResult = .success(Self.view(plan: Self.plan(version: 2)))

        await h.viewModel.reloadIntroCall()
        await h.viewModel.reloadIntroCall()

        let relistens = h.speech.spokenHistoryForTesting.filter { $0 == IntroCallMeetupCopy.planChangedRelisten }
        XCTAssertEqual(relistens.count, 1, "同一次改版念了 \(relistens.count) 遍")
        XCTAssertEqual(h.viewModel.introCallPlanFocusRequest, focusBefore + 1)
    }

    // MARK: - 10 分钟未确认提醒

    /// 安排单发来 10 分钟仍未确认：**只提醒一次**，之后的每一轮轮询都不再念。
    func testUnconfirmedPlanReminderSpeaksOnlyOnce() async {
        let windowEndsAt = Self.start.addingTimeInterval(20 * 60)
        let view = Self.view(plan: Self.plan(version: 1, submittedAt: Self.start), windowEndsAt: windowEndsAt)
        let h = await makeHarness(view: view)

        h.clock.now = Self.start.addingTimeInterval(9 * 60 + 59)
        await h.viewModel.reloadIntroCall()
        XCTAssertFalse(h.speech.spokenHistoryForTesting.contains(IntroCallCopy.blindPlanReminderSpeech), "不到 10 分钟就提醒了")

        for seconds in [600, 605, 640, 700] {
            h.clock.now = Self.start.addingTimeInterval(TimeInterval(seconds))
            await h.viewModel.reloadIntroCall()
        }

        let reminders = h.speech.spokenHistoryForTesting.filter { $0 == IntroCallCopy.blindPlanReminderSpeech }
        XCTAssertEqual(reminders.count, 1)
    }

    /// 到点时 App 不在前台：进后台时排本地通知；回到前台时撤掉，且**不再补播** —— 那一次已经由通知送达了。
    func testReminderGoesThroughALocalNotificationWhileAwayAndIsNotRepeatedOnReturn() async {
        let windowEndsAt = Self.start.addingTimeInterval(20 * 60)
        let view = Self.view(plan: Self.plan(version: 1, submittedAt: Self.start), windowEndsAt: windowEndsAt)
        let h = await makeHarness(view: view)

        h.viewModel.observeScenePhase(.background)
        XCTAssertEqual(h.notifier.scheduled, [Self.start.addingTimeInterval(600)])

        h.clock.now = Self.start.addingTimeInterval(12 * 60)
        h.viewModel.observeScenePhase(.active)
        XCTAssertGreaterThan(h.notifier.cancelCount, 0, "回前台没撤掉还没响的通知")
        await h.viewModel.reloadIntroCall()

        XCTAssertFalse(
            h.speech.spokenHistoryForTesting.contains(IntroCallCopy.blindPlanReminderSpeech),
            "通知已经送达过，回前台又念了一遍"
        )
    }

    /// 到点时窗口已经结束：不提醒（超时由服务端宣布）。
    func testReminderIsSkippedWhenTheWindowEndsFirst() {
        var reminder = IntroCallPlanReminder()
        reminder.observe(
            planVersion: 1,
            submittedAt: Self.start,
            isAwaitingConfirmation: true,
            windowEndsAt: Self.start.addingTimeInterval(9 * 60),
            now: Self.start
        )
        XCTAssertNil(reminder.dueAt)
        XCTAssertFalse(reminder.consumeIfDue(now: Self.start.addingTimeInterval(11 * 60)))
    }

    // MARK: - notify-incoming 60 秒节流（修审查 #10）

    func testNotifyIncomingIsThrottledToOncePerMinuteButDialingIsNot() async throws {
        let h = await makeHarness(view: Self.view())

        XCTAssertNotNil(h.viewModel.introCallDialURL())
        h.clock.now = Self.start.addingTimeInterval(59)
        XCTAssertNotNil(h.viewModel.introCallDialURL(), "节流拦住了拨号本身")
        h.clock.now = Self.start.addingTimeInterval(61)
        XCTAssertNotNil(h.viewModel.introCallDialURL())
        try await Task.sleep(nanoseconds: 200_000_000)

        let notifies = h.orders.calls.filter { $0 == "notifyIntroCallIncoming(orderId:)" }
        XCTAssertEqual(notifies.count, 2, "0 秒、59 秒、61 秒三次拨号应只推 2 次")
    }

    // MARK: - 结局播报

    /// B3 时窗口到点、订单退回派单：先说「本次见面安排未生效」，再说中性的那句。
    func testTimeoutWhileReviewingSaysThePlanDidNotTakeEffectFirst() async {
        let h = await makeHarness(view: Self.view(plan: Self.plan(version: 1)))
        h.orders.orderDetailResult = .success(Self.order(status: .pendingMatch))

        h.viewModel.startPolling(orderId: Self.orderId)
        await Self.waitUntil { h.viewModel.order?.status == .pendingMatch }
        h.viewModel.stopPolling()

        XCTAssertTrue(
            h.speech.spokenHistoryForTesting.contains("本次见面安排未生效。正在为你寻找合适的陪跑伙伴。"),
            "实际念的：\(h.speech.spokenHistoryForTesting)"
        )
    }

    /// 没听过安排单就结束（B1 时超时）：只念中性那句，不提「安排」。
    func testRoundEndingBeforeAnyPlanKeepsTheNeutralCopy() {
        XCTAssertEqual(BlindIntroCallOutcomeCopy.roundEnded(hadPlan: false), IntroCallCopy.continuedSearch)
        XCTAssertEqual(
            BlindIntroCallOutcomeCopy.roundEnded(hadPlan: true),
            "本次见面安排未生效。正在为你寻找合适的陪跑伙伴。"
        )
    }

    /// 约好那一刻的整句，逐字对视觉稿；称呼去星号（读屏不念「星号」）。
    func testAgreedAnnouncementReadsTimePlaceSpotAndColour() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 20))!
        var order = Self.order(status: .pendingAccept)
        order = OrderDetailResponse(
            orderId: order.orderId, status: .pendingAccept, startAddress: "朝阳公园东门",
            startLatitude: nil, startLongitude: nil, endAddress: nil, endLatitude: nil, endLongitude: nil,
            plannedStart: "2026-10-16T07:30:00", plannedEnd: "2026-10-16T08:30:00",
            blindName: nil, blindPhone: nil, volunteerPhone: nil, acceptedAt: nil, createdAt: nil,
            expectedDurationMinutes: nil, pacePreference: nil, routePreference: nil, routeNotes: nil,
            hasGuideDogThisRun: nil, specialNotes: nil, visionLevel: nil, tetherPreference: nil, chatPreference: nil
        )
        order.volunteerName = "李*"
        order.meetSpotNote = "东门保安亭左侧"
        order.volunteerTopColor = .red

        XCTAssertEqual(
            BlindIntroCallOutcomeCopy.agreed(order: order, now: now, calendar: calendar),
            "约定完成。明天 7 点 30 分，朝阳公园东门，东门保安亭左侧。陪跑员李上衣为红色，见面时将主动上前并告知姓氏。"
        )
    }

    // MARK: - B3 的行

    /// 行的顺序与读屏标签**就是** `planSpeech` 的 items：每项一个读屏元素，顺序固定。
    func testPlanRowsFollowTheFixedSpeechOrderOneElementEach() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 20))!
        let original = IntroCallOriginalArrangement(
            plannedStartTime: calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 7)),
            plannedEndTime: calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 8)),
            startAddress: "朝阳公园南门",
            startLatitude: 39.9300,
            startLongitude: 116.4700
        )
        let plan = IntroCallMeetupPlan(
            version: 1,
            plannedStartTime: calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 7, minute: 30)),
            plannedEndTime: calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 8, minute: 30)),
            startAddress: "朝阳公园东门",
            startLatitude: 39.9372,
            startLongitude: 116.4700,
            meetSpotNote: "东门保安亭左侧",
            volunteerTopColor: .red,
            runnerTopColor: .blue
        )

        let layout = BlindMeetupPlanLayout.rows(
            plan: plan, original: original, volunteerName: "李*", now: now, calendar: calendar
        )
        let speech = IntroCallMeetupCopy.planSpeech(
            plan: plan, original: original, volunteerName: "李*", now: now, calendar: calendar
        )

        XCTAssertEqual(layout.rows.map(\.kind), [.time, .place, .meetSpot, .colors, .greeting])
        XCTAssertEqual(layout.rows.map(\.speech), speech.items)
        XCTAssertEqual(layout.titleSpeech, "陪跑员李已提交见面安排，共 2 项变更。")
        XCTAssertEqual(layout.rows.filter(\.isChanged).map(\.kind), [.time, .place])
        // 主值写**新**时间，「原定」写旧时间 —— 两个都在，不许只剩一个。
        let newClock = VolunteerOrderTimeCopy.clock(plan.plannedStartTime!)
        let oldClock = VolunteerOrderTimeCopy.clock(original.plannedStartTime!)
        XCTAssertTrue(layout.rows[0].values.first?.hasPrefix("明天 \(newClock)") == true, "\(layout.rows[0].values)")
        XCTAssertEqual(layout.rows[0].original?.hasPrefix("原定 \(oldClock)"), true, "\(String(describing: layout.rows[0].original))")
        XCTAssertEqual(layout.rows[1].values, ["朝阳公园东门"])
        XCTAssertEqual(layout.rows[1].original?.contains("原定 朝阳公园南门"), true)
        XCTAssertNil(layout.rows[2].original, "见面位置原约里没有，谈不上「原定」")
    }

    // MARK: - 工具

    private static func waitUntil(timeout: TimeInterval = 2, _ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
