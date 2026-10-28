import CoreLocation
import Foundation

// 交给后端的样本（已转 GCJ-02）。从 `LocationService.swift` 挪出来（那个文件超长，SwiftLint 棘轮），行为不变。
extension LocationService {

    func latestBackendSample(now: Date = Date(), freshness: TimeInterval = 15) -> LocatedCoordinate? {
        guard let sample = latestDeviceSample,
              now.timeIntervalSince(sample.capturedAt) <= freshness else { return nil }
        return BackendCoordinateNormalizer.normalize(sample)
    }

    /// 同行会话可以接受的最大样本年龄。
    ///
    /// **不是 15 秒**（求助路径 `latestBackendSample` 那道闸的值）。上报周期是 5 秒，而
    /// `distanceFilter` 是 5–10 米 —— 正常走动时样本随时在来，60 秒是个很宽的门；
    /// 取这么宽正是为了不把「人站住了、坐标没变」误判成定位失效。
    ///
    /// ⚠️ 已知代价：非陪跑模式下 `distanceFilter = 10`，本仓库自己记着「站着不动 Core Location
    /// 就不推新样本」（`BlindBookingView.swift:967-977`，那条注释来自一次真实的线上误判）。
    /// 所以 `DRIVER_EN_ROUTE` / `DRIVER_ARRIVED` 期间原地站够 60 秒仍可能报一次
    /// 「设备位置暂时不可用」。相对于「让对端一直以为陈旧坐标是新的」，这一侧的代价更小 ——
    /// 说错「位置暂时不可用」用户还能自己判断，说对了「15 秒内的新位置」而其实是十分钟前的，
    /// 看不见屏幕的人无从分辨。
    nonisolated static let escortSampleMaxAge: TimeInterval = 60

    /// 同行会话按固定 cadence 复用最近一次真实设备样本；**坐标静止不等于定位失效，
    /// 但样本停更等于**。
    ///
    /// 这两件事此前被当成一件事：原实现只看权限与 `locationError`，不看样本年龄，
    /// 注释还写明是故意的。后果是 GPS 卡住（隧道、地库、商场、iOS 自动暂停）时
    /// Core Location 常常**不报错**、只是不再送新样本，于是发送端每 5 秒把同一个陈旧坐标
    /// 重发一次，服务端每次打上**当前**时间戳，接收端每次都判定「这是 15 秒内的新位置」。
    /// 上行报文里没有采样时间（`WSLocationUpdateMessage` 只有 `type/lat/lng`），
    /// 对端因此没有任何办法自己看穿 —— 只能由发送端不发。
    ///
    /// 返回 nil 同时达成两件事，不需要各自再加判断：
    /// `sendLatestLocation` 的 `guard let sample` 停发（连 `escort-location-send` 的诊断事件
    /// 都不会产生），`refreshHealth` 的 `guard ... != nil` 落到 `.waitingForLocation`。
    ///
    /// 根因修法是后端给 `WSLocationUpdateMessage` 补 `capturedAt` 并透传给对端 —— 已列入待投递。
    func latestEscortBackendSample(
        now: Date = Date(),
        maxAge: TimeInterval = LocationService.escortSampleMaxAge
    ) -> LocatedCoordinate? {
        guard isAuthorized,
              locationError == nil,
              let sample = latestDeviceSample,
              now.timeIntervalSince(sample.capturedAt) <= maxAge else { return nil }
        return BackendCoordinateNormalizer.normalize(sample)
    }
}
