import CoreLocation
import XCTest
@testable import blindRun

/// 下单硬门槛的顺序判定（纯函数，直接驱动）与它在 ViewModel 上的接线。
final class BlindBookingGateTests: XCTestCase {

    // MARK: - 下单门槛

    func testAllSatisfiedReturnsNoGate() {
        XCTAssertNil(
            BlindBookingGate.firstMissing(
                hasValidEmergencyContacts: true,
                hasStartPoint: true,
                isAppointmentTimeValid: true
            )
        )
    }

    func testFirstMissingFollowsDeclaredOrder() {
        // 全部缺失时只报第一个可操作项，逐个补齐后依次推进。
        let expectedSequence: [BlindBookingGate] = [
            .emergencyContacts, .startPoint, .appointmentTime
        ]
        // contacts, startPoint, timeValid
        var flags = [false, false, false]

        for expected in expectedSequence {
            let gate = BlindBookingGate.firstMissing(
                hasValidEmergencyContacts: flags[0],
                hasStartPoint: flags[1],
                isAppointmentTimeValid: flags[2]
            )
            XCTAssertEqual(gate, expected)

            switch expected {
            case .emergencyContacts: flags[0] = true
            case .startPoint: flags[1] = true
            case .appointmentTime: flags[2] = true
            }
        }

        XCTAssertNil(
            BlindBookingGate.firstMissing(
                hasValidEmergencyContacts: flags[0],
                hasStartPoint: flags[1],
                isAppointmentTimeValid: flags[2]
            )
        )
    }

    // MARK: - 门槛在 ViewModel 上的真实接线
    //
    // 上面几条测的是纯函数 `firstMissing`。下面三条测的是「它有没有真的被接上」——
    // 2026-08-05 之前它在两个地方被绕过去了：兜底坐标让 `.startPoint` 恒真，
    // 审阅步的提示语手抄了一份只有后三道的门槛。纯函数全绿，用户照样撞墙。

    private func contact(_ id: Int64, primary: Bool) -> EmergencyContactResponse {
        EmergencyContactResponse(
            id: id, name: "联系人\(id)", phone: "1390013900\(id)",
            relationship: "家人", isPrimary: primary
        )
    }

    /// 这几条用例只驱动门槛，不搜地点，所以 `placeSearchProvider` 留空。
    @MainActor
    private func makeBookingViewModel(
        locationService: LocationService? = nil,
        appState: AppState? = nil
    ) -> BlindBookingViewModel {
        let viewModel = BlindBookingViewModel()
        viewModel.configureForTesting(
            speechService: SpeechService(),
            locationService: locationService,
            appState: appState
        )
        return viewModel
    }

    /// 没有真实定位时，兜底的北京演示坐标**不得**充当出发地点。
    ///
    /// 它一旦充当，`resolvedStartPlace` 就永不为 nil，`.startPoint` 这道门槛在生产里
    /// 变成死代码，一个在上海的用户会被约到北京。
    ///
    /// 前提用接缝钉死：裸 `LocationService()` 在真机上几毫秒内就会被 CoreLocation 填上真实坐标，
    /// 那样这条用例过不过取决于回调时序而不是守卫本身。
    @MainActor
    func testDemoFallbackCoordinateIsNotAcceptedAsStartPoint() {
        let location = LocationService()
        location.simulateMissingDeviceLocationForTesting()
        XCTAssertTrue(location.isUsingDemoFallback, "前提：没有真实定位")
        XCTAssertFalse(location.isDenied, "前提：权限未拒绝 —— 这条测的是演示坐标，不是权限")

        let viewModel = makeBookingViewModel(locationService: location)

        XCTAssertNil(viewModel.resolvedStartPlace, "演示坐标不是出发地点")
        XCTAssertEqual(viewModel.firstMissingGate, .startPoint, "门槛必须真的拦住，而不是恒真")
        XCTAssertFalse(viewModel.canSubmit)
        XCTAssertNil(viewModel.makeCreateOrderRequest(), "演示坐标不得进入下单请求体")
    }

