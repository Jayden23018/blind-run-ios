import XCTest
@testable import blindRun

/// 等待态状态卡上的那个数字：「已等待 12 分钟」。
///
/// 它是「状态驱动单动作」改版补上的最后一格 —— 状态卡恒定给**一个**数字，
/// 有志愿者时是距离、跑起来时是约定结束时间，而还在等人的两态此前是空的
/// （`docs/research/blind-ui-visual-benchmark-20260808.md` §3.2 的「一个数字」列）。
///
/// 这些用例钉三件事：**状态集**（只有还在等人的两态给）、**锚点**（下单时刻，不是别的）、
/// **上限**（不到一分钟不说、超过一天不说）。第三件是这里最容易被后来人「优化」掉的：
/// 看起来像多余的边界判断，实际上挡的是「已等待 10080 分钟」这种既吓人又没用的播报。
final class BlindOrderStatusWaitedDurationTests: XCTestCase {

    /// 下单时刻用的固定基准。用定值而不是 `Date()`：这一组断言全是时间差，
    /// 拿当前时间当锚点会让用例在跨分钟的那一瞬间随机红。
    private static let placedAt = "2026-08-19T09:00:00"

    // MARK: - 状态集

    /// 只有还在等一个志愿者的两态给这个数字。
    ///
    /// 有志愿者之后这一格换成距离、跑起来之后换成约定结束时间 —— 三者状态集互不相交，
    /// 卡上任何时刻只有一个数。这条同时钉住「不许在 `IN_PROGRESS` 也念一个秒表」：
    /// 那一态的数字位已经被结束时间占了，两个数会一起念出来。
    func testOnlyTheTwoWaitingStatesShowHowLongTheRunnerHasWaited() {
        let waiting: Set<RunOrderStatus> = [.pendingMatch, .rematching]

        for status in RunOrderStatus.allCases {
            let order = Self.makeOrder(status: status, createdAt: Self.placedAt)
            let text = order.blindRunnerWaitedText(now: Self.date(minutesAfterPlacement: 12))

            if waiting.contains(status) {
                XCTAssertEqual(
                    text,
                    "已等待 12 分钟",
                    "状态 \(status.rawValue) 还在等志愿者，必须让人听到自己等了多久"
                )
            } else {
                XCTAssertNil(text, "状态 \(status.rawValue) 不该再给一个还在走的秒表")
            }
        }
    }

    // MARK: - 锚点

    /// 锚点是 `createdAt`（下单时刻），不是预约开始时间、也不是接单时间。
    ///
    /// 造一个三者明显对不上的订单：9:00 下单、11:00 才约跑、10:00 有人接过又取消了
    /// （`REMATCHING` 就是这么来的）。9:30 时正确答案是「已等待 30 分钟」。
    func testWaitedDurationIsAnchoredOnOrderCreationNotOnTheAppointmentOrAcceptance() {
        let order = OrderDetailResponse(
            orderId: 7101,
            status: .rematching,
            startAddress: "朝阳公园南门",
            startLatitude: 39.9342,
            startLongitude: 116.4740,
            endAddress: nil,
            endLatitude: nil,
            endLongitude: nil,
            plannedStart: "2026-08-19T11:00:00",
            plannedEnd: "2026-08-19T12:00:00",
            blindName: nil,
            blindPhone: nil,
            volunteerPhone: nil,
            acceptedAt: "2026-08-19T10:00:00",
            createdAt: Self.placedAt,
            expectedDurationMinutes: 60,
            pacePreference: nil,
            routePreference: nil,
            routeNotes: nil,
            hasGuideDogThisRun: nil,
            specialNotes: nil,
            visionLevel: nil,
            tetherPreference: nil,
            chatPreference: nil
        )

        XCTAssertEqual(
            order.blindRunnerWaitedText(now: Self.date(minutesAfterPlacement: 30)),
            "已等待 30 分钟"
        )
    }

    /// 没有 `createdAt` 就不显示这一格，**不拿另一个时间戳顶上**。
    /// 顶上去的那个数没有任何一处能核对，而它长得和真的一模一样。
    func testMissingCreatedAtHidesTheNumberInsteadOfSubstitutingAnotherTimestamp() {
        let order = Self.makeOrder(status: .pendingMatch, createdAt: nil)
        XCTAssertNil(order.blindRunnerWaitedText(now: Self.date(minutesAfterPlacement: 42)))
    }

    /// 后端默认发的是不带时区偏移的 `LocalDateTime`（`2026-08-19T09:00:00`），
    /// 带偏移的 ISO-8601 也要能解 —— 两种形状走同一条 `backendTimestamp`。
    func testBothBackendTimestampShapesParse() throws {
        let local = Self.makeOrder(status: .pendingMatch, createdAt: "2026-08-19T09:00:00")
        XCTAssertNotNil(local.blindRunnerWaitedText(now: Self.date(minutesAfterPlacement: 5)))

        let iso = try XCTUnwrap("2026-08-19T09:00:00Z".backendTimestamp)
        XCTAssertEqual(
            Self.makeOrder(status: .pendingMatch, createdAt: "2026-08-19T09:00:00Z")
                .blindRunnerWaitedText(now: iso.addingTimeInterval(7 * 60)),
            "已等待 7 分钟"
        )
    }

    // MARK: - 上限

