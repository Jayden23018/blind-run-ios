import XCTest
@testable import blindRun

/// #660：通话磨合到汇合这一段的防误触、提醒与身份核对提示（OpenSpec `safeguard-intro-call-to-meetup`）。
@MainActor
final class IntroCallToMeetupSafeguardTests: XCTestCase {

    // MARK: - 「未接到来电」延后出现（V-9）

    func testUnreachableAppearsOnlyAfterTheDelay() {
        let seen = Date(timeIntervalSince1970: 1_000_000)
        let delay = TimeInterval(IntroCallCopy.volunteerUnreachableDelayMinutes * 60)
        XCTAssertFalse(VolunteerIntroCallUnreachableGate.isAvailable(firstSeenAt: seen, now: seen), "进页第 0 秒就能按")
        XCTAssertFalse(VolunteerIntroCallUnreachableGate.isAvailable(firstSeenAt: seen, now: seen.addingTimeInterval(delay - 1)))
        XCTAssertTrue(VolunteerIntroCallUnreachableGate.isAvailable(firstSeenAt: seen, now: seen.addingTimeInterval(delay)))
    }

    /// 退出再进来不重新计时：否则进出一次又要等 5 分钟。
    func testLeavingAndReenteringKeepsTheFirstSeenTime() {
        VolunteerIntroCallUnreachableGate.resetForTesting()
        defer { VolunteerIntroCallUnreachableGate.resetForTesting() }
        let first = Date(timeIntervalSince1970: 2_000_000)
        XCTAssertEqual(VolunteerIntroCallUnreachableGate.noteSeen(orderId: 7, now: first), first)
        XCTAssertEqual(VolunteerIntroCallUnreachableGate.noteSeen(orderId: 7, now: first.addingTimeInterval(240)), first)
        let other = first.addingTimeInterval(60)
        XCTAssertEqual(VolunteerIntroCallUnreachableGate.noteSeen(orderId: 8, now: other), other, "别的订单各算各的")
    }

    // MARK: - 确认文案中性（B-14 / V-9，AGENTS §5 无声拒绝）

    func testConfirmCopyNeverMentionsRoundsOrTheCounterpartsStance() {
        let copies = [
            IntroCallCopy.blindDeclineConfirmTitle, IntroCallCopy.blindDeclineConfirmMessage,
            IntroCallCopy.volunteerDeclineConfirmTitle, IntroCallCopy.volunteerDeclineConfirmMessage,
            IntroCallCopy.volunteerUnreachableConfirmTitle, IntroCallCopy.volunteerUnreachableConfirmMessage,
            IntroCallCopy.volunteerUnreachablePendingNotice, IntroCallCopy.volunteerSubmitReminder,
        ]
        for copy in copies {
            for banned in ["轮", "第", "机会", "最后", "拒绝", "对方觉得", "对方不", "重新匹配"] {
                XCTAssertFalse(copy.contains(banned), "「\(copy)」出现「\(banned)」：泄露轮次或对方表态")
            }
        }
    }

    // MARK: - 带绳提醒（V-8 / F-29，负责人 2026-11-04）

    func testRopeReminderSkipsArmHoldAndVerbalOnly() {
        for tether in ["ARM_HOLD", "VERBAL_ONLY"] {
            let order = OrderDetailResponse.preview(status: .pendingAccept, tetherPreference: tether)
            XCTAssertNil(GuideRopeReminder.line(for: order, isVolunteer: true), tether)
            XCTAssertNil(GuideRopeReminder.line(for: order, isVolunteer: false), tether)
        }
    }

    /// 没给、`NOT_SPECIFIED`、认不出的新值都照常提醒：多带一根绳没有代价。
    func testRopeReminderShowsForRopeAndUnknownChoices() {
        for tether in ["TETHER_ROPE", nil, "NOT_SPECIFIED", "SOMETHING_NEW"] {
            for status in [RunOrderStatus.scheduledConfirmed, .pendingAccept] {
                let order = OrderDetailResponse.preview(status: status, tetherPreference: tether)
                XCTAssertEqual(GuideRopeReminder.line(for: order, isVolunteer: true), GuideRopeReminder.volunteerLine)
                XCTAssertEqual(GuideRopeReminder.line(for: order, isVolunteer: false), GuideRopeReminder.blindLine)
            }
        }
    }

