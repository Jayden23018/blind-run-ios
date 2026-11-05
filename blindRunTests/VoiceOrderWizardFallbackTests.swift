import CoreLocation
import XCTest
@testable import blindRun

@MainActor
final class VoiceOrderWizardFallbackTests: XCTestCase, VoiceOrderWizardTestSupport {

    // MARK: - 网络失败

    // 「解析端点报错就交回表单」那条用例随逐项修改一起删除（2026-08-06）：它测的是
    // `parseSingleSlot` 的 APIError 分支。整句轮**刻意相反** —— 传输失败被吞掉、仍然读回，
    // 由 `testFreeformSwallowsTransportFailuresAndStillReadsBackDefaults` 与
    // `testFreeformAnnouncesThatParsingFailedBeforeReadingBackDefaults` 覆盖。

    /// 等待期间必须出声。不出声的话，全盲用户在结束音之后听到的是最长 8 秒的绝对静默 ——
    /// 这正是我们用来论证要做 `RecordingCue` 的那条 AppleVis 抱怨（「按下之后全程没有任何反馈」），
    /// 只守住起止两端等于只守了一半。
    ///
    /// 断言点必须在**请求发出的那一刻**：等 `submitTranscript` 返回时，读回已经把它覆盖掉了。
    func testNetworkRoundsSayTheyAreWorkingInsteadOfGoingSilent() async {
        let speechService = SpeechService()
        var heardWhileWaiting: [String] = []

        let freeformStub = VoiceOrderAPIClientStub()
        freeformStub.parseOrderResponses = [
            ParseVoiceOrderResponse(
                plannedStartTime: nil, durationMinutes: nil, address: nil,
                latitude: nil, longitude: nil, missing: nil, needReask: nil, ttsText: nil
            )
        ]
        freeformStub.onRequest = { heardWhileWaiting.append(speechService.lastSpokenText ?? "") }
        let freeformWizard = makeWizard(
            stub: freeformStub, speechService: speechService, startingAt: .freeform
        )
        await freeformWizard.submitTranscript("明天早上八点跑一个小时")

        let secondStub = VoiceOrderAPIClientStub()
        secondStub.parseOrderResponses = [
            ParseVoiceOrderResponse(
                plannedStartTime: "2026-08-05T08:00:00", durationMinutes: nil,
                address: nil, latitude: nil, longitude: nil,
                missing: nil, needReask: nil, ttsText: nil
            )
        ]
        secondStub.onRequest = { heardWhileWaiting.append(speechService.lastSpokenText ?? "") }
        let secondWizard = makeWizard(
            stub: secondStub, speechService: speechService, startingAt: .freeform
        )
        await secondWizard.submitTranscript("明天早上八点")

        XCTAssertEqual(heardWhileWaiting.count, 2, "两轮都该发出请求")
        for heard in heardWhileWaiting {
            XCTAssertTrue(heard.contains("正在识别"), "等待期间不得静默，实际听到：「\(heard)」")
        }
    }

    /// 等待提示**不得**顶掉 `lastSpokenPrompt` —— 顶掉之后「重复一遍」念的就是「正在提交订单」，
    /// 而不是用户真正想重听的那一段。
    ///
    /// 断言点选提交轮，是因为**只有这一轮之后没有任何东西会再覆盖 `lastSpokenPrompt`**：
    /// 解析轮无论成功、重问还是降级，随后都会 `speak` 一次把它盖掉，在那里断言等于什么都没测。
    /// `submit()` 失败时播的错误走 `speechService` 而不是向导的 `speak`，所以这里应当保持原样。
    ///
    /// `bookingViewModel` 必须在本地强持有：向导那一侧是 `weak`，不持有的话
    /// `submitConfirmedBooking` 会停在 `guard let` 上，用例根本走不到要测的那一行还照样绿。
    func testParsingNoticeDoesNotBecomeWhatRepeatSpeaks() async {
        let bookingViewModel = BlindBookingViewModel()
        // 起点是关键槽位（#558）：没有它「确认」在提交前就被拦下，走不到等待提示那一步。要在建向导前设好。
        bookingViewModel.selectedStartPlace = ResolvedPlace(id: "people-square", title: "人民广场", addressText: "上海市黄浦区人民广场", latitude: 31.2304, longitude: 121.4737, source: .manual)
        let wizard = makeWizard(
            stub: VoiceOrderAPIClientStub(),
            bookingViewModel: bookingViewModel,
            startingAt: .confirm,
            didCaptureStartTime: true
        )

        await wizard.submitTranscript("确认")

        XCTAssertNil(
            wizard.lastSpokenPrompt,
            "等待提示不该进「重复一遍」的记忆，实际留下：「\(wizard.lastSpokenPrompt ?? "")」"
        )
    }

