import CoreLocation
import SwiftUI
import XCTest
@testable import blindRun

/// 通话后见面安排单的纯逻辑（OpenSpec `add-intro-call-meetup-plan`，#436）。
///
/// 每条用例都挑了**能分出偷懒实现**的输入：回前台喂 `(.inactive → .active)`、
/// 倒计时模拟多次轮询、「未变更」用一张逐字段重填原值的单。
@MainActor
final class IntroCallMeetupPlanTests: XCTestCase {

    // MARK: - 固定场景：原约「明天 7:00–8:00，朝阳公园南门」，现在是今天 20:00（北京时间）

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    private func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private var now: Date { date(day: 15, hour: 20) }

    /// 南门与东门纬度差 0.0072° ≈ 800 米。
    private let southGate = (lat: 39.9300, lng: 116.4700)
    private let eastGate = (lat: 39.9372, lng: 116.4700)

    private var original: IntroCallOriginalArrangement {
        IntroCallOriginalArrangement(
            plannedStartTime: date(day: 16, hour: 7),
            plannedEndTime: date(day: 16, hour: 8),
            startAddress: "朝阳公园南门",
            startLatitude: southGate.lat,
            startLongitude: southGate.lng
        )
    }

    private func plan(
        version: Int = 1,
        start: Date? = nil,
        end: Date? = nil,
        address: String? = nil,
        lat: Double? = nil,
        lng: Double? = nil,
        note: String? = nil,
        volunteerColor: MeetupTopColor? = nil,
        runnerColor: MeetupTopColor? = nil
    ) -> IntroCallMeetupPlan {
        IntroCallMeetupPlan(
            version: version,
            plannedStartTime: start,
            plannedEndTime: end,
            startAddress: address,
            startLatitude: lat,
            startLongitude: lng,
            meetSpotNote: note,
            volunteerTopColor: volunteerColor,
            runnerTopColor: runnerColor
        )
    }

    private func speech(_ plan: IntroCallMeetupPlan) -> IntroCallMeetupPlanSpeech {
        IntroCallMeetupCopy.planSpeech(plan: plan, original: original, volunteerName: "李*", now: now, calendar: calendar)
    }

    // MARK: - 子状态

    func testRunnerStepFollowsPlanAndBackgroundReturn() {
        XCTAssertEqual(IntroCallRunnerStep.resolve(plan: nil, confirmedPlanVersion: nil, hasReturnedFromBackground: false), .awaitingCall)
        XCTAssertEqual(IntroCallRunnerStep.resolve(plan: nil, confirmedPlanVersion: nil, hasReturnedFromBackground: true), .awaitingPlan)
        XCTAssertEqual(IntroCallRunnerStep.resolve(plan: plan(version: 1), confirmedPlanVersion: 1, hasReturnedFromBackground: true), .confirmed)
    }

    /// 杀进程重启后本地「回过前台」标记丢了，但服务端有单 ⇒ 仍是 B3，不退回 B1。
    func testServerPlanWinsOverMissingLocalReturnFlag() {
        XCTAssertEqual(
            IntroCallRunnerStep.resolve(plan: plan(version: 1), confirmedPlanVersion: nil, hasReturnedFromBackground: false),
            .reviewingPlan
        )
    }

    /// 盲人确认过第 1 版，陪跑员又改成第 2 版 ⇒ 之前的确认不算数，回到 B3。
    func testConfirmationOfAnOlderVersionDoesNotCount() {
        XCTAssertEqual(
            IntroCallRunnerStep.resolve(plan: plan(version: 2), confirmedPlanVersion: 1, hasReturnedFromBackground: true),
            .reviewingPlan
        )
    }

    func testVolunteerStepOnlyDependsOnWhetherThePlanExists() {
        XCTAssertEqual(IntroCallVolunteerStep.resolve(plan: nil), .awaitingCall)
        XCTAssertEqual(IntroCallVolunteerStep.resolve(plan: plan(version: 3)), .awaitingRunnerConfirmation)
    }

    // MARK: - 回前台判据

