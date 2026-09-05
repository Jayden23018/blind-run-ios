import CoreLocation
import XCTest
@testable import blindRun

/// 下单硬门槛与盲人引导流的顺序判定。两者都是纯函数，直接驱动。
final class BlindBookingGateTests: XCTestCase {

    // MARK: - 下单门槛

    func testAllSatisfiedReturnsNoGate() {
        XCTAssertNil(
            BlindBookingGate.firstMissing(
                isBasicProfileComplete: true,
                isIdentityVerified: true,
                hasValidEmergencyContacts: true,
                hasStartPoint: true,
                isAppointmentTimeValid: true
            )
        )
    }

    func testFirstMissingFollowsDeclaredOrder() {
        // 全部缺失时只报第一个可操作项，逐个补齐后依次推进。
        let expectedSequence: [BlindBookingGate] = [
            .basicProfile, .identityVerification, .emergencyContacts,
            .startPoint, .appointmentTime
        ]
        // profile, identity, contacts, startPoint, timeValid
        var flags = [false, false, false, false, false]

        for expected in expectedSequence {
            let gate = BlindBookingGate.firstMissing(
                isBasicProfileComplete: flags[0],
                isIdentityVerified: flags[1],
                hasValidEmergencyContacts: flags[2],
                hasStartPoint: flags[3],
                isAppointmentTimeValid: flags[4]
            )
            XCTAssertEqual(gate, expected)

            switch expected {
            case .basicProfile: flags[0] = true
            case .identityVerification: flags[1] = true
            case .emergencyContacts: flags[2] = true
            case .startPoint: flags[3] = true
            case .appointmentTime: flags[4] = true
            }
        }

        XCTAssertNil(
            BlindBookingGate.firstMissing(
                isBasicProfileComplete: flags[0],
                isIdentityVerified: flags[1],
                hasValidEmergencyContacts: flags[2],
                hasStartPoint: flags[3],
                isAppointmentTimeValid: flags[4]
            )
        )
    }

    /// 后端 `OrderCreationService` 先查实名再查紧急联系人；两者同时缺失时
    /// 客户端**不能**先播报紧急联系人，否则用户补完联系人还是会被 403 挡回来。
    func testIdentityGateIsReportedBeforeEmergencyContacts() {
        let gate = BlindBookingGate.firstMissing(
            isBasicProfileComplete: true,
            isIdentityVerified: false,
            hasValidEmergencyContacts: false,
            hasStartPoint: true,
            isAppointmentTimeValid: true
        )
        XCTAssertEqual(gate, .identityVerification)
        XCTAssertNotEqual(gate, .emergencyContacts)

        // 只有实名补上之后，紧急联系人才成为下一个被播报的缺失项。
        XCTAssertEqual(
            BlindBookingGate.firstMissing(
                isBasicProfileComplete: true,
                isIdentityVerified: true,
                hasValidEmergencyContacts: false,
                hasStartPoint: true,
                isAppointmentTimeValid: true
            ),
            .emergencyContacts
        )
    }

    /// 实名档的播报必须给出能走通的下一步（设置 → 实名认证），不能只说"不行"。
    func testIdentityGateMessagePointsToIdentityPage() {
        let message = BlindBookingGate.identityVerification.message
        XCTAssertTrue(message.contains("实名认证"))
        XCTAssertTrue(message.contains("设置"))
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

        // 起点这一步也不许被挡住 —— 挡住等于分步向导走不到第二步。
        viewModel.currentStep = .startPoint
        XCTAssertNil(viewModel.blockingReasonForCurrentStep)
        XCTAssertTrue(viewModel.canAdvanceFromCurrentStep)
    }

    /// 不拦截**不等于**不告知：降级告知必须同时说清「还能怎么下单」和「关着会失去什么」。
    ///
    /// 只说前半句会把一次真实的安全降级说成无关紧要 —— 陪跑过程中志愿者看不到位置、
    /// 云端求助可能发不出去，两件事都发生在盲人当场问不了任何人的时候。
    @MainActor
    func testLocationDeniedNoticeStatesBothTheWorkaroundAndTheSafetyCost() {
        let location = LocationService()
        location.simulateDeviceLocationForTesting(
            CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
            capturedAt: Date(),
            authorized: false
        )
        let viewModel = makeBookingViewModel(locationService: location)

        XCTAssertEqual(
            viewModel.locationDegradationNotice,
            BlindBookingViewModel.locationDeniedNotice,
            "屏幕与耳朵读同一份文案"
        )
        XCTAssertTrue(BlindBookingViewModel.locationDeniedNotice.contains("搜索"), "要说还能手动搜地点")
        XCTAssertTrue(BlindBookingViewModel.locationDeniedNotice.contains("求助"), "要说求助会受影响")

        // 权限正常时不该出现这段告知。
        let authorized = LocationService()
        authorized.simulateMissingDeviceLocationForTesting()
        XCTAssertNil(makeBookingViewModel(locationService: authorized).locationDegradationNotice)
    }

