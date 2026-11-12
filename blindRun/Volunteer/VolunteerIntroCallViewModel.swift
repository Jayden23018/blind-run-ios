import Combine
import SwiftUI

// MARK: - 志愿者侧「接单前通话磨合」

@MainActor
final class VolunteerIntroCallViewModel: ObservableObject {
    @Published private(set) var introCall: IntroCallView?
    /// 这一轮结束时 `introCall` 会清空、通话端点也读不到了，举报入口靠这份留到离开页面。
    @Published private(set) var counterpartUserId: Int64?
    @Published private(set) var outcome: VolunteerIntroCallOutcome = .active
    @Published private(set) var isSubmitting = false
    @Published var errorMessage: String?
    /// 成单后交给 `VolunteerInServiceView` 的首帧订单。成单那一刻 `order.volunteer` 才被写上，
    /// 也正是从那一刻起志愿者才读得到订单详情。
    @Published private(set) var matchedOrder: OrderDetailResponse?
    /// 「跑者王*正在来电」显示到几点（收到 `INTRO_CALL_INCOMING` 的发出时刻 + 2 分钟）。
    @Published private(set) var incomingCallUntil: Date?
    /// 跑者确认那一刻的过渡（#962 第 6 项）。与 `outcome = .matched` 同一拍置上（首帧不会先闪出 ④），
    /// 页面演完约 1 秒后 `finishMatchedTransition` 清掉。判据是纯函数 `VolunteerMatchedTransition.shouldPlay`。
    @Published private(set) var matchedTransition: VolunteerMatchedTransition?
    /// App 在不在前台、上一次拿到通话数据之后进没进过后台。人没一直看着 ③ 时不放过渡（同盲人端 #926）。
    private var isSceneActive = true
    private var backgroundedSinceLastLoad = false

    private weak var appState: AppState?
    private var speechService: SpeechService?
    private var pollingTask: Task<Void, Never>?
    private var orderId: Int64?
    /// 剩 5 分钟 / 1 分钟各播一次。轮询再多也不重复（去重逻辑在 #440 的 `IntroCallCountdownAnnouncer`）。
    private var countdownAnnouncer = IntroCallCountdownAnnouncer()
    /// 上一条来电提醒的发出时刻。重连补读会把同一条再投一次，同一条不重播。
    private var lastIncomingSentAt: Date?

    /// 与盲人订单页同一个 5 秒兜底：这一页的状态由**对方**的动作驱动，
    /// 而 WebSocket 只保证「大概率到」。
    private let pollingInterval: TimeInterval = AppConstants.Timing.orderPollingInterval

    func configure(orderId: Int64, appState: AppState, speechService: SpeechService) {
        self.orderId = orderId
        self.appState = appState
        self.speechService = speechService
    }

