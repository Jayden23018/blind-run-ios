import Foundation

// MARK: - 陪跑员 ③ 等跑者确认的等待效果（#962 第 6 项，稿 `docs/ui/mockups/volunteer-order-v7-parity-20261112/` 第 1 条）
//
// 照搬盲人端 ①（#926）：当前圆点呼吸 + 「已等 N 分钟」+ 跑者确认那一刻约 1 秒过渡。
// 时序常数与圆点画法都复用盲人端（`BlindMatchFoundTiming`、`BlindOrderTimelineCurrentDot`），这里只放陪跑员这一页的判据与文案。

enum VolunteerIntroCallAwaitingCopy {
    /// 说明行后半句。拿不到提交时刻时整行只剩这一句。
    static let confirmTail = "跑者确认后即完成约定"
    /// 跑者确认那一刻（过渡前 0.3 秒）当前步的小字（稿 C 帧第一格）。
    static let runnerConfirmed = "跑者已确认"

    /// 安排单提交到现在过了几分钟。`nil` = 这一刻不说等了多久：
    /// 拿不到 / 解析不了 `submittedAt`，或不到 1 分钟（「已等 0 分钟」是噪音；负数 = 设备时钟偏了，同理）。
    static func waitedMinutes(submittedAt: String?, now: Date) -> Int? {
        guard let submitted = submittedAt?.nilIfBlank?.backendTimestamp else { return nil }
        let minutes = Int(now.timeIntervalSince(submitted) / 60)
        return minutes >= 1 ? minutes : nil
    }

    /// 屏上那行：「已等 12 分钟 · 跑者确认后即完成约定」「已等 1 小时 5 分钟 · …」。
    /// 「X 小时 Y 分钟」与盲人端 ① 同一个格式器（`VolunteerMeetupPlanCopy.durationText`，整小时写「2 小时」）。
    static func detail(submittedAt: String?, now: Date) -> String {
        guard let minutes = waitedMinutes(submittedAt: submittedAt, now: now) else { return confirmTail }
        return "\(BlindOrderStageCopy.matchingWaited(minutes: minutes)) · \(confirmTail)"
    }

    /// 读屏念的当前步：「商量见面安排，已等 12 分钟，进行中」。拿不到时长时「商量见面安排，进行中」。
    static func spokenCurrentStep(submittedAt: String?, now: Date) -> String {
        let title = OrderTimelineVocabulary.volunteer.title(.arrangeMeetup)
        let waited = waitedMinutes(submittedAt: submittedAt, now: now).map { BlindOrderStageCopy.matchingWaited(minutes: $0) }
        return [title, waited, "进行中"].compactMap { $0 }.joined(separator: "，")
    }
}

/// 一次「跑者确认了」过渡。view model 在 `outcome` 变 `.matched` 的同一拍置上，页面演完约 1 秒后清掉。
struct VolunteerMatchedTransition: Equatable {
    let id = UUID()
    /// 结束这一轮之前的通话数据。前 0.3 秒照它画旧 ③（`introCall` 那时已经清空）。
    let previousIntroCall: IntroCallView
    /// 已经揭开到 ④（前 0.3 秒为 `false`）。
    var revealed = false

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id && lhs.revealed == rhs.revealed }

    /// 该不该放这段过渡。**只认「人一直看着 ③ 等，然后跑者确认了」**：
    /// - `previousStep == nil`：页面还没拿到过通话数据（冷启动 / 点通知进来时这一轮已结束），人没看过 ③。
    /// - `previousStep == .awaitingCall`：还在 ② 等来电，不是这段等待。
    /// - `watchedContinuously == false`：App 不在前台，或上一次拿到数据之后进过后台。回来直接显示 ④，不补放。
    /// - `.closed`（这轮没约成）一律不放、不打叉：磨合里对方的表态客户端不许显示（AGENTS §5）。
    static func shouldPlay(
        previousStep: IntroCallVolunteerStep?,
        outcome: VolunteerIntroCallOutcome,
        watchedContinuously: Bool
    ) -> Bool {
        outcome == .matched && previousStep == .awaitingRunnerConfirmation && watchedContinuously
    }
}
