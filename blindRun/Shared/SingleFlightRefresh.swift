import Foundation

/// 一次刷新的凭据。`work` 里每次写状态前用 `SingleFlightRefresh.isCurrent(_:)` 问它还算不算数。
struct RefreshTicket: Equatable, Sendable {
    let id: UUID
}

enum RefreshOutcome: Equatable, Sendable {
    /// 本次是发起方，且正常跑完。只有这一种结果才做收尾。
    case finished
    /// 已经有一次在跑，本次只是等它（或等到一半自己被取消）。参数丢弃，不补跑。
    case joined
    /// 本次是发起方，但被取消了：调用方的 Task 被取消，或中途有人调了 `cancel()`。
    case cancelled
}

/// 同一时间只跑一个刷新（#859）。两端首页的整页刷新与陪跑员端派单摘要刷新共用。
///
/// 行为：
/// - 已经有一次在跑时，后到的调用只等它，返回 `.joined`；先到的参数说了算。
/// - 等着的一方被取消，只有它自己立刻返回，正在跑的那次照常跑完。
/// - 发起方被取消，或有人调 `cancel()`，整次刷新停下，发起方返回 `.cancelled`。
///   清理在发起方自己的 Task 里同步做完，不另排队 —— 旧写法把清理放进另一个 `Task`，
///   外层判断先通过，被取消的请求照样写了「已加载」。
///
/// 和 `CoalescedRerun` 不是一回事：那个会补跑、没有取消、没有请求号。
@MainActor
final class SingleFlightRefresh {
    private let onPhaseChange: @MainActor (HomeRefreshPhase) -> Void
    private var task: Task<Void, Never>?
    private var current: RefreshTicket?
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    init(onPhaseChange: @escaping @MainActor (HomeRefreshPhase) -> Void) {
        self.onPhaseChange = onPhaseChange
    }

    var isRunning: Bool { current != nil }

    /// - Parameters:
    ///   - begin: 只在真正发起时同步调用一次（标「加载中」、记诊断事件）。合并进来的调用不调它。
    ///   - work: 刷新本体。写状态前先判 `isCurrent(ticket)` 与 `Task.isCancelled`。
    func run(
        begin: @MainActor (RefreshTicket) -> Void,
        work: @escaping @MainActor (RefreshTicket) async -> Void
    ) async -> RefreshOutcome {
        // 发起方已被取消、只是还没轮到它收尾：这次已经作废，不让新调用并进去白等。
        // 它让位后，旧发起方回来时 `current` 已不是它，什么都不碰。
        if let task, task.isCancelled {
            settle()
        }
        if isRunning {
            await join()
            return .joined
        }

        let ticket = RefreshTicket(id: UUID())
        current = ticket
        onPhaseChange(.refreshing(requestID: ticket.id))
        begin(ticket)

        let workTask = Task { @MainActor in
            await work(ticket)
        }
        task = workTask

        await withTaskCancellationHandler {
            await workTask.value
        } onCancel: {
            // 同步打上取消标记：后到的 `run` 靠 `task.isCancelled` 认出这次已作废。
            workTask.cancel()
        }

        // 中途被 `cancel()` 停掉（之后可能已经有新的一次在跑）：什么都不碰。
        guard current == ticket else { return .cancelled }
        let wasCancelled = Task.isCancelled
        settle()
        return wasCancelled ? .cancelled : .finished
    }

    /// 有一次在跑就等它结束；自己被取消则立刻返回。没在跑时立即返回。
    func join() async {
        guard isRunning, !Task.isCancelled else { return }
        let waiterID = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if Task.isCancelled || !isRunning {
                    continuation.resume()
                } else {
                    waiters[waiterID] = continuation
                }
            }
        } onCancel: {
            // 等待方不写任何状态，跳回主线程再放行即可。
            Task { @MainActor [weak self] in
                self?.resumeWaiter(waiterID)
            }
        }
    }

    func isCurrent(_ ticket: RefreshTicket) -> Bool {
        current == ticket
    }

    /// 停掉正在跑的那次。没在跑时什么都不做。
    func cancel() {
        guard isRunning else { return }
        task?.cancel()
        settle()
    }

    private func settle() {
        task = nil
        current = nil
        onPhaseChange(.idle)
        let pending = waiters
        waiters.removeAll()
        for continuation in pending.values {
            continuation.resume()
        }
    }

    private func resumeWaiter(_ waiterID: UUID) {
        waiters.removeValue(forKey: waiterID)?.resume()
    }
}
