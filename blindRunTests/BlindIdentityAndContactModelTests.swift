import XCTest
@testable import blindRun

/// 第 2 组（Models And Mock Contract）的最小可运行检查：
/// 实名三态解码容错、AppState 完成度拆分、Mock 紧急联系人 CRUD 与主联系人不变量。
final class BlindIdentityStatusTests: XCTestCase {

    func testVerifyStatusParsesThreeBackendValues() {
        XCTAssertEqual(BlindVerifyStatus.parse("NOT_VERIFIED"), .notVerified)
        XCTAssertEqual(BlindVerifyStatus.parse("VERIFIED"), .verified)
        XCTAssertEqual(BlindVerifyStatus.parse("FAILED"), .failed)
    }

    func testVerifyStatusFallsBackToUnknownInsteadOfFailingDecode() throws {
        // 后端没有 PENDING 态；出现未知值时不能让整包资料解析失败。
        XCTAssertEqual(BlindVerifyStatus.parse("PENDING"), .unknown)
        XCTAssertEqual(BlindVerifyStatus.parse(nil), .unknown)
        XCTAssertEqual(BlindVerifyStatus.parse(""), .unknown)

        let json = Data(#"{"verifyStatus":"PENDING","name":"张三"}"#.utf8)
        let profile = try JSONDecoder().decode(BlindProfileResponse.self, from: json)
        XCTAssertEqual(profile.identityStatus, .unknown)
        XCTAssertEqual(profile.name, "张三")
    }

    func testOnlyVerifiedCountsAsVerifiedAndOthersPrompt() {
        XCTAssertTrue(BlindVerifyStatus.verified.isVerified)
        XCTAssertFalse(BlindVerifyStatus.verified.shouldPromptVerification)
        for status in [BlindVerifyStatus.notVerified, .failed, .unknown] {
            XCTAssertFalse(status.isVerified)
            XCTAssertTrue(status.shouldPromptVerification)
        }
    }

    func testVerificationFailureMessageNeverEchoesBackendMessage() {
        let leaking = APIError.serverError(ErrorResponse(
            code: "SOME_UNMAPPED_CODE",
            message: "身份证号 110101199003072316 无效"
        ))
        let message = BlindIdentityVerificationFailure.message(for: leaking)
        XCTAssertEqual(message, BlindIdentityVerificationFailure.genericMessage)
        XCTAssertFalse(message.contains("110101199003072316"))

        let mapped = APIError.serverError(ErrorResponse(code: "ID_INFO_INVALID", message: "x"))
        XCTAssertTrue(BlindIdentityVerificationFailure.message(for: mapped).contains("核验未通过"))
    }

    func testContactPhoneMaskingIsDisplayOnly() {
        XCTAssertEqual(EmergencyContactResponse.maskPhone("13900139001"), "139****9001")
        XCTAssertNil(EmergencyContactResponse.maskPhone(nil))
        // 非 11 位手机号原样返回，避免把无法识别的值截断成误导性内容。
        XCTAssertEqual(EmergencyContactResponse.maskPhone("123"), "123")
    }

    func testSinglePrimaryRequiresExactlyOne() {
        func contact(_ id: Int64, primary: Bool) -> EmergencyContactResponse {
            EmergencyContactResponse(id: id, name: "n\(id)", phone: "1390013900\(id)", relationship: nil, isPrimary: primary)
        }
        XCTAssertEqual(EmergencyContactResponse.singlePrimary(in: [contact(1, primary: true), contact(2, primary: false)])?.id, 1)
        XCTAssertNil(EmergencyContactResponse.singlePrimary(in: []))
        XCTAssertNil(EmergencyContactResponse.singlePrimary(in: [contact(1, primary: false)]))
        XCTAssertNil(EmergencyContactResponse.singlePrimary(in: [contact(1, primary: true), contact(2, primary: true)]))
    }
}


final class MockEmergencyContactContractTests: XCTestCase {

    private func request(name: String, phone: String, isPrimary: Bool? = nil) -> EmergencyContactRequest {
        EmergencyContactRequest(name: name, phone: phone, relationship: "家人", isPrimary: isPrimary)
    }

    private func contacts(_ client: MockAPIClient) async throws -> [EmergencyContactResponse] {
        try await client.get("/api/users/1/emergency-contacts")
    }

    func testCreateUpToFiveContactsThenRejectsSixth() async throws {
        let client = MockAPIClient()
        var current = try await contacts(client)
        XCTAssertEqual(current.count, 1)

        for index in 2...5 {
            let _: EmergencyContactResponse = try await client.post(
                "/api/users/1/emergency-contacts",
                body: request(name: "联系人\(index)", phone: "1390013900\(index)")
            )
        }
        current = try await contacts(client)
        XCTAssertEqual(current.count, EmergencyContactRules.maxCount)
        XCTAssertEqual(current.filter { $0.isPrimary == true }.count, 1)

        do {
            let _: EmergencyContactResponse = try await client.post(
                "/api/users/1/emergency-contacts",
                body: request(name: "第六个", phone: "13900139006")
            )
            XCTFail("超过 5 个联系人应当被拒绝")
        } catch let error as APIError {
            // 后端已改成专用码：`EmergencyContactService.java:64`
            // `throw new EmergencyContactException(ErrorCode.CONTACT_LIMIT_EXCEEDED, "最多添加 5 个紧急联系人")`。
            // 上限和下限必须能被区分（后续动作完全不同），所以不能退回通用 BAD_REQUEST。
            XCTAssertEqual(error.errorCode, .contactLimitExceeded)
            XCTAssertEqual(EmergencyContactsViewModel.displayMessage(for: error), "最多添加 5 个紧急联系人")
        }
    }

