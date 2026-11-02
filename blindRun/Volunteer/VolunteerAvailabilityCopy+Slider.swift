import Foundation

// MARK: - 文案

/// 滑动 CTA 的文案挂在 `VolunteerAvailabilityCopy` 上（`VolunteerHomeView.swift:15`），
/// 不另起一个 enum —— 那个类型存在的全部理由就是「这个开关在全 App 只有一个名字」。
extension VolunteerAvailabilityCopy {
    /// 未开启时的静止态。是**邀请**不是指令 —— 志愿者是无偿的，命令句式属于 controlling 型激励
    /// （Motivation Crowding，`docs/research/volunteer-home-incentive-layer-20260914.md` §3.2）。
    /// 2026-10-03 负责人按试用反馈改掉「开始接单」：像外卖派活，少了公益的温度。只改这一句，其余仍叫接单。
    static let slideToOpenTitle = "向右滑动，我现在有空陪跑"

    /// 向右拖过阈值之后。
    static let slideReleaseToOpenTitle = "松手即开启"

    /// 已开启时轨道上的主文案。
    static let availableStatusTitle = "接单中"

    /// 已开启时的副文案。**两件事都要说出来**：轨道此刻既是进入接单页的入口，也是关闭开关的地方。
    /// 只说一半的后果是另一半对不看提示的人等于不存在。
    static let availableActionHint = "点这里进入接单，向左滑动停止"

    /// 开着却收不到单时，第二行后面那半句。
    static let slideLeftToCloseHint = "向左滑动停止"

    /// 向左拖过阈值之后。
    static let slideReleaseToCloseTitle = "松手即停止接单"

    static let slideHint = "向右滑动开启，开启后才会收到系统派单，并进入接单页。开启不影响你当前的订单"
    static let enterHubTitle = "进入接单"
    static let enterHubHint = "查看下一次陪跑、待回复的邀请，也可以在那里暂停接单"
    static let closeTitle = "停止接单"
    static let closeHint = "停止后不会收到新的系统派单，但不影响当前订单"
}

extension VolunteerAvailabilityStatus {
    /// 接单主页顶部胶囊。「接单中」只在真的可派单时说。
    var hubPillTitle: String {
        switch self {
        case .accepting: return VolunteerDispatchHubCopy.acceptingPill
        // 刚滑开时摘要还没刷新，这一刻说「收不到派单」会让人以为开启失败了。
        case .confirming: return VolunteerReadinessCopy.confirmingTitle
        default: return "暂时收不到派单"
        }
    }
}
