import Foundation

// 从 `ErrorModels.swift` 原样搬来（#504）：那个文件超了 SwiftLint 长度上限，每加一个后端错误码都要补 baseline。
// 这里是响应体与错误体的解码外壳；`ErrorCode` 枚举本身留在原文件（`scripts/validate-error-codes.mjs` 按那个路径读）。

// MARK: - Error Response

struct ErrorResponse: Codable, Sendable {
    let code: String
    let message: String
    let retryAfterSeconds: Int?

    init(
        code: String,
        message: String,
        retryAfterSeconds: Int? = nil
    ) {
        self.code = code
        self.message = message
        self.retryAfterSeconds = retryAfterSeconds
    }

    var errorCode: ErrorCode? {
        ErrorCode(rawValue: code)
    }
}

struct RateLimitInfo: Codable, Sendable, Equatable {
    let message: String
    let retryAfterSeconds: Int?
}

// MARK: - Cloud Backend Response Envelope

/// Generic response envelope for cloud backend business endpoints.
/// Format: {"success": bool, "code": int, "message": string, "data": T}
/// `URLSessionAPIClient` 的成功体解码策略，抽出来只为一件事：**能被测试直接驱动**。
///
/// 两个调用点（`request` / `upload`）此前各抄了一份同样的六行。真正需要锁住的是它的顺序语义 ——
/// 先试信封、拿不到 `data` 再裸解 —— 因为有些类型（如 `EmergencyActiveEnvelope`）正是靠
/// 「内层解不出」才落到裸解这一步的，靠读代码推断这条路走不走得通并不可靠。
enum APIPayloadDecoder {
    /// - Note: 信封优先是有意的：字段全可选的模型（如 `BlindProfileResponse`）从信封根对象裸解
    ///   会「成功」但全是 nil。
    static func decodePayload<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        decoder: JSONDecoder
    ) throws -> T {
        if let envelope = try? decoder.decode(APIEnvelopeResponse<T>.self, from: data),
           let payload = envelope.data {
            return payload
        }
        return try decoder.decode(T.self, from: data)
    }
}

struct APIEnvelopeResponse<T: Decodable>: Decodable {
    let success: Bool?
    let code: Int?
    let message: String?
    let data: T?
}

/// Empty success payload for endpoints where the client only needs HTTP success.
struct EmptyResponse: Decodable, Sendable {
    init() {}
    init(from decoder: Decoder) throws {}
}

/// Flexible cloud error payload. The demo backend currently returns multiple
/// shapes, including `errorCode`, numeric/string `code`, and `message`.
///
/// 不再解 `error` 键：后端唯一带裸 `error` 的两处分别是 429（同时恒带 `message`，
/// 且后端已确认要删这个冗余键）和 `AuthController` 的 401 —— 而 401 在 `APIClient`
/// 里解 body 之前就 `throw .unauthorized`，这条兜底永远走不到。
struct APIErrorEnvelope: Decodable {
    let success: Bool?
    let code: String?
    let errorCode: String?
    let message: String?
    let retryAfterSeconds: Int?

    private enum CodingKeys: String, CodingKey {
        case success, code, errorCode, message, retryAfterSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decodeIfPresent(Bool.self, forKey: .success)
        errorCode = try container.decodeIfPresent(String.self, forKey: .errorCode)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        retryAfterSeconds = try container.decodeIfPresent(Int.self, forKey: .retryAfterSeconds)
        if let stringCode = try? container.decodeIfPresent(String.self, forKey: .code) {
            code = stringCode
        } else if let intCode = try? container.decodeIfPresent(Int.self, forKey: .code) {
            code = String(intCode)
        } else {
            code = nil
        }
    }

    func resolvedErrorResponse(statusCode: Int) -> ErrorResponse? {
        guard let resolvedMessage = message else { return nil }
        return ErrorResponse(
            code: errorCode ?? code ?? "HTTP_\(statusCode)",
            message: resolvedMessage,
            retryAfterSeconds: retryAfterSeconds
        )
    }
}
