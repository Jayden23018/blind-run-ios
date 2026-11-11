import XCTest
@testable import blindRun

/// 陪跑员实时活动 v4（#920，稿 `docs/ui/mockups/live-activity-v7-20261111/` 第四、五节）：
/// 每一屏的文案与读屏、两段的门槛、token 上传时机。卡片真实长相只能在真机锁屏上看。
/// 整类 `@available(iOS 16.2, *)`：看到 `passed=0` 一律当失败查（整类被跳过了）。
@available(iOS 16.2, *)
@MainActor
final class GuideRunActivityCardTests: XCTestCase {

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
        XCTAssertNil(late.compactCountdownTo, "紧凑态画的要和念的一致：写「该出发了」，不再倒计时")
        XCTAssertEqual(late.compactTrailing, "该出发了")
    }

    /// 出发时刻那一秒的两侧：系统还没把卡标成过期时，也按时刻自己翻。
    func testPreStartTurnsToTimeToLeaveExactlyAtTheLeaveByMoment() {
        let now = Date()
        let start = now.addingTimeInterval(20 * 60)
        XCTAssertEqual(presentation(state(.preStart, leaveBy: now), plannedStart: start, now: now).title, "该出发了")
        XCTAssertNotEqual(
            presentation(state(.preStart, leaveBy: now.addingTimeInterval(1)), plannedStart: start, now: now).title,
            "该出发了"
        )
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

}

// MARK: - 两段的门槛、token 与控制器

@available(iOS 16.2, *)
extension GuideRunActivityCardTests {
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
            let decoded = try JSONDecoder().decode(GuideRunAttributes.ContentState.self, from: JSONEncoder().encode(original))
            XCTAssertEqual(decoded, original)
        }
    }

    // MARK: - 控制器（单测里不起真卡，只看事件）

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
        XCTAssertEqual(controller.eventsForTesting, ["end"], "离开跑还有 1 小时，不起 V4（手上没有卡，只清一次僵尸卡）")

        controller.sync(order: order, now: "2026-09-19T06:45:00".backendTimestamp!)
        XCTAssertEqual(controller.eventsForTesting.last, "skipped:tests", "进了 30 分钟就起 V4")
    }

    /// 没约成（无声拒绝）：立即收卡，不推「已约好」，也不画任何「没约成」的屏。
    func testRoundThatDidNotWorkOutEndsTheCardWithoutABookedScreen() {
        let controller = GuideRunActivityController.shared
        controller.resetEventsForTesting()

        controller.finishFirstSegment(orderID: 907, bookedAs: nil)

        XCTAssertEqual(controller.eventsForTesting, ["finish:907:closed", "end"])
    }

    /// 审查 A2：后端不为第一段推 `end`，首页拿到摘要时对账。只收 V1 / V2，且只在通话已不是这一单时收。
    func testFirstSegmentCardIsOverOnlyOnceTheCallHasMovedOn() {
        func over(_ phase: GuideRunAttributes.Phase?, active: Int64?) -> Bool {
            GuideRunActivityContentBuilder.firstSegmentIsOver(cardOrderID: 7, cardPhase: phase, activeIntroCallOrderID: active)
        }

        XCTAssertFalse(over(.introCall, active: 7), "还在通话里，留着")
        XCTAssertTrue(over(.introCall, active: nil), "通话没了（超时 / 换人 / 成单）")
        XCTAssertTrue(over(.planSubmitted, active: 8), "通话换成了别的单")
        XCTAssertFalse(over(.scheduled, active: nil), "「已约好」是正在锁屏停留的卡，不归对账收")
        XCTAssertFalse(over(.departed, active: nil), "第二段的卡不归对账收")
        XCTAssertFalse(over(nil, active: nil))
    }
}
