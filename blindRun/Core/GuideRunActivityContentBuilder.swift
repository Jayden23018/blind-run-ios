import Foundation

// MARK: - 陪跑员实时活动：订单 / 通话 → 卡片内容（#920）
//
// 起停与上传 token 在 `GuideRunActivityController`；这里只放纯函数，好让用例逐条钉住。

/// 订单 → 卡片内容。**抽成纯函数只为可测**。
@available(iOS 16.2, *)
enum GuideRunActivityContentBuilder {
    /// 开跑前多久起第二段（DECISION 第 2 条）。
    static let preStartLeadTime: TimeInterval = 30 * 60
    /// 第一段 V3「已约好」推完之后锁屏留多久（稿第五节）。
    static let bookedLingerTime: TimeInterval = 15 * 60

    /// 出发 / 汇合两态（后端 `live-activity-token` 也只在这两态收 token）。
    static func showsCard(for status: RunOrderStatus) -> Bool {
        status == .driverEnRoute || status == .driverArrived
    }

    /// V4 的门槛：已约好（含临期确认 `PENDING_ACCEPT`）且离开跑不到 30 分钟（含已过开跑时刻还没出发）。
    static func isInPreStartWindow(status: RunOrderStatus, plannedStart: Date?, now: Date) -> Bool {
        guard status == .scheduledConfirmed || status == .pendingAccept, let plannedStart else { return false }
        return now >= plannedStart.addingTimeInterval(-preStartLeadTime)
    }

    /// 第二段这一刻该画什么；`nil` = 这份订单不该有第二段的卡。
    static func secondSegmentContent(from order: OrderDetailResponse, now: Date) -> GuideRunAttributes.ContentState? {
        if showsCard(for: order.status) { return contentState(from: order) }
        guard isInPreStartWindow(status: order.status, plannedStart: order.plannedStart?.backendTimestamp, now: now) else {
            return nil
        }
        return preStartState(from: order)
    }

    static func attributes(from order: OrderDetailResponse) -> GuideRunAttributes {
        GuideRunAttributes(
            orderID: order.orderId,
            // 卡上不写名字（DECISION 第 7 条），字段照旧只取 `blindSurname`、**不拿掩码名顶替**，
            // 以免以后有人重新把它画上卡时画出「李*」。
            runnerSurname: order.blindSurname?.nilIfBlank,
            meetingPointName: order.startAddress?.nilIfBlank ?? "",
            plannedStart: order.plannedStart?.backendTimestamp
        )
    }

    /// 第一段起卡时还没有订单详情（通话期 `GET /api/orders/{id}` 对陪跑员恒 403），
    /// 只有派单推送或 `IntroCallView` 里的地址与时间。
    static func attributes(orderID: Int64, startAddress: String?, plannedStart: String?) -> GuideRunAttributes {
        GuideRunAttributes(
            orderID: orderID,
            runnerSurname: nil,
            meetingPointName: startAddress?.nilIfBlank ?? "",
            plannedStart: plannedStart?.nilIfBlank?.backendTimestamp
        )
    }

    /// 与后端推送的 `content-state` 同口径（后端 `docs/live-activity.md`「ContentState」一节），
    /// 这样本地更新与推送更新交替到达时卡片不会来回跳。
    static func contentState(from order: OrderDetailResponse) -> GuideRunAttributes.ContentState {
        if order.status == .driverArrived {
            return GuideRunAttributes.ContentState(
                phase: .arrived,
                etaMinutes: nil,
                arriveAt: nil,
                progress: 0.85,
                runnerNearMeetingPoint: order.runnerAtMeetingPoint ?? false,
                distanceBucket: order.meet?.distanceBucket.rawValue
            )
        }
        let eta = order.eta
        return GuideRunAttributes.ContentState(
            phase: eta?.late == true ? .late : .departed,
            etaMinutes: eta?.remainingMinutes,
            arriveAt: eta?.arriveAt?.backendTimestamp,
            progress: eta?.progress ?? 0.1,
            // 三态字段：`nil`（跑者位置未知）按 `false`，与后端推送同一条口径。
            runnerNearMeetingPoint: order.runnerAtMeetingPoint ?? false,
            distanceBucket: nil
        )
    }

    /// V4。`suggestedDepartAt` / `travelMinutes` 只在陪跑员有位置记录时下发，缺了卡上退到「7:00 开跑」。
    static func preStartState(from order: OrderDetailResponse) -> GuideRunAttributes.ContentState {
        GuideRunAttributes.ContentState(
            phase: .preStart,
            etaMinutes: nil,
            arriveAt: nil,
            progress: 0.1,
            runnerNearMeetingPoint: false,
            distanceBucket: nil,
            leaveBy: order.suggestedDepartAt?.nilIfBlank?.backendTimestamp,
            travelMinutes: order.travelMinutes
        )
    }

    /// V1 / V2。子状态的判据与通话页同一个（`VolunteerIntroCallViewModel.step`）。
    static func introCallState(step: IntroCallVolunteerStep, windowEndsAt: Date?) -> GuideRunAttributes.ContentState {
        GuideRunAttributes.ContentState(
            phase: step == .awaitingCall ? .introCall : .planSubmitted,
            etaMinutes: nil,
            arriveAt: nil,
            progress: 0.1,
            runnerNearMeetingPoint: false,
            distanceBucket: nil,
            deadline: step == .awaitingCall ? windowEndsAt : nil
        )
    }

    /// V3。
    static let bookedState = GuideRunAttributes.ContentState(
        phase: .scheduled, etaMinutes: nil, arriveAt: nil, progress: 0.1,
        runnerNearMeetingPoint: false, distanceBucket: nil
    )

    /// 到点后卡片该换样子的那一刻：V1 商量截止、V4 建议出发时刻。widget 读 `context.isStale`。
    static func staleDate(for content: GuideRunAttributes.ContentState) -> Date? {
        switch content.phase {
        case .introCall: return content.deadline
        case .preStart: return content.leaveBy
        default: return nil
        }
    }

    /// 第一段的卡该不该收：只看 V1 / V2（V3 是已结束、正在锁屏停留的卡，不归这里）。
    static func firstSegmentIsOver(
        cardOrderID: Int64, cardPhase: GuideRunAttributes.Phase?, activeIntroCallOrderID: Int64?
    ) -> Bool {
        guard cardPhase == .introCall || cardPhase == .planSubmitted else { return false }
        return cardOrderID != activeIntroCallOrderID
    }

    /// APNs 的 token 是 `Data`，后端要十六进制串（`^[0-9a-fA-F]{32,512}$`）。
    static func hexString(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }
}
