import Foundation
import Combine

// MARK: - WebSocket Connection State

enum WSConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)

    var isDisconnected: Bool {
        if case .disconnected = self { return true }
        return false
    }

    var canSendOrQueueMessages: Bool {
        switch self {
        case .connecting, .connected:
            return true
        case .disconnected, .reconnecting:
            return false
        }
    }
}

// MARK: - WebSocket Role

enum WSRole: String, Sendable {
    case blind
    case volunteer

    var path: String {
        switch self {
        case .blind: return "/ws/blind"
        case .volunteer: return "/ws/volunteer"
        }
    }
}

enum WSDispatchDiagnosticStage: String, Sendable {
    case transportConnected
    case received
    case decodeFailed
    case retained
    case presented
}

/// In-memory, privacy-safe breadcrumbs for diagnosing volunteer dispatch delivery.
/// Never include tokens, coordinates, phone numbers, addresses, or message bodies.
struct WSDispatchDiagnostic: Sendable, Equatable {
    let stage: WSDispatchDiagnosticStage
    let role: WSRole?
    let connectionState: WSConnectionState
    let generation: UInt64
    let messageType: String?
    let orderID: Int64?
    let recordedAt: Date
    let failedField: String?

    func advancing(to stage: WSDispatchDiagnosticStage, recordedAt: Date = Date()) -> Self {
        Self(
            stage: stage,
            role: role,
            connectionState: connectionState,
            generation: generation,
            messageType: messageType,
            orderID: orderID,
            recordedAt: recordedAt,
            failedField: failedField
        )
    }

    var debugSummary: String {
        var values = [
            "stage=\(stage.rawValue)",
            "role=\(role?.rawValue ?? "none")",
            "state=\(connectionState)",
            "generation=\(generation)"
        ]
        if let messageType { values.append("type=\(messageType)") }
        if let orderID { values.append("orderId=\(orderID)") }
        if let failedField { values.append("failedField=\(failedField)") }
        return values.joined(separator: " ")
    }
}

private struct DecodedWebSocketMessage: Sendable {
    let event: WSIncomingEvent?
    let messageType: String?
    let dispatchOrderID: Int64?
    let failedField: String?
}

// MARK: - WebSocket Service

/// Manages WebSocket connection for real-time communication with the backend.
/// Supports auto-reconnect with exponential backoff and heartbeat for both roles.
@MainActor
final class WebSocketService: ObservableObject {
    @Published private(set) var connectionState: WSConnectionState = .disconnected
    @Published private(set) var dispatchDiagnostic: WSDispatchDiagnostic?

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession
    private var baseURL: URL?
    private var token: String?
    private var role: WSRole?

    private var reconnectTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var senderTask: Task<Void, Never>?
    private var reconnectAttempt: Int = 0
    private var pendingMessages: [Data] = []
    private var pendingLocationMessage: Data?
    private var connectionGeneration: UInt64 = 0

    private let eventSubject = PassthroughSubject<WSIncomingEvent, Never>()
    var eventPublisher: AnyPublisher<WSIncomingEvent, Never> {
        eventSubject.eraseToAnyPublisher()
    }

    #if DEBUG
    func simulateIncomingEventForTesting(_ event: WSIncomingEvent) {
        eventSubject.send(event)
    }

    func simulateConnectionStateForTesting(_ state: WSConnectionState) {
        connectionState = state
    }

    var queuedMessageCountForTesting: Int {
        pendingMessages.count + (pendingLocationMessage == nil ? 0 : 1)
    }
    var connectionGenerationForTesting: UInt64 { connectionGeneration }

    func simulateQueuedMessagesForTesting(count: Int) {
        for value in 0..<count { pendingMessages.append(Data("\(value)".utf8)) }
    }

    func simulateLocationUpdatesForTesting(_ coordinates: [(Double, Double)]) {
        for coordinate in coordinates {
            let message = WSLocationUpdateMessage(lat: coordinate.0, lng: coordinate.1)
            pendingLocationMessage = try? encoder.encode(message)
        }
    }

    @discardableResult
    func simulateNewTransportForTesting(state: WSConnectionState = .connected) -> UInt64 {
        connectionGeneration &+= 1
        connectionState = state
        return connectionGeneration
    }

