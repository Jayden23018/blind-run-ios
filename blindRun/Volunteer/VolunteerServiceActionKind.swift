import SwiftUI

/// 陪跑员订单相关按钮的标题。只剩三处在读：首页预约区块（确认 / 释放）与跑步中页（取消）。
enum VolunteerServiceActionKind: Hashable {
    case cancelOrder
    /// 跨天预约单的临期确认（`POST /api/orders/{id}/confirm-departure`）。
    case confirmDeparture
    /// 跨天预约单的「我去不了」。**动作与 `.cancelOrder` 完全相同**（同一个取消端点、同样转
    /// `REMATCHING`），单独一个 case 只为换文案。
    ///
    /// 换文案不是修饰：对志愿者，「取消订单」读起来像是在替盲人取消这一单，而实际后果是
    /// 「这一单回到派单池换个人」。这个差别在预约态下尤其要紧 —— 他要在几天前做这个决定，
    /// 而**确认与释放必须并置且同样好按**（对标志愿者排班软件的 confirm-or-release：
    /// 释放做得难，只会把 no-show 从「提前告知」变成「当天失联」，
    /// 见 `docs/research/volunteer-scheduled-order-confirm-ui-20260906.md` §二.1）。
    case releaseScheduled

    var title: String {
        switch self {
        case .confirmDeparture:
            return "确认我还会去"
        case .releaseScheduled:
            return "我去不了"
        case .cancelOrder:
            return "取消订单"
        }
    }
}
