//
//  MockAPIClient+IntroCall.swift
//  blindRun
//
//  从 MockAPIClient.swift 原样搬出的 接单前通话磨合与订单流转 分段。行为零改动，只改文件位置。
//

import Foundation

extension MockAPIClient {

    // MARK: - 接单前通话磨合

    /// `GET /api/orders/{id}/intro-call`。
    ///
    /// 🚨 **按角色返回不同内容**，这正是这个端点最容易被实现错的地方，所以 Mock 也照演：
    /// 盲人拿明文号 + 掩码为 null，志愿者拿掩码 + 明文为 null。
    /// 两边都给全的 Mock 会让「掩码串不能拼 tel:」这条约束在开发期彻底隐形。
    func handleGetIntroCall(orderId: Int64) throws -> IntroCallView {
        guard let order = orders.first(where: { $0.orderId == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        guard order.status == .pendingIntroCall else {
            throw APIError.serverError(ErrorResponse(
                code: "INTRO_CALL_NOT_ACTIVE", message: "这一轮通话已经结束了"))
        }
        let isBlind = mockRole == .blind
        return IntroCallView(
            counterpartName: isBlind ? "李*" : "王*",
            counterpartPhone: isBlind ? "13800000002" : nil,
            counterpartPhoneMasked: isBlind ? nil : "138****0001",
            myDecision: introCallDecisions[orderId]?[mockRole ?? .unset]?.rawValue,
            windowEndsAt: ISO8601DateFormatter.aidRunFormatter.string(
                from: Date().addingTimeInterval(20 * 60)
            ),
            // 这三项**双方角色都给**（契约：它们是「这一单的信息」不是「对方的信息」），
            // 且必须从真实订单取而不是写死 —— 冷启动恢复出来的通话页正是靠它们才不是一片空白，
            // 写死会让「恢复出来的页面显示的是不是这一单」在开发期永远验不出来。
            startAddress: order.startAddress,
            plannedStartTime: order.plannedStart,
            plannedEndTime: order.plannedEnd
        )
    }

    /// `POST /api/orders/{id}/intro-call/decision`。
    ///
    /// 演的是后端 `IntroCallService.submitDecision` 的三条出路：任一方 `DECLINE` 立即结束本轮
    /// 并退回 `PENDING_MATCH`（**不是 `REMATCHING`** —— 通话没成时从来没有志愿者接过单）；
    /// 双方都 `ACCEPT` 才转 `PENDING_ACCEPT`；只有一方表态就存下来等另一方，
    /// **且不告诉对方**（无声）。
    func handleIntroCallDecision(orderId: Int64, body: (any Encodable & Sendable)?) throws -> ApiSuccessResponse {
        guard let index = orders.firstIndex(where: { $0.orderId == orderId }),
              orders[index].status == .pendingIntroCall else {
            throw APIError.serverError(ErrorResponse(
                code: "INTRO_CALL_NOT_ACTIVE", message: "这一轮通话已经结束了"))
        }
        guard let data = try? JSONEncoder().encode(MockAnyEncodable(body)),
              let request = try? JSONDecoder().decode(IntroCallDecisionRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "请求格式错误"))
        }
        let role = mockRole ?? .unset
        var decisions = introCallDecisions[orderId] ?? [:]
        decisions[role] = request.decision
        introCallDecisions[orderId] = decisions

        if request.decision == .decline {
            orders[index] = updateOrderStatus(orders[index], to: .pendingMatch)
            introCallDecisions[orderId] = nil
        } else if decisions[.blind] == .accept, decisions[.volunteer] == .accept {
            orders[index] = updateOrderStatus(
                orders[index],
                to: .pendingAccept,
                volunteerPhone: "13800000002"
            )
            introCallDecisions[orderId] = nil
        }
        return ApiSuccessResponse(success: true, message: nil)
    }

    /// `POST /api/orders/{id}/intro-call/unreachable`（仅志愿者）。
    /// 与 `DECLINE` 的区别在后端的统计口径，订单侧的结果相同：退回派单队列。
    func handleIntroCallUnreachable(orderId: Int64) throws -> ApiSuccessResponse {
        guard let index = orders.firstIndex(where: { $0.orderId == orderId }),
              orders[index].status == .pendingIntroCall else {
            throw APIError.serverError(ErrorResponse(
                code: "INTRO_CALL_NOT_ACTIVE", message: "这一轮通话已经结束了"))
        }
        orders[index] = updateOrderStatus(orders[index], to: .pendingMatch)
        introCallDecisions[orderId] = nil
        return ApiSuccessResponse(success: true, message: nil)
    }

    /// `POST /api/orders/{id}/intro-call/notify-incoming`（仅盲人）。真实后端只推一条通知，
    /// 不改订单，所以这里也只回成功 —— 客户端本来就 fire-and-forget，不等这个响应。
    func handleIntroCallNotifyIncoming(orderId: Int64) throws -> ApiSuccessResponse {
        guard let order = orders.first(where: { $0.orderId == orderId }),
              order.status == .pendingIntroCall else {
            throw APIError.serverError(ErrorResponse(
                code: "INTRO_CALL_NOT_ACTIVE", message: "这一轮通话已经结束了"))
        }
        return ApiSuccessResponse(success: true, message: nil)
    }

