//
//  SafetyService.swift
//  blindRun
//
//  领域 service 层的第四片：求助·通话磨合·轨迹。范例是 `AuthService.swift`。
//

import Foundation

// MARK: - Endpoints

/// 本片用到的端点，**接单前通话磨合那四条除外** —— 它们早就写成
/// `IntroCallEndpoint`（`Core/Models/IntroCallModels.swift`）且已被用例逐条钉住，
/// 这里直接用，不再抄一份。同一条路径有两个定义就一定会漂。
///
/// 与 `AuthEndpoint` 同一条硬规矩：**一个 case 一条完整字面量路径**，不许拼接 ——
/// `scripts/validate-spec-coverage.mjs` 只认字符串字面量。
enum SafetyEndpoint {
    case triggerEmergency
    case activeEmergency
    case cancelEmergency(eventId: Int64)
    case volunteerEmergencyResponse(eventId: Int64)
    /// 结束后的轨迹回放。**盲人与志愿者共用**，权限由后端按订单参与方判。
    case orderTrack(orderId: Int64)
    /// 通话磨合期「这一单到底是不是我的」的唯一判据，见 `SafetyServing.matchedOrder`。
    case orderDetail(orderId: Int64)

    var request: EndpointRequest {
        switch self {
        case .triggerEmergency:
            return EndpointRequest(.post, "/api/emergency/trigger")
        case .activeEmergency:
            return EndpointRequest(.get, "/api/emergency/active")
        case .cancelEmergency(let eventId):
            return EndpointRequest(.put, "/api/emergency/\(eventId)/cancel")
        case .volunteerEmergencyResponse(let eventId):
            return EndpointRequest(.put, "/api/emergency/\(eventId)/volunteer-response")
        case .orderTrack(let orderId):
            return EndpointRequest(.get, "/api/orders/\(orderId)/track")
        case .orderDetail(let orderId):
            return EndpointRequest(.get, "/api/orders/\(orderId)")
        }
    }
}

// MARK: - Protocol

/// 求助·通话磨合·轨迹片对外的全部能力。
///
/// 这三块凑在一片，是因为它们围着**同一件事**转：把一次陪跑里的人身安全走完 ——
/// 接单前的通话决定「跟谁跑」，进行中的求助决定「出事怎么办」，结束后的轨迹是这趟跑步
/// 唯一的客观记录。它们和订单状态机是正交的：**求助不是订单状态**（`AGENTS.md` §6），
/// 通话磨合期后端连订单详情都不给志愿者看。
///
/// 与 `AuthServing` 同两条规矩：**每个方法都必须有生产调用点**（当前 8 个，
/// 与迁移前的 8 个 `apiClient.<verb>` 一一对应）；错误一律 `throws` 抛出去，**这一层不吞** ——
/// 吞在这里的错误在 UI 上表现成「点了没反应」，而这一片的每一条失败都必须被盲人**听见**。
protocol SafetyServing: Sendable {
    // 求助（`POST /api/emergency/trigger` 只记事件，不动订单状态）
    func triggerEmergency(_ request: EmergencyTriggerRequest) async throws -> EmergencyTriggerResponse
    func activeEmergency() async throws -> EmergencyActiveEnvelope
    func cancelEmergencyByOwner(eventId: Int64) async throws -> EmergencyCancelResponse
    func acknowledgeEmergencyAsVolunteer(eventId: Int64) async throws -> VolunteerEmergencyAcknowledgement

    // 接单前通话磨合（志愿者侧；盲人侧三个调用点还在 `BlindOrderStatusView` 里直接打，随订单片迁）
    func introCall(orderId: Int64) async throws -> IntroCallView
    func submitIntroCallDecision(orderId: Int64, decision: IntroCallDecision) async throws
    func reportIntroCallUnreachable(orderId: Int64) async throws
    func matchedOrder(orderId: Int64) async throws -> OrderDetailResponse

    // 轨迹
    func orderTrack(orderId: Int64) async throws -> OrderTrackResponse
}

// MARK: - Implementation

/// 唯一的生产实现。**只做两件事**：选端点、转参数。判定属于调用方。
struct SafetyService: SafetyServing {
    let transport: any APIClientProtocol

    init(transport: any APIClientProtocol) {
        self.transport = transport
    }

    func triggerEmergency(_ request: EmergencyTriggerRequest) async throws -> EmergencyTriggerResponse {
        try await transport.send(SafetyEndpoint.triggerEmergency.request, body: request)
    }

    func activeEmergency() async throws -> EmergencyActiveEnvelope {
        try await transport.send(SafetyEndpoint.activeEmergency.request)
    }

    func cancelEmergencyByOwner(eventId: Int64) async throws -> EmergencyCancelResponse {
        try await transport.send(SafetyEndpoint.cancelEmergency(eventId: eventId).request)
    }

    /// 🚨 `action` **刻意不是参数**：志愿者端只有 `NEED_HELP` 这一个动作。
    /// 后端对 `FALSE_ALARM` 一律回 403 `EMERGENCY_VOLUNTEER_CANNOT_DISMISS` ——
    /// 一对一陪跑里志愿者可能就是威胁来源，撤销权只在受助者本人和客服手里（`AGENTS.md` §6）。
    /// 开成参数等于把这条红线交给每个调用点各记一遍。
    func acknowledgeEmergencyAsVolunteer(eventId: Int64) async throws -> VolunteerEmergencyAcknowledgement {
        try await transport.send(
            SafetyEndpoint.volunteerEmergencyResponse(eventId: eventId).request,
            query: ["action": "NEED_HELP"]
        )
    }

    func introCall(orderId: Int64) async throws -> IntroCallView {
        try await transport.send(IntroCallEndpoint.view.request(orderId: orderId))
    }

    func submitIntroCallDecision(orderId: Int64, decision: IntroCallDecision) async throws {
        let _: EmptyResponse = try await transport.send(
            IntroCallEndpoint.decision.request(orderId: orderId),
            body: IntroCallDecisionRequest(decision: decision)
        )
    }

    func reportIntroCallUnreachable(orderId: Int64) async throws {
        let _: EmptyResponse = try await transport.send(
            IntroCallEndpoint.unreachable.request(orderId: orderId)
        )
    }

    /// `GET /api/orders/{id}`，但用途只有一个：**判本轮通话磨合成没成**。
    ///
    /// 成单时后端才写上 `order.volunteer`，而它正是 `getOrder` 的鉴权字段 ——
    /// 读得到 ⇒ 成了，仍然 403 ⇒ 这一单不是我的。通话端点刻意不回对方的表态，
    /// 这是该契约下唯一存在的判据（见 `VolunteerIntroCallViewModel.resolveFinishedRound`）。
    ///
    /// 订单片落地后这条会并进订单 service，这里删掉。
    func matchedOrder(orderId: Int64) async throws -> OrderDetailResponse {
        try await transport.send(SafetyEndpoint.orderDetail(orderId: orderId).request)
    }

    func orderTrack(orderId: Int64) async throws -> OrderTrackResponse {
        try await transport.send(SafetyEndpoint.orderTrack(orderId: orderId).request)
    }
}
