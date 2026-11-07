import Foundation

/// An open string enum from the backend: an unknown raw value decodes to `.unknown`.
///
/// AGENTS / CLAUDE.md rule: an enum value that the client does not know must not make the whole
/// response fail to decode. A blank page is an incident for a blind user.
///
/// Adopt it with `enum X: String, Decodable, UnknownFallbackEnum` and a `case unknown`.
/// The enum then gets `init(from:)` from the extension below and must not declare its own.
///
/// ⚠️ When the enum is also `Encodable`, it gets `encode(to:)` from the second extension:
/// `.unknown` encodes as `nil`. Enums that encode `.unknown` as `"UNKNOWN"` (the synthesized
/// behaviour) must not adopt this protocol, because adoption silently changes what they send
/// (#847: the three `VoiceOrderModels` enums and `VolunteerDispatchNotAvailableReason`).
///
/// ⛔ `RunOrderStatus` does not adopt it: it is the order state machine (AGENTS §5).
nonisolated protocol UnknownFallbackEnum: RawRepresentable, Decodable where RawValue == String {
    /// The fallback for raw values that this client does not know. The backend never sends it.
    static var unknown: Self { get }
}

nonisolated extension UnknownFallbackEnum {
    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: rawValue) ?? .unknown
    }
}

nonisolated extension UnknownFallbackEnum where Self: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if rawValue == Self.unknown.rawValue {
            try container.encodeNil()
        } else {
            try container.encode(rawValue)
        }
    }
}
