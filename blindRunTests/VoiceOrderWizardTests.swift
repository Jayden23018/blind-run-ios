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
    func testAffirmativeTakesTheSubmitPathInsteadOfParsing() async {
        let stub = VoiceOrderAPIClientStub()
        let wizard = makeWizard(stub: stub, startingAt: .confirm)

        await wizard.submitTranscript("确认")

        XCTAssertFalse(wizard.isRunning, "提交后不得继续占着麦克风")
        XCTAssertTrue(stub.paths.isEmpty, "确认判定不走后端：\(stub.paths)")
    }

    /// 「改 X」要跳到对应那一项，而不是从头再问一遍。
    func testFixCommandsJumpToTheNamedSlot() async {
        let cases: [(String, VoiceOrderWizard.Step)] = [
            ("改地点", .startPlace),
            ("改时间", .startTime),
            ("改时长", .duration),
            ("换个地点", .startPlace),
            ("改多久", .duration)
        ]
        for (transcript, expected) in cases {
            let stub = VoiceOrderAPIClientStub()
            let wizard = makeWizard(stub: stub, startingAt: .confirm)

            await wizard.submitTranscript(transcript)

            XCTAssertEqual(wizard.step, expected, "「\(transcript)」应跳到 \(expected)")
            XCTAssertTrue(wizard.isRunning)
            XCTAssertNil(wizard.createdOrder, "修改指令绝不能提交")
            XCTAssertTrue(stub.paths.isEmpty)
        }
    }

    func testCommandClassificationIsWholeStringAndConservative() {
        XCTAssertEqual(VoiceOrderWizard.command(for: "确认"), .confirm)
        XCTAssertEqual(VoiceOrderWizard.command(for: "确认吧"), .confirm)
        XCTAssertEqual(VoiceOrderWizard.command(for: "改时间"), .fix(.startTime))
        XCTAssertEqual(VoiceOrderWizard.command(for: "再说一遍"), .repeatBack)
        // 含肯定词的否定与复核请求：整串匹配的存在理由
        for transcript in ["不确认", "先别确认", "确认一下时间", "还不能确认", "我要修改", "嗯"] {
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
        XCTAssertEqual(viewModel.duration, .sixty)
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
        let wizard = makeWizard(stub: stub, startingAt: .freeform)

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
        XCTAssertTrue(spoken.contains("说「确认」就下单"), "出路照旧念全：\(spoken)")
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
        let wizard = makeWizard(stub: stub, startingAt: .freeform)

        await wizard.submitTranscript("呃那个我想想")

        let spoken = wizard.lastSpokenPrompt ?? ""
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

        XCTAssertEqual(viewModel.duration, .fortyFive, "40 分钟没有对应档位，取最近的 45")
        let spoken = wizard.lastSpokenPrompt ?? ""
        XCTAssertTrue(spoken.contains("你说的是40分钟"), "必须说出用户原本说的数字：\(spoken)")
        XCTAssertTrue(spoken.contains("45"), "必须说出实际下单的时长：\(spoken)")
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

    // MARK: - needReask 不是错误

    /// `needReask: true` 是 HTTP 200 的正常业务状态。把它当成错误分支处理，或者据此推进到下一个槽位，
    /// 都会让盲人在完全没确认地点的情况下被问「什么时候出发」。
    func testNeedReaskKeepsTheSameSlotAndDoesNotAdvance() async {
        let stub = VoiceOrderAPIClientStub()
        stub.resolveAddressResponses = [
            ResolveAddressResponse(
                address: nil, latitude: nil, longitude: nil,
                needReask: true, ttsText: "没听清地点，请再说一次出发地"
            )
        ]
        let wizard = makeWizard(stub: stub)

        await wizard.submitTranscript("嗯那个")

        XCTAssertEqual(wizard.step, .startPlace, "needReask 不得推进到下一个槽位")
        XCTAssertEqual(wizard.reaskCount, 1)
        XCTAssertNil(wizard.fallbackMessage, "一次听不清不该降级")
        XCTAssertEqual(wizard.lastSpokenPrompt, "没听清地点，请再说一次出发地")
    }

    /// 同一个槽位连续听不清就交回表单，并且必须说清楚接下来去哪 —— 看不见屏幕的人没有别的方式
    /// 发现语音已经停了。
    func testThreeConsecutiveReasksFallBackToTheForm() async {
        let stub = VoiceOrderAPIClientStub()
        let reask = ResolveAddressResponse(
            address: nil, latitude: nil, longitude: nil, needReask: true, ttsText: "没听清地点"
        )
        stub.resolveAddressResponses = [reask, reask, reask]
        let wizard = makeWizard(stub: stub)

        for _ in 0..<VoiceOrderWizard.maximumReasksPerSlot {
            await wizard.submitTranscript("听不清的话")
        }

        XCTAssertFalse(wizard.isRunning, "降级后不得继续占着麦克风")
        let fallback = wizard.fallbackMessage ?? ""
        XCTAssertTrue(fallback.contains("表单"), "降级文案必须指出回退到表单：\(fallback)")
        XCTAssertEqual(wizard.step, .startPlace)
    }

    // MARK: - 解析结果回填

    func testResolvedSlotsLandOnTheBookingForm() async {
        let stub = VoiceOrderAPIClientStub()
        stub.resolveAddressResponses = [
            ResolveAddressResponse(
                address: "上海市黄浦区人民广场",
                latitude: 31.2304,
                longitude: 121.4737,
                needReask: false,
                ttsText: "您是说在上海市黄浦区人民广场出发吗？"
            )
        ]
        let plannedStart = DateFormatter.aidRunBackendLocalDateTime.string(
            from: Date().addingTimeInterval(3600 * 24)
        )
        stub.parseSlotResponses = [
            ParseSlotResponse(
                plannedStartTime: plannedStart, durationMinutes: nil,
                needReask: false, ttsText: "好的，明天八点半"
            ),
            ParseSlotResponse(
                plannedStartTime: nil, durationMinutes: 90,
                needReask: false, ttsText: "好的，大约90分钟"
            )
        ]
        let viewModel = BlindBookingViewModel()
        let wizard = makeWizard(stub: stub, bookingViewModel: viewModel)

        // 定点修改：改完一项就回读回环节把整单再念一遍，改完不复核用户无从确认改对了没有。
        await wizard.submitTranscript("人民广场地铁站")
        XCTAssertEqual(wizard.step, .confirm, "改完地点要回到读回")
        XCTAssertEqual(viewModel.selectedStartPlace?.latitude, 31.2304)
        XCTAssertEqual(viewModel.selectedStartPlace?.longitude, 121.4737)
        XCTAssertEqual(viewModel.selectedStartPlace?.addressText, "上海市黄浦区人民广场")

        wizard.startForTesting(at: .startTime)
        await wizard.submitTranscript("明天早上八点半")
        XCTAssertEqual(wizard.step, .confirm, "改完时间要回到读回")
        XCTAssertEqual(
            DateFormatter.aidRunBackendLocalDateTime.string(from: viewModel.appointmentTime),
            plannedStart,
            "开始时间必须原样透传，客户端不得二次格式化"
        )

        wizard.startForTesting(at: .duration)
        await wizard.submitTranscript("跑一个半小时")
        XCTAssertEqual(wizard.step, .confirm, "改完时长要回到读回")
        XCTAssertEqual(viewModel.duration, .ninety)
        XCTAssertNil(wizard.createdOrder, "定点修改绝不自动提交，必须由用户说确认")
    }

    /// 后端接受 10~300 的任意分钟数，表单只有固定档位。取整本身可以接受，**静默**取整不行 ——
    /// 对听不见屏幕的人，没说出口的改动等于没发生。
    func testSnappedDurationIsSpokenOutLoud() async {
        let stub = VoiceOrderAPIClientStub()
        stub.parseSlotResponses = [
            ParseSlotResponse(
                plannedStartTime: nil, durationMinutes: 40, needReask: false, ttsText: "好的，大约40分钟"
            )
        ]
        let viewModel = BlindBookingViewModel()
        let wizard = makeWizard(stub: stub, bookingViewModel: viewModel, startingAt: .duration)

        await wizard.submitTranscript("四十分钟")

        XCTAssertEqual(viewModel.duration, .fortyFive)
        let spoken = wizard.lastSpokenPrompt ?? ""
        XCTAssertTrue(spoken.contains("40"), "必须复述用户说的数字：\(spoken)")
        XCTAssertTrue(spoken.contains("45"), "必须说明实际按哪个档位预约：\(spoken)")
    }

    func testDurationSnappingPicksTheNearestOption() {
        XCTAssertEqual(VoiceOrderWizard.durationOption(forMinutes: 90), .ninety)
        XCTAssertEqual(VoiceOrderWizard.durationOption(forMinutes: 40), .fortyFive)
        XCTAssertEqual(VoiceOrderWizard.durationOption(forMinutes: 10), .fifteen)
        XCTAssertEqual(VoiceOrderWizard.durationOption(forMinutes: 300), .oneTwenty)
        XCTAssertNil(BookingDurationOption.none.minutes)
    }

    // MARK: - 与后端黄金语料对齐

    /// 后端 `demo/docs/voice-golden-corpus.json` 里 `source: "regex"` 的 DURATION 用例。
    ///
    /// 锁的是 **Mock 不许比真实解析器松或紧**：Mock 认得的说法真机上也要认得，Mock 认不得的
    /// （语料里 `source: "llm"` 那几条）在开发期就该走到 `needReask` 分支，否则向导的重问路径
    /// 永远没被走过，上真机才发现是死的。语料由后端维护，这里是它的 iOS 侧镜像。
    func testMockDurationParsingMatchesTheBackendGoldenCorpus() {
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

        // `source: "llm"` 的长尾表达：Mock 没有模型兜底，必须落到 needReask，不能瞎猜一个值。
        for transcript in ["随便说点什么", "陪我跑个把小时吧", "跑到我累了为止"] {
            XCTAssertNil(
                MockAPIClient.mockVoiceMinutes(in: transcript),
                "「\(transcript)」在 Mock 里不该被解析出数值"
            )
        }
    }

    /// 语料里的每个真实时长都要能落到一个档位，且落点不能荒唐（差值不超过一档间距）。
    func testEveryCorpusDurationSnapsToAReasonableOption() {
        for minutes in [20, 30, 40, 60, 80, 90, 120] {
            let option = VoiceOrderWizard.durationOption(forMinutes: minutes)
            let snapped = option.minutes ?? 0
            XCTAssertLessThanOrEqual(
                abs(snapped - minutes), 30,
                "\(minutes) 分钟被取整到 \(snapped) 分钟，偏差过大"
            )
        }
    }

    // MARK: - 网络失败

    /// 解析端点报错不是「没听清」，重问没有意义，直接交回表单。
    func testTransportErrorFallsBackInsteadOfReasking() async {
        let stub = VoiceOrderAPIClientStub()
        stub.error = APIError.serverError(ErrorResponse(code: "INTERNAL_ERROR", message: "服务器内部错误"))
        let wizard = makeWizard(stub: stub)

        await wizard.submitTranscript("人民广场")

        XCTAssertFalse(wizard.isRunning)
        XCTAssertNotNil(wizard.fallbackMessage)
        XCTAssertEqual(wizard.reaskCount, 0, "网络错误不该消耗重问次数")
    }

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

        let slotStub = VoiceOrderAPIClientStub()
        slotStub.parseSlotResponses = [
            ParseSlotResponse(
                plannedStartTime: "2026-08-05T08:00:00", durationMinutes: nil,
                needReask: false, ttsText: nil
            )
        ]
        slotStub.onRequest = { heardWhileWaiting.append(speechService.lastSpokenText ?? "") }
        let slotWizard = makeWizard(
            stub: slotStub, speechService: speechService, startingAt: .startTime
        )
        await slotWizard.submitTranscript("明天早上八点")

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
            startingAt: .confirm
        )

        await wizard.submitTranscript("确认")

        XCTAssertNil(
            wizard.lastSpokenPrompt,
            "等待提示不该进「重复一遍」的记忆，实际留下：「\(wizard.lastSpokenPrompt ?? "")」"
        )
    }

    // MARK: - Helpers

    private func makeWizard(
        stub: VoiceOrderAPIClientStub,
        bookingViewModel: BlindBookingViewModel? = nil,
        speechService: SpeechService = SpeechService(),
        startingAt step: VoiceOrderWizard.Step = .startPlace
    ) -> VoiceOrderWizard {
        let bookingViewModel = bookingViewModel ?? BlindBookingViewModel()
        let wizard = VoiceOrderWizard()
        wizard.configure(
            bookingViewModel: bookingViewModel,
            speechService: speechService,
            speechInputService: SpeechInputService(),
            apiClient: stub
        )
        wizard.startForTesting(at: step)
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
