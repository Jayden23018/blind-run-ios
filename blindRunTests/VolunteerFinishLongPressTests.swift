import XCTest
@testable import blindRun

/// 陪跑员端「长按 2 秒结束陪跑」的纯逻辑。
///
/// 手势、震动、环形本身在单测里够不着（`XCUIElement.tap()` 注入的是物理触摸，
/// 也没有公开 API 能执行无障碍动作），所以这里钉的是**手势之外的全部判据**：
/// 时长与屏幕上印的数字是不是同一个、读秒会不会往回跳、渐强震动会不会漏拍或重拍。
/// 行为那一半走 `blindRunUITests` 里的 `press(forDuration:)`，两条路调的是同一个
/// `VolunteerFinishLongPressButton.fire()`。
final class VolunteerFinishLongPressTests: XCTestCase {

    /// 「长按 2 秒」这句话里的 2 必须是手势真正用的那个 2。
    ///
    /// 这是本组最要紧的一条：分开写的那天，症状是「说好按 2 秒，按了 2 秒没反应」，
    /// 而屏幕上、读屏里、手势里三处都还各自自洽，没有任何东西会报警。
    func testEveryPrintedDurationComesFromTheGesturesOwnConstant() {
        let printed = String(format: "%g", VolunteerFinishLongPress.duration)

        XCTAssertTrue(
            VolunteerFinishLongPress.idleSubtitle.contains("长按 \(printed) 秒"),
            "副标题印的秒数必须由 duration 生成：\(VolunteerFinishLongPress.idleSubtitle)"
        )
        XCTAssertTrue(
            VolunteerFinishLongPress.accessibilityLabel.contains("长按 \(printed) 秒"),
            "读屏标签印的秒数必须由 duration 生成：\(VolunteerFinishLongPress.accessibilityLabel)"
        )
        XCTAssertTrue(
            VolunteerFinishLongPress.activationGuidance.contains(printed),
            "双击时念的那句也要用同一个数字：\(VolunteerFinishLongPress.activationGuidance)"
        )
        // 设计包 `状态清单.md` §11 的参数：2 秒、⌀40、线宽 3。
        XCTAssertEqual(VolunteerFinishLongPress.duration, 2)
        XCTAssertEqual(VolunteerFinishLongPress.ringDiameter, 40)
        XCTAssertEqual(VolunteerFinishLongPress.ringLineWidth, 3)
    }

    /// 按钮上印的词与读屏那条自定义动作必须同名 —— 视图里两处都读 `title`。
    func testCustomActionUsesExactlyTheVisibleTitle() {
        XCTAssertEqual(VolunteerFinishLongPress.title, "结束陪跑")
        XCTAssertEqual(
            VolunteerServiceActions.actionKinds(for: .inProgress).map(\.title).first,
            VolunteerFinishLongPress.title
        )
        XCTAssertTrue(VolunteerFinishLongPress.accessibilityLabel.hasPrefix(VolunteerFinishLongPress.title))
    }

    func testRingProgressRunsFromZeroToFullAndClampsBothEnds() {
        XCTAssertEqual(VolunteerFinishLongPress.progress(elapsed: 0), 0)
        XCTAssertEqual(VolunteerFinishLongPress.progress(elapsed: 1), 0.5, accuracy: 0.0001)
        XCTAssertEqual(VolunteerFinishLongPress.progress(elapsed: 2), 1)
        // 触发与最后一次读秒之间差几毫秒，那几毫秒里环形不该越过满格。
        XCTAssertEqual(VolunteerFinishLongPress.progress(elapsed: 2.4), 1)
        XCTAssertEqual(VolunteerFinishLongPress.progress(elapsed: -1), 0)
    }

