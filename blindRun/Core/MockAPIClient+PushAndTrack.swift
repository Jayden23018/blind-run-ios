import CoreLocation
import Foundation

extension MockAPIClient {
    /// `ApnsTokenRequest` 是只出不进的 Encodable，Mock 侧需要一个可解码的镜像来做校验。
    private struct ApnsTokenRequestProbe: Decodable {
        let deviceToken: String
        let platform: String?
    }

    func handleRegisterApnsToken(body: (any Encodable & Sendable)?) throws -> EmptyResponse {
        guard mockToken != nil, !isAccountDeleted else { throw APIError.unauthorized }
        guard let data = try? JSONEncoder().encode(MockAnyEncodable(body)),
              let request = try? JSONDecoder().decode(ApnsTokenRequestProbe.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "请求格式错误"))
        }
        let isHex = request.deviceToken.count >= 32
            && request.deviceToken.count <= 128
            && request.deviceToken.allSatisfy(\.isHexDigit)
        guard isHex else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "deviceToken 格式不正确"))
        }
        registeredApnsTokens.insert(request.deviceToken)
        return EmptyResponse()
    }

    /// 解绑。`401` 那条分支照抄真实后端的行为，正是它让「先 logout 再解绑」的错误顺序
    /// 在 Mock 上也现原形：logout 之后 `mockToken` 已清，这里就会抛 `unauthorized`。
    func handleUnregisterApnsToken(body: (any Encodable & Sendable)?) throws -> EmptyResponse {
        guard mockToken != nil, !isAccountDeleted else { throw APIError.unauthorized }
        guard let data = try? JSONEncoder().encode(MockAnyEncodable(body)),
              let request = try? JSONDecoder().decode(ApnsTokenRequestProbe.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "请求格式错误"))
        }
        // 幂等：不存在也返 200。
        registeredApnsTokens.remove(request.deviceToken)
        return EmptyResponse()
    }

    /// 后端每页上限 50，Mock 刻意压到 3。
    /// 照搬 50 等于把续读那条路藏起来：没人会为了开发期调试手工造 51 条离线通知，
    /// 于是 `hasMore = true` 在 Mock 上永远不出现，多页补读只能靠上线后出事才被发现。
    private static let mockCatchUpPageSize = 3

    func handleGetMissedNotifications(after: String?) throws -> MissedNotificationPage {
        guard mockToken != nil, !isAccountDeleted else { throw APIError.unauthorized }
        guard let after, !after.isEmpty, !after.allSatisfy(\.isNumber) else {
            throw APIError.serverError(ErrorResponse(code: "INVALID_TIMESTAMP", message: "after 格式错误"))
        }
        // 后端窗口：sent_at > after，24h 内，按时间正序，每页有上限。
        let window = missedNotifications
            .filter { ($0.sentAt ?? "") > after }
            .sorted { ($0.sentAt ?? "") < ($1.sentAt ?? "") }
        let page = Array(window.prefix(Self.mockCatchUpPageSize))
        return MissedNotificationPage(notifications: page, hasMore: window.count > page.count)
    }

    func handleGetOrderTrack(orderId: Int64) throws -> OrderTrackResponse {
        guard let order = orders.first(where: { $0.orderId == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        guard order.status == .completed,
              let startLatitude = order.startLatitude,
              let startLongitude = order.startLongitude else {
            return OrderTrackResponse(
                status: order.status,
                volunteerTrack: [],
                volunteerStats: TrackStats(distanceMeters: 0, durationSeconds: 0, avgPaceSecPerKm: nil),
                blindTrack: [],
                blindStats: TrackStats(distanceMeters: 0, durationSeconds: 0, avgPaceSecPerKm: nil)
            )
        }
        let points = [
            TrackPoint(lat: startLatitude, lng: startLongitude, recordedAt: "2026-07-21T08:00:00Z"),
            TrackPoint(lat: startLatitude + 0.003, lng: startLongitude + 0.002, recordedAt: "2026-07-21T08:12:00Z"),
            TrackPoint(lat: startLatitude + 0.006, lng: startLongitude + 0.004, recordedAt: "2026-07-21T08:24:00Z")
        ]
        return OrderTrackResponse(
            status: order.status,
            volunteerTrack: points,
            volunteerStats: TrackStats(distanceMeters: 820, durationSeconds: 1_440, avgPaceSecPerKm: 1_756),
            blindTrack: points,
            blindStats: TrackStats(distanceMeters: 820, durationSeconds: 1_440, avgPaceSecPerKm: 1_756)
        )
    }

    // MARK: - Location Handler

    /// ⚠️ **这里的三态是后端的 `OrderStatus.sharesLiveLocation()`**：
    /// `DRIVER_EN_ROUTE` / `DRIVER_ARRIVED` / `IN_PROGRESS`。Mock 照**后端**演，不照客户端演。
    ///
    /// 客户端侧对应的是 `RunOrderStatus.fetchesVolunteerLocation`，2026-08-31 与这三态对齐了。
    /// 在那之前客户端用的是 `offersVolunteerDistanceToStart`（`PENDING_ACCEPT` /
    /// `DRIVER_EN_ROUTE` / `DRIVER_ARRIVED`），交集只有中间两态，两头都错：
    /// `PENDING_ACCEPT` 时客户端每 5 秒白调一次而后端恒 404，`IN_PROGRESS` 时后端有数据
    /// 而客户端根本不调。**Mock 一直是对的，正因为它照后端演，那个不对称才被看见** ——
    /// 反例是上一次 Mock 自作主张（造了个后端不发的 `updatedAt`），
    /// 代价是兜底对真实后端 100% 静默失效，开发期一次都没暴露。
    func handleGetVolunteerLocation() -> VolunteerLocationResponse {
        // 同上：这里演的是后端 `sharesLiveLocation()`，**不是**客户端的
        // `fetchesVolunteerLocation`。两边今天恰好同集，换成客户端判定就再也撞不出
        // 后端哪天单方面改了。
        let sharing = orders.first {
            [.driverEnRoute, .driverArrived, .inProgress].contains($0.status) // guard:allow status-set-literal
        }
        return VolunteerLocationResponse(
            success: true,
            code: 200,
            message: nil,
            data: VolunteerLocationData(
                orderId: sharing?.orderId,
                status: sharing?.status,
                // epoch 毫秒，与 WS `VOLUNTEER_LOCATION_UPDATE` 的 `timestamp` 同格式（后端 119c810）。
                updatedAt: sharing.map { _ in Int64(Date().timeIntervalSince1970 * 1_000) },
                lat: AppConstants.Defaults.demoLatitude + 0.002,
                lng: AppConstants.Defaults.demoLongitude + 0.001
            )
        )
    }
}
