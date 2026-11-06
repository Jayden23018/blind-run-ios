import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class BlindBookingTests: XCTestCase, BlindRunTestSupport {
    func testCreateOrderRequestUsesOpenAPIWireValues() throws {
        let request = CreateOrderRequest(
            startLatitude: 31.2304,
            startLongitude: 121.4737,
            startAddress: "人民广场",
            endAddress: nil,
            endLatitude: nil,
            endLongitude: nil,
            plannedStartTime: "2026-05-22T09:00:00Z",
            plannedEndTime: "2026-05-22T10:00:00Z",
            expectedDurationMinutes: 60,
            pacePreference: .easy,
            routePreference: .parkTrail,
            routeNotes: "公园慢跑一圈",
            hasGuideDogThisRun: false,
            specialNotes: "请在地铁口见面"
        )

        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["startLatitude"] as? Double, 31.2304)
        XCTAssertEqual(json["startLongitude"] as? Double, 121.4737)
        XCTAssertEqual(json["startAddress"] as? String, "人民广场")
        XCTAssertEqual(json["routeNotes"] as? String, "公园慢跑一圈")
        XCTAssertEqual(json["specialNotes"] as? String, "请在地铁口见面")
        XCTAssertEqual(json["pacePreference"] as? String, "EASY")
        XCTAssertEqual(json["routePreference"] as? String, "PARK_TRAIL")
    }

    func testBlindBookingResolvedStartLocationKeepsCoordinatesAndAppendsManualDescription() {
        let viewModel = BlindBookingViewModel()
        viewModel.currentResolvedPlace = ResolvedPlace(
            id: "current",
            title: "当前位置",
            addressText: "上海市黄浦区人民广场",
            latitude: 31.2304,
            longitude: 121.4737,
            source: .deviceLocation
        )
        viewModel.startLocationDescription = "我在地铁口外侧"

        XCTAssertEqual(viewModel.resolvedStartPlace?.latitude, 31.2304)
        XCTAssertEqual(viewModel.resolvedStartPlace?.longitude, 121.4737)
        XCTAssertEqual(viewModel.resolvedStartPlace?.source, .deviceLocation)
        XCTAssertEqual(viewModel.resolvedStartLocationDescription, "上海市黄浦区人民广场；补充：我在地铁口外侧")
    }

    func testBlindBookingSpeechCompletionAutoSearchesStartPlaceAndAllowsRepeatedKeywordRetry() async {
        let place = ResolvedPlace(
            id: "poi-1",
            title: "大观楼",
            addressText: "大观楼，西山区 大观路284号",
            latitude: 25.024196,
            longitude: 102.673887,
            source: .manual
        )
        let provider = FakePlaceSearchProvider(results: [
            place
        ])
        let speechService = SpeechService()
        let viewModel = BlindBookingViewModel()
        viewModel.configureForTesting(placeSearchProvider: provider, speechService: speechService)

        await viewModel.handlePlaceSearchSpeechCompletion(SpeechInputCompletion(
            field: .startPlaceSearch,
            recognizedText: "大观",
            reason: .silenceTimeout(hadDetectedSound: true)
        ))
        viewModel.selectPlace(place)
        await viewModel.handlePlaceSearchSpeechCompletion(SpeechInputCompletion(
            field: .startPlaceSearch,
            recognizedText: " 大观 ",
            reason: .finalResult
        ))

        XCTAssertEqual(provider.searchKeywords, ["大观", "大观"])
        XCTAssertEqual(viewModel.placeSearchKeyword, "大观")
        XCTAssertEqual(viewModel.placeSearchResults.map(\.title), ["大观楼"])
        XCTAssertEqual(viewModel.searchResultFocusID, "poi-1")
        XCTAssertEqual(speechService.lastVoiceOverAnnouncement, "已找到 1 个地点，第一个是 大观楼。")
    }

    func testBlindBookingSpeechCompletionSkipsErrorAndNoSpeechTimeout() async {
        let provider = FakePlaceSearchProvider(results: [])
        let speechService = SpeechService()
        let viewModel = BlindBookingViewModel()
        viewModel.configureForTesting(placeSearchProvider: provider, speechService: speechService)

        await viewModel.handlePlaceSearchSpeechCompletion(SpeechInputCompletion(
            field: .startPlaceSearch,
            recognizedText: "大观",
            reason: .silenceTimeout(hadDetectedSound: false)
        ))
        await viewModel.handlePlaceSearchSpeechCompletion(SpeechInputCompletion(
            field: .startPlaceSearch,
            recognizedText: "大观",
            reason: .error
        ))

        XCTAssertTrue(provider.searchKeywords.isEmpty)
        XCTAssertTrue(viewModel.placeSearchResults.isEmpty)
    }

    func testResolvedPlaceBookingSearchAccessibilityLabelDoesNotExposeCoordinates() {
        let place = ResolvedPlace(
            id: "poi-1",
            title: "大观楼",
            addressText: "大观楼，西山区 大观路284号",
            latitude: 25.024196,
            longitude: 102.673887,
            source: .manual
        )

        XCTAssertEqual(place.bookingSearchAccessibilityLabel, "选择出发地点，大观楼，大观楼，西山区 大观路284号")
        XCTAssertFalse(place.bookingSearchAccessibilityLabel.contains("纬度"))
        XCTAssertFalse(place.bookingSearchAccessibilityLabel.contains("经度"))
        XCTAssertFalse(place.bookingSearchAccessibilityLabel.contains("25.024196"))
        XCTAssertFalse(place.bookingSearchAccessibilityLabel.contains("102.673887"))
    }

    func testBlindBookingRequiresAppointmentAtLeastThirtyMinutesLater() {
        let viewModel = BlindBookingViewModel()

        viewModel.appointmentTime = Date().addingTimeInterval(10 * 60)

        XCTAssertFalse(viewModel.isAppointmentTimeValid)

        // ⚠️ 不能写 `Date() + 31 分钟`：夜间禁跑窗口上线后那个时刻在 21:29–05:00 之间不合法，
        // 用例会白天绿、夜里红。见 `BookingTimeFixture` 的注释。
        viewModel.appointmentTime = BookingTimeFixture.daytime()

        XCTAssertTrue(viewModel.isAppointmentTimeValid)
    }

    func testBlindBookingGuidedStepValidationBlocksInvalidAppointmentAndSpeaksReason() {
        let speechService = SpeechService()
        let viewModel = BlindBookingViewModel()
        // 不传 placeSearchProvider：它在 view model 里是 weak，原先传的临时对象当场就释放，
        // 等于没传；这两条用例也确实不搜地点。
        viewModel.configureForTesting(speechService: speechService)
        viewModel.currentStep = .appointmentTime
        viewModel.appointmentTime = Date().addingTimeInterval(10 * 60)

        viewModel.moveToNextStep()

        XCTAssertEqual(viewModel.currentStep, .appointmentTime)
        // 🚩 断言打在 `BookingTimeProblem.tooSoon.message` 上而不是抄一句字面量：
        // 那个数字来自 `AppConstants.Timing.minimumBookingLeadMinutes`，抄进用例就等于
        // 再造一份会漂的副本 —— 这条用例上一次红，红的正是「实现改从常量取、用例还抄着 30」。
        XCTAssertEqual(viewModel.errorMessage, BookingTimeProblem.tooSoon.message)
        XCTAssertEqual(speechService.lastSpokenText, BookingTimeProblem.tooSoon.message)
        // 与常量同源这件事本身也要钉住，否则上面两条在文案退回硬编码时照样绿。
        XCTAssertTrue(
            BookingTimeProblem.tooSoon.message
                .contains("\(AppConstants.Timing.minimumBookingLeadMinutes)"),
            "提前量必须从常量取，写死会在后端调整窗口时变成假话"
        )
        XCTAssertFalse(viewModel.canAdvanceFromCurrentStep)
    }

    func testBlindBookingGuidedStepSummariesOmitEmptyOptionalNeeds() {
        let speechService = SpeechService()
        let viewModel = BlindBookingViewModel()
        // 不传 placeSearchProvider：它在 view model 里是 weak，原先传的临时对象当场就释放，
        // 等于没传；这两条用例也确实不搜地点。
        viewModel.configureForTesting(speechService: speechService)
        viewModel.currentStep = .runningNeeds

        XCTAssertTrue(viewModel.optionalReviewItems.isEmpty)
        XCTAssertEqual(viewModel.optionalNeedsSpeechSummary, "没有填写选填跑步需求。")

        viewModel.routeNotes = "沿公园慢跑一圈"
        viewModel.pacePreference = .easy
        viewModel.specialNotes = "我会带导盲杖"
        viewModel.repeatCurrentStepStatus()

        XCTAssertEqual(viewModel.optionalReviewItems.map(\.title), ["路线备注", "配速偏好", "特殊说明"])
        XCTAssertTrue(speechService.lastSpokenText?.contains("路线备注：沿公园慢跑一圈") == true)
        XCTAssertTrue(speechService.lastSpokenText?.contains("配速偏好：轻松") == true)
        XCTAssertFalse(speechService.lastSpokenText?.contains("预计时长") == true)
        XCTAssertFalse(speechService.lastSpokenText?.contains("路线偏好") == true)
    }

    /// #797：资料有默认配速、这次没选时，表单要显示它并说明来源，但下单请求仍不带配速。
    ///
    /// 请求那条断言是分辨用的：把默认值抄进 `pacePreference` 的实现，显示照样对，
    /// 但请求里会多出 `EASY` —— 这里会红。
    func testProfileDefaultPaceIsShownWithSourceButNotSent() throws {
        let appState = AppState(persistence: AppStatePersistenceFactory.makeIsolatedTest())
        appState.updateBlindProfile(BlindProfileResponse(name: "测试用户", defaultPace: .easy))
        let viewModel = BlindBookingViewModel()
        viewModel.configureForTesting(speechService: SpeechService(), appState: appState)
        viewModel.selectedStartPlace = ResolvedPlace(
            id: "poi-1", title: "人民广场", addressText: "上海市黄浦区人民广场",
            latitude: 31.2304, longitude: 121.4737, source: .manual
        )

        XCTAssertEqual(viewModel.pacePreference, .noPreference, "默认值不许抄进这次的选择")
        XCTAssertEqual(viewModel.paceOptionTitle(.noPreference), "资料里的默认：轻松")
        XCTAssertEqual(viewModel.paceOptionTitle(.moderate), "中等")
        let paceItem = try XCTUnwrap(viewModel.optionalReviewItems.first { $0.id == "pace" })
        XCTAssertEqual(paceItem.value, "轻松，资料里的默认")
        XCTAssertTrue(viewModel.optionalNeedsSpeechSummary.contains("配速偏好：轻松，资料里的默认"))
        XCTAssertNil(try XCTUnwrap(viewModel.makeCreateOrderRequest()).pacePreference,
                     "没选配速时不传，由后端回落资料默认值")

        viewModel.pacePreference = .moderate

        XCTAssertEqual(viewModel.optionalReviewItems.first { $0.id == "pace" }?.value, "中等")
        XCTAssertEqual(try XCTUnwrap(viewModel.makeCreateOrderRequest()).pacePreference, .moderate)
    }

    func testNoProfileDefaultPaceKeepsNoPreferenceTitleAndNoReviewItem() {
        let appState = AppState(persistence: AppStatePersistenceFactory.makeIsolatedTest())
        appState.updateBlindProfile(BlindProfileResponse(name: "测试用户", defaultPace: .noPreference))
        let viewModel = BlindBookingViewModel()
        viewModel.configureForTesting(speechService: SpeechService(), appState: appState)

        XCTAssertNil(viewModel.profileDefaultPace)
        XCTAssertEqual(viewModel.paceOptionTitle(.noPreference), "无偏好")
        XCTAssertFalse(viewModel.optionalReviewItems.contains { $0.id == "pace" })
    }

    func testBlindBookingCreateOrderRequestKeepsPayloadFieldsThroughGuidedFlow() throws {
        let viewModel = BlindBookingViewModel()
        viewModel.selectedStartPlace = ResolvedPlace(
            id: "poi-1",
            title: "科技园地铁站",
            addressText: "深圳市南山区科技园地铁站 A 口",
            latitude: 22.5401,
            longitude: 113.9345,
            source: .manual
        )
        viewModel.startLocationDescription = "我在 A 口外侧"
        viewModel.appointmentTime = try XCTUnwrap(DateFormatter.aidRunBackendLocalDateTime.date(from: "2026-07-06T09:30:00"))
        viewModel.duration = .sixty
        viewModel.pacePreference = .moderate
        viewModel.routePreference = .parkTrail
        viewModel.routeNotes = "沿公园慢跑一圈"
        viewModel.hasGuideDogThisRun = true
        viewModel.specialNotes = "我会带导盲杖"

        let request = try XCTUnwrap(viewModel.makeCreateOrderRequest())

        XCTAssertEqual(request.startLatitude, 22.5401, accuracy: 0.000001)
        XCTAssertEqual(request.startLongitude, 113.9345, accuracy: 0.000001)
        XCTAssertEqual(request.startAddress, "深圳市南山区科技园地铁站 A 口；补充：我在 A 口外侧")
        XCTAssertEqual(request.plannedStartTime, "2026-07-06T09:30:00")
        XCTAssertEqual(request.plannedEndTime, "2026-07-06T10:30:00")
        XCTAssertEqual(request.expectedDurationMinutes, 60)
        XCTAssertEqual(request.pacePreference, .moderate)
        XCTAssertEqual(request.routePreference, .parkTrail)
        XCTAssertEqual(request.routeNotes, "沿公园慢跑一圈")
        XCTAssertEqual(request.hasGuideDogThisRun, true)
        XCTAssertEqual(request.specialNotes, "我会带导盲杖")
    }
}
