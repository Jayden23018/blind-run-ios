import SwiftUI
import XCTest
@testable import blindRun

/// 陪跑员实时活动 V1–V6（#920）+ 跑步卡 v2（决定源 V3）。
///
/// 卡片的真实长相只能在真机锁屏上看；这里守的是**会静默漂移**的三类东西：
/// 1. 后端推送的 `content-state` 能不能被系统解（系统用默认解码器，解不了 = 锁屏卡冻住，没有任何报错）；
/// 2. 订单 → 卡片内容的映射与本地更新口径一致；
/// 3. 跑步卡第 1 行的 5 分钟闸与暂停。
/// 整类 `@available(iOS 16.2, *)`：看到 `passed=0` 一律当失败查（整类被跳过了）。
@available(iOS 16.2, *)
@MainActor
final class GuideRunActivityTests: XCTestCase {

    // MARK: - 取值对撞

    /// widget target 编译不到 `AppColors`，锁屏卡的状态色是**第二份**取值；这条是两份之间唯一的连接。
    /// 没有它，`FlowPalette` 改了值锁屏上不会有任何提示 —— 实际发生过：FE-1 把头卡小字透明度从
    /// 80% / 86% 改成 90% / 94%、汇合琥珀补了暗色档 `#AD5210`，widget 这边一直留着旧值。
    ///
    /// 取暗色档：实时活动在锁屏上永远是深色呈现（同 `RunLiveActivityTests.testPaletteMatchesTheFlowPaletteDarkTones`）。
    func testStatePaletteMatchesTheFlowPaletteDarkTones() {
        XCTAssertEqual(LiveActivityStatePalette.stateDeparted, AppColors.Flow.stateDepartedTone.dark)
        XCTAssertEqual(LiveActivityStatePalette.stateArrived, AppColors.Flow.stateArrivedTone.dark)
        XCTAssertEqual(LiveActivityStatePalette.stateRunning, AppColors.Flow.stateRunningTone.dark)
        XCTAssertEqual(LiveActivityStatePalette.statePaused, AppColors.Flow.statePausedTone.dark)
        XCTAssertEqual(LiveActivityStatePalette.gold, AppColors.Flow.goldTone.dark)
        XCTAssertEqual(LiveActivityStatePalette.onHeroBodyOpacity, AppColors.Flow.onHeroBodyOpacity)
        XCTAssertEqual(LiveActivityStatePalette.onHeroEyebrowOpacity, AppColors.Flow.onHeroEyebrowOpacity)
    }

    // MARK: - 推送载荷解码（后端 `docs/live-activity.md` 的两段样例）

    /// 系统解推送用的就是这个：默认策略，不许自定义（Apple 原文见后端文档）。
    private func decodeLikeTheSystem(_ json: String) throws -> GuideRunAttributes.ContentState {
        try JSONDecoder().decode(GuideRunAttributes.ContentState.self, from: Data(json.utf8))
    }

    func testDecodesTheBackendUpdateSampleWithArriveAtInReferenceDateSeconds() throws {
        let state = try decodeLikeTheSystem("""
        {"phase":"departed","etaMinutes":8,"arriveAt":811465020,"progress":0.68,
         "runnerNearMeetingPoint":true,"distanceBucket":null}
        """)

        XCTAssertEqual(state.phase, .departed)
        XCTAssertEqual(state.etaMinutes, 8)
        XCTAssertEqual(state.progress, 0.68)
        XCTAssertTrue(state.runnerNearMeetingPoint)
        XCTAssertNil(state.distanceBucket)
        // 811465020 是 2001 纪元秒 = 2026-09-19T06:57:00+08:00（后端 #434）。
        // 当 Unix 秒解会落在 1995 年；反过来后端照 Unix 秒发则会落在 2057 年 —— 两种错都会让这条红。
        let expected = ISO8601DateFormatter().date(from: "2026-09-19T06:57:00+08:00")
        XCTAssertEqual(state.arriveAt, expected)
    }

    func testDecodesTheBackendEndSampleWithExplicitNulls() throws {
        let state = try decodeLikeTheSystem("""
        {"phase":"arrived","etaMinutes":null,"arriveAt":null,"progress":0.85,
         "runnerNearMeetingPoint":false,"distanceBucket":null}
        """)

        XCTAssertEqual(state.phase, .arrived)
        XCTAssertNil(state.etaMinutes)
        XCTAssertNil(state.arriveAt)
        XCTAssertEqual(state.progress, 0.85)
    }

    /// 后端 pushy 用 Gson，默认**不写 null** —— 可选字段整键缺省同样要能解。
    func testDecodesWhenOptionalKeysAreOmittedEntirely() throws {
        let state = try decodeLikeTheSystem("""
        {"phase":"arrived","progress":0.85,"runnerNearMeetingPoint":false}
        """)

        XCTAssertEqual(state.phase, .arrived)
        XCTAssertNil(state.etaMinutes)
        XCTAssertNil(state.arriveAt)
        XCTAssertNil(state.distanceBucket)
    }

