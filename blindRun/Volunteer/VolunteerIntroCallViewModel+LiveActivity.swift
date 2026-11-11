import Foundation

// MARK: - 通话磨合页 → 陪跑员实时活动第一段（#920）

extension VolunteerIntroCallViewModel {
    /// V1 商量见面 / V2 已交安排单。子状态与本页同一个判据（`step`）。
    /// 后端不为这两屏推送，只有本页在前台轮询时更新；退到后台后卡停在最后一屏，倒计时照走。
    func syncLiveActivity(orderId: Int64) {
        guard #available(iOS 16.2, *), outcome == .active, let introCall else { return }
        GuideRunActivityController.shared.showFirstSegment(
            attributes: GuideRunActivityContentBuilder.attributes(
                orderID: orderId, startAddress: introCall.startAddress, plannedStart: introCall.plannedStartTime
            ),
            content: GuideRunActivityContentBuilder.introCallState(
                step: step, windowEndsAt: introCall.windowEndsAt?.nilIfBlank?.backendTimestamp
            )
        )
    }

    /// 本轮结束：成了推 V3「已约好」后收卡；没成**立即**收，不画「没约成」（同本页的无声拒绝）。
    func finishLiveActivity(orderId: Int64, bookedOrder: OrderDetailResponse?) {
        guard #available(iOS 16.2, *) else { return }
        GuideRunActivityController.shared.finishFirstSegment(
            orderID: orderId, bookedAs: bookedOrder.map(GuideRunActivityContentBuilder.attributes(from:))
        )
    }
}
