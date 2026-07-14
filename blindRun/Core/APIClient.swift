import Foundation

// MARK: - HTTP Method

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

// MARK: - API Error

enum APIError: Error, Sendable {
    case serverError(ErrorResponse)
    case rateLimited(RateLimitInfo)
    case unauthorized
    case networkError(Error)
    case decodingError(Error)
    case invalidURL
    case unknown(statusCode: Int)

    var localizedMessage: String {
        switch self {
        case .serverError(let response):
            if let code = response.errorCode {
                return code.localizedMessage
            }
            return response.message
        case .rateLimited(let info):
            if let seconds = info.retryAfterSeconds {
                return "\(info.message) 请在\(seconds)秒后重试。"
            }
            return info.message
        case .unauthorized:
            return "登录已过期，请重新登录。"
        case .networkError:
            return "网络连接失败，请检查网络设置。"
        case .decodingError:
            return "数据解析错误，请稍后重试。"
        case .invalidURL:
            return "请求地址无效。"
        case .unknown(let statusCode):
            return "未知错误 (\(statusCode))，请稍后重试。"
        }
    }
}

// MARK: - API Client Protocol

protocol APIClientProtocol: Sendable {
    /// 通用请求方法。
    /// - Note: 泛型约束使用 Decodable（非 Decodable & Sendable），
    ///   因为项目设置 SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor 会导致
    ///   自动合成的 Decodable 一致性与 Sendable 产生 actor isolation 冲突。
    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T

    func upload<T: Decodable>(
        path: String,
        query: [String: String]?,
        fields: [String: String]?,
        files: [MultipartFile],
        requiresAuth: Bool
    ) async throws -> T
}

struct MultipartFile: Sendable {
    let fieldName: String
    let fileName: String
    let mimeType: String
    let data: Data
}

extension APIClientProtocol {
    func get<T: Decodable>(
        _ path: String,
        query: [String: String]? = nil,
        requiresAuth: Bool = true
    ) async throws -> T {
        try await request(method: .get, path: path, query: query, body: nil, requiresAuth: requiresAuth)
    }

    func post<T: Decodable>(
        _ path: String,
        body: (any Encodable & Sendable)? = nil,
        requiresAuth: Bool = true
    ) async throws -> T {
        try await request(method: .post, path: path, query: nil, body: body, requiresAuth: requiresAuth)
    }

    func put<T: Decodable>(
        _ path: String,
        body: (any Encodable & Sendable)? = nil,
        requiresAuth: Bool = true
    ) async throws -> T {
        try await request(method: .put, path: path, query: nil, body: body, requiresAuth: requiresAuth)
    }

    func patch<T: Decodable>(
        _ path: String,
        body: (any Encodable & Sendable)? = nil,
        requiresAuth: Bool = true
    ) async throws -> T {
        try await request(method: .patch, path: path, query: nil, body: body, requiresAuth: requiresAuth)
    }

    func delete<T: Decodable>(
        _ path: String,
        requiresAuth: Bool = true
    ) async throws -> T {
        try await request(method: .delete, path: path, query: nil, body: nil, requiresAuth: requiresAuth)
    }

    func upload<T: Decodable>(
        _ path: String,
        query: [String: String]? = nil,
        fields: [String: String]? = nil,
        files: [MultipartFile],
        requiresAuth: Bool = true
    ) async throws -> T {
        try await upload(path: path, query: query, fields: fields, files: files, requiresAuth: requiresAuth)
    }
}

// MARK: - URLSession API Client

