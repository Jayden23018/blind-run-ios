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
    /// - Parameter environment: 只给 DEBUG 下的 UI 测试定位接缝读，单测用它钉住接缝排在同意闸之后。
    static func freshEmergencyCoordinate(
        using locationService: LocationService?,
        sharingBlocked: Bool = false,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async -> LocatedCoordinate? {
        guard !sharingBlocked else { return nil }
        #if DEBUG
        // UI 测试定位接缝（#500）：排在同意闸之后，同意页的约束照样成立；排在精确位置闸之前，
        // 所以和 `AIDRUN_UI_TEST_PRECISE_LOCATION_OFF` 同开时照样出样本 —— 验「精确位置关→不发」的 UI 用例别开接缝。
        if let sample = uiTestEmergencySample(environment: environment) { return sample }
        #endif
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

    /// 临时精确位置的系统弹窗最多等陪跑员这么久回答（#407 第 1 项）。超时按「仍然关着」处理：
    /// 求助等不起一个没人点的弹窗，而降级出来的本地拨号此刻就能打。
    /// `nonisolated`：它是下面那个函数参数的默认值，默认值在非隔离上下文里求值。
    nonisolated static let preciseLocationAnswerTimeout: TimeInterval = 15

    /// 陪跑员代发求助取坐标（#407 第 1 项）：与跑者同一道闸（`freshEmergencyCoordinate`），
    /// 区别只在「精确位置」关着时**先申请一次**临时精确位置、等他回答。
    ///
    /// 此前陪跑员这边直接拿 `latestBackendSample()`，精确位置关着时会把约 5 公里外的区域代表点
    /// 当成求助坐标发出去 —— 违反 `AGENTS.md` §6「必须带新鲜的真实 GCJ-02 坐标，拿不到就不发」。
    /// 跑者端不问（系统弹窗会和「求助未发出」的播报抢读屏焦点）；陪跑员一般看得见屏幕，弹窗是最快的出路。
    /// 系统也可能不弹（SDK：App 不在前台等情况），所以等不到就照常返回 nil，由调用方降级本地拨号。
    static func freshEmergencyCoordinateAskingForPrecision(
        using locationService: LocationService?,
        sharingBlocked: Bool,
        answerTimeout: TimeInterval = preciseLocationAnswerTimeout
    ) async -> LocatedCoordinate? {
        // 没同意共享位置时不问：问了也不会用这个坐标（同意闸在 `freshEmergencyCoordinate` 里）。
        if !sharingBlocked, let locationService, locationService.isPreciseLocationOff {
            locationService.requestTemporaryPreciseLocation(for: .escortRun)
            let deadline = Date().addingTimeInterval(answerTimeout)
            while locationService.isPreciseLocationOff, Date() < deadline {
                guard !Task.isCancelled else { return nil }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        return await freshEmergencyCoordinate(using: locationService, sharingBlocked: sharingBlocked)
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

    #if DEBUG
    /// UI 测试定位接缝的开关（#500）。
    static let uiTestEmergencyLocationKey = "AIDRUN_UI_TEST_EMERGENCY_LOCATION"

    /// UI 测试里拿不到设备采样，求助恒落「未发出：拿不到定位」，于是没有任何 UI 用例走得到屏 3b，
    /// 它的弹出接线（`EmergencyRecoveryPresentation` 的两个 `onChange`）改坏了也不会有用例报红。
    /// 这里产出一份**标记为测试来源**（`.uiTestSeam`）的 GCJ-02 样本，只为让 UI 用例走完这条路。
    ///
    /// 「演示坐标绝不上传」（`AGENTS.md` §6）由三道互相独立的闸守：
    /// ① 只编进 DEBUG；② 只在 UI 测试设了这个开关、**且**选的是 Mock 环境时才有样本；
    /// ③ `trigger` 在客户端不是 Mock 时硬性拒绝测试来源的样本 —— 哪怕前两道都被绕开，
    ///    坐标也一个字节都不会发往真实后端。
    static func uiTestEmergencySample(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        now: Date = Date()
    ) -> LocatedCoordinate? {
        guard environment[uiTestEmergencyLocationKey] == "1",
              environment["AIDRUN_UI_TEST_API_ENV"] == "mock" else { return nil }
        return LocatedCoordinate(
            coordinate: CLLocationCoordinate2D(latitude: 39.9289, longitude: 116.3883),
            system: .gcj02Backend,
            capturedAt: now,
            horizontalAccuracy: 10,
            source: .uiTestSeam
        )
    }
    #endif
}
