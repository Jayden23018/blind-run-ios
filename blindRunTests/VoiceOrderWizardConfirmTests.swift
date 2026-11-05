import CoreLocation
import XCTest
@testable import blindRun

@MainActor
final class VoiceOrderWizardConfirmTests: XCTestCase, VoiceOrderWizardTestSupport {

    // MARK: - 一句话确认

    /// 两个方向的错误代价不对称：漏判「确认」只是多说两轮，误判「修改」为「确认」会产生一张
    /// 用户没打算下的订单并触发真实派单。这一组是本变更的核心安全断言。
    func testOnlyExplicitAffirmativesAreTreatedAsConfirmation() {
        let affirmatives = [
            "确认", "确认下单", "确认预约", "确认提交",
            "没问题", "就这样", "就这么办"
        ]
        for word in affirmatives {
            XCTAssertTrue(
                VoiceOrderWizard.isAffirmative(word),
                "「\(word)」应被判为确认"
            )
        }
        XCTAssertEqual(affirmatives.count, 7, "白名单每加一个词都要先问：它会不会出现在旁人的闲聊里")
        // 2026-08-10 删掉的那一个。本地直通表必须是后端 `INTENT_CONFIRM` 的子集，而后端那条
        // 正则里没有任何模式能命中它；它也从来没被读回教给用户。逐词对撞由
        // `scripts/validate-voice-intent-words.mjs` 做，这里只钉住「删了就别加回来」。
        XCTAssertFalse(
            VoiceOrderWizard.isAffirmative("开始约跑"),
            "后端确定性兜底不认这个词，本地直通表不许比它宽"
        )
    }

    /// 单音节高频应答词**必须**判为非确认。
    ///
    /// 2018 年 Portland 事故：Alexa 问 "[名字], right?"，背景对话里的 "right" 满足了确认，
    /// 一段私人录音被发了出去（Amazon 官方复盘）。中文这几个字与 "right" 同构，
    /// 而陪跑场景里志愿者可能就站在旁边说话。
    ///
    /// 「确定」一并移出：它是 iOS 弹窗按钮的常用词，用户容易顺口说，但也同样容易在
    /// 「我不确定」这类叙述里被截出来 —— 读回教的是「确认」，照着念就行。
    func testSingleSyllableBackchannelsAreNotConfirmation() {
        for word in ["好", "好的", "行", "可以", "对", "是", "没错", "同意", "确定", "提交", "下单"] {
            XCTAssertFalse(
                VoiceOrderWizard.isAffirmative(word),
                "「\(word)」是日常应答词，旁人一句闲聊就能触发下单，不得判为确认"
            )
        }
    }

    /// 白名单必须和读回教用户说的那句话一致，否则用户照着念却不生效。
    func testConfirmPromptTeachesAWordThatIsActuallyOnTheWhitelist() {
        XCTAssertTrue(VoiceOrderWizard.isAffirmative("确认"))
    }

    func testTrailingParticlesAndPunctuationDoNotBlockConfirmation() {
        for word in ["确认吧", "没问题呀", "就这样了", "就这样吧", "确认。", "确认下单，", "确 认"] {
            XCTAssertTrue(
                VoiceOrderWizard.isAffirmative(word),
                "句尾语气词和标点不改变语义：「\(word)」"
            )
        }
    }

    /// 这些串**都含有**肯定词，但意思分别是否定、否定、要求复核。整串匹配的存在理由就是它们。
    func testNegationsContainingAffirmativeWordsAreNotConfirmation() {
        for word in [
            "不确认", "先别确认", "不要确认", "确认一下时间", "我要修改",
            "改一下", "不对", "不是", "取消", "重说", "换个地方",
            "确认个啥", "还不能确认",
            // 旁人闲聊被麦克风收进来的样子 —— 一对一陪跑里志愿者就在身边。
            "好啊我知道了", "对了你等一下", "行我先走了", "是这样没错"
        ] {
            XCTAssertFalse(
                VoiceOrderWizard.isAffirmative(word),
                "「\(word)」不得被当成确认"
            )
        }
    }

    /// 「嗯」刻意不在白名单里：犹豫填充词不该下单。
    func testEmptyOrUnrelatedTranscriptIsNotConfirmation() {
        for word in ["", "   ", "。", "嗯", "嗯那个", "明天早上八点半", "人民广场地铁站"] {
            XCTAssertFalse(
                VoiceOrderWizard.isAffirmative(word),
                "「\(word)」不得被当成确认"
            )
        }
    }

