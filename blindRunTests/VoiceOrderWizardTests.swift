import XCTest
@testable import blindRun

/// 语音下单向导的状态机。录音那一段由 `SpeechInputService` 自己的用例覆盖，这里锁的是向导独有的三条
/// 规则：`needReask` 不推进、连续听不清要降级回表单、解析结果落到正确的表单字段。
@MainActor
final class VoiceOrderWizardTests: XCTestCase {

    // MARK: - 一句话确认

    /// 两个方向的错误代价不对称：漏判「确认」只是多说两轮，误判「修改」为「确认」会产生一张
    /// 用户没打算下的订单并触发真实派单。这一组是本变更的核心安全断言。
    func testOnlyExplicitAffirmativesAreTreatedAsConfirmation() {
        let affirmatives = [
            "确认", "确认下单", "确认预约", "确认提交",
            "没问题", "就这样", "就这么办", "开始约跑"
        ]
        for word in affirmatives {
            XCTAssertTrue(
                VoiceOrderWizard.isAffirmative(word),
                "「\(word)」应被判为确认"
            )
        }
        XCTAssertEqual(affirmatives.count, 8, "白名单每加一个词都要先问：它会不会出现在旁人的闲聊里")
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

    /// 听不懂**绝不能**顺着走下去。读回之后没听懂就原地重问，不提交、不发请求、不跳步。
    func testUnrecognizedConfirmCommandReasksAndNeverSubmits() async {
        let stub = VoiceOrderAPIClientStub()
        let wizard = makeWizard(stub: stub, startingAt: .confirm)

        await wizard.submitTranscript("嗯那个啊")

        XCTAssertEqual(wizard.step, .confirm, "没听懂只能原地重问")
        XCTAssertNil(wizard.createdOrder, "没听懂绝不能提交")
        XCTAssertEqual(wizard.reaskCount, 1)
        XCTAssertTrue(stub.paths.isEmpty, "读回这一轮的指令判定不走后端：\(stub.paths)")
    }

    /// 确认走的是提交路径而不是解析端点。
    ///
    /// `didCaptureStartTime: true` 不能省 —— 没抽到时间时「确认」按设计不生效（见
    /// `testConfirmIsRefusedWhenTheStartTimeWasNeverSpoken`），不传就变成在测拦截而不是提交。
    func testAffirmativeTakesTheSubmitPathInsteadOfParsing() async {
        let stub = VoiceOrderAPIClientStub()
        let wizard = makeWizard(stub: stub, startingAt: .confirm, didCaptureStartTime: true)

        await wizard.submitTranscript("确认")

        XCTAssertFalse(wizard.isRunning, "提交后不得继续占着麦克风")
        XCTAssertTrue(stub.paths.isEmpty, "确认判定不走后端：\(stub.paths)")
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

    // MARK: - 整句那一轮

    /// 一整句一次抽三个槽位，**只发一个请求**。
    ///
    /// 此前是两路并发 `parse-slot`（地点那路被常量关着），后端 2026-08-04 补了 `/voice/parse`
    /// 先抽地名 span 再查高德，三槽合成一次往返 —— 语音场景里省下的那一个往返是用户听着等的时间。
    func testFreeformUtteranceFillsAllThreeSlotsInASingleRequest() async {
        let stub = VoiceOrderAPIClientStub()
        let plannedStart = DateFormatter.aidRunBackendLocalDateTime.string(
            from: Date().addingTimeInterval(3600 * 24)
        )
        stub.parseOrderResponses = [
            ParseVoiceOrderResponse(
                plannedStartTime: plannedStart,
                durationMinutes: 60,
                address: "上海市黄浦区人民广场",
                latitude: 31.2304,
                longitude: 121.4737,
                missing: [],
                needReask: false,
                ttsText: "好的，我记下了"
            )
        ]
        let viewModel = BlindBookingViewModel()
        let wizard = makeWizard(stub: stub, bookingViewModel: viewModel, startingAt: .freeform)

        await wizard.submitTranscript("明天早上八点从人民广场出发跑一个小时")

        XCTAssertEqual(wizard.step, .confirm, "整句解析完必须落到读回确认")
        XCTAssertEqual(viewModel.resolvedDurationMinutes, 60)
        XCTAssertEqual(
            DateFormatter.aidRunBackendLocalDateTime.string(from: viewModel.appointmentTime),
            plannedStart,
            "开始时间必须原样透传，客户端不得二次格式化"
        )
        XCTAssertEqual(stub.paths, [VoiceOrderEndpoint.parseOrder], "整句只该发一个请求：\(stub.paths)")
        XCTAssertTrue(stub.requestedSlotFields.isEmpty, "整句不再走逐槽位端点")
        XCTAssertEqual(wizard.lastUtterance, "明天早上八点从人民广场出发跑一个小时", "读回要先念用户原话")
    }

    /// 整句那一轮**不重问、不失败**：`missing` 等价于「这几项保持默认值」，不是重问信号；
    /// 后端在 `missing` 非空时给的 `ttsText` 是**追问**文案，播它就等于把人拉回重问。
    func testFreeformTreatsMissingSlotsAsDefaultsAndNeverReasks() async {
        let stub = VoiceOrderAPIClientStub()
        stub.parseOrderResponses = [
            ParseVoiceOrderResponse(
                plannedStartTime: nil,
                durationMinutes: nil,
                address: nil,
                latitude: nil,
                longitude: nil,
                missing: [.address, .startTime, .duration],
                needReask: true,
                ttsText: "还差三项没听清，可以再说一次"
            )
        ]
        let wizard = makeWizard(stub: stub, startingAt: .freeform)

        await wizard.submitTranscript("呃那个我想想")

        XCTAssertEqual(wizard.step, .confirm, "整句抽不出也要往读回走，不能原地重问")
        XCTAssertEqual(wizard.reaskCount, 0)
        XCTAssertTrue(wizard.isRunning)
        XCTAssertNil(wizard.createdOrder)
        XCTAssertEqual(
            wizard.lastSpokenPrompt?.contains("还差三项没听清"), false,
            "后端的追问文案不得出现在读回里：\(wizard.lastSpokenPrompt ?? "nil")"
        )
    }

    /// 整句解析整体失败（网络挂了 / 超时 / 解码不了）同样不打回表单：默认值仍然成单，
    /// 由读回环节把实际内容念清楚。把人在这里踢回表单，等于让一句话白说。
    func testFreeformSwallowsTransportFailuresAndStillReadsBackDefaults() async {
        let stub = VoiceOrderAPIClientStub()
        stub.error = .unknown(statusCode: 500)
        let wizard = makeWizard(stub: stub, startingAt: .freeform)

        await wizard.submitTranscript("明天早上八点从人民广场出发跑一个小时")

        XCTAssertEqual(wizard.step, .confirm)
        XCTAssertEqual(wizard.reaskCount, 0)
        XCTAssertNil(wizard.fallbackMessage, "整句这一轮不得因为接口失败就交回表单")
        XCTAssertTrue(wizard.isRunning)
    }

    /// 吞掉错误**不等于不说**。整句解析失败时读回念的全是默认值，而用户听不出「语音没在工作」和
    /// 「语音听懂了但你说的正好是默认值」的区别 —— 没仔细听就下了一张时间地点全错的单。
    ///
    /// 这不是假想场景：2026-08-06 查实 `/api/orders/voice/parse` 的 handler 只在后端未部署分支
    /// （`7cb5758`）上，生产跑的 `7bce0b3` 根本没有这个端点，所以 404 是常态而非偶发。
    func testFreeformAnnouncesThatParsingFailedBeforeReadingBackDefaults() async {
        let stub = VoiceOrderAPIClientStub()
        stub.error = .unknown(statusCode: 404)
        // viewModel 必须由用例**持一个强引用**：向导里是 `private weak var`，内联构造
        // （或让 makeWizard 兜底新建）的实例当场就被释放，`askCurrentStep` 于是退到
        // `step.prompt` 兜底文案，连 `confirmPrompt` 都不进 —— 读回和提示一起消失，
        // 断言会因为一个和本用例无关的理由失败。
        let viewModel = BlindBookingViewModel()
        let wizard = makeWizard(stub: stub, bookingViewModel: viewModel, startingAt: .freeform)

        await wizard.submitTranscript("明天早上八点从人民广场出发跑一个小时")

        XCTAssertEqual(wizard.step, .confirm)
        let spoken = wizard.lastSpokenPrompt ?? ""
        XCTAssertTrue(
            spoken.contains(VoiceOrderWizard.parseFailureNotice),
            "解析失败必须在读回前说出来，否则用户无从察觉语音没在工作：\(spoken)"
        )
        XCTAssertTrue(
            spoken.hasPrefix(VoiceOrderWizard.parseFailureNotice),
            "提示必须在整单之前 —— 说在后面等于让用户先信了一遍默认值：\(spoken)"
        )
        XCTAssertTrue(
            spoken.contains("我听到你说：明天早上八点从人民广场出发跑一个小时。"),
            "识别到的原话仍要念：失败的是解析不是听写，用户得能对出差在哪：\(spoken)"
        )
        // 整句解析失败 = 一个槽位都没抽到 = 时间也没抽到，所以出路念的是「缺时间不能下单」，
        // 而不是「说确认就下单」。教用户说一个说了也不生效的词，比不教更糟。
        XCTAssertTrue(spoken.contains("重说"), "必须给出唯一可行的出路：\(spoken)")
        XCTAssertFalse(
            spoken.contains("说「确认」就下单"),
            "时间都没抽到还教用户说确认，他说了不生效：\(spoken)"
        )
    }

    /// 解析成功时不得出现失败提示 —— 一句每次都念的「提示」等于没有提示。
    func testFreeformDoesNotAnnounceFailureWhenParsingSucceeds() async {
        let stub = VoiceOrderAPIClientStub()
        stub.parseOrderResponses = [
            ParseVoiceOrderResponse(
                plannedStartTime: nil,
                durationMinutes: nil,
                address: nil,
                latitude: nil,
                longitude: nil,
                missing: [.address, .startTime, .duration],
                needReask: true,
                ttsText: nil
            )
        ]
        let viewModel = BlindBookingViewModel()  // 强引用，理由同上一条用例
        let wizard = makeWizard(stub: stub, bookingViewModel: viewModel, startingAt: .freeform)

        await wizard.submitTranscript("呃那个我想想")

        let spoken = wizard.lastSpokenPrompt ?? ""
        XCTAssertTrue(spoken.contains("这次的预约是："), "先确认真的走了读回，否则下一条断言无意义：\(spoken)")
        XCTAssertFalse(
            spoken.contains(VoiceOrderWizard.parseFailureNotice),
            "后端 200 返回「三项都没抽到」是正常业务状态，不是解析失败：\(spoken)"
        )
    }

    /// 时长取整在**整句轮**也必须播报 —— 此前只有定点修改轮播，整句轮是静默取整。
    /// 静默取整对听不见屏幕的人就是篡改，同一条红线不该有两种行为。
    func testFreeformAnnouncesDurationRounding() async {
        let stub = VoiceOrderAPIClientStub()
        stub.parseOrderResponses = [
            ParseVoiceOrderResponse(
                plannedStartTime: nil,
                durationMinutes: 40,
                address: nil,
                latitude: nil,
                longitude: nil,
                missing: [.address, .startTime],
                needReask: true,
                ttsText: nil
            )
        ]
        let viewModel = BlindBookingViewModel()
        let wizard = makeWizard(stub: stub, bookingViewModel: viewModel, startingAt: .freeform)

        await wizard.submitTranscript("跑四十分钟")

        XCTAssertEqual(viewModel.resolvedDurationMinutes, 40, "40 分钟在契约区间内，必须原样保留")
        let spoken = wizard.lastSpokenPrompt ?? ""
        XCTAssertTrue(spoken.contains("40 分钟"), "读回要念用户说的时长：\(spoken)")
        XCTAssertFalse(
            spoken.contains("你说的是"),
            "没有改动就不该有那句「你说的是⋯⋯本次按⋯⋯」——每次都念的提示等于没有提示：\(spoken)"
        )
    }

    /// 只有真的超出契约区间才播报改动。**静默改动对听不见屏幕的人就是篡改**，
    /// 这条红线不因为现在很少触发而消失。
    func testDurationBeyondTheContractRangeIsClampedOutLoud() async {
        let stub = VoiceOrderAPIClientStub()
        stub.parseOrderResponses = [
            ParseVoiceOrderResponse(
                plannedStartTime: nil, durationMinutes: 400, address: nil,
                latitude: nil, longitude: nil,
                missing: [.address, .startTime], needReask: true, ttsText: nil
            )
        ]
        let viewModel = BlindBookingViewModel()
        let wizard = makeWizard(stub: stub, bookingViewModel: viewModel, startingAt: .freeform)

        await wizard.submitTranscript("跑四百分钟")

        XCTAssertEqual(viewModel.resolvedDurationMinutes, 300, "超出契约上限要夹到 300")
        let spoken = wizard.lastSpokenPrompt ?? ""
        XCTAssertTrue(spoken.contains("400"), "必须说出用户原本说的数字：\(spoken)")
        XCTAssertTrue(spoken.contains("5 小时"), "必须说出实际下单的时长：\(spoken)")
    }

    /// `missing` 收到后端将来新增的值不得把整条响应带崩 —— 崩了表现是「说了一整句什么都没发生」。
    func testUnknownMissingSlotValueDecodesInsteadOfThrowing() throws {
        let json = """
        {"missing":["ADDRESS","ROUTE_PREFERENCE"],"needReask":true,"ttsText":"再说一次"}
        """
        let decoded = try JSONDecoder().decode(ParseVoiceOrderResponse.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.missing, [.address, .unknown])
        XCTAssertNil(decoded.resolvedStartPlace)
    }

    /// 只有地址没有坐标（或反过来）不算抽到起点：前者下不了单，后者读回时没法念。
    func testPartialStartPlaceIsTreatedAsNotResolved() {
        let addressOnly = ParseVoiceOrderResponse(
            plannedStartTime: nil, durationMinutes: nil,
            address: "上海市黄浦区人民广场", latitude: nil, longitude: nil,
            missing: nil, needReask: nil, ttsText: nil
        )
        let coordinateOnly = ParseVoiceOrderResponse(
            plannedStartTime: nil, durationMinutes: nil,
            address: nil, latitude: 31.2304, longitude: 121.4737,
            missing: nil, needReask: nil, ttsText: nil
        )

        XCTAssertNil(addressOnly.resolvedStartPlace)
        XCTAssertNil(coordinateOnly.resolvedStartPlace)
    }

    // MARK: - 逐项修改已删除（2026-08-06）
    //
    // 原来这里有四条用例覆盖「改地点 / 改时间 / 改时长」那条逐项流程：needReask 不推进、
    // 连续三次听不清降级、解析结果回填、取整要念出来。逐项修改随 `.restart` 一起删掉之后，
    // 它们测的代码已经不存在。等价保障都在整句轮那几条上：
    //   · 回填 → testFreeformUtteranceFillsAllThreeSlotsInASingleRequest
    //   · 取整播报 → testFreeformAnnouncesDurationRounding
    //   · 连续失败降级 → testRepeatedSilenceEventuallyFallsBackToTheForm
    //   · needReask 不当错误 → testFreeformTreatsMissingSlotsAsDefaultsAndNeverReasks

    /// 语音说多少就是多少，只在超出契约区间（10–300）时夹到边界。
    ///
    /// 原来是「就近 snap 到 6 个枚举档位」，于是「跑三个小时」变成两小时 ——
    /// 枚举存在的理由是选择器需要有限选项，而说话的人不需要选择器。
    func testSpokenDurationIsTakenLiterallyAndOnlyClampedToTheContractRange() {
        XCTAssertEqual(VoiceOrderWizard.acceptedDurationMinutes(180), 180, "三个小时不该被砍成两小时")
        XCTAssertEqual(VoiceOrderWizard.acceptedDurationMinutes(40), 40, "40 分钟不该被抬到 45")
        XCTAssertEqual(VoiceOrderWizard.acceptedDurationMinutes(300), 300)
        XCTAssertEqual(VoiceOrderWizard.acceptedDurationMinutes(400), 300, "超出契约上限夹到 300")
        XCTAssertEqual(VoiceOrderWizard.acceptedDurationMinutes(5), 10, "低于契约下限夹到 10")
    }

    /// 时长文案按精确分钟数生成，不套枚举档位名。
    func testDurationTextReadsTheExactMinutes() {
        XCTAssertEqual(BlindBookingViewModel.durationText(forMinutes: 180), "3 小时")
        XCTAssertEqual(BlindBookingViewModel.durationText(forMinutes: 150), "2 小时 30 分钟")
        XCTAssertEqual(BlindBookingViewModel.durationText(forMinutes: 40), "40 分钟")
    }


    // MARK: - 与后端黄金语料对齐

    // 后端 `demo/docs/voice-golden-corpus.json` 的 iOS 侧镜像，**四族 45 条全覆盖**。
    //
    // 锁的是 **Mock 不许比真实解析器松或紧**：Mock 认得的说法真机上也要认得，Mock 认不得的
    // （语料里 `source: "llm"` 那几条）在开发期就该走到 `needReask` 分支，否则向导的重问路径
    // 永远没被走过，上真机才发现是死的。
    //
    // ⚠️ 下面每个清单上方的 `golden-corpus:` 标记是给 `scripts/validate-golden-corpus.mjs` 认的，
    // 别删。在 2026-08-06 之前那个脚本只比对 DURATION 的 11 条，另外 34 条既无镜像也无告警，
    // 却照样打印「通过」—— 假绿比没有守卫更坏，因为它让人以为查过了。

    /// 语料的时间基准。START_TIME 的期望值全是相对它算出的绝对时间戳，
    /// 不钉住基准就验不出「过去的钟点滚次日」这条规则。
    private static let corpusNow = "2026-07-24T10:00:00"

    private func withCorpusClock(_ body: () -> Void) {
        MockAPIClient.voiceClockForTesting = DateFormatter.aidRunBackendLocalDateTime.date(from: Self.corpusNow)
        defer { MockAPIClient.voiceClockForTesting = nil }
        body()
    }

    func testMockDurationParsingMatchesTheBackendGoldenCorpus() {
        // golden-corpus: DURATION regex
        let regexCases: [(transcript: String, expected: Int)] = [
            ("跑一小时", 60),
            ("跑一个小时", 60),
            ("四十分钟", 40),
            ("半小时", 30),
            ("一个半小时", 90),
            ("一小时二十分钟", 80),
            ("两个小时", 120),
            ("就跑二十分钟吧", 20)
        ]
        for testCase in regexCases {
            XCTAssertEqual(
                MockAPIClient.mockVoiceMinutes(in: testCase.transcript),
                testCase.expected,
                "Mock 与黄金语料漂移：「\(testCase.transcript)」应为 \(testCase.expected) 分钟"
            )
        }

        // golden-corpus: DURATION llm
        // `source: "llm"` 的长尾表达：Mock 没有模型兜底，必须落到 needReask，不能瞎猜一个值。
        for transcript in ["随便说点什么", "陪我跑个把小时吧", "跑到我累了为止"] {
            XCTAssertNil(
                MockAPIClient.mockVoiceMinutes(in: transcript),
                "「\(transcript)」在 Mock 里不该被解析出数值"
            )
        }
    }

    /// START_TIME 13 条。这一族是 2026-08-06 才补上镜像的 —— 补之前 Mock 只认 5 个钟点、
    /// 落点恒定是「明天」，10 条 regex 只对得上 3 条：说「今天八点半」被念成明天，
    /// 说「下午三点」「半小时后」直接走重问，而线上这三种都解得出。
    func testMockStartTimeParsingMatchesTheBackendGoldenCorpus() {
        withCorpusClock {
            // golden-corpus: START_TIME regex
            let regexCases: [(transcript: String, expected: String)] = [
                ("八点半", "2026-07-25T08:30:00"),
                ("今天八点半", "2026-07-24T08:30:00"),
                ("明天早上八点", "2026-07-25T08:00:00"),
                ("后天上午九点", "2026-07-26T09:00:00"),
                ("下午三点", "2026-07-24T15:00:00"),
                ("晚上七点半", "2026-07-24T19:30:00"),
                ("半小时后", "2026-07-24T10:30:00"),
                ("两个小时后", "2026-07-24T12:00:00"),
                ("四十分钟后", "2026-07-24T10:40:00"),
                ("呃，明天早上八点吧", "2026-07-25T08:00:00")
            ]
            for testCase in regexCases {
                let parsed = MockAPIClient.mockVoiceStartTime(in: testCase.transcript)
                XCTAssertEqual(
                    parsed.map(MockAPIClient.mockBackendLocalDateTime),
                    testCase.expected,
                    "Mock 与黄金语料漂移：「\(testCase.transcript)」（now=\(Self.corpusNow)）应为 \(testCase.expected)"
                )
            }

            // golden-corpus: START_TIME llm
            for transcript in ["随便说点什么", "明天差不多这个点吧", "等我吃完早饭吧"] {
                XCTAssertNil(
                    MockAPIClient.mockVoiceStartTime(in: transcript),
                    "「\(transcript)」在 Mock 里不该被解析出时间"
                )
            }
        }
    }

    /// 「八点半」滚次日这条规则单独再锁一次 —— 它是这一族里唯一**依赖 now** 的行为，
    /// 上面那张表只要基准写错就会整体失效，而这条会指名道姓地失败。
    func testAClockTimeAlreadyPastTodayRollsToTomorrowUnlessTodayIsSpoken() {
        withCorpusClock {
            let rolled = MockAPIClient.mockVoiceStartTime(in: "八点半")
            XCTAssertEqual(
                rolled.map(MockAPIClient.mockBackendLocalDateTime), "2026-07-25T08:30:00",
                "now=10:00 时「八点半」必须滚到次日：返回今天 08:30 会被提前量校验判成「太近了」，"
                    + "而用户压根没打算约今天"
            )
            XCTAssertEqual(
                MockAPIClient.mockVoiceStartTime(in: "今天八点半").map(MockAPIClient.mockBackendLocalDateTime),
                "2026-07-24T08:30:00",
                "显式说了「今天」就不该滚 —— 那是用户的明确选择，该由提前量校验去拒绝"
            )
        }
    }

    /// ADDRESS 9 条。语料只断言**剥壳抽取**，不断言地理编码结果（语料 `_address_note`）：
    /// 抽出「五角场」而 Mock 的地点表里查不到坐标，正是线上「抽到 span 但正向编码失败」的同形场景。
    func testMockAddressSpanExtractionMatchesTheBackendGoldenCorpus() {
        // golden-corpus: ADDRESS regex
        let regexCases: [(transcript: String, expected: String)] = [
            ("明天早上八点从五角场出发跑一小时", "五角场"),
            ("我想在人民广场跑步", "人民广场"),
            ("到中山公园那边跑四十分钟", "中山公园"),
            ("从我家楼下出发", "我家楼下"),
            ("在天安门集合", "天安门")
        ]
        for testCase in regexCases {
            XCTAssertEqual(
                MockAPIClient.mockVoiceAddressSpan(in: testCase.transcript),
                testCase.expected,
                "Mock 与黄金语料漂移：「\(testCase.transcript)」应抽出「\(testCase.expected)」"
            )
        }

        // golden-corpus: ADDRESS llm
        // 「从明天早上八点开始跑」这类最危险：壳字「从」在，但后面跟的是时间。
        // 抽出来当地点就把人约到了一个不存在的起点，所以必须一条都不许命中。
        for transcript in ["从明天早上八点开始跑", "从半小时后开始跑", "老地方见，跑一小时", "随便说点什么"] {
            XCTAssertNil(
                MockAPIClient.mockVoiceAddressSpan(in: transcript),
                "「\(transcript)」不该被抽出地名"
            )
        }
    }

    /// GUIDE_DOG 6 条。`nil`（没提）与 `false`（明确不带）必须分得开 ——
    /// 这个字段进派单硬过滤，混淆会让登记了导盲犬的用户被静默按「不带」派单。
    func testMockGuideDogExtractionMatchesTheBackendGoldenCorpus() {
        // golden-corpus: GUIDE_DOG regex
        let regexCases: [(transcript: String, expected: Bool)] = [
            ("明天八点从五角场出发跑一小时，我带导盲犬", true),
            ("我牵着导盲犬", true),
            ("今天不带导盲犬", false),
            ("这次没带导盲犬", false)
        ]
        for testCase in regexCases {
            XCTAssertEqual(
                MockAPIClient.mockVoiceGuideDog(in: testCase.transcript),
                testCase.expected,
                "Mock 与黄金语料漂移：「\(testCase.transcript)」应为 \(testCase.expected)"
            )
        }

        // golden-corpus: GUIDE_DOG none
        for transcript in ["跑步的时候有狗叫", "明天八点从五角场出发跑一小时"] {
            XCTAssertNil(
                MockAPIClient.mockVoiceGuideDog(in: transcript),
                "「\(transcript)」没提导盲犬，必须是 nil 而不是 false —— nil 才会回落档案默认值"
            )
        }
    }

    /// PACE 6 条。
    func testMockPaceExtractionMatchesTheBackendGoldenCorpus() {
        // golden-corpus: PACE regex
        let regexCases: [(transcript: String, expected: String)] = [
            ("慢一点跑", "EASY"),
            ("想轻松跑跑", "EASY"),
            ("能不能快一点", "FAST"),
            ("走跑结合就行", "WALK_RUN"),
            ("中等速度", "MODERATE")
        ]
        for testCase in regexCases {
            XCTAssertEqual(
                MockAPIClient.mockVoicePace(in: testCase.transcript)?.rawValue,
                testCase.expected,
                "Mock 与黄金语料漂移：「\(testCase.transcript)」应为 \(testCase.expected)"
            )
        }

        // golden-corpus: PACE none
        for transcript in ["明天八点从五角场出发跑一小时"] {
            XCTAssertNil(
                MockAPIClient.mockVoicePace(in: transcript),
                "「\(transcript)」没提配速，必须是 nil"
            )
        }
    }

    /// 语料里的每个真实时长都必须**原样保留**。
    ///
    /// 原来这条验的是「取整落点不荒唐（偏差不超过 30 分钟）」—— 那是取整还存在时的将就写法。
    /// 取整删掉之后，正确的断言是零偏差：语料里没有一条超出契约区间，所以一条都不该被改动。
    func testEveryCorpusDurationSurvivesUnchanged() {
        for minutes in [20, 30, 40, 60, 80, 90, 120] {
            XCTAssertEqual(
                VoiceOrderWizard.acceptedDurationMinutes(minutes), minutes,
                "\(minutes) 分钟被改动了 —— 语料里的时长全在 10~300 内，不该有任何夹取"
            )
        }
    }

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
            apiClient: client
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

    /// 同一句话里的地点：「阳光棕榈园」不在 Mock 的关键词表里，抽不出是**预期**的。
    /// 这条断言存在的意义是把「预期抽不出」写死，免得下次又被当成客户端 bug 查一遍。
    func testRealUtterancePlaceIsKnownlyUnsupportedByMock() {
        XCTAssertNil(
            MockAPIClient.mockVoiceAddressSpan(in: "明天早上八点钟从阳光棕榈园跑"),
            "如果这条开始失败，说明 Mock 已经支持这个地点了，把它从『已知不支持』里挪走"
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

    /// 抽到了时间就正常放行 —— 上面那条拦截不能宽到把正常流程也挡了。
    func testConfirmProceedsOnceTheStartTimeWasCaptured() async {
        let stub = VoiceOrderAPIClientStub()
        let plannedStart = DateFormatter.aidRunBackendLocalDateTime.string(
            from: Date().addingTimeInterval(3600 * 24)
        )
        stub.parseOrderResponses = [
            ParseVoiceOrderResponse(
                plannedStartTime: plannedStart, durationMinutes: nil, address: nil,
                latitude: nil, longitude: nil,
                missing: nil, needReask: nil, ttsText: nil
            )
        ]
        // 同上：不强持有的话下面那条断言会因为兜底文案恰好也含「说「确认」就下单」而**假通过**。
        let bookingViewModel = BlindBookingViewModel()
        let wizard = makeWizard(stub: stub, bookingViewModel: bookingViewModel, startingAt: .freeform)

        await wizard.submitTranscript("明天早上八点从人民广场出发")

        XCTAssertTrue(wizard.didCaptureStartTime)
        let spoken = wizard.lastSpokenPrompt ?? ""
        XCTAssertTrue(spoken.contains("这次的预约是："), "念的必须是整单读回而不是兜底提问：\(spoken)")
        XCTAssertTrue(spoken.contains("说「确认」就下单"), "抽到时间后就该正常给出确认这条出路：\(spoken)")
        XCTAssertFalse(spoken.contains("预约时间还没说"))
    }

    // MARK: - 不许把人关在没有出口的循环里
    //
    // 「时间抽不出就不许确认」这条规则必须配一个出口，否则解析这一环一坏就成死循环：
    // 说一整句 → 抽不出时间 → 不给确认 → 「请说重说」→ 重说 → 还是抽不出 → 无限。
    // 2026-08-06 手测就是这么卡住的：用户第二遍明确说了时间，仍然抽不到。
    // 对看不见屏幕的人，没有出口的循环比一条错误信息糟得多。

    /// 端点根本不存在（生产上 `/api/orders/voice/parse` 恒 404）时**一次读回都不做**，直接交回表单。
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
    func testTwoRoundsWithoutAStartTimeFallBackToTheForm() async {
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
        XCTAssertTrue((wizard.fallbackMessage ?? "").contains("表单"))
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
    func testRepeatedSilenceEventuallyFallsBackToTheForm() async {
        let wizard = makeWizard(stub: VoiceOrderAPIClientStub(), startingAt: .freeform)
        let silence = SpeechInputCompletion(
            field: .voiceOrderFreeform,
            recognizedText: "",
            reason: .silenceTimeout(hadDetectedSound: false)
        )

        for _ in 0..<VoiceOrderWizard.maximumReasksPerSlot {
            wizard.handleCompletionForTesting(silence)
        }

        XCTAssertFalse(wizard.isRunning, "连续听不到就该交回表单，不能一直重问")
        XCTAssertNotNil(wizard.fallbackMessage)
        XCTAssertNil(wizard.createdOrder)
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

    // MARK: - 等 TTS 播完再开麦的上限
    //
    // 2026-08-06 真机手测：读回念到一半被切掉，麦克风当场打开。根因是这个上限写死 8 秒，
    // 而读回整单要 15~25 秒 —— 上限一到就开麦，开麦切换音频分类会把正在播的合成器掐断。
    // 上限必须跟着要念的字数走，这一组把这件事钉住。

    /// 读回整单的实际长度量级（原话 + 三个槽位 + 两条出路，约 120 字）必须等得住。
    /// 这条直接对应报障：120 字在旧的 8 秒上限下必被截断。
    func testSettleTimeoutOutlastsAFullReadback() {
        let readback = String(repeating: "字", count: 120)

        let timeout = VoiceOrderWizard.settleTimeout(forCharacterCount: readback.count)

        XCTAssertGreaterThan(
            timeout,
            20,
            "约 120 字的读回念不完就开麦，音频分类切换会把合成器掐断 —— 盲人听到的是一句被切一半的预约"
        )
    }

    /// 短提示的行为不变：下限仍是 8 秒，不因为这次改动被拖长。
    func testSettleTimeoutKeepsTheOldFloorForShortPrompts() {
        XCTAssertEqual(VoiceOrderWizard.settleTimeout(forCharacterCount: 0), 8)
        XCTAssertEqual(VoiceOrderWizard.settleTimeout(forCharacterCount: 5), 8)
    }

    /// 上限存在的理由是合成器代理丢事件时不能无限等 —— 异常长的文本也必须夹住。
    func testSettleTimeoutIsCappedSoALostDelegateCannotHangTheMicrophone() {
        XCTAssertEqual(VoiceOrderWizard.settleTimeout(forCharacterCount: 100_000), 45)
    }

    // MARK: - start() 的门槛接线
    //
    // 上面 28 条用例全部走 `startForTesting(at:)`，**绕过了 `start()`**，所以门槛那三道分支
    // 一条都没被验过 —— 和「兜底坐标让 `.startPoint` 恒真」是同一类：逻辑写对了，但没人证明
    // 它真的被接上。（openspec tasks 3.4 / 3.5）

    private func makeUnstartedWizard(
        bookingViewModel: BlindBookingViewModel,
        speechInputService: SpeechInputService? = nil
    ) -> VoiceOrderWizard {
        let wizard = VoiceOrderWizard()
        wizard.configure(
            bookingViewModel: bookingViewModel,
            speechService: SpeechService(),
            // 参数是非可选的，但 wizard 那侧是 `weak var`：不传时这个临时对象出了本行就释放，
            // wizard 拿到的实际是 nil。走门槛分支的用例本来就不碰语音服务，故此保持现状；
            // 需要真的语音服务的用例（见 testStartFallsBackImmediately...）必须自己 `let` 住再传进来。
            speechInputService: speechInputService ?? SpeechInputService(), // guard:allow weak-temporary
            apiClient: VoiceOrderAPIClientStub()
        )
        return wizard
    }

    /// 四道「本页填不了」的门槛缺任意一道，`start()` 都不得开麦，并且必须把原因说出来。
    ///
    /// 门槛的唯一真源是后端 `OrderCreationService.createOrder`，客户端这份只是把同样的顺序提前。
    /// 让盲人说完一整句才被服务端 403 拒掉是最坏的顺序。
    func testStartIsBlockedByGatesThatVoiceCannotFill() {
        let appState = AppState(persistence: AppStatePersistenceFactory.makeIsolatedTest())
        // 昵称未填 ⇒ basicProfile 缺失，这一道只能去个人资料页补。
        let viewModel = BlindBookingViewModel()
        viewModel.configureForTesting(speechService: SpeechService(), locationService: nil, appState: appState)
        let wizard = makeUnstartedWizard(bookingViewModel: viewModel)

        XCTAssertFalse(wizard.start(), "门槛没过就不该起步")
        XCTAssertFalse(wizard.isRunning)
        XCTAssertEqual(wizard.fallbackMessage, BlindBookingGate.basicProfile.message, "拦住了就必须说得出原因")
    }

    /// 起点与时间**缺失时反而要照常起步** —— 它们正是用户接下来要说出口的槽位。
    ///
    /// ⚠️ openspec tasks 3.4 原文写的是「默认值不可用时**不**出现首步」，那描述属于已被推翻的
    /// `.confirmDefaults` 形态（先念默认值再逐项追问）。现在首步是整句自由说，把这两道门槛
    /// 当成阻断条件会让「没有 GPS 就彻底用不了语音」—— 而语音正是拿来说出发地点的。
    /// `VoiceOrderWizard.start()` 里那两个 `gate != ...` 判断就是这条规则，本用例锁住它。
    func testStartProceedsWhenOnlyTheVoiceFilledSlotsAreMissing() {
        let appState = AppState(persistence: AppStatePersistenceFactory.makeIsolatedTest())
        appState.updateBlindProfile(BlindProfileResponse(name: "测试用户", verifyStatus: "VERIFIED"))
        appState.updateEmergencyContacts([
            EmergencyContactResponse(id: 1, name: "联系人1", phone: "13900139001", relationship: "家人", isPrimary: true)
        ])
        let viewModel = BlindBookingViewModel()
        // ⚠️ 起点缺失必须用 `locationService: nil` 构造，**不能**用裸 `LocationService()`。
        // 后者在真机上是个竞态：`resolvedStartPlace` 只要 `currentLocation != nil` 就成立
        // （`BlindBookingView.swift:358`），而真机几毫秒内就回调出真实坐标，于是起点反而有了、
        // 门槛跳到 `.appointmentTime`。本用例 2026-08-06 首次上真机就是这么红的 ——
        // 它要验的是「起点缺失时照常起步」，跟坐标是不是演示值无关，没必要引入定位的时序。
        viewModel.configureForTesting(speechService: SpeechService(), locationService: nil, appState: appState)
        XCTAssertEqual(viewModel.firstMissingGate, .startPoint, "前提：只差语音要填的槽位")

        let wizard = makeUnstartedWizard(bookingViewModel: viewModel)

        XCTAssertTrue(wizard.start(), "起点缺失恰恰是要用语音补的，不能反过来把语音关掉")
        XCTAssertTrue(wizard.isRunning)
        XCTAssertEqual(wizard.step, .freeform)
        XCTAssertNil(wizard.fallbackMessage)
    }

    /// 语音链路已经在启动阶段失败过（授权被拒 / recognizer 不可用）就直接交回表单。
    /// 明知打不开麦克风还走一遍重问循环，只会让人听三轮「我再问一次」才等到降级。
    func testStartFallsBackImmediatelyWhenTheSpeechPathIsAlreadyKnownBroken() {
        let appState = AppState(persistence: AppStatePersistenceFactory.makeIsolatedTest())
        appState.updateBlindProfile(BlindProfileResponse(name: "测试用户", verifyStatus: "VERIFIED"))
        appState.updateEmergencyContacts([
            EmergencyContactResponse(id: 1, name: "联系人1", phone: "13900139001", relationship: "家人", isPrimary: true)
        ])
        let viewModel = BlindBookingViewModel()
        // `locationService` 在 view model 里是 weak，这里原本传的临时对象当场就释放了 ——
        // 等价于 nil，写成 nil 才不误导。本用例验的是语音链路失败后的降级，与定位无关。
        viewModel.configureForTesting(
            speechService: SpeechService(), locationService: nil, appState: appState
        )
        let speech = SpeechInputService()
        speech.startPendingAuthorizationForTesting(field: .voiceOrderFreeform)
        speech.denyAuthorizationForTesting()
        XCTAssertTrue(speech.isSpeechPathUnavailable, "前提：语音这条路已知不可用")

        let wizard = makeUnstartedWizard(bookingViewModel: viewModel, speechInputService: speech)

        XCTAssertFalse(wizard.start())
        XCTAssertFalse(wizard.isRunning)
        XCTAssertEqual(
            wizard.fallbackMessage,
            "语音输入当前不可用，已切回表单填写，你可以用屏幕上的输入框继续预约。",
            "降级必须说清接下来去哪 —— 看不见屏幕的人没有别的方式发现语音已经停了"
        )
    }

    // MARK: - Helpers

    private func makeWizard(
        stub: VoiceOrderAPIClientStub,
        bookingViewModel: BlindBookingViewModel? = nil,
        speechService: SpeechService = SpeechService(),
        startingAt step: VoiceOrderWizard.Step = .freeform,
        didCaptureStartTime: Bool = false
    ) -> VoiceOrderWizard {
        let bookingViewModel = bookingViewModel ?? BlindBookingViewModel()
        let wizard = VoiceOrderWizard()
        wizard.configure(
            bookingViewModel: bookingViewModel,
            speechService: speechService,
            // 同上：wizard 侧是 weak，这个临时对象等于传 nil。这批用例全走 `startForTesting(at:)`，
            // 不经过真正的开麦路径，所以不需要一个活着的语音服务。
            speechInputService: SpeechInputService(), // guard:allow weak-temporary
            apiClient: stub
        )
        wizard.startForTesting(at: step, didCaptureStartTime: didCaptureStartTime)
        return wizard
    }
}

// MARK: - Stub

private final class VoiceOrderAPIClientStub: APIClientProtocol, @unchecked Sendable {
    enum StubError: Error { case exhausted, unexpectedType }

    var resolveAddressResponses: [ResolveAddressResponse] = []
    var parseOrderResponses: [ParseVoiceOrderResponse] = []
    var parseSlotResponses: [ParseSlotResponse] = []
    var error: APIError?
    /// 在请求发出的那一刻回调。用来观察「等待期间用户听到了什么」—— 这件事只在往返途中成立，
    /// 等 `submitTranscript` 返回时早被读回覆盖了。
    var onRequest: (() -> Void)?
    private(set) var paths: [String] = []
    private(set) var requestedSlotFields: [VoiceSlotField] = []

    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        paths.append(path)
        onRequest?()
        if let error { throw error }
        switch path {
        case VoiceOrderEndpoint.parseOrder:
            guard !parseOrderResponses.isEmpty else { throw StubError.exhausted }
            guard let typed = parseOrderResponses.removeFirst() as? T else {
                throw StubError.unexpectedType
            }
            return typed
        case VoiceOrderEndpoint.resolveAddress:
            guard !resolveAddressResponses.isEmpty else { throw StubError.exhausted }
            guard let typed = resolveAddressResponses.removeFirst() as? T else {
                throw StubError.unexpectedType
            }
            return typed
        case VoiceOrderEndpoint.parseSlot:
            // 整句轮 2026-08-04 起走 `/voice/parse` 单请求，`parse-slot` 只剩定点修改轮在用 ——
            // 那是串行的一轮一个，按队列取就够，不会串台（此前的 by-field 字典已随之删除）。
            if let field = Self.slotField(from: body) { requestedSlotFields.append(field) }
            guard !parseSlotResponses.isEmpty else { throw StubError.exhausted }
            guard let typed = parseSlotResponses.removeFirst() as? T else {
                throw StubError.unexpectedType
            }
            return typed
        default:
            throw StubError.unexpectedType
        }
    }

    func upload<T: Decodable>(
        path: String,
        query: [String: String]?,
        fields: [String: String]?,
        files: [MultipartFile],
        requiresAuth: Bool
    ) async throws -> T {
        throw StubError.unexpectedType
    }

    private static func slotField(from body: (any Encodable & Sendable)?) -> VoiceSlotField? {
        guard let body,
              let data = try? JSONEncoder().encode(ParseSlotRequestBox(body: body)),
              let request = try? JSONDecoder().decode(ParseSlotRequest.self, from: data) else {
            return nil
        }
        return request.field
    }

    private struct ParseSlotRequestBox: Encodable {
        let body: any Encodable & Sendable
        func encode(to encoder: Encoder) throws { try body.encode(to: encoder) }
    }
}
