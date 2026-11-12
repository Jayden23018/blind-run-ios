import XCTest
@testable import blindRun

/// 陪跑员 ③ 等跑者确认的等待效果（#962 第 6 项，稿 `docs/ui/mockups/volunteer-order-v7-parity-20261112/` 第 1 条）。
///
/// 动画只有真机看得见；这里钉两件不开真机也能判对错的事：说明行怎么写，以及什么时候该放那一秒的过渡。
final class VolunteerIntroCallAwaitingTests: XCTestCase {

    private let submitted = Date(timeIntervalSince1970: 1_794_000_000)
    private var submittedAt: String { DateFormatter.aidRunBackendLocalDateTime.string(from: submitted) }

    private func at(minutes: Double) throws -> Date {
        try XCTUnwrap(submittedAt.backendTimestamp).addingTimeInterval(minutes * 60)
    }

    // MARK: - 说明行

    /// 一小时内写分钟，过了一小时写「X 小时 Y 分钟」（与盲人端 ① 同一个格式器），后半句恒在。
    func testDetailCountsMinutesThenHoursAndMinutes() throws {
        XCTAssertEqual(
            VolunteerIntroCallAwaitingCopy.detail(submittedAt: submittedAt, now: try at(minutes: 12)),
            "已等 12 分钟 · 跑者确认后即完成约定"
        )
        XCTAssertEqual(
            VolunteerIntroCallAwaitingCopy.detail(submittedAt: submittedAt, now: try at(minutes: 65)),
            "已等 1 小时 5 分钟 · 跑者确认后即完成约定"
        )
    }

    /// 拿不到 / 读不懂 `submittedAt`、不到 1 分钟、设备时钟偏到提交之前：只留后半句，不写「已等 0 分钟」。
    func testDetailKeepsOnlyTheTailWhenTheWaitIsUnknownOrUnderAMinute() throws {
        let tail = VolunteerIntroCallAwaitingCopy.confirmTail
        XCTAssertEqual(VolunteerIntroCallAwaitingCopy.detail(submittedAt: nil, now: submitted), tail)
        XCTAssertEqual(VolunteerIntroCallAwaitingCopy.detail(submittedAt: "不是时间", now: submitted), tail)
        XCTAssertEqual(VolunteerIntroCallAwaitingCopy.detail(submittedAt: submittedAt, now: try at(minutes: 0.9)), tail)
        XCTAssertEqual(VolunteerIntroCallAwaitingCopy.detail(submittedAt: submittedAt, now: try at(minutes: -5)), tail)
        // 边界那一侧：刚满 1 分钟就开始写。
        XCTAssertEqual(
            VolunteerIntroCallAwaitingCopy.detail(submittedAt: submittedAt, now: try at(minutes: 1)),
            "已等 1 分钟 · \(tail)"
        )
    }

    /// 读屏念稿里那句原话；拿不到时长时省掉中间那段，不念「已等 0 分钟」。
    func testSpokenCurrentStepMatchesTheMockupWording() throws {
        XCTAssertEqual(
            VolunteerIntroCallAwaitingCopy.spokenCurrentStep(submittedAt: submittedAt, now: try at(minutes: 12)),
            "商量见面安排，已等 12 分钟，进行中"
        )
        XCTAssertEqual(
            VolunteerIntroCallAwaitingCopy.spokenCurrentStep(submittedAt: nil, now: submitted),
            "商量见面安排，进行中"
        )
    }

    // MARK: - 什么时候放过渡

    /// 只有「一直看着 ③，然后跑者确认了」才放。
    func testTransitionPlaysOnlyWhenWatchingAwaitingConfirmationThenMatched() {
        XCTAssertTrue(VolunteerMatchedTransition.shouldPlay(
            previousStep: .awaitingRunnerConfirmation, outcome: .matched, watchedContinuously: true
        ))
    }

    /// 人不在这一页 / 进过后台：回来直接显示 ④，不补放。
    func testTransitionDoesNotReplayAfterTheAppWasAway() {
        XCTAssertFalse(VolunteerMatchedTransition.shouldPlay(
            previousStep: .awaitingRunnerConfirmation, outcome: .matched, watchedContinuously: false
        ))
    }

    /// 没约成不播、不打叉（AGENTS §5）；没看过 ③（冷启动、还在等来电）也不播。
    func testTransitionSkipsClosedRoundsAndScreensOtherThanAwaitingConfirmation() {
        XCTAssertFalse(VolunteerMatchedTransition.shouldPlay(
            previousStep: .awaitingRunnerConfirmation, outcome: .closed, watchedContinuously: true
        ))
        XCTAssertFalse(VolunteerMatchedTransition.shouldPlay(
            previousStep: nil, outcome: .matched, watchedContinuously: true
        ))
        XCTAssertFalse(VolunteerMatchedTransition.shouldPlay(
            previousStep: .awaitingCall, outcome: .matched, watchedContinuously: true
        ))
    }
}