    /// 拨号确认框点了取消：`active → inactive → active`。一次都不许判成「打完电话回来」。
    /// 「只要到 `.active` 就算」的实现在第一步和第三步都会返回 true。
    func testInactiveToActiveIsNotAReturnFromTheCall() {
        var detector = IntroCallForegroundReturnDetector()
        XCTAssertFalse(detector.observe(.active))
        XCTAssertFalse(detector.observe(.inactive))
        XCTAssertFalse(detector.observe(.active))
    }

    /// 真机打完电话回来的顺序是 `background → inactive → active`。
    /// 「只比较相邻两个阶段是不是 `(.background, .active)`」的实现在这里返回 false。
    func testRealCallReturnSequenceCountsExactlyOnce() {
        var detector = IntroCallForegroundReturnDetector()
        let results = [ScenePhase.active, .inactive, .background, .inactive, .active, .inactive, .active]
            .map { detector.observe($0) }
        XCTAssertEqual(results, [false, false, false, false, true, false, false])
    }

    func testBackgroundStraightToActiveCounts() {
        var detector = IntroCallForegroundReturnDetector()
        XCTAssertFalse(detector.observe(.background))
        XCTAssertTrue(detector.observe(.active))
    }

    // MARK: - 倒计时

    /// 从剩 6 分钟到 0，每 5 秒轮询一次：5 分钟、1 分钟各恰好响一次。
    func testCountdownAnnouncesFiveAndOneMinuteExactlyOnceAcrossPolling() {
        let endsAt = now.addingTimeInterval(6 * 60)
        var announcer = IntroCallCountdownAnnouncer()
        var fired: [(node: IntroCallCountdownNode, remaining: TimeInterval)] = []
        for elapsed in stride(from: 0.0, through: 6 * 60, by: 5) {
            let pollTime = now.addingTimeInterval(elapsed)
            if let node = announcer.nodeToAnnounce(windowEndsAt: endsAt, now: pollTime) {
                fired.append((node, endsAt.timeIntervalSince(pollTime)))
            }
        }
        XCTAssertEqual(fired.map(\.node), [.fiveMinutes, .oneMinute])
        XCTAssertEqual(fired.map(\.remaining), [300, 60])
    }

    /// App 挂起过、一下跳到 40 秒：只念 1 分钟那句，不连念两句；之后也不补念 5 分钟。
    func testCountdownSkippingPastFiveMinutesOnlyAnnouncesOneMinute() {
        let endsAt = now.addingTimeInterval(6 * 60)
        var announcer = IntroCallCountdownAnnouncer()
        XCTAssertNil(announcer.nodeToAnnounce(windowEndsAt: endsAt, now: now))
        XCTAssertEqual(announcer.nodeToAnnounce(windowEndsAt: endsAt, now: endsAt.addingTimeInterval(-40)), .oneMinute)
        XCTAssertNil(announcer.nodeToAnnounce(windowEndsAt: endsAt, now: endsAt.addingTimeInterval(-30)))
    }

    /// 窗口已过不播（超时由服务端宣布）；换了新一轮窗口重新计。
    func testCountdownStaysSilentAfterExpiryAndResetsForANewWindow() {
        let firstWindow = now.addingTimeInterval(4 * 60)
        var announcer = IntroCallCountdownAnnouncer()
        XCTAssertEqual(announcer.nodeToAnnounce(windowEndsAt: firstWindow, now: now), .fiveMinutes)
        XCTAssertNil(announcer.nodeToAnnounce(windowEndsAt: firstWindow, now: firstWindow.addingTimeInterval(5)))

        let secondWindow = now.addingTimeInterval(20 * 60)
        XCTAssertEqual(announcer.nodeToAnnounce(windowEndsAt: secondWindow, now: secondWindow.addingTimeInterval(-200)), .fiveMinutes)
    }

    func testRemainingTextKeepsTheLineUnderOneMinute() {
        let endsAt = now.addingTimeInterval(10 * 60)
        XCTAssertEqual(IntroCallMeetupCopy.remainingText(windowEndsAt: endsAt, now: endsAt.addingTimeInterval(-359)), "剩余 5 分钟")
        XCTAssertEqual(IntroCallMeetupCopy.remainingText(windowEndsAt: endsAt, now: endsAt.addingTimeInterval(-119)), "剩余 1 分钟")
        XCTAssertEqual(IntroCallMeetupCopy.remainingText(windowEndsAt: endsAt, now: endsAt.addingTimeInterval(-60)), "剩余 1 分钟")
        XCTAssertEqual(IntroCallMeetupCopy.remainingText(windowEndsAt: endsAt, now: endsAt.addingTimeInterval(-40)), "剩余不到 1 分钟")
        XCTAssertEqual(IntroCallMeetupCopy.remainingText(windowEndsAt: endsAt, now: endsAt.addingTimeInterval(3)), "剩余不到 1 分钟")
    }

