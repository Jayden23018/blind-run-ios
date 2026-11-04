import Foundation

// 通话磨合页的防误触与提醒（#660 B-14 / V-9 / V-19）。单放一个文件：`IntroCallModels.swift` 已超长，
// SwiftLint 棘轮只许它变短。

/// 🚨 **确认文案保持中性**（`AGENTS.md` §5「无声拒绝」）：不提轮次、不提「还剩几次机会」、
/// 不提对方表态。客户端算不出这些，也不许显示 —— 「这是最后一次」本身就在告诉盲人前面几位没成。
extension IntroCallCopy {

    // MARK: 盲人侧 · 更换陪跑员的确认

    /// 「更换陪跑员」按下去先问一句（B-14：它紧跟在「确认见面安排」后面，读屏右划时误双击就会丢掉谈好的人）。
    static let blindDeclineConfirmTitle = "确认更换陪跑员？"
    static let blindDeclineConfirmMessage = "确认后，这次通话确认结束，系统会继续为你寻找陪跑员。"
    static let blindDeclineConfirmButton = "确认更换"
    static let declineConfirmCancelButton = "取消"

    // MARK: 陪跑员侧 · 「不合适」「未接到来电」的确认

    static let volunteerDeclineAccessibilityHint = "结束这次通话确认，系统会把此订单派给下一位"
    static let volunteerDeclineConfirmTitle = "确认不合适？"
    static let volunteerDeclineConfirmMessage = "确认后，这次沟通结束，系统会把此订单派给下一位陪跑员。"
    static let volunteerDeclineConfirmButton = "确认不合适"

    static let volunteerUnreachableConfirmTitle = "确认没有接到来电？"
    static let volunteerUnreachableConfirmMessage = "确认后，这次沟通结束，系统会把此订单派给下一位陪跑员。"
    static let volunteerUnreachableConfirmButton = "确认没接到"

    /// 进页后多久才出现「未接到来电」（V-9：原来第 0 秒就能按）。
    ///
    /// 取 5 分钟的理由：跑者先要听完通话页、找到拨号按钮再拨出，读屏用户这一步常要一两分钟；
    /// 后端窗口默认 20 分钟（`app.intro-call.window-minutes`，客户端读不到具体值），
    /// 5 分钟后再给这个出口，仍留出大半个窗口给下一位候选人。
    static let volunteerUnreachableDelayMinutes = 5

    /// 「未接到来电」还没出现时，原位置那一行字。让人知道出口在哪、什么时候出现。
    static let volunteerUnreachablePendingNotice =
        "跑者可能还在准备拨号。\(volunteerUnreachableDelayMinutes) 分钟后仍没接到来电，可在这里告诉系统。"

    // MARK: 陪跑员侧 · 聊完提醒提交（V-19）

    /// App 不知道电话打完了没有，「合适」只能靠提交见面安排表达。没提交就会等到窗口超时。
    static let volunteerSubmitReminder = "聊完记得在这里提交结果：合适就填写见面安排，不合适就按「不合适」。"
    /// 跑者来电提醒播完后接着念的半句。短一点：这时他可能正要接电话。
    static let volunteerSubmitReminderSpeech = "聊完记得回到这一页提交结果。"
}

/// 「未接到来电」什么时候出现。按**这一轮**记本次启动里第一次看到通话页的时刻：
/// 退出再进来不重新计时（否则进出一次就要再等 5 分钟）；杀掉 App 后重新计时 —— 宁可多等，不提前给。
///
/// 「这一轮」= 订单号 + 窗口截止时刻。只按订单号记不够：报过「未接到来电」的这一对不进候选池硬过滤，
/// 同一单可能在同一次启动里再派给他，新一轮不能沿用上一轮的计时。
@MainActor
enum VolunteerIntroCallUnreachableGate {
    struct Round: Hashable {
        let orderId: Int64
        let windowEndsAt: String?
    }

    private static var firstSeenAt: [Round: Date] = [:]

    /// 记下第一次看到的时刻，返回它。已有记录时不覆盖。
    @discardableResult
    static func noteSeen(_ round: Round, now: Date = Date()) -> Date {
        if let seen = firstSeenAt[round] { return seen }
        firstSeenAt[round] = now
        return now
    }

    static func isAvailable(firstSeenAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(firstSeenAt) >= TimeInterval(IntroCallCopy.volunteerUnreachableDelayMinutes * 60)
    }

    #if DEBUG
    static func resetForTesting() { firstSeenAt = [:] }
    #endif
}
