import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class VolunteerCertificateTests: XCTestCase {
    // MARK: - 志愿者资质证书上传（POST /api/volunteer/verification）

    /// 上限来自后端 `VolunteerController.java:77`：`file.getSize() > 5 * 1024 * 1024` 才拒。
    /// 正好 5 MB 必须放行，5 MB + 1 字节必须本地拦截。
    func testCertificateFileSizeBoundaryMatchesBackend() {
        XCTAssertEqual(VolunteerCertificateFileRules.maxByteCount, 5 * 1024 * 1024)
        XCTAssertNil(
            VolunteerCertificateFileRules.validate(fileExtension: "pdf", byteCount: 5 * 1024 * 1024)
        )
        XCTAssertEqual(
            VolunteerCertificateFileRules.validate(fileExtension: "pdf", byteCount: 5 * 1024 * 1024 + 1),
            .tooLarge(byteCount: 5 * 1024 * 1024 + 1)
        )
        XCTAssertEqual(
            VolunteerCertificateFileRules.validate(fileExtension: "pdf", byteCount: 0),
            .emptyFile
        )
    }

    /// 扩展名白名单来自 `LocalFileStorageService.java:26`。
    func testCertificateExtensionWhitelistMatchesBackend() {
        XCTAssertEqual(
            Set(VolunteerCertificateFileRules.allowedExtensions),
            ["jpg", "jpeg", "png", "gif", "webp", "bmp", "pdf"]
        )
        for allowed in VolunteerCertificateFileRules.allowedExtensions {
            XCTAssertNil(VolunteerCertificateFileRules.validate(fileExtension: allowed, byteCount: 1024))
            let mime = VolunteerCertificateFileRules.mimeType(forExtension: allowed)
            // 后端只接受 image/* 或 application/pdf。
            XCTAssertTrue(mime?.hasPrefix("image/") == true || mime == "application/pdf")
        }
        XCTAssertEqual(
            VolunteerCertificateFileRules.validate(fileExtension: "heic", byteCount: 1024),
            .unsupportedType
        )
        XCTAssertNil(VolunteerCertificateFileRules.mimeType(forExtension: "heic"))
    }

    /// 魔数嗅探与后端 `LocalFileStorageService.validateMagicBytes` 对齐，
    /// 客户端据此决定扩展名，避免「改扩展名伪装」被后端 400。
    func testCertificateMagicByteDetection() {
        XCTAssertEqual(VolunteerCertificateFileRules.detectExtension(from: Data("%PDF-1.7".utf8)), "pdf")
        XCTAssertEqual(VolunteerCertificateFileRules.detectExtension(from: Data([0xFF, 0xD8, 0xFF, 0xE0])), "jpg")
        XCTAssertEqual(VolunteerCertificateFileRules.detectExtension(from: Data([0x89, 0x50, 0x4E, 0x47])), "png")
        XCTAssertNil(VolunteerCertificateFileRules.detectExtension(from: Data([0x00, 0x01, 0x02, 0x03])))
    }

    /// 构造出来的文件名不得包含来源文件名（证书属敏感材料）。
    func testCertificateFileBuildsNeutralFileName() throws {
        var pdf = Data("%PDF-1.7\n".utf8)
        pdf.append(Data(repeating: 0x20, count: 1024))

        let result = VolunteerCertificateFile.make(from: pdf)
        guard case .success(let file) = result else {
            return XCTFail("合法 PDF 应当构造成功")
        }
        XCTAssertEqual(file.fileExtension, "pdf")
        XCTAssertEqual(file.mimeType, "application/pdf")
        XCTAssertEqual(file.fileName, "certificate.pdf")
        XCTAssertTrue(file.summaryText.contains("PDF"))
    }

    func testCertificateFileRejectsOversizedPdfWithoutUpload() {
        var pdf = Data("%PDF-1.7\n".utf8)
        pdf.append(Data(repeating: 0x20, count: VolunteerCertificateFileRules.maxByteCount))

        guard case .failure(let failure) = VolunteerCertificateFile.make(from: pdf) else {
            return XCTFail("超过 5 MB 的 PDF 必须在本地被拒")
        }
        guard case .tooLarge = failure else {
            return XCTFail("应当命中大小上限，实际：\(failure)")
        }
        XCTAssertTrue(failure.message.contains("5 MB"))
    }

    func testCertificateFileRejectsUnknownBinaryWithoutUpload() {
        let junk = Data(repeating: 0x7A, count: 2048)

        guard case .failure(let failure) = VolunteerCertificateFile.make(from: junk) else {
            return XCTFail("无法识别的二进制必须在本地被拒")
        }
        XCTAssertEqual(failure, .unsupportedType)
    }

    // MARK: - 资质审核五态

    func testCertificateStatusParsingCoversBackendValues() {
        XCTAssertEqual(VolunteerCertificateStatus.parse("NONE"), VolunteerCertificateStatus.none)
        XCTAssertEqual(VolunteerCertificateStatus.parse("PENDING"), .pending)
        XCTAssertEqual(VolunteerCertificateStatus.parse("APPROVED"), .approved)
        XCTAssertEqual(VolunteerCertificateStatus.parse("REJECTED"), .rejected)
        // 历史上客户端把状态存成小写，解析必须兼容。
        XCTAssertEqual(VolunteerCertificateStatus.parse("approved"), .approved)
        XCTAssertEqual(VolunteerCertificateStatus.parse(nil), .unknown)
        XCTAssertEqual(VolunteerCertificateStatus.parse("SOMETHING_NEW"), .unknown)
    }

    /// 只有 APPROVED 能接单；PENDING 必须明说「审核中，暂时无法接单」且不引导重复上传。
    func testCertificateDisplayStatesGuideAcceptEligibility() {
        let states: [(VolunteerCertificateStatus, Bool, VolunteerCertificateDisplayState)] = [
            (VolunteerCertificateStatus.none, false, .notSubmitted),
            (.pending, false, .pending),
            (.approved, false, .approved),
            (.rejected, false, .rejected),
            (.unknown, false, .statusUnavailable),
            (.approved, true, .statusUnavailable)
        ]
        for (status, loadFailed, expected) in states {
            let state = VolunteerCertificateDisplayState.from(status: status, statusLoadFailed: loadFailed)
            XCTAssertEqual(state, expected)
            XCTAssertFalse(state.displayName.isEmpty)
            XCTAssertFalse(state.guidanceMessage.isEmpty)
        }

        XCTAssertTrue(VolunteerCertificateDisplayState.approved.canAcceptOrders)
        for state: VolunteerCertificateDisplayState in [.notSubmitted, .pending, .rejected, .statusUnavailable] {
            XCTAssertFalse(state.canAcceptOrders, "\(state) 不应被判定为可接单")
        }

        // 未提交 / 被拒可以上传；审核中、已通过、状态未知都不允许发起上传。
        XCTAssertTrue(VolunteerCertificateDisplayState.notSubmitted.allowsUpload)
        XCTAssertTrue(VolunteerCertificateDisplayState.rejected.allowsUpload)
        XCTAssertFalse(VolunteerCertificateDisplayState.pending.allowsUpload)
        XCTAssertFalse(VolunteerCertificateDisplayState.approved.allowsUpload)
        XCTAssertFalse(VolunteerCertificateDisplayState.statusUnavailable.allowsUpload)

        XCTAssertTrue(VolunteerCertificateDisplayState.pending.guidanceMessage.contains("暂时无法接单"))
        XCTAssertTrue(VolunteerCertificateDisplayState.approved.guidanceMessage.contains("可以接单"))
        XCTAssertTrue(VolunteerCertificateDisplayState.statusUnavailable.guidanceMessage.contains("重新获取状态"))
    }

    /// 后端两个接口的响应体都能解出 status。
    func testVerificationStatusResponseDecodesBothShapes() throws {
        let statusOnly = try JSONDecoder().decode(
            VolunteerVerificationStatusResponse.self,
            from: Data(#"{"status":"PENDING"}"#.utf8)
        )
        XCTAssertEqual(VolunteerCertificateStatus.parse(statusOnly.status), .pending)

        let submitResponse = try JSONDecoder().decode(
            VolunteerVerificationStatusResponse.self,
            from: Data(#"{"success":true,"status":"PENDING"}"#.utf8)
        )
        XCTAssertEqual(submitResponse.success, true)
        XCTAssertEqual(VolunteerCertificateStatus.parse(submitResponse.status), .pending)
    }

    // MARK: - 接单被 403 VOLUNTEER_NOT_VERIFIED 拒绝

    /// case 名是历史命名，rawValue 必须保持 `VOLUNTEER_NOT_VERIFIED`。
    func testVolunteerNotVerifiedErrorCodeMapsToCertificateGuidance() {
        XCTAssertEqual(ErrorCode.volunteerNotApproved.rawValue, "VOLUNTEER_NOT_VERIFIED")

        let response = ErrorResponse(code: "VOLUNTEER_NOT_VERIFIED", message: "志愿者资质未通过审核")
        XCTAssertEqual(response.errorCode, .volunteerNotApproved)

        let error = APIError.serverError(response)
        XCTAssertEqual(error.errorCode, .volunteerNotApproved)
        XCTAssertEqual(error.localizedMessage, "尚未通过资质认证，请先上传资质证书。")
    }

    /// 后端 403 的真实响应体（`{success,code,message,errorCode}`）必须能解出 errorCode，
    /// 否则界面拿不到「去上传资质证书」的触发条件。
    func testVolunteerNotVerifiedDecodesFromBackendErrorEnvelope() throws {
        let data = Data(#"""
        {"success":false,"code":403,"errorCode":"VOLUNTEER_NOT_VERIFIED","message":"资质证书未通过审核，暂时无法接单"}
        """#.utf8)

        let envelope = try JSONDecoder().decode(APIErrorEnvelope.self, from: data)
        let resolved = try XCTUnwrap(envelope.resolvedErrorResponse(statusCode: 403))

        XCTAssertEqual(resolved.errorCode, .volunteerNotApproved)
    }
}
