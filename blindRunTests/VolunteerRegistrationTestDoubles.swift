import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

final class BasicInfoStatusAPIClient: APIClientProtocol, @unchecked Sendable {
    private let status: VolunteerRegistrationStatus
    private(set) var submitCount = 0
    private(set) var statusRefreshCount = 0
    private(set) var capturedRequest: BasicInfoRequest?

    init(status: VolunteerRegistrationStatus) {
        self.status = status
    }

    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        if method == .post, path == "/api/volunteer/registration/step1" {
            submitCount += 1
            guard let request = body as? BasicInfoRequest else {
                throw APIError.invalidURL
            }
            capturedRequest = request
            guard let response = EmptyResponse() as? T else {
                throw APIError.invalidURL
            }
            return response
        }
        if method == .get, path == "/api/volunteer/registration/status" {
            statusRefreshCount += 1
            guard let response = status as? T else {
                throw APIError.invalidURL
            }
            return response
        }
        throw APIError.invalidURL
    }

    func upload<T: Decodable>(
        path: String,
        query: [String: String]?,
        fields: [String: String]?,
        files: [MultipartFile],
        requiresAuth: Bool
    ) async throws -> T {
        throw APIError.invalidURL
    }
}

final class CloudAuthVerifierSpy: CloudAuthVerifying, @unchecked Sendable {
    private let outcome: CloudAuthVerificationOutcome
    private(set) var receivedCertifyIds: [String] = []
    private(set) var receivedEnvironments: [APIEnvironment] = []

    init(outcome: CloudAuthVerificationOutcome) {
        self.outcome = outcome
    }

    func verify(certifyId: String, environment: APIEnvironment) async -> CloudAuthVerificationOutcome {
        receivedCertifyIds.append(certifyId)
        receivedEnvironments.append(environment)
        return outcome
    }
}

final class FaceVerifyFlowAPIClient: APIClientProtocol, @unchecked Sendable {
    private let initResponse: FaceVerifyInitResponse
    private let initError: APIError?
    private var resultResponses: [FaceVerifyResponse]
    private let status: VolunteerRegistrationStatus
    private(set) var capturedMetaInfo: String?
    private(set) var initCount = 0
    private(set) var resultCount = 0
    private(set) var statusRefreshCount = 0
    private(set) var requestedPaths: [String] = []

    init(
        initResponse: FaceVerifyInitResponse,
        initError: APIError? = nil,
        resultResponses: [FaceVerifyResponse],
        status: VolunteerRegistrationStatus = VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true)
    ) {
        self.initResponse = initResponse
        self.initError = initError
        self.resultResponses = resultResponses
        self.status = status
    }

    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        requestedPaths.append(path)
        if method == .post, path == "/api/volunteer/registration/step3/face-verify/init" {
            initCount += 1
            if let initError {
                throw initError
            }
            guard let request = body as? FaceVerifyInitRequest,
                  let response = initResponse as? T else {
                throw APIError.invalidURL
            }
            capturedMetaInfo = request.metaInfo
            return response
        }
        if method == .post, path == "/api/volunteer/registration/step3/face-verify/result" {
            resultCount += 1
            guard let response = (resultResponses.isEmpty ? FaceVerifyResponse(passed: false, status: "PENDING", message: nil) : resultResponses.removeFirst()) as? T else {
                throw APIError.invalidURL
            }
            return response
        }
        if method == .get, path == "/api/volunteer/registration/status" {
            statusRefreshCount += 1
            guard let response = status as? T else {
                throw APIError.invalidURL
            }
            return response
        }
        throw APIError.invalidURL
    }

    func upload<T: Decodable>(
        path: String,
        query: [String: String]?,
        fields: [String: String]?,
        files: [MultipartFile],
        requiresAuth: Bool
    ) async throws -> T {
        throw APIError.invalidURL
    }
}
