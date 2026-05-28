import Foundation

// MARK: - WebSocket Message Type

enum WSMessageType: String, Codable, Sendable {
    // Client -> Server
    case locationUpdate = "LOCATION_UPDATE"
    case ping = "PING"

    // Server -> Client (Blind)
    case volunteerLocationUpdate = "VOLUNTEER_LOCATION_UPDATE"
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

struct WSLocationUpdateMessage: Codable, Sendable {
    let type: String
    let lat: Double
    let lng: Double

    init(lat: Double, lng: Double) {
        self.type = WSMessageType.locationUpdate.rawValue
        self.lat = lat
        self.lng = lng
    }
}

struct WSPingMessage: Codable, Sendable {
    let type: String

    init() {
        self.type = WSMessageType.ping.rawValue
    }
}

// MARK: - Incoming Messages (Server -> Client)

/// Generic envelope to peek at message type before full decode
struct WSMessageEnvelope: Codable, Sendable {
    let type: String
}

/// Volunteer real-time location (sent to blind user)
struct WSVolunteerLocationUpdate: Codable, Sendable {
    let type: String
    let orderId: Int64
    let lat: Double
    let lng: Double
    let timestamp: Int64
}

/// Generic notification from backend templates
struct WSAppNotification: Codable, Sendable {
    let type: String
    let body: String
    let ttsText: String?
    let priority: String?
    let timestamp: String?
}

/// Order status change notification
struct WSOrderStatusChanged: Codable, Sendable {
    let type: String
    let orderId: Int64
    let fromStatus: String?
    let toStatus: String
    let message: String?
    let ttsText: String?
    let priority: String?
    let timestamp: String?
}

/// Emergency resolved by volunteer (sent to blind user)
struct WSEmergencyResolved: Codable, Sendable {
    let type: String
    let eventId: Int64
    let message: String?
    let ttsText: String?
    let priority: String?
    let timestamp: String?
}

/// Emergency contact notified (sent to blind user)
struct WSEmergencyContactNotified: Codable, Sendable {
    let type: String
    let eventId: Int64
    let message: String?
    let ttsText: String?
    let priority: String?
    let timestamp: String?
}

/// Heartbeat response
struct WSPong: Codable, Sendable {
    let type: String
    let timestamp: Int64?
}

/// New order dispatch (sent to volunteer)
struct WSNewOrder: Codable, Sendable {
    let type: String
    let orderId: Int64
    let startAddress: String?
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
struct WSEmergencyVolunteerAlert: Codable, Sendable {
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
enum WSIncomingEvent: Sendable {
    case volunteerLocation(WSVolunteerLocationUpdate)
    case notification(WSAppNotification)
    case orderStatusChanged(WSOrderStatusChanged)
    case emergencyResolved(WSEmergencyResolved)
    case emergencyContactNotified(WSEmergencyContactNotified)
    case pong(WSPong)
    case newOrder(WSNewOrder)
    case emergencyAlert(WSEmergencyVolunteerAlert)
    case unknown(String)
}
