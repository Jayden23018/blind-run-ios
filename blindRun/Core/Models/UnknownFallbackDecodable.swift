import Foundation

/// An open string enum from the backend: an unknown raw value decodes to `.unknown`.
///
/// AGENTS / CLAUDE.md rule: an enum value that the client does not know must not make the whole
/// response fail to decode. A blank page is an incident for a blind user.
///
/// Adopt it with `enum X: String, Decodable, UnknownFallbackDecodable` and a `case unknown`.
/// The enum then gets `init(from:)` from the extension below and must not declare its own
/// (the guard rule `unknown-fallback-handwritten` blocks a hand-written copy).
///
/// Decoding: a known raw value gives that case. Any other string gives `.unknown`.
/// A value that is not a string still throws, the same as before (#847).
///
/// This protocol does not touch encoding. A `Codable` enum that adopts only this protocol keeps
/// the synthesized `encode(to:)`, so `.unknown` encodes as `"UNKNOWN"`. To encode `.unknown` as
/// `null`, adopt `UnknownFallbackCodable` instead.
///
/// ⛔ `RunOrderStatus` does not adopt it: it is the order state machine (AGENTS §5).
nonisolated protocol UnknownFallbackDecodable: RawRepresentable, Decodable where RawValue == String {
    /// The fallback for raw values that this client does not know. The backend never sends it.
    static var unknown: Self { get }
}

nonisolated extension UnknownFallbackDecodable {
    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: rawValue) ?? .unknown
    }
}

/// `UnknownFallbackDecodable` plus encoding: `.unknown` encodes as `null`, and every other case
/// encodes as its raw value.
///
/// Use it for enums that the app also sends to the backend (for example the pace and route
/// preferences in order and profile requests). The client must never send back a string that the
/// backend does not know, and `null` must not take the place of a real value such as
/// `NO_PREFERENCE`.
///
/// It is a separate protocol on purpose. If `encode(to:)` came with `UnknownFallbackDecodable`
/// whenever the enum is `Encodable`, adopting the decoding protocol would silently change what a
/// `Codable` enum sends.
///
/// ⚠️ Write both protocols in the enum declaration, and `Codable` too:
/// `enum X: String, Codable, UnknownFallbackDecodable, UnknownFallbackCodable`.
/// With Xcode 26.2 and `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, an enum that gets
/// `UnknownFallbackDecodable` only through this protocol fails to compile on its `case unknown`:
/// "'nonisolated' modifier cannot be applied to this declaration" (#847, device SDK build).
/// A standalone `swiftc` with the same flags did not show it, so check with `build-for-testing`.
nonisolated protocol UnknownFallbackCodable: UnknownFallbackDecodable {}

nonisolated extension UnknownFallbackCodable where Self: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if rawValue == Self.unknown.rawValue {
            try container.encodeNil()
        } else {
            try container.encode(rawValue)
        }
    }
}
