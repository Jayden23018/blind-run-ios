import Foundation
import CoreLocation
import SwiftUI

// MARK: - Order Display Helpers

/// 以下每个 `case .unknown` 都对应「后端新增了本客户端不认识的订单状态」。
/// 一律走中性、只读、不下结论的分支：让订单继续留在列表里可被刷新，
/// 好过把它当成已结束而从界面上抹掉。
extension RunOrderStatus {
    var isActiveForBlindRunner: Bool {
        switch self {
        case .pendingMatch, .pendingAccept, .inProgress, .driverEnRoute, .driverArrived, .rematching:
            return true
        case .completed, .cancelled, .noVolunteer:
            return false
        case .unknown:
            return true
        }
    }

    var isActiveForVolunteer: Bool {
        switch self {
        case .pendingAccept, .driverEnRoute, .driverArrived, .inProgress:
            return true
        case .pendingMatch, .completed, .cancelled, .rematching, .noVolunteer:
            return false
        case .unknown:
            return true
        }
    }

    var blindRunnerDescription: String {
        switch self {
        case .pendingMatch:
            return "系统正在派单，请稍候。"
        case .pendingAccept:
            return "志愿者已接单，请按预约时间前往或等待在出发地点。"
        case .inProgress:
            return "服务已开始，请注意安全。"
        case .driverEnRoute:
            return "志愿者已出发，正在前往出发地点。"
        case .driverArrived:
            return arrivedWaitingCopy
        case .completed:
            return "服务已完成，感谢使用助盲跑。"
        case .cancelled:
            return "本次预约已取消。"
        case .rematching:
            return "正在确认志愿者状态，请稍候；如需更换志愿者，系统会继续处理。"
        case .noVolunteer:
            return "暂时没有可用志愿者，请稍后重试。"
        case .unknown:
            return "订单状态有更新，请刷新页面或稍后重试。"
        }
    }

    var blindRunnerAnnouncement: String {
        switch self {
        case .pendingMatch:
            return "订单提交成功，系统正在为你派单。"
        case .pendingAccept:
            return "志愿者已接单，请前往或等待在预约出发地点。"
        case .inProgress:
            return "服务已开始，请注意安全。"
        case .driverEnRoute:
            return "志愿者已出发，正在前往出发地点。"
        case .driverArrived:
            return "志愿者已到达约定地点，等待志愿者开始服务。"
        case .completed:
            return "服务已完成，感谢使用助盲跑。"
        case .cancelled:
            return "本次预约已取消。"
        case .rematching:
            return "正在确认志愿者状态，请稍候。"
        case .noVolunteer:
            return "暂时没有可用志愿者。"
        case .unknown:
            return "订单状态有更新，请刷新页面或稍后重试。"
        }
    }

    var statusSymbolName: String {
        switch self {
        case .pendingMatch:
            return "clock.arrow.circlepath"
        case .pendingAccept:
            return "person.crop.circle.badge.questionmark"
        case .inProgress:
            return "checkmark.circle.fill"
        case .driverEnRoute:
            return "figure.walk.circle.fill"
        case .driverArrived:
            return "bell.circle.fill"
        case .completed:
            return "checkmark.seal.fill"
        case .cancelled:
            return "xmark.circle.fill"
        case .rematching:
            return "arrow.triangle.2.circlepath"
        case .noVolunteer:
            return "person.slash.fill"
        case .unknown:
            return "questionmark.circle"
        }
    }

    var statusColor: Color {
        switch self {
        case .pendingMatch, .pendingAccept, .rematching:
            return AppColors.warning
        case .inProgress, .driverEnRoute, .completed:
            return AppColors.success
        case .driverArrived:
            return AppColors.primary
        case .cancelled, .noVolunteer:
            return AppColors.textSecondary
        case .unknown:
            return AppColors.textSecondary
        }
    }
}

// MARK: - Order Detail Helpers

extension OrderDetailResponse {
    var sortKey: String {
        createdAt ?? plannedStart ?? ""
    }

    var startCoordinate: CLLocationCoordinate2D? {
        guard let startLatitude, let startLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: startLatitude, longitude: startLongitude)
    }

    var startAddressForAnnouncement: String {
        startAddress?.nilIfBlank ?? "预约出发地点"
    }

    var plannedStartForAnnouncement: String? {
        plannedStart?.nilIfBlank?.displayDateTime
    }

    func volunteerDistanceToStartText(from volunteerCoordinate: CLLocationCoordinate2D?) -> String? {
        guard let volunteerCoordinate, let startCoordinate else { return nil }
        let meters = DistanceCalculator.distance(from: volunteerCoordinate, to: startCoordinate)
        return "距出发地点约 \(DistanceCalculator.formattedDistance(meters))"
    }

    func blindRunnerAnnouncement(distanceText: String? = nil) -> String {
        let distanceSentence = distanceText.map { "志愿者\($0)。" } ?? ""
        switch status {
        case .pendingAccept:
            if let plannedStartForAnnouncement {
                return "志愿者已接单。请在\(plannedStartForAnnouncement)前往或等待在出发地点：\(startAddressForAnnouncement)。\(distanceSentence)志愿者出发后会继续通知你。"
            }
            return "志愿者已接单。请前往或等待在出发地点：\(startAddressForAnnouncement)。\(distanceSentence)志愿者出发后会继续通知你。"
        case .driverEnRoute:
            if let distanceText {
                return "志愿者已出发，正在前往出发地点，\(distanceText)。"
            }
            return "志愿者已出发，正在前往出发地点。"
        case .driverArrived:
            return "\(status.blindRunnerAnnouncement)\(distanceSentence)"
        default:
            return status.blindRunnerAnnouncement
        }
    }
}

// MARK: - String Helpers

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfBlank: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
    }

    /// 后端 `LocalDateTime` 的无时区时间串（`2026-08-04T11:40:42`），**可能带小数秒**
    /// （`2026-08-04T11:40:42.644571`）。凡是取自 `now()` 且没经过 DB round-trip 的字段都会带 ——
    /// 下单回执的 `createdAt` 一定带，`acceptedAt` / `recordedAt` / `triggeredAt` 同理
    /// （handoff 2026-08-04 后端实测）。
    ///
    /// 小数位数不固定（尾零被丢弃），所以不另配一个 `.SSSSSS` 格式器，直接截掉小数部分 ——
    /// 秒以下精度对展示和预约时间都没有意义。**但带时区偏移的串不能这么截**
    /// （`...42.644+08:00` 截完会差好几个小时），所以要求小数点后必须全是数字，
    /// 带偏移的交给调用方的 ISO8601 分支。
    var backendLocalDate: Date? {
        let formatter = DateFormatter.aidRunBackendLocalDateTime
        if let date = formatter.date(from: self) { return date }
        let parts = split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[1].isEmpty, parts[1].allSatisfy(\.isNumber) else { return nil }
        return formatter.date(from: String(parts[0]))
    }

    var displayDateTime: String {
        if let date = backendLocalDate {
            return DateFormatter.aidRunDisplayDateTime.string(from: date)
        }
        if let date = ISO8601DateFormatter.aidRunFormatter.date(from: self) {
            return DateFormatter.aidRunDisplayDateTime.string(from: date)
        }
        if let date = ISO8601DateFormatter().date(from: self) {
            return DateFormatter.aidRunDisplayDateTime.string(from: date)
        }
        return self
    }
}

extension ISO8601DateFormatter {
    static let aidRunFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

extension DateFormatter {
    static let aidRunBackendLocalDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    static let aidRunDisplayDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter
    }()
}