    /// 节点在越过阈值后的**第一次轮询**触发，那时剩的是 298 秒、58 秒这种值。
    /// 向下取整的实现会念成「剩余 4 分钟」「剩余 0 分钟 / 不到 1 分钟」。
    func testCountdownAnnouncementNamesTheNodeAtTheFirstPollPastIt() {
        let endsAt = now.addingTimeInterval(10 * 60)
        func say(_ secondsLeft: TimeInterval, reviewing: Bool) -> String {
            IntroCallMeetupCopy.countdownAnnouncement(
                windowEndsAt: endsAt, now: endsAt.addingTimeInterval(-secondsLeft), isReviewingPlan: reviewing
            )
        }
        XCTAssertEqual(say(298, reviewing: true), "剩余 5 分钟，请确认见面安排。")
        XCTAssertEqual(say(298, reviewing: false), "剩余 5 分钟。")
        XCTAssertEqual(say(58, reviewing: false), "剩余 1 分钟。")
        // 剩 3 分钟才进页面：5 分钟节点照样触发，但念实际的 3 分钟。
        XCTAssertEqual(say(180, reviewing: true), "剩余 3 分钟，请确认见面安排。")
    }

    // MARK: - 朗读

    /// 视觉稿 v2 的示例：改到 7:30–8:30、东门，约 800 米。
    func testChangedPlanReadsOldAndNewValuesInFixedOrder() {
        let result = speech(plan(
            start: date(day: 16, hour: 7, minute: 30),
            end: date(day: 16, hour: 8, minute: 30),
            address: "朝阳公园东门",
            lat: eastGate.lat,
            lng: eastGate.lng,
            note: "东门保安亭左侧",
            volunteerColor: .red,
            runnerColor: .blue
        ))
        XCTAssertEqual(result.title, "陪跑员李已提交见面安排，共 2 项变更。")
        XCTAssertEqual(result.items, [
            "开跑时间，已变更：由明天 7 点改为 7 点 30，8 点 30 结束。",
            "集合地点，已变更：由朝阳公园南门改为朝阳公园东门，距原地点约 800 米。",
            "具体见面位置：东门保安亭左侧。",
            "陪跑员上衣为红色。你的上衣记录为蓝色，如有误请致电更正。",
            "见面时由陪跑员主动上前，并告知姓氏。",
        ])
    }

    /// 陪跑员把原值逐字段重填一遍：仍算「未变更」。
    /// 「字段非空就算改了」的实现在这里会念出「已变更」。
    func testRestatingTheOriginalValuesIsNotAChange() {
        let restated = plan(
            start: original.plannedStartTime,
            end: original.plannedEndTime,
            address: "朝阳公园南门",
            lat: southGate.lat,
            lng: southGate.lng
        )
        for candidate in [plan(), restated] {
            let result = speech(candidate)
            XCTAssertEqual(result.title, "陪跑员李已提交见面安排，无变更。")
            XCTAssertEqual(result.items.first, "开跑时间：明天 7 点，8 点结束。")
            XCTAssertEqual(result.items.dropFirst().first, "集合地点：朝阳公园南门。")
            for item in result.items {
                XCTAssertFalse(item.contains("改"), "未变更项不许出现「改」：\(item)")
            }
        }
    }

    /// 只改了时间：地点那一项不带「改」，标题只算 1 项。
    func testOnlyTheChangedItemCarriesOldAndNewValues() {
        let result = speech(plan(start: date(day: 17, hour: 7, minute: 30), end: date(day: 17, hour: 8, minute: 30)))
        XCTAssertEqual(result.title, "陪跑员李已提交见面安排，共 1 项变更。")
        XCTAssertEqual(result.items[0], "开跑时间，已变更：由明天 7 点改为后天 7 点 30，8 点 30 结束。")
        XCTAssertEqual(result.items[1], "集合地点：朝阳公园南门。")
    }