    /// 后端给 `phase` 加值时不许整条解码失败（那等于锁屏卡从此不再刷新）。
    func testUnknownPhaseFallsBackToDepartedInsteadOfFailingTheWholeUpdate() throws {
        let state = try decodeLikeTheSystem("""
        {"phase":"waiting","progress":0.5,"runnerNearMeetingPoint":false}
        """)
        XCTAssertEqual(state.phase, .departed)
    }

    /// 「已结束」标记走 `phase`：widget 读不到 `activityState`（见 `Phase.ended` 的注释）。
    func testEndedPhaseDecodesAndKeepsTheOtherFieldsOfTheLastState() throws {
        let state = try decodeLikeTheSystem("""
        {"phase":"ended","etaMinutes":8,"progress":0.68,"runnerNearMeetingPoint":true}
        """)
        XCTAssertEqual(state.phase, .ended)
        XCTAssertEqual(state.etaMinutes, 8)
    }

    // MARK: - 订单 → 卡片内容

    func testEnRouteOrderMapsToTheSameShapeTheBackendPushes() {
        var order = OrderDetailResponse.preview(status: .driverEnRoute)
        order.eta = EtaView(
            remainingMinutes: 11,
            arriveAt: "2026-09-19T07:06:00",
            deltaVsStartMinutes: 6,
            late: true,
            progress: 0.4
        )
        order.runnerAtMeetingPoint = nil

        let state = GuideRunActivityContentBuilder.contentState(from: order)

        XCTAssertEqual(state.phase, .late)
        XCTAssertEqual(state.etaMinutes, 11)
        XCTAssertEqual(state.arriveAt, "2026-09-19T07:06:00".backendTimestamp)
        XCTAssertEqual(state.progress, 0.4)
        XCTAssertFalse(state.runnerNearMeetingPoint, "三态字段 nil 按 false，与后端推送同口径")
        XCTAssertNil(state.distanceBucket)
    }

    func testArrivedOrderPinsProgressAndCarriesTheDistanceBucket() {
        var order = OrderDetailResponse.preview(status: .driverArrived)
        order.meet = MeetView(distanceBucket: .within50, farDistanceKm: nil)
        order.runnerAtMeetingPoint = true

        let state = GuideRunActivityContentBuilder.contentState(from: order)

        XCTAssertEqual(state.phase, .arrived)
        XCTAssertEqual(state.progress, 0.85)
        XCTAssertEqual(state.distanceBucket, "WITHIN_50")
        XCTAssertNil(state.etaMinutes)
    }

    func testCardOnlyExistsWhileEnRouteOrArrived() {
        let shown = RunOrderStatus.allCases.filter(GuideRunActivityContentBuilder.showsCard(for:))
        XCTAssertEqual(Set(shown), [.driverEnRoute, .driverArrived])
    }

    /// 决定源 V11：姓氏字段没到时**不拿掩码名顶替**。
    func testAttributesNeverCarryTheMaskedName() {
        let attributes = GuideRunActivityContentBuilder.attributes(
            from: .preview(status: .driverEnRoute, blindName: "李*")
        )
        XCTAssertNil(attributes.runnerSurname)
        XCTAssertEqual(attributes.meetingPointName, "深圳湾公园 3 号入口")
    }

    /// #281：有 `blindSurname` 就带进 attributes（引导绳圆点写姓氏）；空白串当没有。
    func testAttributesCarryTheRunnerSurnameWhenTheBackendSendsIt() {
        var order = OrderDetailResponse.preview(status: .driverEnRoute, blindName: "欧阳*")
        order.blindSurname = "欧阳"
        XCTAssertEqual(GuideRunActivityContentBuilder.attributes(from: order).runnerSurname, "欧阳")

        order.blindSurname = "  "
        XCTAssertNil(GuideRunActivityContentBuilder.attributes(from: order).runnerSurname)
    }

    func testPushTokenIsUploadedAsLowercaseHex() {
        let hex = GuideRunActivityContentBuilder.hexString(Data([0x00, 0x0F, 0xA0, 0xFF]))
        XCTAssertEqual(hex, "000fa0ff")
    }

    // MARK: - 卡上每一块（稿第四节 V1–V6）

    private func presentation(
        _ state: GuideRunAttributes.ContentState,
        plannedStart: Date? = nil,
        surname: String? = nil,
        isStale: Bool = false,
        now: Date = Date()
    ) -> GuideRunActivityPresentation {
        GuideRunActivityPresentation(
            attributes: GuideRunAttributes(
                orderID: 1,
                runnerSurname: surname,
                meetingPointName: "3 号入口",
                plannedStart: plannedStart
            ),
            state: state,
            isStale: isStale,
            now: now
        )
    }

