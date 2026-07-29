import CoreLocation
import Foundation

struct TrackPoint: Codable, Sendable, Equatable, Identifiable {
    let lat: Double
    let lng: Double
    let recordedAt: String

    var id: String { "\(recordedAt):\(lat):\(lng)" }

    var backendCoordinate: LocatedCoordinate? {
        BackendCoordinateNormalizer.backend(latitude: lat, longitude: lng)
    }
}

struct TrackStats: Codable, Sendable, Equatable {
    let distanceMeters: Double?
    let durationSeconds: Int64?
    let avgPaceSecPerKm: Double?

    var distanceText: String? {
        guard let distanceMeters else { return nil }
        if distanceMeters >= 1_000 {
            return String(format: "%.2f 公里", distanceMeters / 1_000)
        }
        return "\(Int(distanceMeters.rounded())) 米"
    }

    var durationText: String? {
        guard let durationSeconds else { return nil }
        let minutes = durationSeconds / 60
        let seconds = durationSeconds % 60
        return minutes > 0 ? "\(minutes) 分 \(seconds) 秒" : "\(seconds) 秒"
    }

    var averagePaceText: String? {
        guard let avgPaceSecPerKm, avgPaceSecPerKm > 0 else { return nil }
        let totalSeconds = Int(avgPaceSecPerKm.rounded())
        return "\(totalSeconds / 60) 分 \(totalSeconds % 60) 秒每公里"
    }
}

struct OrderTrackResponse: Codable, Sendable, Equatable {
    let status: RunOrderStatus
    let volunteerTrack: [TrackPoint]
    let volunteerStats: TrackStats
    let blindTrack: [TrackPoint]
    let blindStats: TrackStats

    var primaryRouteCoordinates: [CLLocationCoordinate2D] {
        blindTrack.compactMap { $0.backendCoordinate?.coordinate }
    }

    var emptyStateText: String? {
        guard blindTrack.count < 2 else { return nil }
        switch status {
        case .pendingMatch, .pendingAccept, .driverEnRoute, .driverArrived, .rematching, .noVolunteer:
            return "本次路线尚未开始。"
        case .inProgress:
            return "本次路线仍在采集，暂时没有足够的轨迹点。"
        case .completed, .cancelled:
            return blindTrack.isEmpty
                ? "该历史订单暂无轨迹。"
                : "本次轨迹点不足，暂时无法绘制路线。"
        }
    }

    var spokenSummary: String {
        if let emptyStateText { return emptyStateText }
        var parts = ["本次路线"]
        if let value = blindStats.distanceText { parts.append("里程 \(value)") }
        if let value = blindStats.durationText { parts.append("时长 \(value)") }
        if let value = blindStats.averagePaceText { parts.append("平均配速 \(value)") }
        return parts.joined(separator: "，") + "。"
    }
}
