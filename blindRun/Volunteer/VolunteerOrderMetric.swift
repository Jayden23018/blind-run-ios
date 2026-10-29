import Foundation

// 从 `VolunteerOrderFlowPage.swift` 原样搬出（SwiftLint 棘轮 #488：那个文件只许变短）。

/// 邀请态三宫格里的一格。值与单位分开：两个字号。
struct VolunteerOrderMetric: Identifiable, Equatable {
    let label: String
    let value: String
    let unit: String?

    var id: String { label }
    /// 读屏先说这是什么：「离你，3.2 公里」。
    var spoken: String { "\(label)，\(value)\(unit.map { " \($0)" } ?? "")" }

    /// 与邀请卡 `VolunteerInviteCard.metrics` 同一套取值（离你 / 跑多远 / 配速），缺的格子不画。
    static func invite(_ dispatch: WSNewOrder) -> [Self] {
        [
            dispatch.distanceKm.map { Self(label: "离你", value: String(format: "%.1f", $0), unit: "公里") },
            RunPlanFormat.plannedDistanceParts(meters: dispatch.plannedDistanceMeters).map {
                Self(label: VolunteerOrderFlowCopy.plannedDistanceLabel, value: $0.value, unit: $0.unit)
            },
            dispatch.plannedPaceText.map { Self(label: VolunteerOrderFlowCopy.paceLabel, value: $0, unit: nil) },
        ].compactMap { $0 }
    }
}
