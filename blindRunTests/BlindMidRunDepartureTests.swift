import XCTest
@testable import blindRun

/// 陪跑员半路退出后，跑者听到和看到什么（#653）。
///
/// 这里守的是判定与接线。「三次都完整听到」只能真机人耳验，见记忆
/// `audio-correctness-needs-real-ears-not-code-reading`。
@MainActor
final class BlindMidRunDepartureTests: XCTestCase {

    private static let suiteName = "BlindMidRunDepartureTests"
    private var defaults: UserDefaults!
    private var record: BlindMidRunDepartureRecord!
    private var originalRecord: BlindMidRunDepartureRecord!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: Self.suiteName)
        defaults.removePersistentDomain(forName: Self.suiteName)
        record = BlindMidRunDepartureRecord(defaults: defaults)
        originalRecord = BlindMidRunDepartureRecord.shared
        BlindMidRunDepartureRecord.shared = record
        // 接管提示音与震动：`.alert` 档每句都会响一次。
        AnnouncementCue.observerForTesting = { _ in }
    }

    override func tearDown() {
        AnnouncementCue.observerForTesting = nil
        BlindMidRunDepartureRecord.shared = originalRecord
        defaults.removePersistentDomain(forName: Self.suiteName)
        super.tearDown()
    }

    // MARK: - 判定

    /// 三态逐个验：只验 `IN_PROGRESS` 分辨不出「只认跑步中」这种收窄的实现。
    func testEachEscortStatusCountsAsMidRun() {
        for status in [RunOrderStatus.driverEnRoute, .driverArrived, .inProgress] {
            defaults.removePersistentDomain(forName: Self.suiteName)
            record.observe(orderID: 7, status: status)
            XCTAssertTrue(record.volunteerLeftMidRun(orderID: 7, status: .rematching), "\(status) 之后退出算半路退出")
        }
    }

    /// 派单等待期取消时跑者还没出门，后端也只发 NORMAL 的 `REMATCHING`。
    func testRematchingFromPendingAcceptIsNotMidRun() {
        record.observe(orderID: 7, status: .pendingAccept)
        XCTAssertFalse(record.volunteerLeftMidRun(orderID: 7, status: .rematching))
    }

    /// 换上新陪跑员之后，事实就不再成立。不清的话下一次出发前退出会误报「只有你一个人」。
    func testNewVolunteerClearsTheRecord() {
        record.observe(orderID: 7, status: .inProgress)
        record.observe(orderID: 7, status: .rematching)
        XCTAssertTrue(record.volunteerLeftMidRun(orderID: 7, status: .rematching))

        record.observe(orderID: 7, status: .pendingAccept)
        XCTAssertFalse(record.volunteerLeftMidRun(orderID: 7, status: .rematching))
    }

    func testAnotherOrderDoesNotInheritTheRecord() {
        record.observe(orderID: 7, status: .inProgress)
        XCTAssertFalse(record.volunteerLeftMidRun(orderID: 8, status: .rematching))
    }

    /// 同一张单只有在 `REMATCHING` 时才算，防止「跑步中」本身被判成已退出。
    func testOnlyTheRematchingStatusReportsDeparture() {
        record.observe(orderID: 7, status: .inProgress)
        XCTAssertFalse(record.volunteerLeftMidRun(orderID: 7, status: .inProgress))
    }

    /// 🔴 App 被杀后重新打开：内存里什么都没了，事实必须还在。
    func testRecordSurvivesARelaunch() {
        record.observe(orderID: 7, status: .inProgress)
        let relaunched = BlindMidRunDepartureRecord(defaults: UserDefaults(suiteName: Self.suiteName))
        XCTAssertTrue(relaunched.volunteerLeftMidRun(orderID: 7, status: .rematching))
    }

    /// 🔴 手机在后台错过了换人：新陪跑员出发前又退出时，普通 `REMATCHING` 通知要能撤销这个记录，
    /// 否则跑者在家听到「只有你一个人」。
    func testPlainRematchingEventClearsTheRecord() {
        record.observe(orderID: 7, status: .inProgress)
        record.note(eventType: "REMATCHING", orderID: 7)
        XCTAssertFalse(record.volunteerLeftMidRun(orderID: 7, status: .rematching))
    }

    /// 通话没聊成回到 `REMATCHING` 时不能说「陪跑员已退出」，否则等于告诉跑者被候选人拒绝了。
    func testIntroCallClearsTheRecordToKeepRejectionSilent() {
        record.observe(orderID: 7, status: .inProgress)
        record.observe(orderID: 7, status: .pendingIntroCall)
        XCTAssertFalse(record.volunteerLeftMidRun(orderID: 7, status: .rematching))
    }

    /// 不认识的新状态不是「接上了人」的证据，不能清。
    func testUnknownStatusKeepsTheRecord() {
        record.observe(orderID: 7, status: .inProgress)
        record.observe(orderID: 7, status: .unknown)
        XCTAssertTrue(record.volunteerLeftMidRun(orderID: 7, status: .rematching))
    }

    /// 过期的「已收到警示」不能吞掉下一次退出的状态句。
    func testLeavingRematchingForgetsTheAlert() {
        record.note(eventType: "REMATCHING_MID_RUN", orderID: 7)
        record.observe(orderID: 7, status: .pendingAccept)
        XCTAssertFalse(record.consumeAlert(orderID: 7))
    }

    func testRecordWithoutDefaultsIsInert() {
        let inert = BlindMidRunDepartureRecord(defaults: nil)
        inert.observe(orderID: 7, status: .inProgress)
        XCTAssertFalse(inert.volunteerLeftMidRun(orderID: 7, status: .rematching))
    }

    // MARK: - 文案

    func testAllSurfacesStopSayingTheGenericSentence() throws {
        record.observe(orderID: 7, status: .inProgress)
        let order = OrderDetailResponse.preview(orderId: 7, status: .rematching)

        let presentation = try XCTUnwrap(
            BlindOrderFlowPresentation.make(order: order, distanceText: nil, canKeepWaiting: false)
        )
        XCTAssertEqual(presentation.title, BlindMidRunDepartureCopy.title)
        XCTAssertTrue(presentation.subtitle.hasPrefix(BlindMidRunDepartureCopy.description))
        XCTAssertEqual(order.blindRunnerAnnouncement(), BlindMidRunDepartureCopy.announcement)
        XCTAssertEqual(
            VoiceStatusQuery.answer(
                intent: .status, order: order, volunteerCoordinate: nil, fallbackAnnouncement: ""
            ).speech,
            BlindMidRunDepartureCopy.announcement
        )

        for text in [presentation.title, presentation.subtitle, order.blindRunnerAnnouncement()] {
            XCTAssertFalse(text.contains("正在确认陪跑员状态"), text)
        }
        XCTAssertTrue(BlindMidRunDepartureCopy.announcement.contains("只有你一个人"))
        XCTAssertTrue(BlindMidRunDepartureCopy.announcement.contains("请先停下来"))
    }

    /// 出发前退出的那一单保持原样：只有确实在同行态退出才说「只有你一个人」。
    func testRematchingBeforeSettingOutKeepsTheGenericCopy() throws {
        let order = OrderDetailResponse.preview(orderId: 7, status: .rematching)
        let presentation = try XCTUnwrap(
            BlindOrderFlowPresentation.make(order: order, distanceText: nil, canKeepWaiting: false)
        )
        XCTAssertEqual(presentation.title, "正在重新匹配陪跑员")
        XCTAssertEqual(order.blindRunnerAnnouncement(), RunOrderStatus.rematching.blindRunnerAnnouncement)
    }
}
