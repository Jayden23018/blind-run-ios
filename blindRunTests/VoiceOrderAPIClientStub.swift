import Foundation
@testable import blindRun

/// 语音下单向导用例共用的传输层替身。从 `VoiceOrderWizardTests.swift` 挪出来，
/// 好让按主题拆开的新用例文件也能用（那个文件已超 SwiftLint 行数上限，不能再变长）。
final class VoiceOrderAPIClientStub: APIClientProtocol, @unchecked Sendable {
    enum StubError: Error { case exhausted, unexpectedType }

    var resolveAddressResponses: [ResolveAddressResponse] = []
    var parseOrderResponses: [ParseVoiceOrderResponse] = []
    var parseSlotResponses: [ParseSlotResponse] = []
    var error: APIError?
    /// 在请求发出的那一刻回调。用来观察「等待期间用户听到了什么」—— 这件事只在往返途中成立，
    /// 等 `submitTranscript` 返回时早被读回覆盖了。
    var onRequest: (() -> Void)?
    private(set) var paths: [String] = []
    private(set) var requestedSlotFields: [VoiceSlotField] = []
    /// 发往 `/voice/parse` 的请求体。**跨轮修正的全部前提是 `current` 真的被发出去了**，
    /// 只看 `paths` 验不出来 —— 路径对、body 里没有 `current` 的话后端一个新字段都不会给。
    private(set) var parseRequests: [ParseVoiceOrderRequest] = []

    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        paths.append(path)
        onRequest?()
        if let error { throw error }
        switch path {
        case VoiceOrderEndpoint.parseOrder:
            if let parsed = Self.decode(ParseVoiceOrderRequest.self, from: body) {
                parseRequests.append(parsed)
            }
            guard !parseOrderResponses.isEmpty else { throw StubError.exhausted }
            guard let typed = parseOrderResponses.removeFirst() as? T else {
                throw StubError.unexpectedType
            }
            return typed
        case VoiceOrderEndpoint.resolveAddress:
            guard !resolveAddressResponses.isEmpty else { throw StubError.exhausted }
            guard let typed = resolveAddressResponses.removeFirst() as? T else {
                throw StubError.unexpectedType
            }
            return typed
        case VoiceOrderEndpoint.parseSlot:
            // 整句轮 2026-08-04 起走 `/voice/parse` 单请求，`parse-slot` 只剩定点修改轮在用 ——
            // 那是串行的一轮一个，按队列取就够，不会串台（此前的 by-field 字典已随之删除）。
            if let field = Self.slotField(from: body) { requestedSlotFields.append(field) }
            guard !parseSlotResponses.isEmpty else { throw StubError.exhausted }
            guard let typed = parseSlotResponses.removeFirst() as? T else {
                throw StubError.unexpectedType
            }
            return typed
        default:
            throw StubError.unexpectedType
        }
    }

    func upload<T: Decodable>(
        path: String,
        query: [String: String]?,
        fields: [String: String]?,
        files: [MultipartFile],
        requiresAuth: Bool
    ) async throws -> T {
        throw StubError.unexpectedType
    }

    private static func slotField(from body: (any Encodable & Sendable)?) -> VoiceSlotField? {
        decode(ParseSlotRequest.self, from: body)?.field
    }

    private static func decode<T: Decodable>(
        _ type: T.Type,
        from body: (any Encodable & Sendable)?
    ) -> T? {
        guard let body,
              let data = try? JSONEncoder().encode(ParseSlotRequestBox(body: body)) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }

    private struct ParseSlotRequestBox: Encodable {
        let body: any Encodable & Sendable
        func encode(to encoder: Encoder) throws { try body.encode(to: encoder) }
    }
}