    /// 关掉定位权限之后，手动搜到的出发地点必须仍然能下单（Apple 5.1.1(iv)）。
    ///
    /// 2026-08-18 之前 `isLocationDenied` 是第四道硬门槛：关掉定位 ⇒ `canSubmit` 恒 false，
    /// 而屏幕上那一段（搜索框 / 常用地点 / 语音输入）同时被权限提示整段顶掉 ——
    /// 也就是没有任何替代路径，App 的核心功能随权限一起消失。
    /// 这条用例钉的就是那道门槛不许回来。
    @MainActor
    func testLocationDeniedStillAllowsBookingWithManualStartPlace() {
        let appState = AppState(persistence: AppStatePersistenceFactory.makeIsolatedTest())
        appState.updateBlindProfile(BlindProfileResponse(name: "测试用户", verifyStatus: "VERIFIED"))
        appState.updateEmergencyContacts([contact(1, primary: true)])

        let location = LocationService()
        // 已有接缝：`authorized: false` 会清掉设备坐标并把权限钉在「被拒」。
        location.simulateDeviceLocationForTesting(
            CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
            capturedAt: Date(),
            authorized: false
        )
        XCTAssertTrue(location.isDenied, "前提：权限确实被拒")

        let viewModel = makeBookingViewModel(locationService: location, appState: appState)
        // 手动搜索这条路不依赖定位权限，选中的地点自带坐标。
        viewModel.selectedStartPlace = ResolvedPlace(
            id: "poi-1", title: "人民广场", addressText: "上海市黄浦区人民广场",
            latitude: 31.2304, longitude: 121.4737, source: .manual
        )
        // 固定白天时刻而不是 `minimumAppointmentTime + 10 分钟`：后者落进夜间窗口
        // `[22:00, 05:00)` 时不合法，会让用例白天绿、夜里红（见 `BookingTimeFixture`）。
        viewModel.appointmentTime = BookingTimeFixture.daytime()

        XCTAssertNil(viewModel.firstMissingGate, "定位被拒不再是下单门槛")
        XCTAssertTrue(viewModel.canSubmit, "手动选了起点就必须能提交")
        XCTAssertNotNil(viewModel.makeCreateOrderRequest(), "请求体用的是手动地点的坐标")
    }

    /// 不拦截**不等于**不告知：降级告知必须同时说清「还能怎么下单」和「关着会失去什么」。
    ///
    /// 只说前半句会把一次真实的安全降级说成无关紧要 —— 陪跑过程中志愿者看不到位置、
    /// 云端求助可能发不出去，两件事都发生在盲人当场问不了任何人的时候。
    ///
    /// 断的是 `locationDegradationNotice(isDenied:)` 本身：约跑页接上告知时（#813）渲染与朗读都该走它。
    @MainActor
    func testLocationDeniedNoticeStatesBothTheWorkaroundAndTheSafetyCost() {
        let location = LocationService()
        location.simulateDeviceLocationForTesting(
            CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
            capturedAt: Date(),
            authorized: false
        )
        XCTAssertTrue(location.isDenied, "先确认这个替身真的处在被拒状态，否则下面断的是空气")

        XCTAssertEqual(
            BlindBookingViewModel.locationDegradationNotice(isDenied: location.isDenied),
            BlindBookingViewModel.locationDeniedNotice,
            "屏幕与耳朵读同一份文案"
        )
        XCTAssertTrue(BlindBookingViewModel.locationDeniedNotice.contains("搜索"), "要说还能手动搜地点")
        XCTAssertTrue(BlindBookingViewModel.locationDeniedNotice.contains("求助"), "要说求助会受影响")

        // 权限正常时不该出现这段告知。
        let authorized = LocationService()
        authorized.simulateMissingDeviceLocationForTesting()
        XCTAssertFalse(authorized.isDenied)
        XCTAssertNil(BlindBookingViewModel.locationDegradationNotice(isDenied: authorized.isDenied))
    }

