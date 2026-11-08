import Foundation

/// 一条已经过新鲜度判据与 GCJ-02 边界的对方位置（OpenSpec `unify-order-live-tracking` design §3）。
struct FreshPeerLocation: Sendable, Equatable {
    let orderID: Int64
    let located: LocatedCoordinate
    /// 只有 `BLIND_LOCATION_UPDATE` 带精度（`accuracyM`），陪跑员位置恒为 nil。
    let accuracyMeters: Double?
    /// 离过期还剩多少秒（阈值减去收到时的样本年龄）。
    let remaining: TimeInterval
}

/// 对方位置「还新不新」的唯一判据。两端订单页与跑者 REST 兜底都用它，阈值只有一个。
///
/// 判法逐行照搬两端订单页原有的 `handleVolunteerLocationUpdate` / `handleBlindLocationUpdate`：
/// 年龄 = 现在 − 采样时刻（不小于 0），`年龄 <= 阈值` 才收，坐标只经 `BackendCoordinateNormalizer.backend` 一次。
struct PeerLocationFreshness: Sendable {
    let threshold: TimeInterval

    nonisolated init(threshold: TimeInterval = LiveEscortSessionCoordinator.peerFreshness) {
        // 与两个订单页 init 里原有的下限相同。
        self.threshold = max(0.01, threshold)
    }

    /// - Parameters:
    ///   - expectedOwner: 这一端要的是谁的位置（跑者页要 `.volunteer`，陪跑员页要 `.blind`）。
    ///   - orderID: 当前跟着的那一单；nil 时一律不收。
    func accept(
        _ sample: RealtimePeerLocationSample,
        expectedOwner: RealtimePeerRole,
        orderID: Int64?,
        now: Date
    ) -> FreshPeerLocation? {
        guard sample.ownerRole == expectedOwner, let orderID, sample.orderId == orderID else { return nil }
        let capturedAt = Date(timeIntervalSince1970: TimeInterval(sample.timestampMilliseconds) / 1_000)
        let age = max(0, now.timeIntervalSince(capturedAt))
        guard age <= threshold,
              let located = BackendCoordinateNormalizer.backend(
                  latitude: sample.latitude,
                  longitude: sample.longitude,
                  capturedAt: capturedAt
              ) else { return nil }
        return FreshPeerLocation(
            orderID: orderID,
            located: located,
            accuracyMeters: sample.accuracyMeters,
            remaining: threshold - age
        )
    }

    /// 跑者 REST 兜底判「WebSocket 样本还新不新」。
    func isFresh(capturedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(capturedAt) <= threshold
    }
}
