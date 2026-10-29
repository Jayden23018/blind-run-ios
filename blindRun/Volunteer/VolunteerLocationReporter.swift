import CoreLocation
import Foundation

enum VolunteerLocationReporter {
    /// #520：「精确位置」关着时不为派单上报 —— 区域代表点偏差约 5 公里，服务端会按它算「附近」、派错单。
    /// 两条上报路径（这里与根视图的定时上报）读同一个判定，不许各写一份。
    static func isBlockedByPreciseLocation(_ locationService: LocationService?) -> Bool {
        locationService?.isPreciseLocationOff == true
    }

    @discardableResult
    static func reportIfNeeded(
        appState: AppState,
        currentLocation: CLLocationCoordinate2D?,
        locationAuthorized: Bool
    ) -> Bool {
        // #368：没有志愿者位置轨迹同意就不往服务器发位置。接单那一下的补报也算 ——
        // 重装后服务端开关仍开着、同意页还没答或已拒绝时，他照样可能点开一张邀请接下来。
        guard appState.hasLocationTrackConsent(.volunteerLocationTrack) else { return false }
        // 原因由 `DispatchPreciseLocationNotice` 说清。
        guard !isBlockedByPreciseLocation(appState.locationService) else { return false }
        return reportIfNeeded(
            currentLocation: currentLocation,
            locationAuthorized: locationAuthorized,
            shouldReportToCloud: appState.currentEnvironment != .mock,
            send: { lat, lng in
                appState.webSocketService?.sendLocationUpdate(lat: lat, lng: lng)
            }
        )
    }

    @discardableResult
    static func reportIfNeeded(
        currentLocation: CLLocationCoordinate2D?,
        locationAuthorized: Bool,
        shouldReportToCloud: Bool,
        send: (Double, Double) -> Void
    ) -> Bool {
        guard locationAuthorized, shouldReportToCloud, let currentLocation else {
            return false
        }
        guard let normalized = BackendCoordinateNormalizer.normalize(
            LocatedCoordinate(coordinate: currentLocation, system: .wgs84Device, source: .device)
        ) else { return false }
        send(normalized.coordinate.latitude, normalized.coordinate.longitude)
        return true
    }
}
