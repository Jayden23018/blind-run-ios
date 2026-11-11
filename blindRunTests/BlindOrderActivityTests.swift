import XCTest
@testable import blindRun

/// 盲人端「约跑进度」锁屏卡（#919，稿 `docs/ui/mockups/live-activity-v7-20261111/` B1–B7、B10、B11）。
///
/// 卡在系统进程里渲染，样子只能真机人工看（XCUITest 也读不到锁屏卡）。这里守的是会静默漂移的东西：
/// 订单状态 → 哪一屏、开跑前 30 分钟的边界、8 小时变灰、哪几屏带提醒、读屏念的那一句、单测不起真卡。
@available(iOS 16.2, *)
@MainActor
final class BlindOrderActivityTests: XCTestCase {

    private typealias Controller = BlindOrderActivityController
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - 状态 → 哪一屏

    /// 穷举全部订单状态：后端加状态时编译器不会提醒这里，只有逐个走一遍才挡得住「忘了映射」。
    func testEveryOrderStatusMapsToADecision() {
        let farBefore = start.addingTimeInterval(-2 * 60 * 60)
        for status in RunOrderStatus.allCases {
            let decision = Controller.decision(status: status, plannedStart: start, reviewingPlan: false, now: farBefore)
            switch status {
            case .pendingMatch, .rematching: XCTAssertEqual(decision, .show(.matching), "\(status)")
            case .pendingIntroCall: XCTAssertEqual(decision, .show(.talking), "\(status)")
            case .scheduledConfirmed, .pendingAccept: XCTAssertEqual(decision, .show(.scheduled), "\(status)")
            case .driverEnRoute: XCTAssertEqual(decision, .show(.enRoute), "\(status)")
            case .driverArrived: XCTAssertEqual(decision, .show(.arrived), "\(status)")
            case .inProgress, .completed: XCTAssertEqual(decision, .end, "\(status) 交给跑步卡")
            case .cancelled: XCTAssertEqual(decision, .show(.cancelled), "\(status)")
            case .noVolunteer: XCTAssertEqual(decision, .show(.noVolunteer), "\(status)")
            case .unknown: XCTAssertEqual(decision, .ignore, "\(status)")
            }
        }
    }

    func testPlanWaitingForConfirmationShowsB3() {
        XCTAssertEqual(
            Controller.decision(status: .pendingIntroCall, plannedStart: start, reviewingPlan: true, now: start),
            .show(.confirmPlan)
        )
    }

    /// 开跑前 30 分钟是第二段起卡点：边界两侧各取一秒。改成 29 或 31 分钟都会红。
    func testSecondStageStartsExactlyThirtyMinutesBeforeTheRun() {
        func phase(minutesBefore: Double) -> Controller.Decision {
            Controller.decision(
                status: .scheduledConfirmed,
                plannedStart: start,
                reviewingPlan: false,
                now: start.addingTimeInterval(-minutesBefore * 60)
            )
        }
        XCTAssertEqual(phase(minutesBefore: 30 + 1 / 60), .show(.scheduled), "30 分 1 秒前还不起")
        XCTAssertEqual(phase(minutesBefore: 30), .show(.preRun), "正好 30 分钟起")
        XCTAssertEqual(phase(minutesBefore: 30 - 1 / 60), .show(.preRun))
    }

    func testScheduledWithoutPlannedStartNeverStartsTheSecondStage() {
        XCTAssertEqual(
            Controller.decision(status: .pendingAccept, plannedStart: nil, reviewingPlan: false, now: start),
            .show(.scheduled)
        )
    }

    // MARK: - 起不起卡

    /// 负责人 11-11：「超 8 小时变灰收起，不再起新卡」。每单每段只起一次；已约好 / 取消从不起卡。
    func testEachStageStartsAtMostOnceAndClosingScreensNeverStartACard() {
        let none: (Int) -> Bool = { _ in false }
        let firstDone: (Int) -> Bool = { $0 == 1 }

        XCTAssertTrue(Controller.startsCard(for: .matching, alreadyStarted: none))
        XCTAssertFalse(Controller.startsCard(for: .matching, alreadyStarted: firstDone), "第一段起过就不再起")
        XCTAssertTrue(Controller.startsCard(for: .preRun, alreadyStarted: firstDone), "第二段另起一张")
        XCTAssertFalse(Controller.startsCard(for: .enRoute, alreadyStarted: { _ in true }))
        for phase in [BlindOrderActivityPhase.scheduled, .cancelled, .noVolunteer] {
            XCTAssertFalse(Controller.startsCard(for: phase, alreadyStarted: none), "\(phase) 只推给已有的卡")
        }
    }

