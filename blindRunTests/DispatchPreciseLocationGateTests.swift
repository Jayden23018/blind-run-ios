import CoreLocation
import XCTest
@testable import blindRun

/// #520：「精确位置」关着时陪跑员不为派单上报位置（同 #407 同行位置那道闸）。
/// 每条「不发」配一条「精确位置开着照发」的对照：只断不发的话，一个永远不发的实现也会绿。
@MainActor
final class DispatchPreciseLocationGateTests: XCTestCase {

    /// 🔴 复现 #520：精确位置关着，接单开关开着 —— 此前照发约 5 公里偏差的区域代表点。
    func testDispatchReportIsBlockedWhilePreciseLocationIsOff() {
        let (appState, location) = makeVolunteer()
        location.simulatePreciseLocationOffForTesting()

        let sent = VolunteerLocationReporter.reportIfNeeded(
            appState: appState,
            currentLocation: location.currentLocation,
            locationAuthorized: true
        )

        XCTAssertFalse(sent, "精确位置关着还在为派单上报")
        withExtendedLifetime(location) {}
    }

    /// 对照：精确位置开着照常上报。
    func testDispatchReportIsSentWhilePreciseLocationIsOn() {
        let (appState, location) = makeVolunteer()
        location.simulatePreciseLocationOffForTesting(false)

        let sent = VolunteerLocationReporter.reportIfNeeded(
            appState: appState,
            currentLocation: location.currentLocation,
            locationAuthorized: true
        )

        XCTAssertTrue(sent)
        withExtendedLifetime(location) {}
    }

    /// 两条上报路径共用的判定（根视图定时上报也读它）：关着拦、开着放。
    func testSharedGateBlocksOnlyWhilePreciseLocationIsOff() {
        let location = LocationService()
        location.simulatePreciseLocationOffForTesting()
        XCTAssertTrue(VolunteerLocationReporter.isBlockedByPreciseLocation(location))
        location.simulatePreciseLocationOffForTesting(false)
        XCTAssertFalse(VolunteerLocationReporter.isBlockedByPreciseLocation(location))
    }

    /// 告知出现的那一刻：念出原因，并以陪跑员派单的用途申请一次临时精确位置。
    func testNoticeSpeaksAndAsksForTemporaryPreciseLocationForDispatch() {
        let location = LocationService()
        location.simulatePreciseLocationOffForTesting()
        let speech = SpeechService()

        DispatchPreciseLocationCopy.announceBecameVisible(speech: speech, location: location)

        XCTAssertTrue(speech.spokenHistoryForTesting.contains(DispatchPreciseLocationCopy.notice))
        XCTAssertEqual(location.temporaryPreciseLocationRequestsForTesting, [.volunteerDispatch])
    }

    /// 停报的原因要说清：已暂停、后果（收不到附近的邀请）、怎么恢复。
    func testNoticeStatesThePauseTheConsequenceAndTheWayBack() {
        let notice = DispatchPreciseLocationCopy.notice
        for word in ["精确位置", "暂停", "邀请", "系统设置"] {
            XCTAssertTrue(notice.contains(word), "缺「\(word)」：\(notice)")
        }
    }

    // MARK: - Helpers

    /// `LocationService` 由用例攥着：`AppState` 对它是 `weak`。
    private func makeVolunteer() -> (AppState, LocationService) {
        let appState = AppState(persistence: AppStatePersistenceFactory.makeIsolatedTest(), tokenStore: InMemoryTokenStore())
        appState.currentEnvironment = .demoCloud
        appState.accessToken = "token-61"
        appState.userId = 61
        appState.activeRole = .volunteer
        appState.recordLocationTrackConsent(.volunteerLocationTrack)
        let location = LocationService()
        location.simulateDeviceLocationForTesting(
            CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
            capturedAt: Date(),
            horizontalAccuracy: 8
        )
        appState.locationService = location
        return (appState, location)
    }
}
