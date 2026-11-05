import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class VolunteerHomeSummaryRefreshTests: XCTestCase, BlindRunTestSupport {
    func testVolunteerHomeRefreshesBackendAuthoritativeDispatchSummary() async {
        let client = Self.makeDispatchSummaryService(
            first: .success(Self.dispatchSummaryUnavailable),
            rest: Self.dispatchSummaryAvailable
        )
        let appState = AppState(orders: client)
        let viewModel = VolunteerHomeViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())

        await viewModel.refreshDispatchSummary()
        XCTAssertFalse(viewModel.dispatchSummary?.canDispatch ?? true)
        XCTAssertEqual(viewModel.statusText, "服务端未返回不可接单原因")

        await viewModel.refreshDispatchSummary()
        XCTAssertTrue(viewModel.dispatchSummary?.canDispatch ?? false)
        XCTAssertEqual(viewModel.statusText, VolunteerDispatchSummaryResponse.onlineWaitingText)
        XCTAssertEqual(client.callCount("dispatchSummary()"), 2)
    }

    func testVolunteerHomeSummaryRefreshPreservesActionError() async {
        let client = Self.makeDispatchSummaryService(
            first: .success(Self.dispatchSummaryUnavailable),
            rest: Self.dispatchSummaryAvailable
        )
        let appState = AppState(orders: client)
        let viewModel = VolunteerHomeViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())
        viewModel.errorMessage = "可服务状态更新失败，请重试"

        await viewModel.refreshDispatchSummary()

        XCTAssertEqual(viewModel.errorMessage, "可服务状态更新失败，请重试")
        XCTAssertNil(viewModel.dispatchSummaryErrorMessage)
        XCTAssertEqual(viewModel.displayedErrorMessage, "可服务状态更新失败，请重试")
    }

    func testVolunteerHomeSummaryRefreshErrorRecoversIndependently() async {
        let client = Self.makeDispatchSummaryService(
            first: .failure(APIError.serverError(
                ErrorResponse(code: "DISPATCH_SUMMARY_UNAVAILABLE", message: "派单摘要暂时不可用")
            )),
            rest: Self.dispatchSummaryAvailable
        )
        let appState = AppState(orders: client)
        let viewModel = VolunteerHomeViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())

        await viewModel.refreshDispatchSummary()
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.dispatchSummaryErrorMessage, "派单摘要暂时不可用")
        XCTAssertEqual(viewModel.displayedErrorMessage, "派单摘要暂时不可用")

        await viewModel.refreshDispatchSummary()
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.dispatchSummaryErrorMessage)
        XCTAssertTrue(viewModel.dispatchSummary?.canDispatch ?? false)
    }

    func testVolunteerReconnectImmediatelyReportsLatestLocationAndRefreshesSummary() async {
        let client = Self.makeDispatchSummaryService(
            first: .success(Self.dispatchSummaryUnavailable),
            rest: Self.dispatchSummaryAvailable
        )
        let appState = AppState(orders: client)
        appState.currentEnvironment = .demoCloud
        appState.activeRole = .volunteer
        let service = WebSocketService()
        appState.webSocketService = service
        var reportCount = 0
        let expectedLocation = CLLocationCoordinate2D(latitude: 39.905, longitude: 116.408)
        let viewModel = VolunteerHomeViewModel(
            dispatchPropagationDelay: 0,
            reportVolunteerLocation: { _, location, authorized in
                XCTAssertTrue(authorized)
                XCTAssertEqual(location?.latitude, expectedLocation.latitude)
                XCTAssertEqual(location?.longitude, expectedLocation.longitude)
                reportCount += 1
                return true
            }
        )
        viewModel.configure(
            with: appState,
            speechService: SpeechService(),
            currentLocationProvider: { expectedLocation },
            locationAuthorizedProvider: { true }
        )
        // #368：为派单上报位置的前提是开着接单开关、且本机有志愿者位置轨迹同意。
        appState.recordLocationTrackConsent(.volunteerLocationTrack)
        viewModel.isAvailable = true
        viewModel.setSceneActive(true)

        service.simulateConnectionStateForTesting(.connected)
        service.simulateConnectionStateForTesting(.reconnecting(attempt: 1))
        service.simulateConnectionStateForTesting(.connected)

        let didRecover = await waitUntil {
            reportCount == 1 && client.callCount("dispatchSummary()") == 1
        }
        XCTAssertTrue(didRecover)
        XCTAssertNil(viewModel.locationDispatchWarning)
    }

    /// 生产代码里的连续失败阈值（VolunteerHomeViewModel.locationReportFailureThreshold）。
    private static let locationReportFailureThreshold = 3

    /// 单次采样为 nil 是常见瞬态，必须完全静默：横幅不能闪，也不能播报。
    func testVolunteerSingleLocationReportFailureStaysSilent() async {
        let client = Self.makeDispatchSummaryService(
            first: .success(Self.dispatchSummaryUnavailable),
            rest: Self.dispatchSummaryAvailable
        )
        let appState = AppState(orders: client)
        appState.currentEnvironment = .demoCloud
        let speechService = SpeechService()
        let viewModel = VolunteerHomeViewModel(
            dispatchPropagationDelay: 0,
            reportVolunteerLocation: { _, _, _ in false }
        )
        viewModel.configure(with: appState, speechService: speechService)
        // #368：为派单上报位置的前提是开着接单开关、且本机有志愿者位置轨迹同意。
        appState.recordLocationTrackConsent(.volunteerLocationTrack)
        viewModel.isAvailable = true

        await viewModel.reportLocationThenRefreshSummary(
            currentLocation: nil,
            locationAuthorized: false
        )

        XCTAssertNil(viewModel.locationDispatchWarning)
        XCTAssertNil(speechService.lastSpokenText)
    }

    /// 连续失败达到阈值才报警，且重复失败不重复播报。
    func testVolunteerMissingLocationShowsAndSpeaksDispatchWarningAfterThreshold() async {
        let client = Self.makeDispatchSummaryService(
            first: .success(Self.dispatchSummaryUnavailable),
            rest: Self.dispatchSummaryAvailable
        )
        let appState = AppState(orders: client)
        appState.currentEnvironment = .demoCloud
        let speechService = SpeechService()
        let viewModel = VolunteerHomeViewModel(
            dispatchPropagationDelay: 0,
            reportVolunteerLocation: { _, _, _ in false }
        )
        viewModel.configure(with: appState, speechService: speechService)
        // #368：为派单上报位置的前提是开着接单开关、且本机有志愿者位置轨迹同意。
        appState.recordLocationTrackConsent(.volunteerLocationTrack)
        viewModel.isAvailable = true

        for attempt in 1..<Self.locationReportFailureThreshold {
            await viewModel.reportLocationThenRefreshSummary(
                currentLocation: nil,
                locationAuthorized: false
            )
            XCTAssertNil(viewModel.locationDispatchWarning, "第 \(attempt) 次失败仍应静默")
        }

        await viewModel.reportLocationThenRefreshSummary(
            currentLocation: nil,
            locationAuthorized: false
        )
        XCTAssertEqual(viewModel.locationDispatchWarning, "定位暂不可用，可能无法收到派单")
        XCTAssertEqual(speechService.lastSpokenText, "定位暂不可用，可能无法收到派单")

        // 已在报警状态时再失败，不得重复播报。
        speechService.speak("哨兵播报")
        await viewModel.reportLocationThenRefreshSummary(
            currentLocation: nil,
            locationAuthorized: false
        )
        XCTAssertEqual(viewModel.locationDispatchWarning, "定位暂不可用，可能无法收到派单")
        XCTAssertEqual(speechService.lastSpokenText, "哨兵播报")
    }

    /// 中途上报成功要清空横幅并复位计数，之后再来一次瞬态失败仍然不报警。
    func testVolunteerSuccessfulLocationReportResetsWarningSuppression() async {
        let client = Self.makeDispatchSummaryService(
            first: .success(Self.dispatchSummaryUnavailable),
            rest: Self.dispatchSummaryAvailable
        )
        let appState = AppState(orders: client)
        appState.currentEnvironment = .demoCloud
        let speechService = SpeechService()
        var shouldSucceed = false
        let viewModel = VolunteerHomeViewModel(
            dispatchPropagationDelay: 0,
            reportVolunteerLocation: { _, _, _ in shouldSucceed }
        )
        viewModel.configure(with: appState, speechService: speechService)
        // #368：为派单上报位置的前提是开着接单开关、且本机有志愿者位置轨迹同意。
        appState.recordLocationTrackConsent(.volunteerLocationTrack)
        viewModel.isAvailable = true

        for _ in 0..<Self.locationReportFailureThreshold {
            await viewModel.reportLocationThenRefreshSummary(
                currentLocation: nil,
                locationAuthorized: false
            )
        }
        XCTAssertEqual(viewModel.locationDispatchWarning, "定位暂不可用，可能无法收到派单")

        shouldSucceed = true
        await viewModel.reportLocationThenRefreshSummary(
            currentLocation: CLLocationCoordinate2D(latitude: 39.905, longitude: 116.408),
            locationAuthorized: true
        )
        XCTAssertNil(viewModel.locationDispatchWarning)

        speechService.speak("哨兵播报")
        shouldSucceed = false
        await viewModel.reportLocationThenRefreshSummary(
            currentLocation: nil,
            locationAuthorized: false
        )
        XCTAssertNil(viewModel.locationDispatchWarning, "复位后单次失败必须重新回到静默")
        XCTAssertEqual(speechService.lastSpokenText, "哨兵播报")
    }

    private static var dispatchSummaryUnavailable: VolunteerDispatchSummaryResponse {
        decodeDispatchSummary(#"{"canDispatch":false,"notAvailableReasons":[],"wantsDispatch":true}"#)
    }
}
