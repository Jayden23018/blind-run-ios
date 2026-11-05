import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class MockSpeechAudioSession: SpeechAudioSessionManaging {
    enum FailurePoint {
        case none
        case deactivate
        case playbackCategory
        case playbackActivation
    }

    var isInputAvailable = true
    var inputNumberOfChannels = 1
    var sampleRate = 44_100.0
    var operations: [String] = []
    var failurePoint: FailurePoint = .none

    func requestRecordPermission(_ response: @escaping (Bool) -> Void) {
        response(true)
    }

    func configureRecordingCategory() throws {
        operations.append("configureRecording")
    }

    func activateRecording() throws {
        operations.append("activateRecording")
    }

    func deactivateRecording() throws {
        operations.append("deactivateRecording")
        if failurePoint == .deactivate { throw MockAudioSessionError.expected }
    }

    func configurePlaybackCategory() throws {
        operations.append("configurePlayback")
        if failurePoint == .playbackCategory { throw MockAudioSessionError.expected }
    }

    func activatePlayback() throws {
        operations.append("activatePlayback")
        if failurePoint == .playbackActivation { throw MockAudioSessionError.expected }
    }
}

enum MockAudioSessionError: Error {
    case expected
}

final class FailingAPIClient: APIClientProtocol, @unchecked Sendable {
    private let error: Error

    init(error: Error) {
        self.error = error
    }

    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        throw error
    }

    func upload<T: Decodable>(
        path: String,
        query: [String: String]?,
        fields: [String: String]?,
        files: [MultipartFile],
        requiresAuth: Bool
    ) async throws -> T {
        throw error
    }
}

final class CancellationSuspendingAPIClient: APIClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var cancellations = 0
    private var requestCounts: [String: Int] = [:]
    private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []

    var cancellationCount: Int {
        lock.withLock { cancellations }
    }

    func requestCount(for path: String) -> Int {
        lock.withLock { requestCounts[path, default: 0] }
    }

    /// Suspends until an in-flight request has actually observed cancellation.
    ///
    /// `HomeLoadCoordinator` intentionally resumes its caller the moment the
    /// deadline fires and never awaits the losing operation, so the cancelled
    /// request records itself on a different task. Asserting on
    /// `cancellationCount` straight after the deadline therefore races the
    /// scheduler. Awaiting this signal makes the assertion causal instead of
    /// wall-clock dependent; it resumes immediately when a cancellation has
    /// already been recorded.
    func awaitCancellation() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if cancellations > 0 {
                lock.unlock()
                continuation.resume()
                return
            }
            cancellationWaiters.append(continuation)
            lock.unlock()
        }
    }

    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        lock.withLock { requestCounts[path, default: 0] += 1 }
        do {
            try await Task.sleep(nanoseconds: 60_000_000_000)
        } catch {
            lock.lock()
            cancellations += 1
            let waiters = cancellationWaiters
            cancellationWaiters.removeAll()
            lock.unlock()
            for waiter in waiters {
                waiter.resume()
            }
            throw error
        }
        throw APIError.invalidURL
    }

    func upload<T: Decodable>(
        path: String,
        query: [String: String]?,
        fields: [String: String]?,
        files: [MultipartFile],
        requiresAuth: Bool
    ) async throws -> T {
        throw APIError.invalidURL
    }
}

/// 志愿者状态流转 + 确认查询的**罐装值装配台**。
///
/// 迁移前这是一个 `APIClientProtocol` 传输桩（按路径后缀 `hasSuffix("/en-route")` 分派）。
/// 现在它只做一件事：**在 init 里一次性把罐装值塞进 `FakeOrderService`**，
/// 之后每次调用都不再有任何判断 —— 判断留在这里的构造参数上，不在替身里面。
///
/// 用法：`AppState(orders: fixture.service)`。
final class TransitionConfirmationFixture: @unchecked Sendable {
    enum Confirmation {
        case response
        case suspended
        case failure(APIError)
    }

    let service = FakeOrderService()

    private let lock = NSLock()
    private var releaseRequested = false
    private var continuations: [UnsafeContinuation<Void, Never>] = []

    init(
        postError: APIError? = nil,
        confirmation: Confirmation,
        order: OrderDetailResponse
    ) {
        let transitionResult: Result<Void, Error> = postError.map { .failure($0) } ?? .success(())
        service.enRouteResult = transitionResult
        service.arrivedResult = transitionResult
        service.startServiceResult = transitionResult
        service.finishResult = transitionResult
        service.cancelResult = transitionResult.map { CancelOrderResponse(success: true, countedAsLateCancel: false) }
        service.respondResult = transitionResult

        switch confirmation {
        case .response:
            service.orderDetailResult = .success(order)
        case .failure(let error):
            service.orderDetailResult = .failure(error)
        case .suspended:
            service.orderDetailResult = .success(order)
            service.orderDetailGate = { [weak self] in await self?.waitUntilReleased() }
        }
    }

