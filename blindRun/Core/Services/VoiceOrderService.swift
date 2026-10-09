//
//  VoiceOrderService.swift
//  blindRun
//
//  领域 service 层的第六片：语音下单解析。范例是 `AuthService.swift`。
//
//  这一片只有一个方法，收的是全仓**最后一个** Services 目录外的裸 `apiClient` 调用点
//  （`VoiceOrderWizard.parseOrderResponse`）。它不清掉，Phase 2 的 `raw-api-call` 守卫
//  就加不上去 —— 一条永远要写例外的守卫等于没有守卫。
//

import Foundation

// MARK: - Protocol

/// 语音片对外的能力：**整句解析，就这一条**。
///
/// 刻意不给 `VoiceOrderEndpoint` 里另外两条（`resolveAddress` / `parseSlot`）摆方法：
/// 它们在本仓库没有任何生产调用点。`AuthServing` 那条「每个方法都必须有生产调用点」
/// 同样适用 —— service 层的价值是收敛调用点，不是先摆一层空壳。
///
/// 错误一律 `throws` 抛出去，**这一层不吞**。向导那边要靠错误分类决定「值不值得让盲人
/// 再说一遍」（`parseIsUnavailable`：端点没部署时重说多少遍都不会变好），吞在这里等于
/// 把那个判断毁掉。
protocol VoiceOrderServing: Sendable {
    func parseOrder(_ request: ParseVoiceOrderRequest) async throws -> ParseVoiceOrderResponse
}

// MARK: - Implementation

/// 唯一的生产实现。**只做两件事**：选端点、转参数。判定属于调用方。
struct VoiceOrderService: VoiceOrderServing {
    let transport: any APIClientProtocol

    init(transport: any APIClientProtocol) {
        self.transport = transport
    }

    /// 这一片**不另起 `VoiceEndpoint` 枚举**：路径字面量早就在
    /// `VoiceOrderEndpoint`（`Core/Models/VoiceOrderModels.swift:12`），
    /// 而 `MockAPIClient` 的路由也认那一份。再抄一条进新枚举就是第二个源，
    /// 迟早有一边漂 —— 与 `SafetyService` 直接复用 `IntroCallEndpoint` 同一条理由。
    ///
    /// 超时**不在这一层**：`VoiceOrderWizard.withParseTimeout` 守的是「盲人听不到任何提示」
    /// 这件事，属于向导的播报语义，挪进 service 会让它对别的调用方悄悄生效。
    func parseOrder(_ request: ParseVoiceOrderRequest) async throws -> ParseVoiceOrderResponse {
        try await transport.send(
            EndpointRequest(.post, VoiceOrderEndpoint.parseOrder),
            body: request
        )
    }
}

// MARK: - Consent gate

/// 当前账号没有同意「说的话转成文字后交给第三方大模型」，所以没有发出解析请求。
enum VoiceOrderConsentError: Error, Equatable {
    case notGranted
}

/// `VoiceOrderServing` 的闸门：**没有同意就不发 `/api/orders/voice/parse`**（#374，审核指南 5.1.2(i)）。
///
/// 做成装饰器而不是只在视图里拦，是因为合规约束要守在**唯一的出口**上：视图层今天只有
/// `BlindBookingView.startVoiceWizard()` 一个入口，明天再多一个入口就绕过去了，而且「没发请求」
/// 在视图里没法单测。这里每次调用都现读同意状态，换账号立刻生效。
///
/// 向导把解析错误当「没听懂」吞掉（`VoiceOrderWizard.handle`），所以这里抛错**不给用户任何交代**。
/// 用户可见的出路由 `BlindBookingView` 在启动向导前先问同意来给；这一层是兜底，正常路径走不到。
struct ConsentGatedVoiceOrderService: VoiceOrderServing {
    let base: any VoiceOrderServing
    /// 在主线程现读 —— 同意记录在 `AppStatePersistence` 里，它不是 `Sendable`。
    let isConsentGranted: @MainActor @Sendable () -> Bool

    func parseOrder(_ request: ParseVoiceOrderRequest) async throws -> ParseVoiceOrderResponse {
        guard await isConsentGranted() else { throw VoiceOrderConsentError.notGranted }
        return try await base.parseOrder(request)
    }
}
