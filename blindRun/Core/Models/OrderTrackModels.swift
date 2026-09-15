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

    // MARK: - 显示用格式化
    //
    // 上面那三个是**播报**格式（值与单位同串、口语化的「分 / 秒」），它们是 VoiceOver 与 TTS 的
    // 口径，一个字都不要改。下面三个是**视觉**格式：值与标签分离、等宽跑表体例，
    // 给陪跑中那屏的巨数字用（设计规格见 `docs/research/blind-runner-ui-reference-study-20260915.md`
    // §27）。两套并存不是重复 —— 屏幕要 `9'06"`，耳朵要「9 分 6 秒每公里」。

    /// 主数字：只有值，没有单位。单位在下面那行标签里（「总距离（公里）」）。
    ///
    /// **不足 1 公里也按公里给两位小数**，不像 `distanceText` 那样切成「米」——
    /// 跑动中单位跳变会让主数字的量级在同一屏里前后不可比，而这是唯一那个大数字。
    var distanceKilometersText: String? {
        guard let distanceMeters else { return nil }
        return String(format: "%.2f", distanceMeters / 1_000)
    }

    /// 跑表体例：一小时以内 `01:54`，超过一小时 `1:02:33`。
    var durationClockText: String? {
        guard let durationSeconds, durationSeconds >= 0 else { return nil }
        let hours = durationSeconds / 3_600
        let minutes = (durationSeconds % 3_600) / 60
        let seconds = durationSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// 配速：`9'06"`。分钟不补零（跑表惯例），秒补零。
    var paceClockText: String? {
        guard let avgPaceSecPerKm, avgPaceSecPerKm > 0 else { return nil }
        let totalSeconds = Int(avgPaceSecPerKm.rounded())
        return String(format: "%d'%02d\"", totalSeconds / 60, totalSeconds % 60)
    }
}

/// 每公里播报的判定。「已跑 3 公里」播不播，只由它说了算。
///
/// **抽成纯逻辑而不是写在 view model 里**：挂在那边的话，测一次「跨公里」得先造
/// `AppState` + 语音服务 + 跑一轮轮询，而这里要验的只是三条算术分支。
/// 同 `VoiceStatusQuery` 的理由（本仓库 XCTest 只能真机跑）。
struct KilometerMilestoneTracker {
    private var lastAnnounced: Int?

    /// 这一轮该播报的整公里数；`nil` = 不播。
    ///
    /// 🚩 **第一个样本只定基线，恒返回 `nil`。** 进页面那一刻状态播报刚开口，
    /// 而合成器全进程只有一个、`speak` 先 `stopSpeaking` —— 紧接着再播一句会**静默切断**
    /// 它，表现是「只念了开头」。代价是 App 被杀后重进会漏掉一次里程碑，比吞掉状态播报便宜。
    ///
    /// 判据是**整公里数变大**而不是「距离变了」：`/track` 每 10 秒回一次，
    /// 按变化播等于每 10 秒往耳朵里塞一遍数字，而跑动中那条听觉通道是留给环境和同伴的。
    mutating func milestone(forDistanceMeters meters: Double?) -> Int? {
        guard let meters, meters >= 0 else { return nil }
        let kilometers = Int(meters / 1_000)
        guard let previous = lastAnnounced else {
            lastAnnounced = kilometers
            return nil
        }
        guard kilometers > previous else { return nil }
        lastAnnounced = kilometers
        return kilometers
    }

    /// 换单时清空。不清的话新订单一开跑就会从上一单的公里数接着算 —— 直接后果是
    /// 新的一单跑到 1 公里时**不播**（因为上一单已经到过 5 公里）。
    mutating func reset() {
        lastAnnounced = nil
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

    /// 轨迹外接矩形的中心，给地图当 `centerCoordinate` 用。
    ///
    /// **不能传起点。** `AMapContainer` 一边在折线落地时 fit 到外接矩形
    /// （`AMapContainer.swift:185-192`），一边在每次 `updateUIView` 里把地图中心拉回传入坐标
    /// （`:102-110`，阈值 1e-4 度）。传起点的话后者会持续覆盖前者，
    /// 结果是路线只剩起点附近一小段留在屏幕上 —— 看起来就像「轨迹没画出来」。
    ///
    /// 用经纬度算术中心而不是 `MAMapRect` 的墨卡托中心：两者的纬度差在城市尺度下约 1e-5 度，
    /// 比上面那个阈值小一个数量级，够不着触发条件。
    var primaryRouteBoundingCenter: CLLocationCoordinate2D? {
        let coordinates = primaryRouteCoordinates
        guard let first = coordinates.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude
        var minLng = first.longitude, maxLng = first.longitude
        for point in coordinates.dropFirst() {
            minLat = min(minLat, point.latitude)
            maxLat = max(maxLat, point.latitude)
            minLng = min(minLng, point.longitude)
            maxLng = max(maxLng, point.longitude)
        }
        return CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
    }

    var emptyStateText: String? {
        guard blindTrack.count < 2 else { return nil }
        switch status {
        case .pendingMatch, .pendingIntroCall, .scheduledConfirmed, .pendingAccept, .driverEnRoute, .driverArrived, .rematching, .noVolunteer:
            return "本次路线尚未开始。"
        case .inProgress:
            return "本次路线仍在采集，暂时没有足够的轨迹点。"
        case .completed, .cancelled:
            return blindTrack.isEmpty
                ? "该历史订单暂无轨迹。"
                : "本次轨迹点不足，暂时无法绘制路线。"
        // 认不出状态时不猜「尚未开始」还是「已结束」，只陈述看得见的事实。
        case .unknown:
            return "暂时没有足够的轨迹点。"
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
