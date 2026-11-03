import Combine
import Foundation

/// 检查版本要用到的两件事。`AppState` 实现它，单测换成假的。
@MainActor
protocol AppUpdateSource: AnyObject {
    func appVersionRequirements() async throws -> AppVersionResponse
    func appUpdateOrderPresence() async -> AppUpdateOrderPresence
}

/// 启动和回到前台时的版本检查。结果只放内存：缓存上一次的结果会让一次错配置在断网时继续拦人。
@MainActor
final class AppUpdateGate: ObservableObject {
    @Published private(set) var presentation: AppUpdatePresentation = .none

    let currentVersion: String?
    private let persistence: AppStatePersistence
    private let rerun = CoalescedRerun()

    init(
        currentVersion: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
        persistence: AppStatePersistence? = nil
    ) {
        self.currentVersion = currentVersion
        self.persistence = persistence ?? AppStatePersistenceFactory.makeDefault()
    }

    func refresh(from source: some AppUpdateSource) async {
        await rerun.run { [weak self] in await self?.evaluate(source) }
    }

    /// 记下这个版本，之后同一版本不再提示。挂在设备上，所以不进 `AppStatePersistenceKeys.all`，换账号不重弹。
    func dismissOptionalPrompt() {
        guard case .optionalPrompt(let target) = presentation else { return }
        persistence.set(target.version, forKey: AppStatePersistenceKeys.dismissedAppUpdateVersion)
        presentation = .none
    }

    /// 只有版本确实过低时才查订单：绝大多数启动不用多打这几个请求。
    private func evaluate(_ source: some AppUpdateSource) async {
        let requirements: AppVersionResponse?
        do {
            requirements = try await source.appVersionRequirements()
        } catch {
            ClientFlowDiagnostics.record(event: "failed", operation: "app-version")
            requirements = nil
        }
        let verdict = AppUpdatePolicy.verdict(currentVersion: currentVersion, requirements: requirements)
        guard verdict != .upToDate else {
            presentation = .none
            return
        }
        presentation = AppUpdatePolicy.presentation(
            verdict: verdict,
            orderPresence: await source.appUpdateOrderPresence(),
            dismissedVersion: persistence.string(forKey: AppStatePersistenceKeys.dismissedAppUpdateVersion)
        )
    }
}
