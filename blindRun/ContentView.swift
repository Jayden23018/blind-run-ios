//
//  ContentView.swift
//  blindRun
//
//  Created by Jerry on 5/18/26.
//

import Combine
import CoreLocation
import SwiftUI

enum RootRoute: Equatable {
    case restoringAccount
    case unauthenticated
    case roleSelection
    case blindProfile
    case blindHome
    case volunteerProfile
    case volunteerHome
    case recoveryFailed(message: String)
}

private extension RootRoute {
    var diagnosticCategory: String {
        switch self {
        case .restoringAccount: return "account-restoration"
        case .unauthenticated: return "login"
        case .roleSelection: return "role-selection"
        case .blindProfile, .volunteerProfile: return "profile"
        case .blindHome, .volunteerHome: return "home"
        case .recoveryFailed: return "recovery-failed"
        }
    }
}

/// Owns the only mounted root destination. Profile hydration is committed
/// atomically so login/profile/home and AMap cannot overlap during routing.
@MainActor
final class ContentRootRouter: ObservableObject {
    @Published private(set) var route: RootRoute = .restoringAccount

    private var hydrationTask: Task<Void, Never>?
    private var generation: UInt64 = 0

    func synchronize(with appState: AppState) {
        generation &+= 1
        let currentGeneration = generation
        hydrationTask?.cancel()
        hydrationTask = nil

        switch appState.sessionRestorationState {
        case .restoring:
            route = .restoringAccount
        case .validationFailed(let message):
            route = .recoveryFailed(message: message)
        case .unauthenticated:
            route = .unauthenticated
        case .choosingRole:
            route = .roleSelection
        case .authenticated:
            guard appState.isLoggedIn else {
                route = .unauthenticated
                return
            }
            guard let role = appState.activeRole, role != .unset else {
                route = .roleSelection
                return
            }
            route = .restoringAccount
            hydrationTask = Task { [weak self, weak appState] in
                guard let self, let appState else { return }
                await self.hydrate(
                    role: role,
                    appState: appState,
                    generation: currentGeneration
                )
            }
        }
    }

    func cancel() {
        generation &+= 1
        hydrationTask?.cancel()
        hydrationTask = nil
    }

    private func hydrate(role: UserRole, appState: AppState, generation: UInt64) async {
        let token = appState.accessToken
        let userID = appState.userId

        switch role {
        case .blind:
            let profileTask: Task<BlindProfileResponse, Error> = Task {
                try await appState.profile.blindProfile()
            }
            let contactsTask: Task<[EmergencyContactResponse], Error>? = userID.map { id in
                Task { try await appState.profile.emergencyContacts(userId: id) }
            }
            defer {
                profileTask.cancel()
                contactsTask?.cancel()
            }

            do {
                let profile = try await withTaskCancellationHandler {
                    try await profileTask.value
                } onCancel: {
                    profileTask.cancel()
                    contactsTask?.cancel()
                }
                let contacts = try await contactsTask?.value ?? []
                guard isCurrent(
                    appState: appState,
                    token: token,
                    userID: userID,
                    role: role,
                    generation: generation
                ) else { return }
                appState.updateBlindProfile(profile)
                appState.updateEmergencyContacts(contacts)
                // 引导流：硬门槛（昵称 + 恰好 1 位主紧急联系人）未过，或实名软提示还没被跳过，
                // 都停在 .blindProfile（由 BlindRunnerOnboardingView 决定展示哪一步）。
                route = appState.blindOnboardingStep == nil ? .blindHome : .blindProfile
            } catch {
                handleHydrationFailure(
                    error,
                    role: role,
                    appState: appState,
                    token: token,
                    userID: userID,
                    generation: generation
                )
            }

        case .volunteer:
            let profileTask: Task<VolunteerProfileResponse, Error> = Task {
                try await appState.profile.volunteerProfile()
            }
            // `try?` 是既有的刻意降级：拿不到注册状态时 `isVolunteerProfileApproved`
            // 退回只看 profile 的判定（`AppState.swift` 同名属性），不是静默失败。
            let registrationTask: Task<VolunteerRegistrationStatus?, Never> = Task {
                try? await appState.profile.volunteerRegistrationStatus()
            }
            defer {
                profileTask.cancel()
                registrationTask.cancel()
            }

            do {
                let profile = try await withTaskCancellationHandler {
                    try await profileTask.value
                } onCancel: {
                    profileTask.cancel()
                    registrationTask.cancel()
                }
                let registration = await registrationTask.value
                guard isCurrent(
                    appState: appState,
                    token: token,
                    userID: userID,
                    role: role,
                    generation: generation
                ) else { return }
                appState.updateVolunteerProfile(profile)
                if let registration { appState.updateVolunteerRegistrationStatus(registration) }
                route = appState.isVolunteerProfileApproved ? .volunteerHome : .volunteerProfile
            } catch {
                handleHydrationFailure(
                    error,
                    role: role,
                    appState: appState,
                    token: token,
                    userID: userID,
                    generation: generation
                )
            }

        case .unset:
            route = .roleSelection
        }
    }

