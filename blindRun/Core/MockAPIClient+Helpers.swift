import CoreLocation
import Foundation

extension MockAPIClient {
    // MARK: - Helpers

    #if DEBUG
    /// UI 用例演后端看门狗（#456）：出发中 / 已到达的那一单转 `REMATCHING`。返回订单号与原状态，供调用方按后端顺序补推送。
    func takeAwayDepartedOrderForUITesting() -> (orderId: Int64, from: RunOrderStatus)? {
        guard let index = orders.firstIndex(where: { $0.status.isTakenAwayWhenVolunteerLost }) else { return nil }
        let from = orders[index].status
        orders[index] = updateOrderStatus(orders[index], to: .rematching)
        return (orders[index].orderId, from)
    }
    #endif

    /// - Parameter meetupPlan: 通话磨合约成时传这一轮的安排单：改过的时间、地点覆盖订单原有那几列，
    ///   见面位置与颜色写进三个新列（后端 #755 口径）。其余调用点不传。
    func updateOrderStatus(
        _ order: OrderDetailResponse,
        to newStatus: RunOrderStatus,
        volunteerPhone: String? = nil,
        meetupPlan: IntroCallPlanView? = nil
    ) -> OrderDetailResponse {
        appendStatusLog(
            orderId: order.orderId,
            from: order.status,
            to: newStatus,
            remark: Self.mockStatusLogRemark(to: newStatus)
        )
        let hasAcceptedVolunteer = Self.mockHasAcceptedVolunteer(newStatus)
        return OrderDetailResponse(
            orderId: order.orderId,
            status: newStatus,
            startAddress: meetupPlan?.startAddress ?? order.startAddress,
            startLatitude: meetupPlan?.startLatitude ?? order.startLatitude,
            startLongitude: meetupPlan?.startLongitude ?? order.startLongitude,
            endAddress: order.endAddress,
            endLatitude: order.endLatitude,
            endLongitude: order.endLongitude,
            plannedStart: meetupPlan?.plannedStartTime ?? order.plannedStart,
            plannedEnd: meetupPlan?.plannedEndTime ?? order.plannedEnd,
            blindName: order.blindName,
            blindPhone: order.blindPhone,
            volunteerPhone: volunteerPhone ?? order.volunteerPhone,
            acceptedAt: newStatus == .pendingAccept ? ISO8601DateFormatter().string(from: Date()) : order.acceptedAt,
            createdAt: order.createdAt,
            expectedDurationMinutes: order.expectedDurationMinutes,
            pacePreference: order.pacePreference,
            routePreference: order.routePreference,
            routeNotes: order.routeNotes,
            hasGuideDogThisRun: order.hasGuideDogThisRun,
            specialNotes: order.specialNotes,
            visionLevel: order.visionLevel,
            tetherPreference: order.tetherPreference,
            chatPreference: order.chatPreference,
            volunteerId: hasAcceptedVolunteer ? Self.mockOrderVolunteerId : nil,
            volunteerName: hasAcceptedVolunteer ? Self.mockOrderVolunteerName : nil,
            // 与 `volunteerName` 同一个下发窗口。后端**确实在发这个字段**
            // （`api_spec.yaml` 的 `OrderDetailResponse`），所以 Mock 给它一个值是在
            // 镜像现实 —— 不是 `updatedAt` 那种 Mock 自己造、后端从来没发过的字段
            // （记忆 `mock-fabricates-fields-the-backend-never-sends`，PR #48）。
            volunteerTotalCompleted: hasAcceptedVolunteer ? Self.mockOrderVolunteerCompletedRuns : nil,
            // 三项是订单列，状态往后走时要带着（约好页之后的每一页都可能显示）。
            // 换陪跑员时清掉陪跑员上衣颜色 —— 说的是走掉的那位；另两项描述地点和跑者，保留（后端同口径）。
            meetSpotNote: meetupPlan?.meetSpotNote ?? order.meetSpotNote,
            runnerTopColor: meetupPlan?.runnerTopColor ?? order.runnerTopColor,
            volunteerTopColor: newStatus == .rematching ? nil : (meetupPlan?.volunteerTopColor ?? order.volunteerTopColor),
            counterpartUserId: hasAcceptedVolunteer ? Self.mockOrderVolunteerId : nil
        )
    }

    /// Mock 的 remark 逐字抄后端那 12 处 `logStatusChange` 的第五个参数，
    /// 让「remark 就是可朗读的中文」这条前端假设在开发期真的被验到。
    /// `CANCELLED` 刻意保留后端那个机器串（`"取消方=" + CancelledBy`）——
    /// `OrderStatusLog.displayText` 的翻译分支只有靠它才走得到。
    private static func mockStatusLogRemark(to newStatus: RunOrderStatus) -> String {
        switch newStatus {
        case .pendingMatch: return "创建订单"
        case .pendingIntroCall: return "志愿者表示有意向，进入通话磨合"
        case .scheduledConfirmed: return "志愿者接单（远期预约，等临期确认）"
        case .pendingAccept: return "志愿者接单"
        case .driverEnRoute: return "志愿者已出发"
        case .driverArrived: return "志愿者已到达"
        case .inProgress: return "志愿者确认开始服务"
        case .completed: return "服务完成"
        case .cancelled: return "取消方=BLIND"
        case .rematching: return "志愿者取消，进入重新匹配，第1次"
        case .noVolunteer, .unknown: return ""
        }
    }

    func extractOrderId(from path: String) -> Int64? {
        let components = path.split(separator: "/")
        // path like /api/orders/123 or /api/orders/123/respond
        guard components.count >= 3, components[1] == "orders" else { return nil }
        return Int64(components[2])
    }

    func extractEmergencyContactId(from path: String) -> Int64? {
        let components = path.split(separator: "/")
        // path like /api/users/1/emergency-contacts/100
        guard components.count == 5,
              components[0] == "api",
              components[1] == "users",
              components[3] == "emergency-contacts" else {
            return nil
        }
        return Int64(components[4])
    }

    func extractSetPrimaryContactId(from path: String) -> Int64? {
        let components = path.split(separator: "/")
        // path like /api/users/1/emergency-contacts/100/set-primary
        guard components.count == 6,
              components[0] == "api",
              components[1] == "users",
              components[3] == "emergency-contacts",
              components[5] == "set-primary" else {
            return nil
        }
        return Int64(components[4])
    }
}
