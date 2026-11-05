import CoreLocation
import XCTest
@testable import blindRun

@MainActor
final class VoiceOrderWizardMockCandidateTests: XCTestCase, VoiceOrderWizardTestSupport {

    // MARK: - Mock 的候选消歧

    /// 候选**只在同一个关键词命中 ≥2 条时**产生，而且必须带坐标才有。
    ///
    /// 后者与后端一致：没有坐标就算不出 `distanceMeters`，而缺了距离的同名列表更难选。
    func testMockReturnsCandidatesOnlyForSameNamePlacesWithCoordinates() async throws {
        let client = MockAPIClient()
        client.syncSessionFromAppState(token: "mock_jwt_token_test", role: .blind)

        let withCoordinates: ParseVoiceOrderResponse = try await client.post(
            VoiceOrderEndpoint.parseOrder,
            body: ParseVoiceOrderRequest(
                transcript: "明天早上八点从万象城出发跑一个小时",
                latitude: 22.5300, longitude: 113.9400
            )
        )
        XCTAssertGreaterThanOrEqual(
            withCoordinates.candidates?.count ?? 0, 2,
            "「万象城」在表里有三条同名，带了坐标就该给候选"
        )
        XCTAssertEqual(withCoordinates.startCandidatesToDisambiguate?.count, 3)

        let withoutCoordinates: ParseVoiceOrderResponse = try await client.post(
            VoiceOrderEndpoint.parseOrder,
            body: ParseVoiceOrderRequest(transcript: "明天早上八点从万象城出发跑一个小时")
        )
        XCTAssertEqual(
            withoutCoordinates.candidates, [],
            "没有坐标就没有候选 —— 空数组不是 null，客户端按 count >= 2 判这一轮是不是消歧轮"
        )

        let unique: ParseVoiceOrderResponse = try await client.post(
            VoiceOrderEndpoint.parseOrder,
            body: ParseVoiceOrderRequest(
                transcript: "明天早上八点从人民广场出发跑一个小时",
                latitude: 31.2304, longitude: 121.4737
            )
        )
        XCTAssertEqual(unique.candidates, [], "只有一个同名地点时不该问用户选哪个，那是纯粹多一轮")
    }

    /// 🔴 表里那条 catch-all `("公园", "本市公园")` **不许被当成同名兄弟**。
    ///
    /// 「中山公园」会同时命中 `中山公园` 和 `公园`，若按「所有命中的条目」收候选，
    /// 每个带「公园」二字的地名都会凭空多出一轮消歧 —— 而线上根本没有这回事
    /// （后端是同一个 query 搜出多个同名 POI，不是模糊包含）。
    func testMockCatchAllParkEntryNeverFabricatesCandidates() async throws {
        let client = MockAPIClient()
        client.syncSessionFromAppState(token: "mock_jwt_token_test", role: .blind)

        let response: ParseVoiceOrderResponse = try await client.post(
            VoiceOrderEndpoint.parseOrder,
            body: ParseVoiceOrderRequest(
                transcript: "明天早上八点从中山公园出发跑一个小时",
                latitude: 31.2230, longitude: 121.4200
            )
        )

        XCTAssertEqual(response.candidates, [], "「中山公园」只有一个真实地点，不该被 catch-all 凑成两个")
        XCTAssertNil(response.startCandidatesToDisambiguate)
    }

    /// 候选播报文案的形状要和后端一致 —— **这段话是教用户说什么的**。
    /// Mock 里念得跟线上不一样，开发期练熟的说法上真机就不生效。
    func testMockCandidateTtsMatchesTheBackendShape() async throws {
        let client = MockAPIClient()
        client.syncSessionFromAppState(token: "mock_jwt_token_test", role: .blind)

        let response: ParseVoiceOrderResponse = try await client.post(
            VoiceOrderEndpoint.parseOrder,
            body: ParseVoiceOrderRequest(
                transcript: "明天早上八点从万象城出发跑一个小时",
                latitude: 22.5300, longitude: 113.9400
            )
        )
        let tts = try XCTUnwrap(response.ttsText)

        XCTAssertTrue(tts.hasPrefix("找到3个地点，请说第几个。"), "开头照抄后端 buildCandidateTts：\(tts)")
        for ordinal in VoiceOrderWizard.ordinalWords {
            XCTAssertTrue(tts.contains(ordinal), "序数要逐个念出来，否则用户不知道能说什么：\(tts)")
        }
        XCTAssertTrue(tts.contains("距您"), "距离是同名地点唯一能靠听分辨的信息：\(tts)")
        // 最近的那条排第一 —— 深圳那家离请求坐标最近。
        XCTAssertEqual(response.candidates?.first?.adname, "南山区")
        XCTAssertEqual(response.address, response.candidates?.first?.readbackAddress,
                       "平铺 address 就是候选第一项，老客户端只读它也要能下单")
    }

    /// 「说了地名、但我们没查到」要报出来，而不是静默落回当前位置。
    ///
    /// 后端同批已经不再回落全国范围的正向编码（那条路曾把深圳说的地名解析到海南），
    /// 所以这个 `true` 会**变常见**；Mock 不跟上的话，开发期永远走不到那条播报分支。
    func testMockReportsAddressUnresolvedWhenTheSpanCannotBeGeocoded() async throws {
        let client = MockAPIClient()
        client.syncSessionFromAppState(token: "mock_jwt_token_test", role: .blind)

        let response: ParseVoiceOrderResponse = try await client.post(
            VoiceOrderEndpoint.parseOrder,
            body: ParseVoiceOrderRequest(
                transcript: "明天早上八点钟从阳光棕榈园跑",
                latitude: 22.5333, longitude: 113.9300
            )
        )

        XCTAssertEqual(response.addressUnresolved, true, "抽到了地名却查不到坐标，必须说得出「说了但没查到」")
        XCTAssertTrue(response.missing?.contains(.address) == true)
        XCTAssertEqual(response.candidates, [])
    }
}
