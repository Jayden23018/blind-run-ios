import CoreLocation
import Foundation

// 约跑进度卡控制器的纯函数部分（#919）。拆出来只为 SwiftLint 的类型长度上限；单测直接调这些。

@available(iOS 16.2, *)
extension BlindOrderActivityController {
    /// 订单状态 → 卡上哪一屏。穷举 switch：后端加状态时编译器逼一次决策。
    static func decision(
        status: RunOrderStatus,
        plannedStart: Date?,
        reviewingPlan: Bool,
        now: Date
    ) -> Decision {
        switch status {
        case .pendingMatch, .rematching:
            return .show(.matching)
        case .pendingIntroCall:
            return .show(reviewingPlan ? .confirmPlan : .talking)
        case .scheduledConfirmed, .pendingAccept:
            guard let plannedStart, now >= plannedStart.addingTimeInterval(-BlindOrderActivityTiming.preRunLead) else {
                return .show(.scheduled)
            }
            return .show(.preRun)
        case .driverEnRoute:
            return .show(.enRoute)
        case .driverArrived:
            return .show(.arrived)
        case .inProgress, .completed:
            return .end
        case .cancelled:
            return .show(.cancelled)
        case .noVolunteer:
            return .show(.noVolunteer)
        case .unknown:
            return .ignore
        }
    }

    /// 没有卡时这一屏要不要起一张。
    ///
    /// - 第一段（找人那三屏）只起一次：负责人 11-11 定「超 8 小时变灰收起，**不再起新卡**」，
    ///   所以系统到点结束之后、或用户自己划掉之后，App 回前台不能又起一张。
    /// - 第二段（开跑前 30 分钟起）同样只起一次。
    /// - 已约好 / 取消 / 没找到 **从不起卡**：它们只是推给已有那张卡的最后一屏。
    static func startsCard(for phase: BlindOrderActivityPhase, alreadyStarted: (Int) -> Bool) -> Bool {
        if phase.isFindingStage { return !alreadyStarted(1) }
        if phase.isSecondStage { return !alreadyStarted(2) }
        return false
    }

    /// 首页喂的订单没有磨合细节与陪跑员距离：同一屏时沿用卡上已有的值，别把 B3 冲回 B2、把距离冲掉。
    static func merge(
        _ fresh: BlindOrderActivityAttributes.ContentState,
        keeping previous: BlindOrderActivityAttributes.ContentState?,
        source: Source
    ) -> BlindOrderActivityAttributes.ContentState {
        guard source == .home, let previous else { return fresh }
        var merged = fresh
        if fresh.phase == .talking, previous.phase == .confirmPlan {
            merged.phase = .confirmPlan
            merged.confirmDeadline = previous.confirmDeadline
        }
        if fresh.phase == previous.phase, fresh.phase == .enRoute, fresh.distanceMeters == nil {
            merged.distanceMeters = previous.distanceMeters
        }
        return merged
    }

    static func content(
        phase: BlindOrderActivityPhase,
        order: OrderDetailResponse,
        introCall: IntroCallSnapshot?,
        volunteerDistanceMeters: Int?,
        previous: BlindOrderActivityAttributes.ContentState?
    ) -> BlindOrderActivityAttributes.ContentState {
        // 出发时距离：进 B6 后第一次拿到的距离，之后一直沿用（小人从这里走向你）。
        let departure = previous?.phase == .enRoute ? (previous?.departureDistanceMeters ?? volunteerDistanceMeters) : volunteerDistanceMeters
        let carriesDistance = phase == .enRoute
        return BlindOrderActivityAttributes.ContentState(
            phase: phase,
            plannedStart: order.plannedStart?.backendTimestamp,
            confirmDeadline: phase == .confirmPlan ? introCall?.deadline : nil,
            placeName: BlindOrderActivityPresentation.trimmed(order.meetSpotNote)
                ?? BlindOrderActivityPresentation.trimmed(order.startAddress),
            volunteerTopColor: order.volunteerTopColor?.spokenName,
            distanceMeters: carriesDistance ? volunteerDistanceMeters : nil,
            departureDistanceMeters: carriesDistance ? departure : nil
        )
    }

    /// 第一段找人那三屏 8 小时变灰（B10）；别的屏不设。
    static func staleDate(for phase: BlindOrderActivityPhase, startedAt: Date) -> Date? {
        phase.isFindingStage ? startedAt.addingTimeInterval(BlindOrderActivityTiming.findingStaleAfter) : nil
    }

    static func relevance(for phase: BlindOrderActivityPhase) -> Double {
        phase.isSecondStage ? BlindOrderActivityTiming.secondStageRelevance : BlindOrderActivityTiming.firstStageRelevance
    }

    /// 陪跑员离见面点多远（米）。坐标缺一个就是 `nil`（卡上写「陪跑员已出发」）。
    static func volunteerDistanceMeters(
        volunteer: CLLocationCoordinate2D?,
        meetingPoint: CLLocationCoordinate2D?
    ) -> Int? {
        guard let volunteer, let meetingPoint else { return nil }
        return Int(DistanceCalculator.distance(from: volunteer, to: meetingPoint).rounded())
    }
}