    /// 不到一分钟不说。「已等待 0 分钟」是噪音 —— 刚下完单的人知道自己刚下完单。
    func testNothingIsAnnouncedDuringTheFirstMinute() {
        let order = Self.makeOrder(status: .pendingMatch, createdAt: Self.placedAt)
        XCTAssertNil(order.blindRunnerWaitedText(now: Self.date(secondsAfterPlacement: 0)))
        XCTAssertNil(order.blindRunnerWaitedText(now: Self.date(secondsAfterPlacement: 59)))
        XCTAssertEqual(
            order.blindRunnerWaitedText(now: Self.date(secondsAfterPlacement: 60)),
            "已等待 1 分钟"
        )
    }

    /// 设备时钟比服务端快时差值是负的，同样不说 —— 「已等待 -3 分钟」比没有更糟。
    func testASkewedDeviceClockDoesNotProduceANegativeWait() {
        let order = Self.makeOrder(status: .pendingMatch, createdAt: Self.placedAt)
        XCTAssertNil(order.blindRunnerWaitedText(now: Self.date(minutesAfterPlacement: -3)))
    }

    /// 一小时以上按小时说，分钟不再念：到这个量级那几分钟不影响任何决定，
    /// 只会拉长播报。
    func testPastAnHourTheNumberSwitchesToWholeHours() {
        let order = Self.makeOrder(status: .pendingMatch, createdAt: Self.placedAt)
        XCTAssertEqual(order.blindRunnerWaitedText(now: Self.date(minutesAfterPlacement: 59)), "已等待 59 分钟")
        XCTAssertEqual(order.blindRunnerWaitedText(now: Self.date(minutesAfterPlacement: 60)), "已等待 1 小时")
        XCTAssertEqual(order.blindRunnerWaitedText(now: Self.date(minutesAfterPlacement: 185)), "已等待 3 小时")
    }

    /// 超过 24 小时整格消失。
    ///
    /// 提前一周下的单在派单期确实等了一周（后端创建后几秒就开始派单），但
    /// 「已等待 168 小时」既吓人又不能让盲人做出任何动作。上限到了就不说，
    /// **不去猜一个「有效等待时间」**——猜出来的数没有任何一处能核对。
    func testAWaitLongerThanADayIsNotAnnouncedAtAll() {
        let order = Self.makeOrder(status: .pendingMatch, createdAt: Self.placedAt)
        XCTAssertEqual(
            order.blindRunnerWaitedText(now: Self.date(minutesAfterPlacement: 24 * 60 - 1)),
            "已等待 23 小时"
        )
        XCTAssertNil(order.blindRunnerWaitedText(now: Self.date(minutesAfterPlacement: 24 * 60)))
        XCTAssertNil(order.blindRunnerWaitedText(now: Self.date(minutesAfterPlacement: 7 * 24 * 60)))
    }

    // MARK: - 不许被当成倒计时

    /// 这句话里**不许出现「还」「剩」「即将」**这类指向未来的字。
    ///
    /// 放弃时刻是 `plannedStart` 减去一个后端配置，且会被「继续等待」往后推
    /// （后端 `DispatchService.dispatchDeadline`）—— 那个配置客户端读不到，
    /// 任何窗口长度都是假信息。与 `KeepWaitingCopy` 的进行时口径同一条红线。
    func testTheWaitedTextNeverImpliesHowMuchLongerTheOrderWillSurvive() throws {
        let order = Self.makeOrder(status: .pendingMatch, createdAt: Self.placedAt)
        let text = try XCTUnwrap(order.blindRunnerWaitedText(now: Self.date(minutesAfterPlacement: 20)))

        for forbidden in ["还剩", "还有", "即将", "倒计时", "超时", "将于"] {
            XCTAssertFalse(
                text.contains(forbidden),
                "「已等待」这一格不许暗示订单还能活多久，命中了 \(forbidden)"
            )
        }
    }

    // MARK: - Helpers

    private static func date(minutesAfterPlacement minutes: Int) -> Date {
        date(secondsAfterPlacement: minutes * 60)
    }

    private static func date(secondsAfterPlacement seconds: Int) -> Date {
        // 解析走生产代码那条链，测试不另建一个格式器 —— 两处解析口径一旦分家，
        // 用例会在生产代码解不出来的形状上照样绿。
        guard let placed = placedAt.backendTimestamp else {
            preconditionFailure("下单时刻解析不出来，后面的断言没有意义")
        }
        return placed.addingTimeInterval(TimeInterval(seconds))
    }

    private static func makeOrder(status: RunOrderStatus, createdAt: String?) -> OrderDetailResponse {
        OrderDetailResponse(
            orderId: 7100,
            status: status,
            startAddress: "朝阳公园南门",
            startLatitude: 39.9342,
            startLongitude: 116.4740,
            endAddress: nil,
            endLatitude: nil,
            endLongitude: nil,
            plannedStart: "2026-08-19T11:00:00",
            plannedEnd: "2026-08-19T12:00:00",
            blindName: nil,
            blindPhone: nil,
            volunteerPhone: nil,
            acceptedAt: nil,
            createdAt: createdAt,
            expectedDurationMinutes: 60,
            pacePreference: nil,
            routePreference: nil,
            routeNotes: nil,
            hasGuideDogThisRun: nil,
            specialNotes: nil,
            visionLevel: nil,
            tetherPreference: nil,
            chatPreference: nil
        )
    }
}
