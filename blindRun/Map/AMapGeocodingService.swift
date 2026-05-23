import AMapSearchKit
import Combine
import CoreLocation
import Foundation

// MARK: - Resolved Place

struct ResolvedPlace: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let addressText: String
    let latitude: Double
    let longitude: Double
    let source: LocationSource

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - AMap Geocoding Service

/// AMap Search wrapper for reverse geocoding and place suggestions.
/// It only resolves selectable order start locations; it does not provide route navigation.
@MainActor
final class AMapGeocodingService: NSObject, ObservableObject {
    @Published private(set) var lastErrorMessage: String?

    private let search = AMapSearchAPI()
    private var reverseContinuation: CheckedContinuation<ResolvedPlace?, Never>?
    private var tipsContinuation: CheckedContinuation<[ResolvedPlace], Never>?

    override init() {
        super.init()
        search?.delegate = self
    }

    deinit {
        search?.delegate = nil
    }

    func reverseGeocode(coordinate: CLLocationCoordinate2D) async -> ResolvedPlace? {
        guard AMapManager.isConfigured else {
            lastErrorMessage = "高德地图未配置，使用坐标作为出发地点。"
            return nil
        }

        reverseContinuation?.resume(returning: nil)
        reverseContinuation = nil

        let request = AMapReGeocodeSearchRequest()
        request.location = AMapGeoPoint.location(
            withLatitude: CGFloat(coordinate.latitude),
            longitude: CGFloat(coordinate.longitude)
        )
        request.radius = 500
        request.requireExtension = true

        return await withCheckedContinuation { continuation in
            reverseContinuation = continuation
            search?.aMapReGoecodeSearch(request)
        }
    }

    func searchPlaces(keyword: String, near coordinate: CLLocationCoordinate2D?) async -> [ResolvedPlace] {
        let normalizedKeyword = amapTrimmed(keyword) ?? ""
        guard !normalizedKeyword.isEmpty else { return [] }
        guard AMapManager.isConfigured else {
            lastErrorMessage = "高德地图未配置，暂不能搜索地点。"
            return []
        }

        tipsContinuation?.resume(returning: [])
        tipsContinuation = nil

        let request = AMapInputTipsSearchRequest()
        request.keywords = normalizedKeyword
        request.cityLimit = false
        if let coordinate {
            request.location = "\(coordinate.longitude),\(coordinate.latitude)"
        }

        return await withCheckedContinuation { continuation in
            tipsContinuation = continuation
            search?.aMapInputTipsSearch(request)
        }
    }

    private func finishReverse(with place: ResolvedPlace?) {
        reverseContinuation?.resume(returning: place)
        reverseContinuation = nil
    }

    private func finishTips(with places: [ResolvedPlace]) {
        tipsContinuation?.resume(returning: places)
        tipsContinuation = nil
    }
}

extension AMapGeocodingService: AMapSearchDelegate {
    nonisolated func onReGeocodeSearchDone(_ request: AMapReGeocodeSearchRequest!, response: AMapReGeocodeSearchResponse!) {
        let coordinate = request.location
        let address = amapTrimmed(response.regeocode?.formattedAddress)
        Task { @MainActor in
            guard let coordinate else {
                self.finishReverse(with: nil)
                return
            }
            let title = address?.isEmpty == false ? address! : "当前位置"
            self.finishReverse(
                with: ResolvedPlace(
                    id: "current-\(coordinate.latitude)-\(coordinate.longitude)",
                    title: title,
                    addressText: title,
                    latitude: Double(coordinate.latitude),
                    longitude: Double(coordinate.longitude),
                    source: .deviceLocation
                )
            )
        }
    }

    nonisolated func onInputTipsSearchDone(_ request: AMapInputTipsSearchRequest!, response: AMapInputTipsSearchResponse!) {
        let tips = response.tips ?? []
        let places = tips.compactMap { tip -> ResolvedPlace? in
            guard let point = tip.location else { return nil }
            let title = amapTrimmed(tip.name) ?? ""
            guard !title.isEmpty else { return nil }
            let address = [tip.district, tip.address]
                .compactMap { amapTrimmed($0) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let id = tip.uid?.isEmpty == false ? tip.uid! : "\(title)-\(point.latitude)-\(point.longitude)"
            return ResolvedPlace(
                id: id,
                title: title,
                addressText: address.isEmpty ? title : "\(title)，\(address)",
                latitude: Double(point.latitude),
                longitude: Double(point.longitude),
                source: .manual
            )
        }

        Task { @MainActor in
            self.finishTips(with: places)
        }
    }

    nonisolated func aMapSearchRequest(_ request: Any!, didFailWithError error: Error!) {
        Task { @MainActor in
            self.lastErrorMessage = "高德地点解析失败，请使用当前位置或手动补充。"
            self.finishReverse(with: nil)
            self.finishTips(with: [])
        }
    }
}

nonisolated private func amapTrimmed(_ value: String?) -> String? {
    value?.trimmingCharacters(in: .whitespacesAndNewlines)
}
