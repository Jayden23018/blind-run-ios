import CoreLocation
import XCTest
@testable import blindRun

@MainActor
final class VoiceOrderWizardStartTimeTests: XCTestCase, VoiceOrderWizardTestSupport {

    // MARK: - 真人手测说过的原话
    //
    // 语料是造出来的，真人说的话不是。这一组收真机手测里实际说过、且当场出过问题的句子，
    // 用来把「到底是 Mock 认不出，还是别的环节断了」钉死 —— 靠推理分不出来，靠断言可以。

    /// 2026-08-06 手测原话：「明天早上八点钟从阳光棕榈园跑」。时间和地点都没被填上。
    func testRealUtteranceFromDeviceTestParsesTheTimeInMock() {
        let transcript = "明天早上八点钟从阳光棕榈园跑"

        let parsed = MockAPIClient.mockVoiceStartTime(in: transcript)

        let time = try? XCTUnwrap(parsed)
        XCTAssertNotNil(parsed, "Mock 认不出这句话的时间，那手测里「时间没识别到」就是 Mock 的锅")
        if let time {
            let components = Calendar.current.dateComponents([.hour, .minute], from: time)
            XCTAssertEqual(components.hour, 8, "「八点钟」应解析成 8 点")
            XCTAssertEqual(components.minute, 0)
        }
    }

    /// **端到端**：真人原话经真正的 `MockAPIClient` 走完整条链路，时间必须落到向导上。
    ///
    /// 上一条只调了 `mockVoiceStartTime`，那是链路的**第一环**。它绿着而真机仍然「识别不了时间点」，
    /// 说明断点在后面几环里：`handleVoiceParseOrder` 组响应 → `mockBackendLocalDateTime` 格式化
    /// → `backendLocalDate` 解回来 → `didCaptureStartTime` 置位。只测第一环等于没测。
    func testRealUtteranceCapturesTheStartTimeThroughTheRealMockClient() async {
        let client = MockAPIClient()
        client.syncSessionFromAppState(token: "mock_jwt_token_test", role: .blind)
        let bookingViewModel = BlindBookingViewModel()
        let wizard = VoiceOrderWizard()
        wizard.configure(
            bookingViewModel: bookingViewModel,
            speechService: SpeechService(), // guard:allow weak-temporary
            speechInputService: SpeechInputService(), // guard:allow weak-temporary
            // 桩仍然实现 `APIClientProtocol`，架一层真的 `VoiceService` 在它上面 ——
            // 这样验的是「向导 → service → 传输」这条真实路径，而不是另造一个假 service
            // 把 service 那一层跳过去。
            voiceOrderService: VoiceOrderService(transport: client)
        )
        wizard.startForTesting(at: .freeform)

        await wizard.submitTranscript("明天早上八点钟从阳光棕榈园跑")

        XCTAssertTrue(
            wizard.didCaptureStartTime,
            "整条链路没把时间带过来 —— 真机「识别不了时间点」就是这一条"
        )
        let spoken = wizard.lastSpokenPrompt ?? ""
        XCTAssertFalse(spoken.contains("预约时间还没说"), "读回仍然说没听到时间：\(spoken)")
    }

    /// iOS 的 `SFSpeechRecognizer` 对同一句话有多种输出形式，Mock 必须都认。
    ///
    /// 诊断用：真机说「明天早上八点钟」而时间抽不出，但端到端用例是绿的 —— 说明识别出的字面
    /// 不是我们假设的那个。把现实中可能的形式一次全列出来，绿的排除、红的就是断点。
    func testRealisticRecognizerOutputsForTheSameSpokenTime() {
        let variants = [
            "明天早上八点钟从阳光棕榈园跑",
            "明天早上8点钟从阳光棕榈园跑",
            "明天早上8点从阳光棕榈园跑",
            "明天早上8:00从阳光棕榈园跑",
            "明天早上8：00从阳光棕榈园跑",
            "明天早上八点半从阳光棕榈园跑",
            "明天上午八点从阳光棕榈园跑",
            "明天早上八点，从阳光棕榈园跑"
        ]
        var failures: [String] = []
        for variant in variants where MockAPIClient.mockVoiceStartTime(in: variant) == nil {
            failures.append(variant)
        }
        XCTAssertTrue(failures.isEmpty, "这些识别形式抽不出时间：\(failures)")
    }

    /// 冒号形式解出来的必须是**正确的时分**，不能只是「没返回 nil」。
    func testColonClockTimeResolvesToTheRightHourAndMinute() {
        let cases: [(String, Int, Int)] = [
            ("明天早上8:00出发", 8, 0),
            ("明天早上8：30出发", 8, 30),
            ("明天18:45出发", 18, 45),
            // 时段词对冒号形式同样生效：识别成 `3:00` 时「下午」是唯一的 12/24 制线索
            ("明天下午3:00出发", 15, 0)
        ]
        for (transcript, hour, minute) in cases {
            guard let parsed = MockAPIClient.mockVoiceStartTime(in: transcript) else {
                XCTFail("「\(transcript)」抽不出时间")
                continue
            }
            let components = Calendar.current.dateComponents([.hour, .minute], from: parsed)
            XCTAssertEqual(components.hour, hour, "「\(transcript)」的小时不对")
            XCTAssertEqual(components.minute, minute, "「\(transcript)」的分钟不对")
        }
    }

