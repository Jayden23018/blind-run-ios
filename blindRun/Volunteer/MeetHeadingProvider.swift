import Combine
import CoreLocation

/// 汇合页专用的手机朝向（交付包 02 ④、03 §三）。
///
/// **自己持有一个 `CLLocationManager`，只在汇合页存活**，不碰全局 `LocationService` ——
/// 那条管位置上报与权限，朝向只有这一屏要，挂上去等于让每一页都开着罗盘。
/// 朝向不需要额外授权；拿不到（设备无罗盘、未校准）时 `heading` 保持 `nil`，方位盘不画扇形。
@MainActor
final class MeetHeadingProvider: NSObject, ObservableObject {
    /// 平滑后的朝向（度，正北 0，顺时针）。
    @Published private(set) var heading: Double?

    private let manager = CLLocationManager()
    private var isRunning = false

    func start() {
        guard !isRunning, CLLocationManager.headingAvailable() else { return }
        isRunning = true
        manager.delegate = self
        manager.headingFilter = HeadingFilter.minimumChange
        manager.startUpdatingHeading()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        manager.stopUpdatingHeading()
        heading = nil
    }
}

extension MeetHeadingProvider: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // 负精度 = 这一帧无效（未校准）。真北要有定位才有，拿不到退回磁北。
        guard newHeading.headingAccuracy >= 0 else { return }
        let raw = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in
            guard self.isRunning,
                  let next = HeadingFilter.next(previous: self.heading, raw: raw) else { return }
            self.heading = next
        }
    }
}
