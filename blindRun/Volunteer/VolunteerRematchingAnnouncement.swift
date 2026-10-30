import Foundation

// 系统转走的 `REMATCHING` 怎么念（#477）。单放一个文件：`VolunteerOrderFlowStep.swift`、`SpeechService.swift`
// 都已超长，SwiftLint 棘轮只许它们变短。

extension VolunteerCancelAnnouncement {
    /// 不是自己按的取消、订单却进了 `REMATCHING`（系统转走）。不说「已取消」：订单没取消，是换人。
    /// 「正在重新匹配」对 `REMATCHING` 恒为真 —— 重匹到上限时后端直接转 `CANCELLED`，不会走到这一态。
    static let reassignedBySystem = "此订单不在你名下了，系统正在为跑者重新匹配陪跑员。"
}

extension RunOrderStatus {
    /// `volunteerAnnouncement` 用哪一档念。
    ///
    /// `REMATCHING` 比默认档低一档：闸门到点时后端**先**发 HIGH 横幅 `SCHEDULED_DEPARTURE_GATE_MISSED`
    /// （`OrderLifecycleService.handleDepartureGateMissed`），**再**推状态。同档会把正在念的横幅切断，
    /// 低一档则排在它后面。迟迟不出发（`handleStalledDeparture`）不给陪跑员发横幅，这一句就是唯一的告知，
    /// 没人在说话时照常立刻念。
    var volunteerAnnouncementPriority: AnnouncementPriority {
        switch self {
        case .rematching:
            return .onDemand
        case .pendingMatch, .pendingIntroCall, .scheduledConfirmed, .pendingAccept, .driverEnRoute,
             .driverArrived, .inProgress, .completed, .cancelled, .noVolunteer, .unknown:
            return .counterpartAction
        }
    }
}

extension SpeechService {
    /// 陪跑员端状态句的统一入口：文案 `volunteerAnnouncement`、档位 `volunteerAnnouncementPriority`，
    /// 去重键与 `speakStatusChange` 共用（首页与订单页都订阅同一条推送，只该念出一句）。
    @discardableResult
    func speakVolunteerStatusChange(_ status: RunOrderStatus) -> Bool {
        speakStatusChange(status, text: status.volunteerAnnouncement, priority: status.volunteerAnnouncementPriority)
    }
}