    // MARK: - 不许把人关在没有出口的循环里
    //
    // 「时间抽不出就不许确认」这条规则必须配一个出口，否则解析这一环一坏就成死循环：
    // 说一整句 → 抽不出时间 → 不给确认 → 「请说重说」→ 重说 → 还是抽不出 → 无限。
    // 2026-08-06 手测就是这么卡住的：用户第二遍明确说了时间，仍然抽不到。
    // 对看不见屏幕的人，没有出口的循环比一条错误信息糟得多。

    /// 端点根本不存在时**一次读回都不做**，直接交回表单 —— 重说一万遍也一样。
    ///
    /// ⚠️ **2026-08-18 更正**：这条用例原来的说明写着「生产上 `/api/orders/voice/parse` 恒 404」，
    /// 那是 2026-08-06 的一次观测，**现在不成立** —— 生产 `GET /v3/api-docs` 里列着该端点。
    /// 用例本身照旧有效：它测的是「端点 404 时不许把人关在循环里」这个**类别**，
    /// 不依赖那个具体故障今天还在不在。
    func testMissingParseEndpointFallsBackImmediatelyInsteadOfOfferingARetry() async {
        let stub = VoiceOrderAPIClientStub()
        stub.error = APIError.serverError(
            ErrorResponse(code: "NOT_FOUND", message: "请求的资源不存在")
        )
        let bookingViewModel = BlindBookingViewModel()
        let wizard = makeWizard(stub: stub, bookingViewModel: bookingViewModel, startingAt: .freeform)

        await wizard.submitTranscript("明天早上八点钟从阳光棕榈园跑")

        XCTAssertFalse(wizard.isRunning, "端点不存在，重说一万遍也一样，不该留在语音里")
        let fallback = wizard.fallbackMessage ?? ""
        XCTAssertTrue(fallback.contains("表单"), "必须给出真正的出路：\(fallback)")
        XCTAssertFalse(
            fallback.contains("重说"),
            "不得建议重说 —— 那是把死路包装成活路：\(fallback)"
        )
    }

    /// 解析活着但连着两轮都抽不到时间，同样要交回表单，而不是第三次说「请说重说」。
    func testTwoRoundsWithoutAStartTimeEndOnTheVoiceStageInsteadOfTheForm() async {
        let stub = VoiceOrderAPIClientStub()
        let noTime = ParseVoiceOrderResponse(
            plannedStartTime: nil, durationMinutes: nil, address: nil,
            latitude: nil, longitude: nil,
            missing: [.startTime], needReask: nil, ttsText: nil
        )
        stub.parseOrderResponses = [noTime, noTime]
        let bookingViewModel = BlindBookingViewModel()
        let wizard = makeWizard(stub: stub, bookingViewModel: bookingViewModel, startingAt: .freeform)

        await wizard.submitTranscript("我想去人民广场")
        XCTAssertTrue(wizard.isRunning, "第一次抽不到时间应该给一次重说的机会")

        await wizard.submitTranscript("重说")
        await wizard.submitTranscript("还是没说时间")

        XCTAssertFalse(wizard.isRunning, "第二次还抽不到就不能再让人重说了")
        // 后端 #502：没听清不再送去表单 —— 全盲用户基本不可能用表单下单。
        XCTAssertNil(wizard.fallbackMessage)
        XCTAssertEqual(wizard.endedMessage, VoiceOrderWizard.notUnderstoodMessage)
        XCTAssertEqual(wizard.lastSpokenPrompt, "暂时没听清，你可以稍后再试，或者让身边的人帮忙。")
        XCTAssertTrue(wizard.endedAfterFailure, "没听清结束才在面板上递「直接下单」")
    }

    /// 出口不能宽到把正常流程也带走：中间成功抽到过时间，计数要清零。
    func testCapturingAStartTimeResetsTheDeadEndCounter() async {
        let stub = VoiceOrderAPIClientStub()
        let plannedStart = DateFormatter.aidRunBackendLocalDateTime.string(
            from: Date().addingTimeInterval(3600 * 24)
        )
        stub.parseOrderResponses = [
            ParseVoiceOrderResponse(
                plannedStartTime: nil, durationMinutes: nil, address: nil,
                latitude: nil, longitude: nil, missing: [.startTime], needReask: nil, ttsText: nil
            ),
            ParseVoiceOrderResponse(
                plannedStartTime: plannedStart, durationMinutes: nil, address: nil,
                latitude: nil, longitude: nil, missing: nil, needReask: nil, ttsText: nil
            )
        ]
        let bookingViewModel = BlindBookingViewModel()
        let wizard = makeWizard(stub: stub, bookingViewModel: bookingViewModel, startingAt: .freeform)

        await wizard.submitTranscript("我想去人民广场")
        await wizard.submitTranscript("重说")
        await wizard.submitTranscript("明天早上八点从人民广场出发")

        XCTAssertTrue(wizard.isRunning, "这一轮抽到时间了，不该被上一轮的失败计数带走")
        XCTAssertTrue(wizard.didCaptureStartTime)
    }