    func startPolling() {
        guard orderId != nil else { return }
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            await self?.load()
            while !Task.isCancelled {
                guard let self, self.outcome == .active else { return }
                try? await Task.sleep(nanoseconds: UInt64(self.pollingInterval * 1_000_000_000))
                if Task.isCancelled { return }
                await self.load()
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// 拉一次通话数据。轮询用它，用例也直接调它（不必等 5 秒一轮）。
    func refresh(now: Date = Date()) async {
        await load(now: now)
    }

    private func load(now: Date = Date()) async {
        guard let orderId, let appState else { return }
        do {
            introCall = try await appState.safety.introCall(orderId: orderId)
            if let id = introCall?.counterpartUserId { counterpartUserId = id }
            if isSceneActive { backgroundedSinceLastLoad = false }
            clearLoadFailure()
            announceCountdownIfDue(now: now)
            syncLiveActivity(orderId: orderId)
        } catch let error as APIError {
            if error.endsSession { return }
            guard Self.endsTheRound(error) else {
                noteLoadFailure()
                return
            }
            // 到底是成了还是没成，端点自己不说，也不该说。
            await resolveFinishedRound(orderId: orderId, appState: appState)
        } catch {
            noteLoadFailure()
        }
    }

    // MARK: 子状态

    /// V1 等来电 / V3 等跑者确认。
    ///
    /// 🚩 **服务端说有安排单就是 V3，哪怕这一版读不懂**（`hasUnreadablePlan`）：退回 V1 会让陪跑员以为
    /// 自己还没提交、再提交一版 —— 而每提交一版跑者之前的确认就作废一次。
    var step: IntroCallVolunteerStep {
        introCall?.plan != nil ? .awaitingRunnerConfirmation : IntroCallVolunteerStep.resolve(plan: introCall?.meetupPlan)
    }

    /// 「跑者王*正在来电」那 2 分钟。
    func isShowingIncomingCall(now: Date) -> Bool {
        guard outcome == .active, let incomingCallUntil else { return false }
        return incomingCallUntil > now
    }

    // MARK: 跑者确认那一刻（#962 第 6 项）

    func noteScenePhase(_ phase: ScenePhase) {
        isSceneActive = phase == .active
        if phase == .background { backgroundedSinceLastLoad = true }
    }

    /// 页面演到哪一步。换了一次新的过渡就不碰（`id` 对不上）。
    func revealMatchedTransition(_ id: UUID) {
        guard matchedTransition?.id == id else { return }
        matchedTransition?.revealed = true
    }

    func finishMatchedTransition(_ id: UUID) {
        guard matchedTransition?.id == id else { return }
        matchedTransition = nil
    }

    // MARK: 倒计时

    /// 剩 5 分钟 / 1 分钟各主动播一次（视觉稿时间线第 7 行，陪跑员端只报剩余时间）。平时静默。
    func announceCountdownIfDue(now: Date = Date()) {
        guard outcome == .active,
              let endsAt = introCall?.windowEndsAt?.nilIfBlank?.backendTimestamp,
              countdownAnnouncer.nodeToAnnounce(windowEndsAt: endsAt, now: now) != nil else { return }
        speechService?.speak(IntroCallMeetupCopy.countdownAnnouncement(windowEndsAt: endsAt, now: now, isReviewingPlan: false))
    }

    // MARK: 跑者正在来电（V1′）

    /// 收到 `INTRO_CALL_INCOMING`。`sentAt` 是后端发出的时刻：重连补读来的旧提醒若已过 2 分钟，不显示也不播。
    func noteIncomingCall(sentAt: Date, now: Date = Date()) {
        // 同一条提醒实时与补读各来一次时两边的时刻可能差几毫秒（格式不同），1 秒内按同一条算，不念两遍。
        guard outcome == .active, let until = IntroCallCopy.incomingCallDisplayUntil(sentAt: sentAt, now: now),
              lastIncomingSentAt.map({ abs(sentAt.timeIntervalSince($0)) >= 1 }) ?? true else { return }
        lastIncomingSentAt = sentAt
        incomingCallUntil = until
        speechService?.speak(
            IntroCallCopy.volunteerIncomingCallAnnouncement(counterpartName: introCall?.counterpartName) + IntroCallCopy.volunteerSubmitReminderSpeech
        )
    }

    /// 服务端明说「这一轮结束了」的回答。契约 `GET /api/orders/{id}/intro-call` 只列了两种：
    /// 409 `INTRO_CALL_NOT_ACTIVE`（本轮已结束）、403 `NOT_ORDER_PARTICIPANT`（我们已经不是参与者了）。
    /// 后端没回可解码的错误体时，同样两个状态码落成 `.unknown(statusCode:)`，一并算。
    ///
    /// 🚨 其余一律不算：网络失败、429、解码失败、5xx 都只是「这次没拿到」。
    /// 当成结束会让弱网一次就把志愿者踢出通话页（#428）—— `resolveFinishedRound` 里的
    /// `matchedOrder` 在弱网下同样失败，于是判成「没成」并停轮询，而盲人可能正在拨他的电话。
    static func endsTheRound(_ error: APIError) -> Bool {
        if let code = error.errorCode, code == .introCallNotActive || code == .notOrderParticipant {
            return true
        }
        if case .unknown(let statusCode) = error {
            return statusCode == 403 || statusCode == 409
        }
        return false
    }

    /// 这次没拿到通话数据：留在 `.active`、轮询照常继续，**只在第一次失败时播一遍** ——
    /// 轮询每 5 秒一次，每次都播会把读屏用户淹掉（与盲人侧 `refreshIntroCallIfNeeded` 同一条）。
    private func noteLoadFailure() {
        guard errorMessage != IntroCallCopy.loadFailed else { return }
        errorMessage = IntroCallCopy.loadFailed
        speechService?.speakError(IntroCallCopy.loadFailed)
    }

    /// 拿到了就撤掉上一次的「暂时拿不到」。只撤这一句：表态失败的错误文案不归这里管。
    private func clearLoadFailure() {
        if errorMessage == IntroCallCopy.loadFailed {
            errorMessage = nil
        }
    }

    /// 本轮结束之后**唯一**能判定「这一单是不是我的」的办法。
    ///
    /// 成单时后端 `IntroCallService.confirmMatch` 会写上 `order.volunteer`，
    /// 而 `OrderQueryService.getOrder` 正是拿这个字段判权限 —— 于是：
    /// 订单详情读得到 ⇒ 成了；仍然 403 ⇒ 这一单不是我的。
    /// 这不是取巧，是这个契约下唯一存在的判据：通话端点刻意不回对方的表态。
    private func resolveFinishedRound(orderId: Int64, appState: AppState) async {
        // 过渡的前 0.3 秒要照结束前的 ③ 画，先记下来（#962 第 6 项）。
        let previousIntroCall = introCall
        let previousStep = previousIntroCall == nil ? nil : step
        introCall = nil
        incomingCallUntil = nil
        if let order = try? await appState.safety.matchedOrder(orderId: orderId) {
            matchedOrder = order
            let plays = VolunteerMatchedTransition.shouldPlay(
                previousStep: previousStep,
                outcome: .matched,
                watchedContinuously: isSceneActive && !backgroundedSinceLastLoad
            )
            matchedTransition = plays ? previousIntroCall.map { VolunteerMatchedTransition(previousIntroCall: $0) } : nil
            outcome = .matched
            speechService?.speak(IntroCallCopy.volunteerMatchedAnnouncement(order: order))
            // 震动沿用状态表（`RunOrderStatus.haptic`，约好 / 临期确认都是 `.success`），不新增波形；
            // 与上面那句播报同生同灭（`SpeechService.speakStatusChange` 的注释）。
            order.status.haptic.map(HapticFeedback.play)
        } else {
            outcome = .closed
            speechService?.speak(IntroCallCopy.volunteerRoundClosed)
        }
        finishLiveActivity(orderId: orderId, bookedOrder: matchedOrder)
        stopPolling()
    }

    // MARK: 提交见面安排（V2）

    /// `PUT /intro-call/plan`。**提交本身就是陪跑员的「合适」**（契约），所以这一侧不再发 `decision=ACCEPT`。
    ///
    /// 成功后就地把这一版挂到 `introCall.plan` 上 —— 页面立刻切到 V3，不等下一轮轮询（5 秒的空档里
    /// 陪跑员会以为没交上去、再点一次）。
    func submitPlan(_ request: IntroCallPlanRequest, distanceFromOriginal: Double?) async -> VolunteerMeetupPlanSubmitOutcome {
        guard let orderId, let appState else { return .roundEnded }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let stored = try await appState.safety.submitIntroCallPlan(orderId: orderId, plan: request)
            if var current = introCall {
                current.plan = stored
                introCall = current
            }
            syncLiveActivity(orderId: orderId)
            clearLoadFailure()
            speechService?.speak(IntroCallCopy.volunteerPlanSubmittedAnnouncement)
            return .submitted
        } catch let error as APIError {
            if error.endsSession { return .roundEnded }
            if Self.endsTheRound(error) {
                await resolveFinishedRound(orderId: orderId, appState: appState)
                return .roundEnded
            }
            let mapped = VolunteerMeetupPlanSubmitError.make(for: error, distanceFromOriginal: distanceFromOriginal)
            speechService?.speakError(mapped.message)
            return .failed(mapped)
        } catch {
            let mapped = VolunteerMeetupPlanSubmitError.make(for: error, distanceFromOriginal: distanceFromOriginal)
            speechService?.speakError(mapped.message)
            return .failed(mapped)
        }
    }

    // MARK: 退出

    /// 「不合适」。
    ///
    /// ⚠️ 请求体**没有 reason 字段**，这是后端刻意的：要求填理由等于要求当面说「不」。
    func submit(_ decision: IntroCallDecision) async {
        await perform { safety, orderId in
            try await safety.submitIntroCallDecision(orderId: orderId, decision: decision)
        }
    }

    /// 「未接到来电」。
    ///
    /// 🚩 **与「不合适」是两个端点，不能合并。** 后端的统计口径相反：这条只增
    /// dispatched + timeout，不动 declined —— 他并没有拒绝任何人，而 `acceptanceRate`
    /// 直接进派单评分。且这一对不进候选池硬过滤，没接到电话不代表两人不合适。
    func reportUnreachable() async {
        await perform { safety, orderId in
            try await safety.reportIntroCallUnreachable(orderId: orderId)
        }
    }

    /// 两个表态端点共用的收尾。`orderId` 由这里 guard 出来再交给闭包 ——
    /// 迁移前是先用 `orderId ?? 0` 拼好路径再在这里 guard，那条路径永远不该被构造出来。
    private func perform(_ call: @MainActor (any SafetyServing, Int64) async throws -> Void) async {
        guard let orderId, let appState else { return }
        isSubmitting = true
        errorMessage = nil
        do {
            try await call(appState.safety, orderId)
            isSubmitting = false
            // 表态之后本轮的落点由服务端宣布。让下一次轮询把结果带回来，不在本地假设任何结论。
            await load()
        } catch let error as APIError {
            isSubmitting = false
            if error.endsSession { return }
            if error.errorCode == .introCallNotActive {
                // 窗口已经超时、订单已经换人。这不是失败重试能解决的，直接收尾。
                await resolveFinishedRound(orderId: orderId, appState: appState)
                return
            }
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isSubmitting = false
            let message = "没有提交成功，请再试一次。"
            errorMessage = message
            speechService?.speakError(message)
        }
    }
}
