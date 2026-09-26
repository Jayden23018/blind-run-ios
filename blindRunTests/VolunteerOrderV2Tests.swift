import CoreLocation
import XCTest
@testable import blindRun

/// 陪跑员订单页 v2 的纯判定（`VolunteerOrderV2.swift`）。
///
/// 时刻类用例一律取**边界前后各 1 秒**：「到点就换按钮」写成 `>` 还是 `>=`、
/// 拿本地时钟还是后端时刻，只有贴着边界的取值才分得出来。
final class VolunteerOrderV2Tests: XCTestCase {
    private let base = Date()

    /// 后端本地时间串（无时区），以及它解析回来的那一刻。用例的 `now` 都围着这一刻取。
    private func backendTime(minutesFromBase minutes: Double) -> (string: String, date: Date) {
        let string = OrderDetailResponse.previewLocalTime(minutesFromNow: minutes, now: base)
        return (string, string.backendTimestamp!)
    }

    // MARK: - 解锁时刻

    func testAgreedPhaseSwitchesExactlyAtPrimaryActionUnlockAt() {
        let unlock = backendTime(minutesFromBase: 30)
        var order = OrderDetailResponse.preview(status: .pendingAccept, plannedStart: backendTime(minutesFromBase: 90).string)
        order.suggestedDepartAt = backendTime(minutesFromBase: 60).string
        order.primaryActionUnlockAt = unlock.string

        let before = unlock.date.addingTimeInterval(-1)
        let after = unlock.date.addingTimeInterval(1)
        XCTAssertEqual(VolunteerOrderPhase.resolve(order: order, now: before), .agreedEarly)
        XCTAssertEqual(VolunteerOrderPhase.resolve(order: order, now: after), .agreedSoon)

        // 主按钮跟着换：解锁前是白色「我已经出发了」，解锁后是黄色「我出发了」—— 发的是同一个动作。
        XCTAssertEqual(VolunteerOrderFlowPresentation.make(order: order, distanceText: nil, now: before)?.primaryAction, .alreadyDeparted)
        XCTAssertEqual(VolunteerOrderFlowPresentation.make(order: order, distanceText: nil, now: after)?.primaryAction, .enRoute)
    }

    /// 后端没给解锁时刻（陪跑员从没上报过位置）⇒ 一直是「我已经出发了」，**不自己算**。
    func testMissingUnlockTimeStaysOnTheSecondaryButton() {
        let order = OrderDetailResponse.preview(status: .pendingAccept, plannedStart: backendTime(minutesFromBase: 5).string)
        XCTAssertEqual(VolunteerOrderPhase.resolve(order: order, now: base), .agreedEarly)
    }

    /// 跨天预约先答「你还去吗」—— 与「我出发了」不是一回事（`AGENTS.md` §5）。
    func testScheduledConfirmedStillAsksWhetherYouAreGoing() {
        let order = OrderDetailResponse.preview(status: .scheduledConfirmed)
        XCTAssertEqual(VolunteerOrderPhase.resolve(order: order, now: base), .confirmStillGoing)
        XCTAssertEqual(VolunteerOrderFlowPresentation.make(order: order, distanceText: nil, now: base)?.primaryAction, .confirmDeparture)
    }

    // MARK: - 结束等待

    func testEndWaitingUnlocksExactlyAtEarliestEndWaitAt() {
        let earliest = backendTime(minutesFromBase: 10)
        var order = OrderDetailResponse.preview(status: .driverArrived, blindPhone: "13800001234")
        order.earliestEndWaitAt = earliest.string

        let before = earliest.date.addingTimeInterval(-1)
        let after = earliest.date.addingTimeInterval(1)
        XCTAssertEqual(VolunteerOrderPhase.resolve(order: order, now: before), .arrived(canEndWait: false))
        XCTAssertEqual(VolunteerOrderPhase.resolve(order: order, now: after), .arrived(canEndWait: true))
        XCTAssertEqual(VolunteerOrderFlowPresentation.make(order: order, distanceText: nil, now: before)?.primaryAction, .startRun)
        XCTAssertEqual(VolunteerOrderFlowPresentation.make(order: order, distanceText: nil, now: after)?.primaryAction, .endWaiting)
    }

