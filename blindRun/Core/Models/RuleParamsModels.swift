import Foundation

/// `GET /api/config/rules` 响应体（`APIClient` 已自动解包 `{success, data}` 外层信封）。
///
/// 契约原话：「这里的数**只用来显示或跳转**，判定结果仍由后端给」——
/// 「算不算临时取消」以取消接口的 `countedAsLateCancel` 为准，「该不该打开订单页」以订单状态为准。
/// 全部收成可选：后端往里加字段、或者某个键没下发，都不该让整条解码失败。
struct RuleParamsResponse: Codable, Sendable, Equatable {
    /// 陪跑员「临时取消」的窗口（小时，后端默认 12）。只用来在取消前提醒。
    let lateCancelWindowHours: Int?
    /// 陪跑员 App 在开跑前多少分钟自动打开订单页（后端默认 120）。
    let volunteerOrderAutoOpenLeadMinutes: Int?
    /// 开放城市与值守时段（#667，后端 #896）。旧后端没有它；下发了但读不出来也当作没有 ——
    /// 能不能下单以 `POST /api/orders` 为准，这里只决定提不提前说一句。
    var launchScope: LaunchScopeResponse?

    init(lateCancelWindowHours: Int?, volunteerOrderAutoOpenLeadMinutes: Int?, launchScope: LaunchScopeResponse? = nil) {
        self.lateCancelWindowHours = lateCancelWindowHours
        self.volunteerOrderAutoOpenLeadMinutes = volunteerOrderAutoOpenLeadMinutes
        self.launchScope = launchScope
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lateCancelWindowHours = try? container.decodeIfPresent(Int.self, forKey: .lateCancelWindowHours)
        volunteerOrderAutoOpenLeadMinutes = try? container.decodeIfPresent(Int.self, forKey: .volunteerOrderAutoOpenLeadMinutes)
        launchScope = try? container.decodeIfPresent(LaunchScopeResponse.self, forKey: .launchScope)
    }
}

/// 开放范围与值守时段（契约 `LaunchScopeResponse`）。**按账号下发，换账号要重新读**（见 `AppState.loadRuleParamsIfNeeded`）。
///
/// 🚨 只用来提前提示。先看三个布尔：`openAreas` 为空本身分不清「没有限制」和「暂未开放」。
/// 两句提示由后端拼好，客户端不拼城市、不拼时段。
struct LaunchScopeResponse: Codable, Sendable, Equatable {
    /// 一段可预约的开跑时段。`days` 是星期的英文全大写名，按开放枚举收：不认识的值不让整条失败。
    struct DutyWindow: Codable, Sendable, Equatable {
        let days: [String]
        /// `HH:mm`，两端都含。
        let start: String
        let end: String
    }

    /// 一块开放范围：GCJ-02 经纬度矩形，四条边都算在内。只是近似，不等于行政边界。
    struct OpenArea: Codable, Sendable, Equatable {
        let name: String
        let southLat: Double
        let northLat: Double
        let westLng: Double
        let eastLng: Double
    }

    /// false = 暂未开放，任何地点和时段都不能下单。
    let acceptingOrders: Bool
    let areaRestricted: Bool
    let dutyHoursRestricted: Bool
    /// 列出全部开放城市的一句话；暂未开放时说明暂未开放。没有限制时为 null。
    let areaHint: String?
    /// 「可预约的开跑时间是周一到周五 18:00 到 21:00」。没有限制时为 null。
    let dutyHoursHint: String?
    /// `nil` = 下发了但读不出来。提示句照常显示，只是不判「在不在范围里」——
    /// 少一块矩形会把开放城市里的出发点误报成范围外。
    let openAreas: [OpenArea]?
    let dutyWindows: [DutyWindow]?