    func simulateDisconnectForTesting(generation: UInt64) {
        handleDisconnect(generation: generation)
    }

    func simulateTextMessageForTesting(_ text: String, generation: UInt64? = nil) {
        handleTextMessage(text, generation: generation ?? connectionGeneration)
    }
    #endif

    // Reconnect configuration (exponential backoff)
    private static let reconnectDelays: [TimeInterval] = [3, 6, 12, 30]
    private static let heartbeatInterval: TimeInterval = 30
    private static let minSendInterval: TimeInterval = 0.5

    static func shouldStartHeartbeat(for role: WSRole) -> Bool {
        switch role {
        case .blind, .volunteer: return true
        }
    }

    static func requiredSendDelay(lastSend: Date, now: Date) -> TimeInterval {
        max(0, minSendInterval - now.timeIntervalSince(lastSend))
    }

    private var lastSendTime: Date = .distantPast

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Connect to WebSocket endpoint
    func connect(baseURL: URL, token: String, role: WSRole) {
        dispatchDiagnostic = nil
        self.baseURL = baseURL
        self.token = token
        self.role = role
        self.reconnectAttempt = 0
        performConnect()
    }

    /// Disconnect and stop all tasks
    func disconnect() {
        connectionGeneration &+= 1
        stopAllTasks()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        connectionState = .disconnected
        dispatchDiagnostic = nil
    }

    /// Send a GCJ-02 location update. Device WGS-84 coordinates must be normalized first.
    func sendLocationUpdate(lat: Double, lng: Double) {
        let msg = WSLocationUpdateMessage(lat: lat, lng: lng)
        sendMessage(msg, coalescesAsLatestLocation: true)
    }

    /// Send application heartbeat for either role.
    func sendPing() {
        let msg = WSPingMessage()
        sendMessage(msg)
    }

    static func connectionURL(baseURL: URL, token: String, role: WSRole) -> URL? {
        var components = URLComponents()
        components.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        components.host = baseURL.host
        components.port = baseURL.port
        components.path = role.path
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        return components.url
    }

    // MARK: - Connection Management

    private func performConnect() {
        guard let baseURL, let token, let role else { return }

        connectionGeneration &+= 1
        let generation = connectionGeneration
        stopAllTasks()
        webSocketTask?.cancel(with: .goingAway, reason: nil)

        guard let url = Self.connectionURL(baseURL: baseURL, token: token, role: role) else {
            connectionState = .disconnected
            return
        }

        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()
        connectionState = .connecting

        startReceiving(task: task, generation: generation)

        if Self.shouldStartHeartbeat(for: role) { startHeartbeat(generation: generation) }
    }

    private func handleDisconnect(generation: UInt64) {
        guard generation == connectionGeneration else { return }
        guard !connectionState.isDisconnected else { return }
        guard reconnectTask == nil else { return }
        stopAllTasks()
        webSocketTask = nil
        scheduleReconnect(generation: generation)
    }

