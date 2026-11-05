import CoreLocation
import XCTest
@testable import blindRun

@MainActor
final class VoiceOrderWizardAddressShortTests: XCTestCase, VoiceOrderWizardTestSupport {

    // MARK: - addressShort：读回念 POI 名，下单带完整门牌号

    /// **本组的核心不变式**：同一个地址，读回念短名、下单带全名。
    ///
    /// 两者混淆的代价是双向的且都很贵：
    /// - 读回念全名 → 「国定路335号1号楼4层(国权路地铁站4号口步行110米)」听完无从判断，
    ///   而读回存在的唯一意义就是让用户听出「这不是我说的地方」；
    /// - 下单带短名 → 志愿者拿到的地址没有门牌号，**上门找不到人**。
    ///
    /// 后端 `api_spec.yaml:3032` 逐字写了这条分工，本用例是它在 iOS 侧的锚。
    func testReadbackSpeaksThePoiNameWhileTheOrderKeepsTheFullAddress() async {
        let full = "五角场市场监督管理所 国定路335号1号楼4层(国权路地铁站4号口步行110米)"
        let stub = VoiceOrderAPIClientStub()
        stub.parseOrderResponses = [
            ParseVoiceOrderResponse(
                plannedStartTime: "2026-07-25T08:00:00", durationMinutes: 60,
                address: full, latitude: 31.2989, longitude: 121.5036,
                missing: [], needReask: false, ttsText: nil,
                addressShort: "五角场市场监督管理所"
            )
        ]
        let viewModel = BlindBookingViewModel()
        let wizard = makeWizard(stub: stub, bookingViewModel: viewModel, startingAt: .freeform)

        await wizard.submitTranscript("明天早上八点从五角场出发跑一个小时")

        let spoken = wizard.lastSpokenPrompt ?? ""
        XCTAssertTrue(
            spoken.contains("出发地点：五角场市场监督管理所。"),
            "读回要念 POI 名：\(spoken)"
        )
        XCTAssertFalse(
            spoken.contains("国定路335号"),
            "门牌号与步行指引不许进读回 —— 听完无从判断，只会把确认句拖长：\(spoken)"
        )

        let request = viewModel.makeCreateOrderRequest()
        XCTAssertEqual(
            request?.startAddress, full,
            "下单必须带完整地址：短名没有门牌号，志愿者上门找不到人"
        )
    }

    /// 后端没给 `addressShort`（老版本、或正向编码回落路径）时退回完整地址。
    /// **念长一点总好过不念** —— 返 nil 会让读回缺掉「出发地点」一整项。
    func testReadbackFallsBackToTheFullAddressWhenBackendOmitsTheShortForm() async {
        let stub = VoiceOrderAPIClientStub()
        stub.parseOrderResponses = [
            ParseVoiceOrderResponse(
                plannedStartTime: "2026-07-25T08:00:00", durationMinutes: 60,
                address: "上海市黄浦区人民广场", latitude: 31.2304, longitude: 121.4737,
                missing: [], needReask: false, ttsText: nil,
                addressShort: nil
            )
        ]
        let viewModel = BlindBookingViewModel()
        let wizard = makeWizard(stub: stub, bookingViewModel: viewModel, startingAt: .freeform)

        await wizard.submitTranscript("明天早上八点从人民广场出发跑一个小时")

        XCTAssertTrue(
            (wizard.lastSpokenPrompt ?? "").contains("出发地点：上海市黄浦区人民广场。"),
            "没有短名时要念完整地址，不能空着：\(wizard.lastSpokenPrompt ?? "")"
        )
    }

    /// 终点同样是「念短名、下单带全名」。
    func testEndPlaceReadbackSpeaksTheShortFormButShipsTheFullAddress() async {
        let fullEnd = "五角场万达广场 邯郸路600号"
        let stub = VoiceOrderAPIClientStub()
        stub.parseOrderResponses = [
            ParseVoiceOrderResponse(
                plannedStartTime: "2026-07-25T08:00:00", durationMinutes: 60,
                address: "上海市黄浦区人民广场", latitude: 31.2304, longitude: 121.4737,
                missing: [], needReask: false, ttsText: nil,
                endAddress: fullEnd, endAddressShort: "五角场万达广场",
                endLatitude: 31.2989, endLongitude: 121.5036
            )
        ]
        let viewModel = BlindBookingViewModel()
        let wizard = makeWizard(stub: stub, bookingViewModel: viewModel, startingAt: .freeform)

        await wizard.submitTranscript("明天早上八点从人民广场跑到五角场万达跑一个小时")

        let spoken = wizard.lastSpokenPrompt ?? ""
        XCTAssertTrue(spoken.contains("结束地点：五角场万达广场。"), "终点读回要念短名：\(spoken)")
        XCTAssertFalse(spoken.contains("邯郸路600号"), "门牌号不许进读回：\(spoken)")
        XCTAssertEqual(viewModel.makeCreateOrderRequest()?.endAddress, fullEnd)
    }

