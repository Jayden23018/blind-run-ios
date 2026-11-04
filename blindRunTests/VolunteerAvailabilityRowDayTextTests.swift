import XCTest
@testable import blindRun

/// #673：列表行的日期串不再以全角「）」收尾（真机审计判「放大字号可能被裁」，补窄空格也不够）。
final class VolunteerAvailabilityRowDayTextTests: XCTestCase {
    func testTrailingFullWidthParenBecomesHalfWidthGroup() {
        XCTAssertEqual(VolunteerAvailabilityScheduleEditing.rowDayText("仅 11月4日（周三）"), "仅 11月4日 (周三)")
        XCTAssertEqual(VolunteerAvailabilityScheduleEditing.rowDayText("仅 10月19日（周一）"), "仅 10月19日 (周一)")
    }

    func testTextWithoutTrailingParenIsUntouched() {
        XCTAssertEqual(VolunteerAvailabilityScheduleEditing.rowDayText("周六"), "周六")
        // 只有「（」没有收尾的「）」：不动，避免拆坏别的文案。
        XCTAssertEqual(VolunteerAvailabilityScheduleEditing.rowDayText("仅 11月4日（周三"), "仅 11月4日（周三")
    }
}
