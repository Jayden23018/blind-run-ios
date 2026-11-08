import Combine
import Foundation
import SwiftUI

extension AppState {
    /// 根据当前环境返回对应的 API Client，外面包着会话失效的统一处理（`SessionAwareAPIClient`，#872）。
    ///
    /// 需要登录的请求最终 401 时，会话在这里处理（跑步中暂缓，否则登出），调用方不用记得去调。
    /// 单测注入的 `apiClientOverride` 一样包：测的就是生产路径。
    var apiClient: any APIClientProtocol {
        sessionAware(sessionUnawareAPIClient)
    }

    /// 页面自带测试注入口（`apiClient:` 构造参数）时用：注入的客户端同样包上会话处理，没注入就是 `apiClient`。
    /// 不包的话，页面在单测里收到 401 只会停下、不登出，测不到生产路径（#873）。
    func apiClient(overriddenBy override: (any APIClientProtocol)?) -> any APIClientProtocol {
        override.map(sessionAware) ?? apiClient
    }

    private func sessionAware(_ client: any APIClientProtocol) -> any APIClientProtocol {
        SessionAwareAPIClient.wrapping(client) { [weak self] in
            self?.handleSessionEndedByNetworkLayer()
        }
    }

    /// 没包会话处理的客户端。**只给登出**（登出的 401 按登出规则处理，不能再提示一次登录已过期）
    /// 和要认出具体实现的测试钩子用（`as? MockAPIClient`）。别的请求一律走 `apiClient`。
    var sessionUnawareAPIClient: any APIClientProtocol {
        if let apiClientOverride { return SessionAwareAPIClient.unwrapped(apiClientOverride) }
        switch currentEnvironment {
        case .mock where AppBuildChannel.current == .development:
            return mockAPIClient
        case .mock:
            return DisabledAPIClient()
        case .demoCloud:
            guard AppBuildChannel.current.allows(currentEnvironment) else {
                return DisabledAPIClient()
            }
            guard let baseURL = currentEnvironment.baseURL else {
                return DisabledAPIClient()
            }
            return URLSessionAPIClient(
                baseURL: baseURL,
                tokenProvider: { [weak self] in self?.accessToken },
                sessionRenewer: tokenRefresher
            )
        }
    }

    /// 认证·会话片的领域 service。
    ///
    /// 与 `apiClient` 一样**每次取都新建**：环境可以在运行时切换（Mock / Demo Cloud），
    /// 缓存一个实例会让切换后的调用还打在旧 transport 上。
    var auth: any AuthServing {
        if let authOverride { return authOverride }
        return AuthService(transport: apiClient)
    }

    /// 激励片的领域 service。每次取都新建，理由同 `auth`。
    var incentive: any IncentiveServing {
        if let incentiveOverride { return incentiveOverride }
        return IncentiveService(transport: apiClient)
    }

    /// 档案·实名·资质片的领域 service。同样**每次取都新建**，理由同上。
    ///
    /// 这里没有 `AppState(profile:)` 注入口 —— 本片现有用例全部通过 `AppState(apiClient:)`
    /// 打桩，桩实现的是 `APIClientProtocol`，`ProfileService` 照样架在它上面。
    /// 真需要一个 `FakeProfileService` 时再照 `auth` 加，不先摆一个没人用的入口。
    var profile: any ProfileServing {
        ProfileService(transport: apiClient)
    }

    /// 跑后运动记录片的领域 service。每次取都新建，理由同 `auth`；注入口等真需要 fake 时再加，理由同 `profile`。
    var runRecord: any RunRecordServing {
        RunRecordService(transport: apiClient)
    }

    /// 求助·通话磨合·轨迹片的领域 service。每次取都新建，理由同 `auth`。
    var safety: any SafetyServing {
        if let safetyOverride { return safetyOverride }
        return SafetyService(transport: apiClient)
    }

    /// 订单片的领域 service。理由与 `auth` 相同：每次取都新建，不缓存实例。
    var orders: any OrderServing {
        if let ordersOverride { return ordersOverride }
        return OrderService(transport: apiClient)
    }

    /// 志愿者线上培训片的领域 service。每次取都新建，理由同 `auth`。
    ///
    /// 没有注入口，理由同 `profile`：培训的用例都通过 `AppState(apiClient:)` 打桩，
    /// 桩实现的是 `APIClientProtocol`，`TrainingService` 照样架在它上面。
    /// 真需要 `FakeTrainingService` 时再照 `auth` 加，不先摆一个没人用的入口。
    var training: any TrainingServing {
        TrainingService(transport: apiClient)
    }

    /// 语音下单解析片的领域 service。每次取都新建，理由同 `auth`。
    ///
    /// 这里没有注入口，理由同 `profile`：现有用例都通过给 `VoiceOrderWizard.configure`
    /// 传一个架在 `APIClientProtocol` 桩上的 `VoiceOrderService` 打桩，够用。
    /// 真需要 `FakeVoiceOrderService` 时再照 `auth` 加，不先摆一个没人用的入口。
    ///
    /// 外面包了一层同意闸门（`ConsentGatedVoiceOrderService`）：账号没同意把转写文字交给第三方大模型时
    /// 不发 `/parse`。向导拿到的就是这一份，没有绕过它的路。
    var voiceOrder: any VoiceOrderServing {
        ConsentGatedVoiceOrderService(
            base: VoiceOrderService(transport: apiClient),
            isConsentGranted: { [weak self] in self?.hasVoiceOrderConsent ?? false }
        )
    }
}