    func testFindingScreensGoStaleAfterEightHoursAndOthersNever() {
        XCTAssertEqual(Controller.staleDate(for: .matching, startedAt: start), start.addingTimeInterval(8 * 60 * 60))
        XCTAssertEqual(Controller.staleDate(for: .confirmPlan, startedAt: start), start.addingTimeInterval(8 * 60 * 60))
        XCTAssertNil(Controller.staleDate(for: .preRun, startedAt: start))
        XCTAssertNil(Controller.staleDate(for: .arrived, startedAt: start))
    }

    func testSecondStageOutranksFirstStage() {
        XCTAssertGreaterThan(Controller.relevance(for: .enRoute), Controller.relevance(for: .matching))
    }

    /// 稿「五」：只在找到陪跑员、请确认、出发、已到达四处带提醒（亮屏 + 声音）。
    func testOnlyFourScreensAlert() {
        let alerting = BlindOrderActivityPhase.allCases.filter(\.alertsOnEntry)
        XCTAssertEqual(Set(alerting), [.talking, .confirmPlan, .enRoute, .arrived])
    }

    /// 未知的 phase 原值降级成「匹配中」，不让整条更新解码失败（那等于锁屏卡冻住）。
    func testUnknownPhaseDecodesAsMatching() throws {
        let json = #"{"phase":"SOMETHING_NEW"}"#
        let state = try JSONDecoder().decode(BlindOrderActivityAttributes.ContentState.self, from: Data(json.utf8))
        XCTAssertEqual(state.phase, .matching)
    }

    // MARK: - 首页喂的订单不冲掉订单页的细节

    func testHomeSourceKeepsB3AndDistanceFromTheOrderPage() {
        let deadline = start.addingTimeInterval(540)
        let previous = state(.confirmPlan, deadline: deadline)
        let fromHome = state(.talking)
        let merged = Controller.merge(fromHome, keeping: previous, source: .home)
        XCTAssertEqual(merged.phase, .confirmPlan)
        XCTAssertEqual(merged.confirmDeadline, deadline)

        let enRoute = Controller.merge(state(.enRoute), keeping: state(.enRoute, distance: 300), source: .home)
        XCTAssertEqual(enRoute.distanceMeters, 300)

        let fromPage = Controller.merge(fromHome, keeping: previous, source: .orderPage)
        XCTAssertEqual(fromPage.phase, .talking, "订单页说没有待确认的安排单，就以订单页为准")
    }

    // MARK: - 卡上的字

    func testB1MatchingSaysWhenTheRunIsAndHasNoAvatar() {
        let now = start.addingTimeInterval(-24 * 60 * 60)
        let p = presentation(state(.matching), now: now)
        XCTAssertEqual(p.title, "正在找陪跑员")
        XCTAssertEqual(p.subtitle, "明天 \(BlindOrderActivityCopy.clock(start)) 开跑")
        XCTAssertFalse(p.showsAvatar, "还没有人，不放头像")
        XCTAssertEqual(p.line, .steps(current: 1))
        XCTAssertTrue(p.compactShowsSearchingDot)
    }

    func testB10StaleFindingCardTurnsGrey() {
        let p = presentation(state(.matching), isStale: true)
        XCTAssertEqual(p.title, "还在找陪跑员")
        XCTAssertEqual(p.subtitle, "打开 App 看最新进度")
        XCTAssertEqual(p.background, BlindOrderActivityPalette.stale)
        XCTAssertNil(p.line)
    }

    func testB3ShowsASystemCountdownAndReadsMinutes() {
        let deadline = start.addingTimeInterval(9 * 60)
        let p = presentation(state(.confirmPlan, deadline: deadline), now: start)
        XCTAssertEqual(p.title, "请确认见面安排")
        XCTAssertEqual(p.countdown, .subtitlePrefix(until: deadline, prefix: "还剩 "))
        XCTAssertTrue(p.accessibilityLabel.contains("还剩约 9 分钟"), p.accessibilityLabel)
    }

    func testB4ScheduledNamesThePlace() {
        let p = presentation(state(.scheduled, place: "朝阳公园南门"), now: start.addingTimeInterval(-60 * 60))
        XCTAssertEqual(p.subtitle, "已约好，在朝阳公园南门")
        XCTAssertEqual(p.line, .steps(current: 3))
    }

