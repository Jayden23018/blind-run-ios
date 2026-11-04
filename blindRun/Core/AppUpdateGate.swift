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
    /// 必须更新的弹窗期间，陪跑员的接单开关有没有被自动关掉（#668）。要求消失（已更新、让路给陪跑、请求失败不拦）时复位。
    @Published private(set) var dispatchPause: DispatchPause = .idle

    enum DispatchPause: Equatable {
        case idle
        case paused
        case failed
    }

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

    /// 系统弹窗按下任何按钮都会收起。收起的是「稍后」那一种就记下版本，之后同一版本不再提示。
    /// 记录挂在设备上，所以不进 `AppStatePersistenceKeys.all`，换账号不重弹。
    /// 必须更新那一种不记录：回到 App 的下一次 `refresh` 版本仍然过低，就会再弹。
    func promptDidClose() {
        if case .optionalPrompt(let target) = presentation {
            persistence.set(target.version, forKey: AppStatePersistenceKeys.dismissedAppUpdateVersion)
        }
        presentation = .none
        // 关成功的保留：去 App Store 绕一圈回来弹窗再出现，开关仍是关的，那句话仍然是真的。关失败的让下一次弹窗再试一次。
        if dispatchPause == .failed { dispatchPause = .idle }
    }

    func recordDispatchPause(_ result: DispatchPause) {
        dispatchPause = result
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
            dispatchPause = .idle
            return
        }
        presentation = AppUpdatePolicy.presentation(
            verdict: verdict,
            orderPresence: await source.appUpdateOrderPresence(),
            dismissedVersion: persistence.string(forKey: AppStatePersistenceKeys.dismissedAppUpdateVersion)
        )
        if !presentation.isRequired { dispatchPause = .idle }
    }
}
