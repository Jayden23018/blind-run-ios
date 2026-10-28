import CoreLocation
import Foundation

// 从 `EmergencyCoordinator.swift` 原样搬来（#502）：那个文件超了 SwiftLint 长度上限，CI 棘轮不许再变长。
extension EmergencyCoordinator {
    // MARK: Location

    /// Longest we will make someone wait for a fresh fix before giving up and saying so.
    static let locationWaitTimeout: TimeInterval = 5

    /// 取一份新鲜的真实 GCJ-02 坐标，拿不到就返回 nil（由 `trigger` 决定不发并如实播报）。
    ///
    /// 放在这里而不是各调用方各写一份：求助入口现在有两个（订单状态页、首页 SOS 条），
    /// 而这段逻辑的每一条都是安全约束 —— `latestBackendSample()` 只返回经单一后端边界
    /// 归一化过的**真实设备采样**，Demo / UI 测试的定位路径压根产不出设备采样，
    /// 所以演示坐标无法经由这里混进云端求助。两份实现意味着这条保证要守两遍。
    ///
    /// 🔴 **「精确位置」关闭时直接返回 nil，不等。** 那时系统给的是区域代表点（约 5 公里），
    /// 它同样是「真实设备采样」、能穿过新鲜度闸 —— 而把家属引到几公里外，正是
    /// `allowsSubmissionWithoutLocation` 那段注释说的「送错地方比不送更糟」。项目负责人 2026-10-09 拍板按无定位处理（#373）。
    /// 这里**不**顺手申请临时精确位置：系统弹窗会和「求助未发出」的播报抢读屏焦点；跑步开始时已经申请过一次。
    ///
    /// 🔴 **本角色没有同意共享位置时（`sharingBlocked`，#368）同样直接返回 nil。**
    /// 同意页写着「不同意 …… 走散提醒和求助定位也用不了」—— 拒绝之后再把位置随求助发出去，就是拿走了用户刚说不的东西。
    static func freshEmergencyCoordinate(
        using locationService: LocationService?,
        sharingBlocked: Bool = false
    ) async -> LocatedCoordinate? {
        guard !sharingBlocked else { return nil }
        guard let locationService, !locationService.isPreciseLocationOff else { return nil }
        if let sample = locationService.latestBackendSample() {
            return sample
        }
        locationService.requestOneTimeLocation()
        let deadline = Date().addingTimeInterval(locationWaitTimeout)
        while Date() < deadline {
            // 被取消时 `Task.sleep` 立刻抛，不查这一句就会在主线程上空转到 deadline。
            guard !Task.isCancelled else { return nil }
            try? await Task.sleep(nanoseconds: 500_000_000)
            if let sample = locationService.latestBackendSample() {
                return sample
            }
        }
        return nil
    }

    /// `freshEmergencyCoordinate` 返回 nil 之后，文案该按哪个原因说。与它配对使用。
    ///
    /// 精确位置关闭排在 `locationError` 之前：那时 `locationError` 通常是 nil，
    /// 落到默认分支就会叫用户「到室外开阔处重试」—— 换地方解决不了一个开关的问题。
    static func locationFailureReason(
        using locationService: LocationService?,
        sharingBlocked: Bool = false
    ) -> LocationError? {
        // 排在最前：没有同意时根本不取位置，下面几个原因都不是真正的原因。
        if sharingBlocked { return .locationSharingNotConsented }
        guard let locationService else { return nil }
        if locationService.isPreciseLocationOff { return .preciseLocationOff }
        return locationService.locationError
    }
}
