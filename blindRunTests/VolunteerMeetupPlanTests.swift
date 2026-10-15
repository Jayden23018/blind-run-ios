import Combine
import CoreLocation
import XCTest
@testable import blindRun

/// 陪跑员端「见面安排」V1–V4（#433）。
///
/// 每条用例挑的是**能分出偷懒实现**的输入：
/// - 提前量：窗口还剩 14 分钟时，最早时刻落在 20:45 而不是 20:30（只算 30 分钟的实现给 20:30）
/// - 主按钮：把时间改回原约那一刻、重选同一个点，都必须仍是「按原约定」
/// - 倒计时：同一个节点连续轮询三次，只许播一次
/// - 夜间窗口：21:00–22:00 放行、21:30–22:30 拒（只看开始时刻的实现两个都放行）
@MainActor
final class VolunteerMeetupPlanTests: XCTestCase {

    // MARK: - 固定场景：原约「明天 7:00–8:00，朝阳公园南门」，现在是今天 20:00

    private let calendar = Calendar.aidRunBackend

    private func date(day: Int, hour: Int, minute: Int = 0, second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute, second: second))!
    }

    private var now: Date { date(day: 15, hour: 20) }

    /// 南门 → 东门 纬度差 0.0072° ≈ 800 米。
    private let southGate = (lat: 39.9300, lng: 116.4700)

    private var original: IntroCallOriginalArrangement {
        IntroCallOriginalArrangement(
            plannedStartTime: date(day: 16, hour: 7),
            plannedEndTime: date(day: 16, hour: 8),
            startAddress: "朝阳公园南门",
            startLatitude: southGate.lat,
            startLongitude: southGate.lng
        )
    }

    /// 往北挪 `meters` 米的一个点。
    private func place(_ address: String, northMeters meters: Double) -> VolunteerMeetupPlanDraft.Place {
        VolunteerMeetupPlanDraft.Place(address: address, latitude: southGate.lat + meters / 111_000, longitude: southGate.lng)
    }

    // MARK: - 主按钮文案随变更项变化

    func testSubmitButtonTitleFollowsWhatChanged() {
        var draft = VolunteerMeetupPlanDraft(original: original)
        XCTAssertEqual(draft.submitButtonTitle, "按原约定提交跑者确认")
        XCTAssertNil(draft.submitButtonCaption)

        draft.plannedStart = date(day: 16, hour: 7, minute: 30)
        XCTAssertEqual(draft.submitButtonTitle, "提交跑者确认")
        XCTAssertEqual(draft.submitButtonCaption, "已变更：开跑时间")

        draft.place = place("朝阳公园东门", northMeters: 800)
        XCTAssertEqual(draft.submitButtonCaption, "已变更：开跑时间、集合地点")

        // 改回原约那一刻、重选同一个点：都不算变更。
        draft.plannedStart = date(day: 16, hour: 7)
        draft.place = VolunteerMeetupPlanDraft.Place(address: "朝阳公园南门", latitude: southGate.lat, longitude: southGate.lng)
        XCTAssertEqual(draft.changedItems, [])
        XCTAssertEqual(draft.submitButtonTitle, "按原约定提交跑者确认")

        // 同名不同点也算改地点（集合点由可能是威胁来源的一方改动）。
        draft.place = place("朝阳公园南门", northMeters: 500)
        XCTAssertEqual(draft.submitButtonCaption, "已变更：集合地点")
    }

    /// 没改的项不发（`nil` = 按原约）；只改开始时不发结束，后端按原时长平移。
    func testRequestOnlyCarriesWhatChanged() {
        var draft = VolunteerMeetupPlanDraft(original: original)
        draft.meetSpotNote = "东门保安亭左侧"
        draft.volunteerTopColor = .red
        let unchanged = draft.request()
        XCTAssertNil(unchanged.plannedStartTime)
        XCTAssertNil(unchanged.place)
        XCTAssertEqual(unchanged.meetSpotNote, "东门保安亭左侧")
        XCTAssertEqual(unchanged.volunteerTopColor, .red)
        XCTAssertNil(unchanged.runnerTopColor, "「未确认」不发")

        draft.plannedStart = date(day: 16, hour: 7, minute: 30)
        draft.place = place("朝阳公园东门", northMeters: 800)
        let changed = draft.request()
        XCTAssertEqual(changed.plannedStartTime, "2026-10-16T07:30:00")
        XCTAssertNil(changed.plannedEndTime)
        XCTAssertEqual(changed.place?.address, "朝阳公园东门")
        XCTAssertEqual(draft.effectiveEnd, date(day: 16, hour: 8, minute: 30), "时长默认不变")
    }

    /// 「修改见面安排」用上一版预填；`.unknown` 颜色不回填成一个选中的色块。
    func testEditingPrefillsFromThePreviousVersion() {
        let plan = IntroCallMeetupPlan(
            version: 2, plannedStartTime: date(day: 16, hour: 7, minute: 30), plannedEndTime: nil,
            startAddress: "朝阳公园东门", startLatitude: southGate.lat + 0.0072, startLongitude: southGate.lng,
            meetSpotNote: "东门保安亭左侧", volunteerTopColor: .unknown, runnerTopColor: .blue
        )
        let draft = VolunteerMeetupPlanDraft(original: original, editing: plan)
        XCTAssertEqual(draft.changedItems, [.time, .place])
        XCTAssertEqual(draft.meetSpotNote, "东门保安亭左侧")
        XCTAssertNil(draft.volunteerTopColor)
        XCTAssertEqual(draft.runnerTopColor, .blue)
    }

    /// 30 字整是上限内、31 字超限；首尾空白不算（与请求体去空白一致）。超限不截断，由界面挡住提交。
    func testMeetSpotNoteOverThirtyCharactersIsFlaggedNotTruncated() {
        var draft = VolunteerMeetupPlanDraft(original: original)
        draft.meetSpotNote = "  " + String(repeating: "门", count: 30) + "  "
        XCTAssertFalse(draft.isMeetSpotNoteTooLong)
        draft.meetSpotNote = String(repeating: "门", count: 31)
        XCTAssertTrue(draft.isMeetSpotNoteTooLong)
        XCTAssertEqual(draft.meetSpotNote.count, 31, "不许静默截掉陪跑员写的字")
    }

    // MARK: - 提前量含窗口剩余

    func testEarliestStartAddsTheRemainingWindowAndRoundsUpToFiveMinutes() {
        // 窗口还剩 14 分钟：20:00 + 30 + 14 = 20:44 → 取整到 20:45。只算 30 分钟的实现给 20:30。
        XCTAssertEqual(
            VolunteerMeetupPlanDraft.earliestStart(now: now, windowEndsAt: date(day: 15, hour: 20, minute: 14), calendar: calendar),
            date(day: 15, hour: 20, minute: 45)
        )
        // 窗口拿不到 / 已过：只按 30 分钟。
        XCTAssertEqual(VolunteerMeetupPlanDraft.earliestStart(now: now, windowEndsAt: nil, calendar: calendar), date(day: 15, hour: 20, minute: 30))
        XCTAssertEqual(
            VolunteerMeetupPlanDraft.earliestStart(now: now, windowEndsAt: date(day: 15, hour: 19), calendar: calendar),
            date(day: 15, hour: 20, minute: 30)
        )
        // 取整：整档不动，多一秒进一档。
        XCTAssertEqual(VolunteerMeetupPlanDraft.roundedUp(date(day: 15, hour: 20, minute: 45), calendar: calendar), date(day: 15, hour: 20, minute: 45))
        XCTAssertEqual(
            VolunteerMeetupPlanDraft.roundedUp(date(day: 15, hour: 20, minute: 45, second: 1), calendar: calendar),
            date(day: 15, hour: 20, minute: 50)
        )
    }

    // MARK: - 就地校验

    /// 判据是**整段**：21:00–22:00 放行，21:30–22:30 拒。
    func testTimeErrorChecksTheWholeTripAgainstTheNightWindow() {
        let short = IntroCallOriginalArrangement(
            plannedStartTime: date(day: 16, hour: 19), plannedEndTime: date(day: 16, hour: 20),
            startAddress: "朝阳公园南门", startLatitude: southGate.lat, startLongitude: southGate.lng
        )
        var draft = VolunteerMeetupPlanDraft(original: short)
        draft.plannedStart = date(day: 16, hour: 21)
        XCTAssertNil(draft.timeError(now: now, windowEndsAt: nil))
        draft.plannedStart = date(day: 16, hour: 21, minute: 30)
        XCTAssertEqual(draft.timeError(now: now, windowEndsAt: nil), VolunteerMeetupPlanCopy.nightWindow)
    }

    func testPlaceErrorSpellsOutTheDistanceBeyondTheThreeKilometreLimit() {
        var draft = VolunteerMeetupPlanDraft(original: original)
        draft.place = place("望京", northMeters: 2900)
        XCTAssertNil(draft.placeError)
        draft.place = place("奥林匹克森林公园南门", northMeters: 8400)
        XCTAssertEqual(draft.placeError, "距原集合地点 8.4 公里，超出 3 公里调整上限。")
    }

    // MARK: - 提交错误落在哪一块

    func testSubmitErrorsLandUnderTheBlockTheyAreAbout() {
        func api(_ code: String) -> APIError { .serverError(ErrorResponse(code: code, message: "后端原话")) }

        let night = VolunteerMeetupPlanSubmitError.make(for: api("APPOINTMENT_IN_NIGHT_WINDOW"), distanceFromOriginal: nil)
        XCTAssertEqual(night, VolunteerMeetupPlanSubmitError(slot: .time, message: VolunteerMeetupPlanCopy.nightWindow))

        let tooSoon = VolunteerMeetupPlanSubmitError.make(for: api("APPOINTMENT_TOO_SOON"), distanceFromOriginal: nil)
        XCTAssertEqual(tooSoon, VolunteerMeetupPlanSubmitError(slot: .time, message: IntroCallMeetupCopy.planStartTooSoon))

        // 跑者那边时段冲突：只说不可用，不说原因。
        let unavailable = VolunteerMeetupPlanSubmitError.make(for: api("INTRO_CALL_PLAN_TIME_UNAVAILABLE"), distanceFromOriginal: nil)
        XCTAssertEqual(unavailable, VolunteerMeetupPlanSubmitError(slot: .time, message: IntroCallMeetupCopy.planTimeUnavailable))

        let far = VolunteerMeetupPlanSubmitError.make(for: api("INTRO_CALL_PLAN_TOO_FAR_FROM_ORIGINAL"), distanceFromOriginal: 8400)
        XCTAssertEqual(far, VolunteerMeetupPlanSubmitError(slot: .place, message: "距原集合地点 8.4 公里，超出 3 公里调整上限。"))
        let farUnknown = VolunteerMeetupPlanSubmitError.make(for: api("INTRO_CALL_PLAN_TOO_FAR_FROM_ORIGINAL"), distanceFromOriginal: nil)
        XCTAssertEqual(farUnknown.message, IntroCallMeetupCopy.planTooFarFromOriginal)

        let offline = VolunteerMeetupPlanSubmitError.make(for: URLError(.notConnectedToInternet), distanceFromOriginal: nil)
        XCTAssertEqual(offline.slot, .general)
    }

    // MARK: - V3 摘要

    func testSummaryMarksOnlyChangedRowsAndNamesUnconfirmedColours() {
        let plan = IntroCallMeetupPlan(
            version: 1, plannedStartTime: date(day: 16, hour: 7, minute: 30), plannedEndTime: date(day: 16, hour: 8, minute: 30),
            startAddress: nil, startLatitude: nil, startLongitude: nil,
            meetSpotNote: "南门保安亭左侧", volunteerTopColor: .red, runnerTopColor: nil
        )
        let summary = VolunteerMeetupPlanSummary.make(plan: plan, original: original, now: now, calendar: calendar)
        XCTAssertEqual(summary.rows.map(\.id), ["time", "place", "colors"])
        XCTAssertEqual(summary.rows[0].value, "明天 7:30 – 8:30")
        XCTAssertTrue(summary.rows[0].isChanged)
        XCTAssertEqual(summary.rows[1].value, "朝阳公园南门 · 南门保安亭左侧")
        XCTAssertFalse(summary.rows[1].isChanged)
        XCTAssertEqual(summary.rows[2].value, "本人 红色 · 跑者 未确认")
        for row in summary.rows {
            for word in ["听", "同意", "拒绝"] {
                XCTAssertFalse(row.accessibilityLabel.contains(word), "V3 不显示跑者状态：\(row.accessibilityLabel)")
            }
        }
    }

    // MARK: - V4 约好

    func testOrderPageAddsMeetSpotAndBothColoursButSkipsUnknownColours() {
        var order = OrderDetailResponse.preview(status: .pendingAccept)
        order.meetSpotNote = "东门保安亭左侧"
        order.runnerTopColor = .blue
        order.volunteerTopColor = .unknown
        let rows = VolunteerOrderFlowPresentation.meetupRows(order: order)
        XCTAssertEqual(rows.map(\.id), ["meetSpotNote", "runnerTopColor"])
        XCTAssertEqual(rows.map(\.value), ["东门保安亭左侧", "蓝色"])

        let presentation = VolunteerOrderFlowPresentation.make(order: order, distanceText: nil)
        XCTAssertTrue(presentation?.rows.contains { $0.id == "meetSpotNote" } == true, "约好那一屏要显示见面位置")

        XCTAssertTrue(VolunteerOrderFlowPresentation.meetupRows(order: .preview(status: .pendingAccept)).isEmpty, "没走过安排单不摆占位")
    }

    func testMatchedAnnouncementReadsTheArrangementInTheMockupOrder() {
        var order = OrderDetailResponse.preview(
            status: .pendingAccept, startAddress: "朝阳公园东门", plannedStart: "2026-10-16T07:30:00", blindName: "王*"
        )
        order.meetSpotNote = "东门保安亭左侧"
        order.runnerTopColor = .blue
        XCTAssertEqual(
            IntroCallCopy.volunteerMatchedAnnouncement(order: order, now: now, calendar: calendar),
            "约定完成。明天 7 点 30 分，朝阳公园东门，东门保安亭左侧。跑者王上衣为蓝色。"
        )
        order.runnerTopColor = .unknown
        XCTAssertFalse(IntroCallCopy.volunteerMatchedAnnouncement(order: order, now: now, calendar: calendar).contains("上衣"))
    }

    // MARK: - 进度绳的新状态（#434 盲人端接着用）

    func testRopeStagesForThePlanSteps() {
        let awaitingPlan = RopeGeometry.make(for: .introCall(.awaitingPlan))
        XCTAssertEqual(awaitingPlan.planSheet, .pending)
        XCTAssertFalse(awaitingPlan.showsPhone)
        XCTAssertFalse(awaitingPlan.showsSelfCheck)

        let submitted = RopeGeometry.make(for: .introCall(.planSubmitted))
        XCTAssertEqual(submitted.planSheet, .submitted)
        XCTAssertTrue(submitted.showsSelfCheck)
        XCTAssertEqual(submitted.otherStyle, .solid)

        let ended = RopeGeometry.make(for: .introCall(.ended))
        XCTAssertNil(ended.planSheet)
        XCTAssertEqual(ended.otherStyle, .hollow)
        XCTAssertEqual(RopeState.introCall(.ended).accessibilityLabel(), "第 1 步，共 4 步，邀请，本次沟通已结束", "结束了不再念「接下来」")

        // 已有三档不受影响。
        XCTAssertNil(RopeGeometry.make(for: .introCall(.beforeCall)).planSheet)
        XCTAssertTrue(RopeGeometry.make(for: .introCall(.beforeCall)).showsPhone)
        XCTAssertNil(RopeGeometry.make(for: .introCall(.decided)).planSheet)
    }

    // MARK: - View model：倒计时、来电提醒、提交

    /// view model 对 `appState` 是 `weak` —— 三样都由用例方法自己持有，否则当场释放、断言什么都没测。
    private struct Harness {
        let appState: AppState
        let speech: SpeechService
        let viewModel: VolunteerIntroCallViewModel
    }

    private func makeHarness(_ safety: FakeSafetyService) -> Harness {
        let appState = AppState(safety: safety)
        let speech = SpeechService()
        let viewModel = VolunteerIntroCallViewModel()
        viewModel.configure(orderId: 433, appState: appState, speechService: speech)
        return Harness(appState: appState, speech: speech, viewModel: viewModel)
    }

    private func introCall(windowEndsAt: String?, plan: IntroCallPlanView? = nil) -> IntroCallView {
        IntroCallView(
            counterpartName: "王*", counterpartPhone: nil, counterpartPhoneMasked: "138****0001", myDecision: nil,
            windowEndsAt: windowEndsAt, startAddress: "朝阳公园南门",
            plannedStartTime: "2026-10-16T07:00:00", plannedEndTime: "2026-10-16T08:00:00",
            startLatitude: southGate.lat, startLongitude: southGate.lng, plan: plan
        )
    }

    /// 剩 5 分钟、剩 1 分钟各播一次；每 5 秒一轮的轮询不重复播。
    func testCountdownSpeaksEachNodeOnceAcrossRepeatedPolls() async throws {
        let raw = "2026-10-15T20:14:00"
        let endsAt = try XCTUnwrap(raw.backendTimestamp)
        let safety = FakeSafetyService()
        safety.introCallResult = .success(introCall(windowEndsAt: raw))
        let h = makeHarness(safety)
        h.speech.resetSpokenHistoryForTesting()

        for seconds in [240.0, 235, 230] {
            await h.viewModel.refresh(now: endsAt.addingTimeInterval(-seconds))
        }
        XCTAssertEqual(h.speech.spokenHistoryForTesting.filter { $0.hasPrefix("剩余") }, ["剩余 4 分钟。"])

        for seconds in [50.0, 45, 40] {
            await h.viewModel.refresh(now: endsAt.addingTimeInterval(-seconds))
        }
        XCTAssertEqual(h.speech.spokenHistoryForTesting.filter { $0.hasPrefix("剩余") }, ["剩余 4 分钟。", "剩余 1 分钟。"])

        // 远在 5 分钟之外：一句都不播。
        let quiet = makeHarness(safety)
        quiet.speech.resetSpokenHistoryForTesting()
        await quiet.viewModel.refresh(now: endsAt.addingTimeInterval(-600))
        XCTAssertTrue(quiet.speech.spokenHistoryForTesting.filter { $0.hasPrefix("剩余") }.isEmpty)
    }

    /// 「跑者王*正在来电」显示 2 分钟、播一次；同一条重投不重播，过期的补读不显示。
    func testIncomingCallShowsForTwoMinutesAndSpeaksOnce() async {
        let safety = FakeSafetyService()
        safety.introCallResult = .success(introCall(windowEndsAt: nil))
        let h = makeHarness(safety)
        await h.viewModel.refresh(now: now)
        h.speech.resetSpokenHistoryForTesting()

        let sentAt = now.addingTimeInterval(-30)
        h.viewModel.noteIncomingCall(sentAt: sentAt, now: now)
        h.viewModel.noteIncomingCall(sentAt: sentAt, now: now.addingTimeInterval(5))
        XCTAssertEqual(h.speech.spokenHistoryForTesting, ["跑者王正在来电，请留意接听。"])
        XCTAssertTrue(h.viewModel.isShowingIncomingCall(now: now))
        XCTAssertTrue(h.viewModel.isShowingIncomingCall(now: sentAt.addingTimeInterval(119)))
        XCTAssertFalse(h.viewModel.isShowingIncomingCall(now: sentAt.addingTimeInterval(121)))

        // 发出时刻比本机快 10 分钟（时钟偏差）：仍只挂 2 分钟。
        let skewed = makeHarness(safety)
        skewed.viewModel.noteIncomingCall(sentAt: now.addingTimeInterval(600), now: now)
        XCTAssertTrue(skewed.viewModel.isShowingIncomingCall(now: now.addingTimeInterval(119)))
        XCTAssertFalse(skewed.viewModel.isShowingIncomingCall(now: now.addingTimeInterval(121)))

        // 重连补读来的旧提醒（3 分钟前发的）：不显示也不播。
        let stale = makeHarness(safety)
        stale.speech.resetSpokenHistoryForTesting()
        stale.viewModel.noteIncomingCall(sentAt: now.addingTimeInterval(-180), now: now)
        XCTAssertFalse(stale.viewModel.isShowingIncomingCall(now: now))
        XCTAssertTrue(stale.speech.spokenHistoryForTesting.isEmpty)
    }

    /// 提交成功：就地切到 V3（不等下一轮轮询）并播「已提交」；请求体原样交给服务层。
    func testSubmittingThePlanMovesToAwaitingConfirmationAtOnce() async {
        let safety = FakeSafetyService()
        safety.introCallResult = .success(introCall(windowEndsAt: nil))
        safety.submitIntroCallPlanResult = .success(IntroCallPlanView(version: 1, meetSpotNote: "东门保安亭左侧"))
        let h = makeHarness(safety)
        await h.viewModel.refresh(now: now)
        XCTAssertEqual(h.viewModel.step, .awaitingCall)

        let outcome = await h.viewModel.submitPlan(IntroCallPlanRequest(meetSpotNote: "东门保安亭左侧"), distanceFromOriginal: nil)

        XCTAssertEqual(outcome, .submitted)
        XCTAssertEqual(h.viewModel.step, .awaitingRunnerConfirmation)
        XCTAssertEqual(safety.lastIntroCallPlan?.meetSpotNote, "东门保安亭左侧")
        XCTAssertFalse(safety.calls.contains("submitIntroCallDecision(orderId:decision:)"), "陪跑员的「合适」就是提交安排单，不再另发 ACCEPT")
        XCTAssertEqual(h.speech.lastSpokenText, IntroCallCopy.volunteerPlanSubmittedAnnouncement)
    }

    /// 真机崩溃复现（2026-10-16 合并跑测，`EXC_BAD_ACCESS` 在 `SafetyService.submitIntroCallPlan` 拷贝请求体时）：
    /// 表单的 `onSubmit` 是一个存起来的 async 闭包，提交走的是「表单 → 闭包 → view model」这条链，
    /// 而上面那条用例直接调 `submitPlan`，从不经过闭包的类型转换 thunk —— 所以它绿、真机红。
    /// 这条照通话页的写法造一张表单、从 MainActor 上的 Task 调它的 `onSubmit`，与按钮按下去走的是同一条路。
    func testSubmittingThroughTheFormClosureDeliversTheRequestIntact() async {
        let safety = FakeSafetyService()
        safety.introCallResult = .success(introCall(windowEndsAt: nil))
        safety.submitIntroCallPlanResult = .success(IntroCallPlanView(version: 1, meetSpotNote: "东门保安亭左侧"))
        let h = makeHarness(safety)
        await h.viewModel.refresh(now: now)
        let form = VolunteerMeetupPlanFormView(original: original, editing: nil, windowEndsAt: nil) { request, distance in
            await h.viewModel.submitPlan(request, distanceFromOriginal: distance)
        }
        var draft = VolunteerMeetupPlanDraft(original: original)
        draft.meetSpotNote = "东门保安亭左侧"
        draft.place = place("朝阳公园东门", northMeters: 800)
        draft.runnerTopColor = .blue
        let request = draft.request()

        let outcome = await Task { await form.onSubmit(request, draft.distanceFromOriginal) }.value

        XCTAssertEqual(outcome, .submitted)
        XCTAssertEqual(safety.lastIntroCallPlan, request, "请求体经过闭包后要原样到达服务层")
        XCTAssertEqual(h.viewModel.step, .awaitingRunnerConfirmation)
    }

    /// 服务端说有安排单、但这一版读不懂：仍是 V3，不退回 V1 让陪跑员再交一版（每交一版跑者的确认就作废一次）。
    func testUnreadablePlanStillCountsAsSubmitted() async {
        let safety = FakeSafetyService()
        safety.introCallResult = .success(introCall(windowEndsAt: nil, plan: IntroCallPlanView(version: nil)))
        let h = makeHarness(safety)
        await h.viewModel.refresh(now: now)
        XCTAssertEqual(h.viewModel.introCall?.hasUnreadablePlan, true)
        XCTAssertEqual(h.viewModel.step, .awaitingRunnerConfirmation)
    }

    func testSubmitFailureKeepsTheFormAndRoundEndClosesIt() async {
        let safety = FakeSafetyService()
        safety.introCallResult = .success(introCall(windowEndsAt: nil))
        safety.submitIntroCallPlanResult = .failure(
            APIError.serverError(ErrorResponse(code: "INTRO_CALL_PLAN_TOO_FAR_FROM_ORIGINAL", message: "太远"))
        )
        let h = makeHarness(safety)
        await h.viewModel.refresh(now: now)
        let rejected = await h.viewModel.submitPlan(IntroCallPlanRequest(), distanceFromOriginal: 8400)
        XCTAssertEqual(rejected, .failed(VolunteerMeetupPlanSubmitError(slot: .place, message: "距原集合地点 8.4 公里，超出 3 公里调整上限。")))
        XCTAssertEqual(h.viewModel.step, .awaitingCall)
        XCTAssertEqual(h.viewModel.outcome, .active)

        safety.submitIntroCallPlanResult = .failure(
            APIError.serverError(ErrorResponse(code: "INTRO_CALL_NOT_ACTIVE", message: "这一轮通话已经结束了"))
        )
        safety.matchedOrderResult = .failure(APIError.unknown(statusCode: 403))
        let ended = await h.viewModel.submitPlan(IntroCallPlanRequest(), distanceFromOriginal: nil)
        XCTAssertEqual(ended, .roundEnded)
        XCTAssertEqual(h.viewModel.outcome, .closed)
    }

    // MARK: - 来电推送不进横幅（页面自己念）

    func testIncomingCallNotificationSkipsTheBannerOnlyWhileTheCallPageIsOpen() async {
        func notification() -> WSAppNotification {
            WSAppNotification(
                type: WSMessageType.appNotification.rawValue, eventId: Int64.random(in: 1...1_000_000),
                eventType: "INTRO_CALL_INCOMING", title: nil, body: "跑者正在打给你，请留意来电",
                ttsText: nil, priority: "HIGH", timestamp: "2026-10-15T20:00:00"
            )
        }
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .volunteer)
        var received: [Date] = []
        let subscription = coordinator.introCallIncomingPublisher.sink { received.append($0) }
        defer { subscription.cancel() }

        // 两处入口各开过一页，关掉一页后另一页仍在 ⇒ 仍不进横幅。
        coordinator.introCallPageDidAppear()
        coordinator.introCallPageDidAppear()
        coordinator.introCallPageDidDisappear()
        service.simulateIncomingEventForTesting(.notification(notification()))
        await Task.yield()
        XCTAssertEqual(received.count, 1)
        // 信封 timestamp 是无时区的 LocalDateTime：必须按后端时刻解出来，不能落回「收到的时刻」——
        // 否则重连补读来的旧提醒会被当成刚刚打来的。
        XCTAssertEqual(received.first, "2026-10-15T20:00:00".backendTimestamp)
        XCTAssertNil(coordinator.currentNotification, "通话页开着时由页面自己念，横幅再念一遍就是两遍")

        coordinator.introCallPageDidDisappear()
        service.simulateIncomingEventForTesting(.notification(notification()))
        await Task.yield()
        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(coordinator.currentNotification?.displayText, "跑者正在打给你，请留意来电", "不在通话页时照旧走横幅")
    }
}
