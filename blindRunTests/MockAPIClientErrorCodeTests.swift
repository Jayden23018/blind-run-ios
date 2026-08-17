import XCTest
@testable import blindRun

/// 防止 Mock 抛出的 wire code 与 `ErrorCode` 枚举再次漂移。
///
/// 曾经是扫 `MockAPIClient.swift` 源码的静态守卫，但真机测试包沙盒里读不到 .swift，
/// 而真机是本仓唯一可用的 XCTest 通道（模拟器因高德无 arm64-sim slice 不可用），
/// 于是这条守卫从来没真正执行过。改为内联字面量清单，代价是新增 throw 点要手动补进来。
final class MockAPIClientErrorCodeTests: XCTestCase {

    /// `MockAPIClient.swift` 里所有 `ErrorResponse(code: "...")` 字面量。
    /// 用 `grep -o 'code: "[A-Z_]*"' blindRun/Core/MockAPIClient.swift | sort -u` 重新生成。
    ///
    /// 2026-08-12 重新生成过一次：手动维护已经漂了 7 条
    /// （`EMERGENCY_*` 三条、`KEEP_WAITING_LIMIT_REACHED`、`NOT_ORDER_PARTICIPANT` 等），
    /// 也就是说这条守卫在那段时间对新增 throw 点是瞎的。**改 Mock 就重跑一次上面那条命令**，
    /// 别只往下加自己那一条。
    private static let mockWireCodes = [
        "ACTIVE_ORDER_ACCOUNT_DELETION_BLOCKED",
        "APPOINTMENT_TOO_SOON",
        "BAD_REQUEST",
        "CONTACT_FIELD_REQUIRED",
        "CONTACT_LIMIT_EXCEEDED",
        "CONTACT_MINIMUM_REQUIRED",
        "EMERGENCY_ALREADY_CLOSED",
        "EMERGENCY_CONTACT_REQUIRED",
        "EMERGENCY_NOT_OWNER",
        "EMERGENCY_VOLUNTEER_CANNOT_DISMISS",
        "IDENTITY_NOT_VERIFIED",
        "ID_INFO_INVALID",
        "INVALID_TIMESTAMP",
        "INVALID_VERIFICATION_CODE",
        "KEEP_WAITING_LIMIT_REACHED",
        "NOT_ORDER_PARTICIPANT",
        "ORDER_ALREADY_ACCEPTED",
        "ORDER_NOT_FOUND",
        "ORDER_STATUS_NOT_ALLOWED",
        "REGISTRATION_STEP_INVALID",
        "RESOURCE_NOT_FOUND",
        "REVIEW_ALREADY_SUBMITTED",
        "SECURITY_FORBIDDEN",
        "VALIDATION_ERROR"
    ]

    func testMockErrorCodesAllResolveToKnownErrorCode() {
        let unknown = Self.mockWireCodes.filter { ErrorCode(rawValue: $0) == nil }

        XCTAssertTrue(
            unknown.isEmpty,
            "MockAPIClient 抛出的这些 code 在 ErrorCode 枚举里不存在，客户端会落到未知兜底：\(unknown.sorted())"
        )
    }

    // MARK: - 盲人下单前置门槛（后端 ErrorCode.java「盲人下单前置条件类（403）」）

    /// rawValue 必须逐字对上后端枚举的 `code`，错一个字母就落到未知兜底。
    func testBookingPrerequisiteErrorCodesDecodeFromBackendWireValues() {
        XCTAssertEqual(ErrorCode(rawValue: "IDENTITY_NOT_VERIFIED"), .identityNotVerified)
        XCTAssertEqual(ErrorCode(rawValue: "EMERGENCY_CONTACT_REQUIRED"), .emergencyContactRequired)

        XCTAssertEqual(
            ErrorResponse(code: "IDENTITY_NOT_VERIFIED", message: "请先完成实名认证再下单").errorCode,
            .identityNotVerified
        )
        XCTAssertEqual(
            ErrorResponse(code: "EMERGENCY_CONTACT_REQUIRED", message: "请先设置紧急联系人再下单").errorCode,
            .emergencyContactRequired
        )
    }

    /// 客户端固定文案：不回显后端 message，并且要指出下一步动作（盲人靠 TTS 听）。
    func testBookingPrerequisiteMessagesAreClientOwnedAndActionable() {
        let identity = ErrorCode.identityNotVerified.localizedMessage
        XCTAssertTrue(identity.contains("实名认证"))
        XCTAssertTrue(identity.contains("设置"), "要告诉用户去哪儿做，不能只说不行")
        XCTAssertEqual(ErrorCode.identityNotVerified.ttsMessage, identity)

        let contacts = ErrorCode.emergencyContactRequired.localizedMessage
        XCTAssertTrue(contacts.contains("紧急联系人"))
        XCTAssertTrue(contacts.contains("主联系人"))
        XCTAssertEqual(ErrorCode.emergencyContactRequired.ttsMessage, contacts)

        // 专用码存在的意义就是不再和兜底权限拒绝共用同一句话。
        XCTAssertNotEqual(contacts, ErrorCode.orderPermissionDenied.localizedMessage)
        XCTAssertNotEqual(identity, ErrorCode.orderPermissionDenied.localizedMessage)
        XCTAssertNotEqual(identity, contacts)
    }
}
