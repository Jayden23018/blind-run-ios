import SwiftUI
import XCTest
@testable import blindRun

/// 订单页 v7 ① 匹配中的等待与「找到了」那一刻（#926，稿 `docs/ui/mockups/blind-matching-wait-20261111/`）。
///
/// 动画本身只有真机看得见；这里钉的是两件不用开真机也能判对错的事：
/// 屏上「已等多久」怎么写，以及**什么时候该放**那一秒的过渡。
final class BlindMatchingWaitTests: XCTestCase, BlindRunTestSupport {

    // MARK: - 已等多久

    /// 一小时内写分钟；过了一小时写「X 小时 Y 分钟」（稿 B 帧「已等 2 小时 15 分钟」），整小时不带「0 分钟」。
    func testWaitedTextSwitchesToHoursAndMinutesPastOneHour() {
        XCTAssertEqual(BlindOrderStageCopy.matchingWaited(minutes: 3), "已等 3 分钟")
        XCTAssertEqual(BlindOrderStageCopy.matchingWaited(minutes: 59), "已等 59 分钟")
        XCTAssertEqual(BlindOrderStageCopy.matchingWaited(minutes: 60), "已等 1 小时")
        XCTAssertEqual(BlindOrderStageCopy.matchingWaited(minutes: 135), "已等 2 小时 15 分钟")
    }

    /// ① 的当前步小字按 `now` 算；同一刻旧的播报口径（「已等待 2 小时」）不变 —— 屏与播报共用一个分钟数，写法各自的。
    func testMatchingDetailUsesMinutesOnScreenWhileSpeechKeepsHours() throws {
        let order = makeOrder(orderId: 1, status: .pendingMatch)
        let placed = try XCTUnwrap(order.createdAt?.backendTimestamp)
        let now = placed.addingTimeInterval(135 * 60)

        let page = try XCTUnwrap(BlindOrderStagePresentation.make(order: order, canKeepWaiting: false, now: now))

        XCTAssertEqual(page.timeline.details[.matchVolunteer], "已等 2 小时 15 分钟")
        XCTAssertEqual(order.blindRunnerWaitedText(now: now), "已等待 2 小时")
    }

    /// 不到 1 分钟、满 24 小时都不写（沿用 `blindRunnerWaitedText` 的上下限）。
    func testMatchingDetailIsHiddenUnderOneMinuteAndFromOneDay() throws {
        let order = makeOrder(orderId: 1, status: .rematching)
        let placed = try XCTUnwrap(order.createdAt?.backendTimestamp)

        for seconds in [59, 24 * 3600] {
            let page = try XCTUnwrap(BlindOrderStagePresentation.make(
                order: order, canKeepWaiting: false, now: placed.addingTimeInterval(TimeInterval(seconds))
            ))
            XCTAssertNil(page.timeline.details[.matchVolunteer], "\(seconds) 秒")
        }
        let lastMinute = try XCTUnwrap(BlindOrderStagePresentation.make(
            order: order, canKeepWaiting: false, now: placed.addingTimeInterval(TimeInterval(24 * 3600 - 60))
        ))
        XCTAssertEqual(lastMinute.timeline.details[.matchVolunteer], "已等 23 小时 59 分钟")
    }

    // MARK: - 呼吸圆点

    /// 只有 ① 呼吸；④ 保持 #923 的静态外圈。
    func testOnlyTheMatchingStageBreathes() throws {
        for status in [RunOrderStatus.pendingMatch, .rematching] {
            let page = try XCTUnwrap(BlindOrderStagePresentation.make(order: makeOrder(orderId: 1, status: status), canKeepWaiting: true))
            XCTAssertEqual(page.timeline.currentDot, .breathing, status.rawValue)
        }
        for status in [RunOrderStatus.scheduledConfirmed, .pendingAccept] {
            let page = try XCTUnwrap(BlindOrderStagePresentation.make(order: makeOrder(orderId: 1, status: status), canKeepWaiting: true))
            XCTAssertEqual(page.timeline.currentDot, .still, status.rawValue)
        }
    }