    private func state(
        _ phase: GuideRunAttributes.Phase,
        etaMinutes: Int? = nil,
        arriveAt: Date? = nil,
        runnerNear: Bool = false,
        bucket: String? = nil,
        deadline: Date? = nil,
        leaveBy: Date? = nil,
        travelMinutes: Int? = nil
    ) -> GuideRunAttributes.ContentState {
        .init(phase: phase, etaMinutes: etaMinutes, arriveAt: arriveAt, progress: 0.5,
              runnerNearMeetingPoint: runnerNear, distanceBucket: bucket,
              deadline: deadline, leaveBy: leaveBy, travelMinutes: travelMinutes)
    }

    /// 固定在本地时区的某一刻，免得「今天 / 明早」随跑用例的时刻漂。
    private func local(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testIntroCallCardCountsDownToTheWindowEndAndSitsOnTheSecondStep() {
        let now = Date()
        let deadline = now.addingTimeInterval(19 * 60)
        let view = presentation(state(.introCall, deadline: deadline), now: now)

        XCTAssertEqual(view.title, "给跑者打电话")
        XCTAssertEqual(view.subtitle, "商量见面，还剩 ")
        XCTAssertEqual(view.subtitleCountdownTo, deadline, "倒计时交给系统自走，App 在后台也会动")
        XCTAssertEqual(view.step, 2)
        XCTAssertEqual(view.trailing, .person)
        XCTAssertTrue(view.actions.isEmpty)
        XCTAssertEqual(view.accessibilityLabel, "助盲跑，陪跑，给跑者打电话，商量见面，还剩约 19 分钟，第 2 步，共 5 步，商量")
    }

    /// 过了截止时刻（staleDate）还停在倒计时，会让「还剩 00:00」一直挂在锁屏上。
    func testIntroCallCardStopsCountingDownOnceTheWindowHasPassed() {
        let now = Date()
        let view = presentation(state(.introCall, deadline: now.addingTimeInterval(60)), isStale: true, now: now)

        XCTAssertEqual(view.subtitle, "打开 App 看最新进度")
        XCTAssertNil(view.subtitleCountdownTo)
        XCTAssertNil(view.compactCountdownTo)
    }

    func testPlanSubmittedCardWaitsForTheRunner() {
        let view = presentation(state(.planSubmitted))

        XCTAssertEqual(view.title, "等跑者确认")
        XCTAssertEqual(view.subtitle, "见面安排已发出")
        XCTAssertEqual(view.step, 2)
        XCTAssertEqual(view.compactTrailing, "等确认")
    }

    func testBookedCardNamesTheDayTheTimeAndTheMeetingPoint() {
        let now = local(2026, 11, 10, 10, 24)

        let tomorrowMorning = presentation(state(.scheduled), plannedStart: local(2026, 11, 11, 7, 0), now: now)
        XCTAssertEqual(tomorrowMorning.title, "明早 7:00 开跑")
        XCTAssertEqual(tomorrowMorning.subtitle, "已约好，在3 号入口")
        XCTAssertEqual(tomorrowMorning.step, 3)
        XCTAssertTrue(tomorrowMorning.accessibilityLabel.hasPrefix("助盲跑，陪跑，明早 7 点开跑"))

        XCTAssertEqual(presentation(state(.scheduled), plannedStart: local(2026, 11, 11, 19, 30), now: now).title, "明天 19:30 开跑")
        XCTAssertEqual(presentation(state(.scheduled), plannedStart: local(2026, 11, 10, 18, 0), now: now).title, "今天 18:00 开跑")
        XCTAssertEqual(presentation(state(.scheduled), plannedStart: local(2026, 11, 13, 7, 5), now: now).title, "11月13日 7:05 开跑")
    }

    func testPreStartCardSaysWhenToLeaveAndTurnsGoldOncePastIt() {
        let now = Date()
        let leaveBy = now.addingTimeInterval(10 * 60)
        let start = now.addingTimeInterval(30 * 60)

        let onTime = presentation(state(.preStart, leaveBy: leaveBy, travelMinutes: 18), plannedStart: start, now: now)
        XCTAssertEqual(onTime.title, "\(GuideRunActivityCopy.clock(leaveBy)) 前出发")
        XCTAssertEqual(onTime.subtitle, "路上约 18 分钟")
        XCTAssertFalse(onTime.titleIsWarning)
        XCTAssertEqual(onTime.step, 3)
        XCTAssertEqual(onTime.compactCountdownTo, start)

        let late = presentation(state(.preStart, leaveBy: leaveBy, travelMinutes: 18), plannedStart: start, isStale: true, now: now)
        XCTAssertEqual(late.title, "该出发了")
        XCTAssertTrue(late.titleIsWarning)
    }

    /// 陪跑员没有位置记录时后端不发 `suggestedDepartAt`：退到开跑时刻，不编一个出发时间。
    func testPreStartCardWithoutSuggestedDepartureFallsBackToTheStartTime() {
        let start = local(2026, 11, 11, 7, 0)
        let view = presentation(state(.preStart), plannedStart: start, now: local(2026, 11, 11, 6, 35))

        XCTAssertEqual(view.title, "7:00 开跑")
        XCTAssertEqual(view.subtitle, "记得按时出发")
        XCTAssertFalse(view.titleIsWarning)
    }

    func testDepartedCardOffersOnlyAlmostThereOnTheRightAndDrawsNoLine() {
        let view = presentation(state(.departed, etaMinutes: 8, runnerNear: true))

        XCTAssertEqual(view.title, "8 分钟后到")
        XCTAssertEqual(view.subtitle, "跑者已到3 号入口附近")
        XCTAssertEqual(view.actions, [.almostThere], "「再等我 5 分钟」进 App，不上卡（DECISION 第 9 条）")
        XCTAssertNil(view.step)
        XCTAssertEqual(view.compactTrailing, "8 分钟")
    }

    func testLateCardTurnsTheTitleGoldAndSaysHowLate() {
        let arriveAt = Date(timeIntervalSinceReferenceDate: 811_465_020)
        let view = presentation(
            state(.late, etaMinutes: 11, arriveAt: arriveAt, runnerNear: true),
            plannedStart: arriveAt.addingTimeInterval(-6 * 60)
        )

        XCTAssertEqual(view.title, "约 11 分钟后到")
        XCTAssertTrue(view.titleIsWarning)
        XCTAssertEqual(view.subtitle, "晚到约 6 分钟", "快迟到时副标题换成晚到多久（稿 V5 注）")
        XCTAssertEqual(view.actions, [.almostThere])
    }

    func testDepartedCardWithoutRunnerNearbyFallsBackToTheArrivalTime() {
        let arriveAt = Date(timeIntervalSinceReferenceDate: 811_465_020)
        let view = presentation(state(.departed, etaMinutes: 8, arriveAt: arriveAt))

        XCTAssertEqual(view.subtitle, "预计 \(GuideRunActivityCopy.clock(arriveAt)) 到")
        XCTAssertTrue(view.accessibilityLabel.contains("预计 \(GuideRunActivityCopy.spokenClock(arriveAt))到"))
    }

    func testZeroMinutesSaysArrivingNowNotZeroMinutes() {
        let view = presentation(state(.departed, etaMinutes: 0))
        XCTAssertEqual(view.title, "马上到")
        XCTAssertEqual(view.compactTrailing, "马上到")
    }

    func testArrivedCardEnlargesTheTitleAndOnlyOffersRinging() {
        let view = presentation(state(.arrived, runnerNear: true, bucket: "WITHIN_10"))

        XCTAssertEqual(view.title, "已到3 号入口")
        XCTAssertTrue(view.titleIsLarge)
        XCTAssertEqual(view.subtitle, "跑者就在 10 米内")
        XCTAssertEqual(view.actions, [.ringRunner])
        XCTAssertEqual(GuideRunActivityAction.ringRunner.title, "让他手机响")
        XCTAssertNil(view.step)
        XCTAssertEqual(view.compactTrailing, "到了")
        XCTAssertTrue(view.compactIsPositive)
    }

    func testUnknownDistanceBucketShowsNoSubtitle() {
        XCTAssertNil(presentation(state(.arrived, bucket: "SOMETHING_NEW")).subtitle)
    }

    /// #281：`end` 推送之后锁屏还要留 5 分钟，不能停在「8 分钟后到」且按钮还能按。
    func testEndedCardShowsNoStaleEtaNoButtonAndNoLine() {
        let view = presentation(state(.ended, etaMinutes: 8, arriveAt: Date(), runnerNear: true, bucket: "WITHIN_10"))

        XCTAssertEqual(view.title, "引导已结束")
        XCTAssertNil(view.subtitle)
        XCTAssertEqual(view.trailing, .none)
        XCTAssertTrue(view.actions.isEmpty)
        XCTAssertNil(view.step)
        XCTAssertEqual(view.background, GuideRunCardPalette.ended)
        XCTAssertEqual(view.compactTrailing, "已结束")
        XCTAssertEqual(view.accessibilityLabel, "助盲跑，陪跑，引导已结束")
    }

    /// DECISION 第 7 条：卡上不写名字。后端给了姓氏也不许出现在任何一屏的任何一块。
    func testNoPhaseEverPutsTheRunnerSurnameOnTheCard() {
        let now = Date()
        let phases: [GuideRunAttributes.Phase] = [.introCall, .planSubmitted, .scheduled, .preStart, .departed, .late, .arrived, .ended]
        for phase in phases {
            let view = presentation(
                state(phase, etaMinutes: 8, arriveAt: now, runnerNear: true, bucket: "WITHIN_10",
                      deadline: now.addingTimeInterval(600), leaveBy: now.addingTimeInterval(600), travelMinutes: 18),
                plannedStart: now.addingTimeInterval(1_800), surname: "欧阳", now: now
            )
            for text in [view.title, view.subtitle ?? "", view.accessibilityLabel, view.compactAccessibilityLabel, view.compactTrailing] {
                XCTAssertFalse(text.contains("欧阳"), "\(phase): \(text)")
            }
            XCTAssertNotEqual(view.background, LiveActivityStatePalette.stateArrived, "v4 不再按状态换底色")
        }
    }

    // MARK: - 两段的门槛与 token

    /// 30 分钟门槛两侧各取一点：门槛被改成 20 或 40 分钟都会红。
    func testPreStartWindowOpensThirtyMinutesBeforeTheStart() {
        let start = local(2026, 11, 11, 7, 0)
        func opens(_ status: RunOrderStatus, secondsBefore: TimeInterval) -> Bool {
            GuideRunActivityContentBuilder.isInPreStartWindow(
                status: status, plannedStart: start, now: start.addingTimeInterval(-secondsBefore)
            )
        }

        XCTAssertFalse(opens(.scheduledConfirmed, secondsBefore: 30 * 60 + 1))
        XCTAssertTrue(opens(.scheduledConfirmed, secondsBefore: 30 * 60 - 1))
        XCTAssertTrue(opens(.pendingAccept, secondsBefore: 60), "临期确认过的单同样在等出发")
        XCTAssertTrue(opens(.scheduledConfirmed, secondsBefore: -300), "过了开跑时刻还没出发，卡照样在（转「该出发了」）")
        XCTAssertFalse(opens(.inProgress, secondsBefore: 60))
        XCTAssertFalse(GuideRunActivityContentBuilder.isInPreStartWindow(status: .scheduledConfirmed, plannedStart: nil, now: start))
    }

    func testScheduledOrderBecomesThePreStartCardInsideTheWindowOnly() {
        var order = OrderDetailResponse.preview(status: .scheduledConfirmed, plannedStart: "2026-09-19T07:00:00")
        order.suggestedDepartAt = "2026-09-19T06:40:00"
        order.travelMinutes = 18

        let inside = GuideRunActivityContentBuilder.secondSegmentContent(
            from: order, now: "2026-09-19T06:35:00".backendTimestamp!
        )
        XCTAssertEqual(inside?.phase, .preStart)
        XCTAssertEqual(inside?.leaveBy, "2026-09-19T06:40:00".backendTimestamp)
        XCTAssertEqual(inside?.travelMinutes, 18)
        XCTAssertEqual(inside.flatMap(GuideRunActivityContentBuilder.staleDate(for:)), inside?.leaveBy)

        XCTAssertNil(GuideRunActivityContentBuilder.secondSegmentContent(
            from: order, now: "2026-09-19T06:20:00".backendTimestamp!
        ))
    }

    func testIntroCallStepMapsToTheFirstTwoScreens() {
        let deadline = Date().addingTimeInterval(600)
        let calling = GuideRunActivityContentBuilder.introCallState(step: .awaitingCall, windowEndsAt: deadline)
        XCTAssertEqual(calling.phase, .introCall)
        XCTAssertEqual(GuideRunActivityContentBuilder.staleDate(for: calling), deadline)

        let submitted = GuideRunActivityContentBuilder.introCallState(step: .awaitingRunnerConfirmation, windowEndsAt: deadline)
        XCTAssertEqual(submitted.phase, .planSubmitted)
        XCTAssertNil(submitted.deadline, "交了安排单后卡上不再倒计时")
    }

    /// 后端 `/api/devices/live-activity-token` 在出发 / 到达以外答 409 —— V4 就起的卡不许早传。
    func testOnlyDepartedLateAndArrivedPhasesUploadThePushToken() {
        let all: [GuideRunAttributes.Phase] = [.introCall, .planSubmitted, .scheduled, .preStart, .ended, .departed, .late, .arrived]
        XCTAssertEqual(Set(all.filter(\.acceptsPushToken)), [.departed, .late, .arrived])
        XCTAssertEqual(Set(all.filter(\.isFirstSegment)), [.introCall, .planSubmitted, .scheduled])
    }

    /// 本地四个新值能被系统解码器原样解回（App 被杀后系统按 JSON 存着这张卡）。
    func testLocalOnlyPhasesRoundTripThroughTheDefaultCoder() throws {
        for phase in [GuideRunAttributes.Phase.introCall, .planSubmitted, .scheduled, .preStart] {
            let original = state(phase, deadline: Date(timeIntervalSinceReferenceDate: 811_465_020), travelMinutes: 18)
            let decoded = try decodeLikeTheSystem(String(decoding: try JSONEncoder().encode(original), as: UTF8.self))
            XCTAssertEqual(decoded, original)
        }
    }

    // MARK: - 单测里不起真卡

    func testUnitTestsNeverStartARealGuideActivity() {
        XCTAssertTrue(GuideRunActivityController.isRunningUnderTests)

        let controller = GuideRunActivityController.shared
        controller.resetEventsForTesting()
        controller.sync(order: .preview(orderId: 902, status: .driverEnRoute))

        XCTAssertEqual(controller.eventsForTesting.last, "skipped:tests")
        XCTAssertFalse(controller.eventsForTesting.contains { $0.hasPrefix("update") })
    }

    /// 出发 / 汇合后被重派时订单页把 `order` 置 nil —— 卡必须跟着结束，不能停在「正在赶去」。
    func testCardEndsWhenTheOrderIsClearedAfterRematching() {
        let viewModel = VolunteerInServiceViewModel()
        viewModel.order = .preview(orderId: 903, status: .driverEnRoute)
        let controller = GuideRunActivityController.shared
        controller.resetEventsForTesting()

        viewModel.order = nil

        XCTAssertEqual(controller.eventsForTesting, ["end"])
    }

    func testCardEndsWhenTheOrderLeavesTheTwoStates() {
        let viewModel = VolunteerInServiceViewModel()
        viewModel.order = .preview(orderId: 904, status: .driverArrived)
        let controller = GuideRunActivityController.shared
        controller.resetEventsForTesting()

        viewModel.order = .preview(orderId: 904, status: .inProgress)

        XCTAssertEqual(controller.eventsForTesting, ["end"])
    }

    /// 响应派单（稿第五节「第一段 · 陪跑员」）：有意向起 V1，直接接下推 V3 收卡，拒绝什么都不做。
    func testDispatchResponseDrivesTheFirstSegment() {
        let controller = GuideRunActivityController.shared
        let attributes = GuideRunActivityContentBuilder.attributes(
            orderID: 905, startAddress: "南门", plannedStart: "2026-09-19T07:00:00"
        )

        controller.resetEventsForTesting()
        controller.noteDispatchResponse(.interested, attributes: attributes)
        XCTAssertEqual(controller.eventsForTesting.last, "skipped:tests")

        controller.resetEventsForTesting()
        controller.noteDispatchResponse(.accept, attributes: attributes)
        XCTAssertEqual(controller.eventsForTesting.first, "finish:905:booked")

        controller.resetEventsForTesting()
        controller.noteDispatchResponse(.decline, attributes: attributes)
        XCTAssertTrue(controller.eventsForTesting.isEmpty)
    }

    func testScheduledOrderOutsideTheWindowStartsNoCard() {
        let order = OrderDetailResponse.preview(orderId: 906, status: .scheduledConfirmed, plannedStart: "2026-09-19T07:00:00")
        let controller = GuideRunActivityController.shared
        controller.resetEventsForTesting()

        controller.sync(order: order, now: "2026-09-19T06:00:00".backendTimestamp!)
        XCTAssertFalse(controller.eventsForTesting.contains("skipped:tests"), "离开跑还有 1 小时，不起 V4")

        controller.sync(order: order, now: "2026-09-19T06:45:00".backendTimestamp!)
        XCTAssertEqual(controller.eventsForTesting.last, "skipped:tests", "进了 30 分钟就起 V4")
    }

    // MARK: - 跑步卡 v2（陪跑员端）

    private let stats = TrackStats(distanceMeters: 2_400, durationSeconds: 1_112, avgPaceSecPerKm: 463)

    /// 5 分钟闸两侧各取一点：阈值被悄悄改成 10 分钟或 1 分钟都会红。
    func testRhythmSignalDisappearsFromTheHeadlineAfterFiveMinutes() {
        let now = Date()
        func headline(signalAgo seconds: TimeInterval) -> String {
            let state = RunLiveActivityContentBuilder.contentState(
                from: stats, partnerName: "李",
                rhythmSignal: "OK", rhythmSignalAt: now.addingTimeInterval(-seconds), now: now
            )
            return RunLiveActivityCopy.volunteerHeadline(
                surname: state.partnerName, rhythmSignal: state.rhythmSignal, isPaused: state.isPaused == true
            )
        }

        XCTAssertEqual(headline(signalAgo: 4 * 60 + 50), "陪跑中 · 李：刚刚好")
        XCTAssertEqual(headline(signalAgo: 5 * 60 + 10), "陪跑中")
    }

    func testHeadlineFallsBackToRunnerWithoutSurnameAndSaysPausedWhenPaused() {
        XCTAssertEqual(
            RunLiveActivityCopy.volunteerHeadline(surname: nil, rhythmSignal: "SLOWER", isPaused: false),
            "陪跑中 · 跑者：稍慢一点"
        )
        XCTAssertEqual(
            RunLiveActivityCopy.volunteerHeadline(surname: "李", rhythmSignal: "FASTER", isPaused: true),
            "已暂停"
        )
        XCTAssertEqual(
            RunLiveActivityCopy.volunteerHeadline(surname: "李", rhythmSignal: "UNKNOWN_NEW", isPaused: false),
            "陪跑中",
            "不认识的信号不显示，不崩"
        )
    }

    func testTargetDistanceDrivesTheSuffixAndProgress() {
        let state = RunLiveActivityContentBuilder.contentState(
            from: stats, partnerName: nil, targetDistanceMeters: 5_000
        )
        XCTAssertEqual(state.targetDistanceText, "5.00")
        XCTAssertEqual(state.progress ?? -1, 0.48, accuracy: 0.0001)
        XCTAssertEqual(RunLiveActivityCopy.targetSuffix(state.targetDistanceText), "/ 5.00 公里")

        let noTarget = RunLiveActivityContentBuilder.contentState(from: stats, partnerName: nil)
        XCTAssertNil(noTarget.progress, "没有目标就不画进度条")
        XCTAssertEqual(RunLiveActivityCopy.targetSuffix(noTarget.targetDistanceText), "公里")
    }

    func testProgressIsCappedAtFullWhenTheRunnerOverruns() {
        let state = RunLiveActivityContentBuilder.contentState(
            from: TrackStats(distanceMeters: 5_320, durationSeconds: 2_000, avgPaceSecPerKm: 380),
            partnerName: nil, targetDistanceMeters: 5_000
        )
        XCTAssertEqual(state.progress, 1)
    }

    /// 旧版本起的跑步卡被新版本认回时，系统拿旧 JSON 解新结构 —— v2 新增字段缺省必须能解。
    func testRunCardStateFromBeforeV2StillDecodes() throws {
        let legacy = """
        {"distanceText":"2.40","durationText":"18:32","paceText":"7'43\\"",
         "spokenDistance":"2.40 公里","spokenDuration":"18 分 32 秒","spokenPace":"7 分 43 秒每公里"}
        """
        let state = try JSONDecoder().decode(RunLiveActivityAttributes.ContentState.self, from: Data(legacy.utf8))
        XCTAssertNil(state.targetDistanceText)
        XCTAssertNil(state.isPaused)
    }
}

// MARK: - 对比度

@available(iOS 16.2, *)
final class GuideRunActivityContrastTests: XCTestCase {

