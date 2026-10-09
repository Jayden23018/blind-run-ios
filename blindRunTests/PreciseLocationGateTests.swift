import CoreLocation
import XCTest
@testable import blindRun

/// #373：盲人端识别「精确位置」关闭与低精度定位（OpenSpec `gate-blind-location-on-precise-accuracy`）。
///
/// 每条拦截用例都配一个「精确位置开着」的对照：只断「关着时拦住」的话，
/// 一个把所有定位都拦掉的实现也会绿。
@MainActor
final class PreciseLocationGateTests: XCTestCase {

    override func setUp() {
        super.setUp()
        EmergencyAlarm.observerForTesting = { _ in }
        EmergencyHaptics.observerForTesting = { _ in }
    }

    // MARK: - 阈值

    /// 盲人端与陪跑员端说「定位差」用的是同一个数。两处常量各写一份，这条钉住它们不漂。
    func testWeakAccuracyThresholdMatchesTheVolunteerSide() {
        XCTAssertEqual(LocationAccuracyPolicy.weakAccuracyMeters, VolunteerRunTip.weakAccuracyMeters)
    }

    /// 边界取在阈值两侧：50 米整不算差，50.5 米算差；精度未知不算差（没有依据就不说「不准」）。
    func testWeakAccuracyIsStrictlyAboveTheThreshold() {
        XCTAssertNil(LocationAccuracyPolicy.weakAccuracyMeters(of: Self.sample(accuracy: 50)))
        XCTAssertEqual(LocationAccuracyPolicy.weakAccuracyMeters(of: Self.sample(accuracy: 50.5)), 50.5)
        XCTAssertNil(LocationAccuracyPolicy.weakAccuracyMeters(of: Self.sample(accuracy: nil)))
        XCTAssertNil(LocationAccuracyPolicy.weakAccuracyMeters(of: nil))
    }

    // MARK: - 云端求助

    /// 🔴 精确位置关闭时，一个**新鲜的真实设备样本**也不许发出去。
    ///
    /// 样本故意给得「什么都对」：刚采到、已授权、精度 5000 米（模糊位置的典型值）。
    /// 只靠新鲜度闸的旧实现会把它原样发出 —— 这正是 #373 的缺陷。
    func testPreciseLocationOffSendsNoEmergencyAndSaysWhy() async {
        let location = Self.locationService(accuracy: 5000)
        location.simulatePreciseLocationOffForTesting()
        let coordinator = EmergencyCoordinator()
        let safety = FakeSafetyService()
        safety.triggerEmergencyResult = .success(
            EmergencyTriggerResponse(success: true, eventId: 1, status: "CONTACT_NOTIFIED")
        )

        let startedAt = Date()
        let outcome = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { await EmergencyCoordinator.freshEmergencyCoordinate(using: location) },
            locationFailureReason: { EmergencyCoordinator.locationFailureReason(using: location) }
        )

