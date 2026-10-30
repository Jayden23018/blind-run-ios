import SwiftUI
import UserNotifications

// MARK: - 推送权限：用到时再问（#521）

/// 启动时不再弹系统推送授权（那时还没过首启隐私同意、也没登录）。改在第一个需要推送的时刻问：
/// 盲人有了第一张订单（等匹配、等志愿者到达都靠推送提醒）、陪跑员第一次打开接单开关（邀请靠推送）。
/// 问之前先用一句话（屏幕 + 朗读）说明用途 —— 读屏用户在不知道用途时听到系统弹窗，容易随手拒绝，
/// 之后求助、到达类推送就再也收不到。已经拒绝过的，给去系统设置的入口。
enum PushPermissionCopy {
    static let askTitle = "开启通知"
    static let askButton = "开启通知"
    static let laterButton = "暂不开启"
    static let deniedTitle = "通知已关闭"
    static let settingsButton = "去系统设置打开"

    static func explanation(for role: UserRole) -> String {
        role == .volunteer
            ? "开启通知后，有新的陪跑邀请、订单有变化时，即使没打开助盲跑也会提醒你。接下来系统会问你是否允许通知。"
            : "开启通知后，志愿者接单、到达集合点、订单有变化时，即使没打开助盲跑也会提醒你并念出来。接下来系统会问你是否允许通知。"
    }

    static func denied(for role: UserRole) -> String {
        role == .volunteer
            ? "通知已关闭：新的陪跑邀请和订单变化的提醒会收不到。可以到系统设置里为助盲跑打开通知。"
            : "通知已关闭：志愿者接单、到达和订单变化的提醒会收不到。可以到系统设置里为助盲跑打开通知。"
    }
}

/// 在需要推送的时刻该做什么。抽成纯函数只为可测。每个角色在本机只主动提示一次：拒绝了还反复弹是打扰。
enum PushPermissionPrompt: Equatable {
    /// 还没问过：先说明用途，再请求系统授权。
    case explainThenAsk
    /// 拒绝过：说明后果，给去系统设置的入口（系统授权框不会再弹第二次）。
    case offerSettings

    static func decide(status: UNAuthorizationStatus, alreadyPrompted: Bool) -> PushPermissionPrompt? {
        guard !alreadyPrompted else { return nil }
        switch status {
        case .notDetermined: return .explainThenAsk
        case .denied: return .offerSettings
        case .authorized, .provisional, .ephemeral: return nil
        @unknown default: return nil
        }
    }

    static func promptedKey(for role: UserRole) -> String {
        "pushPermissionPrompted.\(role.rawValue)"
    }

    /// 陪跑员端「第一个需要推送的时刻」：开着接单开关，且派单位置没被「精确位置」拦住（#520）。
    /// 拦住时顶部那条精确位置提示同一拍在念、在弹临时精确位置框：同档播报后到的会切断先到的，两个弹窗也会叠在一起。
    /// 拦住时本来也收不到邀请，等派单位置恢复上报再问通知不晚。
    static func volunteerNeedsPush(isAvailable: Bool, location: LocationService?) -> Bool {
        isAvailable && !VolunteerLocationReporter.isBlockedByPreciseLocation(location)
    }

    /// UI 用例默认不弹，专测这道提示的用例设 `AIDRUN_UI_TEST_FORCE_PUSH_PROMPT=1`。真实安装没有这些环境变量。
    static func isSuppressedForUITests(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment["AIDRUN_UI_TEST_RESET_STATE"] == "1" && environment["AIDRUN_UI_TEST_FORCE_PUSH_PROMPT"] != "1"
    }
}

/// 「已经先说明过用途」的凭证。只有本文件能造（`fileprivate init`），而 `PushNotificationsManager.requestAuthorization`
/// 要它才肯调 —— 于是「启动时直接请求」这种回退在编译期就写不出来（审查 A：此前没有任何检查守着）。
struct PushPermissionExplained {
    fileprivate init() {}
}

/// 打开系统设置里本 App 那一页（通知开关在里面）。不是拨号，不走 `EmergencyDialer`。
enum SystemSettingsLink {
    static func open() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url) // guard:allow raw-open-url
    }
}

private struct AsksForPushPermission: ViewModifier {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    let isNeeded: Bool
    let role: UserRole
    @State private var prompt: PushPermissionPrompt?