    /// 副标题（白 64%，稿 `--sub`）在深蓝卡底与已结束灰底上都要过正文 4.5:1。
    func testSubtitleOnTheGuideCardClearsBodyTextContrast() {
        let opacity = GuideRunCardPalette.subtitleOpacity
        for background in [GuideRunCardPalette.navy, GuideRunCardPalette.ended] {
            let ratio = Self.contrast(Self.whiteBlended(opacity, over: background), background)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, String(format: "#%06X 上 %.2f:1", background, ratio))
        }
        // 反向验证公式真的会拒：白 30% 在深蓝上必须不过线。
        XCTAssertLessThan(
            Self.contrast(Self.whiteBlended(0.30, over: GuideRunCardPalette.navy), GuideRunCardPalette.navy),
            4.5
        )
    }

    /// 金色标题（快迟到 / 该出发了）在深蓝上要过正文 4.5:1（22pt 粗体只要 3:1，这里按更严的取）。
    func testGoldTitleClearsContrastOnNavy() {
        XCTAssertGreaterThanOrEqual(Self.contrast(GuideRunCardPalette.gold, GuideRunCardPalette.navy), 4.5)
    }

    /// 跑步卡小标题照交付包用 80%，在跑步青绿与暂停灰上都够。
    func testRunCardEyebrowClearsBodyTextContrast() {
        let opacity = LiveActivityStatePalette.onHeroEyebrowOpacity
        for background in [LiveActivityStatePalette.stateRunning, LiveActivityStatePalette.statePaused] {
            XCTAssertGreaterThanOrEqual(Self.contrast(Self.whiteBlended(opacity, over: background), background), 4.5)
        }
    }

