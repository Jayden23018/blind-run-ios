import XCTest
@testable import blindRun

/// 首屏派单状态卡不重复作业区（#325 第三轮界面迭代）。
/// 写成扩展：`VolunteerProfileFirstScreenTests` 已超过类与文件长度上限（SwiftLint 棘轮只许变小）。
extension VolunteerProfileFirstScreenTests {

    /// 作业区已经画成整卡的原因（培训、资质），底部派单状态卡不再说第二遍；
    /// 其余原因照说，全被说过时那一句整句不出现。
    ///
    /// 🔴 第二条与第四条是这条用例的价值：「不过滤」的实现在第一条就红，而
    /// 「只要有一条被说过就整句不出」的实现只会在第二条红；第四条钉住未识别取值的兜底。
    func testDispatchCardOmitsReasonsTheTodoSectionAlreadyShows() {
        let omit = VolunteerDispatchSummaryCard.reasonsShownInTodoSection
        XCTAssertNil(
            Self.summary(reasons: [.trainingIncomplete]).dispatchStatusText(omitting: omit),
            "作业区已经有「尚未完成必修培训」整卡，底部卡再说一遍是 2026-10-05 评审点名的重复"
        )
        XCTAssertEqual(
            Self.summary(reasons: [.trainingIncomplete, .offline]).dispatchStatusText(omitting: omit),
            "当前未在线",
            "别处没说过的原因要留下"
        )
        XCTAssertEqual(
            Self.summary(reasons: []).dispatchStatusText(omitting: omit),
            "已上线，等待系统派单"
        )
        XCTAssertEqual(
            Self.summary(reasons: [.notVerified, .unknown]).dispatchStatusText(omitting: omit),
            VolunteerDispatchNotAvailableReason.unknown.displayText,
            "只剩未识别取值时说兜底那句，不能拼出空串"
        )
    }

    /// 卡里省掉的原因集合必须与作业区两道闸**逐个一致** —— 闸改了而集合没跟，
    /// 要么同一屏说两遍，要么某条原因哪儿都不说。
    func testDispatchCardOmitsExactlyTheReasonsTheTodoGatesShow() {
        for reason in VolunteerDispatchNotAvailableReason.allCases {
            let summary = Self.summary(reasons: [reason])
            let shownInTodo = VolunteerProfileTodoGate.needsTrainingEntry(summary: summary)
                || VolunteerProfileTodoGate.needsCertificateEntry(summary: summary, apiRejectedAsUnapproved: false)
            XCTAssertEqual(
                VolunteerDispatchSummaryCard.reasonsShownInTodoSection.contains(reason),
                shownInTodo,
                "\(reason.rawValue)：卡里省不省与作业区画不画对不上"
            )
        }
    }
}
