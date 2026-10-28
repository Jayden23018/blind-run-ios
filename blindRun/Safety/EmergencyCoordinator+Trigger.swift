import CoreLocation
import Foundation

// 从 `EmergencyCoordinator.swift` 原样搬来（#502）：那个文件超了 SwiftLint 长度上限，CI 棘轮不许再变长。
extension EmergencyCoordinator {
    // MARK: Trigger

    /// Result of a trigger attempt, so callers can announce without re-deriving the state.
    struct TriggerOutcome: Equatable {
        let state: EmergencySOSState
        /// 所发坐标的误差说明（`EmergencySafetyCopy.impreciseLocationNote`），只在适用时有值。
        var locationNote: String? = nil
        var message: String { (state.message ?? "") + (locationNote ?? "") }
        var isFailure: Bool { state.isFailure }
    }

    /// 这次求助是不是发往 Mock（进程内的假后端，不发网络请求）。不是本机定位的坐标（测试接缝、后端来源）只许走这一条（#500 / #548）。
    ///
    /// 只认「`SafetyService` 包着 `MockAPIClient`」这一种形状，别的实现（包括单测的替身）一律按真实后端算：
    /// 判错的代价不对称 —— 判成「不是 Mock」最多让一条 UI 用例走不通，判成「是 Mock」就是测试坐标出了门。
    static func isMockBacked(_ safety: any SafetyServing) -> Bool {
        (safety as? SafetyService)?.transport is MockAPIClient
    }

    /// Sends one SOS for an owned `IN_PROGRESS` order.
    ///
    /// - Parameter locate: supplies the freshest **real** device sample, already normalized to
    ///   GCJ-02. Callers must source it from `LocationService.latestBackendSample()`, which returns
    ///   `nil` unless a genuine `CLLocation` arrived within its freshness window — the Demo/UI-test
    ///   fallback never produces one, so a demo coordinate cannot reach the cloud through here.
    ///   It is a closure rather than a value so the wait for a fresh fix happens *inside*
    ///   `.locating`: otherwise a blind runner gets several seconds of silence after tapping and the
    ///   duplicate-tap guard is not yet armed.
    /// - Parameter locationFailureReason: read **after** `locate` returns nil, so the copy can tell
    ///   「权限被关」from「拿不到 GPS」. Defaults to nil, which speaks the generic 拿不到定位 branch.
    @discardableResult
    func trigger(
        order: OrderDetailResponse,
        role: UserRole?,
        userID: Int64?,
        safety: any SafetyServing,
        locate: @MainActor () async -> LocatedCoordinate?,
        locationFailureReason: () -> LocationError? = { nil },
        useCountdown: Bool = false
    ) async -> TriggerOutcome {
        // Duplicate-submit protection: one tap at a time, regardless of how the alert was dismissed.
        guard !state.isBusy else {
            return outcome(state)
        }

        // Re-check eligibility against canonical order state at send time. Stale screen state or a
        // WebSocket event must never widen this.
        guard let role, order.status.canTriggerEmergency(as: role) else {
            return finish(.failed("当前订单状态不能发起求助"))
        }
        // 排在取定位之前：凭证已过期就别让人再等 5 秒定位，然后才听到发不出去。
        guard !blocksCloudSOSForExpiredSession else {
            return finish(.unsentSessionExpired)
        }

        state = .locating
        let coordinate = await locate()
        // 等定位这几秒里会话可能已经结束（`reset()` 取消了倒计时任务）：那就一个字节都别发，
        // 否则上一个账号的求助会带着新账号的 token 出去。
        guard !Task.isCancelled else { return finish(.idle) }

        // 🔴 不是本机定位的样本（UI 测试接缝 `.uiTestSeam`、后端来源 `.backend`，#500 / #548）只许发给 Mock（`AGENTS.md` §6「Mock / demo 坐标绝不上传」）。
        // 排在「没坐标照样发」那条降级之前，且不走它：测试样本出现在真实客户端上，说明接缝漏进了真实运行，
        // 此时连「不带坐标的求助」也不该发 —— 发出去的是一条用户从没按过的求助。
        if let coordinate, coordinate.source != .device, !Self.isMockBacked(safety) {
            return finish(.unsentNoLocation(nil))
        }

        guard let coordinate, coordinate.system == .gcj02Backend else {
            guard Self.allowsSubmissionWithoutLocation else {
                return finish(.unsentNoLocation(locationFailureReason()))
            }
            return await send(
                request: EmergencyTriggerRequest(
                    orderId: order.orderId, gpsLat: nil, gpsLng: nil, useCountdown: useCountdown ? true : nil
                ),
                orderID: order.orderId,
                userID: userID,
                safety: safety
            )
        }

        return await send(
            request: EmergencyTriggerRequest(
                orderId: order.orderId,
                gpsLat: coordinate.coordinate.latitude,
                gpsLng: coordinate.coordinate.longitude,
                useCountdown: useCountdown ? true : nil
            ),
            orderID: order.orderId,
            userID: userID,
            safety: safety,
            locationAccuracyMeters: LocationAccuracyPolicy.metersIfWeak(coordinate)
        )
    }

