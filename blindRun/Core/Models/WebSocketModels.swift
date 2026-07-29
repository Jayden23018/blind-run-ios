import Foundation

// MARK: - WebSocket Message Type

nonisolated enum WSMessageType: String, Codable, Sendable {
    // Client -> Server
    case locationUpdate = "LOCATION_UPDATE"
    case ping = "PING"

    // Server -> Client (Blind)
    case volunteerLocationUpdate = "VOLUNTEER_LOCATION_UPDATE"
    case blindLocationUpdate = "BLIND_LOCATION_UPDATE"
    case separationAlert = "SEPARATION_ALERT" // legacy flat compatibility only
    case appNotification = "APP_NOTIFICATION"
    case orderStatusChanged = "ORDER_STATUS_CHANGED"
    case emergencyResolvedByVolunteer = "EMERGENCY_RESOLVED_BY_VOLUNTEER"
    case emergencyContactNotified = "EMERGENCY_CONTACT_NOTIFIED"
    case pong = "PONG"

    // Server -> Client (Volunteer)
    case newOrder = "NEW_ORDER"
    case emergencyVolunteerAlert = "EMERGENCY_VOLUNTEER_ALERT"
}

// MARK: - Outgoing Messages (Client -> Server)

nonisolated struct WSLocationUpdateMessage: Codable, Sendable {
    let type: String
    let lat: Double
    let lng: Double

    init(lat: Double, lng: Double) {
        self.type = WSMessageType.locationUpdate.rawValue
        self.lat = lat
        self.lng = lng
    }
}

nonisolated struct WSPingMessage: Codable, Sendable {
    let type: String

    init() {
        self.type = WSMessageType.ping.rawValue
    }
}

// MARK: - Incoming Messages (Server -> Client)

/// Generic envelope to peek at message type before full decode
nonisolated struct WSMessageEnvelope: Codable, Sendable {
    let type: String
}

/// Volunteer real-time location (sent to blind user)
nonisolated struct WSVolunteerLocationUpdate: Codable, Sendable {
    let type: String
    let orderId: Int64
    let lat: Double
    let lng: Double
    let timestamp: Int64
}

/// Blind-runner real-time location (sent to the associated volunteer).
nonisolated struct WSBlindLocationUpdate: Codable, Sendable {
    let type: String
    let orderId: Int64
    let lat: Double
    let lng: Double
    let timestamp: Int64
}

/// Generic notification from backend templates
nonisolated struct WSAppNotification: Decodable, Sendable {
    let type: String
    let eventId: Int64?
    let messageId: String?
    let eventType: String
    let title: String?
    let body: String
    let ttsText: String?
    let priority: String?
    let timestamp: String?

    init(
        type: String,
        eventId: Int64?,
        messageId: String? = nil,
        eventType: String,
        title: String?,
        body: String,
        ttsText: String?,
        priority: String?,
        timestamp: String?
    ) {
        self.type = type
        self.eventId = eventId
        self.messageId = messageId
        self.eventType = eventType
        self.title = title
        self.body = body
        self.ttsText = ttsText
        self.priority = priority
        self.timestamp = timestamp
    }

    private enum CodingKeys: String, CodingKey {
        case type, eventId, messageId, eventType, title, body, ttsText, priority, timestamp
    }

    init(from decoder: Decoder) throws {
        let envelope = try decoder.container(keyedBy: CodingKeys.self)
        type = try envelope.decode(String.self, forKey: .type)
        eventId = try envelope.decodeIfPresent(Int64.self, forKey: .eventId)
        messageId = try envelope.decodeIfPresent(String.self, forKey: .messageId)
        eventType = try envelope.decode(String.self, forKey: .eventType)
        title = try envelope.decodeIfPresent(String.self, forKey: .title)
        body = try envelope.decode(String.self, forKey: .body)
        ttsText = try envelope.decodeIfPresent(String.self, forKey: .ttsText)
        priority = try envelope.decodeIfPresent(String.self, forKey: .priority)
        timestamp = try envelope.decodeIfPresent(String.self, forKey: .timestamp)
    }
}

/// Feature-neutral separation signal. Feature policy is owned by a later change.
nonisolated struct WSSeparationAlert: Codable, Sendable {
    let type: String
    let eventId: Int64
    let orderId: Int64
    let distanceMeters: Double?
    let message: String
    let ttsText: String?
    let priority: String?
    let timestamp: String?
}

/// Order status change notification
nonisolated struct WSOrderStatusChanged: Codable, Sendable {
    let type: String
    let messageId: String?
    let orderId: Int64
    let fromStatus: String?
    let toStatus: String
    let message: String?
    let ttsText: String?
    let priority: String?
    let timestamp: String?

    init(
        type: String,
        messageId: String? = nil,
        orderId: Int64,
        fromStatus: String?,
        toStatus: String,
        message: String?,
        ttsText: String?,
        priority: String?,
        timestamp: String?
    ) {
        self.type = type
        self.messageId = messageId
        self.orderId = orderId
        self.fromStatus = fromStatus
        self.toStatus = toStatus
        self.message = message
        self.ttsText = ttsText
        self.priority = priority
        self.timestamp = timestamp
    }
}

/// Emergency resolved by volunteer (sent to blind user)
nonisolated struct WSEmergencyResolved: Codable, Sendable {
    let type: String
    let eventId: Int64
    let message: String?
    let ttsText: String?
    let priority: String?
    let timestamp: String?
}

/// Emergency contact notified (sent to blind user)
nonisolated struct WSEmergencyContactNotified: Codable, Sendable {
    let type: String
    let eventId: Int64
    let message: String?
    let ttsText: String?
    let priority: String?
    let timestamp: String?
}

/// Heartbeat response
nonisolated struct WSPong: Codable, Sendable {
    let type: String
    let timestamp: Int64?
}

/// New order dispatch (sent to volunteer)
nonisolated struct WSNewOrder: Codable, Sendable {
    let type: String
    let timestamp: String?
    let orderId: Int64
    let startAddress: String?
    let startLatitude: Double?
    let startLongitude: Double?
    let distanceKm: Double?
    let plannedStart: String?
    let plannedEnd: String?
    let dispatchTimeoutSeconds: Int?
    let priority: String?
    let pacePreference: String?
    let hasGuideDog: Bool?
    let specialNotes: String?
}

/// Emergency alert for volunteer
nonisolated struct WSEmergencyVolunteerAlert: Codable, Sendable {
    let type: String
    let eventId: Int64
    let orderId: Int64
    let userId: Int64?
    let message: String?
    let ttsText: String?
    let priority: String?
    let gpsLat: Double?
    let gpsLng: Double?
    let timestamp: String?
}

// MARK: - Parsed WebSocket Event

/// High-level event enum for consumers to switch on
nonisolated enum WSIncomingEvent: Sendable {
    case volunteerLocation(WSVolunteerLocationUpdate)
    case blindLocation(WSBlindLocationUpdate)
    case separationAlert(WSSeparationAlert)
    case notification(WSAppNotification)
    case orderStatusChanged(WSOrderStatusChanged)
    case emergencyResolved(WSEmergencyResolved)
    case emergencyContactNotified(WSEmergencyContactNotified)
    case pong(WSPong)
    case newOrder(WSNewOrder)
    case emergencyAlert(WSEmergencyVolunteerAlert)
    case unknown(String)
}
