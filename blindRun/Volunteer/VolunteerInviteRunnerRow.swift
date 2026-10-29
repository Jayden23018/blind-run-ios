import Foundation

/// 邀请卡跑者行要显示和念的字（#339，DECISIONS-v2 V11）。
///
/// 抽成值类型是为了让单测守住三件只在屏幕上才看得见的事：屏幕保留掩码（「跑者李*」，去掉星号会让人以为拿到了全名）、
/// 头像取姓（「李」）、读屏去星号（「跑者李」，否则念「李星号」）；没有称呼时回落成「跑者」与占位「跑」，不编名字。
/// 读屏标签那一行是 `accessibilityElement(children: .ignore)`，UI 用例看不到可见文字，所以只能在这里守。
struct VolunteerInviteRunnerRow: Equatable {
    /// 屏幕上那一行：「跑者李*」或「跑者」。
    let title: String
    /// 头像圆里取姓用的名字（去星号）。`nil` = 显示占位「跑」。
    let avatarName: String?
    /// 整行合成一个焦点念的字：「跑者李，全盲，牵引绳，一起跑过 3 次」。
    let spokenLabel: String

    /// 称呼、跑者情况、一起跑过几次三样都没有 ⇒ `nil`，整行不渲染。
    init?(order: WSNewOrder, summary: String?, together: String?) {
        let name = order.runnerName
        guard name != nil || summary != nil || together != nil else { return nil }
        title = VolunteerOrderFlowCopy.runnerLabel + (name?.display ?? "")
        avatarName = name?.spoken
        spokenLabel = [VolunteerOrderFlowCopy.runnerLabel + (name?.spoken ?? ""), summary, together]
            .compactMap { $0 }
            .joined(separator: "，")
    }
}
