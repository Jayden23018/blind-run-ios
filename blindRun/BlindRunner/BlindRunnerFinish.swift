import Foundation

// 跑步中跑者自己的出路（#660 B-4 / F-10、F-20，#682）。
//
// 契约（`POST /api/orders/{id}/finish`，后端 #346）：盲人也能结束，但只在陪跑员超过
// `blind-finish-volunteer-offline-minutes`（默认 5 分钟）没上报位置时放行；陪跑员还在线时回 409
// `VOLUNTEER_STILL_ONLINE`，message 带最早可结束的时刻、可直接朗读。**判据在后端，客户端不判。**

enum BlindRunnerFinishCopy {
    static let endRunTitle = "陪跑员联系不上，结束本次陪跑"
    static let endRunHint = "陪跑员掉线超过 5 分钟后才能由你结束。按下后会再确认一次。"

    static let confirmTitle = "结束本次陪跑？"
    /// 说清两件事：先打电话；后端会判陪跑员是不是真的掉线了，不是按下就一定结束。
    static let confirmMessage = "请先打电话联系陪跑员。确认后，如果陪跑员已经掉线超过 5 分钟，本次陪跑会结束；还在线的话，会告诉你什么时候可以结束。"
    static let confirmButtonTitle = "结束陪跑"
    static let cancelButtonTitle = "先不结束"

    /// 按下后、请求回来之前那一句。网络慢时让人知道按到了（同 `BlindRunCopy.startingAnnouncement`）。
    static let finishingAnnouncement = "正在结束本次陪跑。"

    /// 409 `VOLUNTEER_STILL_ONLINE` 而后端 message 为空时的兜底。正常应念后端那句（带时刻）。
    static let stillOnlineFallback = "陪跑员的手机还在线，现在还不能由你结束。请先打电话联系陪跑员。"
    /// `ORDER_HAS_ACTIVE_EMERGENCY` 的跑者口径。通用文案是写给陪跑员的（「需要跑者本人撤销」）。
    static let activeEmergency = "这一单还有没结束的求助，现在还不能结束。如果求助是误触，可以先撤销求助；否则请等客服处理完。"
    static let failedFallback = "结束失败，请稍后再试。"
    /// 弹层打开期间订单已经不在跑步中（例如陪跑员刚好结束了）。
    static let notRunning = "本次陪跑已经不在进行中，不用再结束。"

    /// 跑者自己结束时的完成句。**不说「某某结束了本次陪跑」**：那句会让人以为陪跑员又联系上了。
    static func runnerFinishedAnnouncement(distanceText: String?) -> String {
        let head = "你已结束本次陪跑"
        guard let distanceText else { return head + "。" }
        return head + "，共跑 \(distanceText)。"
    }

    // MARK: F-20

    static let volunteerUnwellTitle = "陪跑员身体不适或倒地怎么办"
    /// 顺序是审计 F-20 定的：先叫急救，再把位置说给 120，然后让家人知道。三步对应求助中心里已有的三格。
    static let volunteerUnwellSteps = "第一，拨打120。第二，用「播报我的位置」，把位置告诉接线员。第三，联系你的紧急联系人。"

    // MARK: ORDER_OVERDUE

    /// 盲人端 `ORDER_OVERDUE` 的替代正文。后端模板说「请让志愿者点击结束服务」，
    /// 陪跑员联系不上时这句话没有出路，而跑者自己其实能结束。陪跑员端照念后端原文。
    static let overdueForRunner = "本次陪跑已超过约定结束时间。如果一切正常，请让陪跑员结束本次陪跑。"
        + "如果联系不上陪跑员，可以在求助与安全里自己结束；遇到危险请按求助。"

    /// 给 `AppRealtimeCoordinator.overriddenBody` 用。`nil` = 照播后端原文。
    static func overdueOverride(eventType: String, role: WSRole?) -> String? {
        eventType == "ORDER_OVERDUE" && role == .blind ? overdueForRunner : nil
    }

    // MARK: #682

