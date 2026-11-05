import Combine
import Foundation
import SwiftUI

extension AppState {
    // MARK: - Legal Links

    /// 拉一次隐私政策 / 用户协议的外链地址。
    ///
    /// **必须 `requiresAuth: false`** —— 后端对该端点 permitAll，App Store 审核员是未登录状态，
    /// 而 5.1.1/5.1.2 要求他们能在应用内找到隐私政策。带鉴权会让未登录时 401 直接失败。
    ///
    /// 失败静默：入口在任何时刻都得是可点且有内容的，回退文案页承担这件事。
    /// 这里冒出一个错误弹窗，反而会把审核员挡在隐私政策之外。
    func loadLegalLinksIfNeeded() async {
        guard !didAttemptLegalLinksLoad else { return }
        didAttemptLegalLinksLoad = true
        do {
            legalLinks = try await auth.legalLinks()
        } catch {
            ClientFlowDiagnostics.record(event: "failed", operation: "legal-links")
        }
    }

    /// 拉一次功能开关（`GET /api/config/features`，需登录、不限角色）。
    ///
    /// 失败静默，但**会在下一次调用时重试**（见 `didLoadFeatureFlags` 的注释）。
    /// 失败时 `featureFlags` 保持 `nil`，消费方据此说一句不做承诺的话。
    func loadFeatureFlagsIfNeeded() async {
        guard !didLoadFeatureFlags, accessToken != nil else { return }
        do {
            featureFlags = try await auth.featureFlags()
            didLoadFeatureFlags = true
        } catch {
            ClientFlowDiagnostics.record(event: "failed", operation: "feature-flags")
        }
    }
}
