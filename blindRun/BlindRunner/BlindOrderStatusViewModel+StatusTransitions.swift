import SwiftUI

extension BlindOrderStatusViewModel {
    /// 页面开着跨过可取消时刻时播一句（后端 #682）。
    ///
    /// **不另起定时器**：`apply` 每 5 秒一次（轮询），按钮也是靠这一轮的重绘变亮的 ——
    /// 两件事挂在同一拍上，不会出现「念了可以取消、按钮还是灰的」。并发模型与轮询同一条。
    func announceArrivalCancelUnlockIfNeeded(for updated: OrderDetailResponse, speakChanges: Bool) {
        let gate = BlindArrivalCancelGate.resolve(order: updated, now: Date())
        defer { lastArrivalCancelGate = gate }
        guard speakChanges,
              let sentence = BlindArrivalCancelGate.unlockAnnouncement(from: lastArrivalCancelGate, to: gate) else { return }
        speechService?.speak(sentence)
    }

    /// 汇合 → 跑步中那三秒倒计时。
    ///
    /// 🔴 **触发点是「状态推到了 `IN_PROGRESS`」，不是谁按了什么。**
    /// 设计稿写的是「任一端按下开始跑步（双方都能按，先按的生效）」：盲人自己按
    /// （`startRun`，后端 #346 起盲人 token 可调 `/start-service`）与陪跑员先按，
    /// 落到这里的都是同一次状态转移 —— 所以倒计时只在这一处起，两种路径不会各数一遍。
    ///
    /// 两条边界都要守住，而且方向相反：
    /// - `previousStatus == nil` ⇒ **冷启动进来时已经在跑了**，不倒数。中途进页面的人
    ///   听一遍「准备开始」是在说一件三公里以前发生过的事。
    /// - `previousStatus == .inProgress` ⇒ 同一态的重复刷新（每 5 秒一轮），不重放。
    ///
    /// 播报走 `announce`（VoiceOver announcement 通道）而**不是** `speak`：
    /// `SpeechService.speak` 会先 `stopSpeaking(.immediate)`，紧接着三拍数字会把
    /// 同一刻正在播的「陪跑服务已开始」整句切断，表现是「只念了开头」
    /// （记忆 `later-speak-silently-cuts-the-earlier-one`）。announcement 不抢合成器、
    /// 也不移动读屏焦点 —— 焦点在这三秒里必须待在原处，那正是原地变形要保住的东西。
    /// `状态清单.md` §2 也是逐字这么要求的：「数字走 announcement 通道播报，
    /// 不插入遍历顺序、不移动焦点」。
    /// 判据抽成**纯静态函数**，理由同 `FlowStepper.accessibilityLabel`：三秒倒计时本身
    /// 只有真机能看，但「什么时候该倒数」是两个布尔判断，不该也要开一次真机才知道对不对。
    /// 上面那两条边界（冷启动不倒数 / 同态刷新不重放）各有一条用例钉着。
    nonisolated static func shouldStartRunCountdown(
        from previousStatus: RunOrderStatus?,
        to status: RunOrderStatus
    ) -> Bool {
        guard status == .inProgress, let previousStatus else { return false }
        return previousStatus != .inProgress
    }

    /// 🔴 **不是「不该倒数就 return」，是「不该倒数就取消」。**
    ///
    /// 志愿者在开跑后三秒内取消（`IN_PROGRESS → REMATCHING`，走 WebSocket 的
    /// `statusUpdatePublisher`）时，只 return 的写法会让旧 Task 照常跑完剩下两拍：
    /// 屏幕是对的（相位已经落回 `.beforeRun`），而耳朵和手指是错的 —— 刚听完
    /// 「陪跑员取消了，正在重新为你匹配」，紧接着念「2」「1」并震两下。
    /// 同一形状也适用于 `IN_PROGRESS → COMPLETED`。
    func updateRunCountdown(from previousStatus: RunOrderStatus?, to status: RunOrderStatus) {
        if Self.shouldStartRunCountdown(from: previousStatus, to: status) {
            startRunCountdown()
        } else if Self.shouldCancelRunCountdown(on: status) {
            cancelRunCountdown()
        }
    }

    /// 与 `shouldStartRunCountdown` 一样抽成纯函数：这两条**不是互补的**
    /// （「不该启动」≠「该取消」—— 同一态的每 5 秒轮询既不该启动也不该取消），
    /// 所以各需要一条自己的用例，写成一个函数的取反会把那个区别抹掉。
    nonisolated static func shouldCancelRunCountdown(on status: RunOrderStatus) -> Bool {
        status != .inProgress
    }

