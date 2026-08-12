import CoreLocation
import Foundation
import MapKit
import UIKit

enum ExternalMapNavigationProvider: String, CaseIterable, Identifiable, Sendable {
    case amap
    case baidu
    case appleMaps

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .amap:
            return "高德地图"
        case .baidu:
            return "百度地图"
        case .appleMaps:
            return "苹果地图"
        }
    }

    var systemImageName: String {
        switch self {
        case .amap, .baidu:
            return "location.fill"
        case .appleMaps:
            return "map.fill"
        }
    }

    var schemeProbeURL: URL? {
        switch self {
        case .amap:
            return URL(string: "iosamap://")
        case .baidu:
            return URL(string: "baidumap://")
        case .appleMaps:
            return nil
        }
    }
}

struct ExternalMapNavigationRequest: Identifiable, Equatable, Sendable {
    let id = UUID()
    let originCoordinate: CLLocationCoordinate2D?
    let originName: String
    let destinationCoordinate: CLLocationCoordinate2D
    let destinationName: String

    static func == (lhs: ExternalMapNavigationRequest, rhs: ExternalMapNavigationRequest) -> Bool {
        lhs.id == rhs.id
    }
}

enum ExternalMapNavigationAvailability {
    @MainActor
    static func availableProviders(
        canOpenURL: (URL) -> Bool = { UIApplication.shared.canOpenURL($0) }
    ) -> [ExternalMapNavigationProvider] {
        ExternalMapNavigationProvider.allCases.filter { provider in
            guard let probeURL = provider.schemeProbeURL else {
                return true
            }
            return canOpenURL(probeURL)
        }
    }
}

enum ExternalMapNavigationURLBuilder {
    static func url(
        for provider: ExternalMapNavigationProvider,
        request: ExternalMapNavigationRequest
    ) -> URL? {
        switch provider {
        case .amap:
            return amapWalkingURL(request: request)
        case .baidu:
            return baiduWalkingURL(request: request)
        case .appleMaps:
            return nil
        }
    }

    static func amapWalkingURL(request: ExternalMapNavigationRequest) -> URL? {
        var components = URLComponents()
        components.scheme = "iosamap"
        components.host = "path"

        var items = [
            URLQueryItem(name: "sourceApplication", value: "助盲跑"),
            URLQueryItem(name: "dlat", value: coordinateString(request.destinationCoordinate.latitude)),
            URLQueryItem(name: "dlon", value: coordinateString(request.destinationCoordinate.longitude)),
            URLQueryItem(name: "dname", value: request.destinationName),
            URLQueryItem(name: "dev", value: "0"),
            URLQueryItem(name: "t", value: "2")
        ]

        if let origin = request.originCoordinate {
            items.append(contentsOf: [
                URLQueryItem(name: "slat", value: coordinateString(origin.latitude)),
                URLQueryItem(name: "slon", value: coordinateString(origin.longitude)),
                URLQueryItem(name: "sname", value: request.originName)
            ])
        }

        components.queryItems = items
        return components.url
    }

    static func baiduWalkingURL(request: ExternalMapNavigationRequest) -> URL? {
        var components = URLComponents()
        components.scheme = "baidumap"
        components.host = "map"
        components.path = "/direction"

        let destination = "latlng:\(coordinateString(request.destinationCoordinate.latitude)),\(coordinateString(request.destinationCoordinate.longitude))|name:\(request.destinationName)"
        var items = [
            URLQueryItem(name: "destination", value: destination),
            URLQueryItem(name: "mode", value: "walking"),
            URLQueryItem(name: "coord_type", value: "gcj02")
        ]

        if let origin = request.originCoordinate {
            let originValue = "latlng:\(coordinateString(origin.latitude)),\(coordinateString(origin.longitude))|name:\(request.originName)"
            items.append(URLQueryItem(name: "origin", value: originValue))
        }

        components.queryItems = items
        return components.url
    }

    private static func coordinateString(_ value: CLLocationDegrees) -> String {
        String(format: "%.6f", value)
    }
}

@MainActor
enum ExternalMapNavigationLauncher {
    static func open(provider: ExternalMapNavigationProvider, request: ExternalMapNavigationRequest) {
        switch provider {
        case .amap, .baidu:
            guard let url = ExternalMapNavigationURLBuilder.url(for: provider, request: request) else { return }
            UIApplication.shared.open(url)
        case .appleMaps:
            openAppleMaps(request: request)
        }
    }

    private static func openAppleMaps(request: ExternalMapNavigationRequest) {
        let destinationPlacemark = MKPlacemark(coordinate: request.destinationCoordinate)
        let destinationItem = MKMapItem(placemark: destinationPlacemark)
        destinationItem.name = request.destinationName

        let launchOptions = [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ]

        if let originCoordinate = request.originCoordinate {
            let originPlacemark = MKPlacemark(coordinate: originCoordinate)
            let originItem = MKMapItem(placemark: originPlacemark)
            originItem.name = request.originName
            MKMapItem.openMaps(with: [originItem, destinationItem], launchOptions: launchOptions)
        } else {
            destinationItem.openInMaps(launchOptions: launchOptions)
        }
    }
}
