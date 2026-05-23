import Foundation
import SwiftUI

// MARK: - Order Display Helpers

extension RunOrderStatus {
    var isActiveForBlindRunner: Bool {
        switch self {
        case .matching, .accepted, .arrived, .inProgress:
            return true
        case .completed, .cancelled, .emergency:
            return false
        }
    }

    var shouldPollOnBlindRunnerPage: Bool {
        switch self {
        case .matching, .accepted, .arrived, .inProgress:
            return true
        case .completed, .cancelled, .emergency:
            return false
        }
    }

    var canEnterEmergency: Bool {
        switch self {
        case .accepted, .arrived, .inProgress:
            return true
        case .matching, .completed, .cancelled, .emergency:
            return false
        }
    }

    var canCancelBeforeStart: Bool {
        switch self {
        case .matching, .accepted, .arrived:
            return true
        case .inProgress, .completed, .cancelled, .emergency:
            return false
        }
    }

    var blindRunnerDescription: String {
        switch self {
        case .matching:
            return "匹配中，请稍候。"
        case .accepted:
            return "志愿者已接单，正在赶来。"
        case .arrived:
            return "志愿者已到达约定地点，请确认开始服务。"
        case .inProgress:
            return "服务进行中，请注意安全。"
        case .completed:
            return "服务已完成，感谢使用助盲跑。"
        case .cancelled:
            return "本次预约已取消。"
        case .emergency:
            return "已进入求助状态，系统已记录本次异常。"
        }
    }

    var blindRunnerAnnouncement: String {
        switch self {
        case .matching:
            return "订单提交成功，正在等待志愿者接单。"
        case .accepted:
            return "志愿者已接单，志愿者正在赶来。"
        case .arrived:
            return "志愿者已到达约定地点，请确认开始服务。"
        case .inProgress:
            return "服务已开始，请注意安全。"
        case .completed:
            return "服务已完成，感谢使用助盲跑。"
        case .cancelled:
            return "本次预约已取消。"
        case .emergency:
            return "已进入求助状态，系统已记录本次异常。"
        }
    }

    var statusSymbolName: String {
        switch self {
        case .matching:
            return "clock.arrow.circlepath"
        case .accepted:
            return "checkmark.circle.fill"
        case .arrived:
            return "bell.circle.fill"
        case .inProgress:
            return "figure.run.circle.fill"
        case .completed:
            return "checkmark.seal.fill"
        case .cancelled:
            return "xmark.circle.fill"
        case .emergency:
            return "exclamationmark.triangle.fill"
        }
    }

    var statusColor: Color {
        switch self {
        case .matching:
            return AppColors.warning
        case .accepted, .inProgress, .completed:
            return AppColors.success
        case .arrived:
            return AppColors.primary
        case .cancelled:
            return AppColors.textSecondary
        case .emergency:
            return AppColors.destructive
        }
    }
}

extension LocationPoint {
    var displayAddress: String {
        guard let addressText, !addressText.trimmed.isEmpty else {
            return source == .demoDefault ? "当前位置（演示模式）" : "当前位置"
        }
        return addressText
    }
}

extension RunOrderDto {
    var updatedAtSortKey: String {
        updatedAt ?? createdAt ?? appointmentTime
    }
}

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
