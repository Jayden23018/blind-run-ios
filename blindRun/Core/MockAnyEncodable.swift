import CoreLocation
import Foundation

// MARK: - MockAnyEncodable Helper

/// Helper to bridge `any Encodable` to concrete Encodable for JSONEncoder.
/// 拆分成 `MockAPIClient+*.swift` 之后它必须是 internal，所以带上 `Mock` 前缀 ——
/// 这是 Mock 内部的编码桥，不是 App 词汇表里的类型。
struct MockAnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init(_ wrapped: (any Encodable & Sendable)?) {
        self._encode = { encoder in
            if let value = wrapped {
                try value.encode(to: encoder)
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