    /// 开跑那一刻念一次。按法只写苹果支持文档写明的那种（同 `BlindFirstRunHelp` 的 `systemSOS`），
    /// 🔴 并说清这是系统功能、App 不会代你求助（`AGENTS.md` §6）。
    static let systemSOSReminder = "提醒一句：跑步中不方便操作屏幕时，可以同时按住侧边按钮和任意一个音量按钮，"
        + "用 iPhone 自带的紧急 SOS 拨打急救电话。这是系统功能，App 不会代你发送求助。"
}

/// 「这一单是跑者自己结束的」。只存内存：它只决定完成那一句怎么说。
///
/// **在发请求之前记**，失败再撤销：状态推送可能先于 HTTP 响应到达，
/// 那条路径上的完成句也要说成「你已结束」。
enum BlindRunnerFinishRecord {
    private(set) static var finishedByRunner: Set<Int64> = []

    static func mark(_ orderID: Int64) { finishedByRunner.insert(orderID) }
    static func unmark(_ orderID: Int64) { finishedByRunner.remove(orderID) }
}

extension BlindOrderStatusViewModel {
    /// 求助中心「陪跑员联系不上，结束本次陪跑」确认之后。
    /// 返回 `nil` = 已结束（或登录已过期、交给全局处理）；返回一句话 = 没结束成，求助中心把它留在按钮下面。
    @discardableResult
    func finishBecauseVolunteerUnreachable() async -> String? {
        guard let order, let appState, !isPerformingAction else { return BlindRunnerFinishCopy.failedFallback }
        guard order.status == .inProgress else { return BlindRunnerFinishCopy.notRunning }
        isPerformingAction = true
        errorMessage = nil
        speechService?.speak(BlindRunnerFinishCopy.finishingAnnouncement)
        BlindRunnerFinishRecord.mark(order.orderId)
        do {
            try await appState.orders.finish(orderId: order.orderId)
            isPerformingAction = false
            await loadOrder(orderId: order.orderId, speakChanges: true)
            return nil
        } catch {
            // 只有后端明确拒绝时才撤销记录。网络断在半路时请求可能已经生效，
            // 撤销的话下一轮轮询看到已完成，会说成「陪跑员结束了本次陪跑」—— 像是他又联系上了。
            if case APIError.serverError = error { BlindRunnerFinishRecord.unmark(order.orderId) }
            isPerformingAction = false
            if let apiError = error as? APIError, appState.handleAuthenticatedAPIError(apiError) { return nil }
            let message = Self.runnerFinishFailureMessage(for: error)
            speechService?.speakError(message)
            errorMessage = message
            return message
        }
    }

    /// 结束失败念哪一句。`VOLUNTEER_STILL_ONLINE` 不在 `ErrorCode` 里（未知码本来就念后端 message），
    /// 只为 message 为空的情况按原串兜底。
    static func runnerFinishFailureMessage(for error: Error) -> String {
        guard let apiError = error as? APIError else { return BlindRunnerFinishCopy.failedFallback }
        if case .serverError(let response) = apiError, response.code == "VOLUNTEER_STILL_ONLINE" {
            return response.message.nilIfBlank ?? BlindRunnerFinishCopy.stillOnlineFallback
        }
        if apiError.errorCode == .orderHasActiveEmergency { return BlindRunnerFinishCopy.activeEmergency }
        return apiError.localizedMessage.nilIfBlank ?? BlindRunnerFinishCopy.failedFallback
    }

    /// 完成那一句。跑者自己结束的单换成「你已结束」，其余照旧。
    static func completionText(
        _ kind: CompletionAnnouncement,
        order: OrderDetailResponse,
        stats: TrackStats?
    ) -> String {
        guard kind == .justFinished, BlindRunnerFinishRecord.finishedByRunner.contains(order.orderId) else {
            return completionAnnouncementText(kind, order: order, stats: stats)
        }
        return BlindRunnerFinishCopy.runnerFinishedAnnouncement(distanceText: stats?.distanceText)
    }
}
