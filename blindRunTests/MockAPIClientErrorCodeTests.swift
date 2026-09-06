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

    // MARK: - 2026-09-04 后端新增两码（架构复核 N126）

    func testTwoThousandTwentySixNinthBatchCodesDecodeFromBackendWireValues() {
        XCTAssertEqual(ErrorCode(rawValue: "VOLUNTEER_ALREADY_ENGAGED"), .volunteerAlreadyEngaged)
        XCTAssertEqual(ErrorCode(rawValue: "ID_VERIFY_UNAVAILABLE"), .idVerifyUnavailable)
    }

    /// 🚨 `VOLUNTEER_ALREADY_ENGAGED` 与 `ORDER_ALREADY_ACCEPTED` **意思相反**，
    /// 共用一句话会把志愿者指到完全错误的动作上：那个是「这一单被别人抢走了」（去看别的单），
    /// 这个是「你自己那个时段有事」（换个时段的单）。
    ///
    /// 文案跟的是后端 2026-09-05 改后的语义 —— 判据已从「有没有占用中的单」改成
    /// 「有没有**时间重叠**的占用中的单」。所以它必须说「时间段」，不能说「还有一单没有完成」：
    /// 跨天预约上线后接了后天的单照样能接今天的，照旧文案会让他去找一张根本不冲突的单。
    func testVolunteerAlreadyEngagedIsAboutTheTimeSlotNotAnUnfinishedOrder() {
        let engaged = ErrorCode.volunteerAlreadyEngaged.localizedMessage

        XCTAssertTrue(engaged.contains("时间段"), "判据是时段重叠，说成「有单没跑完」会指错方向")
        XCTAssertFalse(
            engaged.contains("没有完成"),
            "这是 2026-09-05 之前的旧语义，跨天预约上线后它是假话"
        )
        XCTAssertNotEqual(
            engaged,
            ErrorCode.orderAlreadyAccepted.localizedMessage,
            "两者意思相反，共用文案等于把志愿者指到相反的动作上"
        )
        XCTAssertEqual(ErrorCode.volunteerAlreadyEngaged.ttsMessage, engaged)
    }

    /// `ID_VERIFY_UNAVAILABLE`(503) 是核验**服务**挂了，`ID_INFO_INVALID`(400) 才是证件对不上。
    /// 前者绝不能引导用户去核对证件 —— 他的证件没有任何问题，让他去核对是在浪费他的时间。
    func testIdVerifyUnavailableNeverTellsTheUserToCheckTheirCredentials() {
        let unavailable = ErrorCode.idVerifyUnavailable.localizedMessage

        XCTAssertTrue(unavailable.contains("暂时不可用"))
        XCTAssertTrue(unavailable.contains("稍后重试"), "重试是唯一有意义的动作")
        XCTAssertFalse(unavailable.contains("核对"), "他的证件没问题，引导核对是在浪费他的时间")
        XCTAssertNotEqual(unavailable, ErrorCode.idInfoInvalid.localizedMessage)

        // 盲人提交页有自己的一层固定文案（不回显后端 message），同一条区分要在那儿也成立 ——
        // 否则它会落到 `genericMessage`，和「提交失败」这类真·未知错误说同一句话。
        let blindCopy = BlindIdentityVerificationFailure.message(
            for: .serverError(ErrorResponse(code: "ID_VERIFY_UNAVAILABLE", message: "身份认证服务暂时不可用"))
        )
        XCTAssertNotEqual(blindCopy, BlindIdentityVerificationFailure.genericMessage)
        XCTAssertFalse(blindCopy.contains("核对"))
        XCTAssertNotEqual(
            blindCopy,
            BlindIdentityVerificationFailure.message(
                for: .serverError(ErrorResponse(code: "ID_INFO_INVALID", message: "身份信息核验未通过"))
            )
        )
    }
}