    /// 找到那一刻的旧 ①：当前点打勾、小字「刚刚找到」，其余不动。④ 调它原样返回。
    func testMarkingMatchFoundOnlyChangesTheCurrentDotAndDetail() throws {
        let matching = try XCTUnwrap(BlindOrderStagePresentation.make(order: makeOrder(orderId: 1, status: .pendingMatch), canKeepWaiting: true))
        let found = matching.markingMatchFound()

        XCTAssertEqual(found.timeline.currentDot, .justFound)
        XCTAssertEqual(found.timeline.details[.matchVolunteer], "刚刚找到")
        XCTAssertEqual(found.timeline.position, matching.timeline.position)
        XCTAssertEqual(found.title, matching.title)
        XCTAssertEqual(found.bottom, matching.bottom)

        let booked = try XCTUnwrap(BlindOrderStagePresentation.make(order: makeOrder(orderId: 1, status: .scheduledConfirmed), canKeepWaiting: true))
        XCTAssertEqual(booked.markingMatchFound(), booked)
    }

    // MARK: - 何时放过渡

    /// 从匹配两态变到 ②（通话）或 ④（已约好，含 PENDING_ACCEPT）才放。
    func testTransitionPlaysFromMatchingIntoIntroCallOrBooked() {
        for from in [RunOrderStatus.pendingMatch, .rematching] {
            for to in [RunOrderStatus.pendingIntroCall, .scheduledConfirmed, .pendingAccept] {
                XCTAssertTrue(
                    BlindMatchFoundTransition.shouldPlay(from: from, to: to, watchedContinuously: true),
                    "\(from.rawValue) → \(to.rawValue)"
                )
            }
        }
    }

    /// 点通知 / 冷启动进来（没有上一态）、或中途进过后台：直接显示定格屏（稿第 5 条）。
    func testTransitionDoesNotPlayWhenTheWaitWasNotWatched() {
        XCTAssertFalse(BlindMatchFoundTransition.shouldPlay(from: nil, to: .pendingIntroCall, watchedContinuously: true))
        XCTAssertFalse(BlindMatchFoundTransition.shouldPlay(from: .pendingMatch, to: .pendingIntroCall, watchedContinuously: false))
    }

    /// 别的转移一律不放：取消、没找到、匹配两态互转、同态刷新，以及**不是从匹配出发**的 ② → ④。
    func testTransitionDoesNotPlayForOtherChanges() {
        let pairs: [(RunOrderStatus, RunOrderStatus)] = [
            (.pendingMatch, .cancelled),
            (.pendingMatch, .noVolunteer),
            (.pendingMatch, .rematching),
            (.rematching, .pendingMatch),
            (.pendingMatch, .pendingMatch),
            (.pendingMatch, .unknown),
            (.pendingIntroCall, .scheduledConfirmed),
            (.pendingIntroCall, .pendingMatch),
            (.scheduledConfirmed, .driverEnRoute),
        ]
        for (from, to) in pairs {
            XCTAssertFalse(
                BlindMatchFoundTransition.shouldPlay(from: from, to: to, watchedContinuously: true),
                "\(from.rawValue) → \(to.rawValue)"
            )
        }
    }

    // MARK: - view model 接线

    /// `apply` 换状态的同一刻置上过渡，并记下换之前那一单（旧 ① 照它画）。
    @MainActor
    func testApplySetsTheTransitionTogetherWithTheNewOrder() throws {
        let viewModel = BlindOrderStatusViewModel()
        viewModel.apply(makeOrder(orderId: 1, status: .pendingMatch), speakChanges: false)
        XCTAssertNil(viewModel.matchFound, "第一次拿到订单没有上一态，不放")

        viewModel.apply(makeOrder(orderId: 1, status: .pendingIntroCall), speakChanges: false)

        let transition = try XCTUnwrap(viewModel.matchFound)
        XCTAssertEqual(transition.previousOrder.status, .pendingMatch)
        XCTAssertFalse(transition.revealed)

        viewModel.revealMatchFound(transition.id)
        XCTAssertEqual(viewModel.matchFound?.revealed, true)
        viewModel.finishMatchFound(transition.id)
        XCTAssertNil(viewModel.matchFound)
    }

    /// 等待期间进过后台：回来后状态变了也不放。
    @MainActor
    func testApplySkipsTheTransitionAfterTheAppWentToBackground() {
        let viewModel = BlindOrderStatusViewModel()
        viewModel.apply(makeOrder(orderId: 1, status: .pendingMatch), speakChanges: false)
        viewModel.observeScenePhase(.background)
        viewModel.observeScenePhase(.active)

        viewModel.apply(makeOrder(orderId: 1, status: .pendingIntroCall), speakChanges: false)

        XCTAssertNil(viewModel.matchFound)
    }
}
