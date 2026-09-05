import XCTest
@testable import blindRun

/// 防止 Mock 抛出的 wire code 与 `ErrorCode` 枚举再次漂移。
///
/// 曾经是扫 `MockAPIClient.swift` 源码的静态守卫，但真机测试包沙盒里读不到 .swift，
/// 而真机是本仓唯一可用的 XCTest 通道（模拟器因高德无 arm64-sim slice 不可用），
/// 于是这条守卫从来没真正执行过。改为内联字面量清单，代价是新增 throw 点要手动补进来。
final class MockAPIClientErrorCodeTests: XCTestCase {

    /// Mock 各分片里所有 `ErrorResponse(code: "...")` 字面量。**改 Mock 就重跑一次下面这条**，
    /// 别只往下加自己那一条：
    ///
    /// ```
    /// python3 -c "
    /// import re,glob
    /// c=set()
    /// for p in glob.glob('blindRun/Core/MockAPIClient*.swift'):
    ///     c |= set(re.findall(r'code:\s*\"([A-Z_]+)\"', open(p).read()))
    /// print('\n'.join(sorted(c)))"
    /// ```
    ///
    /// ⚠️ 2026-09-05 把范围从 `MockAPIClient.swift` 一个文件改成 `MockAPIClient*.swift` ——
    /// **上一版的重新生成命令本身是漏的**。Mock 早已拆成 8 个分片（`+Order` / `+IntroCall` /
    /// `+Incentive` …），命令只扫主文件，于是 `INTRO_CALL_NOT_ACTIVE`、`SHARE_ORDER_ALREADY_FINISHED`、
    /// `FAVORITE_VOLUNTEER_*` 两条这 4 个码照着命令重跑也补不进来。
    /// 这是同一个漂移的第二次：2026-08-12 那次漂了 7 条（`EMERGENCY_*` 三条、
    /// `KEEP_WAITING_LIMIT_REACHED`、`NOT_ORDER_PARTICIPANT` 等），当时只补了清单没修命令。
    /// 用 `grep -o` 也不行 —— 本仓库 Bash 输出会被压制，多行匹配拿不到内容（见 `~/.claude/RTK.md`）。
    private static let mockWireCodes = [
        // ⚠️ 这里没有 `APPOINTMENT_TOO_LONG` / `APPOINTMENT_IN_NIGHT_WINDOW` 不是漏了：
        // Mock 刻意不镜像这两道，理由见 `MockAPIClient+Order.handleCreateOrder`。
        // 它们的映射与文案由本文件下面那两条用例守。
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
        "FAVORITE_VOLUNTEER_LIMIT_EXCEEDED",
        "FAVORITE_VOLUNTEER_NOT_ELIGIBLE",
        "IDENTITY_NOT_VERIFIED",
        "ID_INFO_INVALID",
        "INTRO_CALL_NOT_ACTIVE",
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
        "SHARE_ORDER_ALREADY_FINISHED",
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

    // MARK: - 下单时间类三条（后端 N134）

    func testAppointmentTimeErrorCodesDecodeFromBackendWireValues() {
        XCTAssertEqual(ErrorCode(rawValue: "APPOINTMENT_TOO_LONG"), .appointmentTooLong)
        XCTAssertEqual(ErrorCode(rawValue: "APPOINTMENT_IN_NIGHT_WINDOW"), .appointmentInNightWindow)
    }

    /// 盲人下单被拒后只能靠 TTS 听原因，**必须听得出该改哪个字段**。
    /// 只说「预约失败」的话，两条 422 在耳朵里完全一样，用户唯一能做的是原样再试一次。
    func testAppointmentRejectionMessagesTellTheUserWhatToChange() {
        let tooLong = ErrorCode.appointmentTooLong.localizedMessage
        XCTAssertTrue(tooLong.contains("5小时"), "要给出上限，不能只说太长")
        XCTAssertTrue(tooLong.contains("改短"), "要说清改哪个字段")
        XCTAssertEqual(ErrorCode.appointmentTooLong.ttsMessage, tooLong)

        let night = ErrorCode.appointmentInNightWindow.localizedMessage
        XCTAssertTrue(night.contains("10点") && night.contains("5点"), "要念出禁跑时段的两端")
        XCTAssertTrue(night.contains("整段"), "🚨 判据是整段不是开始时刻，不说清用户会去挪开始时间")
        XCTAssertEqual(ErrorCode.appointmentInNightWindow.ttsMessage, night)

        // 两条 422 同族，但要改的东西不同，文案不能撞。
        let tooSoon = ErrorCode.appointmentTooSoon.localizedMessage
        XCTAssertNotEqual(tooLong, night)
        XCTAssertNotEqual(tooLong, tooSoon)
        XCTAssertNotEqual(night, tooSoon)

        // 两条都命中时后端返回 `APPOINTMENT_TOO_LONG`，那句话就不能把人往改时段上引。
        XCTAssertFalse(tooLong.contains("晚上"), "超长单先要改短，改时段没用")
    }
}
