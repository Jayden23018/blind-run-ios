//
//  AuthService.swift
//  blindRun
//
//  领域 service 层的第一片：认证·会话。**其余几片照这个文件抄。**
//

import Foundation

// MARK: - Endpoints

/// 认证·会话片用到的全部端点。
///
/// **一个 case 一条完整字面量路径**，不许拼接 —— `scripts/validate-spec-coverage.mjs`
/// 只认字符串字面量，拼出来的路径它扫不到，于是这条端点就再也不会跟后端契约对撞。
/// 带参数的写成插值（`"/api/users/\(userId)"`），脚本会归一成 `{param}`。
///
/// 「会话」的边界按**流程**划，不按端点归属划：`hydrate` 里那三条资料端点
/// （`blindProfile` / `emergencyContacts` / `volunteerProfile` / `volunteerRegistrationStatus`）
/// 是会话恢复的一部分 —— 它们决定用户落在哪个首页。档案片落地后这几条会搬过去，
/// 到时候这里删掉、`AuthServing` 上对应方法一起删。
enum AuthEndpoint {
    case sendVerificationCode
    case verifyCode
    case currentUser
    case logout
    case deleteAccount(userId: Int64)
    case legalLinks
    case missedNotifications
    /// 注销账号前的进行中订单预检。挂在这里是因为它只服务账号注销这一条流程。
    case accountDeletionOrderPreflight
    case blindProfile
    case emergencyContacts(userId: Int64)
    case volunteerProfile
    case volunteerRegistrationStatus
    case registerDeviceToken
    case unregisterDeviceToken

    var request: EndpointRequest {
        switch self {
        case .sendVerificationCode:
            // 未登录时打，必须 requiresAuth: false。
            return EndpointRequest(.post, "/api/auth/send-code", requiresAuth: false)
        case .verifyCode:
            return EndpointRequest(.post, "/api/auth/verify-code", requiresAuth: false)
        case .currentUser:
            return EndpointRequest(.get, "/api/auth/me")
        case .logout:
            return EndpointRequest(.post, "/api/auth/logout")
        case .deleteAccount(let userId):
            return EndpointRequest(.delete, "/api/users/\(userId)")
        case .legalLinks:
            // **必须 requiresAuth: false** —— 后端 permitAll，App Store 审核员是未登录状态。
            return EndpointRequest(.get, "/api/misc/legal-links", requiresAuth: false)
        case .missedNotifications:
            return EndpointRequest(.get, "/api/notifications/since")
        case .accountDeletionOrderPreflight:
            return EndpointRequest(.get, "/api/orders/mine")
        case .blindProfile:
            return EndpointRequest(.get, "/api/blind/profile")
        case .emergencyContacts(let userId):
            return EndpointRequest(.get, "/api/users/\(userId)/emergency-contacts")
        case .volunteerProfile:
            return EndpointRequest(.get, "/api/volunteer/profile")
        case .volunteerRegistrationStatus:
            return EndpointRequest(.get, "/api/volunteer/registration/status")
        case .registerDeviceToken:
            return EndpointRequest(.post, "/api/devices/apns")
        case .unregisterDeviceToken:
            return EndpointRequest(.delete, "/api/devices/apns")
        }
    }
}

// MARK: - Protocol

/// 认证·会话片对外的全部能力。
///
/// **每个方法都必须有生产调用点**（当前 14 个，与迁移前的 14 个 `apiClient.<verb>` 一一对应）。
/// 没有调用点的方法当场删 —— service 层的价值是收敛调用点，不是先摆一层空壳。
///
/// 错误一律 `throws` 抛出去，**这一层不吞**。谁负责渲染谁 catch：
/// 吞在 service 里的错误在 UI 上表现成「点了没反应」，对盲人端就是事故。
protocol AuthServing: Sendable {
    // 登录
    func sendVerificationCode(phone: String) async throws -> SendCodeResponse
    func verifyCode(phone: String, code: String) async throws -> LoginResponse

