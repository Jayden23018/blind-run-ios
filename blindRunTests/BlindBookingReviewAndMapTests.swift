import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class BlindBookingReviewAndMapTests: XCTestCase, BlindRunTestSupport {
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
    /// 「未填写选填跑步需求。」，而请求里已经装着一个具体的结束时刻。语音向导读回念的就是这一句。
    func testPlannedEndSummaryDisclosesTheDefaultedEndTime() throws {
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

        let speech = viewModel.plannedEndSummary

        XCTAssertTrue(speech.contains("没有说跑多久"), "没交代这个结束时刻是系统补的：\(speech)")
        XCTAssertTrue(speech.contains("1 小时"), "没说按多久计：\(speech)")
        XCTAssertTrue(speech.contains("10:30"), "没念出具体结束时刻：\(speech)")
    }

    /// 说了时长就只念时刻，**不能还挂着「没有说跑多久」** —— 那是在说用户没做过的事。
    func testPlannedEndSummaryStatesTheEndTimePlainlyWhenDurationWasGiven() throws {
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

        let speech = viewModel.plannedEndSummary

        XCTAssertFalse(speech.contains("没有说跑多久"), "用户说了三小时，却被说成没说：\(speech)")
        XCTAssertTrue(speech.contains("12:30"), "结束时刻没跟着精确分钟数走：\(speech)")
    }

    /// 结束时刻**不许混进选填需求那一段** —— 它是推出来的事实不是用户填的项，
    /// 混进去用户会以为那是自己填过的东西。这两条既有断言正好守住这条边界。
    func testDefaultedEndTimeDoesNotLeakIntoTheOptionalNeedsSection() {
        let viewModel = BlindBookingViewModel()

        XCTAssertTrue(viewModel.optionalReviewItems.isEmpty)
        XCTAssertEqual(viewModel.optionalNeedsSpeechSummary, "没有填写选填跑步需求。")
    }

    func testBlindBookingLocationRefreshUpdatesPayloadUntilAPlaceIsChosen() async throws {
        let locationService = LocationService()
        let initialPlace = ResolvedPlace(
            id: "current-1", title: "当前位置", addressText: "深圳市南山区科技园", latitude: 22.5401, longitude: 113.9345, source: .deviceLocation
        )
        let smallMovePlace = ResolvedPlace(
            id: "current-2", title: "当前位置", addressText: "深圳市南山区科技园 A 口", latitude: 22.5402, longitude: 113.9345, source: .deviceLocation
        )
        let largeMovePlace = ResolvedPlace(
            id: "current-3", title: "当前位置", addressText: "深圳市南山区科技园 B 口", latitude: 22.5410, longitude: 113.9345, source: .deviceLocation
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

        locationService.currentLocation = CLLocationCoordinate2D(latitude: 22.5401, longitude: 113.9345)
        await viewModel.refreshCurrentLocationIfNeeded()
        XCTAssertEqual(viewModel.resolvedStartPlace?.addressText, "深圳市南山区科技园")

        locationService.currentLocation = CLLocationCoordinate2D(latitude: 22.5402, longitude: 113.9345)
        await viewModel.refreshCurrentLocationIfNeeded()
        let smallMoveRequest = try XCTUnwrap(viewModel.makeCreateOrderRequest())

        XCTAssertEqual(smallMoveRequest.startLatitude, smallMovePlace.latitude, accuracy: 0.000001)
        XCTAssertEqual(smallMoveRequest.startAddress, "深圳市南山区科技园 A 口")

        locationService.currentLocation = CLLocationCoordinate2D(latitude: 22.5410, longitude: 113.9345)
        await viewModel.refreshCurrentLocationIfNeeded()

        XCTAssertEqual(viewModel.resolvedStartPlace?.addressText, "深圳市南山区科技园 B 口")

        let selectedPlace = ResolvedPlace(
            id: "poi-2", title: "大观楼", addressText: "大观楼", latitude: 25.024196, longitude: 102.673887, source: .manual
        )
        viewModel.selectPlace(selectedPlace)
        let selectedRequest = try XCTUnwrap(viewModel.makeCreateOrderRequest())

        XCTAssertEqual(selectedRequest.startLatitude, selectedPlace.latitude, accuracy: 0.000001)

        locationService.currentLocation = CLLocationCoordinate2D(latitude: 22.5500, longitude: 113.9400)
        await viewModel.refreshCurrentLocationIfNeeded()

        XCTAssertEqual(viewModel.resolvedStartPlace?.id, selectedPlace.id)
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
}