    /// 审阅步的提示语必须覆盖全部五道门槛。
    ///
    /// 按钮禁用状态走的是 `canSubmit`（五道全查）。提示语若只查后两道，
    /// 缺实名或紧急联系人时用户听到的是「提交后系统将为你派单」配一个按不动的按钮 ——
    /// 看不见屏幕的人只会当成「点了没反应」。
    @MainActor
    func testReviewStepBlockingReasonCoversGatesFixedOnOtherPages() {
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
        viewModel.currentStep = .review

        XCTAssertFalse(viewModel.canSubmit, "前提：按钮此时是禁用的")
        XCTAssertEqual(
            viewModel.blockingReasonForCurrentStep,
            BlindBookingGate.emergencyContacts.message,
            "禁用了就必须说得出原因"
        )
    }

    /// 进页面就播报「本页填不了」的门槛，别等用户走到审阅步。
    /// 起点和时间是本页的槽位，缺了不播 —— 分步流程自己会管。
    @MainActor
    func testEntryAnnouncementCoversOnlyGatesFixedElsewhere() {
        let appState = AppState(persistence: AppStatePersistenceFactory.makeIsolatedTest())
        // 昵称未填 ⇒ basicProfile 缺失。
        let viewModel = makeBookingViewModel(appState: appState)
        viewModel.announceEntryGateIfNeeded()
        XCTAssertEqual(viewModel.errorMessage, BlindBookingGate.basicProfile.message)

        // 前四道都过、只差本页的起点时，进页面不该播报。
        appState.updateBlindProfile(BlindProfileResponse(name: "测试用户", verifyStatus: "VERIFIED"))
        appState.updateEmergencyContacts([contact(1, primary: true)])
        // 起点缺失只能用 `locationService: nil` 表达：这个 appState 是 Mock 环境，
        // 而 Mock 通道本来就放行演示坐标当起点（`allowsDemoFallbackAsStartPoint`），
        // 挂任何一个活着的 LocationService 都会让 `.startPoint` 直接通过。
        let onPageOnly = makeBookingViewModel(locationService: nil, appState: appState)
        XCTAssertEqual(onPageOnly.firstMissingGate, .startPoint, "前提：只差本页槽位")
        onPageOnly.announceEntryGateIfNeeded()
        XCTAssertNil(onPageOnly.errorMessage)
    }

    // MARK: - 引导流步骤

    func testOnboardingStepOrder() {
        XCTAssertEqual(
            BlindOnboardingStep.first(
                isBasicProfileComplete: false,
                hasValidEmergencyContacts: false,
                shouldPromptIdentity: true,
                didDismissIdentityPrompt: false
            ),
            .basicProfile
        )

        XCTAssertEqual(
            BlindOnboardingStep.first(
                isBasicProfileComplete: true,
                hasValidEmergencyContacts: false,
                shouldPromptIdentity: true,
                didDismissIdentityPrompt: false
            ),
            .emergencyContacts
        )

        XCTAssertEqual(
            BlindOnboardingStep.first(
                isBasicProfileComplete: true,
                hasValidEmergencyContacts: true,
                shouldPromptIdentity: true,
                didDismissIdentityPrompt: false
            ),
            .identityPrompt
        )
    }

    /// 引导流的「稍后再说」只放行进首页（还能看历史订单、进设置），
    /// **不等于放行下单**——下单拦截在 `BlindBookingGate.identityVerification`。
    func testDismissedIdentityPromptLetsUserThrough() {
        XCTAssertNil(
            BlindOnboardingStep.first(
                isBasicProfileComplete: true,
                hasValidEmergencyContacts: true,
                shouldPromptIdentity: true,
                didDismissIdentityPrompt: true
            )
        )

        XCTAssertNil(
            BlindOnboardingStep.first(
                isBasicProfileComplete: true,
                hasValidEmergencyContacts: true,
                shouldPromptIdentity: false,
                didDismissIdentityPrompt: false
            )
        )
    }
}
