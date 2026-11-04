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

    /// 待命时只在 App 开着时上报位置，后台定位只在出发到跑步结束这段打开（`LocationService.setEscortLocationMode`）。
    /// 后端位置 30 秒过期就退出候选池，所以锁屏后收不到新邀请（审计 V-1，#654）。
    /// 负责人 2026-11-04 定：上线前不改机制，界面如实说。机制改了，这句和用到它的地方一起删。
    static let keepAppOpenNote = "保持助盲跑开着才收得到新邀请，锁屏或切到别的 App 后收不到"

    static let slideHint = "向右滑动开启，开启后才会收到系统派单，并进入接单页。\(keepAppOpenNote)。开启不影响你当前的订单"
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
