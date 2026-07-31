import Combine
import Foundation
import UIKit
import UserNotifications

// MARK: - APNs Token 上报请求

/// `POST /api/devices/apns`。后端校验 `deviceToken` 为 32~128 位 hex，`platform` 预留 ANDROID。
nonisolated struct ApnsTokenRequest: Encodable, Sendable {
    let deviceToken: String
    let platform: String

    init(deviceToken: String, platform: String = "IOS") {
        self.deviceToken = deviceToken
        self.platform = platform
    }
}

// MARK: - Push Notifications Manager

/// APNs 离线推送接线：授权、注册、deviceToken 上报，以及收到推送时的播报。
///
/// 后端只对 `priority=HIGH` 的通知补发 APNs（紧急求助 / 走散告警 / 到达 / 取消预警），
/// 正文优先 `ttsText`。盲人用户收到即朗读，走既有的 `SpeechService`，不另起一套 TTS。
///
/// **deviceToken 是凭据**：只在内存里比对与上报，不写日志、不进无障碍字符串。
final class PushNotificationsManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {

    /// 最近一次成功上报的 token，避免同一 token 反复上报（Apple 每次注册都会回调）。
    private var lastReportedToken: String?

    /// 未登录时拿到的 token 缓存，登录后补报。
    private var pendingToken: String?

    private weak var appState: AppState?
    private weak var speechService: SpeechService?

    func configure(appState: AppState, speechService: SpeechService) {
        self.appState = appState
        self.speechService = speechService
        UNUserNotificationCenter.current().delegate = self
    }

    /// 请求通知授权，通过后注册远程通知。启动时调用一次即可。
    func requestAuthorizationAndRegister() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            Task { @MainActor in
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    /// APNs 回调：转 hex 字符串，已登录则上报，未登录则缓存等登录后补报。
    nonisolated func handleDeviceToken(_ data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            self.submitToken(token)
        }
    }

    /// 注册失败不阻断任何业务流程：APNs 只是 WS 离线时的兜底通道。
    /// 免费个人开发者团队没有 Push Notifications capability，本机真机调试必然走到这里。
    nonisolated func handleRegistrationFailure(_ error: Error) {
        ClientFlowDiagnostics.record(event: "registration_failed", operation: "apns")
    }

    /// 进前台或登录态变化时调用：重新注册以拿到可能被 Apple 轮换过的 token，并补报缓存的 token。
    func refreshRegistrationIfReady() {
        guard appState?.isLoggedIn == true else { return }
        if let pendingToken {
            submitToken(pendingToken)
        }
        UIApplication.shared.registerForRemoteNotifications()
    }

    private func submitToken(_ token: String) {
        guard let appState, appState.isLoggedIn else {
            // 未登录：缓存，等 refreshRegistrationIfReady 补报。
            pendingToken = token
            return
        }
        guard token != lastReportedToken else {
            pendingToken = nil
            return
        }
        let request = ApnsTokenRequest(deviceToken: token)
        Task { @MainActor in
            do {
                let _: EmptyResponse = try await appState.apiClient.post("/api/devices/apns", body: request)
                self.lastReportedToken = token
                self.pendingToken = nil
            } catch {
                // 不清 lastReportedToken：下次进前台或重新登录时自然重试。
                self.pendingToken = token
                ClientFlowDiagnostics.record(event: "failed", operation: "apns-token-report")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// 前台收到推送：直接朗读，并保留横幅与提示音（HIGH 通知不应静默）。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        speak(from: notification)
        completionHandler([.banner, .sound])
    }

    /// 后台/冷启动时用户点开推送：补一次朗读。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        speak(from: response.notification)
        completionHandler()
    }

    private nonisolated func speak(from notification: UNNotification) {
        let content = notification.request.content
        let text = Self.speechText(userInfo: content.userInfo, fallbackBody: content.body)
        guard !text.isEmpty else { return }
        Task { @MainActor in
            self.speechService?.speak(text)
        }
    }

    /// 播报文案优先 `ttsText`（后端为盲人用户单独写的口播版本），退化到通知正文。
    static func speechText(userInfo: [AnyHashable: Any], fallbackBody: String) -> String {
        if let ttsText = (userInfo["ttsText"] as? String)?.trimmed, !ttsText.isEmpty {
            return ttsText
        }
        return fallbackBody.trimmed
    }
}
