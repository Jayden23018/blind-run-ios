import Foundation

// 从 `EmergencyCoordinator.swift` 原样搬来（#502）：那个文件超了 SwiftLint 长度上限，CI 棘轮不许再变长。
// 倒计时的三个存储属性（`countdownTask` / `countdownAnnouncer` / `isWithdrawing`）留在类体里：extension 不能放存储属性。
extension EmergencyCoordinator {
    // MARK: Countdown（屏 3）

    /// 服务端倒计时的默认秒数（后端 `app.emergency.countdown-seconds`）。**只用于测试与文档** ——
    /// 真正播几秒一律照响应里的 `countdownEndsAt`，两端各存一份时长必然漂移。
    static let countdownSeconds = 3

    /// 倒数显示的上限。挡的是两端时钟差：本机比服务端慢半分钟时，照 `countdownEndsAt` 算出来的
    /// 「还有 33 秒」是假的，而服务端 3 秒后就开火。夹在这里，最坏是屏幕上多数几秒。
    static let maxDisplayedCountdownSeconds = 10

    /// 到点后多等这么久再去问后端「推成正式求助了没有」—— 服务端开火在截止之后还有一段宽限
    /// （`app.emergency.countdown-grace-ms`，默认 1.5 秒），调度器每秒扫一次。
    static let serverFireGrace: TimeInterval = 3

    /// 还剩几秒（向上取整），夹在 `[0, maxDisplayedCountdownSeconds]`。
    nonisolated static func secondsRemaining(until endsAt: Date, now: Date) -> Int {
        let raw = Int(endsAt.timeIntervalSince(now).rounded(.up))
        return min(max(raw, 0), maxDisplayedCountdownSeconds)
    }

