import Foundation
import CoreLocation
import SwiftUI

// MARK: - Order Display Helpers

extension RunOrderStatus {
    var isActiveForBlindRunner: Bool {
        switch self {
        case .pendingMatch, .pendingAccept, .inProgress, .driverEnRoute, .driverArrived, .rematching:
            return true
        case .completed, .cancelled, .noVolunteer:
            return false
        }
    }

    var isActiveForVolunteer: Bool {
        switch self {
        case .pendingAccept, .driverEnRoute, .driverArrived, .inProgress:
            return true
        case .pendingMatch, .completed, .cancelled, .rematching, .noVolunteer:
            return false
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

    var displayDateTime: String {
        if let date = DateFormatter.aidRunBackendLocalDateTime.date(from: self) {
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