    func body(content: Content) -> some View {
        content
            .onAppear { if isNeeded { Task { await evaluate() } } }
            .onChange(of: isNeeded) { needed in if needed { Task { await evaluate() } } }
            .alert(
                prompt == .offerSettings ? PushPermissionCopy.deniedTitle : PushPermissionCopy.askTitle,
                isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } })
            ) {
                if prompt == .offerSettings {
                    Button(PushPermissionCopy.settingsButton) { markPrompted(); SystemSettingsLink.open() }
                } else {
                    Button(PushPermissionCopy.askButton) {
                        markPrompted()
                        Task { _ = await appState.pushNotificationsManager?.requestAuthorization(after: PushPermissionExplained()) }
                    }
                }
                Button(PushPermissionCopy.laterButton, role: .cancel) { markPrompted() }
            } message: {
                Text(message)
            }
    }

    private var message: String {
        prompt == .offerSettings ? PushPermissionCopy.denied(for: role) : PushPermissionCopy.explanation(for: role)
    }

    private var promptedKey: String { PushPermissionPrompt.promptedKey(for: role) }

    private func evaluate() async {
        // UI 用例（进程内 Mock）不弹：应用内 alert 会挡住几十条靠建单 / 开开关进页面的用例，系统弹窗的中断监视器也点不掉它。
        guard !PushPermissionPrompt.isSuppressedForUITests(), prompt == nil, appState.isLoggedIn,
              let push = appState.pushNotificationsManager else { return }
        let status = await push.authorizationStatus()
        // await 回来后重读：两次触发交错时，标记与 `prompt` 都可能已经变了。
        let alreadyPrompted = appState.persistence.object(forKey: promptedKey) as? Bool ?? false
        guard prompt == nil, let next = PushPermissionPrompt.decide(status: status, alreadyPrompted: alreadyPrompted) else { return }
        prompt = next
        // 读屏开着时 alert 本身会被念，不再朗读第二遍（也免得切断刚才那句订单播报）。
        if !UIAccessibility.isVoiceOverRunning { speechService.speak(message) }
    }

    /// 「本机已提示过」只在用户真的看到并关掉提示时记（审查 A）：先记再显示的话，alert 没弹出来（同一宿主上已有别的模态）标记也烧掉了。
    private func markPrompted() {
        appState.persistence.set(true, forKey: promptedKey)
    }
}

/// 盲人端：有了订单（等匹配、等志愿者到达都靠推送提醒）就是「第一个需要推送的时刻」。
/// 订单由首页与订单页交给同行协调器（`updateOwnedOrder`，含 `PENDING_MATCH`）；嵌套的 ObservableObject 不会经 `AppState`
/// 转发变化（记忆 nested-observableobject-does-not-republish），所以这里直接订它的发布者。
private struct AsksBlindForPushPermissionOnFirstOrder: ViewModifier {
    @EnvironmentObject private var appState: AppState
    @State private var hasOrder = false

    func body(content: Content) -> some View {
        content
            .onReceive(appState.liveEscortCoordinator.$activeOrderID) { hasOrder = $0 != nil }
            .asksForPushPermission(when: hasOrder, role: .blind)
    }
}

extension View {
    /// `isNeeded` 第一次为真时（盲人有了订单、陪跑员打开接单开关）按需提示一次。
    func asksForPushPermission(when isNeeded: Bool, role: UserRole) -> some View {
        modifier(AsksForPushPermission(isNeeded: isNeeded, role: role))
    }

    /// 盲人端根容器挂一次。
    func asksBlindForPushPermissionOnFirstOrder() -> some View {
        modifier(AsksBlindForPushPermissionOnFirstOrder())
    }
}

// MARK: - 设置页的「通知」一行

/// 设置页常驻一行：当前通知开没开；拒绝过时给「去系统设置打开」。从系统设置回来时重读。
struct NotificationPermissionRow: View {
    @EnvironmentObject private var appState: AppState
    @State private var status: UNAuthorizationStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("通知：\(statusText)")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if status == .denied {
                // 64pt 写在标签内部（记忆 button-frame-outside-label-does-not-grow-hit-area）。
                Button(action: SystemSettingsLink.open) {
                    Text(PushPermissionCopy.settingsButton)
                        .font(AppFonts.body())
                        .frame(maxWidth: .infinity, minHeight: 64)
                }
                .accessibilityHint("打开系统设置里助盲跑的通知开关")
                .accessibilityIdentifier("notificationPermissionSettingsLink")
            } else if status == .notDetermined {
                // 在说明页点过「暂不开启」的人系统设置里还没有通知开关（从没请求过），出口只能在这里（审查 A）。
                Button {
                    Task {
                        _ = await appState.pushNotificationsManager?.requestAuthorization(after: PushPermissionExplained())
                        await refresh()
                    }
                } label: {
                    Text(PushPermissionCopy.askButton)
                        .font(AppFonts.body())
                        .frame(maxWidth: .infinity, minHeight: 64)
                }
                .accessibilityHint("接单、到达和订单变化时提醒你，接下来系统会问你是否允许")
                .accessibilityIdentifier("notificationPermissionRequestButton")
            }
        }
        .task { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await refresh() }
        }
    }

    private var statusText: String {
        switch status {
        case .authorized, .provisional, .ephemeral: return "已开启"
        case .denied: return "已关闭，订单与邀请的提醒会收不到"
        case .notDetermined: return "还没开启"
        case .none: return "正在读取"
        @unknown default: return "正在读取"
        }
    }

    private func refresh() async {
        status = await appState.pushNotificationsManager?.authorizationStatus()
    }
}