    /// 长按 3 秒 / 自定义无障碍动作 / 轻点后的二次确认，三条路都落到这里。
    ///
    /// 先取定位、再带 `useCountdown: true` 发 trigger —— 发出去的是一条**什么都不做**的倒计时事件，
    /// 服务端回 `countdownEndsAt` 后照它倒数（`startServerCountdown`）。
    /// 拿不到定位时和以前一样**一个字节都不发**，并且现在是立刻说，不再白数三秒。
    func beginCountdown(
        order: OrderDetailResponse,
        role: UserRole?,
        userID: Int64?,
        safety: any SafetyServing,
        locate: @escaping @MainActor () async -> LocatedCoordinate?,
        locationFailureReason: @escaping () -> LocationError? = { nil },
        announce: @escaping (String) -> Void = { _ in }
    ) {
        // 与 `trigger` 同一道重复提交保护：倒计时期间再按一下不该叠出第二个倒计时。
        guard !state.isBusy else { return }
        guard let role, order.status.canTriggerEmergency(as: role) else {
            state = .failed("当前订单状态不能发起求助")
            return
        }
        countdownAnnouncer = announce
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await self.trigger(
                order: order,
                role: role,
                userID: userID,
                safety: safety,
                locate: locate,
                locationFailureReason: locationFailureReason,
                useCountdown: true
            )
            // 进了倒计时就由倒数任务接手播报；没进（没定位 / 失败 / 服务端没采纳倒计时）就现在说结果。
            guard !Task.isCancelled, !outcome.state.isCountingDown else { return }
            announce(outcome.message)
        }
    }

    /// 照服务端的截止时刻倒数。trigger 响应与重连恢复（`refreshActiveEvent`）两条路都进这里。
    ///
    /// 每一秒：响一声、震一下、念一句「N 秒后发出，现在取消还来得及」。到点**不宣称已送达**，
    /// 只说「已记录，系统正在处理」，再等一段宽限去问后端要真实状态。
    @discardableResult
    func startServerCountdown(
        eventID: Int64,
        orderID: Int64,
        userID: Int64?,
        endsAt: Date,
        locationAccuracyMeters: Double? = nil
    ) -> TriggerOutcome {
        activeEvent = ActiveEmergencyEvent(eventID: eventID, orderID: orderID, userID: userID, status: .countdown)
        // 在 `activeEvent` 之后写：换事件时它的 didSet 会清掉旧值。恢复路径传 nil = 保留同一事件已有的值。
        if let locationAccuracyMeters { submittedLocationAccuracyMeters = locationAccuracyMeters }
        state = .countingDown(secondsRemaining: Self.secondsRemaining(until: endsAt, now: Date()))
        let announce = countdownAnnouncer ?? { _ in }
        // 误差说明只跟在第一句后面念一次；每秒那句倒数不带，否则每秒重复一遍。
        announce(EmergencySafetyCopy.countdownTitle + (locationNote(for: state) ?? ""))
        // 不 cancel 旧句柄：从 `beginCountdown` 进来时它正是调用链上的那个任务，取消它等于自杀。
        countdownTask = Task { [weak self] in
            while true {
                guard !Task.isCancelled, let self else { return }
                let now = Date()
                let remaining = Self.secondsRemaining(until: endsAt, now: now)
                guard remaining > 0 else { break }
                self.state = .countingDown(secondsRemaining: remaining)
                EmergencyAlarm.countdownTick()
                EmergencyHaptics.countdownTick()
                announce(EmergencySafetyCopy.countdown(secondsRemaining: remaining))
                // 睡到下一个整秒边界（相对截止时刻），而不是固定 1 秒 —— 否则累积误差会让
                // 「1」念完之后还要再等大半秒，那半秒里服务端可能已经开火。
                let untilNextTick = endsAt.timeIntervalSince(now) - Double(remaining - 1)
                try? await Task.sleep(nanoseconds: UInt64(max(untilNextTick, 0.05) * 1_000_000_000))
            }
            guard !Task.isCancelled, let self else { return }
            // 🚩 先松开句柄再改状态：离开 `.countingDown` 时 `didSet` 会取消 `countdownTask`，
            // 而此刻它正是我们自己。
            self.countdownTask = nil
            self.activeEvent?.markCountdownFired(at: endsAt)
            self.state = .acknowledged(.pending)
            announce(self.statusMessage ?? "")
            try? await Task.sleep(nanoseconds: UInt64(Self.serverFireGrace * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self.refreshActiveEvent()
        }
        return outcome(state)
    }

    /// 倒计时里按了「取消」：`PUT /api/emergency/{id}/cancel` 把服务端那条倒计时撤掉。
    ///
    /// 三种结果，文案刻意分开：
    /// - `CANCELLED` → 从未发出（`withdrawnBeforeSending`）
    /// - `FALSE_ALARM` → 请求到达前服务端已经开火，这是一次**撤销已发出的求助**（`cancelledByOwner`）
    /// - 请求失败 → 服务端倒计时照走，**必须说可能已经发出**（`withdrawFailed`），事件保留以便再撤
    ///
    /// 返回 nil = 此刻没有在倒计时，什么都没做（不是「撤销已经发出的求助」—— 那是另一个按钮）。
    @discardableResult
    func cancelCountdown(safety: any SafetyServing) async -> TriggerOutcome? {
        guard state.isCountingDown, !isWithdrawing else { return nil }
        countdownTask?.cancel()
        countdownTask = nil
        EmergencyAlarm.stopAll()
        guard let active = activeEvent else { return finish(.idle) }
        isWithdrawing = true
        defer { isWithdrawing = false }
        do {
            let response = try await safety.cancelEmergencyByOwner(eventId: active.eventID)
            guard response.success else {
                return finish(.withdrawFailed(nil))
            }
            activeEvent = nil
            return finish(response.status == EmergencyEventStatus.cancelled.rawValue
                ? .withdrawnBeforeSending
                : .cancelledByOwner)
        } catch let error as APIError {
            if error.errorCode == .emergencyAlreadyClosed {
                activeEvent = nil
                return finish(.idle)
            }
            return finish(.withdrawFailed(error.localizedMessage))
        } catch {
            return finish(.withdrawFailed(nil))
        }
    }
}
