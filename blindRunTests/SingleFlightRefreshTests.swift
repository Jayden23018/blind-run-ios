import XCTest
@testable import blindRun

/// `SingleFlightRefresh` 的行为（#859）。不依赖 `AppState`，只看模块自己。
@MainActor
final class SingleFlightRefreshTests: XCTestCase {
    private var phases: [HomeRefreshPhase] = []

    private func makeRefresh() -> SingleFlightRefresh {
        phases = []
        return SingleFlightRefresh { [weak self] phase in
            self?.phases.append(phase)
        }
    }

    func testConcurrentCallsShareOneRunAndOnlyTheFirstBegins() async {
        let refresh = makeRefresh()
        let gate = Gate()
        let box = Box()

        let first = Task {
            await refresh.run { _ in box.beginCount += 1 } work: { _ in
                box.workCount += 1
                await gate.wait()
            }
        }
        await Self.yieldUntil { box.workCount == 1 }
        let second = Task {
            await refresh.run { _ in box.beginCount += 1 } work: { _ in box.workCount += 1 }
        }
        // 让第二个调用真的挂进等待队列，再开闸。
        for _ in 0..<20 { await Task.yield() }
        gate.open()

        let firstOutcome = await first.value
        let secondOutcome = await second.value
        XCTAssertEqual(firstOutcome, .finished)
        XCTAssertEqual(secondOutcome, .joined)
        XCTAssertEqual(box.beginCount, 1)
        XCTAssertEqual(box.workCount, 1)
        XCTAssertFalse(refresh.isRunning)
        XCTAssertEqual(phases.count, 2)
        XCTAssertEqual(phases.last, .idle)
    }

    func testCancelledWaiterReturnsAtOnceWhileInitiatorKeepsRunning() async {
        let refresh = makeRefresh()
        let gate = Gate()
        let box = Box()

        let initiator = Task {
            await refresh.run { _ in } work: { _ in
                box.workStarted = true
                await gate.wait()
            }
        }
        await Self.yieldUntil { box.workStarted }
        let waiter = Task {
            await refresh.run { _ in } work: { _ in XCTFail("A waiter must not run work") }
        }
        // 等它真的挂进等待队列再取消；否则测的是「没等就返回」。
        for _ in 0..<20 { await Task.yield() }
        waiter.cancel()

        let waiterOutcome = await waiter.value
        XCTAssertEqual(waiterOutcome, .joined)
        XCTAssertTrue(refresh.isRunning, "Cancelling a waiter must not stop the shared run")

        gate.open()
        let initiatorOutcome = await initiator.value
        XCTAssertEqual(initiatorOutcome, .finished)
    }

    func testCancelledInitiatorReturnsCancelledAndSkipsWrites() async {
        let refresh = makeRefresh()
        let box = Box()

        let initiator = Task {
            await refresh.run { _ in } work: { ticket in
                box.ticket = ticket
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard refresh.isCurrent(ticket), !Task.isCancelled else { return }
                box.wroteContent = true
            }
        }
        await Self.yieldUntil { box.ticket != nil }
        initiator.cancel()

        let outcome = await initiator.value
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertFalse(box.wroteContent)
        XCTAssertFalse(refresh.isRunning)
        XCTAssertEqual(phases.last, .idle)
        if let capturedTicket = box.ticket {
            XCTAssertFalse(refresh.isCurrent(capturedTicket))
        }
    }

    func testTicketIsStaleOnceItsRunHasFinished() async {
        let refresh = makeRefresh()
        let box = Box()

        let outcome = await refresh.run { ticket in box.ticket = ticket } work: { ticket in
            box.currentDuringWork = refresh.isCurrent(ticket)
        }
        let secondOutcome = await refresh.run { _ in } work: { _ in }

        XCTAssertEqual(outcome, .finished)
        XCTAssertEqual(secondOutcome, .finished)
        XCTAssertTrue(box.currentDuringWork)
        guard let firstTicket = box.ticket else { return XCTFail("begin was not called") }
        XCTAssertFalse(refresh.isCurrent(firstTicket))
    }

    func testCancelMidFlightStopsTheRunAndReleasesWaiters() async {
        let refresh = makeRefresh()
        let box = Box()

        let initiator = Task {
            await refresh.run { _ in } work: { ticket in
                box.ticket = ticket
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard refresh.isCurrent(ticket), !Task.isCancelled else { return }
                box.wroteContent = true
            }
        }
        await Self.yieldUntil { box.ticket != nil }
        let waiter = Task {
            await refresh.run { _ in } work: { _ in XCTFail("A waiter must not run work") }
        }
        for _ in 0..<20 { await Task.yield() }

        refresh.cancel()
        XCTAssertFalse(refresh.isRunning)
        if let capturedTicket = box.ticket {
            XCTAssertFalse(refresh.isCurrent(capturedTicket))
        }

        let initiatorOutcome = await initiator.value
        let waiterOutcome = await waiter.value
        XCTAssertEqual(initiatorOutcome, .cancelled)
        XCTAssertEqual(waiterOutcome, .joined)
        XCTAssertFalse(box.wroteContent)
        XCTAssertEqual(phases.last, .idle)
    }

    func testCancelWhileIdleDoesNothing() {
        let refresh = makeRefresh()
        refresh.cancel()
        XCTAssertFalse(refresh.isRunning)
        XCTAssertTrue(phases.isEmpty)
    }

    // MARK: - Helpers

    private static func yieldUntil(
        timeout: TimeInterval = 2,
        _ condition: @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            await Task.yield()
        }
    }

    /// 闭包里要改的计数与标志放这里，避免在并发闭包里改捕获的局部变量。
    @MainActor
    private final class Box {
        var beginCount = 0
        var workCount = 0
        var workStarted = false
        var currentDuringWork = false
        var wroteContent = false
        var ticket: RefreshTicket?
    }

    /// 一道手动开的闸：`wait()` 挂起，`open()` 一次放行所有人。不响应取消。
    @MainActor
    private final class Gate {
        private var continuations: [CheckedContinuation<Void, Never>] = []
        private var isOpen = false

        var waiterCount: Int { continuations.count }

        func wait() async {
            guard !isOpen else { return }
            await withCheckedContinuation { continuations.append($0) }
        }

        func open() {
            isOpen = true
            let pending = continuations
            continuations.removeAll()
            pending.forEach { $0.resume() }
        }
    }
}
