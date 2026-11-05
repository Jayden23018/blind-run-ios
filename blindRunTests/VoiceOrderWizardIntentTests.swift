import CoreLocation
import XCTest
@testable import blindRun

@MainActor
final class VoiceOrderWizardIntentTests: XCTestCase, VoiceOrderWizardTestSupport {

    /// 后端判 `CONFIRM`（「这样就行，直接下单吧」这类本地表接不住的说法）走的是同一条提交路径，
    /// 且**仍然受缺槽位门槛拦着** —— 槽位没齐时一句确认不能派单。
    func testBackendConfirmIntentTakesTheSubmitPathAndStillRespectsTheMissingTimeGate() async {
        // ① 缺时间：后端就算判了 CONFIRM 也不许提交。
        let blockedStub = VoiceOrderAPIClientStub()
        blockedStub.parseOrderResponses = [Self.parseResponse(userIntent: .confirm)]
        let blocked = makeWizard(stub: blockedStub, startingAt: .confirm, didCaptureStartTime: false)

        await blocked.submitTranscript("这样就行，直接下单吧")

        XCTAssertNil(blocked.createdOrder, "没说过时间就不能凭一句确认派单")
        XCTAssertTrue(blocked.isRunning)

        // ② 槽位齐了：走提交。
        let stub = VoiceOrderAPIClientStub()
        stub.parseOrderResponses = [Self.parseResponse(userIntent: .confirm)]
        let speechService = SpeechService() // 向导对它是 weak，下面要读它念过什么
        let wizard = makeWizard(
            stub: stub, bookingViewModel: .withStartPointForTesting(), speechService: speechService,
            startingAt: .confirm, didCaptureStartTime: true
        )

        await wizard.submitTranscript("这样就行，直接下单吧")

        XCTAssertFalse(wizard.isRunning, "提交后不得继续占着麦克风")
        XCTAssertTrue(speechService.spokenHistoryForTesting.contains("正在提交订单。"), "槽位齐了要真走到提交（#601）")
    }

    /// 「算了不下了」结束整个语音流程，**不重问**。用户要退出时再追问一句是把人锁在里面。
    func testBackendCancelIntentEndsTheVoiceFlowWithoutReasking() async {
        let stub = VoiceOrderAPIClientStub()
        stub.parseOrderResponses = [Self.parseResponse(ttsText: "已取消", userIntent: .cancel)]
        let wizard = makeWizard(stub: stub, startingAt: .confirm, didCaptureStartTime: true)

        await wizard.submitTranscript("算了，今天不跑了")

        XCTAssertFalse(wizard.isRunning, "取消就该停下来")
        XCTAssertNil(wizard.createdOrder)
        // 后端 #502：取消停在语音面板，不送去表单，播报不提表单。
        XCTAssertEqual(wizard.endedMessage, VoiceOrderWizard.cancelledMessage)
        XCTAssertEqual(wizard.lastSpokenPrompt, "已取消这次语音下单。", "看不见屏幕的人需要听到语音已经停了")
        XCTAssertNil(wizard.fallbackMessage, "取消不是语音坏了，不切表单")
        XCTAssertFalse(wizard.endedAfterFailure, "用户刚说了不要，不递「直接下单」")
    }

    /// 本地取消词：整串匹配，尾部语气词被 `normalizedCommand` 剥掉。
    /// 「把导盲犬取消」是改一项，不是取消整单 —— 包含匹配会让整单凭空消失。
    func testCancelWordsMatchWholeUtteranceOnly() {
        for word in ["算了", "算了吧", "算了。", "不下单", "不下了", "不订了", "不跑了", "不要了", "取消", "取消吧", "放弃"] {
            XCTAssertTrue(VoiceOrderWizard.isCancel(word), "「\(word)」是取消")
        }
        for phrase in ["把导盲犬取消", "取消导盲犬", "我要放弃导盲犬", "算了，今天不跑了", "确认", "不确认", "明天早上八点从人民广场出发", ""] {
            XCTAssertFalse(VoiceOrderWizard.isCancel(phrase), "「\(phrase)」不是取消整单")
        }
    }