    // MARK: - 沉默不等于同意默认值
    //
    // 2026-08-06 真机：用户没听到起音提示、不知道麦克风开了，沉默着等；8 秒后系统判定
    // 「他想用默认值」，念了一整单他从没说过的预约。原话是「他也没有经过我的同意」。
    // 沉默的原因绝大多数是没听见 / 没听懂 / 还在想，不是「我接受默认值」。

    /// 整句那一轮**什么都没听到**时必须重问，不能直接跳去读回默认整单。
    func testTotalSilenceInFreeformReasksInsteadOfReadingBackDefaults() async {
        let wizard = makeWizard(stub: VoiceOrderAPIClientStub(), startingAt: .freeform)

        wizard.handleCompletionForTesting(
            SpeechInputCompletion(
                field: .voiceOrderFreeform,
                recognizedText: "",
                reason: .silenceTimeout(hadDetectedSound: false)
            )
        )

        XCTAssertEqual(wizard.step, .freeform, "没听到任何话就跳去读回，等于替用户决定了整张订单")
        XCTAssertEqual(wizard.reaskCount, 1)
        XCTAssertNil(wizard.createdOrder)
    }

    /// 重问那句要**带例句** —— 听不见屏幕的人缺的是「我该说什么」，不是「再说一次」。
    /// 调研 §6.6 引 Google 的错误处理规范：例子比解释有效。
    func testFreeformSilenceReaskGivesAnExample() async {
        let wizard = makeWizard(stub: VoiceOrderAPIClientStub(), startingAt: .freeform)

        wizard.handleCompletionForTesting(
            SpeechInputCompletion(
                field: .voiceOrderFreeform,
                recognizedText: "",
                reason: .silenceTimeout(hadDetectedSound: false)
            )
        )

        let spoken = wizard.lastSpokenPrompt ?? ""
        XCTAssertTrue(spoken.contains("没有听到你说话"), "实际：\(spoken)")
        XCTAssertTrue(spoken.contains("比如"), "重问必须给例句，实际：\(spoken)")
    }

    /// 连续沉默不会无限重问：两次之后交回表单，而不是把人按在麦克风前。
    func testRepeatedSilenceEventuallyEndsOnTheVoiceStage() async {
        let wizard = makeWizard(stub: VoiceOrderAPIClientStub(), startingAt: .freeform)
        let silence = SpeechInputCompletion(
            field: .voiceOrderFreeform,
            recognizedText: "",
            reason: .silenceTimeout(hadDetectedSound: false)
        )

        for _ in 0..<VoiceOrderWizard.maximumReasksPerSlot {
            wizard.handleCompletionForTesting(silence)
        }

        XCTAssertFalse(wizard.isRunning, "连续听不到就该停下，不能一直重问")
        XCTAssertNil(wizard.fallbackMessage, "没听清不送去表单（#502）")
        XCTAssertEqual(wizard.endedMessage, VoiceOrderWizard.notUnderstoodMessage)
        XCTAssertTrue(wizard.endedAfterFailure)
        XCTAssertNil(wizard.createdOrder)
    }

    /// 结束态之后再开一轮，结束态必须清干净 —— 否则界面判「已结束」，又递出上一轮的「直接下单」。
    /// 走真实的 `start()`（门槛构造同 `testStartProceedsWhenOnlyTheVoiceFilledSlotsAreMissing`）。
    func testStartingAgainClearsTheEndedState() async {
        let appState = AppState(persistence: AppStatePersistenceFactory.makeIsolatedTest())
        appState.updateBlindProfile(BlindProfileResponse(name: "测试用户", verifyStatus: "VERIFIED"))
        appState.updateEmergencyContacts([
            EmergencyContactResponse(id: 1, name: "联系人1", phone: "13900139001", relationship: "家人", isPrimary: true)
        ])
        let viewModel = BlindBookingViewModel()
        viewModel.configureForTesting(speechService: SpeechService(), locationService: nil, appState: appState)
        let wizard = makeUnstartedWizard(bookingViewModel: viewModel)
        XCTAssertTrue(wizard.start(), "前提：门槛已过")
        let silence = SpeechInputCompletion(
            field: .voiceOrderFreeform,
            recognizedText: "",
            reason: .silenceTimeout(hadDetectedSound: false)
        )
        for _ in 0..<VoiceOrderWizard.maximumReasksPerSlot {
            wizard.handleCompletionForTesting(silence)
        }
        XCTAssertTrue(wizard.endedAfterFailure, "前提：没听清进了结束态")

        XCTAssertTrue(wizard.start())

        XCTAssertNil(wizard.endedMessage)
        XCTAssertFalse(wizard.endedAfterFailure)
        XCTAssertTrue(wizard.isRunning)
    }

