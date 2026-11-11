import SwiftUI

extension BlindOrderStatusViewModel {
    /// 拉陪跑中与已完成那两屏的三个数字。跟着订单轮询走，节流到 `trackPollingInterval`。
    ///
    /// 三种走法，别合并：
    /// - `IN_PROGRESS` —— 按 10 秒节流反复拉，顺带判每公里里程碑。
    /// - `COMPLETED` —— **绕过节流拉最后一次终值**，之后不再拉；里程碑基线清掉
    ///   （再进同一单不该补播一次「已跑 5 公里」）。数字**不清空**：它就是 ④ 那一屏的内容。
    /// - 其余状态 —— 三样一起清掉（统计 / 节流时刻 / 里程碑基线）。少清一个，
    ///   下次进同一单就会顶着上一段的数字，或者一进来就补播一次里程碑。
    func refreshTrackStatsIfNeeded(for order: OrderDetailResponse, appState: AppState) async {
        // 里程碑基线：只要不在跑动中就清。完成态也清 —— 否则再进同一单会补播一次
        // 「已跑 5 公里」。放在决策之外是因为它对 `.skip` 与 `.fetch` 两条路都要做。
        if order.status != .inProgress { kilometerMilestones.reset() }

        var isFinalTrackFetch = false
        switch Self.trackFetchDecision(
            status: order.status,
            didFetchFinalTrack: didFetchFinalTrack,
            lastFetchAt: lastTrackFetchAt,
            now: Date()
        ) {
        case .clear:
            trackStats = nil
            liveRunRoute = []
            lastTrackFetchAt = nil
            didFetchFinalTrack = false
            return
        case .skip:
            return
        case .fetch(let isFinal):
            lastTrackFetchAt = Date()
            isFinalTrackFetch = isFinal
        }

        do {
            let safety = appState.safety
            let orderID = order.orderId
            // 🔴 **终值那一次必须限时。** 完成播报排在它后面，而 `URLSession` 的请求超时是
            // 15 秒、资源超时 20 秒（`APIClient.swift:282-283`）—— 网络一抖，
            // 「张伟结束了本次陪跑」就可能十几秒之后才出声。对刚刚跑完、看不见屏幕的人，
            // 那十几秒里发生的事是「陪跑员松开了引导绳，而 App 一个字没说」。
            // 跑动中那条不限时：它每 10 秒还有下一次，早一秒晚一秒没人听得出来。
            let track: OrderTrackResponse
            if isFinalTrackFetch {
                track = try await HomeLoadCoordinator.run(
                    timeout: Self.finalTrackDeadline,
                    operationName: "blind-order-final-track"
                ) {
                    try await safety.orderTrack(orderId: orderID)
                }
            } else {
                track = try await safety.orderTrack(orderId: orderID)
            }
            trackStats = track.blindStats
            liveRunRoute = track.primaryRouteCoordinates
            // 🔴 **只在成功之后才算「终值拉过了」。** 置位放在请求之前的写法会让任何一次
            // 失败（网络抖动、或者上面那次自我取消）把这一单永久锁在 `.skip` 上 ——
            // 屏幕上三个 `--`、而读屏还会一直念「正在获取」，也就是一直撒谎。
            if isFinalTrackFetch { didFetchFinalTrack = true }
            // 下面两件事**只在跑动中做**，已完成那一次终值拉取不做：
            // ① 锁屏卡在 `COMPLETED` 已经该结束了（`liveActivityPlan` 判 nil），
            //    往一张正在收起的卡上推数字只会多一次同步；
            // ② 里程碑基线刚在上面被 reset，这一次调用必然只定基线、不播 ——
            //    靠那个隐式事实等于把「跑完之后不补播已跑 N 公里」寄托在另一个函数的内部行为上。
            if order.status == .inProgress {
                // 推给锁屏卡，顺带复位它自己的节流器 —— 不推的话协调器会为同一单再拉一次
                // 同一个 `/track`，跑动中每 10 秒多发一个请求。
                appState.liveEscortCoordinator.submitTrackStats(track.blindStats, orderID: order.orderId)
                announceKilometerMilestoneIfNeeded(track.blindStats)
            }
        } catch {
            // **不清空已有的数字、不播报。** 与 `refreshVolunteerLocationFallbackIfNeeded` 同一条理由：
            // 跑动中一次网络抖动把屏幕上的距离归零，比暂时不更新糟得多；而每 10 秒往耳朵里塞一句
            // 「获取失败」会占住盲人用来听车流和同伴说话的那条通道，且没有任何可执行的动作。
        }
    }