    /// 三轮里说「算了」都本地退出：不发 `/parse`、不当地名、不提交订单，并且说出接下来去哪。
    func testLocalCancelExitsFromEveryRoundWithoutTouchingTheBackend() async {
        let candidates = [Self.candidate("阳光棕榈园"), Self.candidate("阳光棕榈园北门")]
        for startingStep in ["freeform", "disambiguate", "confirm"] {
            let stub = VoiceOrderAPIClientStub()
            let wizard: VoiceOrderWizard
            switch startingStep {
            case "freeform":
                wizard = makeWizard(stub: stub)
            case "disambiguate":
                stub.parseOrderResponses = [Self.parseResponse(
                    plannedStartTime: Self.backendTime(hoursFromNow: 20),
                    durationMinutes: 60,
                    address: "阳光棕榈园",
                    latitude: 22.5333,
                    longitude: 113.9300,
                    candidates: candidates
                )]
                wizard = makeWizard(stub: stub)
                await wizard.submitTranscript("明天早上八点从阳光棕榈园出发跑一个小时")
            default:
                wizard = makeWizard(stub: stub, startingAt: .confirm, didCaptureStartTime: true)
            }
            let pathsBefore = stub.paths.count

            await wizard.submitTranscript("算了吧")

            XCTAssertFalse(wizard.isRunning, "\(startingStep)：取消就该停下来")
            XCTAssertNil(wizard.createdOrder, "\(startingStep)：取消绝不能提交")
            XCTAssertEqual(stub.paths.count, pathsBefore, "\(startingStep)：取消是本地判定，不走后端：\(stub.paths)")
            XCTAssertEqual(
                wizard.lastSpokenPrompt, VoiceOrderWizard.cancelledMessage,
                "\(startingStep)：要让看不见屏幕的人听到已取消，且不提表单"
            )
            XCTAssertNil(wizard.fallbackMessage, "\(startingStep)：取消不切表单（#502）")
            XCTAssertNotNil(wizard.endedMessage, "\(startingStep)：停在语音面板的结束态")
        }
    }

    /// 整句轮里「把导盲犬取消」是下单内容，不是取消 —— 要照常交给 `/parse`。
    func testCancelPhraseInsideAFullSentenceStillGoesToParsing() async {
        let stub = VoiceOrderAPIClientStub()
        stub.parseOrderResponses = [Self.parseResponse(
            plannedStartTime: Self.backendTime(hoursFromNow: 20),
            durationMinutes: 60
        )]
        let wizard = makeWizard(stub: stub)

        await wizard.submitTranscript("把导盲犬取消")

        XCTAssertEqual(stub.paths.count, 1, "非整句取消应走 /parse：\(stub.paths)")
        XCTAssertNil(wizard.fallbackMessage)
    }

    /// 后端判 `RESTART` 时**快照也要清干净**。
    /// 留着 `current`，用户「重说」的那一整句会被后端和上一轮的旧槽位合并，
    /// 于是他这次没提的东西又原样回来了，而屏幕上一个字都不会变。
    func testBackendRestartIntentClearsTheSnapshotSoTheNextUtteranceStartsClean() async {
        let stub = VoiceOrderAPIClientStub()
        stub.parseOrderResponses = [
            Self.parseResponse(
                plannedStartTime: Self.backendTime(hoursFromNow: 24), durationMinutes: 60,
                address: "上海市黄浦区人民广场", latitude: 31.2304, longitude: 121.4737
            ),
            Self.parseResponse(ttsText: "好的，我们重新来", userIntent: .restart),
            Self.parseResponse(
                plannedStartTime: Self.backendTime(hoursFromNow: 26), durationMinutes: 30,
                address: "上海市长宁区中山公园", latitude: 31.2230, longitude: 121.4200
            )
        ]
        let viewModel = BlindBookingViewModel()
        let wizard = makeWizard(stub: stub, bookingViewModel: viewModel, startingAt: .freeform)

        await wizard.submitTranscript("明天早上八点从人民广场出发跑一个小时")
        await wizard.submitTranscript("咱们从头再来一次吧，我说错了")

        XCTAssertEqual(wizard.step, .freeform, "后端判重来就要回到整句轮")
        XCTAssertNil(viewModel.selectedStartPlace, "重来必须把上一轮的槽位清干净")

        await wizard.submitTranscript("后天早上十点从中山公园出发跑半小时")

        XCTAssertNil(
            stub.parseRequests[2].current,
            "重来之后的第一句是新的整句轮，不许把上一轮的槽位捎回去"
        )
    }

    /// 「你再念一遍」重播读回，**一个槽位都不动，也不清空**。
    /// 判成重来的代价是把用户刚说完的一整句清掉，方向不对称。
    func testBackendRepeatIntentReadsBackAgainWithoutTouchingAnySlot() async {
        let stub = VoiceOrderAPIClientStub()
        let viewModel = BlindBookingViewModel()
        stub.parseOrderResponses = [
            Self.parseResponse(
                plannedStartTime: Self.backendTime(hoursFromNow: 24), durationMinutes: 60,
                address: "上海市黄浦区人民广场", latitude: 31.2304, longitude: 121.4737
            ),
            Self.parseResponse(ttsText: "好的，我再念一遍", userIntent: .repeatBack)
        ]
        let wizard = makeWizard(stub: stub, bookingViewModel: viewModel, startingAt: .freeform)

        await wizard.submitTranscript("明天早上八点从人民广场出发跑一个小时")
        await wizard.submitTranscript("你刚才说啥来着，我没跟上")

        XCTAssertEqual(wizard.step, .confirm)
        XCTAssertEqual(viewModel.selectedStartPlace?.title, "上海市黄浦区人民广场", "重听不许动槽位")
        XCTAssertEqual(viewModel.resolvedDurationMinutes, 60)
        XCTAssertTrue(wizard.didCaptureStartTime)
        XCTAssertTrue(
            (wizard.lastSpokenPrompt ?? "").contains("出发地点"),
            "重听要重播整单读回：\(wizard.lastSpokenPrompt ?? "")"
        )
    }
}
