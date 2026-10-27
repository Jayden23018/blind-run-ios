import Foundation

// 持续定位的角色与账号边界（#417 / #425）。从 `AppState.swift` 挪出来：那个文件已经超长（SwiftLint 棘轮），
// 而这一组只读 `AppState` 的状态、只调 `LocationService`，放在一处也更好找。
extension AppState {

    /// 为派单上报位置的总闸：开着接单开关，且同意过志愿者位置轨迹。
    /// 同意文案第 1 条写了「暂停接单后不再为派单获取位置」，这一闸就是它的兑现。
    var allowsVolunteerDispatchLocationReporting: Bool {
        volunteerWantsDispatch && hasLocationTrackConsent(.volunteerLocationTrack)
    }

    /// 角色这一层要不要持续定位（#425）。结果只由状态决定，凡是会改变它的地方都调一次：
    /// 注入定位服务、登录 / 换账号、换角色、接单开关、记下位置轨迹同意。
    /// - 盲人：在线、且同意过盲人位置轨迹（首页播报位置、求助取新坐标都靠它）。
    /// - 陪跑员：在线、开着接单开关、且同意过陪跑员位置轨迹。同意文案第 1 条写的是
    ///   「暂停接单后不再为派单获取位置」—— 关开关就撤回，不只是不上传。
    ///
    /// 只管这两份。页面、同行会话各自要的定位由它们自己撤回，这里不碰：
    /// 关接单开关时同行会话还在跑的话，硬件照开。
    /// 先立新的、再撤旧的：换到同样同意过的角色时硬件不会停了又开。
    func syncRoleLocationIntents() {
        guard let locationService else { return }
        let wantsBlindRole = isLoggedIn && activeRole == .blind && hasLocationTrackConsent(.blindLocationTrack)
        let wantsDispatch = isLoggedIn && activeRole == .volunteer && allowsVolunteerDispatchLocationReporting
        if wantsBlindRole { locationService.startUpdating(for: .blindRole) }
        if wantsDispatch { locationService.startUpdating(for: .volunteerDispatch) }
        if !wantsBlindRole { locationService.stopUpdating(for: .blindRole) }
        if !wantsDispatch { locationService.stopUpdating(for: .volunteerDispatch) }
    }

    /// 换账号 / 换角色 / 退出登录时，当前账号的当前角色在本机没有位置轨迹同意就停掉持续定位（#417）。
    /// 有同意时不全停：角色这一层由紧跟着的 `syncRoleLocationIntents` 换成新角色那一份，先立后撤，硬件不停了又开。
    /// 同行会话不受影响：换角色本来就会 `liveEscortCoordinator.reset`，新角色的会话由它自己立意图。
    func stopLocationUpdatesWithoutTrackConsent() {
        if let purpose = PrivacyConsentPurpose.locationTrack(for: activeRole),
           hasLocationTrackConsent(purpose) {
            return
        }
        stopLocationUpdates()
    }

    func stopLocationUpdates() {
        // 生产里唯一的注入点是 `blindRunApp` 根视图那一行，单测都自己注入 —— 删掉那一行所有单测照样绿，
        // 而这次修复整个失效。所以真 App（含 UI 用例跑的那个）里没注入就当场崩；单测宿主进程不注入是常态，放行。
        assert(
            locationService != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil,
            "AppState.locationService 未注入：退出登录 / 换角色停不了定位（#417）"
        )
        locationService?.stopAllUpdates()
    }
}
