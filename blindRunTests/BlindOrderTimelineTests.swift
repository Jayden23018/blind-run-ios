import XCTest
@testable import blindRun

/// 订单页 v7 五步竖线（#917）：状态 → 步骤、折叠规则、读屏句。
///
/// 这条竖线的错误形态全是静默的：落错一步、该收的没收、读屏少念一步，屏幕上都不会报错。
/// 折叠阈值是「≥ 2 步才收」，所以每条用例都挑落在 1 与 2 之间的那组输入：阈值被改成 1 或 3 时会红。
final class BlindOrderTimelineTests: XCTestCase {

    // MARK: - 状态 → 步骤

    /// 穷举全部状态。漏一个状态不会让别的断言变红，它只是不再被检查。
    func testEveryOrderStatusMapsToAnExplicitTimelinePosition() {
        let expected: [RunOrderStatus: BlindOrderTimelinePosition?] = [
            .pendingMatch: .current(.matchVolunteer),
            .rematching: .current(.matchVolunteer),
            .pendingIntroCall: .current(.arrangeMeetup),
            .scheduledConfirmed: .current(.awaitDeparture),
            .pendingAccept: .current(.awaitDeparture),
            .driverEnRoute: .current(.meetUp),
            .driverArrived: .current(.meetUp),
            .inProgress: .current(.startRun),
            .completed: .allDone,
            .cancelled: nil,
            .noVolunteer: nil,
            .unknown: nil,
        ]
        for status in RunOrderStatus.allCases {
            XCTAssertTrue(expected.keys.contains(status), "\(status.rawValue) 没有写进期望表")
            XCTAssertEqual(status.blindOrderTimelinePosition, expected[status] ?? nil, status.rawValue)
        }
    }

    /// 「我不认识这个状态」不许画成「正在找人」。
    func testUnknownStatusDrawsNoTimeline() {
        XCTAssertNil(RunOrderStatus.unknown.blindOrderTimelinePosition)
    }

    func testStepNamesMatchTheDesignInOrder() {
        XCTAssertEqual(
            BlindOrderTimelineStep.allCases.map(\.title),
            ["匹配陪跑员", "商量见面安排", "等出发", "在集合点汇合", "开跑"]
        )
        XCTAssertEqual(BlindOrderTimelineStep.matchVolunteer.doneTitle, "已匹配陪跑员")
        XCTAssertEqual(BlindOrderTimelineStep.arrangeMeetup.doneTitle, "商量见面安排")
    }

    // MARK: - 四屏的折叠结果（稿 v7 ①–④）

    /// ① 匹配中：当前步展开，下一步一行，后面三步收起。
    func testMatchingShowsNextStepAndFoldsTheRemainingThree() {
        let rows = BlindOrderTimelineLayout.rows(input(.current(.matchVolunteer), details: [.matchVolunteer: "已等待 3 分钟"]))
        XCTAssertEqual(rows, [
            .current(.matchVolunteer, detail: "已等待 3 分钟"),
            .next(.arrangeMeetup),
            .todoFold([.awaitDeparture, .meetUp, .startRun]),
        ])
    }

    /// ② 通电话：已完成只有 1 步 ⇒ 单列不收（阈值是 2，改成 1 这条会红）。
    func testIntroCallKeepsASingleDoneStepUnfolded() {
        let rows = BlindOrderTimelineLayout.rows(input(.current(.arrangeMeetup)))
        XCTAssertEqual(rows, [
            .done(.matchVolunteer, detail: nil),
            .current(.arrangeMeetup, detail: nil),
            .next(.awaitDeparture),
            .todoFold([.meetUp, .startRun]),
        ])
    }

    /// ③ 确认安排单：下一步也并进「还有 3 步」，好让安排单五项首屏完整可见（v7 第 11 条 D）。
    func testPlanReviewFoldsTheNextStepToo() {
        let rows = BlindOrderTimelineLayout.rows(input(.current(.arrangeMeetup), showsNextStep: false))
        XCTAssertEqual(rows, [
            .done(.matchVolunteer, detail: nil),
            .current(.arrangeMeetup, detail: nil),
            .todoFold([.awaitDeparture, .meetUp, .startRun]),
        ])
    }

    /// ④ 已约好：已完成 2 步收起（阈值改成 3 这条会红）；下一步后面只剩 1 步 ⇒ 单列（阈值改成 1 会红）。
    func testBookedFoldsTwoDoneStepsAndListsTheLastOne() {
        let rows = BlindOrderTimelineLayout.rows(input(.current(.awaitDeparture)))
        XCTAssertEqual(rows, [
            .doneFold([.matchVolunteer, .arrangeMeetup]),
            .current(.awaitDeparture, detail: nil),
            .next(.meetUp),
            .todo(.startRun),
        ])
    }