    /// 读秒印出来的必须是**真实剩余**的那一格，且只许单调下降。
    ///
    /// 🔴 `1.7` 与 `1.9` 是这条用例的真正目标，换成别的值就白写：
    /// 二进制里 `2 - 1.7 == 0.30000000000000004`、`2 - 1.9 == 0.10000000000000009`，
    /// 少了那个 1e-6 的修正就会向上取整成「0.4」「0.2」—— 比真实剩余多整整一格。
    ///
    /// ⚠️ 2026-09-16 这条用例第一版取的是 `elapsed: 0.3`，而 `2 - 0.3` 恰好是**精确的**
    /// 1.7 —— 把修正打回去它照样绿。挑不出两种实现之差的用例，绿灯是在替一个没验过的
    /// 实现背书；下面这两行是实测打回后**真的变红**的那两行。
    func testRemainingSecondsNeverTicksBackwards() {
        XCTAssertEqual(VolunteerFinishLongPress.remainingText(elapsed: 0), "2.0")
        XCTAssertEqual(VolunteerFinishLongPress.remainingText(elapsed: 1.7), "0.3")
        XCTAssertEqual(VolunteerFinishLongPress.remainingText(elapsed: 1.9), "0.1")
        XCTAssertEqual(VolunteerFinishLongPress.remainingText(elapsed: 1.2), "0.8")

        var previous = Double.greatestFiniteMagnitude
        for step in stride(from: 0.0, through: VolunteerFinishLongPress.duration, by: VolunteerFinishLongPress.tickInterval) {
            let shown = Double(VolunteerFinishLongPress.remainingText(elapsed: step))!
            XCTAssertLessThanOrEqual(shown, previous, "读秒在 \(step) 秒处回跳了：\(previous) → \(shown)")
            previous = shown
        }
    }

    /// 按住期间永远不显示 0.0：显示 0.0 而按钮还没结束，读起来像卡住了。
    func testRemainingSecondsNeverShowsZeroWhileStillHolding() {
        XCTAssertEqual(VolunteerFinishLongPress.remainingText(elapsed: 1.99), "0.1")
        XCTAssertEqual(VolunteerFinishLongPress.remainingText(elapsed: 2), "0.1")
        XCTAssertEqual(
            VolunteerFinishLongPress.holdingSubtitle(elapsed: 1.2),
            "按住不要松手 · 还有 0.8 秒"
        )
    }

    /// 渐强：强度逐拍上升，且**每一拍都严格落在 2 秒之前**。
    /// 踩在 2.0 上那一拍会和触发时的满强度黏成一下，渐强就没有终点。
    func testHapticRampRisesAndLeavesRoomBeforeTheTrigger() {
        let ramp = VolunteerFinishLongPress.hapticRamp
        XCTAssertGreaterThanOrEqual(ramp.count, 3, "两三拍不足以让人感觉到「在渐强」")
        XCTAssertEqual(ramp.first?.elapsed, 0, "第一拍要落在按下那一刻")

        for (previous, current) in zip(ramp, ramp.dropFirst()) {
            XCTAssertLessThan(previous.elapsed, current.elapsed)
            XCTAssertLessThan(previous.intensity, current.intensity)
        }
        for step in ramp {
            XCTAssertLessThan(step.elapsed, VolunteerFinishLongPress.duration)
            XCTAssertGreaterThan(step.intensity, 0)
            XCTAssertLessThanOrEqual(step.intensity, 1)
        }
        XCTAssertLessThan(
            ramp.last!.intensity,
            VolunteerFinishLongPress.triggerIntensity,
            "触发那一记要比渐强最后一拍更重，否则分不出「按够了」"
        )
    }

    /// 按满一次，每一档强度恰好震一次、顺序不乱。
    /// 漏拍与重拍在真机上都只是「手感怪」，这里是唯一能把它变成红灯的地方。
    func testOneHoldFiresEveryRampStepExactlyOnceInOrder() {
        var fired: [CGFloat] = []
        var previous: TimeInterval = -1
        var now: TimeInterval = 0
        while now <= VolunteerFinishLongPress.duration {
            if let intensity = VolunteerFinishLongPress.hapticIntensity(from: previous, to: now) {
                fired.append(intensity)
            }
            previous = now
            now += VolunteerFinishLongPress.tickInterval
        }

        XCTAssertEqual(fired, VolunteerFinishLongPress.hapticRamp.map(\.intensity))
    }

    /// 松手即取消：没跨过下一档就不许震，否则会在同一档上连震一片。
    func testHapticDoesNotRepeatWithinTheSameStep() {
        XCTAssertNil(VolunteerFinishLongPress.hapticIntensity(from: 0, to: 0.05))
        XCTAssertNil(VolunteerFinishLongPress.hapticIntensity(from: 0.05, to: 0.4))
        XCTAssertEqual(VolunteerFinishLongPress.hapticIntensity(from: -1, to: 0), 0.35)
    }
}