final class URLSessionAPIClient: APIClientProtocol, @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let tokenProvider: @Sendable () -> String?

    private static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        return URLSession(configuration: configuration)
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

    init(
        baseURL: URL,
        session: URLSession = URLSessionAPIClient.defaultSession,
        tokenProvider: @escaping @Sendable () -> String?
    ) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
    }

    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: true)

        if let query, !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if requiresAuth, let token = tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try encoder.encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.unknown(statusCode: -1)
        }

        switch httpResponse.statusCode {
        case 200...299:
            if T.self == EmptyResponse.self, data.isEmpty {
                return EmptyResponse() as! T
            }
            // Strategy: Try envelope first, then direct decode.
            // Envelope-first avoids the issue where all-optional models (e.g. BlindProfileResponse)
            // would "succeed" with all-nil values when decoded from the envelope root object.
            if let envelope = try? decoder.decode(APIEnvelopeResponse<T>.self, from: data),
               let payload = envelope.data {
                return payload
            }
            // Fallback: direct decode (for auth endpoints with flat responses)
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decodingError(error)
            }
        case 401:
            throw APIError.unauthorized
        case 429:
            throw Self.rateLimitError(data: data, response: httpResponse, decoder: decoder)
        default:
            // Try string-code ErrorResponse (e.g. {"code": "INVALID_VERIFICATION_CODE", "message": "..."})
            if let errorResponse = try? decoder.decode(ErrorResponse.self, from: data) {
                throw APIError.serverError(errorResponse)
            }
            // Accept the cloud backend's flexible error payload during contract convergence.
            if let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data),
               let errorResponse = envelope.resolvedErrorResponse(statusCode: httpResponse.statusCode) {
                throw APIError.serverError(errorResponse)
            }
            throw APIError.unknown(statusCode: httpResponse.statusCode)
        }
    }

    // MARK: - Multipart Upload

    func upload<T: Decodable>(
        path: String,
        query: [String: String]? = nil,
        fields: [String: String]? = nil,
        files: [MultipartFile],
        requiresAuth: Bool = true
    ) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: true)

        if let query, !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if requiresAuth, let token = tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()
        for (name, value) in (fields ?? [:]).sorted(by: { $0.key < $1.key }) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append(value.data(using: .utf8) ?? Data())
            body.append("\r\n".data(using: .utf8)!)
        }
        for file in files {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(file.fieldName)\"; filename=\"\(file.fileName)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: \(file.mimeType)\r\n\r\n".data(using: .utf8)!)
            body.append(file.data)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.unknown(statusCode: -1)
        }

        switch httpResponse.statusCode {
        case 200...299:
            if T.self == EmptyResponse.self, data.isEmpty {
                return EmptyResponse() as! T
            }
            // Strategy: Try envelope first, then direct decode.
            // Envelope-first avoids the issue where all-optional models (e.g. BlindProfileResponse)
            // would "succeed" with all-nil values when decoded from the envelope root object.
            if let envelope = try? decoder.decode(APIEnvelopeResponse<T>.self, from: data),
               let payload = envelope.data {
                return payload
            }
            // Fallback: direct decode (for auth endpoints with flat responses)
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decodingError(error)
            }
        case 401:
            throw APIError.unauthorized
        case 429:
            throw Self.rateLimitError(data: data, response: httpResponse, decoder: decoder)
        default:
            // Try string-code ErrorResponse (e.g. {"code": "INVALID_VERIFICATION_CODE", "message": "..."})
            if let errorResponse = try? decoder.decode(ErrorResponse.self, from: data) {
                throw APIError.serverError(errorResponse)
            }
            // Accept the cloud backend's flexible error payload during contract convergence.
            if let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data),
               let errorResponse = envelope.resolvedErrorResponse(statusCode: httpResponse.statusCode) {
                throw APIError.serverError(errorResponse)
            }
            throw APIError.unknown(statusCode: httpResponse.statusCode)
        }
    }

    private static func rateLimitError(
        data: Data,
        response: HTTPURLResponse,
        decoder: JSONDecoder
    ) -> APIError {
        let headerSeconds = response.value(forHTTPHeaderField: "Retry-After")
            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if let payload = try? decoder.decode(ErrorResponse.self, from: data) {
            return .rateLimited(RateLimitInfo(
                message: payload.message,
                bucket: payload.rateLimitBucket,
                retryAfterSeconds: headerSeconds ?? payload.retryAfterSeconds
            ))
        }
        if let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data) {
            return .rateLimited(RateLimitInfo(
                message: envelope.message ?? envelope.error ?? "操作过于频繁。",
                bucket: envelope.rateLimitBucket,
                retryAfterSeconds: headerSeconds ?? envelope.retryAfterSeconds
            ))
        }
        return .rateLimited(RateLimitInfo(
            message: "操作过于频繁。",
            bucket: nil,
            retryAfterSeconds: headerSeconds
        ))
    }
}
