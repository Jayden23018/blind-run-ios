import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class MockBackendAlignmentTests: XCTestCase {
    // MARK: - ROLE_ALREADY_SET 语义

    /// 该码曾被命名成 `activeOrderRoleSwitchBlocked` 并映射成「存在进行中的订单，无法切换角色」，
    /// 导致没有任何订单的用户看到假的订单拦截提示。后端 `RoleController` 的真实语义只是
    /// 「角色一次性设定，不可修改」，与订单无关，文案里不得再出现「订单」。
    func testRoleAlreadySetMessageDoesNotBlameOrders() {
        let response = ErrorResponse(code: "ROLE_ALREADY_SET", message: "身份已设定，不可修改")
        XCTAssertEqual(response.errorCode, .roleAlreadySet)

        let message = APIError.serverError(response).localizedMessage
        XCTAssertFalse(message.contains("订单"), "ROLE_ALREADY_SET 文案不得提及订单：\(message)")
    }

    // MARK: - Mock 与后端实现逐条对齐

    func testMockVerificationStatusOnlyReturnsBackendEnumValues() async throws {
        let client = MockAPIClient()
        let response: VolunteerVerificationStatusResponse = try await client.get(
            "/api/volunteer/verification/status"
        )
        let raw = try XCTUnwrap(response.status)

        XCTAssertTrue(["NONE", "PENDING", "APPROVED", "REJECTED"].contains(raw), "Mock 返回了后端不存在的取值：\(raw)")
        XCTAssertNotEqual(VolunteerCertificateStatus.parse(raw), .unknown)
    }

    /// `VolunteerController.java:77` 的大小拒绝，文案逐字一致且不带 errorCode。
    func testMockRejectsOversizedCertificateLikeBackend() async {
        let client = MockAPIClient()
        let file = MultipartFile(
            fieldName: "file",
            fileName: "certificate.jpg",
            mimeType: "image/jpeg",
            data: Data(repeating: 0xFF, count: 5 * 1024 * 1024 + 1)
        )

        do {
            let _: VolunteerVerificationStatusResponse = try await client.upload(
                "/api/volunteer/verification",
                files: [file]
            )
            XCTFail("超过 5 MB 必须被拒")
        } catch let error as APIError {
            XCTAssertNil(error.errorCode, "后端该 400 没有 errorCode")
            XCTAssertEqual(error.localizedMessage, "文件大小不能超过5MB")
        } catch {
            XCTFail("应当抛出 APIError，实际：\(error)")
        }
    }

    /// `VolunteerController.java:73` 的类型拒绝。
    func testMockRejectsUnsupportedCertificateContentTypeLikeBackend() async {
        let client = MockAPIClient()
        let file = MultipartFile(
            fieldName: "file",
            fileName: "certificate.txt",
            mimeType: "text/plain",
            data: Data("hello".utf8)
        )

        do {
            let _: VolunteerVerificationStatusResponse = try await client.upload(
                "/api/volunteer/verification",
                files: [file]
            )
            XCTFail("非图片非 PDF 必须被拒")
        } catch let error as APIError {
            XCTAssertEqual(error.localizedMessage, "文件格式仅支持图片或PDF")
        } catch {
            XCTFail("应当抛出 APIError，实际：\(error)")
        }
    }

    /// `VolunteerService.java:314`：APPROVED 状态重传抛 `IllegalArgumentException`，
    /// 经 `GlobalExceptionHandler:136` 变成 `ApiResponse.error(400, BAD_REQUEST, message)`。
    /// 与前三条 Controller 内联 400 不同，这一条**带 errorCode**，
    /// 因此 `localizedMessage` 走的是 `ErrorCode.badRequest` 的通用文案，
    /// 后端那句具体说明只留在 `ErrorResponse.message` 里。
    func testMockRejectsReuploadAfterApprovalLikeBackend() async {
        let client = MockAPIClient()
        let file = MultipartFile(
            fieldName: "file",
            fileName: "certificate.pdf",
            mimeType: "application/pdf",
            data: Data("%PDF-1.7".utf8)
        )

        do {
            let _: VolunteerVerificationStatusResponse = try await client.upload(
                "/api/volunteer/verification",
                files: [file]
            )
            XCTFail("已通过审核不允许重传")
        } catch let error as APIError {
            XCTAssertEqual(error.errorCode, .badRequest, "后端该 400 由全局异常处理器带上 BAD_REQUEST")
            guard case .serverError(let response) = error else {
                return XCTFail("应当是 serverError，实际：\(error)")
            }
            XCTAssertEqual(response.message, "资质证书已审核通过，无需重新上传")
            XCTAssertEqual(error.localizedMessage, "请求参数有误。")
        } catch {
            XCTFail("应当抛出 APIError，实际：\(error)")
        }
    }

    /// 上传成功后状态置 PENDING，且 `/api/volunteer/profile` 与状态接口保持同源。
    func testMockUploadMovesStatusToPendingAndStaysConsistent() async throws {
        setenv("AIDRUN_MOCK_VOLUNTEER_VERIFICATION_STATUS", "NONE", 1)
        defer { unsetenv("AIDRUN_MOCK_VOLUNTEER_VERIFICATION_STATUS") }

        let client = MockAPIClient()
        let before: VolunteerVerificationStatusResponse = try await client.get(
            "/api/volunteer/verification/status"
        )
        XCTAssertEqual(VolunteerCertificateStatus.parse(before.status), VolunteerCertificateStatus.none)

        let submitted: VolunteerVerificationStatusResponse = try await client.upload(
            "/api/volunteer/verification",
            files: [MultipartFile(
                fieldName: "file",
                fileName: "certificate.pdf",
                mimeType: "application/pdf",
                data: Data("%PDF-1.7".utf8)
            )]
        )
        XCTAssertEqual(submitted.success, true)
        XCTAssertEqual(VolunteerCertificateStatus.parse(submitted.status), .pending)

        let after: VolunteerVerificationStatusResponse = try await client.get(
            "/api/volunteer/verification/status"
        )
        XCTAssertEqual(VolunteerCertificateStatus.parse(after.status), .pending)

        let profile: VolunteerProfileResponse = try await client.get("/api/volunteer/profile")
        XCTAssertEqual(VolunteerCertificateStatus.parse(profile.verificationStatus), .pending)
    }

    /// `GET /api/volunteer/verification/status` 只返回 status，写回时不得抹掉其它资料字段。
    func testAppStateVerificationStatusUpdateKeepsOtherProfileFields() {
        let appState = AppState()
        appState.updateVolunteerProfile(VolunteerProfileResponse(
            name: "测试志愿者",
            verificationStatus: "NONE",
            isAvailable: true,
            acceptsGuideDog: true,
            paceRange: .moderate
        ))

        appState.updateVolunteerVerificationStatus("PENDING")

        XCTAssertEqual(appState.volunteerProfile?.verificationStatus, "PENDING")
        XCTAssertEqual(appState.volunteerProfile?.name, "测试志愿者")
        XCTAssertEqual(appState.volunteerProfile?.isAvailable, true)
        XCTAssertEqual(appState.volunteerProfile?.acceptsGuideDog, true)
        XCTAssertEqual(appState.volunteerProfile?.paceRange, .moderate)
    }
}