    private static func channels(_ rgb: UInt32) -> [Double] {
        [Double((rgb >> 16) & 0xFF), Double((rgb >> 8) & 0xFF), Double(rgb & 0xFF)]
    }

    private static func whiteBlended(_ alpha: Double, over background: UInt32) -> UInt32 {
        let mixed: [UInt32] = channels(background).map { channel in
            let value: Double = 255 * alpha + channel * (1 - alpha)
            return UInt32(value.rounded())
        }
        return (mixed[0] << 16) | (mixed[1] << 8) | mixed[2]
    }

    private static func luminance(_ rgb: UInt32) -> Double {
        let linear: [Double] = channels(rgb).map { raw in
            let c: Double = raw / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let red: Double = 0.2126 * linear[0]
        let green: Double = 0.7152 * linear[1]
        let blue: Double = 0.0722 * linear[2]
        return red + green + blue
    }

    private static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let la = luminance(a)
        let lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}

// MARK: - 锁屏卡高度

/// 锁屏实时活动卡片高度上限 160pt（交付包 04「锁屏卡片高度须 ≤160pt」，同为系统截断线）。
///
/// 实时活动在系统进程里渲染，XCUITest 读不到它的尺寸 —— 这里在真机上按锁屏卡的实际宽度
/// 把同一个 SwiftUI 视图排一次版，量它想要的高度。**量的是内容高度，不是系统画出来的高度**：
/// 超了系统会裁，裁掉的通常是最后一行（按钮）。
///
/// 为了能在这里排版，`GuideRunActivityWidget.swift` 与 `RunLiveActivityWidget.swift` 两个视图文件
/// **同时编进了 app target**（`project.pbxproj`）—— 这是有意的，删掉那两条编译项这里会编不过。
@available(iOS 17.0, *)
@MainActor
final class LiveActivityCardHeightTests: XCTestCase {
    /// 2026-09-26 iPhone 16 Pro（402pt 宽）通知中心里锁屏卡片那一格的宽度（SpringBoard 无障碍树 `ListCell`）。
    static let lockScreenCardWidth: CGFloat = 374
    static let maximumHeight: CGFloat = 160

