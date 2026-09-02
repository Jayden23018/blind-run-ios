import XCTest
@testable import blindRun

/// 档案片的 service 层。这里只管一件事：**每个方法打的是不是它自己那一条端点**。
///
/// 路径字面量本身由 `scripts/validate-spec-coverage.mjs` 对着后端契约撞，
/// 但那个脚本看不出 `updateBlindProfile()` 被写成了 `GET /api/blind/profile` ——
/// 17 条端点里大量共享路径或前缀（`/api/blind/profile` 一条路径两个方法、
/// 紧急联系人四条只差尾巴、注册流程三条只差最后一段），复制粘贴改漏一处不会有任何编译错误。
///
/// 失败传播不在这里测：本片的错误处理全在各自的 ViewModel 用例里（`EmergencyContactsViewModelTests`
/// / `BlindIdentityVerificationViewModelTests` / `blindRunTests` 的注册流程组），
/// 它们打桩的是 `APIClientProtocol`，`ProfileService` 迁移后照样架在那些桩上。
final class ProfileServiceTests: XCTestCase {

    /// 一次跑完 `ProfileServing` 的全部 17 个方法，逐条比对实际发出的 `方法 + 路径`。
    ///
    /// 用一条 trace 而不是 17 个用例：端点映射错的形态永远是「打到了别人那条」，
    /// 整条序列一起比才看得出串了；拆成 17 个用例只会让每次加端点都要抄一遍样板。
    func testEveryMethodHitsItsOwnEndpoint() async throws {
        let transport = RecordingTransport()
        let service = ProfileService(transport: transport)

        transport.enqueue(BlindProfileResponse())
        _ = try await service.blindProfile()

        transport.enqueue(BlindProfileResponse())
        _ = try await service.updateBlindProfile(
            BlindProfileUpdateRequest(
                name: "小明",
                runningPace: nil,
                specialNeeds: nil,
                visionLevel: nil,
                hasGuideDog: nil,
                tetherPreference: nil,
                chatPreference: nil,
                defaultPace: nil
            )
        )

        transport.enqueue(BlindVerifySubmitResponse())
        _ = try await service.verifyBlindIdentity(
            BlindVerifyRequest(idCardName: "小明", idCardNumber: "11010119900307721X")
        )

        let contactRequest = EmergencyContactRequest(
            name: "小红",
            phone: "13800138000",
            relationship: "家人",
            isPrimary: true
        )
        let contact = EmergencyContactResponse(
            id: 7,
            name: "小红",
            phone: "13800138000",
            relationship: "家人",
            isPrimary: true
        )

        transport.enqueue([contact])
        _ = try await service.emergencyContacts(userId: 42)

        transport.enqueue(contact)
        _ = try await service.createEmergencyContact(userId: 42, contactRequest)

        transport.enqueue(contact)
        _ = try await service.updateEmergencyContact(userId: 42, contactId: 7, contactRequest)

        transport.enqueue(EmptyResponse())
        try await service.deleteEmergencyContact(userId: 42, contactId: 7)

        transport.enqueue(EmptyResponse())
        try await service.setPrimaryEmergencyContact(userId: 42, contactId: 7)

        transport.enqueue(VolunteerProfileResponse())
        _ = try await service.volunteerProfile()

        transport.enqueue(VolunteerProfileResponse())
        _ = try await service.updateVolunteerProfile(VolunteerProfileUpdateRequest(name: "小明"))

        transport.enqueue(VolunteerProfileResponse())
        _ = try await service.approveMockVerification()

        transport.enqueue(VolunteerVerificationStatusResponse())
        _ = try await service.volunteerVerificationStatus()

        transport.enqueue(VolunteerVerificationStatusResponse())
        _ = try await service.uploadVolunteerCertificate(
            MultipartFile(fieldName: "file", fileName: "cert.jpg", mimeType: "image/jpeg", data: Data([0xFF]))
        )

        transport.enqueue(VolunteerRegistrationStatus())
        _ = try await service.volunteerRegistrationStatus()

        transport.enqueue(EmptyResponse())
        try await service.submitVolunteerBasicInfo(
            BasicInfoRequest(
                name: "小明",
                phone: "13800138000",
                idCardName: "小明",
                idCardNumber: "11010119900307721X",
                runningExperience: nil,
                hasGuidedBefore: nil,
                emergencyExperience: nil
            )
        )

        transport.enqueue(FaceVerifyInitResponse(certifyId: "c1", status: "PENDING", message: nil))
        _ = try await service.initFaceVerify(FaceVerifyInitRequest(metaInfo: "{}"))

        transport.enqueue(FaceVerifyResponse(passed: true, status: "PASSED", message: nil))
        _ = try await service.faceVerifyResult(FaceVerifyResultRequest(certifyId: "c1"))

        XCTAssertEqual(transport.trace, [
            "GET /api/blind/profile",
            "PUT /api/blind/profile",
            "POST /api/blind/verify-identity",
            "GET /api/users/42/emergency-contacts",
            "POST /api/users/42/emergency-contacts",
            "PUT /api/users/42/emergency-contacts/7",
            "DELETE /api/users/42/emergency-contacts/7",
            "PUT /api/users/42/emergency-contacts/7/set-primary",
            "GET /api/volunteer/profile",
            "PUT /api/volunteer/profile",
            "POST /api/volunteer/mock-verification/approve",
            "GET /api/volunteer/verification/status",
            "UPLOAD /api/volunteer/verification",
            "GET /api/volunteer/registration/status",
            "POST /api/volunteer/registration/step1",
            "POST /api/volunteer/registration/step3/face-verify/init",
            "POST /api/volunteer/registration/step3/face-verify/result",
        ])

        XCTAssertTrue(
            transport.allRequiredAuth,
            "档案片没有任何未登录端点；漏带 JWT 的那一条会静默变成 401"
        )
    }

