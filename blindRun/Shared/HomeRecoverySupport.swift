import Foundation
import OSLog

enum HomeLoadCoordinatorError: Error, Equatable, Sendable {
    case timedOut
}

enum HomeRefreshPhase: Equatable {
    case idle
    case refreshing(requestID: UUID)

    var isRefreshing: Bool {
        if case .refreshing = self { return true }
        return false
    }
}

enum ClientFlowDiagnostics {
    nonisolated private static let logger = Logger(
        subsystem: "com.jerry.aidrun",
        category: "client-flow"
    )
    nonisolated private static let lock = NSLock()
    nonisolated(unsafe) private static var phase = "idle"

    nonisolated static func record(event: String, operation: String) {
        lock.lock()
        phase = "\(operation).\(event)"
        lock.unlock()
        logger.info(
            "event=\(event, privacy: .public) operation=\(operation, privacy: .public)"
        )
    }

    nonisolated static func recordDuration(
        operation: String,
        result: String,
        startedAt: ContinuousClock.Instant
    ) {
        let duration = startedAt.duration(to: .now)
        let milliseconds = max(
            0,
            Int(duration.components.seconds * 1_000) +
                Int(duration.components.attoseconds / 1_000_000_000_000_000)
        )
        lock.lock()
        phase = "\(operation).\(result)"
        lock.unlock()
        logger.info(
            "operation=\(operation, privacy: .public) result=\(result, privacy: .public) duration_ms=\(milliseconds, privacy: .public)"
        )
    }

    nonisolated static var currentPhase: String {
        lock.lock()
        let value = phase
        lock.unlock()
        return value
    }
}

enum HomeLoadPolicy {
    nonisolated static var defaultTimeout: TimeInterval {
        #if DEBUG
        if let rawValue = ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_HOME_LOAD_TIMEOUT"],
           let timeout = TimeInterval(rawValue) {
            return max(0.05, timeout)
        }
        #endif
        return 20
    }
}

enum HomeLoadCoordinator {
    nonisolated static func run<T: Sendable>(
        timeout: TimeInterval,
        operationName: String = "home",
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let boundedTimeout = max(0.05, timeout)
        let race = HomeLoadRace(operationName: operationName)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                race.start(
                    timeout: boundedTimeout,
                    terminalHandler: { terminal in
                        switch terminal {
                        case .timedOut:
                            continuation.resume(throwing: HomeLoadCoordinatorError.timedOut)
                        case .cancelled:
                            continuation.resume(throwing: CancellationError())
                        }
                    },
                    operation: {
                        do {
                            let value = try await operation()
                            if race.claimOperationResult() {
                                continuation.resume(returning: value)
                            }
                        } catch is CancellationError {
                            race.cancel()
                        } catch {
                            if race.claimOperationResult() {
                                continuation.resume(throwing: error)
                            }
                        }
                    }
                )
            }
        } onCancel: {
            race.cancel()
        }
    }
}

/// A timeout race that does not await a losing operation after the caller has
/// received a deadline or cancellation result. This is intentionally
/// unstructured: a third-party or test client that ignores cooperative
/// cancellation must never keep a home screen in its loading state.
private enum HomeLoadTerminal: Sendable {
    case timedOut
    case cancelled
}

/// This state holder is deliberately non-generic. Xcode 26.5's Swift 6.3.3
/// optimizer crashes while inlining the synthesized destructor of the generic
/// variant in optimized Demo/Release builds.
private final class HomeLoadRace: @unchecked Sendable {
    typealias TerminalHandler = @Sendable (HomeLoadTerminal) -> Void

    private enum Completion {
        case timedOut
        case cancelled
    }

    private let lock = NSLock()
    private let logger = Logger(subsystem: "com.jerry.aidrun", category: "home-load")
    private let operationName: String
    nonisolated(unsafe) private var isCompleted = false
    nonisolated(unsafe) private var earlyTerminal: HomeLoadTerminal?
    nonisolated(unsafe) private var terminalHandler: TerminalHandler?
    nonisolated(unsafe) private var operationTask: Task<Void, Never>?
    nonisolated(unsafe) private var timeoutTask: Task<Void, Never>?

    nonisolated init(operationName: String) {
        self.operationName = operationName
    }

    nonisolated func start(
        timeout: TimeInterval,
        terminalHandler: @escaping TerminalHandler,
        operation: @escaping @Sendable () async -> Void
    ) {
        lock.lock()
        if isCompleted {
            let earlyTerminal = self.earlyTerminal ?? .cancelled
            lock.unlock()
            terminalHandler(earlyTerminal)
            return
        }
        self.terminalHandler = terminalHandler
        lock.unlock()

        let operationTask = Task.detached(priority: .userInitiated) {
            await operation()
        }
        let timeoutTask = Task.detached(priority: .userInitiated) { [self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            } catch {
                return
            }
            finish(.timedOut)
        }
        install(operationTask: operationTask, timeoutTask: timeoutTask)
    }

    nonisolated func cancel() {
        finish(.cancelled)
    }

    nonisolated func claimOperationResult() -> Bool {
        let operationTask: Task<Void, Never>?
        let timeoutTask: Task<Void, Never>?

        lock.lock()
        guard !isCompleted else {
            lock.unlock()
            logger.debug("late_result_discarded operation=\(self.operationName, privacy: .public)")
            return false
        }
        isCompleted = true
        operationTask = self.operationTask
        timeoutTask = self.timeoutTask
        terminalHandler = nil
        self.operationTask = nil
        self.timeoutTask = nil
        lock.unlock()

        operationTask?.cancel()
        timeoutTask?.cancel()
        return true
    }

    nonisolated private func install(
        operationTask: Task<Void, Never>,
        timeoutTask: Task<Void, Never>
    ) {
        lock.lock()
        if isCompleted {
            lock.unlock()
            operationTask.cancel()
            timeoutTask.cancel()
            return
        }
        self.operationTask = operationTask
        self.timeoutTask = timeoutTask
        lock.unlock()
    }

    nonisolated private func finish(_ completion: Completion) {
        let terminalHandler: TerminalHandler?
        let operationTask: Task<Void, Never>?
        let timeoutTask: Task<Void, Never>?
        let terminal: HomeLoadTerminal

        lock.lock()
        guard !isCompleted else {
            lock.unlock()
            logger.debug("late_result_discarded operation=\(self.operationName, privacy: .public)")
            return
        }
        isCompleted = true
        switch completion {
        case .timedOut:
            terminal = .timedOut
        case .cancelled:
            terminal = .cancelled
        }
        earlyTerminal = terminal
        terminalHandler = self.terminalHandler
        operationTask = self.operationTask
        timeoutTask = self.timeoutTask
        self.terminalHandler = nil
        self.operationTask = nil
        self.timeoutTask = nil
        lock.unlock()

        operationTask?.cancel()
        timeoutTask?.cancel()

        switch completion {
        case .timedOut:
            logger.error("deadline_exceeded operation=\(self.operationName, privacy: .public)")
        case .cancelled:
            logger.debug("cancelled operation=\(self.operationName, privacy: .public)")
        }
        terminalHandler?(terminal)
    }
}