    func handleAcceptOrder(orderId: Int64) throws -> OrderResponse {
        guard let index = orders.firstIndex(where: { $0.orderId == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        guard orders[index].status == .pendingMatch else {
            throw APIError.serverError(ErrorResponse(
                code: "ORDER_ALREADY_ACCEPTED", message: "订单已被其他志愿者接单"))
        }
        orders[index] = updateOrderStatus(orders[index], to: .pendingAccept, volunteerPhone: "13800000002")
        return actionResponse(for: orders[index], message: "接单成功")
    }

    func handleDeclineOrder(orderId: Int64) throws -> OrderResponse {
        guard let order = orders.first(where: { $0.orderId == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        return actionResponse(for: order, message: "已拒绝本次派单")
    }

    func handleEnRoute(orderId: Int64) throws -> OrderResponse {
        guard let index = orders.firstIndex(where: { $0.orderId == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        guard orders[index].status == .pendingAccept else {
            throw APIError.serverError(ErrorResponse(
                code: "ORDER_STATUS_NOT_ALLOWED", message: "当前订单状态不允许该操作"))
        }
        orders[index] = updateOrderStatus(orders[index], to: .driverEnRoute)
        return actionResponse(for: orders[index], message: "已出发")
    }

    func handleArrived(orderId: Int64) throws -> OrderResponse {
        guard let index = orders.firstIndex(where: { $0.orderId == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        guard orders[index].status == .driverEnRoute else {
            throw APIError.serverError(ErrorResponse(
                code: "ORDER_STATUS_NOT_ALLOWED", message: "当前订单状态不允许该操作"))
        }
        orders[index] = updateOrderStatus(orders[index], to: .driverArrived)
        return actionResponse(for: orders[index], message: "已到达")
    }

    func handleFinish(orderId: Int64) throws -> OrderResponse {
        guard let index = orders.firstIndex(where: { $0.orderId == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        guard orders[index].status.canFinishService else {
            throw APIError.serverError(ErrorResponse(
                code: "ORDER_STATUS_NOT_ALLOWED", message: "当前订单状态不允许该操作"))
        }
        orders[index] = updateOrderStatus(orders[index], to: .completed)
        return actionResponse(for: orders[index], message: "服务已完成")
    }

    func handleStartService(orderId: Int64) throws -> OrderResponse {
        guard let index = orders.firstIndex(where: { $0.orderId == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        guard orders[index].status == .driverArrived else {
            throw APIError.serverError(ErrorResponse(
                code: "ORDER_STATUS_NOT_ALLOWED", message: "当前订单状态不允许该操作"))
        }
        orders[index] = updateOrderStatus(orders[index], to: .inProgress)
        return actionResponse(for: orders[index], message: "服务已开始")
    }

    func handleCancel(orderId: Int64) throws -> OrderResponse {
        guard let index = orders.firstIndex(where: { $0.orderId == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        guard let role = mockRole, orders[index].status.canCancel(as: role) else {
            throw APIError.serverError(ErrorResponse(
                code: "ORDER_STATUS_NOT_ALLOWED", message: "当前订单状态不允许取消"))
        }
        let nextStatus: RunOrderStatus = role == .volunteer ? .rematching : .cancelled
        orders[index] = updateOrderStatus(orders[index], to: nextStatus)
        let message = role == .volunteer ? "志愿者已取消，订单重新匹配中" : "订单已取消"
        return actionResponse(for: orders[index], message: message)
    }

    /// `PUT /api/orders/{id}/keep-waiting` 与 `/keep-rematching`。
    ///
    /// 两条端点前置状态互斥，所以调用方传进来要求的那一个 —— Mock 不去猜订单当前是什么，
    /// 猜的话就把「客户端打错了端点」这类 bug 遮掉了。
    ///
    /// 成功只回 `{"success": true}`，**订单状态不变**，这是契约保证的全部形状
    /// （`api_spec.yaml:277-283`）。不要在这里编一个带剩余次数或新超时时刻的回执 ——
    /// 那样客户端会长出依赖后端并不提供的字段的代码。
    func handleKeepWaiting(
        orderId: Int64,
        requiredStatus: RunOrderStatus
    ) throws -> ApiSuccessResponse {
        guard let index = orders.firstIndex(where: { $0.orderId == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        guard orders[index].status == requiredStatus else {
            throw APIError.serverError(ErrorResponse(
                code: "ORDER_STATUS_NOT_ALLOWED", message: "当前订单状态不支持此操作"))
        }
        let used = keepWaitingCounts[orderId] ?? 0
        guard used < Self.mockKeepWaitingLimit else {
            throw APIError.serverError(ErrorResponse(
                code: "KEEP_WAITING_LIMIT_REACHED", message: "继续等待次数已达上限，请取消订单后重新下单"))
        }
        keepWaitingCounts[orderId] = used + 1
        return ApiSuccessResponse(success: true, message: nil)
    }

    func actionResponse(for order: OrderDetailResponse, message: String) -> OrderResponse {
        OrderResponse(id: order.orderId, status: order.status, message: message, success: true)
    }

    /// `POST /api/orders/{id}/review`。
    ///
    /// 此前无条件回成功、也不留存 —— 于是 `REVIEW_ALREADY_SUBMITTED` 那条分支在开发期
    /// 一次都走不到，而它恰恰是「重进已完成订单再点提交」的必经之路。
    /// 两条前置校验对齐后端 `ReviewService:57`（非 COMPLETED）与 `:62`（重复提交）。
    func handleReview(orderId: Int64, body: (any Encodable & Sendable)?) throws -> ApiSuccessResponse {
        guard let order = orders.first(where: { $0.orderId == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        guard order.status == .completed else {
            throw APIError.serverError(ErrorResponse(
                code: "ORDER_STATUS_NOT_ALLOWED", message: "订单未完成，暂不能评价"))
        }
        guard orderReviews[orderId] == nil else {
            throw APIError.serverError(ErrorResponse(
                code: "REVIEW_ALREADY_SUBMITTED", message: "已评价过此订单"))
        }
        guard let data = try? JSONEncoder().encode(MockAnyEncodable(body)),
              let request = try? JSONDecoder().decode(CreateReviewRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "请求格式错误"))
        }
        orderReviews[orderId] = OrderReview(
            orderId: orderId,
            rating: request.rating,
            comment: request.comment,
            createdAt: Self.backendLocalTimestamp()
        )
        return ApiSuccessResponse(success: true, message: nil)
    }

    /// `GET /api/orders/{id}/reviews`。尚未评价时 `data` 为 null，**不是 404**。
    func handleGetReview(orderId: Int64) throws -> OrderReviewEnvelope {
        guard orders.contains(where: { $0.orderId == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        return OrderReviewEnvelope(data: orderReviews[orderId])
    }

    /// `GET /api/orders/{id}/status-logs`。裸数组，最新在前。
    /// 订单不存在时后端抛 `IllegalArgumentException` → **400 `BAD_REQUEST`，不是 404**
    /// （`OrderController.java:261-262`）。
    func handleGetStatusLogs(orderId: Int64) throws -> [OrderStatusLog] {
        guard orders.contains(where: { $0.orderId == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "BAD_REQUEST", message: "订单不存在"))
        }
        return orderStatusLogs[orderId] ?? []
    }

    /// 开分享链接。**幂等**：同一单重复调返回同一条链接，与后端一致
    /// （换令牌会让已经发出去的那条失效，家属只看到「分享已结束」，分不清是跑完了还是链接被换了）。
    func handleCreateShareLink(orderId: Int64) throws -> ShareLinkResponse {
        guard let order = orders.first(where: { $0.orderId == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        guard order.status.offersRunPlanShare else {
            throw APIError.serverError(ErrorResponse(
                code: "SHARE_ORDER_ALREADY_FINISHED",
                message: "订单已结束，不能再新开分享链接"
            ))
        }
        if let existing = shareLinks[orderId] {
            return existing
        }
        // 令牌放 **fragment**，与契约同形。Mock 里也照做的理由：这一条正是「客户端不许重新拼链接」
        // 那条约束的载体，Mock 里写成 `?t=` 会让测试在一个错误形状上过绿。
        //
        // 域名用 RFC 2606 保留的 `example.com`：真实分享域名由后端下发，
        // 客户端一个字都不该知道。`guard.mjs` 的 `server-addr` 白名单也只放行这一族。
        let token = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(43))
        let link = ShareLinkResponse(
            shareUrl: "https://example.com/share.html#\(token)",
            expiresAt: Self.backendLocalTimestamp()
        )
        shareLinks[orderId] = link
        return link
    }

    /// 停分享。**幂等**：没有可撤销的链接时同样成功（后端返 204）。
    func handleRevokeShareLink(orderId: Int64) throws -> EmptyResponse {
        guard orders.contains(where: { $0.orderId == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        shareLinks.removeValue(forKey: orderId)
        return EmptyResponse()
    }

    /// 记一条状态变更。后端在每个状态流转点都写一条（12 处 `logStatusChange`），
    /// Mock 把它收在 `updateOrderStatus` 一处 —— 那是所有状态改动的唯一出口，
    /// 逐个调用点补记漏一处就是审计链断裂。
    func appendStatusLog(
        orderId: Int64,
        from: RunOrderStatus?,
        to: RunOrderStatus,
        remark: String
    ) {
        let log = OrderStatusLog(
            id: nextStatusLogId,
            fromStatus: from,
            toStatus: to,
            changedAt: Self.backendLocalTimestamp(),
            remark: remark
        )
        nextStatusLogId += 1
        orderStatusLogs[orderId, default: []].insert(log, at: 0)
    }

    /// 后端 `LocalDateTime` 的无时区串（`2026-08-04T09:05:03`），与 `String.backendLocalDate` 对得上。
    private static func backendLocalTimestamp() -> String {
        DateFormatter.aidRunBackendLocalDateTime.string(from: Date())
    }
}
