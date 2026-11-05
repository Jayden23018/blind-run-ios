import CoreLocation
import XCTest
@testable import blindRun

@MainActor
final class VoiceOrderWizardPartialStartTimeTests: XCTestCase, VoiceOrderWizardTestSupport {

    // MARK: 半句开始时间 partialStartTime（后端 #501 / 前端 #508）

    private static let halfSaidTomorrowMorning = VoicePartialStartTime(date: "2026-10-05", period: "MORNING")

    /// 契约示例：响应里的 `partialStartTime` 能解出来，并**原样**进下一轮的 `current`。
    /// 不回传的后果是静默的 —— 用户答「九点」会被读成今天 9 点，而不是「后天 9 点」。
    func testPartialStartTimeIsDecodedAndEchoedIntoTheNextRoundsCurrent() throws {
        let json = #"""
        {"missing":["START_TIME"],"needReask":true,"ttsText":"明天早上几点？",
         "partialStartTime":{"date":"2026-10-05","period":"MORNING"}}
        """#
        let response = try JSONDecoder().decode(ParseVoiceOrderResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.partialStartTime, Self.halfSaidTomorrowMorning)
        XCTAssertNil(response.plannedStartTime, "半句时间时 plannedStartTime 必为 null")

        let request = ParseVoiceOrderRequest(transcript: "九点", current: response.slotSnapshot)
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        let partial = (body?["current"] as? [String: Any])?["partialStartTime"] as? [String: Any]
        XCTAssertEqual(partial?["date"] as? String, "2026-10-05")
        XCTAssertEqual(partial?["period"] as? String, "MORNING")
    }

    /// `period` 是响应方向的开放枚举：未知值**不许抛、也不许丢**，要原样回传（契约原话）。
    /// 所以存成字符串 —— 枚举的 `.unknown` 兜底会把原值吞掉，回传就不再是「原样」。
    func testUnknownPartialPeriodSurvivesDecodingAndIsEchoedUnchanged() throws {
        let json = #"{"partialStartTime":{"date":null,"period":"TWILIGHT"}}"#
        let response = try JSONDecoder().decode(ParseVoiceOrderResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.slotSnapshot.partialStartTime?.period, "TWILIGHT")
        XCTAssertNil(response.slotSnapshot.partialStartTime?.date)
    }

    /// 没有半句时间（绝大多数轮次）时请求里**不能多出这个键**；两个字段都空的壳子也不发
    /// （契约：「两个字段至少一个非 null」，空壳发回去可能被后端判校验失败）。
    func testNoPartialStartTimeMeansNoKeyOnTheWire() throws {
        let absent = try JSONDecoder().decode(ParseVoiceOrderResponse.self, from: Data("{}".utf8))
        XCTAssertNil(absent.slotSnapshot.partialStartTime)
        let hollow = Self.parseResponse(partialStartTime: VoicePartialStartTime(date: nil, period: " "))
        XCTAssertNil(hollow.slotSnapshot.partialStartTime, "空壳不带")

        let request = ParseVoiceOrderRequest(transcript: "x", current: absent.slotSnapshot)
        let encoded = try JSONEncoder().encode(request)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("partialStartTime"))
    }

    /// 消歧轮挑定起点只换起点，**不碰时间**：上一轮留下的半句时间要接着带进下一轮。
    func testPickingAStartCandidateKeepsThePartialStartTime() {
        let parsed = Self.parseResponse(
            missing: [.startTime],
            candidates: [Self.candidate("万象城"), Self.candidate("万象城", address: "富春路")],
            partialStartTime: Self.halfSaidTomorrowMorning
        )
        let picked = parsed.replacingStartPlace(with: Self.candidate("万象城"))
        XCTAssertEqual(picked.partialStartTime, Self.halfSaidTomorrowMorning)
        XCTAssertEqual(picked.slotSnapshot.partialStartTime, Self.halfSaidTomorrowMorning)
    }

    /// 🔴 最危险的一条路：「明天早上」这类半句话通常**没说起点**，正好走进确认轮「补设备位置」那处
    /// **手工拼快照**的代码 —— 它漏掉任何字段，字段就在这一轮静默消失。
    /// `address` 非空证明走的确实是那条补位置的分支。
    func testPartialStartTimeSurvivesTheDeviceLocationFallbackSnapshot() async {
        let stub = VoiceOrderAPIClientStub()
        stub.parseOrderResponses = [
            Self.parseResponse(
                durationMinutes: 60,
                missing: [.address, .startTime],
                ttsText: "明天早上几点？",
                partialStartTime: Self.halfSaidTomorrowMorning
            ),
            Self.parseResponse(ttsText: "您想改哪一项？", correctionUnclear: true)
        ]
        let viewModel = BlindBookingViewModel()
        viewModel.applyVoiceResolvedStartPlace(
            address: "上海市黄浦区人民广场 人民大道185号",
            spokenAddress: "人民广场",
            latitude: 31.2304,
            longitude: 121.4737
        )
        let wizard = makeWizard(stub: stub, bookingViewModel: viewModel, startingAt: .freeform)

        await wizard.submitTranscript("明天早上跑一个小时")
        await wizard.submitTranscript("九点")

        let current = stub.parseRequests[1].current
        XCTAssertNotNil(current?.address?.nilIfBlank, "前提：这一轮确实走了「补设备位置」的手工快照")
        XCTAssertEqual(current?.partialStartTime, Self.halfSaidTomorrowMorning)
        XCTAssertNil(current?.plannedStartTime, "半句时间不等于时间：plannedStartTime 一个字都不许有")
    }

    /// 同一条链路，但不经过补位置的分支（响应里已经有起点）。
    func testPartialStartTimeIsCarriedWhenTheResponseAlreadyHasAStartPlace() async {
        let stub = VoiceOrderAPIClientStub()
        stub.parseOrderResponses = [
            Self.parseResponse(
                durationMinutes: 60,
                address: "上海市黄浦区人民广场", latitude: 31.2304, longitude: 121.4737,
                missing: [.startTime],
                partialStartTime: Self.halfSaidTomorrowMorning
            ),
            Self.parseResponse(ttsText: "您想改哪一项？", correctionUnclear: true)
        ]
        let wizard = makeWizard(stub: stub, startingAt: .freeform)

        await wizard.submitTranscript("明天早上从人民广场出发跑一个小时")
        await wizard.submitTranscript("九点")

        XCTAssertEqual(stub.parseRequests[1].current?.partialStartTime, Self.halfSaidTomorrowMorning)
    }

    /// 后端的 `ttsText` 永远是 `missing` 里**第一个**阻断项的追问，而向导顺序是起点在前（后端 #508）。
    /// 整句只说「明天早上」、没说起点时 `missing = [ADDRESS, START_TIME]`，`ttsText` 是起点追问 ——
    /// 念出来之后读回紧接着念「使用设备当前位置」，两句自相矛盾。所以只在开始时间**排第一**时才念。
    ///
    /// 两组输入把三种实现分开：「含 START_TIME 就念」在第一组红，「永远不念」在第二组红。
    func testFreeformReadsTheBackendReaskOnlyWhenStartTimeIsTheFirstMissingSlot() async {
        let deviceStart = BlindBookingViewModel()
        deviceStart.applyVoiceResolvedStartPlace(
            address: "上海市黄浦区人民广场 人民大道185号",
            spokenAddress: "人民广场",
            latitude: 31.2304,
            longitude: 121.4737
        )
        let addressFirst = VoiceOrderAPIClientStub()
        addressFirst.parseOrderResponses = [
            Self.parseResponse(
                durationMinutes: 60,
                missing: [.address, .startTime],
                ttsText: "没听清出发地点，请再说一次，比如“人民广场”",
                partialStartTime: Self.halfSaidTomorrowMorning
            )
        ]
        let first = makeWizard(stub: addressFirst, bookingViewModel: deviceStart, startingAt: .freeform)
        await first.submitTranscript("明天早上跑一个小时")
        let spokenFirst = first.lastSpokenPrompt ?? ""
        XCTAssertTrue(spokenFirst.contains("这次的预约是："), "前提：走到了读回：\(spokenFirst)")
        XCTAssertFalse(spokenFirst.contains("没听清出发地点"), "起点有当前位置兜着，不许再念起点追问：\(spokenFirst)")

        let timeFirst = VoiceOrderAPIClientStub()
        timeFirst.parseOrderResponses = [
            Self.parseResponse(
                durationMinutes: 60,
                address: "上海市黄浦区人民广场", latitude: 31.2304, longitude: 121.4737,
                missing: [.startTime],
                ttsText: "明天早上几点？",
                partialStartTime: Self.halfSaidTomorrowMorning
            )
        ]
        // wizard 对表单 view model 是 weak 引用：不自己持有一个，`makeWizard` 临时 new 的那个出函数就没了，
        // 读回只剩结尾一句（第一次写这条用例时就这么假红过）。
        let spokenStart = BlindBookingViewModel()
        let second = makeWizard(stub: timeFirst, bookingViewModel: spokenStart, startingAt: .freeform)
        await second.submitTranscript("明天早上从人民广场出发跑一个小时")
        let spokenSecond = second.lastSpokenPrompt ?? ""
        XCTAssertTrue(spokenSecond.contains("明天早上几点？"), "开始时间排第一时，后端的反问是这一轮唯一的解释：\(spokenSecond)")
    }
}
