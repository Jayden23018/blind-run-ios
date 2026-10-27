import SwiftUI

/// 谁在要持续定位（#425）。`LocationService` 全 App 只有一份，所以开 / 停都要说明是替谁：
/// 每个调用方只撤回自己那一份，集合空了才停硬件。否则关接单开关会停掉同行会话要的定位，
/// 同行会话结束也会停掉预约页要的定位；反过来，谁都不撤回就一直开着（#425 的两条路径）。
enum LocationUpdateReason: String, CaseIterable, Sendable {
    /// 盲人角色在线、且同意过盲人位置轨迹（首页播报位置、求助取新坐标）。`AppState.syncRoleLocationIntents` 管。
    case blindRole
    /// 陪跑员开着接单开关、且同意过陪跑员位置轨迹：为派单获取位置。`AppState.syncRoleLocationIntents` 管。
    case volunteerDispatch
    /// 盲人预约页（出发地点）。`requestsLocationUpdates` 管，离开页面撤回。
    case blindBooking
    /// 陪跑员订单详情页（到起点的距离）。`requestsLocationUpdates` 管，离开页面撤回。
    case volunteerOrderDetail
    /// 陪跑员进行中订单页（出发 / 汇合 / 跑步）。`requestsLocationUpdates` 管，离开页面撤回。
    case volunteerActiveOrder
    /// 同行会话（`DRIVER_EN_ROUTE` / `DRIVER_ARRIVED` / `IN_PROGRESS`）。`LiveEscortSessionCoordinator` 管，会话结束撤回。
    case escortSession
}

/// 页面要持续定位时挂这个：出现时以 `reason` 的名义要，消失时撤回这一份。
/// 开和撤写在同一处，页面就不会只开不撤（#425 之前三处页面都只开不撤，定位一直开到退出登录）。
private struct LocationUpdateIntentModifier: ViewModifier {
    @EnvironmentObject private var locationService: LocationService
    let reason: LocationUpdateReason
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content
            .onAppear { apply(isEnabled) }
            .onChange(of: isEnabled) { apply($0) }
            .onDisappear { locationService.stopUpdating(for: reason) }
    }

    private func apply(_ enabled: Bool) {
        if enabled {
            locationService.startUpdating(for: reason)
        } else {
            locationService.stopUpdating(for: reason)
        }
    }
}

extension View {
    /// 这一页在屏幕上、且 `isEnabled` 为真时要持续定位。位置轨迹同意（#368）由调用方算好传进来。
    func requestsLocationUpdates(_ reason: LocationUpdateReason, when isEnabled: Bool = true) -> some View {
        modifier(LocationUpdateIntentModifier(reason: reason, isEnabled: isEnabled))
    }
}