    func testSetPrimaryIsAtomicAndReturnsEmptyBody() async throws {
        let client = MockAPIClient()
        let added: EmergencyContactResponse = try await client.post(
            "/api/users/1/emergency-contacts",
            body: request(name: "联系人2", phone: "13900139002")
        )
        XCTAssertEqual(added.isPrimary, false)

        // set-primary 返回空 object，不返回列表：客户端必须重新 GET。
        let _: EmptyResponse = try await client.put("/api/users/1/emergency-contacts/\(added.id)/set-primary")

        let refreshed = try await contacts(client)
        XCTAssertEqual(refreshed.filter { $0.isPrimary == true }.map(\.id), [added.id])
        XCTAssertNotNil(EmergencyContactResponse.singlePrimary(in: refreshed))
    }

    func testUpdateWithIsPrimaryClearsPreviousPrimary() async throws {
        let client = MockAPIClient()
        let added: EmergencyContactResponse = try await client.post(
            "/api/users/1/emergency-contacts",
            body: request(name: "联系人2", phone: "13900139002")
        )
        let updated: EmergencyContactResponse = try await client.put(
            "/api/users/1/emergency-contacts/\(added.id)",
            body: request(name: "联系人2", phone: "13900139002", isPrimary: true)
        )
        XCTAssertEqual(updated.isPrimary, true)

        let refreshed = try await contacts(client)
        XCTAssertEqual(refreshed.filter { $0.isPrimary == true }.count, 1)
    }

    func testDeletingLastContactIsRejected() async throws {
        let client = MockAPIClient()
        let existing = try await contacts(client)
        let onlyContact = try XCTUnwrap(existing.first)

        do {
            let _: EmptyResponse = try await client.delete("/api/users/1/emergency-contacts/\(onlyContact.id)")
            XCTFail("最后一个紧急联系人不允许删除")
        } catch let error as APIError {
            // 同上：`EmergencyContactService.java:154` 抛专用码 CONTACT_MINIMUM_REQUIRED。
            XCTAssertEqual(error.errorCode, .contactMinimumRequired)
            XCTAssertEqual(EmergencyContactsViewModel.displayMessage(for: error), "至少保留 1 个紧急联系人")
        }
        let remaining = try await contacts(client)
        XCTAssertEqual(remaining.count, 1)
    }

    func testDeletingPrimaryContactPromotesAnotherPrimary() async throws {
        let client = MockAPIClient()
        let _: EmergencyContactResponse = try await client.post(
            "/api/users/1/emergency-contacts",
            body: request(name: "联系人2", phone: "13900139002")
        )
        let before = try await contacts(client)
        let primary = try XCTUnwrap(EmergencyContactResponse.singlePrimary(in: before))

        let _: EmptyResponse = try await client.delete("/api/users/1/emergency-contacts/\(primary.id)")

        let after = try await contacts(client)
        XCTAssertEqual(after.count, 1)
        XCTAssertNotNil(EmergencyContactResponse.singlePrimary(in: after))
    }

    func testAccountDeletionRouteStillRejectsForeignUser() async throws {
        let client = MockAPIClient()
        do {
            let _: DeleteAccountResponse = try await client.delete("/api/users/999")
            XCTFail("只允许删除当前账户")
        } catch let error as APIError {
            guard case .serverError(let response) = error else { return XCTFail("期望 serverError") }
            // 后端 UserService.deleteAccount 对非本人抛 PermissionDeniedException，
            // GlobalExceptionHandler#handlePermissionDenied 固定回 ErrorCode.SECURITY_FORBIDDEN（403）。
            XCTAssertEqual(response.code, ErrorCode.securityForbidden.rawValue)
        }
    }
}

final class MockBlindIdentityVerificationTests: XCTestCase {

    func testVerifyIdentitySubmissionUpdatesStatusReadBackFromProfile() async throws {
        let client = MockAPIClient()
        let _: EmptyResponse = try await client.post(
            "/api/blind/verify-identity",
            body: BlindVerifyRequest(idCardName: "张三", idCardNumber: "11010119900307231X")
        )
        // 响应是无类型 object，权威状态靠重新读资料。
        let profile: BlindProfileResponse = try await client.get("/api/blind/profile")
        XCTAssertEqual(profile.identityStatus, .verified)
    }

    func testVerifyIdentityRejectsMalformedIdCardNumber() async throws {
        let client = MockAPIClient()
        do {
            let _: EmptyResponse = try await client.post(
                "/api/blind/verify-identity",
                body: BlindVerifyRequest(idCardName: "张三", idCardNumber: "12345")
            )
            XCTFail("身份证号格式错误应被拒绝")
        } catch let error as APIError {
            XCTAssertEqual(error.errorCode, .idInfoInvalid)
            XCTAssertEqual(BlindIdentityVerificationFailure.message(for: error), "身份信息核验未通过，请核对姓名和身份证号后重试。")
        }
    }

    func testProfileUpdateDoesNotOverwriteVerifyStatus() async throws {
        let client = MockAPIClient()
        let updated: BlindProfileResponse = try await client.put(
            "/api/blind/profile",
            body: BlindProfileUpdateRequest(
                name: "新名字",
                runningPace: nil,
                specialNeeds: nil,
                visionLevel: nil,
                hasGuideDog: nil,
                tetherPreference: nil,
                chatPreference: nil,
                defaultPace: nil
            )
        )
        XCTAssertEqual(updated.name, "新名字")
        XCTAssertEqual(updated.identityStatus, .verified)
    }
}
