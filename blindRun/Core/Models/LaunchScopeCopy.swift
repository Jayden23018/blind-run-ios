import Foundation

// MARK: - 下单前的开放范围告知（#667）

/// 下单入口现在能不能进。只看 `acceptingOrders`：开放城市和时段的限制只提示不拦，能不能下单以 `POST /api/orders` 为准。
enum BookingLaunchAvailability: Equatable {
    /// 能进，或者不知道（旧后端、没拉到）—— 不知道时放行，后端兜底。
    case open
    /// 暂未开放。`notice` 显示并播报，不进表单、不启动语音向导。
    case closed(notice: String)

    init(_ scope: LaunchScopeResponse?) {
        guard let scope, !scope.acceptingOrders else {
            self = .open
            return
        }
        self = .closed(notice: scope.areaHint ?? LaunchScopeCopy.closedFallback)
    }
}

extension LaunchScopeResponse {
    /// 本地记下「后端刚说暂不接受预约」（`AppState.noteBookingServiceNotOpen`）。`notice` 是后端那句 `message`。
    static func closed(notice: String) -> Self {
        Self(acceptingOrders: false, areaRestricted: true, dutyHoursRestricted: false, areaHint: notice, openAreas: [], dutyWindows: [])
    }

    /// 出发地点那一步的提示。没有限制时 `nil`，界面一个字不提。
    /// 城市名只来自后端的 `areaHint`，这里只在「已选的出发点不在范围里」时加一句前缀。
    func areaNotice(latitude: Double?, longitude: Double?) -> String? {
        guard areaRestricted else { return nil }
        var outside = false
        if let latitude, let longitude { outside = containsStart(latitude: latitude, longitude: longitude) == false }
        return LaunchScopeCopy.notice(hint: areaHint, outsidePrefix: outside ? LaunchScopeCopy.outsideAreaPrefix : nil)
    }

    /// 预约时间那一步的提示。没有限制时 `nil`。时段句子只来自后端的 `dutyHoursHint`。
    func dutyHoursNotice(start: Date, calendar: Calendar = .aidRunBackend) -> String? {
        guard dutyHoursRestricted else { return nil }
        let outside = admitsStart(start, calendar: calendar) == false
        return LaunchScopeCopy.notice(hint: dutyHoursHint, outsidePrefix: outside ? LaunchScopeCopy.outsideDutyHoursPrefix : nil)
    }
}

enum LaunchScopeCopy {
    /// 暂未开放而后端 `areaHint` 为空时。与后端 `ORDER_SERVICE_NOT_OPEN` 的默认文案同一句，不提城市、不引导改地点或时间。
    static let closedFallback = "陪跑服务暂未开放，现在还不能预约，开放后再来下单。"
    static let outsideAreaPrefix = "这个出发点不在开放范围内。"
    static let outsideDutyHoursPrefix = "这个开跑时间不在可预约时段内。"
    /// 首次进入、本账号还没有规则数据时的等待提示。
    static let checking = "正在确认是否开放预约"
    static let backHome = "返回首页"

    // 三个建单拒绝码的兜底句：只在后端 `message` 为空时用（`ErrorCode.prefersServerMessage`）。取自后端 `ErrorCode.java` 的默认文案。
    static let serviceNotOpenFallback = closedFallback
    static let outsideOpenAreaFallback = "这个出发点不在开放范围内，请换一个开放范围内的出发点。"
    static let outsideDutyHoursFallback = "这个时间没有值守人员，暂不接受预约，请换个时间。"

    static func rejectionFallback(for code: ErrorCode) -> String {
        switch code {
        case .orderOutsideOpenArea: return outsideOpenAreaFallback
        case .appointmentOutsideDutyHours: return outsideDutyHoursFallback
        default: return serviceNotOpenFallback
        }
    }

    static func notice(hint: String?, outsidePrefix: String?) -> String? {
        let text = [outsidePrefix, hint].compactMap { $0 }.joined()
        return text.isEmpty ? nil : text
    }
}
