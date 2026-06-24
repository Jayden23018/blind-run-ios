import CoreLocation
import Foundation

enum VolunteerLocationReporter {
    @discardableResult
    static func reportIfNeeded(
        appState: AppState,
        currentLocation: CLLocationCoordinate2D?,
        locationAuthorized: Bool
    ) -> Bool {
        reportIfNeeded(
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
        send(currentLocation.latitude, currentLocation.longitude)
        return true
    }
}