    /// 只改了结束时间：点名结束时间。「开始、结束合在一起比」的实现会念「由明天 7 点改为 7 点」。
    func testEndOnlyChangeNamesTheEndTime() {
        let result = speech(plan(end: date(day: 16, hour: 9)))
        XCTAssertEqual(result.title, "陪跑员李已提交见面安排，共 1 项变更。")
        XCTAssertEqual(result.items[0], "开跑时间，已变更：明天 7 点开始，结束时间由 8 点改为 9 点。")
    }

    /// 同名不同点：坐标挪了 800 米也要念出来 —— 集合点是由可能是威胁来源的一方改的。
    /// 不念「由南门改为南门」，那句听不出改了什么。
    func testSameNameButMovedCoordinatesStillCountsAsAChange() {
        let result = speech(plan(address: "朝阳公园南门", lat: eastGate.lat, lng: eastGate.lng))
        XCTAssertEqual(result.title, "陪跑员李已提交见面安排，共 1 项变更。")
        XCTAssertEqual(result.items[1], "集合地点，已变更：仍为朝阳公园南门，距原地点约 800 米。")
    }

    /// 改了名字但坐标没动、或缺坐标：不念距离。`formattedDistance` 最小报 10 米，
    /// 不拦就会把 0 米说成「约 10 米」。
    func testDistanceIsOnlySpokenWhenItIsReal() {
        let sameSpot = speech(plan(address: "朝阳公园正门", lat: southGate.lat, lng: southGate.lng))
        XCTAssertEqual(sameSpot.items[1], "集合地点，已变更：由朝阳公园南门改为朝阳公园正门。")

        let noCoordinate = speech(plan(address: "朝阳公园东门"))
        XCTAssertEqual(noCoordinate.items[1], "集合地点，已变更：由朝阳公园南门改为朝阳公园东门。")

        let unchanged = speech(plan())
        XCTAssertFalse(unchanged.fullText.contains("距原地点"))
    }

    /// 数字与汉字之间的空格只加在模板拼接处，用户填的「3号门」原样念。
    func testUserTextIsReadVerbatim() {
        let result = speech(plan(note: "3号门左侧"))
        XCTAssertTrue(result.items.contains("具体见面位置：3号门左侧。"))
    }

    func testSpokenClockAndDayWording() {
        XCTAssertEqual(IntroCallMeetupCopy.spokenClock(date(day: 16, hour: 7, minute: 5), calendar: calendar), "7 点 05")
        XCTAssertEqual(IntroCallMeetupCopy.spokenClock(date(day: 16, hour: 19), calendar: calendar), "19 点")
        XCTAssertEqual(IntroCallMeetupCopy.spokenDay(date(day: 15, hour: 23), now: now, calendar: calendar), "今天")
        XCTAssertEqual(IntroCallMeetupCopy.spokenDay(date(day: 18, hour: 7), now: now, calendar: calendar), "10月18日")
    }

    func testUnknownColourIsNeverSpoken() {
        let onlyUnknown = speech(plan(volunteerColor: .unknown, runnerColor: nil))
        XCTAssertFalse(onlyUnknown.fullText.contains("上衣"))
        XCTAssertFalse(onlyUnknown.fullText.contains("UNKNOWN"))

        let mixed = speech(plan(volunteerColor: .unknown, runnerColor: .green))
        XCTAssertTrue(mixed.items.contains("你的上衣记录为绿色，如有误请致电更正。"))
        XCTAssertFalse(mixed.fullText.contains("陪跑员上衣"))
    }

    func testColourDecodingIsLenient() {
        XCTAssertEqual(MeetupTopColor(lenientRawValue: " red "), .red)
        XCTAssertEqual(MeetupTopColor(lenientRawValue: "NEON_GREEN"), .unknown)
        XCTAssertNil(MeetupTopColor.unknown.spokenName)
    }

    func testFullTextRepeatsTitleThenEveryItem() {
        let result = speech(plan(note: "南门保安亭左侧"))
        XCTAssertTrue(result.fullText.hasPrefix(result.title))
        XCTAssertTrue(result.fullText.hasSuffix(IntroCallMeetupCopy.fixedGreetingLine))
        XCTAssertEqual(result.fullText, ([result.title] + result.items).joined())
    }
}
