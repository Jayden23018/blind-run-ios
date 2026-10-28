import CoreLocation
import XCTest
@testable import blindRun

/// #393：「隐私与授权」页的撤回。断言打在出站请求计数与定位意图上，不打在「状态文字变了」上 ——
/// 文字变了而请求照发、定位照开，才是真正的缺陷。每条撤回都配一条「撤回之前确实在发 / 在定位」的前提。
@MainActor
final class PrivacyAuthorizationTests: XCTestCase {

    private static let request = ParseVoiceOrderRequest(
        transcript: "明天早上七点从人民广场出发",
        latitude: nil,
        longitude: nil,
        current: nil
    )

    /// 🔴 #393 验收：撤回语音下单同意后 `/api/orders/voice/parse` 不再发出。
    func testRevokingVoiceConsentStopsParseRequests() async throws {
        let client = ParseCountingClient()
        let appState = makeBlindAppState(client: client)
        appState.recordVoiceOrderConsent()
        _ = try await appState.voiceOrder.parseOrder(Self.request)
        XCTAssertEqual(client.parseCount, 1, "前提：同意时照常发")

        appState.revokeVoiceOrderConsent()

        XCTAssertFalse(appState.hasVoiceOrderConsent)
        do {
            _ = try await appState.voiceOrder.parseOrder(Self.request)
            XCTFail("撤回后不该解析成功")
        } catch {
            XCTAssertEqual(error as? VoiceOrderConsentError, .notGranted)
        }
        XCTAssertEqual(client.parseCount, 1, "撤回后又发出了解析请求")
    }

    /// 撤回位置同意：本机记录删掉、盲人角色那一份持续定位停掉、求助不再附位置。
    func testRevokingBlindLocationConsentStopsLocationAndEmergencyLocation() {
        let location = LocationService()
        location.interceptLocationManagerForTesting()
        location.handleAuthorizationChange(.authorizedWhenInUse, accuracy: .fullAccuracy)
        let appState = makeBlindAppState(client: ParseCountingClient())
        appState.locationService = location
        appState.recordLocationTrackConsent(.blindLocationTrack)
        XCTAssertEqual(location.updateReasons, [.blindRole], "前提：同意过就在为盲人角色定位")

        XCTAssertTrue(appState.revokeLocationTrackConsent(.blindLocationTrack))

        XCTAssertFalse(appState.hasLocationTrackConsent(.blindLocationTrack))
        XCTAssertFalse(location.isUpdatingLocation, "撤回后不许还在定位")
        XCTAssertTrue(appState.isEmergencyLocationSharingBlocked, "撤回后求助不附位置")
    }

    /// 陪跑进行中拒绝撤回位置同意：撤回会让对方立刻看不到位置、同意页马上再弹。同意保留。
    func testLocationConsentCannotBeRevokedDuringAnEscortSession() async {
        let appState = makeBlindAppState(client: ParseCountingClient())
        appState.recordLocationTrackConsent(.blindLocationTrack)
        appState.liveEscortCoordinator.updateOwnedOrder(orderID: 77, status: .inProgress)

        XCTAssertFalse(appState.canRevokeLocationTrackConsentNow)
        XCTAssertFalse(appState.revokeLocationTrackConsent(.blindLocationTrack))
        XCTAssertTrue(appState.hasLocationTrackConsent(.blindLocationTrack), "陪跑中同意必须保留")
        appState.liveEscortCoordinator.reset()
    }

    /// 文案：撤回结果要说清后果与出路；陪跑中那句要给系统设置这条路。
    func testRevokeCopyStatesConsequenceAndWayBack() {
        XCTAssertTrue(PrivacyAuthorizationCopy.voiceRevoked.contains("重新问你"))
        XCTAssertTrue(PrivacyAuthorizationCopy.voiceRevoked.contains("手动填写"), "要给出不用语音的出路")
        XCTAssertTrue(PrivacyAuthorizationCopy.locationRevoked.contains("求助"))
        XCTAssertTrue(PrivacyAuthorizationCopy.locationBlockedDuringEscort.contains("系统设置"))
    }

    // MARK: - Helpers

    private func makeBlindAppState(client: ParseCountingClient) -> AppState {
        let appState = AppState(apiClient: client, persistence: AppStatePersistenceFactory.makeIsolatedTest(), tokenStore: InMemoryTokenStore())
        appState.handleLoginSuccess(response: LoginResponse(token: "t", userId: 31, role: "BLIND"))
        return appState
    }
}

/// 只数 `/api/orders/voice/parse` 发了几次；别的请求一律失败（本组用例不该发别的）。
private final class ParseCountingClient: APIClientProtocol, @unchecked Sendable {
    private(set) var parseCount = 0

    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        guard path == VoiceOrderEndpoint.parseOrder else { throw APIError.invalidURL }
        parseCount += 1
        // 解析响应全是可选字段，`{}` 就能解出来（同 `VoiceOrderConsentGateTests`）。
        return try JSONDecoder().decode(T.self, from: Data("{}".utf8))
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