    /// 提交被拦时念的那句必须覆盖要去别的页面补的门槛。
    ///
    /// 按钮禁用状态走的是 `canSubmit`（门槛全查）。说法若只查本页的槽位，
    /// 缺紧急联系人时用户听到的是一个按不动的按钮却没有原因 ——
    /// 看不见屏幕的人只会当成「点了没反应」。
    @MainActor
    func testSubmitGateMessageCoversGatesFixedOnOtherPages() {
        let appState = AppState(persistence: AppStatePersistenceFactory.makeIsolatedTest())
        appState.updateBlindProfile(BlindProfileResponse(name: "测试用户", verifyStatus: "VERIFIED"))
        // 紧急联系人故意留空 —— 这道门槛只能去别的页面补。

        let viewModel = makeBookingViewModel(appState: appState)
        viewModel.selectedStartPlace = ResolvedPlace(
            id: "poi-1", title: "人民广场", addressText: "上海市黄浦区人民广场",
            latitude: 31.2304, longitude: 121.4737, source: .manual
        )
        // 固定白天时刻而不是 `minimumAppointmentTime + 10 分钟`：后者落进夜间窗口
        // `[22:00, 05:00)` 时不合法，会让用例白天绿、夜里红（见 `BookingTimeFixture`）。
        viewModel.appointmentTime = BookingTimeFixture.daytime()

        XCTAssertFalse(viewModel.canSubmit, "前提：按钮此时是禁用的")
        XCTAssertEqual(
            viewModel.firstMissingGate.map(viewModel.message(for:)),
            BlindBookingGate.emergencyContacts.message,
            "禁用了就必须说得出原因"
        )
    }

    /// 「时间不合法」时要说出**真实原因**，不能一律念「至少 30 分钟后」（#424）。
    ///
    /// 三个取值各落在不同的问题上：晚上 23:00（在 30 分钟之后，但撞夜间窗口）、8 天后的白天、一分钟后。
    /// 若实现退回手抄的「至少 30 分钟」，前两条会拿到 `.tooSoon` 的说法而变红；
    /// 若三种原因被塌成同一句，下面的互不相等断言也会抓到。
    @MainActor
    func testGateMessageNamesTheActualAppointmentTimeProblem() {
        let appState = AppState(persistence: AppStatePersistenceFactory.makeIsolatedTest())
        appState.updateBlindProfile(BlindProfileResponse(name: "测试用户", verifyStatus: "VERIFIED"))
        appState.updateEmergencyContacts([contact(1, primary: true)])

        let viewModel = makeBookingViewModel(appState: appState)
        viewModel.selectedStartPlace = ResolvedPlace(
            id: "poi-1", title: "人民广场", addressText: "上海市黄浦区人民广场",
            latitude: 31.2304, longitude: 121.4737, source: .manual
        )

        // 夜间窗口按北京时间判（`Calendar.aidRunBackend`），所以用同一个日历造 23:00。
        let backend = Calendar.aidRunBackend
        let tomorrow = backend.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let tomorrowNight = backend.date(bySettingHour: 23, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        let eightDaysAhead = BookingTimeFixture.daytime().addingTimeInterval(8 * 24 * 3600)

        let cases: [(Date, BookingTimeProblem)] = [
            (tomorrowNight, .nightWindow),
            (eightDaysAhead, .tooFar),
            (Date().addingTimeInterval(60), .tooSoon)
        ]
        var spoken: [String] = []
        for (time, problem) in cases {
            viewModel.appointmentTime = time
            XCTAssertEqual(viewModel.appointmentTimeProblem, problem, "前提：这个时间确实卡在 \(problem)")
            XCTAssertEqual(viewModel.firstMissingGate, .appointmentTime)
            XCTAssertEqual(viewModel.message(for: .appointmentTime), problem.message, "提交被拦时要说出真实原因")
            spoken.append(viewModel.message(for: .appointmentTime))
        }
        XCTAssertEqual(Set(spoken).count, 3, "三种原因必须说成三句不同的话")

        // 非时间门槛的说法不受影响。
        XCTAssertEqual(viewModel.message(for: .emergencyContacts), BlindBookingGate.emergencyContacts.message)
    }
}