    private func startRunCountdown() {
        runCountdownTask?.cancel()
        runCountdownTask = Task { @MainActor [weak self] in
            for beat in BlindRunCountdown.beats {
                guard let self, !Task.isCancelled else { return }
                self.runCountdown = beat
                // 每拍**轻震**（设计稿逐字）。用 `.tick` 而不是 `.success`：
                // 后者是通知波形，紧接着 `speakStatusChange(.inProgress)` 也会震一次，
                // 三秒里四次同样的波形等于把触觉这条通道的语义洗掉。见 `HapticFeedback.Kind.tick`。
                HapticFeedback.play(.tick)
                // 阶段 1 留下的账①已结：这三拍**不再绕开播报 funnel**。
                // 通告仍然是通告（合成器一个字都不抢），但现在要过一道优先级闸 ——
                // 此刻若正在播求助或警示，这三个数字不会盖掉它
                // （`AnnouncementQueue.allowsAnnouncement`）。档位按 `状态清单.md` §2 取「对方操作」。
                self.speechService?.announce("\(beat)", priority: .counterpartAction)
                try? await Task.sleep(
                    nanoseconds: UInt64(BlindRunCountdown.beatInterval * 1_000_000_000)
                )
            }
            guard let self, !Task.isCancelled else { return }
            self.runCountdown = nil
            // 🔴 **「现在可以跑了」这一刻必须有信号。**
            //
            // 唯一那句「陪跑服务已开始」是三秒**之前**播的（状态刚推过来时），
            // 而变形完成这一刻此前什么都不发生 —— 对看不见屏幕的人，
            // 起跑这个动作没有任何起点。设计稿 §3 逐字：「开始时『开始跑步』+ 强震一次」。
            //
            // 走 `speak` 而**不是** `announce`：VoiceOver 关着时 announcement 是 no-op，
            // 而低视力用户同样需要听到这一句。
            //
            // 阶段 1 留下的账②已结：排进「对方操作」档，正在播求助或警示时**排队等它说完**（`AnnouncementQueue.submit`）；
            // 正在播的若是每公里或按需那两档，它照旧抢过来 —— 起跑这一刻比复述里程要紧。
            self.speechService?.speak(BlindRunCopy.runStartedAnnouncement, priority: .counterpartAction)
            HapticFeedback.play(.success)
            // #682：系统紧急 SOS 提醒排在「开始跑步」之后（低一档才排队，同档会切断它）。冷启动进跑步中不走这里。
            self.speechService?.speak(BlindRunnerFinishCopy.systemSOSReminder, priority: .onDemand)
        }
    }

    /// 换单 / 离开页面时收掉倒计时。
    ///
    /// 不收的后果不是「多演三秒」而是**状态错乱**：任务还在往 `runCountdown` 写值，
    /// 而订单可能已经换成另一单了 —— 那一单的屏幕上会凭空倒数一次。
    func cancelRunCountdown() {
        runCountdownTask?.cancel()
        runCountdownTask = nil
        runCountdown = nil
    }

    /// 状态推进时该播哪一句。除了一处例外，都是 `blindRunnerAnnouncement`。
    ///
    /// 例外是**通话没聊成、退回派单队列**。两个落点各自的常规播报在这一刻都是错的：
    /// - `PENDING_MATCH` 念「订单提交成功，系统正在为你派单」—— 订单是二十分钟前提交的。
    /// - `REMATCHING` 念「正在确认志愿者状态，请稍候」—— 这一刻**没有志愿者可确认**，
    ///   刚才那位候选人从来就没接过单。
    ///
    /// 后端为这条转移专门发了 `INTRO_CALL_CONTINUE`（正文「正在为你寻找合适的陪跑伙伴」），
    /// 两个落点逐字复用它 —— 后端也**刻意**对两种状态发同一条中性文案，不为 `REMATCHING` 另开一条。
    ///
    /// ⚠️ `REMATCHING` 这个落点是 2026-08-26 后端修 P0（N105）之后才有的：通话退出改成回
    /// 「进通话之前那个状态」，而进通话之前它可能就是 `REMATCHING`。
    ///
    /// 🚨 措辞里不许出现「重新」「换一位」「再找一位」这类暗示前面失败过的词：
    /// 无声拒绝的全部要求就是盲人无从得知自己被谁拒过。
    func statusChangeAnnouncement(
        from previousStatus: RunOrderStatus?,
        to updated: OrderDetailResponse
    ) -> String {
        if previousStatus == .pendingIntroCall,
           updated.status == .pendingMatch || updated.status == .rematching {
            // 盲人听过安排单（多半是在 B3 时窗口到点）：先说「本次见面安排未生效」，
            // 免得以为刚听的安排已经定了。`introCall` 此刻还是上一轮的 —— `apply` 播完才清。
            return BlindIntroCallOutcomeCopy.roundEnded(hadPlan: introCall?.plan != nil)
        }
        // 盲人确认安排单那一刻成单：念整句约定（时间、地点、见面位置、陪跑员上衣），
        // 取代「志愿者已接单，请前往……」—— 那句不知道见面位置，也不知道该认哪件衣服。
        if previousStatus == .pendingIntroCall,
           updated.status == .pendingAccept || updated.status == .scheduledConfirmed {
            return BlindIntroCallOutcomeCopy.agreed(order: updated)
        }
        return updated.blindRunnerAnnouncement(distanceText: volunteerDistanceToStartText)
    }
}
