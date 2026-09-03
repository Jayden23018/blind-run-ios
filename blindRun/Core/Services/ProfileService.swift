//
//  ProfileService.swift
//  blindRun
//
//  领域 service 层的第二片：档案·实名·资质。范例仍是 `AuthService.swift`。
//

import Foundation

// MARK: - Endpoints

/// 档案片用到的全部端点。规矩同 `AuthEndpoint`：
/// **一个 case 一条完整字面量路径**，不许拼接 —— `scripts/validate-spec-coverage.mjs`
/// 只认字符串字面量，拼出来的路径它扫不到，这条端点就再也不会跟后端契约对撞。
///
/// 「档案」的边界按**数据归属**划：谁是这份资料的主人。
/// 盲人资料 / 紧急联系人 / 志愿者资料 / 资质证书 / 注册流程，都是「这个用户是谁」的一部分。
/// 订单、激励、求助不在内，各自成片。
///
/// `blindProfile` 与 `updateBlindProfile` 路径相同、方法不同，所以是两个 case ——
/// 端点的身份是「方法 + 路径」，不是路径。
enum ProfileEndpoint {
    // 盲人资料与实名
    case blindProfile
    case updateBlindProfile
    case verifyBlindIdentity

    // 紧急联系人
    case emergencyContacts(userId: Int64)
    case createEmergencyContact(userId: Int64)
    case updateEmergencyContact(userId: Int64, contactId: Int64)
    case deleteEmergencyContact(userId: Int64, contactId: Int64)
    case setPrimaryEmergencyContact(userId: Int64, contactId: Int64)

    // 志愿者资料
    case volunteerProfile
    case updateVolunteerProfile
    case approveMockVerification

    // 志愿者资质证书
    case volunteerVerificationStatus
    case uploadVolunteerCertificate

    // 志愿者注册流程
    case volunteerRegistrationStatus
    case submitVolunteerBasicInfo
    case initFaceVerify
    case faceVerifyResult

    var request: EndpointRequest {
        switch self {
        case .blindProfile:
            return EndpointRequest(.get, "/api/blind/profile")
        case .updateBlindProfile:
            return EndpointRequest(.put, "/api/blind/profile")
        case .verifyBlindIdentity:
            return EndpointRequest(.post, "/api/blind/verify-identity")
        case .emergencyContacts(let userId):
            return EndpointRequest(.get, "/api/users/\(userId)/emergency-contacts")
        case .createEmergencyContact(let userId):
            return EndpointRequest(.post, "/api/users/\(userId)/emergency-contacts")
        case .updateEmergencyContact(let userId, let contactId):
            return EndpointRequest(.put, "/api/users/\(userId)/emergency-contacts/\(contactId)")
        case .deleteEmergencyContact(let userId, let contactId):
            return EndpointRequest(.delete, "/api/users/\(userId)/emergency-contacts/\(contactId)")
        case .setPrimaryEmergencyContact(let userId, let contactId):
            return EndpointRequest(.put, "/api/users/\(userId)/emergency-contacts/\(contactId)/set-primary")
        case .volunteerProfile:
            return EndpointRequest(.get, "/api/volunteer/profile")
        case .updateVolunteerProfile:
            return EndpointRequest(.put, "/api/volunteer/profile")
        case .approveMockVerification:
            return EndpointRequest(.post, "/api/volunteer/mock-verification/approve")
        case .volunteerVerificationStatus:
            return EndpointRequest(.get, "/api/volunteer/verification/status")
        case .uploadVolunteerCertificate:
            return EndpointRequest(.post, "/api/volunteer/verification")
        case .volunteerRegistrationStatus:
            return EndpointRequest(.get, "/api/volunteer/registration/status")
        case .submitVolunteerBasicInfo:
            return EndpointRequest(.post, "/api/volunteer/registration/step1")
        case .initFaceVerify:
            return EndpointRequest(.post, "/api/volunteer/registration/step3/face-verify/init")
        case .faceVerifyResult:
            return EndpointRequest(.post, "/api/volunteer/registration/step3/face-verify/result")
        }
    }
}

// MARK: - Protocol

/// 档案片对外的全部能力。
///
/// **每个方法都必须有生产调用点**（17 个方法 / 23 个调用点：ContentView 4 ·
/// EmergencyContactsView 5 · BlindIdentityVerificationView 2 · ProfileModule 1 ·
/// VolunteerModule 2 · VolunteerCertificateUploadView 2 · VolunteerRegistrationFlowView 7）。
/// 没有调用点的方法当场删 —— service 层的价值是收敛调用点，不是先摆一层空壳。
///
/// 错误一律 `throws` 抛出去，**这一层不吞**。谁负责渲染谁 catch：
/// 吞在 service 里的错误在 UI 上表现成「点了没反应」，对盲人端就是事故。
///
/// 隐私红线不在这一层实施（这层只选端点、转参数），但它决定了这些端点的返回值怎么渲染：
/// 联系人手机号上屏与进 `accessibilityLabel` 一律走 `EmergencyContactResponse.maskPhone`，
/// 全号只进 `tel:`（VoiceOver 是外放的，念全号等于把号码广播给周围所有人）。见 AGENTS.md §8。
protocol ProfileServing: Sendable {
    // 盲人资料与实名
    func blindProfile() async throws -> BlindProfileResponse
    func updateBlindProfile(_ request: BlindProfileUpdateRequest) async throws -> BlindProfileResponse
    func verifyBlindIdentity(_ request: BlindVerifyRequest) async throws -> BlindVerifySubmitResponse

