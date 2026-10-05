import XCTest
@testable import blindRun

/// 后端 #542：WS 载荷里的时刻用 Java `LocalDateTime.toString()` 拼，秒与小数秒都为 0 时
/// 它会省掉 `:00`，输出 `2026-10-05T07:00` 而不是协议写的 `2026-10-05T07:00:00`。
///
/// `NEW_ORDER.plannedStart` 是用户预约的时刻，几乎总是整分钟 —— 所以线上不是「偶尔」缺秒，
/// 而是几乎每条都缺。解析不出来时陪跑员邀请屏的大标题会从「明天 7:00」退回「新的陪跑邀请」，
/// 而调试预置与用例的时间都带秒，从来没走到过这条路径。
@MainActor
final class WireTimeWithoutSecondsTests: XCTestCase {
    func testParsesJavaLocalDateTimeThatDropsZeroSeconds() throws {
        let withSeconds = try XCTUnwrap("2026-10-05T07:00:00".backendLocalDate)
        XCTAssertEqual("2026-10-05T07:00".backendLocalDate, withSeconds)
        XCTAssertEqual("2026-10-05T07:00".backendTimestamp, withSeconds)
    }

    /// 用户看得见的那一层：邀请屏标题与首页大字都走 `RunPlanFormat.shortStart`。
    func testInviteTitleShowsTheStartTimeWhenTheWireDropsSeconds() throws {
        let now = try XCTUnwrap("2026-10-04T20:00:00".backendTimestamp)
        let expected = try XCTUnwrap(RunPlanFormat.shortStart("2026-10-05T07:00:00", now: now))
        XCTAssertEqual(RunPlanFormat.shortStart("2026-10-05T07:00", now: now), expected)
    }

    /// 放宽只放宽「缺秒」这一种形状。带偏移的串仍然交给 ISO-8601 分支，不能被本地格式吞掉
    /// —— 那样会把 `Z` / `+08:00` 当成北京钟点，差出整数小时。
    func testMinuteOnlyShapeDoesNotSwallowOffsetsOrTruncatedStrings() {
        XCTAssertNil("2026-10-05T07:00Z".backendLocalDate)
        XCTAssertNil("2026-10-05T07:00+08:00".backendLocalDate)
        XCTAssertNil("2026-10-05T07".backendLocalDate)
        XCTAssertNil("2026-10-05".backendLocalDate)
    }
}
