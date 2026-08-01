import XCTest
@testable import blindRun

/// 语音下单向导的状态机。录音那一段由 `SpeechInputService` 自己的用例覆盖，这里锁的是向导独有的三条
/// 规则：`needReask` 不推进、连续听不清要降级回表单、解析结果落到正确的表单字段。
@MainActor
final class VoiceOrderWizardTests: XCTestCase {

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

        await wizard.submitTranscript("人民广场地铁站")
        XCTAssertEqual(wizard.step, .startTime)
        XCTAssertEqual(viewModel.selectedStartPlace?.latitude, 31.2304)
        XCTAssertEqual(viewModel.selectedStartPlace?.longitude, 121.4737)
        XCTAssertEqual(viewModel.selectedStartPlace?.addressText, "上海市黄浦区人民广场")

        await wizard.submitTranscript("明天早上八点半")
        XCTAssertEqual(wizard.step, .duration)
        XCTAssertEqual(
            DateFormatter.aidRunBackendLocalDateTime.string(from: viewModel.appointmentTime),
            plannedStart,
            "开始时间必须原样透传，客户端不得二次格式化"
        )

        await wizard.submitTranscript("跑一个半小时")
        XCTAssertEqual(wizard.step, .review, "三项齐了应停在确认步骤")
        XCTAssertEqual(viewModel.duration, .ninety)
        XCTAssertFalse(wizard.isRunning, "确认步骤不自动提交，必须由用户显式提交")
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

    // MARK: - Helpers

    private func makeWizard(
        stub: VoiceOrderAPIClientStub,
        bookingViewModel: BlindBookingViewModel? = nil,
        startingAt step: VoiceOrderWizard.Step = .startPlace
    ) -> VoiceOrderWizard {
        let bookingViewModel = bookingViewModel ?? BlindBookingViewModel()
        let wizard = VoiceOrderWizard()
        wizard.configure(
            bookingViewModel: bookingViewModel,
            speechService: SpeechService(),
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
    var parseSlotResponses: [ParseSlotResponse] = []
    var error: APIError?
    private(set) var paths: [String] = []

    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        paths.append(path)
        if let error { throw error }
        switch path {
        case VoiceOrderEndpoint.resolveAddress:
            guard !resolveAddressResponses.isEmpty else { throw StubError.exhausted }
            guard let typed = resolveAddressResponses.removeFirst() as? T else {
                throw StubError.unexpectedType
            }
            return typed
        case VoiceOrderEndpoint.parseSlot:
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
}