    // 紧急联系人
    func emergencyContacts(userId: Int64) async throws -> [EmergencyContactResponse]
    func createEmergencyContact(userId: Int64, _ request: EmergencyContactRequest) async throws -> EmergencyContactResponse
    func updateEmergencyContact(
        userId: Int64,
        contactId: Int64,
        _ request: EmergencyContactRequest
    ) async throws -> EmergencyContactResponse
    func deleteEmergencyContact(userId: Int64, contactId: Int64) async throws
    func setPrimaryEmergencyContact(userId: Int64, contactId: Int64) async throws

    // 志愿者资料
    func volunteerProfile() async throws -> VolunteerProfileResponse
    func updateVolunteerProfile(_ request: VolunteerProfileUpdateRequest) async throws -> VolunteerProfileResponse
    func approveMockVerification() async throws -> VolunteerProfileResponse

    // 志愿者资质证书
    func volunteerVerificationStatus() async throws -> VolunteerVerificationStatusResponse
    func uploadVolunteerCertificate(_ file: MultipartFile) async throws -> VolunteerVerificationStatusResponse

    // 志愿者注册流程
    func volunteerRegistrationStatus() async throws -> VolunteerRegistrationStatus
    func submitVolunteerBasicInfo(_ request: BasicInfoRequest) async throws
    func initFaceVerify(_ request: FaceVerifyInitRequest) async throws -> FaceVerifyInitResponse
    func faceVerifyResult(_ request: FaceVerifyResultRequest) async throws -> FaceVerifyResponse
}

// MARK: - Implementation

/// 唯一的生产实现。**只做两件事**：选端点、转参数。
///
/// 不做重试、不做缓存、不做错误分类，也**不写 `AppState`** —— 写状态是调用方的事。
/// 这一层多一个判断，就多一处「Mock 和真实后端行为不一样」的来源。
struct ProfileService: ProfileServing {
    let transport: any APIClientProtocol

    init(transport: any APIClientProtocol) {
        self.transport = transport
    }

    func blindProfile() async throws -> BlindProfileResponse {
        try await transport.send(ProfileEndpoint.blindProfile.request)
    }

    func updateBlindProfile(_ request: BlindProfileUpdateRequest) async throws -> BlindProfileResponse {
        try await transport.send(ProfileEndpoint.updateBlindProfile.request, body: request)
    }

    func verifyBlindIdentity(_ request: BlindVerifyRequest) async throws -> BlindVerifySubmitResponse {
        try await transport.send(ProfileEndpoint.verifyBlindIdentity.request, body: request)
    }

    func emergencyContacts(userId: Int64) async throws -> [EmergencyContactResponse] {
        try await transport.send(ProfileEndpoint.emergencyContacts(userId: userId).request)
    }

    func createEmergencyContact(
        userId: Int64,
        _ request: EmergencyContactRequest
    ) async throws -> EmergencyContactResponse {
        try await transport.send(
            ProfileEndpoint.createEmergencyContact(userId: userId).request,
            body: request
        )
    }

    func updateEmergencyContact(
        userId: Int64,
        contactId: Int64,
        _ request: EmergencyContactRequest
    ) async throws -> EmergencyContactResponse {
        try await transport.send(
            ProfileEndpoint.updateEmergencyContact(userId: userId, contactId: contactId).request,
            body: request
        )
    }

    func deleteEmergencyContact(userId: Int64, contactId: Int64) async throws {
        let _: EmptyResponse = try await transport.send(
            ProfileEndpoint.deleteEmergencyContact(userId: userId, contactId: contactId).request
        )
    }

    func setPrimaryEmergencyContact(userId: Int64, contactId: Int64) async throws {
        let _: EmptyResponse = try await transport.send(
            ProfileEndpoint.setPrimaryEmergencyContact(userId: userId, contactId: contactId).request
        )
    }

    func volunteerProfile() async throws -> VolunteerProfileResponse {
        try await transport.send(ProfileEndpoint.volunteerProfile.request)
    }

    func updateVolunteerProfile(_ request: VolunteerProfileUpdateRequest) async throws -> VolunteerProfileResponse {
        try await transport.send(ProfileEndpoint.updateVolunteerProfile.request, body: request)
    }

    func approveMockVerification() async throws -> VolunteerProfileResponse {
        try await transport.send(ProfileEndpoint.approveMockVerification.request)
    }

    func volunteerVerificationStatus() async throws -> VolunteerVerificationStatusResponse {
        try await transport.send(ProfileEndpoint.volunteerVerificationStatus.request)
    }

    /// 全仓库唯一一条 multipart 上传，也是 `send(_:files:)` 存在的理由。
    func uploadVolunteerCertificate(_ file: MultipartFile) async throws -> VolunteerVerificationStatusResponse {
        try await transport.send(
            ProfileEndpoint.uploadVolunteerCertificate.request,
            files: [file]
        )
    }

    func volunteerRegistrationStatus() async throws -> VolunteerRegistrationStatus {
        try await transport.send(ProfileEndpoint.volunteerRegistrationStatus.request)
    }

    func submitVolunteerBasicInfo(_ request: BasicInfoRequest) async throws {
        let _: EmptyResponse = try await transport.send(
            ProfileEndpoint.submitVolunteerBasicInfo.request,
            body: request
        )
    }

    func initFaceVerify(_ request: FaceVerifyInitRequest) async throws -> FaceVerifyInitResponse {
        try await transport.send(ProfileEndpoint.initFaceVerify.request, body: request)
    }

    func faceVerifyResult(_ request: FaceVerifyResultRequest) async throws -> FaceVerifyResponse {
        try await transport.send(ProfileEndpoint.faceVerifyResult.request, body: request)
    }
}
