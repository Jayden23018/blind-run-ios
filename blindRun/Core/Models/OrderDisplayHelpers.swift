import Foundation
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
            return "已找到志愿者，等待确认中。"
        case .inProgress:
            return "服务已开始，请注意安全。"
        case .driverEnRoute:
            return "志愿者正在赶来。"
        case .driverArrived:
            return "志愿者已到达约定地点。"
        case .completed:
            return "服务已完成，感谢使用助盲跑。"
        case .cancelled:
            return "本次预约已取消。"
        case .rematching:
            return "正在重新匹配志愿者。"
        case .noVolunteer:
            return "暂时没有可用志愿者，请稍后重试。"
        }
    }

    var blindRunnerAnnouncement: String {
        switch self {
        case .pendingMatch:
            return "订单提交成功，系统正在为你派单。"
        case .pendingAccept:
            return "已找到志愿者，正在等待对方确认。"
        case .inProgress:
            return "服务已开始，请注意安全。"
        case .driverEnRoute:
            return "志愿者正在赶来，请耐心等待。"
        case .driverArrived:
            return "志愿者已到达约定地点。"
        case .completed:
            return "服务已完成，感谢使用助盲跑。"
        case .cancelled:
            return "本次预约已取消。"
        case .rematching:
            return "正在重新为您匹配志愿者，请稍候。"
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
        if let date = ISO8601DateFormatter.aidRunFormatter.date(from: self) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        if let date = ISO8601DateFormatter().date(from: self) {
            return date.formatted(date: .abbreviated, time: .shortened)
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
}
