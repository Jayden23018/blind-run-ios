import SwiftUI

/// 挂在根视图最外层：强制更新页要盖住隐私同意页、登录页和所有路由。
///
/// 背后的界面退出读屏树要两层一起挂（记忆 `hide-uikit-hosted-tree-from-accessibility`）。
/// 它还得反复写：冷启动时这一页比标签栏容器先出现，只写一次藏不住后来挂上的容器（真机用例
/// `testAppUpdateGateCoversHomeAndOnlyOffersLocalDial` 红过）。
/// 判定在 `AppUpdatePolicy`：这一层只负责触发检查和渲染结果。
struct AppUpdateGateModifier: ViewModifier {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @StateObject private var gate = AppUpdateGate()
    @State private var hiderRevision = 0

    private static let hiderReapplyInterval: UInt64 = 500_000_000

    /// 恢复结束、登录、换角色时都要重判：判定读的订单归属取决于这两样。
    private struct RefreshKey: Equatable {
        let restoration: SessionRestorationState
        let role: UserRole?
    }

    private var requiredTarget: AppUpdateTarget? {
        guard case .requiredGate(let target) = gate.presentation else { return nil }
        return target
    }

    private var optionalTarget: AppUpdateTarget? {
        guard appState.didAcceptPrivacyConsent, case .optionalPrompt(let target) = gate.presentation else { return nil }
        return target
    }

    private var isShowingOptionalPrompt: Binding<Bool> {
        Binding(
            get: { optionalTarget != nil },
            set: { if !$0 { gate.dismissOptionalPrompt() } }
        )
    }

    func body(content: Content) -> some View {
        content
            .accessibilityHidden(requiredTarget != nil)
            .background(HostedContainersAccessibilityHider(isHidden: requiredTarget != nil, revision: hiderRevision))
            .overlay {
                if let requiredTarget {
                    AppUpdateRequiredView(target: requiredTarget, currentVersion: gate.currentVersion ?? "")
                        .accessibilityAddTraits(.isModal)
                }
            }
            .alert(AppUpdateCopy.optionalTitle, isPresented: isShowingOptionalPrompt, presenting: optionalTarget) { target in
                Button(AppUpdateCopy.updateButtonTitle) { openOptionalUpdate(target.url) }
                Button(AppUpdateCopy.optionalLaterButtonTitle, role: .cancel) {}
            } message: { target in
                Text(AppUpdateCopy.optionalMessage(targetVersion: target.version))
            }
            // ponytail: 定时重写而不是追踪每一处树变化。这一页只在版本过低时出现，且没有列表要滚动，
            // 半秒一次的代价可以忽略。要省的话改成观察容器的子控制器变化。
            .task(id: requiredTarget != nil) {
                guard requiredTarget != nil else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: Self.hiderReapplyInterval)
                    hiderRevision &+= 1
                }
            }
            .task(id: RefreshKey(restoration: appState.sessionRestorationState, role: appState.activeRole)) {
                await gate.refresh(from: appState)
            }
            .onChange(of: scenePhase) { phase in
                guard phase == .active else { return }
                Task { await gate.refresh(from: appState) }
            }
    }

    private func openOptionalUpdate(_ url: URL) {
        openURL(url) { accepted in
            if !accepted { speechService.speak(text: AppUpdateCopy.openFailed) }
        }
    }
}

/// 强制更新页。一屏一个主任务：更新。紧急呼叫只拨号，绝不调 `/api/emergency/trigger`（`AGENTS.md` §6）。
private struct AppUpdateRequiredView: View {
    let target: AppUpdateTarget
    let currentVersion: String

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @Environment(\.openURL) private var openURL
    @State private var showCallOptions = false
    @State private var didFailToOpen = false

    private var reason: String {
        AppUpdateCopy.requiredReason(currentVersion: currentVersion, targetVersion: target.version)
    }

    /// 只有跑者端的拨号单列联系人，与 `VolunteerOrderSOSMode` 那一侧一致。
    private var primaryContact: EmergencyContactResponse? {
        appState.activeRole == .blind ? EmergencyContactResponse.singlePrimary(in: appState.emergencyContacts) : nil
    }

    private var callContext: EmergencyCallContext {
        .updateRequired(role: appState.activeRole)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                Text(AppUpdateCopy.requiredTitle)
                    .font(AppFonts.largeTitle())
                    .foregroundColor(AppColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(reason)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                if didFailToOpen {
                    Text(AppUpdateCopy.openFailed)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.destructive)
                }
                Button(AppUpdateCopy.updateButtonTitle, action: openUpdate)
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityHint(AppUpdateCopy.updateAccessibilityHint)
                    .accessibilityIdentifier("appUpdateRequiredUpdateButton")
                Button(EmergencySafetyCopy.homeCallTitle) { showCallOptions = true }
                    .buttonStyle(PrimaryButtonStyle(isDestructive: true))
                    .accessibilityLabel(EmergencySafetyCopy.homeCallAccessibilityLabel)
                    .accessibilityHint(callContext.accessibilityHint)
                    .accessibilityIdentifier("appUpdateRequiredCallButton")
                Button(AppUpdateCopy.repeatButtonTitle) { speakReason(priority: .onDemand) }
                    .buttonStyle(OutlineSecondaryButtonStyle())
                    .accessibilityHint(AppUpdateCopy.repeatAccessibilityHint)
                    .accessibilityIdentifier("appUpdateRequiredRepeatButton")
            }
            .padding(AppSpacing.large)
            .readableContentColumn()
        }
        .background(AppColors.background.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("appUpdateRequiredGate")
        // 背后的标签栏容器退出了读屏树，它的全屏手势跟着失效。求助的手势在这一页要继续能用。
        .accessibilityAction(.magicTap) { showCallOptions = true }
        .emergencyCallOptionsDialog(
            isPresented: $showCallOptions,
            context: callContext,
            primaryContact: primaryContact
        )
        // 走警示档：背后的首页这时可能刚加载完，默认档的进入播报会切断这一句（`AnnouncementQueue`）。
        .task(id: target.version) { speakReason(priority: .alert) }
    }

    private func speakReason(priority: AnnouncementPriority) {
        let opening = "\(AppUpdateCopy.requiredTitle)。\(reason)"
        speechService.speak(text: didFailToOpen ? "\(opening)\(AppUpdateCopy.openFailed)" : opening, priority: priority)
    }

    private func openUpdate() {
        openURL(target.url) { accepted in
            guard !accepted else { return }
            didFailToOpen = true
            speechService.speak(text: AppUpdateCopy.openFailed)
        }
    }
}