    // MARK: - 就地展开

    func testExpandingFoldsListsEveryStep() {
        let rows = BlindOrderTimelineLayout.rows(
            input(.current(.awaitDeparture)),
            pastExpanded: true,
            futureExpanded: true
        )
        XCTAssertEqual(rows, [
            .done(.matchVolunteer, detail: nil),
            .done(.arrangeMeetup, detail: nil),
            .current(.awaitDeparture, detail: nil),
            .next(.meetUp),
            .todo(.startRun),
        ])

        let matching = BlindOrderTimelineLayout.rows(input(.current(.matchVolunteer)), futureExpanded: true)
        XCTAssertEqual(matching, [
            .current(.matchVolunteer, detail: nil),
            .next(.arrangeMeetup),
            .todo(.awaitDeparture),
            .todo(.meetUp),
            .todo(.startRun),
        ])
    }

    /// #918 抽屉拉到顶：五步全部平铺，不写「下一步」。
    func testUnfoldedInputListsAllFiveStepsWithoutTheNextPrefix() {
        var unfolded = input(.current(.meetUp))
        unfolded.folds = false
        XCTAssertEqual(BlindOrderTimelineLayout.rows(unfolded), [
            .done(.matchVolunteer, detail: nil),
            .done(.arrangeMeetup, detail: nil),
            .done(.awaitDeparture, detail: nil),
            .current(.meetUp, detail: nil),
            .todo(.startRun),
        ])
    }

    /// 已完成页：没有当前步，五步全打勾（折叠时收成一行）。
    func testAllDoneHasNoCurrentStep() {
        XCTAssertEqual(
            BlindOrderTimelineLayout.rows(input(.allDone)),
            [.doneFold(BlindOrderTimelineStep.allCases)]
        )
        var unfolded = input(.allDone)
        unfolded.folds = false
        XCTAssertEqual(BlindOrderTimelineLayout.rows(unfolded).count, 5)
    }

    /// 终态（#946）：竖线停在中断那一步，后面的步一行都不画；之前完成的照常折叠。
    func testStoppedPositionEndsTheLineAtThatStep() {
        XCTAssertEqual(
            BlindOrderTimelineLayout.rows(input(.stopped(.awaitDeparture))),
            [.doneFold([.matchVolunteer, .arrangeMeetup]), .stopped(.awaitDeparture, detail: nil)]
        )
        XCTAssertEqual(
            BlindOrderTimelineLayout.rows(input(.stopped(.matchVolunteer))),
            [.stopped(.matchVolunteer, detail: nil)]
        )
        XCTAssertEqual(
            BlindOrderTimelineLayout.accessibilityLabel(for: .stopped(.awaitDeparture, detail: "你取消了订单")),
            "等出发，到这一步结束。你取消了订单"
        )
    }

    // MARK: - 读屏

    /// 稿原话「后面还有 3 步：等出发、在南门汇合、开跑」（第四步名见 `BlindOrderTimelineStep` 注释）。
    func testFoldRowsReadEveryHiddenStep() {
        XCTAssertEqual(
            BlindOrderTimelineLayout.accessibilityLabel(for: .todoFold([.awaitDeparture, .meetUp, .startRun])),
            "后面还有 3 步：等出发、在集合点汇合、开跑"
        )
        XCTAssertEqual(
            BlindOrderTimelineLayout.accessibilityLabel(for: .doneFold([.matchVolunteer, .arrangeMeetup])),
            "已完成 2 步：匹配陪跑员、商量见面安排"
        )
        XCTAssertEqual(BlindOrderTimelineLayout.foldAccessibilityHint, "点两下展开")
    }

    func testCurrentRowSaysItIsTheCurrentStepAndReadsTheDetail() {
        XCTAssertEqual(
            BlindOrderTimelineLayout.accessibilityLabel(for: .current(.awaitDeparture, detail: "开跑前 1 小时会提醒你出门")),
            "等出发，当前这一步。开跑前 1 小时会提醒你出门"
        )
        XCTAssertEqual(BlindOrderTimelineLayout.accessibilityLabel(for: .next(.meetUp)), "下一步，在集合点汇合")
        XCTAssertEqual(BlindOrderTimelineLayout.accessibilityLabel(for: .done(.matchVolunteer, detail: nil)), "已匹配陪跑员")
    }

    // MARK: - Helpers

    private func input(
        _ position: BlindOrderTimelinePosition,
        details: [BlindOrderTimelineStep: String] = [:],
        showsNextStep: Bool = true
    ) -> BlindOrderTimelineInput {
        BlindOrderTimelineInput(position: position, details: details, showsNextStep: showsNextStep)
    }
}
