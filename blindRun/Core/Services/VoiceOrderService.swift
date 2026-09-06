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
