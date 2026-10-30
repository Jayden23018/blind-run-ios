import CoreLocation
import XCTest
@testable import blindRun

/// 读回结尾「说确认就下单」只在关键槽位齐了才给：开始时间与出发地点（#558 走查卡死 2），
/// 以及录音中「重复一遍」先停麦（卡死 1）。从 `VoiceOrderWizardTests` 拆出来：那个类超了 SwiftLint 上限。
@MainActor
final class VoiceOrderWizardStartPointTests: XCTestCase {
    /// 抽到了时间就正常放行 —— 上面那条拦截不能宽到把正常流程也挡了。
    func testConfirmProceedsOnceTheStartTimeWasCaptured() async {
        let stub = VoiceOrderAPIClientStub()
        stub.parseOrderResponses = [Self.timeOnlyResponse(hoursFromNow: 24)]
        // 同上：不强持有的话下面那条断言会因为兜底文案恰好也含「说「确认」就下单」而**假通过**。
        let bookingViewModel = BlindBookingViewModel()
        // 起点也是关键槽位（#558）：这条用例验的是「时间齐了就放行」，起点得先有。
        bookingViewModel.selectedStartPlace = Self.peopleSquare
        let wizard = makeWizard(stub: stub, bookingViewModel: bookingViewModel, startingAt: .freeform)

        await wizard.submitTranscript("明天早上八点从人民广场出发")

        XCTAssertTrue(wizard.didCaptureStartTime)
        let spoken = wizard.lastSpokenPrompt ?? ""
        XCTAssertTrue(spoken.contains("这次的预约是："), "念的必须是整单读回而不是兜底提问：\(spoken)")
        XCTAssertTrue(spoken.contains("说「确认」就下单"), "抽到时间后就该正常给出确认这条出路：\(spoken)")
        XCTAssertFalse(spoken.contains("预约时间还没说"))
    }