    /// - Parameter locationAccuracyMeters: 所发坐标的精度，只在差于阈值时非 nil。
    ///   事件落地（`activeEvent` 写入）**之后**才记，换事件时 `activeEvent.didSet` 会先清掉旧值。
    private func send(
        request: EmergencyTriggerRequest,
        orderID: Int64,
        userID: Int64?,
        safety: any SafetyServing,
        locationAccuracyMeters: Double? = nil
    ) async -> TriggerOutcome {
        state = .submitting
        do {
            let response = try await safety.triggerEmergency(request)
            // Only a structured success enters submitted state. A 200 that does not decode into
            // `{success, eventId, status}` is a failure, not an acknowledgement.
            guard response.success else {
                return finish(.failed("服务器未受理求助"))
            }
            // 服务端采纳了倒计时 → 照它的截止时刻倒数。没采纳（`countdownEndsAt` 为 null）
            // 说明已经立即发出，走下面的已受理分支 —— 自己再数 3 秒就是「屏幕还在倒数、求助早发出去了」。
            if response.eventStatus == .countdown, let endsAt = response.countdownEndsAt?.backendTimestamp {
                return startServerCountdown(
                    eventID: response.eventId,
                    orderID: orderID,
                    userID: userID,
                    endsAt: endsAt,
                    locationAccuracyMeters: locationAccuracyMeters
                )
            }
            // 后端 #841：本人已有一条已发出、未结案的求助时，再按不新建，回的是同一个 `eventId`。
            // 在覆盖 `activeEvent` 之前判。
            let mergedIntoOpenEvent = activeEvent?.eventID == response.eventId
            activeEvent = .afterTrigger(
                eventID: response.eventId, orderID: orderID, userID: userID,
                status: response.eventStatus, previous: activeEvent
            )
            submittedLocationAccuracyMeters = locationAccuracyMeters
            guard mergedIntoOpenEvent else {
                return finish(.acknowledged(response.eventStatus))
            }
            mergedRetriggerCount += 1
            return finish(.mergedIntoOpenEvent(response.eventStatus))
        } catch let error as APIError {
            if case .rateLimited(let info) = error {
                return await reconcile(
                    after: .cooldown(retryAfterSeconds: info.retryAfterSeconds),
                    locationAccuracyMeters: locationAccuracyMeters
                )
            }
            return await reconcile(after: .failed(error.localizedMessage), locationAccuracyMeters: locationAccuracyMeters)
        } catch {
            return await reconcile(after: .failed("网络异常"), locationAccuracyMeters: locationAccuracyMeters)
        }
    }

    /// 发送失败之后**去问一句后端到底有没有收到**。
    ///
    /// 🔴 解决的是一个会说谎的失败：请求在服务端处理完了、响应在回程丢了（弱网、切基站、
    /// 后台挂起），客户端只看见一个 `网络异常`。那一刻屏幕上写着「求助未发出」，
    /// 而家属的短信其实已经在路上 —— 盲人会据此以为没人知道他出事了。
    /// `429 冷却` 更直接：后端按触发者 SETNX 占位，命中它几乎就等于**刚才那条真的发出去了**。
    ///
    /// **没有做成自动重发。** 后端 `POST /api/emergency/trigger` 没有幂等 key，重发要么
    /// 建出第二个事件、要么撞上 60 秒冷却回 429 —— 而 429 的文案是「请稍后再试」，
    /// 会把一个**已经生效**的求助说成被拒绝。查询是只读的，没有这一类代价，
    /// 而 `GET /api/emergency/active` 本来就是「事件 id 与当前状态的唯一权威来源」（契约原话）。
    ///
    /// 查不到（或这一侧没装恢复入口，比如志愿者 —— 他问到的是对方的事件，不是自己这一条）就老老实实保留失败态 ——
    /// 对账失败不许制造任何救援状态。
    private func reconcile(
        after failure: EmergencySOSState,
        locationAccuracyMeters: Double? = nil
    ) async -> TriggerOutcome {
        _ = finish(failure)
        await refreshActiveEvent()
        guard activeEvent != nil else { return outcome(failure) }
        // 对账找回的就是刚才那条（响应在回程丢了）—— 它带的正是这个坐标。
        if let locationAccuracyMeters { submittedLocationAccuracyMeters = locationAccuracyMeters }
        return outcome(state)
    }

    func finish(_ newState: EmergencySOSState) -> TriggerOutcome {
        state = newState
        return outcome(newState)
    }
}
