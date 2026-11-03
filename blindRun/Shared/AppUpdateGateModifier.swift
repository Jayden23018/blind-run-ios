import SwiftUI

/// 版本更新弹窗。判定在 `AppUpdatePolicy`，这一层只负责触发检查和弹系统 `.alert`。
///
/// 必须更新的弹窗只有一个按钮。按下后系统把弹窗收起，跳去 App Store；回到 App 时
/// `scenePhase` 变成 `.active` 触发检查，版本仍然过低就再弹一次。
///
/// `@ObservedObject` 自己持有协调器：它挂在 `AppState` 上，嵌套的 ObservableObject 不会经 AppState 重新发布。
struct AppUpdateGateModifier: ViewModifier {
    @ObservedObject var escort: LiveEscortSessionCoordinator
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @StateObject private var gate = AppUpdateGate()
    @State private var didFailToOpen = false

    /// 三样都决定要不要弹。陪跑一结束 `isEscortUnderway` 就翻转，弹窗不用等下次回到前台。
    private struct RefreshKey: Equatable {
        let restoration: SessionRestorationState
        let role: UserRole?
        let isEscortUnderway: Bool
    }

    /// 可关闭的提示等同意隐私之后再弹，必须更新的不等：旧版本用户也可能还没同意过新告知。
    private var presentation: AppUpdatePresentation {
        if case .optionalPrompt = gate.presentation, !appState.didAcceptPrivacyConsent { return .none }
        return gate.presentation
    }

    private var isShowingPrompt: Binding<Bool> {
        Binding(
            get: { presentation != .none },
            set: { if !$0 { gate.promptDidClose() } }
        )
    }

    private var title: String {
        presentation.isRequired ? AppUpdateCopy.requiredTitle : AppUpdateCopy.optionalTitle
    }

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: isShowingPrompt, presenting: presentation.target) { target in
                if !presentation.isRequired {
                    Button(AppUpdateCopy.laterButtonTitle, role: .cancel) {}
                }
                Button(AppUpdateCopy.updateButtonTitle) { openUpdate(target.url) }
            } message: { target in
                Text(message(for: target))
            }
            .task(id: RefreshKey(
                restoration: appState.sessionRestorationState,
                role: appState.activeRole,
                isEscortUnderway: escort.isSessionEligible
            )) {
                await gate.refresh(from: appState)
            }
            .onChange(of: scenePhase) { phase in
                guard phase == .active else { return }
                Task { await gate.refresh(from: appState) }
            }
    }

    private func message(for target: AppUpdateTarget) -> String {
        guard presentation.isRequired else { return AppUpdateCopy.optionalMessage(targetVersion: target.version) }
        return didFailToOpen ? AppUpdateCopy.openFailed : AppUpdateCopy.requiredMessage(targetVersion: target.version)
    }

    /// 打不开时 App 不会离开前台，`scenePhase` 不变，所以要自己重查一次，否则弹窗收起后人就绕过去了。
    private func openUpdate(_ url: URL) {
        didFailToOpen = false
        openURL(url) { accepted in
            guard !accepted else { return }
            didFailToOpen = true
            speechService.speak(text: AppUpdateCopy.openFailed)
            Task { await gate.refresh(from: appState) }
        }
    }
}
