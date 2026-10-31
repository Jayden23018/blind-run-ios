import XCTest
@testable import blindRun

/// 下单表单的读屏可用性（#295）。这几条钉的是 view model 里决定「念什么 / 默认值是什么」的部分；
/// 焦点落点、控件是否可调节只能真机开 VoiceOver 看，单测摸不到。
@MainActor
final class BlindBookingFormAccessibilityTests: XCTestCase {

    private func makeViewModel(speechService: SpeechService = SpeechService()) -> BlindBookingViewModel {
        let viewModel = BlindBookingViewModel()
        viewModel.configureForTesting(speechService: speechService)
        return viewModel
    }

    private func makePlace() -> ResolvedPlace {
        ResolvedPlace(
            id: "poi-1",
            title: "科技园地铁站",
            addressText: "深圳市南山区科技园地铁站 A 口",
            latitude: 22.5401,
            longitude: 113.9345,
            source: .manual
        )
    }

    // MARK: - 默认时间过期

    /// 默认值只比下限多 1 分钟，读屏用户在第 1 步停留几分钟后它就过期。
    /// 进入第 2 步时必须重新取最早可约时刻，否则一进去就是红字加灰掉的下一步。
    func testEnteringAppointmentStepReseedsAnExpiredDefaultTime() {
        let viewModel = makeViewModel()
        viewModel.selectedStartPlace = makePlace()
        viewModel.appointmentTime = Date().addingTimeInterval(-5 * 60)

        viewModel.moveToNextStep()

        XCTAssertEqual(viewModel.currentStep, .appointmentTime)
        XCTAssertGreaterThanOrEqual(viewModel.appointmentTime, viewModel.minimumAppointmentTime)
        XCTAssertNotEqual(viewModel.appointmentTimeProblem, .tooSoon)
    }

    /// 反方向：用户自己选的、仍然合法的时间不许被动。
    func testEnteringAppointmentStepKeepsAValidChosenTime() {
        let viewModel = makeViewModel()
        viewModel.selectedStartPlace = makePlace()
        let chosen = BookingTimeFixture.daytime()
        viewModel.appointmentTime = chosen

        viewModel.moveToNextStep()

        XCTAssertEqual(viewModel.appointmentTime, chosen)
    }

    // MARK: - Stepper 步进

    func testShiftAppointmentMovesByRequestedMinutes() {
        let viewModel = makeViewModel()
        let start = BookingTimeFixture.daytime()
        viewModel.appointmentTime = start

        viewModel.shiftAppointment(byMinutes: 15)
        XCTAssertEqual(viewModel.appointmentTime, start.addingTimeInterval(15 * 60))

        viewModel.shiftAppointment(byMinutes: 24 * 60)
        XCTAssertEqual(viewModel.appointmentTime, start.addingTimeInterval(15 * 60 + 24 * 3600))
    }

    func testShiftAppointmentNeverLeavesTheDatePickerRange() {
        let viewModel = makeViewModel()

        viewModel.appointmentTime = viewModel.minimumAppointmentTime.addingTimeInterval(120)
        viewModel.shiftAppointment(byMinutes: -24 * 60)
        XCTAssertGreaterThanOrEqual(viewModel.appointmentTime, viewModel.minimumAppointmentTime, "往前步进不能越过最早可约")

        viewModel.appointmentTime = viewModel.maximumAppointmentTime.addingTimeInterval(-3600)
        viewModel.shiftAppointment(byMinutes: 24 * 60)
        XCTAssertLessThanOrEqual(viewModel.appointmentTime, viewModel.maximumAppointmentTime, "往后步进不能越过最远可约")
    }

    /// 按天越界时原地不动：夹到边界会连时刻一起改掉，用户以为只动了日期（#295 代码审查）。
    func testDayStepPastTheRangeLeavesTheTimeUntouched() {
        let viewModel = makeViewModel()
        let chosen = viewModel.minimumAppointmentTime.addingTimeInterval(3 * 3600)
        viewModel.appointmentTime = chosen

        viewModel.shiftAppointment(byMinutes: -BlindBookingViewModel.minutesPerDay)

        XCTAssertEqual(viewModel.appointmentTime, chosen)
    }

    // MARK: - 出发地点卡

    /// 屏幕写「正在获取当前位置」时，读屏不能念「出发地点，」。
    func testStartPointDisplayTextFallsBackWhileAddressIsUnknown() {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.resolvedStartLocationDescription, "")
        XCTAssertEqual(viewModel.startPointDisplayText, "正在获取当前位置")

        viewModel.selectedStartPlace = makePlace()
        XCTAssertEqual(viewModel.startPointDisplayText, "深圳市南山区科技园地铁站 A 口")
    }

    // MARK: - 提交前的进度播报

    func testFormSubmitAnnouncesProgressWhenSubmittable() async {
        let speechService = SpeechService()
        let viewModel = makeViewModel(speechService: speechService)
        viewModel.selectedStartPlace = makePlace()
        viewModel.appointmentTime = BookingTimeFixture.daytime()
        XCTAssertTrue(viewModel.canSubmit)

        _ = await viewModel.submitAnnouncingProgress()

        XCTAssertEqual(speechService.lastVoiceOverAnnouncement, "正在提交预约。")
    }

    /// 门槛没过时不能说「正在提交」—— 接下来念的是拒绝原因，先说提交中就是撒谎。
    func testFormSubmitStaysSilentWhenGateIsNotMet() async {
        let speechService = SpeechService()
        let viewModel = makeViewModel(speechService: speechService)
        viewModel.appointmentTime = BookingTimeFixture.daytime()
        XCTAssertFalse(viewModel.canSubmit, "没有出发地点")

        _ = await viewModel.submitAnnouncingProgress()

        XCTAssertNotEqual(speechService.lastVoiceOverAnnouncement, "正在提交预约。")
    }
}