    private func scheduleReconnect(generation: UInt64) {
        guard generation == connectionGeneration else { return }
        let delayIndex = min(reconnectAttempt, Self.reconnectDelays.count - 1)
        let delay = Self.reconnectDelays[delayIndex]
        reconnectAttempt += 1
        connectionState = .reconnecting(attempt: reconnectAttempt)

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self,
                  generation == self.connectionGeneration else { return }
            self.reconnectTask = nil
            self.performConnect()
        }
    }

    // MARK: - Receiving Messages

    private func startReceiving(task: URLSessionWebSocketTask, generation: UInt64) {
        receiveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard generation == self.connectionGeneration,
                      task === self.webSocketTask else { break }
                do {
                    let message = try await task.receive()
                    guard generation == self.connectionGeneration,
                          task === self.webSocketTask else { break }
                    self.markConnected(generation: generation)
                    let text: String?
                    switch message {
                    case .string(let value):
                        text = value
                    case .data(let data):
                        text = String(data: data, encoding: .utf8)
                    @unknown default:
                        text = nil
                    }
                    if let text {
                        ClientFlowDiagnostics.record(event: "received", operation: "websocket-decode")
                        let decoded = await Task.detached(priority: .userInitiated) {
                            Self.decodeTextMessage(text)
                        }.value
                        guard generation == self.connectionGeneration,
                              task === self.webSocketTask else { break }
                        if let decoded {
                            self.handleDecodedMessage(decoded, generation: generation)
                        }
                    }
                } catch {
                    self.handleDisconnect(generation: generation)
                    break
                }
            }
        }
    }

    private func handleTextMessage(_ text: String, generation: UInt64) {
        guard generation == connectionGeneration else { return }
        guard let decoded = Self.decodeTextMessage(text) else { return }
        handleDecodedMessage(decoded, generation: generation)
    }

    nonisolated private static func decodeTextMessage(_ text: String) -> DecodedWebSocketMessage? {
        guard let data = text.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()

        // First decode the envelope to get the type
        guard let envelope = try? decoder.decode(WSMessageEnvelope.self, from: data) else {
            return DecodedWebSocketMessage(
                event: nil,
                messageType: nil,
                dispatchOrderID: nil,
                failedField: nil
            )
        }

        let event: WSIncomingEvent

        switch envelope.type {
        case WSMessageType.volunteerLocationUpdate.rawValue:
            if let msg = try? decoder.decode(WSVolunteerLocationUpdate.self, from: data) {
                event = .volunteerLocation(msg)
            } else { return nil }

        case WSMessageType.blindLocationUpdate.rawValue:
            if let msg = try? decoder.decode(WSBlindLocationUpdate.self, from: data) {
                event = .blindLocation(msg)
            } else { return nil }

        case WSMessageType.appNotification.rawValue:
            if let msg = try? decoder.decode(WSAppNotification.self, from: data) {
                event = .notification(msg)
            } else { return nil }

        case WSMessageType.orderStatusChanged.rawValue:
            if let msg = try? decoder.decode(WSOrderStatusChanged.self, from: data) {
                event = .orderStatusChanged(msg)
            } else { return nil }

        case WSMessageType.emergencyResolvedByVolunteer.rawValue:
            if let msg = try? decoder.decode(WSEmergencyResolved.self, from: data) {
                event = .emergencyResolved(msg)
            } else { return nil }

        case WSMessageType.emergencyContactNotified.rawValue:
            if let msg = try? decoder.decode(WSEmergencyContactNotified.self, from: data) {
                event = .emergencyContactNotified(msg)
            } else { return nil }

        case WSMessageType.pong.rawValue:
            if let msg = try? decoder.decode(WSPong.self, from: data) {
                event = .pong(msg)
            } else { return nil }

        case WSMessageType.newOrder.rawValue:
            do {
                let msg = try decoder.decode(WSNewOrder.self, from: data)
                event = .newOrder(msg)
            } catch {
                return DecodedWebSocketMessage(
                    event: nil,
                    messageType: envelope.type,
                    dispatchOrderID: nil,
                    failedField: Self.failedField(from: error)
                )
            }

        case WSMessageType.emergencyVolunteerAlert.rawValue:
            if let msg = try? decoder.decode(WSEmergencyVolunteerAlert.self, from: data) {
                event = .emergencyAlert(msg)
            } else { return nil }

        default:
            event = .unknown(envelope.type)
        }

        let dispatchOrderID: Int64?
        if case .newOrder(let order) = event {
            dispatchOrderID = order.orderId
        } else {
            dispatchOrderID = nil
        }
        return DecodedWebSocketMessage(
            event: event,
            messageType: envelope.type,
            dispatchOrderID: dispatchOrderID,
            failedField: nil
        )
    }

    private func handleDecodedMessage(_ decoded: DecodedWebSocketMessage, generation: UInt64) {
        guard generation == connectionGeneration else { return }
        if let failedField = decoded.failedField {
            recordDispatchDiagnostic(
                stage: .decodeFailed,
                generation: generation,
                messageType: decoded.messageType,
                failedField: failedField
            )
            ClientFlowDiagnostics.record(event: "failed", operation: "websocket-decode")
            return
        }
        guard let event = decoded.event else { return }
        if let orderID = decoded.dispatchOrderID {
            recordDispatchDiagnostic(
                stage: .received,
                generation: generation,
                messageType: decoded.messageType,
                orderID: orderID
            )
        }
        ClientFlowDiagnostics.record(event: "applied", operation: "websocket-decode")
        eventSubject.send(event)
    }

    private func markConnected(generation: UInt64) {
        guard generation == connectionGeneration else { return }
        if case .connected = connectionState { return }
        connectionState = .connected
        reconnectAttempt = 0
        recordDispatchDiagnostic(
            stage: .transportConnected,
            generation: generation
        )
    }

    private func recordDispatchDiagnostic(
        stage: WSDispatchDiagnosticStage,
        generation: UInt64,
        messageType: String? = nil,
        orderID: Int64? = nil,
        failedField: String? = nil
    ) {
        dispatchDiagnostic = WSDispatchDiagnostic(
            stage: stage,
            role: role,
            connectionState: connectionState,
            generation: generation,
            messageType: messageType,
            orderID: orderID,
            recordedAt: Date(),
            failedField: failedField
        )
    }

    nonisolated private static func failedField(from error: Error) -> String? {
        let codingPath: [CodingKey]
        switch error {
        case DecodingError.keyNotFound(let key, let context):
            let field = key.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return field.isEmpty ? context.codingPath.last?.stringValue : field
        case DecodingError.typeMismatch(_, let context),
             DecodingError.valueNotFound(_, let context),
             DecodingError.dataCorrupted(let context):
            codingPath = context.codingPath
        default:
            return nil
        }
        return codingPath.last?.stringValue
    }

    // MARK: - Sending Messages

    private func sendMessage<T: Encodable>(
        _ message: T,
        coalescesAsLatestLocation: Bool = false
    ) {
        guard webSocketTask != nil else { return }
        guard connectionState.canSendOrQueueMessages else { return }

        guard let data = try? encoder.encode(message) else { return }
        if coalescesAsLatestLocation {
            let didReplace = pendingLocationMessage != nil
            pendingLocationMessage = data
            ClientFlowDiagnostics.record(
                event: didReplace ? "coalesced" : "queued",
                operation: "websocket-location"
            )
        } else {
            pendingMessages.append(data)
        }
        drainSendQueueIfNeeded()
    }

    private func drainSendQueueIfNeeded() {
        guard senderTask == nil else { return }
        guard let task = webSocketTask else { return }
        let generation = connectionGeneration
        senderTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, generation == self.connectionGeneration,
                  !self.pendingMessages.isEmpty || self.pendingLocationMessage != nil {
                let delay = Self.requiredSendDelay(lastSend: self.lastSendTime, now: Date())
                if delay > 0 {
                    try? await Task.sleep(
                        nanoseconds: UInt64(delay * 1_000_000_000)
                    )
                }
                guard !Task.isCancelled, generation == self.connectionGeneration,
                      task === self.webSocketTask,
                      !self.pendingMessages.isEmpty || self.pendingLocationMessage != nil else { break }
                let data: Data
                if !self.pendingMessages.isEmpty {
                    data = self.pendingMessages.removeFirst()
                } else if let location = self.pendingLocationMessage {
                    data = location
                    self.pendingLocationMessage = nil
                } else {
                    break
                }
                guard let text = String(data: data, encoding: .utf8) else { continue }
                do {
                    try await task.send(.string(text))
                    self.lastSendTime = Date()
                    self.markConnected(generation: generation)
                } catch {
                    self.handleDisconnect(generation: generation)
                    break
                }
            }
            if generation == self.connectionGeneration {
                self.senderTask = nil
            }
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat(generation: UInt64) {
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.heartbeatInterval * 1_000_000_000))
                guard !Task.isCancelled, let self,
                      generation == self.connectionGeneration else { break }
                self.sendPing()
            }
        }
    }

    // MARK: - Cleanup

    private func stopAllTasks() {
        receiveTask?.cancel()
        receiveTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        senderTask?.cancel()
        senderTask = nil
        pendingMessages.removeAll(keepingCapacity: false)
        pendingLocationMessage = nil
        lastSendTime = .distantPast
    }

    deinit {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
    }
}