    func testB6EnRouteWalksTheRunnerTowardsYou() {
        var s = state(.enRoute, place: "南门", distance: 300)
        s.departureDistanceMeters = 1_200
        let p = presentation(s)
        XCTAssertEqual(p.title, "陪跑员正在赶来")
        XCTAssertEqual(p.subtitle, "离你约 300 米")
        XCTAssertEqual(p.line, .distance(progress: 0.75, endLabel: "你 · 南门"))
        XCTAssertFalse(p.accessibilityLabel.contains("·"), "读屏不念点号：\(p.accessibilityLabel)")
    }

    /// 负责人 11-11 定：距离算不出（订单页没开）时写「陪跑员已出发」，小人停在起点。
    func testB6WithoutDistanceDegradesToDeparted() {
        let p = presentation(state(.enRoute, place: "南门"))
        XCTAssertEqual(p.subtitle, "陪跑员已出发")
        XCTAssertEqual(p.line, .distance(progress: 0, endLabel: "你 · 南门"))
    }

    func testB7ArrivedUsesTheLargeTitleAndTheTopColor() {
        var s = state(.arrived, place: "南门")
        s.volunteerTopColor = "蓝色"
        let p = presentation(s)
        XCTAssertEqual(p.title, "陪跑员到了")
        XCTAssertTrue(p.titleIsLarge)
        XCTAssertEqual(p.subtitle, "在南门等你，穿蓝色上衣")
        XCTAssertEqual(p.line, .distance(progress: 1, endLabel: "你 · 南门"))
    }

    func testB11CancelledIsGreyWithoutALine() {
        let p = presentation(state(.cancelled))
        XCTAssertEqual(p.title, "这次约跑已取消")
        XCTAssertEqual(p.subtitle, "打开 App 可以重新约")
        XCTAssertEqual(p.background, BlindOrderActivityPalette.stale)
        XCTAssertNil(p.line)
    }

    /// 卡上不写名字（负责人 2026-11-11）：任何一屏的读屏标签里都不该出现陪跑员姓名。
    /// 名字根本进不了 `ContentState`（没有这个字段）—— 这条用例守的是将来有人把它加回来。
    func testNoScreenSpeaksAName() {
        for phase in BlindOrderActivityPhase.allCases {
            let p = presentation(state(phase, place: "南门"))
            XCTAssertTrue(p.accessibilityLabel.hasPrefix("助盲跑，"), "\(phase)：\(p.accessibilityLabel)")
            XCTAssertFalse(p.compactAccessibilityLabel.isEmpty)
        }
    }

    func testDistanceCopyRoundsToTenMetresAndOneDecimalKilometre() {
        XCTAssertEqual(BlindOrderActivityCopy.distance(296), "300 米")
        XCTAssertEqual(BlindOrderActivityCopy.distance(3), "10 米")
        XCTAssertEqual(BlindOrderActivityCopy.distance(1_240), "1.2 公里")
        XCTAssertEqual(BlindOrderActivityCopy.distance(2_010), "2 公里")
    }

    // MARK: - 单测不起真卡

    /// 🔴 单测绝不能在真机上留下实时活动（2026-09-16 事故，见 `RunLiveActivityTests`）。
    func testUnitTestsNeverStartARealActivity() {
        XCTAssertTrue(Controller.isRunningUnderTests)
        let controller = Controller.shared
        controller.resetEventsForTesting()
        controller.sync(order: .preview(orderId: 919_001, status: .pendingMatch), source: .home)
        XCTAssertTrue(
            controller.eventsForTesting.contains { $0.hasPrefix("skipped:tests") }
                || controller.eventsForTesting.isEmpty,
            "走到了真起卡：\(controller.eventsForTesting)"
        )
        XCTAssertFalse(controller.eventsForTesting.contains { $0.hasPrefix("start:") })
    }

    // MARK: - 帮手

    private func state(
        _ phase: BlindOrderActivityPhase,
        place: String? = nil,
        deadline: Date? = nil,
        distance: Int? = nil
    ) -> BlindOrderActivityAttributes.ContentState {
        BlindOrderActivityAttributes.ContentState(
            phase: phase,
            plannedStart: start,
            confirmDeadline: deadline,
            placeName: place,
            volunteerTopColor: nil,
            distanceMeters: distance,
            departureDistanceMeters: nil
        )
    }

    private func presentation(
        _ state: BlindOrderActivityAttributes.ContentState,
        isStale: Bool = false,
        now: Date? = nil
    ) -> BlindOrderActivityPresentation {
        BlindOrderActivityPresentation(state: state, isStale: isStale, now: now ?? start.addingTimeInterval(-60 * 60))
    }
}