    /// 资质证书走的是 multipart，不是 `send(_:body:)`。
    /// 走错通道时后端收到的是一个没有文件的空 POST —— 接口照样 200、状态照样回读，
    /// 屏幕上会念「资质证书已提交，等待管理员审核」，而证书根本没离开这台手机。
    func testCertificateUploadCarriesTheFileThroughTheMultipartChannel() async throws {
        let transport = RecordingTransport()
        transport.enqueue(VolunteerVerificationStatusResponse())

        _ = try await ProfileService(transport: transport).uploadVolunteerCertificate(
            MultipartFile(
                fieldName: "file",
                fileName: "cert.jpg",
                mimeType: "image/jpeg",
                data: Data([0x01, 0x02, 0x03])
            )
        )

        XCTAssertTrue(transport.requests.isEmpty, "走了普通 JSON 通道就等于文件被丢了")
        let upload = try XCTUnwrap(transport.uploads.first)
        XCTAssertEqual(upload.path, "/api/volunteer/verification")
        XCTAssertEqual(upload.files.count, 1)
        XCTAssertEqual(upload.files.first?.fieldName, "file")
        XCTAssertEqual(upload.files.first?.data, Data([0x01, 0x02, 0x03]))
    }
}

// MARK: - Test Doubles

/// 只记录并回放罐装值的 transport。**不含任何判定** —— 判定属于被测代码。
/// 与 `AuthServiceTests` 里那个同名替身分开各写一份：那个不需要记 `upload`，
/// 合并会让两片的用例互相牵制。
private final class RecordingTransport: APIClientProtocol, @unchecked Sendable {
    struct Recorded {
        let method: HTTPMethod
        let path: String
        let requiresAuth: Bool
    }

    struct RecordedUpload {
        let path: String
        let files: [MultipartFile]
        let requiresAuth: Bool
    }

    private(set) var requests: [Recorded] = []
    private(set) var uploads: [RecordedUpload] = []
    /// 调用顺序，元素是 `"METHOD /path"`（multipart 记成 `"UPLOAD /path"`）。
    private(set) var trace: [String] = []

    private var queued: [Any] = []

    func enqueue(_ response: Any) {
        queued.append(response)
    }

    var allRequiredAuth: Bool {
        requests.allSatisfy(\.requiresAuth) && uploads.allSatisfy(\.requiresAuth)
    }

    private func dequeue<T>() throws -> T {
        guard !queued.isEmpty else { throw APIError.unknown(statusCode: -1) }
        guard let typed = queued.removeFirst() as? T else { throw APIError.unknown(statusCode: -2) }
        return typed
    }

    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        requests.append(Recorded(method: method, path: path, requiresAuth: requiresAuth))
        trace.append("\(method.rawValue) \(path)")
        return try dequeue()
    }

    func upload<T: Decodable>(
        path: String,
        query: [String: String]?,
        fields: [String: String]?,
        files: [MultipartFile],
        requiresAuth: Bool
    ) async throws -> T {
        uploads.append(RecordedUpload(path: path, files: files, requiresAuth: requiresAuth))
        trace.append("UPLOAD \(path)")
        return try dequeue()
    }
}