    private func isCurrent(
        appState: AppState,
        token: String?,
        userID: Int64?,
        role: UserRole,
        generation: UInt64
    ) -> Bool {
        !Task.isCancelled &&
        self.generation == generation &&
        appState.accessToken == token &&
        appState.userId == userID &&
        appState.activeRole == role
    }

    private func handleHydrationFailure(
        _ error: Error,
        role: UserRole,
        appState: AppState,
        token: String?,
        userID: Int64?,
        generation: UInt64
    ) {
        guard isCurrent(
            appState: appState,
            token: token,
            userID: userID,
            role: role,
            generation: generation
        ) else { return }

        if let apiError = error as? APIError {
            if appState.handleAuthenticatedAPIError(apiError) {
                route = .unauthenticated
                return
            }
            if case .unknown(statusCode: 404) = apiError {
                route = role == .blind ? .blindProfile : .volunteerProfile
                return
            }
            route = .recoveryFailed(message: apiError.localizedMessage)
        } else {
            route = .recoveryFailed(message: "账号资料恢复失败，请检查网络后重试。")
        }
    }
}

/// 根路由视图，根据 AppState 的登录状态和活跃角色决定显示内容。
/// 路由由 @Published 属性驱动，登录或角色切换后自动更新。
struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationService: LocationService
    @State private var showRestorationLocalSignOutConfirmation = false
    @EnvironmentObject private var speechService: SpeechService
    @State private var showLogoutConfirmation = false
    #if DEBUG
    // 只给下面那条 Mock 横幅用：横屏时顶部安全区为 0，没有能放它的地方。
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif
    @StateObject private var rootRouter = ContentRootRouter()
    @State private var notificationAnnouncementGate = CurrentValueReplayGate<UUID>()
    @State private var healthAnnouncementGate = CurrentValueReplayGate<LiveEscortHealthState>()
    private let locationReportTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    private var rootRoutingKey: String {
        let restoration: String
        switch appState.sessionRestorationState {
        case .restoring: restoration = "restoring"
        case .validationFailed: restoration = "failed"
        case .unauthenticated: restoration = "unauthenticated"
        case .choosingRole: restoration = "choosing-role"
        case .authenticated: restoration = "authenticated"
        }
        return "\(restoration)-\(appState.accessToken?.hashValue ?? 0)-\(appState.activeRole?.rawValue ?? "no-role")-\(appState.userId ?? -1)-\(appState.isBlindBookingReady)-\(appState.didDismissBlindIdentityPrompt)-\(appState.isVolunteerProfileApproved)"
    }

    /// 同意隐私告知之后的正文。抽成独立属性只是为了给 `body` 里的同意门腾出 if/else 的位置，
    /// 路由逻辑一行未动。
    @ViewBuilder
    private var routedContent: some View {
        Group {
            switch rootRouter.route {
            case .restoringAccount:
                VStack(spacing: 16) {
                    ProgressView()
                    Text("正在恢复账号资料")
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("正在恢复账号资料，请稍候")
                .accessibilityIdentifier("rootRoute.restoringAccount")
            case .recoveryFailed(let message):
                VStack(spacing: 20) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 40))
                        .accessibilityHidden(true)
                    Text("暂时无法恢复账号资料")
                        .font(.headline)
                    Text(message)
                        .multilineTextAlignment(.center)
                    Button("重试恢复") {
                        rootRouter.synchronize(with: appState)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("重新加载当前账号资料")
                    Button("退出登录", role: .destructive) {
                        Task { await appState.logout() }
                    }
                    .accessibilityHint("退出当前账号并返回登录页")
                }
                .padding(24)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("rootRoute.recoveryFailed")
            case .unauthenticated:
                LoginView()
                    .accessibilityIdentifier("rootRoute.unauthenticated")
            case .roleSelection:
                RoleSelectionView()
                    .accessibilityIdentifier("rootRoute.roleSelection")
            case .blindProfile:
                // 兜底取 .identityPrompt：这条路由只在 step != nil 时进入，
                // step 变 nil 的那一瞬间 rootRoutingKey 已经变了，下一帧就会重新路由到 .blindHome。
                BlindRunnerOnboardingView(
                    step: appState.blindOnboardingStep ?? .identityPrompt,
                    onSkipIdentityPrompt: { appState.dismissBlindIdentityPrompt() }
                )
                .accessibilityIdentifier("rootRoute.blindProfile")
            case .blindHome:
                BlindRunnerHomeView()
                    .accessibilityIdentifier("rootRoute.blindHome")
            case .volunteerProfile:
                NavigationStack {
                    VolunteerProfileView()
                }
                .accessibilityIdentifier("rootRoute.volunteerProfile")
            case .volunteerHome:
                VolunteerHomeView()
                    .accessibilityIdentifier("rootRoute.volunteerHome")
            }
        }
    }

    var body: some View {
        Group {
            // 同意门排在路由**之前**：没同意就不该出现任何一个会收集信息的界面，登录页也算
            // （手机号是个人信息）。判定在 `AppState.didAcceptPrivacyConsent`，
            // 只有用户按下「同意并开始使用」才会翻面 —— 「看过这一页」不算同意。
            if !appState.didAcceptPrivacyConsent {
                PrivacyConsentGateView()
                    .accessibilityIdentifier("rootRoute.privacyConsent")
            } else {
                routedContent
            }
        }
        #if DEBUG
        // Mock 横幅：`.overlay` + 钉进状态栏那一条，**不是** `.safeAreaInset`。
        //
        // 原来写的是 `.safeAreaInset(edge: .top)`，而各路由自己建 `NavigationStack`
        // （见 `routedContent`，盲人首页那条在 `BlindRunnerHomeView.body`）。safeAreaInset
        // 改的是外层安全区，压不动内层那条导航栏 —— 2026-09-05 iPhone 16 Pro 真机实测
        // （窗口 402x874）：横幅 y `0..101.3`，导航栏 y `62..116`，标题 y `73.7..94.3`
        // **整条被盖住**。`.contrast` 审计于是采到横幅的黄底黑字、报的却是被盖在下面的
        // 页面标题，创建预约 / 使用帮助 / 服务成就三条审计用例随机红。
        //
        // 换成 `overlay` 的关键在于**它一个 pt 都不占**。顶部一旦占位，每一屏的内容区都会
        // 矮一截，而盲人首页那一列（地图留白 + 280pt 主按钮 + 「重复当前状态」）离底部
        // 常驻 SOS 条只剩几十 pt —— `testBlindHomeWithoutAnOrderHidesAskQuestionAndKeeps…`
        // 守的就是这个距离。overlay 不改任何 frame，那一批几何断言全部不受影响。
        //
        // **字号别动，保持 `.callout`。** 写死 pt 那版曾是这套审计长期报红的唯一根因
        // （`.dynamicType` 报「User will not be able to change the font size of this element」）。
        // 2026-09-05 改这条横幅时顺手换成 `.caption2`（配更紧的内边距），真机上**同一条审计
        // 立刻又红**，报的还是这枚胶囊本身（`id=` 空、`label=Mock 本地模拟`、
        // `frame=(33, 17, 97, 13.3)`），创建预约 / 使用帮助 / 服务成就三条全挂；换回
        // `.callout` 当轮即干净。横幅是 `#if DEBUG` + Mock 专属，而 UI 测试恰好全跑在这个
        // 组合下，于是它出现在**每一屏** —— 常年红的门禁等于没有门禁
        // （记忆 `known-red-suites-hide-new-failures`）。
        //
        // ponytail: 压成状态栏里的一枚小胶囊，只盖掉时钟 —— 这块屏幕上最不重要的东西。
        // 文字压短并靠左，躲开灵动岛（16 Pro 上约 x 143..259）；靠左 24 / 距顶 14 是为了
        // 落在屏幕圆角之内。横屏（`verticalSizeClass == .compact`）顶部安全区为 0，
        // 没有可落脚的地方，直接不挂 —— 与其盖住返回按钮，不如没有。
        //
        // ponytail 天花板：状态栏只有 59pt 高，而字号必须可缩放（上面那条），所以 AX4/AX5
        // 下这枚胶囊仍会长到导航栏上。没管，因为它 `#if DEBUG` + Mock 专属、不会发布，
        // 且没有任何自动用例跑在 AX 档（UI 测试一律默认字号）。真要管：把 `dynamicTypeSize`
        // 也加进上面那个 `if`，代价是审计放大字号时元素会消失，得重新验一轮审计。
        .overlay(alignment: .topLeading) {
            if appState.currentEnvironment == .mock, verticalSizeClass != .compact {
                Label("Mock 本地模拟", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.bold())
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.yellow, in: Capsule())
                    .padding(.leading, 24)
                    .padding(.top, 14)
                    // 状态栏那一条本来就没有可点的东西，但让它可点会把「点状态栏回到顶部」
                    // 这个系统手势吃掉。
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("警告：Mock 本地模拟，不连接云端")
                    .accessibilityIdentifier("mockEnvironmentBanner")
                    .ignoresSafeArea(edges: .top)
            }
        }
        #endif
        .onReceive(locationService.$currentLocation) { _ in
            reportWebSocketLocationIfNeeded()
        }
        .onReceive(locationReportTimer) { _ in
            reportWebSocketLocationIfNeeded()
        }
        .onChange(of: appState.activeRole) { _ in
            if appState.isLoggedIn, appState.currentEnvironment != .mock {
                locationService.startUpdating()
            }
            reportWebSocketLocationIfNeeded()
        }
        .task(id: rootRoutingKey) {
            appState.liveEscortCoordinator.attachLocationService(locationService)
            rootRouter.synchronize(with: appState)
        }
        .onChange(of: rootRouter.route) { route in
            MainRunLoopWatchdog.shared.setPageCategory(route.diagnosticCategory)
        }
        .modifier(SessionLifecycleStatusModifier())
        .overlay(alignment: .top) {
            if let notification = appState.realtimeCoordinator.currentNotification {
                RealtimeForegroundNotificationBanner(
                    notification: notification,
                    onDismiss: { appState.realtimeCoordinator.dismissCurrentNotification() }
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                // 「减弱动态效果」开启时只淡入淡出，不从屏幕顶端滑进来。
                // 这条横幅是主动弹出的（不是用户操作触发），突然的位移最容易引起不适；
                // 淡入保留了「有新东西出现」这个提示本身。
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                .zIndex(100)
            }
        }
        .onReceive(appState.realtimeCoordinator.$currentNotification.compactMap { $0 }) { notification in
            // @Published is a current-value publisher. Speaking mutates VoiceService,
            // which invalidates this view and recreates the subscription. Without an
            // identity gate, the recreated subscription immediately replays the same
            // notification and forms a main-thread render/TTS feedback loop.
            guard notificationAnnouncementGate.accepts(notification.id) else { return }
            speechService.speak(notification.speechText)
        }
        .onReceive(appState.liveEscortCoordinator.$healthState.removeDuplicates()) { state in
            // removeDuplicates only applies within one subscription. SwiftUI may
            // recreate the subscription after any environment-object publication,
            // so retain the last handled value in view state across subscriptions.
            guard healthAnnouncementGate.accepts(state) else { return }
            if let message = state.userMessage { speechService.speak(message) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let message = appState.liveEscortCoordinator.healthState.userMessage {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "location.fill.viewfinder")
                        .foregroundColor(AppColors.warning)
                        .accessibilityHidden(true)
                    Text(message)
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.textPrimary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(message)
                .accessibilityIdentifier("liveEscortHealthBanner")
            }
        }
        .alert("确认仅退出本机", isPresented: $showRestorationLocalSignOutConfirmation) {
            Button("仅退出本机", role: .destructive) { appState.clearSession() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前无法确认服务端 Token 已撤销。仅退出本机会清除本机登录信息，但远端 Token 可能继续有效。")
        }
    }

    private func reportWebSocketLocationIfNeeded() {
        guard appState.isLoggedIn,
              appState.activeRole == .volunteer,
              appState.currentEnvironment != .mock,
              locationService.isAuthorized,
              !appState.liveEscortCoordinator.isSessionEligible,
              let sample = locationService.latestBackendSample() else {
            return
        }

        locationService.startUpdating()
        appState.webSocketService?.sendLocationUpdate(
            lat: sample.coordinate.latitude,
            lng: sample.coordinate.longitude
        )
    }

}