    /// 后端没给 `earliestEndWaitAt` ⇒ 永远不出「结束等待」。不拿到达时间自己加 15 分钟。
    func testMissingEarliestEndWaitNeverOffersEndWaiting() {
        let order = OrderDetailResponse.preview(status: .driverArrived)
        let muchLater = base.addingTimeInterval(24 * 3600)
        XCTAssertEqual(VolunteerOrderPhase.resolve(order: order, now: muchLater), .arrived(canEndWait: false))
    }

    // MARK: - 出发中的 ETA 文案

    private func departedHero(delta: Int, late: Bool) -> VolunteerOrderHero {
        var order = OrderDetailResponse.preview(status: .driverEnRoute, plannedStart: backendTime(minutesFromBase: 10).string)
        order.eta = EtaView(
            remainingMinutes: 8,
            arriveAt: backendTime(minutesFromBase: 8).string,
            deltaVsStartMinutes: delta,
            late: late,
            progress: 0.5
        )
        let phase = VolunteerOrderPhase.resolve(order: order, now: base)!
        return .make(order: order, phase: phase, now: base)
    }

    func testDepartedLineFollowsDeltaVsStart() {
        let early = departedHero(delta: -3, late: false)
        XCTAssertTrue(early.lines.first?.contains("比约定早 3 分钟") == true, "\(early.lines)")
        XCTAssertFalse(early.isGold)

        let onTime = departedHero(delta: 0, late: false)
        XCTAssertTrue(onTime.lines.first?.contains("刚好赶上") == true, "\(onTime.lines)")
        XCTAssertNil(onTime.notice)

        // 后端 `late` = 晚于开跑 > 3 分钟，delta 4 时它给 true。
        let late = departedHero(delta: 4, late: true)
        XCTAssertTrue(late.lines.first?.contains("比约定晚约 4 分钟") == true, "\(late.lines)")
        XCTAssertTrue(late.isGold)
        XCTAssertEqual(late.notice, "已自动告诉李*你会晚到约 4 分钟")
    }

    /// 快迟到样式**只认 `eta.late`**：delta 4 而后端没说 late，就不变金色、不出提醒条。
    func testLateStyleComesOnlyFromTheBackendFlag() {
        let hero = departedHero(delta: 4, late: false)
        XCTAssertFalse(hero.isGold)
        XCTAssertNil(hero.notice)
    }

    // MARK: - 在场胶囊

    func testPresencePillOnlyWhenBackendSaysTrue() {
        func presence(_ value: Bool?) -> String? {
            var order = OrderDetailResponse.preview(status: .driverEnRoute)
            order.eta = EtaView(remainingMinutes: 8, arriveAt: nil, deltaVsStartMinutes: 0, late: false, progress: 0.5)
            order.runnerAtMeetingPoint = value
            return VolunteerOrderHero.make(order: order, phase: .departed(late: false), now: base).presence
        }
        XCTAssertNil(presence(nil), "null = 不知道（盲人没报位置）⇒ 胶囊不出现")
        XCTAssertNil(presence(false))
        XCTAssertEqual(presence(true), "李*已到集合点附近")
    }

    // MARK: - 约好：没有时刻时不编

    /// 四个时刻字段同进同出，陪跑员从没上报过位置时全是 null。主角退回开跑时刻，**不出现「出发」**。
    func testNoDepartureTimeIsInventedWhenAllFourFieldsAreNull() {
        let start = backendTime(minutesFromBase: 22 * 60)
        let order = OrderDetailResponse.preview(status: .pendingAccept, plannedStart: start.string)
        XCTAssertNil(order.suggestedDepartAt)
        XCTAssertNil(order.departReminderAt)
        XCTAssertNil(order.primaryActionUnlockAt)
        XCTAssertNil(order.travelMinutes)

        let hero = VolunteerOrderHero.make(order: order, phase: .agreedEarly, now: base)
        XCTAssertEqual(hero.number, VolunteerOrderTimeCopy.clock(start.date))
        XCTAssertEqual(hero.unit, "开跑")
        XCTAssertFalse(hero.accessibilityLabel.contains("出发"), hero.accessibilityLabel)
        XCTAssertFalse(hero.accessibilityLabel.contains("提醒你"), hero.accessibilityLabel)
        XCTAssertTrue(hero.lines.contains { $0.contains("李*") }, "屏幕上保留掩码")
        XCTAssertFalse(hero.accessibilityLabel.contains("*"), "读屏不念星号：\(hero.accessibilityLabel)")
    }

