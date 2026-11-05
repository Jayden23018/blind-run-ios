import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class ExternalMapNavigationTests: XCTestCase {
    func testAMapWrappersHideCompassByDefault() {
        let coordinate = CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074)

        XCTAssertFalse(AMapContainer(centerCoordinate: coordinate).showsCompass)
        XCTAssertFalse(MapViewWrapper(centerCoordinate: coordinate).showsCompass)
    }

    func testExternalMapNavigationAvailabilityFiltersThirdPartySchemes() {
        let providers = ExternalMapNavigationAvailability.availableProviders { url in
            url.scheme == "iosamap"
        }

        XCTAssertEqual(providers, [.amap, .appleMaps])
    }

    func testAMapWalkingURLIncludesOriginDestinationAndWalkingMode() throws {
        let request = makeNavigationRequest()

        let url = try XCTUnwrap(ExternalMapNavigationURLBuilder.amapWalkingURL(request: request))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = try XCTUnwrap(components.queryItems).reduce(into: [String: String]()) { result, item in
            result[item.name] = item.value
        }

        XCTAssertEqual(components.scheme, "iosamap")
        XCTAssertEqual(components.host, "path")
        XCTAssertEqual(query["slat"], "39.904200")
        XCTAssertEqual(query["slon"], "116.407400")
        XCTAssertEqual(query["sname"], "我的位置")
        XCTAssertEqual(query["dlat"], "39.934200")
        XCTAssertEqual(query["dlon"], "116.474000")
        XCTAssertEqual(query["dname"], "朝阳公园南门")
        XCTAssertEqual(query["t"], "2")
        XCTAssertEqual(query["dev"], "0")
    }

    func testBaiduWalkingURLIncludesGCJ02WalkingDirections() throws {
        let request = makeNavigationRequest()

        let url = try XCTUnwrap(ExternalMapNavigationURLBuilder.baiduWalkingURL(request: request))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = try XCTUnwrap(components.queryItems).reduce(into: [String: String]()) { result, item in
            result[item.name] = item.value
        }

        XCTAssertEqual(components.scheme, "baidumap")
        XCTAssertEqual(components.host, "map")
        XCTAssertEqual(components.path, "/direction")
        XCTAssertEqual(query["mode"], "walking")
        XCTAssertEqual(query["coord_type"], "gcj02")
        XCTAssertEqual(query["origin"], "latlng:39.904200,116.407400|name:我的位置")
        XCTAssertEqual(query["destination"], "latlng:39.934200,116.474000|name:朝阳公园南门")
    }

    private func makeNavigationRequest() -> ExternalMapNavigationRequest {
        ExternalMapNavigationRequest(
            originCoordinate: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074),
            originName: "我的位置",
            destinationCoordinate: CLLocationCoordinate2D(latitude: 39.9342, longitude: 116.4740),
            destinationName: "朝阳公园南门"
        )
    }
}
