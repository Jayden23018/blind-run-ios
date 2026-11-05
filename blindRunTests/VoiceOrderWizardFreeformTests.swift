import CoreLocation
import XCTest
@testable import blindRun

@MainActor
final class VoiceOrderWizardFreeformTests: XCTestCase, VoiceOrderWizardTestSupport {

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

    /// 三个可选槽位（导盲犬 / 配速 / 备注）必须真的落到订单上，并且**读回要念出来**。
    ///
    /// 回归的是一条静默缺陷：模型层 2026-08-04 就解出了这三项，向导却一个都没消费，
    /// 于是「带导盲犬」被解析出来之后原地丢掉。`hasGuideDogThisRun` 进派单**硬过滤**，
    /// 丢掉它等于按档案默认值缩小候选池，而读回不提这一项，盲人无从察觉。
    func testFreeformAppliesOptionalSlotsAndReadsThemBack() async {
        let stub = VoiceOrderAPIClientStub()
        stub.parseOrderResponses = [
            ParseVoiceOrderResponse(
                plannedStartTime: DateFormatter.aidRunBackendLocalDateTime.string(
                    from: Date().addingTimeInterval(3600 * 24)
                ),
                durationMinutes: 60,
                address: "上海市黄浦区人民广场",
                latitude: 31.2304,
                longitude: 121.4737,
                missing: [],
                needReask: false,
                ttsText: "好的，我记下了",
                hasGuideDog: true,
                pacePreference: .easy,
                specialNotes: "我有低血糖"
            )
        ]
        let viewModel = BlindBookingViewModel()
        let wizard = makeWizard(stub: stub, bookingViewModel: viewModel, startingAt: .freeform)

        await wizard.submitTranscript("明天早上八点从人民广场出发跑一个小时，带导盲犬，慢一点，我有低血糖")

        XCTAssertEqual(viewModel.hasGuideDogThisRun, true)
        XCTAssertEqual(viewModel.pacePreference, .easy)
        XCTAssertEqual(viewModel.specialNotes, "我有低血糖")

        let readback = wizard.lastSpokenPrompt ?? ""
        XCTAssertTrue(readback.contains("本次携带"), "读回必须念出导盲犬：\(readback)")
        XCTAssertTrue(readback.contains("我有低血糖"), "读回必须念出备注：\(readback)")

        let request = viewModel.makeCreateOrderRequest()
        XCTAssertEqual(request?.hasGuideDogThisRun, true)
        XCTAssertEqual(request?.pacePreference, .easy)
        XCTAssertEqual(request?.specialNotes, "我有低血糖")
    }

    /// 「今天不带导盲犬」（`false`）与「压根没提」（`nil`）在下单请求里**必须是两个不同的值**。
    ///
    /// 塌缩成同一个值的后果是静默的：`false` 变 `nil` 时后端回落 `BlindProfile.hasGuideDog`，
    /// 档案里登记了导盲犬的用户明说了「今天不带」仍会按"带"派单，候选池被无声缩小；
    /// 反过来 `nil` 变 `false` 则是替一个什么都没说的用户表了态。两个方向都听不出来。
    func testFreeformKeepsExplicitNoGuideDogDistinctFromUnspoken() async {
        func request(forParsedGuideDog parsed: Bool?) async -> CreateOrderRequest? {
            let stub = VoiceOrderAPIClientStub()
            stub.parseOrderResponses = [
                ParseVoiceOrderResponse(
                    plannedStartTime: DateFormatter.aidRunBackendLocalDateTime.string(
                        from: Date().addingTimeInterval(3600 * 24)
                    ),
                    durationMinutes: 60,
                    address: "上海市黄浦区人民广场",
                    latitude: 31.2304,
                    longitude: 121.4737,
                    missing: [],
                    needReask: false,
                    ttsText: "好的，我记下了",
                    hasGuideDog: parsed
                )
            ]
            let viewModel = BlindBookingViewModel()
            let wizard = makeWizard(stub: stub, bookingViewModel: viewModel, startingAt: .freeform)
            await wizard.submitTranscript("明天早上八点从人民广场出发跑一个小时")
            return viewModel.makeCreateOrderRequest()
        }

        let explicitNo = await request(forParsedGuideDog: false)
        XCTAssertEqual(explicitNo?.hasGuideDogThisRun, false, "「今天不带」必须原样传 false，不能塌成 nil")

        let unspoken = await request(forParsedGuideDog: nil)
        XCTAssertNil(unspoken?.hasGuideDogThisRun, "没提就不传，让后端回落档案默认值")
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
}