    /// 从表单搜索里挑了别的地点之后，**读回不许再念上一轮语音的 POI 名**。
    ///
    /// 这条防的是「屏幕上是 A、耳朵里是 B」：出发地点行显示新挑的地址，
    /// 而读回念着上一句话里抽到的名字 —— 而看不见屏幕的人只有耳朵那一路，无从发现。
    func testPickingAPlaceFromTheFormClearsTheVoiceSpokenAddress() {
        let viewModel = BlindBookingViewModel()
        viewModel.applyVoiceResolvedStartPlace(
            address: "五角场市场监督管理所 国定路335号",
            spokenAddress: "五角场市场监督管理所",
            latitude: 31.2989, longitude: 121.5036
        )
        XCTAssertTrue(viewModel.startPointSummary.contains("五角场市场监督管理所。"))

        viewModel.selectPlace(
            ResolvedPlace(
                id: "manual", title: "人民广场", addressText: "上海市黄浦区人民广场",
                latitude: 31.2304, longitude: 121.4737, source: .manual
            ),
            announce: false
        )

        let summary = viewModel.startPointSummary
        XCTAssertFalse(
            summary.contains("五角场"),
            "手动改了起点，读回还念上一轮语音的地名就是屏幕与播报打架：\(summary)"
        )
        XCTAssertTrue(summary.contains("人民广场"), "要念新挑的那个：\(summary)")
    }

    /// 候选消歧挑定之后，读回念**他挑的那个**候选的 POI 名，不是上一轮最佳猜测的名字。
    func testPickingACandidateSpeaksThatCandidatesName() {
        let viewModel = BlindBookingViewModel()
        let parsed = ParseVoiceOrderResponse(
            plannedStartTime: "2026-07-25T08:00:00", durationMinutes: 60,
            address: "五角场 邯郸路", latitude: 31.2989, longitude: 121.5036,
            missing: [], needReask: false, ttsText: nil,
            addressShort: "五角场"
        )
        let picked = AddressCandidate(
            name: "五角场万达广场", address: "邯郸路600号", adname: "杨浦区",
            business: nil, distanceMeters: 800, latitude: 31.3001, longitude: 121.5109
        )

        let replaced = parsed.replacingStartPlace(with: picked)
        XCTAssertEqual(
            replaced.addressShort, "五角场万达广场",
            "挑定之后朗读形态要换成他挑的那个，念旧的等于告诉他挑没生效"
        )
        XCTAssertEqual(replaced.address, picked.readbackAddress, "下单地址仍是 POI 名 + 街道")

        viewModel.applyVoiceResolvedStartPlace(
            address: picked.readbackAddress,
            spokenAddress: picked.name,
            latitude: picked.latitude, longitude: picked.longitude
        )
        XCTAssertTrue(viewModel.startPointSummary.contains("五角场万达广场。"))
        XCTAssertEqual(viewModel.makeCreateOrderRequest()?.startAddress, "五角场万达广场 邯郸路600号")
    }

    /// Mock 的短名口径必须与后端一致，否则离线跑通的读回在真机上是另一个样子。
    func testMockAddressShortTakesThePoiNameAndLeavesShortAddressesAlone() {
        XCTAssertEqual(
            MockAPIClient.mockVoiceAddressShort("五角场市场监督管理所 国定路335号1号楼4层(步行110米)"),
            "五角场市场监督管理所"
        )
        // 正向地理编码回落路径不带 POI 名分隔，契约要求此时**等于** address。
        XCTAssertEqual(
            MockAPIClient.mockVoiceAddressShort("上海市黄浦区人民广场"),
            "上海市黄浦区人民广场"
        )
        XCTAssertNil(MockAPIClient.mockVoiceAddressShort(nil))
        XCTAssertNil(MockAPIClient.mockVoiceAddressShort("   "))
    }

