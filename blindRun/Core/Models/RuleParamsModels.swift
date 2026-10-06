import Foundation

/// `GET /api/config/rules` 响应体（`APIClient` 已自动解包 `{success, data}` 外层信封）。
///
/// 契约原话：「这里的数**只用来显示或跳转**，判定结果仍由后端给」——
/// 「算不算临时取消」以取消接口的 `countedAsLateCancel` 为准，「该不该打开订单页」以订单状态为准。
/// 两个字段都收成可选：后端往里加字段、或者某个键没下发，都不该让整条解码失败。
struct RuleParamsResponse: Codable, Sendable, Equatable {
    /// 陪跑员「临时取消」的窗口（小时，后端默认 12）。只用来在取消前提醒。
    let lateCancelWindowHours: Int?
    /// 陪跑员 App 在开跑前多少分钟自动打开订单页（后端默认 120）。
    let volunteerOrderAutoOpenLeadMinutes: Int?
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
