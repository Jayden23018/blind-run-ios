import UIKit

/// APNs 回调入口。SwiftUI 生命周期下通过 `@UIApplicationDelegateAdaptor` 接入。
final class AppDelegate: NSObject, UIApplicationDelegate {

    /// 由 `blindRunApp` 注入后转发 APNs 回调。
    var pushNotificationsManager: PushNotificationsManager?

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        pushNotificationsManager?.handleDeviceToken(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        pushNotificationsManager?.handleRegistrationFailure(error)
    }
}