    /// 页面那次不限时的轨迹加载（`CompletedTrackSummaryViewModel.load`，喂 footer 的
    /// 轨迹总结）回来之后，把数字补给卡片与「重复当前状态」。
    ///
    /// 🚩 它只在**终值那一次限时到点或失败**时才有活干：正常路径上 `trackStats` 已经有值，
    /// 这里 guard 掉。不补的后果是 ④ 那张卡顶着三个 `--`，而同一页下面的轨迹总结里
    /// 明明有数字 —— 同一屏上两个矛盾的事实，对读屏用户尤其难解释。
    func adoptCompletedTrackStats(_ stats: TrackStats?) {
        guard order?.status == .completed, trackStats == nil, let stats else { return }
        trackStats = stats
    }

    /// 这一轮要不要拉 `/track`。
    enum TrackFetchDecision: Equatable {
        /// 拉。`isFinal` = 这是完成态那唯一一次终值拉取。
        case fetch(isFinal: Bool)
        /// 不拉，但屏幕上已有的数字**留着**。
        case skip
        /// 不拉，并且把数字清掉（这一态不该有数字）。
        case clear
    }

    /// 判据抽成纯函数，理由同 `shouldStartRunCountdown`：这里三条分支的错误形态全是静默的
    /// —— 完成态误落 `.clear` ⇒ ④ 那一屏三个数字变 `--`（而它的全部内容就是那三个数）；
    /// 完成态照节流走 ⇒ 屏幕停在最后一个中途值；跑动中漏了节流 ⇒ 每 5 秒多发一个请求。
    nonisolated static func trackFetchDecision(
        status: RunOrderStatus,
        didFetchFinalTrack: Bool,
        lastFetchAt: Date?,
        now: Date
    ) -> TrackFetchDecision {
        switch status {
        case .inProgress:
            if let lastFetchAt, now.timeIntervalSince(lastFetchAt) < trackPollingInterval {
                return .skip
            }
            return .fetch(isFinal: false)
        case .completed:
            // 🔴 **刻意不看节流。** 完成那一刻上一次跑动中的拉取往往还在 10 秒窗内，
            // 照节流跳过就把中途值（5.18）留在了 ④ 那一屏上。拉过一次就不再拉 ——
            // 已完成的轨迹不会再变。
            return didFetchFinalTrack ? .skip : .fetch(isFinal: true)
        case .pendingMatch, .pendingIntroCall, .scheduledConfirmed, .pendingAccept,
             .driverEnRoute, .driverArrived, .rematching, .cancelled, .noVolunteer, .unknown:
            return .clear
        }
    }

    /// 完成那一刻**唯一**那一句。`/track` 的终值拉过之后才调（`loadOrder` 末尾）。
    ///
    /// 走 `speakStatusChange` 这个 funnel 而不是直接 `speak`，是为了拿它那两件东西：
    /// 「同一状态只播一次」的 guard（跨轮询、跨重进页面）与 `RunOrderStatus.haptic`
    /// —— 强震一次就挂在那张表上（`.completed` → `.strong`），
    /// 在这里另外补一次 `HapticFeedback.play` 会变成两下。
    ///
    /// 🔴 **不在这里判「里程为空就不播」**：这件事（陪跑结束了）比那个数字要紧得多，
    /// `runFinishedAnnouncement` 自己会在拿不到里程时把那半句去掉。
    func startCompletionAnnouncement(
        _ kind: CompletionAnnouncement,
        order: OrderDetailResponse
    ) {
        completionTask?.cancel()
        completionTask = Task { [weak self] in
            guard let self else { return }
            // 拉终值。限时 3 秒（`finalTrackDeadline`）—— 拉不到就带着没有里程的那一句出声。
            if let appState = self.appState {
                await self.refreshTrackStatsIfNeeded(for: order, appState: appState)
            }
            // 🔴 **刻意不走 `speakStatusChange` 那个 funnel。** 它的 guard 是
            // `status != lastSpokenStatus`，而 `lastSpokenStatus` 是**全 App 一份**的
            // （`SpeechService` 是 `blindRunApp` 上的 `@StateObject`）——
            // 连着从历史记录点开两张已完成的单，第二张会被静默吞掉：两张单的状态
            // 都是 `COMPLETED`，而「状态变了没有」是**每张单各自**的事实。
            // 这一条恰好打在 `.coldStart` 存在的理由上（它就是为「点开一张旧单」写的），
            // 且改版前由 `.task` 里那句轨迹总结兜着 —— 那句已经删了。
            // 用例 `testTwoFinishedOrdersInARowBothSpeak` 钉住（打回 funnel 写法即红）。
            //
            // 去重责任因此留在 view model 这一层，那里本来就是按单记的：
            // `completionAnnouncement(from:to:)` 要求 `previousStatus != .completed`，
            // 而 `apply` 的三个调用者都在主 actor 上、`order` 是同步写的 ⇒ 不存在交错窗口。
            //
            // 触觉跟着这一句就地播，而不是靠 `RunOrderStatus.haptic` 那张表 ——
            // 「触觉必须伴随一句话」那条不变量要的是**同生同灭**，这里两行紧挨着；
            // 而走 funnel 的版本在上面那种情况下是**话没播、震也不震**（整条返回 false）。
            self.speechService?.speak(
                Self.completionText(kind, order: order, stats: self.trackStats), // 跑者自己结束的单另说一句
                priority: .counterpartAction
            )
            HapticFeedback.play(.strong)
        }
    }