    init(
        acceptingOrders: Bool,
        areaRestricted: Bool,
        dutyHoursRestricted: Bool,
        areaHint: String? = nil,
        dutyHoursHint: String? = nil,
        openAreas: [OpenArea]? = [],
        dutyWindows: [DutyWindow]? = []
    ) {
        self.acceptingOrders = acceptingOrders
        self.areaRestricted = areaRestricted
        self.dutyHoursRestricted = dutyHoursRestricted
        self.areaHint = areaHint
        self.dutyHoursHint = dutyHoursHint
        self.openAreas = openAreas
        self.dutyWindows = dutyWindows
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        acceptingOrders = try container.decode(Bool.self, forKey: .acceptingOrders)
        areaRestricted = try container.decode(Bool.self, forKey: .areaRestricted)
        dutyHoursRestricted = try container.decode(Bool.self, forKey: .dutyHoursRestricted)
        areaHint = (try? container.decodeIfPresent(String.self, forKey: .areaHint))?.nilIfBlank
        dutyHoursHint = (try? container.decodeIfPresent(String.self, forKey: .dutyHoursHint))?.nilIfBlank
        openAreas = try? container.decode([OpenArea].self, forKey: .openAreas)
        dutyWindows = try? container.decode([DutyWindow].self, forKey: .dutyWindows)
    }

    /// 起跑点在不在开放范围里。`nil` = 没有限制，或范围读不出来 —— 这时不提「在不在」。
    func containsStart(latitude: Double, longitude: Double) -> Bool? {
        guard areaRestricted, let openAreas else { return nil }
        return openAreas.contains { area in
            area.southLat <= latitude && latitude <= area.northLat && area.westLng <= longitude && longitude <= area.eastLng
        }
    }

    /// 开跑时刻在不在值守时段里：按北京时间的星期与分钟比，`start`、`end` 两端都含。
    /// `nil` = 没有限制，或有一段时段读不出来。
    func admitsStart(_ date: Date, calendar: Calendar = .aidRunBackend) -> Bool? {
        guard dutyHoursRestricted, let dutyWindows else { return nil }
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = parts.weekday, let hour = parts.hour, let minute = parts.minute,
              Self.weekdayNames.indices.contains(weekday - 1) else { return nil }
        let day = Self.weekdayNames[weekday - 1]
        let minuteOfDay = hour * 60 + minute
        var admits = false
        for window in dutyWindows {
            // 跨午夜的时段（start > end）契约没说怎么判，不猜：整体当作读不出来，只念后端那句。
            guard let start = Self.minuteOfDay(window.start), let end = Self.minuteOfDay(window.end), start <= end else { return nil }
            if window.days.contains(day), start <= minuteOfDay, minuteOfDay <= end { admits = true }
        }
        return admits
    }

    /// `Calendar.weekday` 从星期日 = 1 起数。
    private static let weekdayNames = ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"]

    private static func minuteOfDay(_ text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return hour * 60 + minute
    }
}

/// 客户端实际使用的规则参数：后端下发的值，拿不到或不合法时退回默认值。
///
/// 默认值与后端配置的默认值相同（契约 `RuleParamsResponse` 的 `example`）。
/// 「不合法」= 缺字段或 ≤ 0：0 小时的窗口会让取消提醒永远不出现，0 分钟的提前量会让订单页永远不自动打开 ——
/// 两者都不是后端会有意下发的值，更可能是配置写错，这时按默认值做比照单全收更安全。
struct RuleParams: Equatable, Sendable {
    let lateCancelWindowHours: Int
    let volunteerOrderAutoOpenLeadMinutes: Int

    static let fallback = RuleParams(
        lateCancelWindowHours: 12,
        volunteerOrderAutoOpenLeadMinutes: AppConstants.Timing.volunteerOrderAutoOpenLeadMinutes
    )

    init(lateCancelWindowHours: Int, volunteerOrderAutoOpenLeadMinutes: Int) {
        self.lateCancelWindowHours = lateCancelWindowHours
        self.volunteerOrderAutoOpenLeadMinutes = volunteerOrderAutoOpenLeadMinutes
    }

    /// `response == nil` = 还没拉到或拉失败，整份走默认值。
    init(response: RuleParamsResponse?) {
        let fallback = Self.fallback
        self.init(
            lateCancelWindowHours: Self.positive(response?.lateCancelWindowHours)
                ?? fallback.lateCancelWindowHours,
            volunteerOrderAutoOpenLeadMinutes: Self.positive(response?.volunteerOrderAutoOpenLeadMinutes)
                ?? fallback.volunteerOrderAutoOpenLeadMinutes
        )
    }

    private static func positive(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }
}