    func testRopeReminderOnlyOnTheAgreedStep() {
        for status in [RunOrderStatus.pendingIntroCall, .driverEnRoute, .driverArrived, .inProgress, .completed] {
            let order = OrderDetailResponse.preview(status: status, tetherPreference: "TETHER_ROPE")
            XCTAssertNil(GuideRopeReminder.line(for: order, isVolunteer: true), "\(status)")
        }
    }

    func testBlindAgreedSubtitleCarriesTheRopeReminder() throws {
        let rope = OrderDetailResponse.preview(status: .pendingAccept, volunteerName: "张*", tetherPreference: "TETHER_ROPE")
        let arm = OrderDetailResponse.preview(status: .pendingAccept, volunteerName: "张*", tetherPreference: "ARM_HOLD")
        let ropePage = try XCTUnwrap(BlindOrderFlowPresentation.make(order: rope, distanceText: nil, canKeepWaiting: false))
        let armPage = try XCTUnwrap(BlindOrderFlowPresentation.make(order: arm, distanceText: nil, canKeepWaiting: false))
        XCTAssertTrue(ropePage.subtitle.contains(GuideRopeReminder.blindLine), "实际：\(ropePage.subtitle)")
        XCTAssertFalse(armPage.subtitle.contains("引导绳"), "选了搀扶还在提醒带绳：\(armPage.subtitle)")
    }

    func testStartRunCaptionFollowsTheGuidanceMethod() {
        let action = VolunteerOrderFlowPresentation.PrimaryAction.startRun
        XCTAssertEqual(action.caption(awaitingBlindConfirmation: false, tetherPreference: "TETHER_ROPE"), "见面并握好引导绳后再按")
        for tether in ["ARM_HOLD", "VERBAL_ONLY", nil] {
            let caption = action.caption(awaitingBlindConfirmation: false, tetherPreference: tether) ?? ""
            XCTAssertFalse(caption.contains("引导绳"), "\(tether ?? "nil") 时还写死引导绳：\(caption)")
            XCTAssertFalse(caption.isEmpty)
        }
        XCTAssertEqual(
            action.caption(awaitingBlindConfirmation: true, tetherPreference: "ARM_HOLD"),
            VolunteerOrderFlowCopy.startRunAwaitingConfirmation,
            "等对方确认那句要优先"
        )
        XCTAssertEqual(
            VolunteerOrderFlowPresentation.PrimaryAction.endWaiting.caption(awaitingBlindConfirmation: false, tetherPreference: "ARM_HOLD"),
            VolunteerOrderFlowCopy.endWaitingCaption
        )
    }

    func testVolunteerArrivalAnnouncementNoLongerAssumesARope() {
        let text = RunOrderStatus.driverArrived.volunteerAnnouncement
        XCTAssertFalse(text.contains("引导绳"), text)
        XCTAssertTrue(text.contains("先报姓氏"), text)
    }

    // MARK: - 汇合核对身份（B-15 / F-4 / V-14）

    func testBlindArrivalAsksToCheckTheSurnameBeforeStarting() throws {
        XCTAssertTrue(RunOrderStatus.blindRunnerArrivedCopy.contains("按开始前，先核对对方姓氏"))
        XCTAssertTrue(SpeechService.statusAnnouncement(for: .driverArrived).contains("先核对对方姓氏"))
        let order = OrderDetailResponse.preview(status: .driverArrived, volunteerName: "张*", volunteerPhone: "13800000001")
        let page = try XCTUnwrap(BlindOrderFlowPresentation.make(order: order, distanceText: nil, canKeepWaiting: false))
        XCTAssertTrue(page.subtitle.contains("按开始前，先核对对方姓氏"), "实际：\(page.subtitle)")
        XCTAssertTrue(BlindRunCopy.metUpLockedSubtitle(opensAt: "9:45").contains("先核对对方姓氏"))
    }

    func testVolunteerMeetupHeroAlwaysSaysHowToIntroduceYourself() {
        let order = OrderDetailResponse.preview(status: .driverArrived, tetherPreference: "ARM_HOLD")
        let phase = VolunteerOrderPhase.arrived(canEndWait: false)
        let hero = VolunteerOrderHero.make(order: order, phase: phase, now: Date())
            .withPrepNotices(order: order, phase: phase, totalCompleted: 3)
        XCTAssertEqual(hero.lines.last, VolunteerMeetupIdentityCopy.line)
        XCTAssertTrue(hero.accessibilityLabel.contains(VolunteerMeetupIdentityCopy.line))
    }

