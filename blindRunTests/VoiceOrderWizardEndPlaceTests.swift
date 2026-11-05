import CoreLocation
import XCTest
@testable import blindRun

@MainActor
final class VoiceOrderWizardEndPlaceTests: XCTestCase, VoiceOrderWizardTestSupport {

    // MARK: - 终点（SPEC B1，2026-08-08 后端新增）

    /// 终点的规则**比起点松一档**，两边不是同一套（`api_spec.yaml:3007-3019`）：
    /// 有地名没坐标算数（高德查不到是正常情况，订单照下），只有坐标没地名不算。
    func testEndPlaceKeepsTheAddressEvenWithoutCoordinatesButNeverTheReverse() {
        let full = ParseVoiceOrderResponse(
            plannedStartTime: nil, durationMinutes: nil, address: nil, latitude: nil, longitude: nil,
            missing: nil, needReask: nil, ttsText: nil,
            endAddress: "上海市杨浦区五角场", endLatitude: 31.2989, endLongitude: 121.5036
        )
        let addressOnly = ParseVoiceOrderResponse(
            plannedStartTime: nil, durationMinutes: nil, address: nil, latitude: nil, longitude: nil,
            missing: nil, needReask: nil, ttsText: nil,
            endAddress: "老王家门口", endLatitude: nil, endLongitude: nil, endAddressUnresolved: true
        )
        let coordinateOnly = ParseVoiceOrderResponse(
            plannedStartTime: nil, durationMinutes: nil, address: nil, latitude: nil, longitude: nil,
            missing: nil, needReask: nil, ttsText: nil,
            endAddress: nil, endLatitude: 31.2989, endLongitude: 121.5036
        )
        // 半个坐标：后端会返 400「终点经纬度必须同时提供」，客户端不许构造出这种请求。
        let halfCoordinate = ParseVoiceOrderResponse(
            plannedStartTime: nil, durationMinutes: nil, address: nil, latitude: nil, longitude: nil,
            missing: nil, needReask: nil, ttsText: nil,
            endAddress: "五角场", endLatitude: 31.2989, endLongitude: nil
        )

        XCTAssertEqual(full.resolvedEndPlace?.latitude, 31.2989)
        XCTAssertEqual(full.resolvedEndPlace?.isUnresolved, false)

        XCTAssertEqual(addressOnly.resolvedEndPlace?.address, "老王家门口")
        XCTAssertEqual(
            addressOnly.resolvedEndPlace?.isUnresolved, true,
            "说了地名但查不到坐标要保留地名 —— 静默丢掉的话，用户明明说了「跑到老王家门口」、"
                + "读回却不念终点，盲人无从分辨是没听到还是没存下"
        )

        XCTAssertNil(coordinateOnly.resolvedEndPlace, "只有坐标没有地名，读回时无从念起")
        XCTAssertNil(halfCoordinate.resolvedEndPlace?.latitude, "半个坐标必须降级成「只有地名」")
        XCTAssertEqual(halfCoordinate.resolvedEndPlace?.address, "五角场")
    }

    /// 未知枚举/缺字段一律不许把整条响应带崩 —— 老客户端收到带终点的响应时表现成
    /// 「说了一整句什么都没发生」，那对盲人就是事故。
    func testEndLocationFieldsDecodeAndAreOptional() throws {
        let withEnd = """
        {"address":"人民广场","latitude":31.2304,"longitude":121.4737,
         "endAddress":"五角场","endLatitude":31.2989,"endLongitude":121.5036,
         "endAddressUnresolved":false,"missing":[],"needReask":false}
        """
        let withoutEnd = """
        {"address":"人民广场","latitude":31.2304,"longitude":121.4737,"missing":[],"needReask":false}
        """

        let a = try JSONDecoder().decode(ParseVoiceOrderResponse.self, from: Data(withEnd.utf8))
        let b = try JSONDecoder().decode(ParseVoiceOrderResponse.self, from: Data(withoutEnd.utf8))

        XCTAssertEqual(a.resolvedEndPlace?.address, "五角场")
        XCTAssertNil(b.resolvedEndPlace, "后端没给终点字段时不能凭空造一个")
        XCTAssertNil(b.endAddressUnresolved)
    }

