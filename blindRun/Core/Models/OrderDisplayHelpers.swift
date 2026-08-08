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

    /// 志愿者能否看到盲人填的**自由文本**（`specialNotes` 特殊说明 / `routeNotes` 路线备注）。
    ///
    /// `AGENTS.md §8`：**接单前隐藏盲人的敏感健康信息。** 自由文本取值空间开放、敏感度无法预判，
    /// 语音下单落地后它装的就是用户原话（「我有低血糖，如果我说头晕请马上停下来」）。
    /// 派单是串行的，接单前展示等于把它交给这一单碰到过的每一个志愿者，包括最后拒单的那些。
    ///
    /// `routeNotes` 2026-08-07 一并收进来（后端已拍板同口径并在适配）。它的产品用途看着无害
    /// （「沿湖边跑道」），但字段类型决定风险、用途不决定：同一个输入框里写「我住院刚出来，
    /// 只能走平路」是完全自然的事，而客户端无法在展示前判断用户写了哪一种。
    ///
    /// 刻意写成穷举 switch 而不是 `!= .pendingMatch`，为的是两件事：
    /// - `.rematching` —— 原志愿者取消后订单回到重新派单，**那个人已经不是参与者了**，
    ///   简写的 `!=` 会把他判成可见。
    /// - `.unknown` —— 后端新增状态时必须**默认不公开**。这一族的其他 helper 对未知值取
    ///   「保守地当作进行中」，那是为了不让订单从界面上消失；隐私边界的保守方向相反，是关。
    ///
    /// `.pendingAccept` 判为可见，因为它已经在接单**之后**：盲人端该状态的文案是
    /// 「志愿者已接单」，且志愿者此时才拥有取消权（`AGENTS.md §5`）。
    /// 派单弹窗那一刻订单还是 `PENDING_MATCH`。
    ///
    /// 结构化条件（配速 / 路线偏好 / 导盲犬）**不走这条闸**：取值空间封闭（枚举 / 布尔），
    /// 且它们是志愿者判断「我接不接得下来」的依据，藏起来只会让人盲接、接了再取消。
    var disclosesBlindRunnerNotesToVolunteer: Bool {
        switch self {
        case .pendingAccept, .driverEnRoute, .driverArrived, .inProgress, .completed, .cancelled:
            return true
        case .pendingMatch, .rematching, .noVolunteer:
            return false
        case .unknown:
            return false
        }
    }

    /// 盲人端订单页该不该给出「打电话给志愿者」的主按钮。
    ///
    /// 陪跑没有车牌 / 车型 / 颜色，视障者确认「眼前这个人是不是我的志愿者」的唯一手段就是这通电话
    /// （依据见 `docs/research/blind-ui-visual-benchmark-20260808.md` §3.2）。所以凡是需要**当面汇合**
    /// 的状态都要给，且要给成主按钮而不是一行文字。
    ///
    /// 终态一律不给：订单结束后 `volunteerPhone` 可能还在响应里，但那时候摆一个占半屏的拨号按钮
    /// 是在诱导盲人打一通没有理由的电话。
    ///
    /// 写成穷举 switch 而不是集合字面量：后端往枚举加值时编译器会在这里逼一次决策，
    /// 而集合字面量会默默把新状态判成 false。
    var offersVolunteerCall: Bool {
        switch self {
        case .pendingAccept, .driverEnRoute, .driverArrived, .inProgress:
            return true
        // 还没有志愿者，或那个志愿者已经不是本单参与者（`REMATCHING` 是他取消后进入的状态）。
        case .pendingMatch, .rematching, .noVolunteer:
            return false
        case .completed, .cancelled:
            return false
        // 状态未知时落到只读跟踪页，不提供任何会产生外呼的动作。
        case .unknown:
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
