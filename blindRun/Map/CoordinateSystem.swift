import CoreLocation
import Foundation

/// 坐标来源必须跟随坐标一起流转，避免设备坐标被重复转换。
enum CoordinateSystem: Sendable, Equatable {
    case wgs84Device
    case gcj02Backend
}

struct LocatedCoordinate: Sendable, Equatable {
    let coordinate: CLLocationCoordinate2D
    let system: CoordinateSystem
    let capturedAt: Date

    init(
        coordinate: CLLocationCoordinate2D,
        system: CoordinateSystem,
        capturedAt: Date = Date()
    ) {
        self.coordinate = coordinate
        self.system = system
        self.capturedAt = capturedAt
    }

    var isValid: Bool {
        CLLocationCoordinate2DIsValid(coordinate)
            && (-90 ... 90).contains(coordinate.latitude)
            && (-180 ... 180).contains(coordinate.longitude)
    }
}

/// 唯一的设备定位网络边界。后端来源坐标在这里显式原样通过。
enum BackendCoordinateNormalizer {
    private static let earthRadius = 6_378_245.0
    private static let eccentricitySquared = 0.00669342162296594323

    static func normalize(_ sample: LocatedCoordinate) -> LocatedCoordinate? {
        guard sample.isValid else { return nil }
        switch sample.system {
        case .gcj02Backend:
            return sample
        case .wgs84Device:
            return LocatedCoordinate(
                coordinate: wgs84ToGCJ02(sample.coordinate),
                system: .gcj02Backend,
                capturedAt: sample.capturedAt
            )
        }
    }

    static func backend(
        latitude: Double,
        longitude: Double,
        capturedAt: Date = Date()
    ) -> LocatedCoordinate? {
        normalize(
            LocatedCoordinate(
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                system: .gcj02Backend,
                capturedAt: capturedAt
            )
        )
    }

    static func wgs84ToGCJ02(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard !isOutsideChina(coordinate) else { return coordinate }

        let deltaLongitude = coordinate.longitude - 105
        let deltaLatitude = coordinate.latitude - 35
        var latitudeOffset = transformLatitude(x: deltaLongitude, y: deltaLatitude)
        var longitudeOffset = transformLongitude(x: deltaLongitude, y: deltaLatitude)
        let radians = coordinate.latitude / 180 * .pi
        let sinLatitude = sin(radians)
        var magic = 1 - eccentricitySquared * sinLatitude * sinLatitude
        let sqrtMagic = sqrt(magic)
        latitudeOffset = latitudeOffset * 180
            / ((earthRadius * (1 - eccentricitySquared)) / (magic * sqrtMagic) * .pi)
        longitudeOffset = longitudeOffset * 180
            / (earthRadius / sqrtMagic * cos(radians) * .pi)
        magic = coordinate.latitude + latitudeOffset

        return CLLocationCoordinate2D(
            latitude: magic,
            longitude: coordinate.longitude + longitudeOffset
        )
    }

    static func isOutsideChina(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.longitude < 72.004
            || coordinate.longitude > 137.8347
            || coordinate.latitude < 0.8293
            || coordinate.latitude > 55.8271
    }

    private static func transformLatitude(x: Double, y: Double) -> Double {
        var result = -100 + 2 * x + 3 * y + 0.2 * y * y + 0.1 * x * y
            + 0.2 * sqrt(abs(x))
        result += (20 * sin(6 * x * .pi) + 20 * sin(2 * x * .pi)) * 2 / 3
        result += (20 * sin(y * .pi) + 40 * sin(y / 3 * .pi)) * 2 / 3
        result += (160 * sin(y / 12 * .pi) + 320 * sin(y * .pi / 30)) * 2 / 3
        return result
    }

    private static func transformLongitude(x: Double, y: Double) -> Double {
        var result = 300 + x + 2 * y + 0.1 * x * x + 0.1 * x * y
            + 0.1 * sqrt(abs(x))
        result += (20 * sin(6 * x * .pi) + 20 * sin(2 * x * .pi)) * 2 / 3
        result += (20 * sin(x * .pi) + 40 * sin(x / 3 * .pi)) * 2 / 3
        result += (150 * sin(x / 12 * .pi) + 300 * sin(x / 30 * .pi)) * 2 / 3
        return result
    }
}
