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

    /// 一次上报的归属：token 本身，加上收下它的那个后端与账号。
    ///
    /// 只比 token 是不够的：`/api/devices/apns` 的记录存在服务端，切环境换了后端、
    /// 或换账号后，新的一侧根本没有这条记录，而 Apple 回调的 token 通常一模一样，
    /// 于是短路掉重报——推送从此静默失效，且没有任何报错。
    struct ReportedTokenScope: Equatable {
        let token: String
        let environment: APIEnvironment
        let userId: Int64?
    }

    /// 最近一次成功上报的归属，避免同一 token 对同一后端同一账号反复上报
    /// （Apple 每次注册都会回调）。
    private var lastReportedScope: ReportedTokenScope?

    /// 未登录时拿到的 token 缓存，登录后补报。
    private var pendingToken: String?

    private weak var appState: AppState?
    private weak var speechService: SpeechService?
    private var sessionStateCancellable: AnyCancellable?

    /// 向 APNs 注册 / 注销本机的接缝。单测换成记账的替身：宿主 App 里真调会改掉测试机的注册状态。
    struct RemoteNotificationRegistrar {
        let register: @MainActor () -> Void
        let unregister: @MainActor () -> Void
        /// 清掉通知中心里已经送达的通知。会话结束时调：留着的话，下一个人登录后点开，会念出上一个人的消息。
        var clearDelivered: @MainActor () -> Void = {}

        static let system = RemoteNotificationRegistrar(
            register: { UIApplication.shared.registerForRemoteNotifications() },
            unregister: { UIApplication.shared.unregisterForRemoteNotifications() },
            clearDelivered: { UNUserNotificationCenter.current().removeAllDeliveredNotifications() }
        )
        static let inert = RemoteNotificationRegistrar(register: {}, unregister: {})
    }

    var registrar: RemoteNotificationRegistrar =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil ? .system : .inert
    /// `configure` 之前就到了的锁屏邀请操作（冷启动：系统在启动结束前就回调 delegate，根视图还没出来）。
    private var inviteActionsBeforeConfigure: [InviteNotificationActions.Request] = []

    /// 启动结束前调（`AppDelegate.didFinishLaunching`）。系统要求通知中心的 delegate 在那之前设好，
    /// 否则冷启动时那一下点击 / 锁屏操作的回调会丢（#338 安全复核 HIGH 2）。
    func installAtLaunch() {
        UNUserNotificationCenter.current().delegate = self
        // 邀请类 APNs 的锁屏操作（#338）。category 不分角色注册：跑者收不到邀请推送，注册了也不会出现。
        UNUserNotificationCenter.current().setNotificationCategories(InviteNotificationActions.categories)
    }

    func configure(appState: AppState, speechService: SpeechService) {
        self.appState = appState
        self.speechService = speechService
        installAtLaunch()
        // 只在有人登录时向 APNs 注册（#459）。会话一结束就注销：服务端解绑可能没成（断网登出），
        // 旧账号的推送还会发到这个 token，而 App 不在前台时横幅由系统直接弹，前台闸拦不住。
        // Apple 文档把「用户登出与推送关联的账号」列为调用 `unregisterForRemoteNotifications` 的场景。
        // 恢复中 / 校验失败不动：那时还不知道会话在不在。
        sessionStateCancellable = appState.$sessionRestorationState
            .compactMap(Self.wantsRemoteNotifications)
            .removeDuplicates()
            .sink { [weak self, weak appState] signedIn in
                guard let self else { return }
                if signedIn {
                    self.registrar.register()
                } else {
                    self.registrar.unregister()
                    self.registrar.clearDelivered()
                }
                // 回到登录页（下次登录前）与登录成功后各补撤一次没撤完的上一次登录。不等它：
                // 两件事互不依赖（后端解绑只删属于旧账号的那一行，新账号上报会自己换绑）。
                Task { await appState?.pendingSessionRevoker.retryIfPending() }
            }
        appState.realtimeCoordinator.pruneDeliveredInviteNotifications = { prune in
            Task { await InviteNotificationCenter.prune(prune) }
        }
        let early = inviteActionsBeforeConfigure
        inviteActionsBeforeConfigure = []
        for request in early { handleInviteAction(request) }
    }

    /// 这个会话状态下要不要收推送。nil = 还不知道（恢复中 / 校验失败），保持现状。
    nonisolated static func wantsRemoteNotifications(_ state: SessionRestorationState) -> Bool? {
        switch state {
        case .authenticated, .choosingRole: return true
        case .unauthenticated: return false
        case .restoring, .validationFailed: return nil
        }
    }

    /// 请求通知授权。启动时调用一次即可；注册本身跟着登录状态走（见 `configure`）。
    func requestAuthorizationAndRegister() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            Task { @MainActor in
                guard self.appState?.isLoggedIn == true else { return }
                self.registrar.register()
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
        // 回前台时补撤断网登出没撤完的上一次登录（#459）；没有待撤记录时什么都不做。不看有没有人登录。
        Task { await appState?.pendingSessionRevoker.retryIfPending() }
        guard appState?.isLoggedIn == true else { return }
        if let pendingToken {
            submitToken(pendingToken)
        }
        registrar.register()
    }

    private func submitToken(_ token: String) {
        guard let appState, appState.isLoggedIn else {
            // 未登录：缓存，等 refreshRegistrationIfReady 补报。
            pendingToken = token
            return
        }
        let scope = ReportedTokenScope(
            token: token,
            environment: appState.currentEnvironment,
            userId: appState.userId
        )
        guard scope != lastReportedScope else {
            pendingToken = nil
            return
        }
        Task { @MainActor in
            do {
                try await appState.auth.registerDeviceToken(token)
                self.lastReportedScope = scope
                self.pendingToken = nil
            } catch {
                // 不清 lastReportedScope：下次进前台或重新登录时自然重试。
                self.pendingToken = token
                ClientFlowDiagnostics.record(event: "failed", operation: "apns-token-report")
            }
        }
    }

    /// 解绑本机 token，**必须在 `POST /api/auth/logout` 之前调**。
    ///
    /// 顺序不是风格问题，是后端契约写死的（`api_spec.yaml` `unregisterApnsToken` 的 description）：
    /// logout 会把 JWT 拉黑，反过来调的话 JwtFilter 查到黑名单直接返 401，token 删不掉、洞照样在。
    /// 契约原文特意加了一句「这一条读代码看不出来，请写进登出流程的注释」—— 就是这一段。
    ///
    /// 不解绑的后果：token 仍绑在旧 userId 上，后端会继续对 `priority=HIGH`（求助 / 走散告警 /
    /// 到达 / 取消预警）补发 APNs 到这台手机，而 `userNotificationCenter(_:willPresent:)`
    /// **会直接朗读出来** —— 设备转手、借用、换人登录之后，念的是上一个人的订单和紧急消息。
    ///
    /// 失败不阻断登出：接口幂等、可安全重试，而把人卡在登录态里更糟。本地那份绑定记忆
    /// 无论成败都清掉，否则下一个账号的同一个 token 会被 `submitToken` 的短路判成「报过了」。
    ///
    /// - Returns: 还绑在旧账号上、值得之后补撤的 token（断网 / 限流 / 服务端错误）。
    ///   成功、本来没有、或 401（这次登录已结束，旧凭据解不了）都返回 nil。由 `AppState.logout` 记进待撤记录（#459）。
    func unregisterDeviceTokenBeforeLogout() async -> String? {
        defer { forgetLocalTokenBinding() }
        guard let token = lastReportedScope?.token ?? pendingToken,
              let appState, appState.isLoggedIn else { return nil }
        do {
            try await appState.auth.unregisterDeviceToken(token)
            return nil
        } catch {
            ClientFlowDiagnostics.record(event: "failed", operation: "apns-token-unregister")
            return PendingSessionRevoker.isWorthRetrying(error) ? token : nil
        }
    }

    /// 本机此刻绑着（或等着上报）的推送 token。「仅退出本机」记待撤记录时用。
    var boundDeviceToken: String? { lastReportedScope?.token ?? pendingToken }

    /// 补撤的解绑落地时同一账号已经又登录了，新会话那份绑定被删掉了：忘掉「报过了」，重新注册并上报（#459）。
    func reportTokenAgainAfterServerUnbind() {
        let token = lastReportedScope?.token
        forgetLocalTokenBinding()
        if let token { submitToken(token) }
        registrar.register()
    }

    /// 忘掉「这个 token 已经报给这个账号了」。
    ///
    /// 每一条会话结束路径都要走（含 401 过期 —— 那条路上 token 已经废了，解绑必然 401，
    /// 但本地这份记忆留着就会让下一个账号的上报被短路掉，推送从此静默失效）。
    func forgetLocalTokenBinding() {
        lastReportedScope = nil
        pendingToken = nil
    }

    #if DEBUG
    var hasLocalTokenBindingForTesting: Bool {
        lastReportedScope != nil || pendingToken != nil
    }

    func seedReportedScopeForTesting(_ scope: ReportedTokenScope) {
        lastReportedScope = scope
    }
    #endif

    // MARK: - UNUserNotificationCenterDelegate

    /// 前台收到推送：直接朗读，并保留横幅与提示音（HIGH 通知不应静默）。
    ///
    /// **没人登录时不朗读、不上屏**（#459）：这时收到的只可能是上一个账号的（服务端解绑可能还没补上），
    /// 念出来就是把上一个人的求助 / 订单消息念给下一个拿手机的人。
    /// 新邀请（`NEW_ORDER`，#338）例外：同一条邀请 WS 也会到，App 里的邀请卡 / 横幅才是它在前台的样子（设计交付 v3 §4.4.1）。
    /// 系统横幅不出、不念，改去对一次待回复列表 —— APNs 先到时由对账把它放进队列，WS 后到按 `inviteId` 去重，
    /// 两路只出现一次。`INVITE_EXPIRING` 照旧弹出（App 不处理 WS 那一条）。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Task { @MainActor in
            let signedIn = self.appState?.isLoggedIn == true
            // 没人登录：一律不上屏（#459）。有人登录：新邀请交给 App 内卡片（#338），其余照常横幅 + 提示音。
            let options = signedIn
                ? InviteNotificationActions.foregroundPresentationOptions(for: notification.request.content.userInfo)
                : Self.foregroundPresentation(isSignedIn: false)
            completionHandler(options)
            guard signedIn else { return }
            if options.isEmpty {
                await self.absorbForegroundInvite()
            } else {
                self.speak(from: notification)
            }
        }
    }

    /// 前台推送怎么呈现：有人登录才出横幅和提示音，没人登录一律不上屏（#459）。
    nonisolated static func foregroundPresentation(isSignedIn: Bool) -> UNNotificationPresentationOptions {
        isSignedIn ? [.banner, .sound] : []
    }

    /// 前台收到的 `NEW_ORDER` APNs：不出横幅、不念，对一次待回复列表，由 App 内邀请卡呈现（WS 后到按 `inviteId` 去重）。
    func absorbForegroundInvite() async {
        await appState?.restorePendingInvites()
    }

    /// 后台/冷启动时用户点开推送：补一次朗读。锁屏上按的是邀请操作时改走 `handleInviteAction`。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        guard let request = InviteNotificationActions.request(actionIdentifier: response.actionIdentifier, userInfo: userInfo) else {
            speak(from: response.notification)
            completionHandler()
            return
        }
        Task { @MainActor in
            self.handleInviteAction(request)
            completionHandler()
        }
    }

    /// 锁屏邀请操作（#338）。两个操作都已把 App 拉到前台：记给协调器，由首页对上队列里那一张后
    /// 走卡片上同一条路径；顺手对一次账，冷启动时队列是空的。还没 `configure` 就先存着。
    func handleInviteAction(_ request: InviteNotificationActions.Request) {
        guard let appState else {
            inviteActionsBeforeConfigure.append(request)
            return
        }
        appState.realtimeCoordinator.requestLockScreenInviteAction(request, userID: appState.userId)
        Task { await appState.restorePendingInvites() }
    }

    private nonisolated func speak(from notification: UNNotification) {
        let content = notification.request.content
        let text = Self.speechText(userInfo: content.userInfo, fallbackBody: content.body)
        guard !text.isEmpty else { return }
        Task { @MainActor in await self.announce(text) }
    }

    /// 朗读推送，**只在有人登录时**（#459）：没人登录时收到或点开的只可能是上一个账号的。
    /// 冷启动点开通知时会话还在恢复，先等它恢复完再判，免得把本人的消息也吞掉（最多等 `restorationWait`）。
    func announce(_ text: String, restorationWait: TimeInterval = 5) async {
        let deadline = Date().addingTimeInterval(restorationWait)
        while appState?.sessionRestorationState == .restoring, Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard appState?.isLoggedIn == true else { return }
        speechService?.speak(text)
    }

    /// 播报文案优先 `ttsText`（后端为盲人用户单独写的口播版本），退化到通知正文。
    static func speechText(userInfo: [AnyHashable: Any], fallbackBody: String) -> String {
        if let ttsText = (userInfo["ttsText"] as? String)?.trimmed, !ttsText.isEmpty {
            return ttsText
        }
        return fallbackBody.trimmed
    }
}