    /// 本地表接不住的那一句**交给后端**，而不是就地回一句「没听懂」。
    ///
    /// 2026-08-10 之前这里断言的是 `stub.paths.isEmpty` —— 那正是「只能说确认或重说」二选一的
    /// 那道墙：用户说「把时间改成九点」会被本地表判成没听懂，而他说得完全清楚。
    /// 现在第 1 档判不出来只意味着「本地接不住」，第 2 档发 `/parse` 由后端分意图。
    func testUnrecognizedConfirmCommandGoesToTheBackendInsteadOfGivingUp() async {
        let stub = VoiceOrderAPIClientStub()
        stub.parseOrderResponses = [Self.parseResponse(ttsText: "您想改哪一项？", correctionUnclear: true)]
        let wizard = makeWizard(stub: stub, startingAt: .confirm)

        await wizard.submitTranscript("嗯那个啊")

        XCTAssertEqual(wizard.step, .confirm, "没听懂只能原地重问")
        XCTAssertNil(wizard.createdOrder, "没听懂绝不能提交")
        XCTAssertEqual(wizard.reaskCount, 1, "消歧问句这一条确实是没听懂，要计入上限")
        XCTAssertEqual(stub.paths, [VoiceOrderEndpoint.parseOrder], "本地接不住就该交后端")
    }

    /// 确认轮的网络失败**不许说成「没听懂」** —— 失败的是网络，改说法一点用都没有；
    /// 而本地那几个词仍然直通，所以提示里必须把这两条仅存的出路念出来。
    func testConfirmRoundNetworkFailureKeepsTheLocalEscapeHatchesAudible() async {
        let stub = VoiceOrderAPIClientStub()
        stub.error = .serverError(ErrorResponse(code: "INTERNAL_ERROR", message: "boom"))
        let speechService = SpeechService() // 向导对它是 weak，下面要读它念过什么
        let wizard = makeWizard(
            stub: stub, bookingViewModel: .withStartPointForTesting(), speechService: speechService,
            startingAt: .confirm, didCaptureStartTime: true
        )

        await wizard.submitTranscript("把时间往后挪一挪吧")

        let spoken = wizard.lastSpokenPrompt ?? ""
        XCTAssertFalse(spoken.contains("没听懂"), "失败的是网络不是听力：\(spoken)")
        XCTAssertTrue(spoken.contains("确认"), "本地直通的出路必须念出来：\(spoken)")
        XCTAssertTrue(spoken.contains("重说"), "本地直通的出路必须念出来：\(spoken)")
        XCTAssertEqual(wizard.step, .confirm)
        XCTAssertNil(wizard.createdOrder)

        // 网络还是坏的，但「确认」不经过网络 —— 一次已经解析成功的语音下单不该死在最后一步。
        await wizard.submitTranscript("确认")
        XCTAssertTrue(speechService.spokenHistoryForTesting.contains("正在提交订单。"), "本地确认必须能在断网时下单")
    }

    /// 「重说」回到整句那一轮，而不是跳进某个逐项流程（逐项修改已于 2026-08-06 删除）。
    func testRestartGoesBackToTheFullUtteranceRound() async {
        for transcript in ["重说", "重新说", "重来", "从头再说", "重新说一遍"] {
            let stub = VoiceOrderAPIClientStub()
            let wizard = makeWizard(stub: stub, startingAt: .confirm)

            await wizard.submitTranscript(transcript)

            XCTAssertEqual(wizard.step, .freeform, "「\(transcript)」应回到整句轮")
            XCTAssertTrue(wizard.isRunning)
            XCTAssertNil(wizard.createdOrder, "重说绝不能提交")
            XCTAssertTrue(stub.paths.isEmpty, "重说是本地判定，不走后端")
        }
    }