    private func height(_ view: some View) -> CGFloat {
        UIHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: Self.lockScreenCardWidth, height: .greatestFiniteMagnitude))
            .height
    }

    private let attributes = GuideRunAttributes(
        orderID: 1, runnerSurname: "李", meetingPointName: "深圳湾公园 3 号入口", plannedStart: Date()
    )

    private func guideHeight(_ state: GuideRunAttributes.ContentState, label: String) -> CGFloat {
        let measured = height(GuideRunLockScreenView(
            attributes: attributes,
            presentation: GuideRunActivityPresentation(attributes: attributes, state: state)
        ))
        XCTContext.runActivity(named: "[card-height] guide \(label) = \(measured)") { _ in }
        return measured
    }

    /// 带进度线的最高一种：V1 副标题带倒计时 + 右侧人像 + 底部五步线。
    func testIntroCallCardFitsTheLockScreen() {
        let state = GuideRunAttributes.ContentState(
            phase: .introCall, etaMinutes: nil, arriveAt: nil, progress: 0.1,
            runnerNearMeetingPoint: false, distanceBucket: nil, deadline: Date().addingTimeInterval(19 * 60)
        )
        XCTAssertLessThanOrEqual(guideHeight(state, label: "V1"), Self.maximumHeight)
    }

    func testPreStartCardFitsTheLockScreen() {
        let state = GuideRunAttributes.ContentState(
            phase: .preStart, etaMinutes: nil, arriveAt: nil, progress: 0.1,
            runnerNearMeetingPoint: false, distanceBucket: nil,
            leaveBy: Date().addingTimeInterval(600), travelMinutes: 18
        )
        XCTAssertLessThanOrEqual(guideHeight(state, label: "V4"), Self.maximumHeight)
    }

    func testLateDepartureCardFitsTheLockScreen() {
        let state = GuideRunAttributes.ContentState(
            phase: .late, etaMinutes: 11, arriveAt: Date().addingTimeInterval(660), progress: 0.4,
            runnerNearMeetingPoint: true, distanceBucket: nil
        )
        XCTAssertLessThanOrEqual(guideHeight(state, label: "V5 late"), Self.maximumHeight)
    }

    func testArrivedCardFitsTheLockScreen() {
        let state = GuideRunAttributes.ContentState(
            phase: .arrived, etaMinutes: nil, arriveAt: nil, progress: 0.85,
            runnerNearMeetingPoint: true, distanceBucket: "WITHIN_10"
        )
        XCTAssertLessThanOrEqual(guideHeight(state, label: "V6"), Self.maximumHeight)
    }

    func testVolunteerRunCardFitsTheLockScreen() {
        let state = RunLiveActivityContentBuilder.contentState(
            from: TrackStats(distanceMeters: 12_400, durationSeconds: 5_112, avgPaceSecPerKm: 463),
            partnerName: "李", targetDistanceMeters: 15_000,
            rhythmSignal: "FASTER", rhythmSignalAt: Date()
        )
        let measured = height(VolunteerRunCardView(state: state))
        XCTContext.runActivity(named: "[card-height] run v2 = \(measured)") { _ in }
        XCTAssertLessThanOrEqual(measured, Self.maximumHeight)
    }
}