    /// 完成那一句的正文。纯函数，两种语境各一句。
    nonisolated static func completionAnnouncementText(
        _ kind: CompletionAnnouncement,
        order: OrderDetailResponse,
        stats: TrackStats?
    ) -> String {
        switch kind {
        case .justFinished:
            return BlindRunCopy.runFinishedAnnouncement(
                name: order.volunteerNameForSpeech,
                distanceText: stats?.distanceText
            )
        case .coldStart:
            // 既有的状态句 + 三个数字。数字这一半原先由 `.task` 里那句轨迹总结承担，
            // 而它**同档打断**了状态句（记忆 `later-speak-silently-cuts-the-earlier-one`）——
            // 合成一句之后两半都能听全。
            var parts = [order.blindRunnerAnnouncement(distanceText: nil)]
            if let stats, let clause = spokenStatsClause(stats, isFinished: true) {
                parts.append(clause)
            }
            return parts.joined(separator: " ")
        }
    }

    /// 三个数字的**播报**口径（`9'06"` 会被念成「九撇零六引号」，所以不能用屏幕口径）。
    ///
    /// 抽出来是因为它有两个调用点 —— 「重复当前状态」与完成播报。两处各拼一份的下场是
    /// 同一组数字在两个入口念得不一样，而屏幕上不会有任何症状。
    nonisolated static func spokenStatsClause(_ stats: TrackStats, isFinished: Bool) -> String? {
        let spoken = [
            stats.distanceText.map { "已跑 \($0)" },
            stats.durationText.map { "用时 \($0)" },
            // 标签与那一屏上写的那格一致（③「配速」/ ④「平均配速」，判据在 `BlindRunCopy`）。
            stats.averagePaceText.map { "\(BlindRunCopy.metricPaceLabel(isFinished: isFinished)) \($0)" }
        ].compactMap { $0 }
        guard !spoken.isEmpty else { return nil }
        return spoken.joined(separator: "，") + "。"
    }

    /// 每跑满一公里播一句「已跑 N 公里」。**只播距离** —— 不播配速、心率、卡路里
    /// （`docs/research/blind-runner-ui-reference-study-20260915.md` §7.4）。
    /// 播不播的判定在 `KilometerMilestoneTracker`，这里只负责发声与震动。
    private func announceKilometerMilestoneIfNeeded(_ stats: TrackStats) {
        guard let kilometers = kilometerMilestones.milestone(forDistanceMeters: stats.distanceMeters) else {
            return
        }
        // 最低档：正在播的任何别的东西都比它要紧，而它排队超过 10 秒就自己丢掉
        // （`AnnouncementQueue.perKilometerMaxQueueAge`）—— 一句迟到的「已跑 2 公里」
        // 会让跑者按一个过期的数字去判断还能跑多久。前置音（单声 0.3 秒）按档自动加。
        speechService?.speak("已跑 \(kilometers) 公里", priority: .perKilometer)
        // ponytail: 复用既有的三种系统语义之一，不为里程碑自造波形（见 `HapticFeedback`）。
        HapticFeedback.play(.success)
    }
}
