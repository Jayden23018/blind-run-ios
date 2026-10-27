import CoreLocation
import Foundation

// 同行会话的两个纯函数。从 `LiveEscortSessionCoordinator.swift` 挪出来（那个文件超长，SwiftLint 棘轮），
// 行为不变：它们不读协调器的任何状态，抽出来本来就只为可测。
extension LiveEscortSessionCoordinator {

    /// 同行会话的上行报文。`sample` 必须已是 GCJ-02（`latestEscortBackendSample` 保证）。
    /// 纯函数，只为可测：拿不到的字段一律不传，这是契约的硬要求。
    static func locationMessage(sample: LocatedCoordinate, motion: RunMotionSnapshot?) -> WSLocationUpdateMessage {
        WSLocationUpdateMessage(
            lat: sample.coordinate.latitude,
            lng: sample.coordinate.longitude,
            hAcc: sample.horizontalAccuracy,
            speed: sample.speed,
            alt: motion?.altitude,
            steps: motion?.steps,
            cadence: motion?.cadence,
            batteryLevel: motion?.batteryLevel
        )
    }

    /// 该不该有这张卡、长什么样。`nil` = 不该有，结束掉。
    ///
    /// **抽成纯函数只为可测**：唯一调用点埋在 `@MainActor` + ActivityKit 后面，而这里要守的
    /// 是红线 ——「锁屏卡只在 `IN_PROGRESS` 出现」（状态清单 §16/§17「IN_PROGRESS 期间常驻」）。
    /// 两端都带对方姓氏（决定源 V11 取代了 2026-09-16「陪跑员端不显示对方姓名」）。
    static func liveActivityPlan(
        orderID: Int64?,
        status: RunOrderStatus?,
        role: UserRole?,
        partnerName: String?
    ) -> (orderID: Int64, side: RunLiveActivitySide, partnerName: String?)? {
        guard let orderID, status == .inProgress, let role else { return nil }
        switch role {
        case .blind:
            return (orderID, .runner, partnerName)
        case .volunteer:
            return (orderID, .volunteer, partnerName)
        case .unset:
            return nil
        }
    }
}