    /// 「重说」必须**把上一轮抽到的槽位清干净**。
    ///
    /// 不清的话，新一句里没提到的项会留着旧值，读回照样念出来 —— 用户会以为那是他这次说的，
    /// 而看不见屏幕的人无从察觉这是上一轮的残留。
    func testRestartClearsSlotsCapturedInThePreviousRound() async {
        let bookingViewModel = BlindBookingViewModel()
        bookingViewModel.duration = .sixty
        let wizard = makeWizard(
            stub: VoiceOrderAPIClientStub(),
            bookingViewModel: bookingViewModel,
            startingAt: .confirm
        )

        await wizard.submitTranscript("重说")

        XCTAssertEqual(bookingViewModel.duration, .none, "上一轮的时长留着，用户会以为是这次说的")
        XCTAssertNil(bookingViewModel.selectedStartPlace)
        XCTAssertFalse(wizard.didCaptureStartTime)
    }

    /// 肯定词与「重说」的匹配严格程度**刻意不同** —— 两者的失败方向不对称：
    /// 误判成确认会产生一张用户没打算下的真实订单；误判成重说只是让人多说一句话。
    func testCommandClassificationIsStrictForConfirmAndLenientForRestart() {
        XCTAssertEqual(VoiceOrderWizard.command(for: "确认"), .confirm)
        XCTAssertEqual(VoiceOrderWizard.command(for: "确认吧"), .confirm)
        XCTAssertEqual(VoiceOrderWizard.command(for: "重复"), .repeatBack)

        // 🔴 「再说一遍 / 再说一次」是**重听**，不是重说。2026-08-10 从 `.restart` 改判过来 ——
        // 逐词对撞后端 `VoiceSlotParser` 时查出这是一处方向相反的分歧：本地判重说会把用户刚说完的
        // 一整句清空，后端 `INTENT_REPEAT` 判的是重播。判反的代价不对称，以代价小的那边为准。
        for transcript in ["再说一遍", "再说一次", "你再说一遍", "没听清"] {
            XCTAssertEqual(
                VoiceOrderWizard.command(for: transcript), .repeatBack,
                "「\(transcript)」是要求重播，不是要求清空重说"
            )
        }

        // 重说用包含匹配：真机上「改地点」被听成同音的「该地点」，整串精确匹配把人卡死在读回轮，
        // 之后说什么都是「没听懂」。宽一点的代价只是偶尔多重说一轮。
        for transcript in ["重说", "那我重说一遍", "我想重新说", "重来吧", "算了重新来过"] {
            XCTAssertEqual(
                VoiceOrderWizard.command(for: transcript), .restart,
                "「\(transcript)」应判为重说"
            )
        }

        // 肯定词仍然整串：含肯定词的否定与复核请求一个都不许放行。
        for transcript in ["不确认", "先别确认", "确认一下时间", "还不能确认", "嗯"] {
            XCTAssertEqual(
                VoiceOrderWizard.command(for: transcript), .unrecognized,
                "「\(transcript)」不得被判成任何指令"
            )
        }
    }

    // MARK: - 确认轮的跨轮定点修改

    /// **本变更的核心用例。** 读回之后只说要改的那一项，其余槽位一个都不能丢。
    ///
    /// 2026-08-10 之前用户只有两条路：说「确认」，或者把整句重说一遍。想把时间从八点改成九点，
    /// 就得连出发地、终点、时长一起重念 —— 每重说一次都是一次新的识别错误机会，而对听不见屏幕的
    /// 人，错在哪一项他只能靠听完整段读回去分辨。
    func testCorrectionInTheConfirmRoundKeepsEverySlotTheUserDidNotMention() async {
        let stub = VoiceOrderAPIClientStub()
        let viewModel = BlindBookingViewModel()
        let firstRound = Self.parseResponse(
            plannedStartTime: Self.backendTime(hoursFromNow: 24),
            durationMinutes: 60,
            address: "上海市黄浦区人民广场", latitude: 31.2304, longitude: 121.4737,
            endAddress: "上海市杨浦区五角场", endLatitude: 31.3040, endLongitude: 121.5140
        )
        // 第 2 轮：后端把新时间合进整单，其余槽位从 `current` 逐字继承回来。
        let corrected = Self.parseResponse(
            plannedStartTime: Self.backendTime(hoursFromNow: 25),
            durationMinutes: 60,
            address: "上海市黄浦区人民广场", latitude: 31.2304, longitude: 121.4737,
            endAddress: "上海市杨浦区五角场", endLatitude: 31.3040, endLongitude: 121.5140
        )
        stub.parseOrderResponses = [firstRound, corrected]
        let wizard = makeWizard(stub: stub, bookingViewModel: viewModel, startingAt: .freeform)

        await wizard.submitTranscript("明天早上八点从人民广场跑到五角场，跑一个小时")
        XCTAssertEqual(wizard.step, .confirm)

        await wizard.submitTranscript("把时间改成明天早上九点")

        XCTAssertEqual(wizard.step, .confirm, "改一项之后回到读回，不是回到整句轮")
        XCTAssertEqual(viewModel.endPlace?.address, "上海市杨浦区五角场", "没提到的终点不许被清掉")
        XCTAssertEqual(viewModel.resolvedDurationMinutes, 60, "没提到的时长不许被清掉")
        XCTAssertEqual(viewModel.selectedStartPlace?.title, "上海市黄浦区人民广场", "没提到的起点不许被清掉")
        XCTAssertTrue(wizard.didCaptureStartTime)
        XCTAssertEqual(
            viewModel.appointmentTime.timeIntervalSince1970,
            Self.date(hoursFromNow: 25).timeIntervalSince1970,
            accuracy: 90,
            "说了要改的那一项必须真的变了"
        )
    }