    /// 起点也是关键槽位（#558 走查卡死 2）。定位还没拿到、或「精确位置」关着时没有可用起点：
    /// 读回不许教「说确认」，说了「确认」也不许提交。以前会提交、失败、语音面板消失，
    /// 人被送到表单上，只听到一句「请选择出发地点。」。
    func testConfirmIsRefusedWhenThereIsNoUsableStartPoint() async {
        let noFix: (LocationService) -> Void = { $0.simulateMissingDeviceLocationForTesting() }
        let preciseOff: (LocationService) -> Void = {
            $0.simulateDeviceLocationForTesting(
                CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737), capturedAt: Date()
            )
            $0.simulatePreciseLocationOffForTesting()
        }
        for (label, setUp) in [("定位还没拿到", noFix), ("精确位置关闭", preciseOff)] {
            let locationService = LocationService()
            setUp(locationService)
            let speechService = SpeechService()
            let bookingViewModel = BlindBookingViewModel()
            bookingViewModel.configureForTesting(speechService: speechService, locationService: locationService)
            XCTAssertNil(bookingViewModel.resolvedStartPlace, "\(label)：前提是没有可用起点")

            let stub = VoiceOrderAPIClientStub()
            stub.parseOrderResponses = [Self.timeOnlyResponse(hoursFromNow: 24)]
            let wizard = makeWizard(stub: stub, bookingViewModel: bookingViewModel, startingAt: .freeform)

            await wizard.submitTranscript("明天早上八点跑一个小时")

            XCTAssertTrue(wizard.didCaptureStartTime, "\(label)：前提是时间抽到了，拦住确认的只能是起点")
            let readback = wizard.lastSpokenPrompt ?? ""
            XCTAssertFalse(readback.contains("说「确认」就下单"), "\(label)：没有起点还教说确认：\(readback)")
            XCTAssertTrue(readback.contains(VoiceOrderWizard.missingStartPointMessage), "\(label)：\(readback)")
            XCTAssertFalse(readback.contains("正在获取当前位置"), "\(label)：等不到的位置不许说成正在获取：\(readback)")

            await wizard.submitTranscript("确认")

            XCTAssertNil(wizard.createdOrder, "\(label)")
            XCTAssertTrue(wizard.isRunning, "\(label)：拦住之后要留在语音里，不许把人送去表单")
            XCTAssertTrue(
                (wizard.lastSpokenPrompt ?? "").contains(VoiceOrderWizard.missingStartPointMessage),
                "\(label)：说了确认要告诉他缺的是出发地点"
            )
        }
    }

    /// 读回时还没有起点、确认前定位才到：用户没听过这个起点，「确认」要先重念读回，不许直接提交（#558 审查）。
    func testConfirmRereadsWhenTheStartPointAppearedAfterTheReadback() async {
        let locationService = LocationService()
        locationService.simulateMissingDeviceLocationForTesting()
        let bookingViewModel = BlindBookingViewModel()
        bookingViewModel.configureForTesting(speechService: SpeechService(), locationService: locationService)
        let stub = VoiceOrderAPIClientStub()
        stub.parseOrderResponses = [Self.timeOnlyResponse(hoursFromNow: 24)]
        let wizard = makeWizard(stub: stub, bookingViewModel: bookingViewModel, startingAt: .freeform)
        await wizard.submitTranscript("明天早上八点跑一个小时")
        XCTAssertTrue((wizard.lastSpokenPrompt ?? "").contains(VoiceOrderWizard.missingStartPointMessage), "前提")

        bookingViewModel.selectedStartPlace = Self.peopleSquare // 起点在读回之后才有
        await wizard.submitTranscript("确认")

        XCTAssertTrue(wizard.isRunning, "用户没听过的起点不许直接提交")
        let reread = wizard.lastSpokenPrompt ?? ""
        XCTAssertTrue(reread.contains("人民广场"), "重念要把新起点念出来：\(reread)")
        XCTAssertTrue(reread.contains("说「确认」就下单"), reread)
    }

    /// 确认轮断网、关键槽位又不齐：提示不许教「说确认」—— 说了也不生效（#558 审查）。
    func testConfirmRoundNetworkFailureDoesNotTeachConfirmWhileSlotsAreMissing() async {
        let bookingViewModel = BlindBookingViewModel()
        let stub = VoiceOrderAPIClientStub()
        stub.error = .serverError(ErrorResponse(code: "INTERNAL_ERROR", message: "boom"))
        let wizard = makeWizard(stub: stub, bookingViewModel: bookingViewModel, startingAt: .confirm)

        await wizard.submitTranscript("把时间往后挪一挪吧")

        let spoken = wizard.lastSpokenPrompt ?? ""
        XCTAssertFalse(spoken.contains("说「确认」"), "缺时间还教说确认：\(spoken)")
        XCTAssertTrue(spoken.contains(VoiceOrderWizard.missingStartTimeMessage), spoken)
    }

    /// 录音中按「重复一遍」要先停麦再念（#558 走查卡死 1）。以前麦克风开着就念，整句轮的提示里有
    /// 示例句「明天早上八点从人民广场出发」，会被录成用户说的话。
    /// 停麦还不许触发完成回调 —— 那会走一次空转录的 `handle`，被记成一次「没听清」重问。
    func testRepeatWhileRecordingStopsTheMicrophoneBeforeSpeaking() {
        let speechService = SpeechService()
        let speechInputService = SpeechInputService()
        let bookingViewModel = BlindBookingViewModel()
        let wizard = VoiceOrderWizard()
        wizard.configure(
            bookingViewModel: bookingViewModel,
            speechService: speechService,
            speechInputService: speechInputService,
            voiceOrderService: VoiceOrderService(transport: VoiceOrderAPIClientStub())
        )
        wizard.startForTesting(at: .freeform)
        var completions = 0
        speechInputService.startRecognitionForTesting(field: .voiceOrderFreeform, onCompletion: { _ in completions += 1 })
        XCTAssertTrue(speechInputService.isListening, "前提：麦克风开着")

        wizard.repeatCurrentPrompt()

        XCTAssertFalse(speechInputService.isListening, "念提示之前必须先停麦，否则提示会被录成用户说的话")
        XCTAssertEqual(completions, 0, "停麦不许触发完成回调")
        XCTAssertEqual(wizard.reaskCount, 0, "重听不是没听清")
        XCTAssertEqual(wizard.lastSpokenPrompt, VoiceOrderWizard.Step.freeform.prompt)
        // 重新开麦的那个 Task 在下一次 runloop 才跑；先停掉，免得它在单测里去要真实的麦克风授权。
        wizard.stop()
    }

    fileprivate static let peopleSquare = ResolvedPlace(
        id: "people-square", title: "人民广场", addressText: "上海市黄浦区人民广场",
        latitude: 31.2304, longitude: 121.4737, source: .manual
    )

    /// 确认走的是提交路径而不是解析端点。
    ///
    /// `didCaptureStartTime: true` 与起点都不能省：缺哪个「确认」都被拦下，就变成在测拦截而不是提交。
    /// 断言落在「正在提交订单。」这一句上：`submitConfirmedBooking` 拿不到 view model 时走不到它（#601），
    /// 只断 `isRunning` 的话，view model 被释放了也是绿的。
    func testAffirmativeTakesTheSubmitPathInsteadOfParsing() async {
        let stub = VoiceOrderAPIClientStub()
        let bookingViewModel = BlindBookingViewModel.withStartPointForTesting()
        let speechService = SpeechService()
        let wizard = makeWizard(
            stub: stub, bookingViewModel: bookingViewModel, speechService: speechService,
            startingAt: .confirm, didCaptureStartTime: true
        )

        await wizard.submitTranscript("确认")

        XCTAssertFalse(wizard.isRunning, "提交后不得继续占着麦克风")
        XCTAssertTrue(speechService.spokenHistoryForTesting.contains("正在提交订单。"), "没有走到提交：\(speechService.spokenHistoryForTesting)")
        XCTAssertTrue(stub.paths.isEmpty, "确认判定不走后端：\(stub.paths)")
    }

    /// 只抽到了开始时间、其余全空的一条 `/voice/parse` 响应。
    private static func timeOnlyResponse(hoursFromNow hours: Double) -> ParseVoiceOrderResponse {
        ParseVoiceOrderResponse(
            plannedStartTime: DateFormatter.aidRunBackendLocalDateTime.string(
                from: Date().addingTimeInterval(hours * 3600)
            ),
            durationMinutes: nil, address: nil, latitude: nil, longitude: nil,
            missing: nil, needReask: nil, ttsText: nil
        )
    }

    /// ⚠️ wizard 对 view model 是 weak：调用方必须自己持有传进来的 `bookingViewModel`。
    private func makeWizard(
        stub: VoiceOrderAPIClientStub,
        bookingViewModel: BlindBookingViewModel,
        speechService: SpeechService = SpeechService(),
        startingAt step: VoiceOrderWizard.Step,
        didCaptureStartTime: Bool = false
    ) -> VoiceOrderWizard {
        let wizard = VoiceOrderWizard()
        wizard.configure(
            bookingViewModel: bookingViewModel,
            // 两个语音服务在 wizard 侧都是 weak，不攥住等于传 nil。要读念过什么的用例自己攥住 `speechService` 传进来。
            speechService: speechService,
            speechInputService: SpeechInputService(), // guard:allow weak-temporary
            voiceOrderService: VoiceOrderService(transport: stub)
        )
        wizard.startForTesting(at: step, didCaptureStartTime: didCaptureStartTime)
        return wizard
    }
}

extension BlindBookingViewModel {
    /// 起点已定的 view model。走「确认」提交路径的用例要用它：没有起点时确认会被拦下（#558），走不到提交（#601）。
    static func withStartPointForTesting() -> BlindBookingViewModel {
        let viewModel = BlindBookingViewModel()
        viewModel.selectedStartPlace = VoiceOrderWizardStartPointTests.peopleSquare
        return viewModel
    }
}
