import XCTest
@testable import blindRun

/// 待回复邀请对账的并发闸（`AppState.restorePendingInvites` 用的 `CoalescedRerun`）。
///
/// 要守的是「跑着的时候又被触发 ⇒ 这一次结束后**再跑一次**」：在跑的那次可能是触发之前发出的，
/// 快照早于后到的调用想看到的变化（例如断线前发出、重连时还没回来）。只合并不补跑，那次变化就丢了。
@MainActor
final class CoalescedRerunTests: XCTestCase {

    func testTriggeringWhileRunningRunsOnceMoreAfterwards() async {
        let gate = CoalescedRerun()
        var runs = 0
        var release: CheckedContinuation<Void, Never>?

        let first = Task {
            await gate.run {
                runs += 1
                if runs == 1 { await withCheckedContinuation { release = $0 } }
            }
        }
        while release == nil { await Task.yield() }
        let second = Task { await gate.run { XCTFail("后到的调用不该另起一份工作，只请在跑的那份补跑一次") } }
        await Task.yield()

        release?.resume()
        await first.value
        await second.value

        XCTAssertEqual(runs, 2, "跑着时又被触发，结束后要再跑一次")
    }

    func testASingleTriggerRunsOnce() async {
        let gate = CoalescedRerun()
        var runs = 0
        await gate.run { runs += 1 }
        await gate.run { runs += 1 }
        XCTAssertEqual(runs, 2, "前一次跑完之后的调用各跑各的，不合并")
    }
}