    /// 终点三件套要一路落到下单请求里。
    func testResolvedEndPlaceReachesTheCreateOrderRequest() async {
        let stub = VoiceOrderAPIClientStub()
        stub.parseOrderResponses = [
            ParseVoiceOrderResponse(
                plannedStartTime: nil, durationMinutes: 60,
                address: "上海市黄浦区人民广场", latitude: 31.2304, longitude: 121.4737,
                missing: [], needReask: false, ttsText: nil,
                endAddress: "上海市杨浦区五角场", endLatitude: 31.2989, endLongitude: 121.5036
            )
        ]
        let viewModel = BlindBookingViewModel()
        let wizard = makeWizard(stub: stub, bookingViewModel: viewModel, startingAt: .freeform)

        await wizard.submitTranscript("明天早上八点从人民广场跑到五角场跑一个小时")

        let request = viewModel.makeCreateOrderRequest()
        XCTAssertEqual(request?.endAddress, "上海市杨浦区五角场")
        XCTAssertEqual(request?.endLatitude, 31.2989)
        XCTAssertEqual(request?.endLongitude, 121.5036)
    }

    /// 查不到坐标时**照样带地名下单**，坐标两个都不许带（只带一个后端返 400）。
    func testUnresolvedEndPlaceStillShipsTheAddressWithoutCoordinates() async {
        let stub = VoiceOrderAPIClientStub()
        stub.parseOrderResponses = [
            ParseVoiceOrderResponse(
                plannedStartTime: nil, durationMinutes: 60,
                address: "上海市黄浦区人民广场", latitude: 31.2304, longitude: 121.4737,
                missing: [], needReask: false, ttsText: nil,
                endAddress: "老王家门口", endLatitude: nil, endLongitude: nil,
                endAddressUnresolved: true
            )
        ]
        let viewModel = BlindBookingViewModel()
        let wizard = makeWizard(stub: stub, bookingViewModel: viewModel, startingAt: .freeform)

        await wizard.submitTranscript("明天早上八点从人民广场跑到老王家门口跑一个小时")

        let request = viewModel.makeCreateOrderRequest()
        XCTAssertEqual(request?.endAddress, "老王家门口")
        XCTAssertNil(request?.endLatitude)
        XCTAssertNil(request?.endLongitude)
    }

    /// 读回：终点必须**紧跟起点**念，而且要说清没定位到。
    ///
    /// 位置不是排版偏好 —— 起终点由大模型抽取，抽反了（把出发地听成目的地）只有读回能被用户
    /// 发现，而两句挨着才听得出反没反。中间隔着预约时间就听不出来了。
    func testEndPlaceIsReadBackRightAfterTheStartPlace() async {
        let stub = VoiceOrderAPIClientStub()
        stub.parseOrderResponses = [
            ParseVoiceOrderResponse(
                plannedStartTime: nil, durationMinutes: 60,
                address: "上海市黄浦区人民广场", latitude: 31.2304, longitude: 121.4737,
                missing: [], needReask: false, ttsText: nil,
                endAddress: "老王家门口", endLatitude: nil, endLongitude: nil,
                endAddressUnresolved: true
            )
        ]
        let viewModel = BlindBookingViewModel()
        let wizard = makeWizard(stub: stub, bookingViewModel: viewModel, startingAt: .freeform)

        await wizard.submitTranscript("明天早上八点从人民广场跑到老王家门口跑一个小时")

        let spoken = wizard.lastSpokenPrompt ?? ""
        XCTAssertTrue(spoken.contains("结束地点：老王家门口"), "读回必须念出终点：\(spoken)")
        XCTAssertTrue(
            spoken.contains("这个地点没能定位到"),
            "查不到坐标要说出来，否则盲人会以为终点已经定准了：\(spoken)"
        )
        guard let start = spoken.range(of: "出发地点"),
              let end = spoken.range(of: "结束地点"),
              let time = spoken.range(of: "预约时间") else {
            return XCTFail("读回里缺了起点 / 终点 / 时间之一：\(spoken)")
        }
        XCTAssertTrue(start.lowerBound < end.lowerBound, "终点要排在起点后面：\(spoken)")
        XCTAssertTrue(
            end.lowerBound < time.lowerBound,
            "终点必须紧跟起点、排在预约时间之前 —— 隔开就听不出起终点被抽反了：\(spoken)"
        )
    }
}