    // 会话
    func currentUser() async throws -> CurrentUserResponse
    func logout() async throws -> LogoutResponse
    func deleteAccount(userId: Int64) async throws -> DeleteAccountResponse
    func legalLinks() async throws -> LegalLinksResponse
    func missedNotifications(after: String) async throws -> [MissedNotificationResponse]
    func accountDeletionOrderPreflight() async throws -> PagedOrderResponse

    // 会话恢复时的资料水合
    func blindProfile() async throws -> BlindProfileResponse
    func emergencyContacts(userId: Int64) async throws -> [EmergencyContactResponse]
    func volunteerProfile() async throws -> VolunteerProfileResponse
    func volunteerRegistrationStatus() async throws -> VolunteerRegistrationStatus

    // 设备令牌
    func registerDeviceToken(_ token: String) async throws
    func unregisterDeviceToken(_ token: String) async throws
}

// MARK: - Implementation

/// 唯一的生产实现。**只做两件事**：选端点、转参数。
///
/// 不做重试、不做缓存、不做错误分类 —— 那些属于调用方或 `APIClient`。
/// 这一层多一个判断，就多一处「Mock 和真实后端行为不一样」的来源。
struct AuthService: AuthServing {
    let transport: any APIClientProtocol

    init(transport: any APIClientProtocol) {
        self.transport = transport
    }

    func sendVerificationCode(phone: String) async throws -> SendCodeResponse {
        try await transport.send(
            AuthEndpoint.sendVerificationCode.request,
            body: SendCodeRequest(phone: phone)
        )
    }

    func verifyCode(phone: String, code: String) async throws -> LoginResponse {
        try await transport.send(
            AuthEndpoint.verifyCode.request,
            body: VerifyCodeRequest(phone: phone, code: code)
        )
    }

    func currentUser() async throws -> CurrentUserResponse {
        try await transport.send(AuthEndpoint.currentUser.request)
    }

    func logout() async throws -> LogoutResponse {
        try await transport.send(AuthEndpoint.logout.request)
    }

    func deleteAccount(userId: Int64) async throws -> DeleteAccountResponse {
        try await transport.send(AuthEndpoint.deleteAccount(userId: userId).request)
    }

    func legalLinks() async throws -> LegalLinksResponse {
        try await transport.send(AuthEndpoint.legalLinks.request)
    }

    func missedNotifications(after: String) async throws -> [MissedNotificationResponse] {
        try await transport.send(
            AuthEndpoint.missedNotifications.request,
            query: ["after": after]
        )
    }

    func accountDeletionOrderPreflight() async throws -> PagedOrderResponse {
        try await transport.send(
            AuthEndpoint.accountDeletionOrderPreflight.request,
            query: ["page": "0", "size": "100"]
        )
    }

    func blindProfile() async throws -> BlindProfileResponse {
        try await transport.send(AuthEndpoint.blindProfile.request)
    }

    func emergencyContacts(userId: Int64) async throws -> [EmergencyContactResponse] {
        try await transport.send(AuthEndpoint.emergencyContacts(userId: userId).request)
    }

    func volunteerProfile() async throws -> VolunteerProfileResponse {
        try await transport.send(AuthEndpoint.volunteerProfile.request)
    }

    func volunteerRegistrationStatus() async throws -> VolunteerRegistrationStatus {
        try await transport.send(AuthEndpoint.volunteerRegistrationStatus.request)
    }

    func registerDeviceToken(_ token: String) async throws {
        let _: EmptyResponse = try await transport.send(
            AuthEndpoint.registerDeviceToken.request,
            body: ApnsTokenRequest(deviceToken: token)
        )
    }

    /// `DELETE` **带 body** —— `APIClientProtocol.delete(_:)` 便捷式没有 body 参数，
    /// 这一条正是 `send(_:body:)` 存在的理由。
    func unregisterDeviceToken(_ token: String) async throws {
        let _: EmptyResponse = try await transport.send(
            AuthEndpoint.unregisterDeviceToken.request,
            body: ApnsTokenRequest(deviceToken: token)
        )
    }
}