    /// 没说终点就**一个字都不提**。`nil` 的语义是「用户未指定」，不是「原路返回起点」，
    /// 多播一句「本次没有结束地点」会让人以为系统漏听了他没说过的话。
    func testNoEndPlaceMeansTheReadBackNeverMentionsIt() async {
        let stub = VoiceOrderAPIClientStub()
        stub.parseOrderResponses = [
            ParseVoiceOrderResponse(
                plannedStartTime: nil, durationMinutes: 60,
                address: "上海市黄浦区人民广场", latitude: 31.2304, longitude: 121.4737,
                missing: [], needReask: false, ttsText: nil
            )
        ]
        let viewModel = BlindBookingViewModel()
        let wizard = makeWizard(stub: stub, bookingViewModel: viewModel, startingAt: .freeform)

        await wizard.submitTranscript("明天早上八点从人民广场出发跑一个小时")

        XCTAssertNil(viewModel.endPlace)
        XCTAssertFalse(
            (wizard.lastSpokenPrompt ?? "").contains("结束地点"),
            "没说终点就不该出现「结束地点」：\(wizard.lastSpokenPrompt ?? "")"
        )
        let request = viewModel.makeCreateOrderRequest()
        XCTAssertNil(request?.endAddress)
        XCTAssertNil(request?.endLatitude)
        XCTAssertNil(request?.endLongitude)
    }

    /// 第二句没提终点就必须把上一句的终点清掉。
    ///
    /// 屏幕上没有任何终点控件，用户重说一遍之后没有**视觉**线索能发现旧终点还挂着 ——
    /// 只有读回会念，而那时他已经准备说「确认」了。
    func testASecondUtteranceWithoutAnEndPlaceClearsThePreviousOne() async {
        let stub = VoiceOrderAPIClientStub()
        stub.parseOrderResponses = [
            ParseVoiceOrderResponse(
                plannedStartTime: nil, durationMinutes: 60,
                address: "上海市黄浦区人民广场", latitude: 31.2304, longitude: 121.4737,
                missing: [], needReask: false, ttsText: nil,
                endAddress: "上海市杨浦区五角场", endLatitude: 31.2989, endLongitude: 121.5036
            ),
            ParseVoiceOrderResponse(
                plannedStartTime: nil, durationMinutes: 30,
                address: "上海市黄浦区人民广场", latitude: 31.2304, longitude: 121.4737,
                missing: [], needReask: false, ttsText: nil
            )
        ]
        let viewModel = BlindBookingViewModel()
        let wizard = makeWizard(stub: stub, bookingViewModel: viewModel, startingAt: .freeform)

        await wizard.submitTranscript("明天早上八点从人民广场跑到五角场跑一个小时")
        XCTAssertEqual(viewModel.endPlace?.address, "上海市杨浦区五角场", "前提：第一句抽到了终点")

        await wizard.submitTranscript("重说")
        XCTAssertNil(viewModel.endPlace, "「重说」要把上一轮的终点一起清掉")

        await wizard.submitTranscript("明天早上八点从人民广场出发跑半小时")
        XCTAssertNil(viewModel.endPlace, "新一句没提终点，旧终点不许留着")
        XCTAssertFalse((wizard.lastSpokenPrompt ?? "").contains("五角场"))
    }

    /// Mock 的终点抽取：只认「跑到」，且不许和起点抢同一段文字。
    ///
    /// 「明天早上8:00到五角场跑四十分钟」只有一个地点，口语里它就是**出发地**（到那儿去跑）。
    /// 裸「到」也认的话，同一段文字会既当起点又当终点 —— 正是后端 2026-08-09 修掉的 N38。
    func testMockEndSpanOnlyMatchesExplicitRunToPhrasing() {
        let cases: [(transcript: String, expected: String?)] = [
            ("明天早上8:00从人民广场跑到五角场，跑四十分钟", "五角场"),
            ("明天早上8:00跑到五角场，从人民广场出发，跑四十分钟", "五角场"),
            ("明天早上8:00从人民广场出发跑到五角场，跑一个小时", "五角场"),
            ("明天下午三点跑到中山公园，跑半小时", "中山公园"),
            ("明天早上8:00到五角场跑四十分钟", nil),
            ("明天早上八点从人民广场出发跑一个小时", nil)
        ]
        for testCase in cases {
            XCTAssertEqual(
                MockAPIClient.mockVoiceEndSpan(in: testCase.transcript),
                testCase.expected,
                "「\(testCase.transcript)」的终点应为 \(testCase.expected ?? "nil")"
            )
        }
    }
}