    /// 识别**起不来**（首次在系统弹窗里拒了语音 / 麦克风权限，回调原因是 `.error`）不是「没听清」：
    /// 重说多少遍都不会好，满上限后仍交回表单，不停在语音面板（#502 的不变项，审查 A1）。
    func testRepeatedRecognitionStartFailuresStillFallBackToTheForm() async {
        let wizard = makeWizard(stub: VoiceOrderAPIClientStub(), startingAt: .freeform)
        let startFailure = SpeechInputCompletion(
            field: .voiceOrderFreeform,
            recognizedText: "",
            reason: .error
        )

        for _ in 0..<VoiceOrderWizard.maximumReasksPerSlot {
            wizard.handleCompletionForTesting(startFailure)
        }

        XCTAssertFalse(wizard.isRunning)
        XCTAssertNil(wizard.endedMessage, "识别起不来不该进「没听清」的结束态")
        XCTAssertFalse(wizard.endedAfterFailure, "不该在一个用不了的语音页上递「直接下单」")
        XCTAssertTrue((wizard.fallbackMessage ?? "").contains("表单"), "实际：\(wizard.fallbackMessage ?? "nil")")
    }

    /// 结束态之后再降级，结束态必须清掉 —— 否则界面停在语音面板，播报却说「已切回表单」/ 去补前置项（审查 A2）。
    /// 用「结束后门槛失效（删光紧急联系人）再重开」触发：不碰真麦克风（真 `SpeechInputService` 会在真机上弹授权框）。
    func testFallingBackAfterAnEndedSessionLeavesTheEndedState() async {
        let appState = AppState(persistence: AppStatePersistenceFactory.makeIsolatedTest())
        appState.updateBlindProfile(BlindProfileResponse(name: "测试用户", verifyStatus: "VERIFIED"))
        appState.updateEmergencyContacts([
            EmergencyContactResponse(id: 1, name: "联系人1", phone: "13900139001", relationship: "家人", isPrimary: true)
        ])
        let viewModel = BlindBookingViewModel()
        viewModel.configureForTesting(speechService: SpeechService(), locationService: nil, appState: appState)
        let wizard = makeUnstartedWizard(bookingViewModel: viewModel)
        XCTAssertTrue(wizard.start(), "前提：门槛已过")
        let silence = SpeechInputCompletion(
            field: .voiceOrderFreeform,
            recognizedText: "",
            reason: .silenceTimeout(hadDetectedSound: false)
        )
        for _ in 0..<VoiceOrderWizard.maximumReasksPerSlot {
            wizard.handleCompletionForTesting(silence)
        }
        XCTAssertNotNil(wizard.endedMessage, "前提：没听清进了结束态")

        appState.updateEmergencyContacts([])
        XCTAssertNotNil(viewModel.firstMissingGate, "前提：门槛现在失效了")

        XCTAssertFalse(wizard.start())

        XCTAssertNil(wizard.endedMessage, "要去表单补前置项时结束态必须清掉，否则屏幕停在语音面板")
        XCTAssertFalse(wizard.endedAfterFailure)
        XCTAssertNotNil(wizard.fallbackMessage)
    }

    /// **说了话但抽不出槽位**那条路径不受影响 —— 用户确实说了，用默认值补齐并读回是对的，
    /// 他能在读回里听出来。这条钉住上面三条没有把它一起改掉。
    func testSpeakingSomethingUnparseableStillReadsBackInsteadOfReasking() async {
        let stub = VoiceOrderAPIClientStub()
        stub.parseOrderResponses = [
            ParseVoiceOrderResponse(
                plannedStartTime: nil, durationMinutes: nil, address: nil,
                latitude: nil, longitude: nil,
                missing: [.address, .startTime, .duration], needReask: true, ttsText: nil
            )
        ]
        let wizard = makeWizard(stub: stub, startingAt: .freeform)

        await wizard.submitTranscript("呃那个我想想")

        XCTAssertEqual(wizard.step, .confirm, "说了话就该往读回走 —— 沉默才重问，这两件事不一样")
        XCTAssertEqual(wizard.reaskCount, 0)
    }
}
