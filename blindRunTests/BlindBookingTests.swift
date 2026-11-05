import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class BlindBookingTests: XCTestCase {
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

    /// 🚨 **没说时长那一支此前一条测试都没有**，而它才是有代价的那一支。
    ///
    /// `plannedEndTime` 在契约上必填，用户没说时长时客户端补
    /// `AppConstants.Timing.defaultBookingDurationMinutes`。这个数字不是无害的默认值：
    /// 后端 `+15min` 推 `ORDER_OVERDUE`、`+60min` 自动把订单置成 COMPLETED，
    /// 行程分享链接的有效期也跟着它。
    ///
    /// 第二条断言是这条用例真正的重点：**`expectedDurationMinutes` 必须仍是 nil**。
    /// 顺手把兜底值一起填进去，就是把「用户没提」改写成「用户说了一小时」——
    /// 与 `hasGuideDogThisRun` 那条三态红线同一类错误，且同样静默。
    func testCreateOrderRequestFallsBackToTheDefaultDurationWithoutFakingUserIntent() throws {
        let viewModel = BlindBookingViewModel()
        viewModel.selectedStartPlace = ResolvedPlace(
            id: "poi-1",
            title: "科技园地铁站",
            addressText: "深圳市南山区科技园地铁站 A 口",
            latitude: 22.5401,
            longitude: 113.9345,
            source: .manual
        )
        viewModel.appointmentTime = try XCTUnwrap(
            DateFormatter.aidRunBackendLocalDateTime.date(from: "2026-07-06T09:30:00")
        )
        viewModel.duration = .none

        let request = try XCTUnwrap(viewModel.makeCreateOrderRequest())

        XCTAssertEqual(request.plannedStartTime, "2026-07-06T09:30:00")
        XCTAssertEqual(
            request.plannedEndTime,
            "2026-07-06T10:30:00",
            "兜底时长与 AppConstants.Timing.defaultBookingDurationMinutes 对不上"
        )
        XCTAssertNil(
            request.expectedDurationMinutes,
            "把兜底值一起填进 expectedDurationMinutes = 把「用户没提」改写成「用户说了一小时」"
        )
    }

    /// 兜底那一支**必须说出来**。此前整条链一个字都没提：复核页那时显示的是
    /// 「未填写选填跑步需求。」，而请求里已经装着一个具体的结束时刻。
    func testReviewSpeechDisclosesTheDefaultedEndTime() throws {
        let viewModel = BlindBookingViewModel()
        viewModel.selectedStartPlace = ResolvedPlace(
            id: "poi-1",
            title: "科技园地铁站",
            addressText: "深圳市南山区科技园地铁站 A 口",
            latitude: 22.5401,
            longitude: 113.9345,
            source: .manual
        )
        viewModel.appointmentTime = try XCTUnwrap(
            DateFormatter.aidRunBackendLocalDateTime.date(from: "2026-07-06T09:30:00")
        )
        viewModel.duration = .none

        let speech = viewModel.reviewSummarySpeech

        XCTAssertTrue(speech.contains("没有说跑多久"), "没交代这个结束时刻是系统补的：\(speech)")
        XCTAssertTrue(speech.contains("1 小时"), "没说按多久计：\(speech)")
        XCTAssertTrue(speech.contains("10:30"), "没念出具体结束时刻：\(speech)")
    }

    /// 说了时长就只念时刻，**不能还挂着「没有说跑多久」** —— 那是在说用户没做过的事。
    func testReviewSpeechStatesTheEndTimePlainlyWhenDurationWasGiven() throws {
        let viewModel = BlindBookingViewModel()
        viewModel.selectedStartPlace = ResolvedPlace(
            id: "poi-1",
            title: "科技园地铁站",
            addressText: "深圳市南山区科技园地铁站 A 口",
            latitude: 22.5401,
            longitude: 113.9345,
            source: .manual
        )
        viewModel.appointmentTime = try XCTUnwrap(
            DateFormatter.aidRunBackendLocalDateTime.date(from: "2026-07-06T09:30:00")
        )
        viewModel.exactDurationMinutes = 180

        let speech = viewModel.reviewSummarySpeech

        XCTAssertFalse(speech.contains("没有说跑多久"), "用户说了三小时，却被说成没说：\(speech)")
        XCTAssertTrue(speech.contains("12:30"), "结束时刻没跟着精确分钟数走：\(speech)")
    }

    /// 🚨 零输入路径**没有复核屏**，按钮标题就是唯一的复核面（也是它的 accessibilityLabel）。
    /// 而走到这条路径的用户一定没说过时长（他连语音都用不了）⇒ 结束时刻一定是补的那个。
    /// 不念，他就会在 1 小时 15 分时收到一条无从解释的「可能失联」提示。
    func testZeroInputSummaryStatesTheEndTimeItIsAboutToCommit() throws {
        let viewModel = BlindBookingViewModel()
        viewModel.selectedStartPlace = ResolvedPlace(
            id: "poi-1",
            title: "科技园地铁站",
            addressText: "深圳市南山区科技园地铁站 A 口",
            latitude: 22.5401,
            longitude: 113.9345,
            source: .manual
        )
        viewModel.appointmentTime = try XCTUnwrap(
            DateFormatter.aidRunBackendLocalDateTime.date(from: "2026-07-06T09:30:00")
        )

        let summary = viewModel.zeroInputSummary

        XCTAssertTrue(summary.contains("1 小时"), "没说按多久计：\(summary)")
        XCTAssertTrue(summary.contains("10:30"), "没念出结束时刻：\(summary)")
    }

    /// 结束时刻**不许混进选填需求那一段** —— 它是推出来的事实不是用户填的项，
    /// 混进去用户会以为那是自己填过的东西。这两条既有断言正好守住这条边界。
    func testDefaultedEndTimeDoesNotLeakIntoTheOptionalNeedsSection() {
        let viewModel = BlindBookingViewModel()

        XCTAssertTrue(viewModel.optionalReviewItems.isEmpty)
        XCTAssertEqual(viewModel.optionalNeedsSpeechSummary, "没有填写选填跑步需求。")
    }

    func testBlindBookingAuxiliaryMapAccessibilityLabelDoesNotExposeCoordinates() {
        let viewModel = BlindBookingViewModel()
        viewModel.selectedStartPlace = ResolvedPlace(
            id: "poi-1",
            title: "大观楼",
            addressText: "大观楼，西山区 大观路284号",
            latitude: 25.024196,
            longitude: 102.673887,
            source: .manual
        )

        XCTAssertTrue(viewModel.auxiliaryMapAccessibilityLabel.contains("辅助地图"))
        XCTAssertTrue(viewModel.auxiliaryMapAccessibilityLabel.contains("已选择地点"))
        XCTAssertFalse(viewModel.auxiliaryMapAccessibilityLabel.contains("25.024196"))
        XCTAssertFalse(viewModel.auxiliaryMapAccessibilityLabel.contains("102.673887"))
    }

    func testBlindBookingLocationRefreshUpdatesPayloadWhileStabilizingAuxiliaryMapMarker() async throws {
        let locationService = LocationService()
        let initialPlace = ResolvedPlace(
            id: "current-1",
            title: "当前位置",
            addressText: "深圳市南山区科技园",
            latitude: 22.5401,
            longitude: 113.9345,
            source: .deviceLocation
        )
        let smallMovePlace = ResolvedPlace(
            id: "current-2",
            title: "当前位置",
            addressText: "深圳市南山区科技园 A 口",
            latitude: 22.5402,
            longitude: 113.9345,
            source: .deviceLocation
        )
        let largeMovePlace = ResolvedPlace(
            id: "current-3",
            title: "当前位置",
            addressText: "深圳市南山区科技园 B 口",
            latitude: 22.5410,
            longitude: 113.9345,
            source: .deviceLocation
        )
        let provider = FakePlaceSearchProvider(
            results: [],
            reverseGeocodeResults: [initialPlace, smallMovePlace, largeMovePlace]
        )
        let viewModel = BlindBookingViewModel()
        viewModel.configureForTesting(
            placeSearchProvider: provider,
            speechService: SpeechService(),
            locationService: locationService
        )

        await viewModel.refreshCurrentLocation()
        let demoCenter = try XCTUnwrap(viewModel.auxiliaryMapCenter)
        XCTAssertEqual(viewModel.auxiliaryMapPlace?.source, .demoDefault)

        locationService.currentLocation = CLLocationCoordinate2D(latitude: 22.5401, longitude: 113.9345)
        await viewModel.refreshCurrentLocationIfNeeded()
        let initialCenter = try XCTUnwrap(viewModel.auxiliaryMapCenter)
        let initialMapPlace = try XCTUnwrap(viewModel.auxiliaryMapPlace)
        XCTAssertNotEqual(initialCenter.latitude, demoCenter.latitude, accuracy: 0.000001)
        XCTAssertEqual(initialMapPlace.latitude, initialPlace.latitude, accuracy: 0.000001)
        XCTAssertEqual(viewModel.resolvedStartPlace?.addressText, "深圳市南山区科技园")

        locationService.currentLocation = CLLocationCoordinate2D(latitude: 22.5402, longitude: 113.9345)
        await viewModel.refreshCurrentLocationIfNeeded()
        let smallMoveCenter = try XCTUnwrap(viewModel.auxiliaryMapCenter)
        let smallMoveMapPlace = try XCTUnwrap(viewModel.auxiliaryMapPlace)
        let smallMoveRequest = try XCTUnwrap(viewModel.makeCreateOrderRequest())

        XCTAssertEqual(smallMoveCenter.latitude, initialCenter.latitude, accuracy: 0.000001)
        XCTAssertEqual(smallMoveCenter.longitude, initialCenter.longitude, accuracy: 0.000001)
        XCTAssertEqual(smallMoveMapPlace.latitude, initialPlace.latitude, accuracy: 0.000001)
        XCTAssertEqual(smallMoveRequest.startLatitude, smallMovePlace.latitude, accuracy: 0.000001)
        XCTAssertEqual(smallMoveRequest.startAddress, "深圳市南山区科技园 A 口")

        locationService.currentLocation = CLLocationCoordinate2D(latitude: 22.5410, longitude: 113.9345)
        await viewModel.refreshCurrentLocationIfNeeded()
        let largeMoveCenter = try XCTUnwrap(viewModel.auxiliaryMapCenter)
        let largeMoveMapPlace = try XCTUnwrap(viewModel.auxiliaryMapPlace)

        XCTAssertEqual(largeMoveCenter.latitude, initialCenter.latitude, accuracy: 0.000001)
        XCTAssertEqual(largeMoveCenter.longitude, initialCenter.longitude, accuracy: 0.000001)
        XCTAssertEqual(largeMoveMapPlace.latitude, largeMovePlace.latitude, accuracy: 0.000001)
        XCTAssertEqual(viewModel.resolvedStartPlace?.addressText, "深圳市南山区科技园 B 口")

        let selectedPlace = ResolvedPlace(
            id: "poi-2",
            title: "大观楼",
            addressText: "大观楼",
            latitude: 25.024196,
            longitude: 102.673887,
            source: .manual
        )
        viewModel.selectPlace(selectedPlace)
        let selectedCenter = try XCTUnwrap(viewModel.auxiliaryMapCenter)
        let selectedMapPlace = try XCTUnwrap(viewModel.auxiliaryMapPlace)
        let selectedRequest = try XCTUnwrap(viewModel.makeCreateOrderRequest())

        XCTAssertEqual(selectedCenter.latitude, selectedPlace.latitude, accuracy: 0.000001)
        XCTAssertEqual(selectedCenter.longitude, selectedPlace.longitude, accuracy: 0.000001)
        XCTAssertEqual(selectedMapPlace.latitude, selectedPlace.latitude, accuracy: 0.000001)
        XCTAssertEqual(selectedRequest.startLatitude, selectedPlace.latitude, accuracy: 0.000001)

        locationService.currentLocation = CLLocationCoordinate2D(latitude: 22.5500, longitude: 113.9400)
        await viewModel.refreshCurrentLocationIfNeeded()

        XCTAssertEqual(viewModel.resolvedStartPlace?.id, selectedPlace.id)
        XCTAssertEqual(viewModel.auxiliaryMapPlace?.id, selectedPlace.id)
    }

    func testBlindBookingDurationOptions() {
        XCTAssertEqual(BookingDurationOption.sixty.minutes, 60)
        XCTAssertNil(BookingDurationOption.none.minutes)
    }

    func testPacePreferenceDisplayNames() {
        XCTAssertEqual(PacePreference.walkRun.displayName, "走跑结合")
        XCTAssertEqual(PacePreference.easy.displayName, "轻松")
        XCTAssertEqual(PacePreference.moderate.displayName, "中等")
        XCTAssertEqual(PacePreference.fast.displayName, "快速")
        XCTAssertEqual(PacePreference.noPreference.displayName, "无偏好")
    }

    func testRoutePreferenceDisplayNames() {
        XCTAssertEqual(RoutePreference.parkTrail.displayName, "公园步道")
        XCTAssertEqual(RoutePreference.street.displayName, "街道")
        XCTAssertEqual(RoutePreference.track.displayName, "跑道")
        XCTAssertEqual(RoutePreference.noPreference.displayName, "无偏好")
    }

    func testAMapPOIMapsToResolvedPlaceForBookingSearch() throws {
        let poi = AMapPOI()
        poi.uid = "poi-001"
        poi.name = "科技园地铁站"
        poi.district = "南山区"
        poi.address = "A口"
        poi.location = AMapGeoPoint.location(withLatitude: 22.5401, longitude: 113.9345)

        let place = try XCTUnwrap(AMapGeocodingService.resolvedPlace(from: poi))

        XCTAssertEqual(place.id, "poi-001")
        XCTAssertEqual(place.title, "科技园地铁站")
        XCTAssertEqual(place.addressText, "科技园地铁站，南山区 A口")
        XCTAssertEqual(place.latitude, 22.5401, accuracy: 0.000001)
        XCTAssertEqual(place.longitude, 113.9345, accuracy: 0.000001)
        XCTAssertEqual(place.source, .manual)
    }

    @MainActor
    private final class FakePlaceSearchProvider: PlaceSearchProviding {
        var lastErrorMessage: String?
        var searchKeywords: [String] = []
        private let results: [ResolvedPlace]
        private var reverseGeocodeResults: [ResolvedPlace]

        init(
            results: [ResolvedPlace],
            lastErrorMessage: String? = nil,
            reverseGeocodeResults: [ResolvedPlace] = []
        ) {
            self.results = results
            self.lastErrorMessage = lastErrorMessage
            self.reverseGeocodeResults = reverseGeocodeResults
        }

        func reverseGeocode(coordinate: CLLocationCoordinate2D) async -> ResolvedPlace? {
            guard !reverseGeocodeResults.isEmpty else { return nil }
            return reverseGeocodeResults.removeFirst()
        }

        func searchPlaces(keyword: String, near coordinate: CLLocationCoordinate2D?) async -> [ResolvedPlace] {
            searchKeywords.append(keyword)
            return results
        }
    }
}