/// Retains the identity last handled by a SwiftUI `onReceive` closure.
///
/// Combine's `@Published` publisher immediately emits its current value to every
/// new subscriber. SwiftUI is allowed to rebuild a subscription when another
/// observed object changes, so `removeDuplicates()` alone cannot suppress the
/// replay across subscription lifetimes.
struct CurrentValueReplayGate<Value: Equatable> {
    private(set) var lastAcceptedValue: Value?

    mutating func accepts(_ value: Value) -> Bool {
        guard lastAcceptedValue != value else { return false }
        lastAcceptedValue = value
        return true
    }
}

private struct SessionLifecycleStatusModifier: ViewModifier {
    @EnvironmentObject private var appState: AppState

    private var logoutFailure: Binding<Bool> {
        Binding(
            get: { if case .revocationFailed = appState.logoutState { return true }; return false },
            set: { if !$0 { appState.dismissLogoutFailure() } }
        )
    }

    private var deletionFailure: Binding<Bool> {
        Binding(
            get: { if case .revocationFailed = appState.accountDeletionState { return true }; return false },
            set: { if !$0 { appState.dismissAccountDeletionFailure() } }
        )
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if appState.logoutState == .inProgress || appState.accountDeletionState == .inProgress {
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        ProgressView("正在处理，请稍候")
                            .padding(24)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                            .accessibilityLabel("请求正在处理中，请稍候")
                    }
                }
            }
            .alert("服务端退出失败", isPresented: logoutFailure) {
                Button("重试") { Task { await appState.logout() } }
                Button("仅退出本机", role: .destructive) { appState.confirmLocalOnlySignOut() }
                Button("取消", role: .cancel) { appState.dismissLogoutFailure() }
            } message: {
                let message: String = {
                    if case .revocationFailed(let value) = appState.logoutState { return value }
                    return "未能确认服务端 Token 已撤销。"
                }()
                Text("\(message) 仅退出本机可能使远端 Token 继续有效。")
            }
            .alert("删除账户失败", isPresented: deletionFailure) {
                Button("重试") { Task { await appState.deleteCurrentAccount() } }
                Button("取消", role: .cancel) { appState.dismissAccountDeletionFailure() }
            } message: {
                if case .revocationFailed(let message) = appState.accountDeletionState {
                    Text(message)
                }
            }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(LocationService())
        .environmentObject(SpeechService())
}
