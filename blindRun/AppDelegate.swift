import UIKit

/// APNs 回调入口。SwiftUI 生命周期下通过 `@UIApplicationDelegateAdaptor` 接入。
final class AppDelegate: NSObject, UIApplicationDelegate {

    /// App 生命周期内唯一的一份。放在这里而不是 `blindRunApp` 的 `@StateObject`：通知中心的 delegate
    /// 要在启动结束前设好（`didFinishLaunching`），那时根视图还没出来（#338 安全复核 HIGH 2）。
    let pushNotificationsManager = PushNotificationsManager()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        pushNotificationsManager.installAtLaunch()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        pushNotificationsManager.handleDeviceToken(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        pushNotificationsManager.handleRegistrationFailure(error)
    }
}