    func testVolunteerAgreedHeroCarriesTheRopeReminderOnlyWhenNeeded() {
        let phase = VolunteerOrderPhase.agreedEarly
        let rope = OrderDetailResponse.preview(status: .pendingAccept, tetherPreference: "TETHER_ROPE")
        let verbal = OrderDetailResponse.preview(status: .pendingAccept, tetherPreference: "VERBAL_ONLY")
        let ropeHero = VolunteerOrderHero.make(order: rope, phase: phase, now: Date())
            .withPrepNotices(order: rope, phase: phase, totalCompleted: 3)
        let verbalHero = VolunteerOrderHero.make(order: verbal, phase: phase, now: Date())
            .withPrepNotices(order: verbal, phase: phase, totalCompleted: 3)
        XCTAssertTrue(ropeHero.lines.contains(GuideRopeReminder.volunteerLine))
        XCTAssertFalse(verbalHero.lines.contains(GuideRopeReminder.volunteerLine))
    }

    // MARK: - 首单提示（V-35）

    func testFirstRunLabelNeedsAKnownZeroCompletedCount() {
        let order = OrderDetailResponse.preview(status: .pendingAccept)
        let phase = VolunteerOrderPhase.agreedEarly
        let base = VolunteerOrderHero.make(order: order, phase: phase, now: Date())
        XCTAssertEqual(base.withPrepNotices(order: order, phase: phase, totalCompleted: 0).notice, VolunteerFirstRunCopy.label)
        XCTAssertNil(base.withPrepNotices(order: order, phase: phase, totalCompleted: nil).notice, "没拉到摘要不许猜成新人")
        XCTAssertNil(base.withPrepNotices(order: order, phase: phase, totalCompleted: 1).notice)
    }

    func testFirstRunLabelOnlyBeforeTheRun() {
        XCTAssertTrue(VolunteerFirstRunCopy.isFirstRun(totalCompleted: 0, phase: .arrived(canEndWait: false)))
        XCTAssertTrue(VolunteerFirstRunCopy.isFirstRun(totalCompleted: 0, phase: .departed(late: false)))
        XCTAssertFalse(VolunteerFirstRunCopy.isFirstRun(totalCompleted: 0, phase: .completed))
        XCTAssertFalse(VolunteerFirstRunCopy.isFirstRun(totalCompleted: 0, phase: .runnerCancelled))
    }

    /// 快迟到的提醒条优先，首单标签不顶掉它。
    func testLateNoticeWinsOverTheFirstRunLabel() {
        var hero = VolunteerOrderHero(rope: .agreed, eyebrow: "正在赶去")
        hero.notice = "已自动告诉李*你会晚到约 5 分钟"
        let order = OrderDetailResponse.preview(status: .driverEnRoute)
        let result = hero.withPrepNotices(order: order, phase: .departed(late: true), totalCompleted: 0)
        XCTAssertEqual(result.notice, "已自动告诉李*你会晚到约 5 分钟")
    }

    func testFirstRunTipsLiveInTheAutoOpenedHelp() {
        let topic = VolunteerFirstRunHelp.topics.first { $0.id == "firstRun" }
        XCTAssertNotNil(topic, "首单要点没进使用帮助")
        XCTAssertTrue(topic?.body.contains("先报姓氏") == true)
        let flow = VolunteerFirstRunHelp.topics.first { $0.id == "flow" }?.body ?? ""
        XCTAssertFalse(flow.contains("握好引导绳之后"), "帮助页还写死引导绳：\(flow)")
    }

    // MARK: - 手机号去向只说一次（V-17）

    func testPhoneShareNoticeIsRememberedPerAccount() {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let first = VolunteerOnceNotice(kind: .phoneShare, persistence: persistence, userID: 1)
        let second = VolunteerOnceNotice(kind: .phoneShare, persistence: persistence, userID: 2)
        XCTAssertFalse(first.isDone)
        first.markDone()
        XCTAssertTrue(first.isDone)
        XCTAssertFalse(second.isDone, "换一个账号要再说一次")
        let anonymous = VolunteerOnceNotice(kind: .phoneShare, persistence: persistence, userID: nil)
        anonymous.markDone()
        XCTAssertFalse(anonymous.isDone, "拿不到 userId 时按没说过处理")
    }

    func testPhoneShareCopySaysTheNumberGoesToTheRunner() {
        XCTAssertTrue(VolunteerPhoneShareCopy.message.contains("完整手机号"))
        XCTAssertTrue(VolunteerPhoneShareCopy.message.contains("跑者"))
        XCTAssertTrue(VolunteerPhoneShareCopy.message.contains("没有约成"), "要说清只聊不成对方也拿着号码")
    }
}
