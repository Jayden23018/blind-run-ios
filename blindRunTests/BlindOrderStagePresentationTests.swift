import XCTest
@testable import blindRun

/// 订单页 v7 ①④ 的内容（#917）：哪几个状态走新版式、底部按钮、「···」菜单、不该出现的句子。
final class BlindOrderStagePresentationTests: XCTestCase, BlindRunTestSupport {

    /// 只有跑步前五个状态走 v7 ①–④；出发起归 #918，终态与未知态各有落点。
    func testOnlyThePreDepartureStatesUseTheStagePage() {
        let expected: [RunOrderStatus: BlindOrderStage?] = [
            .pendingMatch: .matching,
            .rematching: .matching,
            .pendingIntroCall: .introCall,
            .scheduledConfirmed: .booked,
            .pendingAccept: .booked,
            .driverEnRoute: nil,
            .driverArrived: nil,
            .inProgress: nil,
            .completed: nil,
            .cancelled: nil,
            .noVolunteer: nil,
            .unknown: nil,
        ]
        for status in RunOrderStatus.allCases {
            XCTAssertTrue(expected.keys.contains(status), "\(status.rawValue) 没有写进期望表")
            XCTAssertEqual(BlindOrderStage.resolve(status), expected[status] ?? nil, status.rawValue)
        }
    }

    // MARK: - ① 匹配中

    /// PENDING_MATCH 没有「继续等待」（后端每轮超时自己往后推），只有取消。
    func testPendingMatchOnlyOffersCancel() throws {
        let page = try XCTUnwrap(BlindOrderStagePresentation.make(order: makeOrder(orderId: 1, status: .pendingMatch), canKeepWaiting: true))
        XCTAssertEqual(page.bottom, [.cancelMatching])
        XCTAssertEqual(page.menu, [])
        XCTAssertEqual(page.title, BlindOrderStageCopy.matchingTitle)
    }

    /// REMATCHING 还能延长时：「继续等待」在前（实心），「取消匹配」在后。用完次数就只剩取消。
    func testRematchingOffersKeepWaitingOnlyWhileItCanStillExtend() throws {
        let order = makeOrder(orderId: 1, status: .rematching)
        let open = try XCTUnwrap(BlindOrderStagePresentation.make(order: order, canKeepWaiting: true))
        XCTAssertEqual(open.bottom, [.keepWaiting, .cancelMatching])
        let used = try XCTUnwrap(BlindOrderStagePresentation.make(order: order, canKeepWaiting: false))
        XCTAssertEqual(used.bottom, [.cancelMatching])
    }

    /// 「最晚开跑前半小时会有结果」等 backend#949，合之前任何状态都不许出现。
    func testDeadlineLineWaitingForTheBackendNeverAppears() throws {
        for status in [RunOrderStatus.pendingMatch, .rematching, .scheduledConfirmed, .pendingAccept] {
            let page = try XCTUnwrap(BlindOrderStagePresentation.make(order: makeOrder(orderId: 1, status: status), canKeepWaiting: true))
            let texts = [page.eyebrow, page.title, page.place, page.when, page.cardLead, page.cardBody] + page.timeline.details.values.map(Optional.some)
            XCTAssertFalse(texts.compactMap { $0 }.contains { $0.contains("半小时") }, status.rawValue)
        }
    }

    // MARK: - ④ 已约好

    func testBookedCallsTheVolunteerOnlyWithADialableNumber() throws {
        var order = makeOrder(orderId: 1, status: .scheduledConfirmed)
        order.volunteerName = "陈*"
        let page = try XCTUnwrap(BlindOrderStagePresentation.make(order: order, canKeepWaiting: false))
        XCTAssertEqual(page.bottom, [.callVolunteer(title: "打电话给陪跑员")])
    }

    /// 掩码串绝不能拼 `tel:`（`AGENTS.md` §5）：拼不出可拨 URL 时整个按钮不出现。
    func testBookedHidesTheCallButtonForAMaskedNumber() throws {
        let masked = OrderDetailResponse.preview(
            status: .scheduledConfirmed,
            volunteerName: "陈*",
            volunteerPhone: "138****0002"
        )
        let page = try XCTUnwrap(BlindOrderStagePresentation.make(order: masked, canKeepWaiting: false))
        XCTAssertEqual(page.bottom, [])
    }

    /// 「···」里第一项是取消预约（`SCHEDULED_CONFIRMED` 盲人可取消）。
    func testBookedMenuStartsWithCancelBooking() throws {
        let page = try XCTUnwrap(BlindOrderStagePresentation.make(order: makeOrder(orderId: 1, status: .scheduledConfirmed), canKeepWaiting: false))
        XCTAssertEqual(page.menu.first, .cancelBooking)
        XCTAssertEqual(page.eyebrow, BlindOrderStageCopy.bookedEyebrow)
        XCTAssertEqual(page.timeline.position, .current(.awaitDeparture))
    }

    /// 陪跑员那一行：屏幕保留掩码，读屏去星号；上衣颜色与次数只写后端发了的项。
    func testBookedVolunteerLineKeepsTheMaskOnScreenAndDropsItForSpeech() throws {
        var order = makeOrder(orderId: 1, status: .scheduledConfirmed)
        order.volunteerName = "陈*"
        order.volunteerTopColor = .blue
        order.volunteerTotalCompleted = 32
        order.meetSpotNote = "南门保安亭左边"
        let page = try XCTUnwrap(BlindOrderStagePresentation.make(order: order, canKeepWaiting: false))
        XCTAssertEqual(page.volunteer?.line, "陈* · 蓝色上衣 · 陪跑 32 次")
        XCTAssertEqual(page.volunteer?.spoken.contains("*"), false)
        XCTAssertEqual(page.place, "朝阳公园南门 · 南门保安亭左边")
    }

    /// 提前量取 `BlindRunStartReminder.leadTime`，不写死「1 小时」。
    func testDepartureReminderFollowsTheLeadTime() {
        XCTAssertEqual(BlindOrderStageCopy.departureReminder(leadTime: 3600), "开跑前 1 小时会提醒你出门")
        XCTAssertEqual(BlindOrderStageCopy.departureReminder(leadTime: 1800), "开跑前 30 分钟会提醒你出门")
    }
}