    // MARK: - 完成页

    /// N **直接取** `completedTogetherCount`（本单完成时已计入），不 +1。
    func testCompletedCountIsTakenAsIs() {
        func headline(_ count: Int?) -> String? {
            var order = OrderDetailResponse.preview(status: .completed)
            order.completedTogetherCount = count
            return VolunteerOrderHero.make(order: order, phase: .completed, now: base).headline
        }
        XCTAssertEqual(headline(1), "你和李*第一次一起跑")
        XCTAssertEqual(headline(4), "你和李*第 4 次一起跑")
        XCTAssertEqual(headline(nil), "你和李*跑完了", "没下发就不编数字")
    }

    // MARK: - 汇合方位

    func testFarAndUnknownBucketsNeverMentionADirection() {
        for bucket in [DistanceBucket.far, .unknown] {
            var order = OrderDetailResponse.preview(status: .driverArrived)
            order.meet = MeetView(distanceBucket: bucket, farDistanceKm: bucket == .far ? 1.8 : nil)
            let hero = VolunteerOrderHero.make(order: order, phase: .arrived(canEndWait: false), now: base, direction: "右前方")
            XCTAssertFalse(hero.accessibilityLabel.contains("右前方"), "\(bucket): \(hero.accessibilityLabel)")
            XCTAssertFalse(MeetBucketCopy.showsDirection(for: bucket))
            XCTAssertNil(
                MeetDirection.make(
                    device: CLLocationCoordinate2D(latitude: 22.5, longitude: 113.9),
                    runner: LocatedCoordinate(coordinate: CLLocationCoordinate2D(latitude: 22.501, longitude: 113.9), system: .gcj02Backend),
                    runnerAccuracyMeters: 5,
                    heading: 0,
                    bucket: bucket,
                    previous: nil
                ),
                "\(bucket) 不画扇形"
            )
        }
    }

    /// 本机 WGS-84 要先转 GCJ-02。跑者放在「本机转换后的位置」正北 50 米：
    /// 不转的话两套坐标在深圳差出约 500 米，方位会整个偏掉。
    func testDirectionConvertsTheDeviceToGCJBeforeTakingTheBearing() {
        let device = CLLocationCoordinate2D(latitude: 22.5, longitude: 113.9)
        let deviceGCJ = BackendCoordinateNormalizer.normalize(LocatedCoordinate(coordinate: device, system: .wgs84Device))!.coordinate
        let runner = LocatedCoordinate(
            coordinate: CLLocationCoordinate2D(latitude: deviceGCJ.latitude + 0.00045, longitude: deviceGCJ.longitude),
            system: .gcj02Backend
        )
        func direction(heading: Double) -> MeetDirection? {
            MeetDirection.make(device: device, runner: runner, runnerAccuracyMeters: 5, heading: heading, bucket: .within50, previous: nil)
        }
        XCTAssertEqual(direction(heading: 0)?.sector, .front)
        XCTAssertEqual(direction(heading: 90)?.sector, .left, "面朝东，正北的人在左边")
        XCTAssertEqual(direction(heading: 0)?.sectorWidth, DirectionDialGeometry.minimumSector)
        XCTAssertNil(MeetDirection.make(device: device, runner: runner, runnerAccuracyMeters: 5, heading: nil, bucket: .within50, previous: nil))
    }

    // MARK: - 求助弹窗文案

    /// 陪跑员这里不列紧急联系人，「尚未设置唯一的主紧急联系人」那句对他不成立。
    func testVolunteerBeforeRunDialogDoesNotAppendTheContactHint() {
        XCTAssertFalse(EmergencyCallContext.volunteerBeforeRun.appendsNoContactHint)
        XCTAssertTrue(EmergencyCallContext.homeIdle.appendsNoContactHint, "跑者首页那句提示不能跟着丢")
        XCTAssertTrue(EmergencyCallContext.volunteerBeforeRun.dialogMessage.contains("App 不会代你发送求助"))
        // 完成页与跑者取消页也用这一句，「还没开始跑步」在那两态不成立。
        XCTAssertFalse(EmergencyCallContext.volunteerBeforeRun.dialogMessage.contains("还没开始"))
    }
}
