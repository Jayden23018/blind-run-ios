import SwiftUI
import XCTest
@testable import blindRun

/// 陪跑员出发 / 汇合锁屏卡 + 跑步卡 v2（决定源 V3）。
///
/// 卡片的真实长相只能在真机锁屏上看；这里守的是**会静默漂移**的三类东西：
/// 1. 后端推送的 `content-state` 能不能被系统解（系统用默认解码器，解不了 = 锁屏卡冻住，没有任何报错）；
/// 2. 订单 → 卡片内容的映射与本地更新口径一致；
/// 3. 跑步卡第 1 行的 5 分钟闸与暂停。
/// 整类 `@available(iOS 16.2, *)`：看到 `passed=0` 一律当失败查（整类被跳过了）。
@available(iOS 16.2, *)
@MainActor
final class GuideRunActivityTests: XCTestCase {

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

    func testPushTokenIsUploadedAsLowercaseHex() {
        let hex = GuideRunActivityContentBuilder.hexString(Data([0x00, 0x0F, 0xA0, 0xFF]))
        XCTAssertEqual(hex, "000fa0ff")
    }

    // MARK: - 卡上每一行

    private func presentation(
        _ state: GuideRunAttributes.ContentState,
        plannedStart: Date? = nil,
        surname: String? = nil
    ) -> GuideRunActivityPresentation {
        GuideRunActivityPresentation(
            attributes: GuideRunAttributes(
                orderID: 1,
                runnerSurname: surname,
                meetingPointName: "3 号入口",
                plannedStart: plannedStart
            ),
            state: state
        )
    }

    func testLateCardSaysHowLateAndUsesTheDepartedColour() {
        let arriveAt = Date(timeIntervalSinceReferenceDate: 811_465_020)
        let view = presentation(
            .init(phase: .late, etaMinutes: 11, arriveAt: arriveAt, progress: 0.4,
                  runnerNearMeetingPoint: false, distanceBucket: nil),
            plannedStart: arriveAt.addingTimeInterval(-6 * 60)
        )

        XCTAssertEqual(view.headline, "约 11 分钟后到")
        XCTAssertTrue(view.headlineIsLate)
        XCTAssertEqual(view.lateSuffix, "晚到约 6 分钟")
        XCTAssertEqual(view.background, LiveActivityStatePalette.stateDeparted, "快迟到仍是出发色（交付包 04）")
        XCTAssertEqual(view.actions, [.almostThere, .waitFiveMinutes])
    }

    func testDepartedCardNamesTheRunnerAsRunnerNotBySurnameInASentence() {
        let view = presentation(
            .init(phase: .departed, etaMinutes: 8, arriveAt: nil, progress: 0.68,
                  runnerNearMeetingPoint: true, distanceBucket: nil),
            surname: "李"
        )

        XCTAssertEqual(view.headline, "8 分钟后到")
        XCTAssertEqual(view.statusLine, "跑者已到3 号入口附近")
        XCTAssertFalse(view.accessibilityLabel.contains("先生"))
        XCTAssertFalse(view.accessibilityLabel.contains("女士"))
        XCTAssertTrue(view.accessibilityLabel.hasPrefix("助盲跑，正在赶去，8 分钟后到"))
    }

    func testZeroMinutesSaysArrivingNowNotZeroMinutes() {
        let view = presentation(
            .init(phase: .departed, etaMinutes: 0, arriveAt: nil, progress: 0.85,
                  runnerNearMeetingPoint: false, distanceBucket: nil)
        )
        XCTAssertEqual(view.headline, "马上到")
        XCTAssertEqual(view.compactTrailing, "马上到")
    }

    func testArrivedCardSwapsToTheArrivedColourAndOnlyOffersRinging() {
        let view = presentation(
            .init(phase: .arrived, etaMinutes: nil, arriveAt: nil, progress: 0.85,
                  runnerNearMeetingPoint: true, distanceBucket: "WITHIN_10")
        )

        XCTAssertEqual(view.headline, "已到集合点")
        XCTAssertEqual(view.statusLine, "跑者就在你身边")
        XCTAssertEqual(view.background, LiveActivityStatePalette.stateArrived)
        XCTAssertEqual(view.actions, [.ringRunner])
        XCTAssertEqual(view.compactTrailing, "已到")
    }

    func testUnknownDistanceBucketShowsNoStatusLine() {
        let view = presentation(
            .init(phase: .arrived, etaMinutes: nil, arriveAt: nil, progress: 0.85,
                  runnerNearMeetingPoint: false, distanceBucket: "SOMETHING_NEW")
        )
        XCTAssertNil(view.statusLine)
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

    /// 锁屏卡上 14–15pt 的小字在出发 / 汇合两种底色上都要过正文 4.5:1。
    /// 把透明度改回交付包的 80% 这条就红（出发蓝 4.36、汇合琥珀 4.45）。
    func testSmallTextOnTheGuideCardClearsBodyTextContrast() {
        let opacity = LiveActivityStatePalette.smallTextOpacityOnGuideCard
        for background in [LiveActivityStatePalette.stateDeparted, LiveActivityStatePalette.stateArrived] {
            let ratio = Self.contrast(Self.whiteBlended(opacity, over: background), background)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, String(format: "#%06X 上 %.2f:1", background, ratio))
        }
        // 反向验证公式真的会拒：80% 在出发蓝上必须不过线。
        XCTAssertLessThan(
            Self.contrast(Self.whiteBlended(0.80, over: LiveActivityStatePalette.stateDeparted), LiveActivityStatePalette.stateDeparted),
            4.5
        )
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

    /// 最高的一种：快迟到（多一行「晚到约 N 分钟」）+ 跑者已到附近 + 两枚按钮。
    func testLateDepartureCardFitsTheLockScreen() {
        let state = GuideRunAttributes.ContentState(
            phase: .late, etaMinutes: 11, arriveAt: Date().addingTimeInterval(660), progress: 0.4,
            runnerNearMeetingPoint: true, distanceBucket: nil
        )
        let measured = height(GuideRunLockScreenView(
            attributes: attributes,
            presentation: GuideRunActivityPresentation(attributes: attributes, state: state)
        ))
        XCTContext.runActivity(named: "[card-height] guide late = \(measured)") { _ in }
        XCTAssertLessThanOrEqual(measured, Self.maximumHeight)
    }

    func testArrivedCardFitsTheLockScreen() {
        let state = GuideRunAttributes.ContentState(
            phase: .arrived, etaMinutes: nil, arriveAt: nil, progress: 0.85,
            runnerNearMeetingPoint: true, distanceBucket: "WITHIN_10"
        )
        let measured = height(GuideRunLockScreenView(
            attributes: attributes,
            presentation: GuideRunActivityPresentation(attributes: attributes, state: state)
        ))
        XCTContext.runActivity(named: "[card-height] guide arrived = \(measured)") { _ in }
        XCTAssertLessThanOrEqual(measured, Self.maximumHeight)
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
