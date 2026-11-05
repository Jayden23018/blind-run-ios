import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
protocol BlindRunTestSupport {}

extension BlindRunTestSupport {
    // MARK: - Helpers

    func makeDispatchOrder(
        orderId: Int64,
        requiresIntroCall: Bool? = true,
        dispatchTimeoutSeconds: Int = 30
    ) -> WSNewOrder {
        WSNewOrder(
            type: "NEW_ORDER",
            timestamp: "2026-06-25T19:30:00",
            orderId: orderId,
            startAddress: "朝阳公园南门",
            startLatitude: 39.9342,
            startLongitude: 116.4740,
            distanceKm: 0.1,
            plannedStart: "2026-06-25T20:00:00",
            plannedEnd: "2026-06-25T21:00:00",
            dispatchTimeoutSeconds: dispatchTimeoutSeconds,
            priority: "HIGH",
            pacePreference: "MODERATE",
            hasGuideDog: false,
            requiresIntroCall: requiresIntroCall
        )
    }

    func makeOrder(
        orderId: Int64,
        status: RunOrderStatus,
        createdAt: String = "2026-06-25T10:00:00Z",
        startLatitude: Double? = 39.9342,
        startLongitude: Double? = 116.4740,
        endAddress: String? = nil,
        endLatitude: Double? = nil,
        endLongitude: Double? = nil
    ) -> OrderDetailResponse {
        OrderDetailResponse(
            orderId: orderId,
            status: status,
            startAddress: "朝阳公园南门",
            startLatitude: startLatitude,
            startLongitude: startLongitude,
            endAddress: endAddress,
            endLatitude: endLatitude,
            endLongitude: endLongitude,
            plannedStart: "2026-06-25T20:00:00Z",
            plannedEnd: "2026-06-25T21:00:00Z",
            blindName: "李明",
            blindPhone: status == .pendingMatch ? nil : "13800001001",
            volunteerPhone: status == .pendingMatch ? nil : "13800000002",
            acceptedAt: status == .pendingMatch ? nil : "2026-06-25T19:50:00Z",
            createdAt: createdAt,
            expectedDurationMinutes: 60,
            pacePreference: .moderate,
            routePreference: .parkTrail,
            routeNotes: nil,
            hasGuideDogThisRun: false,
            specialNotes: nil,
            visionLevel: "TOTAL_BLIND",
            tetherPreference: "TETHER_ROPE",
            chatPreference: "PREFER_CHAT"
        )
    }

    func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }

    func setMockRole(_ role: UserRole, appState: AppState) async throws {
        appState.switchRole(to: role)
        let _: SetRoleResponse = try await appState.apiClient.post(
            "/api/user/role",
            body: SetRoleRequest(role: role)
        )
    }

    /// 派单摘要的罐装序列。取代 `DispatchSummarySequenceAPIClient` /
    /// `RecoveringDispatchSummaryAPIClient` 两个传输桩 —— 它们做的都是
    /// 「第一次回 A，之后回 B」，那是一串罐装值，不是业务判定。
    static func makeDispatchSummaryService(
        first: Result<VolunteerDispatchSummaryResponse, Error>,
        rest: VolunteerDispatchSummaryResponse
    ) -> FakeOrderService {
        let service = FakeOrderService()
        service.dispatchSummaryResults = [first]
        service.dispatchSummaryResult = .success(rest)
        return service
    }

    static func decodeDispatchSummary(_ json: String) -> VolunteerDispatchSummaryResponse {
        // swiftlint:disable:next force_try
        try! JSONDecoder().decode(VolunteerDispatchSummaryResponse.self, from: Data(json.utf8))
    }

    static var dispatchSummaryAvailable: VolunteerDispatchSummaryResponse {
        decodeDispatchSummary(
            #"{"canDispatch":true,"notAvailableReasons":[],"wantsDispatch":true,"coverageRadiusKm":10}"#
        )
    }

    func makeVolunteerProfile(
        name: String = "测试志愿者",
        verificationStatus: String = "not_submitted",
        adminReviewStatus: String? = nil,
        isAvailable: Bool = false,
        registrationStep: String? = nil,
        canAcceptOrders: Bool? = nil
    ) -> VolunteerProfileResponse {
        VolunteerProfileResponse(
            name: name,
            verificationStatus: verificationStatus,
            adminReviewStatus: adminReviewStatus,
            registrationStep: registrationStep,
            canAcceptOrders: canAcceptOrders,
            isAvailable: isAvailable,
            availableTimeSlots: nil,
            acceptsGuideDog: nil,
            paceRange: nil
        )
    }

    func makeApprovedVolunteerProfile(isAvailable: Bool = true) -> VolunteerProfileResponse {
        makeVolunteerProfile(
            verificationStatus: "approved",
            isAvailable: isAvailable
        )
    }
}