    /// 迁移前是「打到 `/en-route` 或 `/arrived` 的 POST 次数」。现在按方法名统计，
    /// 覆盖面更宽一点（多算了 start-service / finish / cancel / respond），
    /// 而每条用例里只会有其中一种被调用，计数含义不变。
    var postRequestCount: Int {
        ["enRoute(orderId:)", "arrived(orderId:)", "startService(orderId:)",
         "finish(orderId:)", "cancel(orderId:)", "respond(orderId:action:)"]
            .reduce(0) { $0 + service.callCount($1) }
    }

    var getRequestCount: Int {
        service.callCount("orderDetail(orderId:)")
    }

    func releaseSuspendedRequests() {
        let pending = lock.withLock { () -> [UnsafeContinuation<Void, Never>] in
            releaseRequested = true
            defer { continuations.removeAll() }
            return continuations
        }
        pending.forEach { $0.resume() }
    }

    private func waitUntilReleased() async {
        await withUnsafeContinuation { continuation in
            let shouldResume = lock.withLock { () -> Bool in
                if releaseRequested { return true }
                continuations.append(continuation)
                return false
            }
            if shouldResume { continuation.resume() }
        }
    }
}

@MainActor
final class FakePlaceSearchProvider: PlaceSearchProviding {
    var lastErrorMessage: String?
    var searchKeywords: [String] = []
    private let results: [ResolvedPlace]
    private var reverseGeocodeResults: [ResolvedPlace]

    init(
        results: [ResolvedPlace],
        lastErrorMessage: String? = nil,
        reverseGeocodeResults: [ResolvedPlace] = []
    ) {
        self.results = results
        self.lastErrorMessage = lastErrorMessage
        self.reverseGeocodeResults = reverseGeocodeResults
    }

    func reverseGeocode(coordinate: CLLocationCoordinate2D) async -> ResolvedPlace? {
        guard !reverseGeocodeResults.isEmpty else { return nil }
        return reverseGeocodeResults.removeFirst()
    }

    func searchPlaces(keyword: String, near coordinate: CLLocationCoordinate2D?) async -> [ResolvedPlace] {
        searchKeywords.append(keyword)
        return results
    }
}

final class AuthLifecycleAPIClient: APIClientProtocol, @unchecked Sendable {
    let meResult: Result<CurrentUserResponse, APIError>?
    let logoutResult: Result<LogoutResponse, APIError>
    let registrationRateLimitSeconds: Int?
    let mineOrders: PagedOrderResponse?

    init(
        meResult: Result<CurrentUserResponse, APIError>? = nil,
        logoutResult: Result<LogoutResponse, APIError> = .success(LogoutResponse(success: true, message: nil)),
        registrationRateLimitSeconds: Int? = nil,
        mineOrders: PagedOrderResponse? = nil
    ) {
        self.meResult = meResult
        self.logoutResult = logoutResult
        self.registrationRateLimitSeconds = registrationRateLimitSeconds
        self.mineOrders = mineOrders
    }

    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        if method == .get, path == "/api/auth/me", let meResult {
            let response = try meResult.get()
            guard let typed = response as? T else { throw APIError.decodingError(TestError.typeMismatch) }
            return typed
        }
        if method == .post, path == "/api/auth/logout" {
            let response = try logoutResult.get()
            guard let typed = response as? T else { throw APIError.decodingError(TestError.typeMismatch) }
            return typed
        }
        if method == .post, path == "/api/volunteer/registration/step1",
           let registrationRateLimitSeconds {
            throw APIError.rateLimited(RateLimitInfo(
                message: "注册过于频繁",
                retryAfterSeconds: registrationRateLimitSeconds
            ))
        }
        if method == .get, path == "/api/orders/mine", let mineOrders {
            guard let typed = mineOrders as? T else { throw APIError.decodingError(TestError.typeMismatch) }
            return typed
        }
        throw APIError.invalidURL
    }

    func upload<T: Decodable>(
        path: String,
        query: [String: String]?,
        fields: [String: String]?,
        files: [MultipartFile],
        requiresAuth: Bool
    ) async throws -> T {
        throw APIError.invalidURL
    }

    private enum TestError: Error { case typeMismatch }
}