    /// 「8点半」的半小时不能被静默抹掉。
    ///
    /// 原来只查中文形式「八点半」，识别输出阿拉伯数字时半小时被悄悄归零 ——
    /// 对听不见屏幕的人，静默改掉他说的时间就是一次无声的篡改。
    func testHalfPastIsRecognisedForArabicDigitsToo() {
        for transcript in ["明天早上8点半出发", "明天早上八点半出发"] {
            guard let parsed = MockAPIClient.mockVoiceStartTime(in: transcript) else {
                XCTFail("「\(transcript)」抽不出时间")
                continue
            }
            XCTAssertEqual(
                Calendar.current.component(.minute, from: parsed), 30,
                "「\(transcript)」的半小时被抹掉了"
            )
        }
    }

    /// 剥壳与地理编码是**两件事**，这条把它们分开钉住。
    ///
    /// 2026-08-08 之前这里断言的是「抽不出」，理由写的是「阳光棕榈园不在 Mock 的关键词表里」——
    /// 那句话把两件事混成了一件：抽不出的真实原因是当时的壳只手列了 4 对，`从…跑` 不在里面。
    /// 关键词表管的是**下一步**（span → 坐标），跟能不能剥壳无关。
    ///
    /// 现在壳照抄后端 `ADDRESS_SPAN` 的叉积，span 抽得出；而 `mockVoicePlaces` 里仍然没有这个
    /// 地点，所以坐标依旧查不到 —— 这正是语料 `_address_note` 描述的线上同形场景
    /// 「抽到 span 但正向编码失败」，结果该是 `missing` 含 `ADDRESS`，而不是当用户没说起点。
    func testAddressSpanIsExtractedEvenWhenTheMockCannotGeocodeIt() {
        XCTAssertEqual(
            MockAPIClient.mockVoiceAddressSpan(in: "明天早上八点钟从阳光棕榈园跑"),
            "阳光棕榈园",
            "壳是「从…跑」，剥壳这一步与关键词表无关"
        )
    }

    // MARK: - 不许编时间
    //
    // 2026-08-06 用户原话：「这个默认配置我觉得不应该给它默认配置，除了地点有默认地点之外，
    // 其他的为什么能默认呢」。`appointmentTime` 的初值是 `Date()`，抽不出时间时读回会念出一个
    // 用户从没说过的具体时刻，再补一句「需至少在 30 分钟后」—— 听不见屏幕的人只会记住前半句。

    /// 没抽到开始时间时，读回**不得念出任何具体时刻**。
    func testReadbackSaysTheTimeIsMissingInsteadOfInventingOne() async {
        let stub = VoiceOrderAPIClientStub()
        stub.parseOrderResponses = [
            ParseVoiceOrderResponse(
                plannedStartTime: nil, durationMinutes: nil, address: nil,
                latitude: nil, longitude: nil,
                missing: [.startTime], needReask: nil, ttsText: nil
            )
        ]
        // bookingViewModel 必须本地强持有：向导那侧是 `weak`，不持有的话 `askCurrentStep`
        // 会走 `else` 分支念 `Step.confirm.prompt` 兜底文案，整单一个字都不念 —— 用例
        // 测的就不是读回内容了。本仓库 `weak-temporary` 守卫说的就是这个坑。
        let bookingViewModel = BlindBookingViewModel()
        let wizard = makeWizard(stub: stub, bookingViewModel: bookingViewModel, startingAt: .freeform)

        await wizard.submitTranscript("我想去人民广场")

        let spoken = wizard.lastSpokenPrompt ?? ""
        XCTAssertTrue(spoken.contains("预约时间还没说"), "没说就要说没说：\(spoken)")
        XCTAssertFalse(wizard.didCaptureStartTime)
        XCTAssertFalse(
            spoken.contains("预约时间：20"),
            "念出了一个用户从没说过的具体时刻：\(spoken)"
        )
    }

    /// 缺开始时间时「确认」不生效 —— 不能凭一句「确认」就派一张用户没说过时间的单。
    func testConfirmIsRefusedWhenTheStartTimeWasNeverSpoken() async {
        let bookingViewModel = BlindBookingViewModel()
        let wizard = makeWizard(
            stub: VoiceOrderAPIClientStub(),
            bookingViewModel: bookingViewModel,
            startingAt: .confirm,
            didCaptureStartTime: false
        )

        await wizard.submitTranscript("确认")

        XCTAssertNil(wizard.createdOrder, "用户从没说过时间，不能成单")
        XCTAssertTrue(wizard.isRunning, "拦住之后要留在语音里，而不是静默结束")
        XCTAssertTrue((wizard.lastSpokenPrompt ?? "").contains("重说"), "必须给出唯一可行的出路")
    }
}