    /// 跨轮修正的全部前提：确认轮把上一轮的结果作为 `current` **发出去了**。
    /// 只断言路径验不出来 —— 路径对、body 里没有 `current` 的话后端一个新字段都不会给，
    /// 而那正是 2026-08-09 之前的状态（后端做完一整批，iOS 侧全部不可达）。
    func testConfirmRoundSendsThePreviousRoundBackAsCurrent() async {
        let stub = VoiceOrderAPIClientStub()
        let first = Self.parseResponse(
            plannedStartTime: Self.backendTime(hoursFromNow: 24),
            durationMinutes: 60,
            address: "上海市黄浦区人民广场", latitude: 31.2304, longitude: 121.4737,
            hasGuideDog: true
        )
        stub.parseOrderResponses = [first, Self.parseResponse(ttsText: "您想改哪一项？", correctionUnclear: true)]
        let wizard = makeWizard(stub: stub, startingAt: .freeform)

        await wizard.submitTranscript("明天早上八点从人民广场出发跑一个小时")
        await wizard.submitTranscript("不对")

        XCTAssertEqual(stub.parseRequests.count, 2)
        XCTAssertNil(stub.parseRequests[0].current, "整句那一轮没有「上一轮」，不该带 current")
        let current = stub.parseRequests[1].current
        XCTAssertEqual(current?.plannedStartTime, first.plannedStartTime)
        XCTAssertEqual(current?.durationMinutes, 60)
        XCTAssertEqual(current?.address, "上海市黄浦区人民广场")
        XCTAssertEqual(current?.latitude, 31.2304)
        XCTAssertEqual(current?.hasGuideDog, true, "可选槽位也要继承，否则第 2 轮会把导盲犬悄悄丢掉")
    }

    /// `current` **只能从响应派生，绝不从 view model 派生**。
    ///
    /// `BlindBookingViewModel.appointmentTime` 的初值是 `Date()`，从它取快照会把一个用户从没说过的
    /// 时刻当成「已确认槽位」发给后端；后端原样继承回来、读回念出来，一张没人说过的单就这么成立了。
    /// 这是 2026-08-06「他也没有经过我的同意」那条红线在跨轮修正上的等价物。
    func testCurrentNeverCarriesAnAppointmentTimeTheUserNeverSpoke() async {
        let stub = VoiceOrderAPIClientStub()
        // 第 1 轮只抽到地点，时间没抽出来 —— 但 `appointmentTime` 这时**已经是一个具体时刻**了。
        stub.parseOrderResponses = [
            Self.parseResponse(
                address: "上海市黄浦区人民广场", latitude: 31.2304, longitude: 121.4737,
                missing: [.startTime, .duration]
            ),
            Self.parseResponse(ttsText: "您想改哪一项？", correctionUnclear: true)
        ]
        let viewModel = BlindBookingViewModel()
        let wizard = makeWizard(stub: stub, bookingViewModel: viewModel, startingAt: .freeform)

        await wizard.submitTranscript("从人民广场出发")
        await wizard.submitTranscript("不对")

        XCTAssertFalse(wizard.didCaptureStartTime)
        XCTAssertNil(
            stub.parseRequests[1].current?.plannedStartTime,
            "用户没说过时间，快照里就一个字都不许有 —— view model 那个 Date() 初值不是用户说的"
        )
    }
}
