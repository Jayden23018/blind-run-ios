import Foundation
import Combine

// MARK: - WebSocket Connection State

enum WSConnectionState: Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)

    var isDisconnected: Bool {
        if case .disconnected = self { return true }
        return false
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

// MARK: - WebSocket Service

/// Manages WebSocket connection for real-time communication with the backend.
/// Supports auto-reconnect with exponential backoff and heartbeat (blind only).
@MainActor
final class WebSocketService: ObservableObject {
    @Published private(set) var connectionState: WSConnectionState = .disconnected

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession
    private var baseURL: URL?
    private var token: String?
    private var role: WSRole?

    private var reconnectTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var reconnectAttempt: Int = 0

    private let eventSubject = PassthroughSubject<WSIncomingEvent, Never>()
    var eventPublisher: AnyPublisher<WSIncomingEvent, Never> {
        eventSubject.eraseToAnyPublisher()
    }

    // Reconnect configuration (exponential backoff)
    private static let reconnectDelays: [TimeInterval] = [3, 6, 12, 30]
    private static let heartbeatInterval: TimeInterval = 30
    private static let minSendInterval: TimeInterval = 0.5

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
        self.baseURL = baseURL
        self.token = token
        self.role = role
        self.reconnectAttempt = 0
        performConnect()
    }

    /// Disconnect and stop all tasks
    func disconnect() {
        stopAllTasks()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        connectionState = .disconnected
    }

    /// Send location update
    func sendLocationUpdate(lat: Double, lng: Double) {
        let msg = WSLocationUpdateMessage(lat: lat, lng: lng)
        sendMessage(msg)
    }

    /// Send ping (blind user only)
    func sendPing() {
        let msg = WSPingMessage()
        sendMessage(msg)
    }

    // MARK: - Connection Management

    private func performConnect() {
        guard let baseURL, let token, let role else { return }

        stopAllTasks()
        webSocketTask?.cancel(with: .goingAway, reason: nil)

        // Build ws:// URL with token query param
        var components = URLComponents()
        components.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        components.host = baseURL.host
        components.port = baseURL.port
        components.path = role.path
        components.queryItems = [URLQueryItem(name: "token", value: token)]

        guard let url = components.url else {
            connectionState = .disconnected
            return
        }

        connectionState = .connecting
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()

        startReceiving()

        // Start heartbeat only for blind users
        if role == .blind {
            startHeartbeat()
        }
    }

    private func handleDisconnect() {
        guard !connectionState.isDisconnected else { return }
        stopAllTasks()
        webSocketTask = nil
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        let delayIndex = min(reconnectAttempt, Self.reconnectDelays.count - 1)
        let delay = Self.reconnectDelays[delayIndex]
        reconnectAttempt += 1
        connectionState = .reconnecting(attempt: reconnectAttempt)

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.performConnect()
        }
    }

    // MARK: - Receiving Messages

    private func startReceiving() {
        receiveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard let task = self.webSocketTask else { break }
                do {
                    let message = try await task.receive()
                    self.markConnected()
                    switch message {
                    case .string(let text):
                        self.handleTextMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleTextMessage(text)
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    // Connection lost
                    self.handleDisconnect()
                    break
                }
            }
        }
    }

    private func handleTextMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        // First decode the envelope to get the type
        guard let envelope = try? decoder.decode(WSMessageEnvelope.self, from: data) else { return }

        let event: WSIncomingEvent

        switch envelope.type {
        case WSMessageType.volunteerLocationUpdate.rawValue:
            if let msg = try? decoder.decode(WSVolunteerLocationUpdate.self, from: data) {
                event = .volunteerLocation(msg)
            } else { return }

        case WSMessageType.appNotification.rawValue:
            if let msg = try? decoder.decode(WSAppNotification.self, from: data) {
                event = .notification(msg)
            } else { return }

        case WSMessageType.orderStatusChanged.rawValue:
            if let msg = try? decoder.decode(WSOrderStatusChanged.self, from: data) {
                event = .orderStatusChanged(msg)
            } else { return }

        case WSMessageType.emergencyResolvedByVolunteer.rawValue:
            if let msg = try? decoder.decode(WSEmergencyResolved.self, from: data) {
                event = .emergencyResolved(msg)
            } else { return }

        case WSMessageType.emergencyContactNotified.rawValue:
            if let msg = try? decoder.decode(WSEmergencyContactNotified.self, from: data) {
                event = .emergencyContactNotified(msg)
            } else { return }

        case WSMessageType.pong.rawValue:
            if let msg = try? decoder.decode(WSPong.self, from: data) {
                event = .pong(msg)
            } else { return }

        case WSMessageType.newOrder.rawValue:
            if let msg = try? decoder.decode(WSNewOrder.self, from: data) {
                event = .newOrder(msg)
            } else { return }

        case WSMessageType.emergencyVolunteerAlert.rawValue:
            if let msg = try? decoder.decode(WSEmergencyVolunteerAlert.self, from: data) {
                event = .emergencyAlert(msg)
            } else { return }

        default:
            event = .unknown(envelope.type)
        }

        eventSubject.send(event)
    }

    private func markConnected() {
        if case .connected = connectionState { return }
        connectionState = .connected
        reconnectAttempt = 0
    }

    // MARK: - Sending Messages

    private func sendMessage<T: Encodable>(_ message: T) {
        guard let task = webSocketTask else { return }
        switch connectionState {
        case .connecting, .connected:
            break
        case .disconnected, .reconnecting:
            return
        }

        // Rate limiting: minimum 500ms between sends
        let now = Date()
        guard now.timeIntervalSince(lastSendTime) >= Self.minSendInterval else { return }
        lastSendTime = now

        Task {
            do {
                let data = try encoder.encode(message)
                if let text = String(data: data, encoding: .utf8) {
                    try await task.send(.string(text))
                    markConnected()
                }
            } catch {
                // Send failure - connection may be lost
                handleDisconnect()
            }
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.heartbeatInterval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                self?.sendPing()
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
    }

    deinit {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
    }
}