        XCTAssertTrue(safety.calls.isEmpty, "一个字节都不许发")
        XCTAssertEqual(coordinator.state, .unsentNoLocation(.preciseLocationOff))
        XCTAssertTrue(outcome.isFailure, "失败态才会出现本地拨号兜底按钮")
        for word in ["未发出", "精确位置", "120", "110"] {
            XCTAssertTrue(outcome.message.contains(word), "缺「\(word)」：\(outcome.message)")
        }
        XCTAssertFalse(outcome.message.contains("室外开阔处"), "换地方解决不了一个开关的问题")
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 2, "开关问题不该白等 5 秒定位")
        XCTAssertTrue(location.temporaryPreciseLocationRequestsForTesting.isEmpty, "求助时不弹系统框抢读屏焦点")
    }

    /// 对照：同一个样本、精确位置开着，就该照常拿到坐标。
    func testPreciseLocationOnReturnsTheFreshSample() async {
        let location = Self.locationService(accuracy: 5000)
        location.simulatePreciseLocationOffForTesting(false)

        let coordinate = await EmergencyCoordinator.freshEmergencyCoordinate(using: location)

        XCTAssertNotNil(coordinate)
        XCTAssertNil(EmergencyCoordinator.locationFailureReason(using: location))
    }

    /// 精确授权下精度 65 米：照发，屏幕与播报都说误差。30 米：不说。
    func testLowAccuracyEmergencyIsSentWithAnErrorNoteAndPreciseOneIsNot() async {
        for (accuracy, expectsNote) in [(65.0, true), (30.0, false)] {
            let coordinator = EmergencyCoordinator()
            let safety = FakeSafetyService()
            safety.triggerEmergencyResult = .success(
                EmergencyTriggerResponse(success: true, eventId: 77, status: "CONTACT_NOTIFIED")
            )

            let outcome = await coordinator.trigger(
                order: Self.makeOrder(status: .inProgress),
                role: .blind,
                userID: 7,
                safety: safety,
                locate: { Self.backendSample(accuracy: accuracy) }
            )

            XCTAssertEqual(safety.calls, ["triggerEmergency(_:)"], "精度差不是拦截理由")
            XCTAssertEqual(coordinator.state, .acknowledged(.contactNotified))
            let shown = coordinator.statusMessage ?? ""
            XCTAssertEqual(shown.contains("误差约 65 米"), expectsNote, "屏幕：\(accuracy) 米 → \(shown)")
            XCTAssertEqual(outcome.message.contains("误差约"), expectsNote, "播报：\(accuracy) 米 → \(outcome.message)")
            XCTAssertEqual(outcome.message, shown, "屏幕与耳朵读同一句")
        }
    }

    /// 倒计时路径：误差说明跟在第一句后面念一次，每秒那句倒数不带。
    func testCountdownAnnouncesTheErrorNoteOnceNotEverySecond() async {
        let coordinator = EmergencyCoordinator()
        let safety = FakeSafetyService()
        safety.triggerEmergencyResult = .success(
            EmergencyTriggerResponse(
                success: true,
                eventId: 91,
                status: "COUNTDOWN",
                countdownEndsAt: DateFormatter.aidRunBackendLocalDateTime.string(from: Date().addingTimeInterval(3))
            )
        )
        var spoken: [String] = []

        coordinator.beginCountdown(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.backendSample(accuracy: 65) },
            announce: { spoken.append($0) }
        )
        let ticked = await Self.waitUntil { spoken.count >= 2 }
        coordinator.reset()

        XCTAssertTrue(ticked, "倒计时没开始：\(spoken)")
        XCTAssertTrue(spoken[0].contains("误差约 65 米"), "第一句要带误差：\(spoken[0])")
        XCTAssertFalse(spoken[1].contains("误差"), "每秒倒数不重复误差：\(spoken[1])")
    }

    /// 换了事件（陪跑员代发、冷启动恢复）就不许再挂上一条的误差说明。
    ///
    /// 恢复路径不经过 `send`，只有 `activeEvent.didSet` 会清 —— 那道清理被拿掉时这条会红。
    func testErrorNoteDoesNotFollowADifferentRecoveredEvent() async {
        let safety = FakeSafetyService()
        let coordinator = EmergencyCoordinator()
        coordinator.observe(AppRealtimeCoordinator(notificationDuration: 60)) { safety }
        safety.triggerEmergencyResult = .success(
            EmergencyTriggerResponse(success: true, eventId: 77, status: "CONTACT_NOTIFIED")
        )
        _ = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.backendSample(accuracy: 65) }
        )
        XCTAssertTrue(coordinator.statusMessage?.contains("误差约 65 米") == true, "前提：第一条带误差")

        safety.activeEmergencyResult = .success(Self.openEventEnvelope(id: 88))
        await coordinator.refreshActiveEvent()

        XCTAssertEqual(coordinator.activeEvent?.eventID, 88, "前提：恢复出来的是另一条事件")
        XCTAssertFalse(coordinator.statusMessage?.contains("误差") == true, "别的事件不是用这个坐标发的")
    }

    /// 只有「已发出或即将发出」才谈得上所附位置的误差。
    func testOnlySentStatesCarryTheSubmittedLocation() {
        let carrying: [EmergencySOSState] = [
            .countingDown(secondsRemaining: 3), .submitting, .acknowledged(.pending),
            .acknowledged(.contactNotified), .contactSmsDelivered, .contactNotifyFailed
        ]
        let notCarrying: [EmergencySOSState] = [
            .idle, .locating, .unsentNoLocation(.preciseLocationOff), .failed("网络异常"),
            .cooldown(retryAfterSeconds: 30), .cancelledByOwner, .withdrawnBeforeSending,
            .withdrawFailed(nil), .acknowledged(.resolved), .acknowledged(.cancelled)
        ]
        for state in carrying { XCTAssertTrue(state.carriesSubmittedLocation, "\(state)") }
        for state in notCarrying { XCTAssertFalse(state.carriesSubmittedLocation, "\(state)") }
    }

    // MARK: - 下单起点

    /// 精确位置关闭：设备位置拿得到，但不许当出发点；进页只自动申请一次，按钮可以再申请。
    func testPreciseLocationOffKeepsCurrentLocationOutOfTheStartPoint() async {
        let location = Self.locationService(accuracy: 5000)
        location.simulatePreciseLocationOffForTesting()
        let viewModel = Self.makeBookingViewModel(locationService: location)

        await viewModel.refreshCurrentLocation()
        await viewModel.refreshCurrentLocation()

        XCTAssertNil(viewModel.currentResolvedPlace)
        XCTAssertNil(viewModel.resolvedStartPlace, "区域代表点不是出发点")
        XCTAssertEqual(viewModel.firstMissingGate, .startPoint)
        XCTAssertEqual(location.temporaryPreciseLocationRequestsForTesting, [.bookingStartPoint], "本页只自动申请一次")

        viewModel.requestTemporaryPreciseLocation()
        XCTAssertEqual(location.temporaryPreciseLocationRequestsForTesting.count, 2, "用户按按钮就再申请")

        // 手动选的地点照常可用 —— 拦的是设备来源，不是下单。
        let manual = ResolvedPlace(
            id: "poi-1", title: "人民广场", addressText: "上海市黄浦区人民广场",
            latitude: 31.2304, longitude: 121.4737, source: .manual
        )
        viewModel.selectedStartPlace = manual
        XCTAssertEqual(viewModel.resolvedStartPlace?.id, "poi-1")
    }

    /// 对照：精确位置开着，同一个设备位置就是出发点，也不申请临时授权。
    func testPreciseLocationOnUsesCurrentLocationAsTheStartPoint() async {
        let location = Self.locationService(accuracy: 10)
        location.simulatePreciseLocationOffForTesting(false)
        let viewModel = Self.makeBookingViewModel(locationService: location)

        await viewModel.refreshCurrentLocation()

        XCTAssertEqual(viewModel.resolvedStartPlace?.source, .deviceLocation)
        XCTAssertTrue(location.temporaryPreciseLocationRequestsForTesting.isEmpty)
    }

    /// 降级告知：精确位置关闭一档说清「还能怎么下单」和「关着会失去什么」；被拒优先。
    func testPreciseLocationOffNoticeStatesTheWorkaroundAndTheSafetyCost() {
        XCTAssertEqual(
            BlindBookingViewModel.locationDegradationNotice(isDenied: false, isPreciseLocationOff: true),
            BlindBookingViewModel.preciseLocationOffNotice
        )
        for word in ["精确位置", "搜索", "求助"] {
            XCTAssertTrue(BlindBookingViewModel.preciseLocationOffNotice.contains(word), "缺「\(word)」")
        }
        XCTAssertEqual(
            BlindBookingViewModel.locationDegradationNotice(isDenied: true, isPreciseLocationOff: true),
            BlindBookingViewModel.locationDeniedNotice,
            "被拒时没有精确位置可谈"
        )
        XCTAssertNil(BlindBookingViewModel.locationDegradationNotice(isDenied: false, isPreciseLocationOff: false))
    }

    /// 精确授权下 65 米：当前位置照用，卡片提示核对并念一次；30 米不提示。
    func testLowAccuracyCurrentLocationAsksToVerifyTheAddressOnce() async {
        for (accuracy, expectsNotice) in [(65.0, true), (30.0, false)] {
            let location = Self.locationService(accuracy: accuracy)
            location.simulatePreciseLocationOffForTesting(false)
            let speech = SpeechService()
            let viewModel = Self.makeBookingViewModel(locationService: location, speechService: speech)

            await viewModel.refreshCurrentLocation()

            XCTAssertEqual(viewModel.resolvedStartPlace?.source, .deviceLocation, "精度差不是拦截理由")
            XCTAssertEqual(viewModel.startPointAccuracyNotice != nil, expectsNotice, "\(accuracy) 米")
            let notice = viewModel.startPointAccuracyNotice
            let spokenCount = { speech.spokenHistoryForTesting.filter { $0 == notice }.count }
            guard expectsNotice else {
                XCTAssertFalse(speech.spokenHistoryForTesting.contains { $0.contains("误差") })
                continue
            }
            XCTAssertTrue(notice?.contains("误差约 65 米") == true)
            XCTAssertEqual(spokenCount(), 1, "屏幕与耳朵读同一句：\(speech.spokenHistoryForTesting)")

            await viewModel.refreshCurrentLocation()
            XCTAssertEqual(spokenCount(), 1, "本页只念一次")
        }
    }

    // MARK: - 陪跑中

    /// 盲人端：出发阶段申请一次，进 `IN_PROGRESS` 再申请一次，同一阶段不重复；健康提示落到精确位置那一档。
    func testBlindEscortRequestsPreciseLocationPerPhaseAndShowsTheHealthBanner() async {
        let location = Self.locationService(accuracy: 5000)
        location.simulatePreciseLocationOffForTesting()
        let coordinator = Self.makeEscortCoordinator(role: .blind, location: location)

        coordinator.updateOwnedOrder(orderID: 79, status: .driverEnRoute)
        let showedBanner = await Self.waitUntil { coordinator.healthState == .preciseLocationOff }
        XCTAssertTrue(showedBanner, "健康提示：\(coordinator.healthState)")
        XCTAssertEqual(location.temporaryPreciseLocationRequestsForTesting, [.escortRun])
        XCTAssertTrue(coordinator.healthState.userMessage?.contains("求助") == true, "要说清求助会发不出去")

        coordinator.updateOwnedOrder(orderID: 79, status: .driverArrived)
        _ = await Self.waitUntil { false }
        XCTAssertEqual(location.temporaryPreciseLocationRequestsForTesting.count, 1, "出发阶段内不重复弹")

        coordinator.updateOwnedOrder(orderID: 79, status: .inProgress)
        let requestedAgain = await Self.waitUntil { location.temporaryPreciseLocationRequestsForTesting.count == 2 }
        XCTAssertTrue(requestedAgain, "进跑步阶段仍关着就再申请一次")

        // 用户允许了：下一轮刷新回到正常档位。
        location.simulatePreciseLocationOffForTesting(false)
        let recovered = await Self.waitUntil { coordinator.healthState == .active(background: true) }
        XCTAssertTrue(recovered, "允许之后应恢复：\(coordinator.healthState)")
        coordinator.reset()
    }

    /// 陪跑员端不进这一档、不弹系统框（#373 只管盲人端）。
    func testVolunteerEscortIgnoresPreciseLocation() async {
        let location = Self.locationService(accuracy: 5000)
        location.simulatePreciseLocationOffForTesting()
        let coordinator = Self.makeEscortCoordinator(role: .volunteer, location: location)

        coordinator.updateOwnedOrder(orderID: 80, status: .inProgress)
        let settled = await Self.waitUntil { coordinator.healthState == .active(background: true) }

        XCTAssertTrue(settled, "健康提示：\(coordinator.healthState)")
        XCTAssertTrue(location.temporaryPreciseLocationRequestsForTesting.isEmpty)
        coordinator.reset()
    }

    // MARK: - Helpers

    private static func locationService(accuracy: Double?) -> LocationService {
        let location = LocationService()
        location.simulateDeviceLocationForTesting(
            CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
            capturedAt: Date(),
            horizontalAccuracy: accuracy
        )
        return location
    }

    private static func sample(accuracy: Double?) -> LocatedCoordinate {
        LocatedCoordinate(
            coordinate: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
            system: .wgs84Device,
            horizontalAccuracy: accuracy
        )
    }

    nonisolated private static func backendSample(accuracy: Double) -> LocatedCoordinate {
        LocatedCoordinate(
            coordinate: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
            system: .gcj02Backend,
            capturedAt: Date(),
            horizontalAccuracy: accuracy
        )
    }

    private static func makeBookingViewModel(
        locationService: LocationService,
        speechService: SpeechService = SpeechService()
    ) -> BlindBookingViewModel {
        let viewModel = BlindBookingViewModel()
        viewModel.configureForTesting(speechService: speechService, locationService: locationService)
        return viewModel
    }

    private static func makeEscortCoordinator(role: UserRole, location: LocationService) -> LiveEscortSessionCoordinator {
        let coordinator = LiveEscortSessionCoordinator(
            realtimeCoordinator: AppRealtimeCoordinator(),
            reportInterval: 0.05,
            sendLocation: { _, _, _ in }
        )
        let service = WebSocketService()
        service.simulateConnectionStateForTesting(.connected)
        coordinator.configure(identityKey: "account:\(role):token", role: role, webSocketService: service)
        coordinator.attachLocationService(location)
        return coordinator
    }

    /// 轮询到条件成立或超时。`{ false }` 当作「等一小段」用。
    private static func waitUntil(timeout: TimeInterval = 1, _ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    private static func openEventEnvelope(id: Int64) -> EmergencyActiveEnvelope {
        let json = """
        {"success":true,"code":200,"data":{
          "id":\(id),"orderId":4242,"userId":7,
          "triggeredAt":"2026-10-09T07:30:00","triggerType":"VOLUNTEER_BUTTON",
          "status":"CONTACT_NOTIFIED","hasGpsLocation":true}}
        """
        // swiftlint:disable:next force_try 桩数据解不出说明这条用例本身写坏了，该当场炸。
        return try! APIPayloadDecoder.decodePayload(
            EmergencyActiveEnvelope.self,
            from: Data(json.utf8),
            decoder: JSONDecoder()
        )
    }

    private static func makeOrder(status: RunOrderStatus) -> OrderDetailResponse {
        OrderDetailResponse(
            orderId: 4242,
            status: status,
            startAddress: "测试出发点",
            startLatitude: nil,
            startLongitude: nil,
            endAddress: nil,
            endLatitude: nil,
            endLongitude: nil,
            plannedStart: nil,
            plannedEnd: nil,
            blindName: nil,
            blindPhone: nil,
            volunteerPhone: "13800000000",
            acceptedAt: nil,
            createdAt: nil,
            expectedDurationMinutes: nil,
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
