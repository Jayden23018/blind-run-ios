//
//  MockAPIClient+Order.swift
//  blindRun
//
//  从 MockAPIClient.swift 原样搬出的 订单 分段。行为零改动，只改文件位置。
//

import Foundation

extension MockAPIClient {

    // MARK: - Order Handlers

    func handleCreateOrder(body: (any Encodable & Sendable)?) throws -> OrderResponse {
        guard let data = try? JSONEncoder().encode(MockAnyEncodable(body)),
              let request = try? JSONDecoder().decode(CreateOrderRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "请求格式错误"))
        }

        // 校验顺序与后端 `OrderCreationService.createOrder` 严格一致：
        // 提前量（422 APPOINTMENT_TOO_SOON）→ 紧急联系人（403 EMERGENCY_CONTACT_REQUIRED）。
        // 2026-11-05 起后端不再校验实名（blind-run-backend#924），Mock 跟着去掉。
        // 顺序错了会让 Mock 引导用户先补一个后端根本不会先拒的项。
        // 注意：后端**不校验** `BlindProfile.name`，Mock 也不能比后端严；
        // 之前那条 `PROFILE_INCOMPLETE` 是真实后端永不返回的死码，已删除。
        //
        // ⚠️ 后端 N134 在提前量之后还加了两道，Mock **刻意不镜像**（2026-09-05）：
        // `APPOINTMENT_TOO_LONG`（>300 分钟）和 `APPOINTMENT_IN_NIGHT_WINDOW`
        // （整段落进 `[22:00, 05:00)`）。前者客户端到不了 —— 表单选择器最大 120 分钟、
        // 语音被 `VoiceOrderWizard.acceptedDurationMinutes` 夹在 10–300，Mock 加了也是死分支。
        // 后者会把整个测试套件变成看墙钟的：本仓多条用例按 `Date() + 45 分钟` 下单
        // （`blindRunTests.swift:1220`、`OrderReviewAndStatusLogDecodingTests.swift:152`），镜像之后它们白天全绿、
        // 晚上 8 点后集体变红 —— 提交时验不出来的红是最贵的那种。
        // 两个码的**客户端映射与 TTS 文案照常有**（`ErrorCode.appointmentTooLong` /
        // `.appointmentInNightWindow`），真实后端拒绝时盲人听到的是能照着改的那句话。

        // Validate appointment time (30 min ahead)
        if let date = ISO8601DateFormatter().date(from: request.plannedStartTime)
            ?? request.plannedStartTime.backendLocalDate {
            let leadTime = date.timeIntervalSince(Date())
            if leadTime < Double(AppConstants.Timing.minimumBookingLeadMinutes) * 60 {
                throw APIError.serverError(ErrorResponse(
                    code: "APPOINTMENT_TOO_SOON", message: "预约时间至少需要在 30 分钟后"))
            }
        }

        guard !emergencyContacts.isEmpty else {
            throw APIError.serverError(ErrorResponse(
                code: "EMERGENCY_CONTACT_REQUIRED", message: "请先设置紧急联系人再下单"))
        }

        let orderId = nextOrderId
        nextOrderId += 1

        let order = OrderDetailResponse(
            orderId: orderId,
            status: .pendingMatch,
            startAddress: request.startAddress,
            startLatitude: request.startLatitude,
            startLongitude: request.startLongitude,
            endAddress: request.endAddress,
            endLatitude: request.endLatitude,
            endLongitude: request.endLongitude,
            plannedStart: request.plannedStartTime,
            plannedEnd: request.plannedEndTime,
            blindName: blindProfile?.name,
            blindPhone: nil,
            volunteerPhone: nil,
            acceptedAt: nil,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            expectedDurationMinutes: request.expectedDurationMinutes,
            pacePreference: request.pacePreference,
            routePreference: request.routePreference,
            routeNotes: request.routeNotes,
            hasGuideDogThisRun: request.hasGuideDogThisRun,
            specialNotes: request.specialNotes,
            visionLevel: blindProfile?.visionLevel,
            tetherPreference: blindProfile?.tetherPreference,
            chatPreference: blindProfile?.chatPreference
        )
        orders.append(order)
        // 后端在 `OrderCreationService:125` 写的第一条日志，`fromStatus` 为 null。
        appendStatusLog(orderId: orderId, from: nil, to: .pendingMatch, remark: "创建订单")

        return OrderResponse(id: orderId, status: .pendingMatch, message: "订单已创建", success: true)
    }

    func handleGetMyOrders(query: [String: String]?) -> PagedOrderResponse {
        var filtered = orders
        if let status = query?["status"], let s = RunOrderStatus(rawValue: status) {
            filtered = filtered.filter { $0.status == s }
        }
        return PagedOrderResponse(
            content: filtered.sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") },
            totalElements: Int64(filtered.count),
            totalPages: 1,
            number: 0,
            size: 100,
            first: true,
            last: true,
            empty: filtered.isEmpty
        )
    }

    /// `GET /api/orders/active` —— 盲人端冷启动 / 断线重连恢复。
    ///
    /// ⚠️ **判据是后端的，不是客户端的**：`status ∉ {COMPLETED, CANCELLED, NO_VOLUNTEER}`，
    /// 同时存在多条时取 `createdAt` 最近的一条（契约 `/api/orders/active` 的 description 逐字）。
    /// 别"顺手"换成客户端的 `isActiveForBlindRunner` —— 那条对 `.unknown` 判 true 是为了
    /// 不让订单从界面上消失，与这里问的「后端认不认为这一单还没走完」不是同一个问题。
    ///
    /// 没有活跃订单时 `data` 为 `null`（不是 404、不是空对象）。
    func handleGetActiveOrder() -> ActiveOrderEnvelope {
        let active = orders
            // 理由就是上面那段注释：这里演的是**后端**的判断，换成客户端判定
            // 会让「两边口径不一致」这件事再也看不见。 guard:allow status-set-literal
            .filter { ![.completed, .cancelled, .noVolunteer].contains($0.status) }
            .sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
            .first
        return ActiveOrderEnvelope(success: true, data: active)
    }

    func handleGetOrder(orderId: Int64) throws -> OrderDetailResponse {
        guard let order = orders.first(where: { $0.orderId == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        return order
    }

    func handleRespondOrder(orderId: Int64, body: (any Encodable & Sendable)?) throws -> OrderResponse {
        guard let data = try? JSONEncoder().encode(MockAnyEncodable(body)),
              let request = try? JSONDecoder().decode(OrderRespondRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "请求格式错误"))
        }
        switch request.action {
        case .accept:
            return try handleAcceptOrder(orderId: orderId)
        case .decline:
            return try handleDeclineOrder(orderId: orderId)
        case .interested:
            return try handleInterestedOrder(orderId: orderId)
        }
    }

    /// `action=INTERESTED` —— 订单转 `PENDING_INTRO_CALL` 并锁给这位志愿者。
    ///
    /// ⚠️ **刻意不写 `volunteerPhone`**：后端这一态 `order.volunteer` 恒为 null，号码只从
    /// 通话专用接口按角色单向下发。Mock 里图省事填上，开发期就永远看不到「志愿者拿不到明文号」
    /// 这条真实约束 —— 而那正是本仓库 2026-08-11 那个「掩码串被拨成空号」缺陷的土壤。
    private func handleInterestedOrder(orderId: Int64) throws -> OrderResponse {
        guard let index = orders.firstIndex(where: { $0.orderId == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        guard orders[index].status == .pendingMatch || orders[index].status == .rematching else {
            throw APIError.serverError(ErrorResponse(
                code: "ORDER_ALREADY_ACCEPTED", message: "订单已被他人接单或状态不允许"))
        }
        orders[index] = updateOrderStatus(orders[index], to: .pendingIntroCall)
        introCallDecisions[orderId] = [:]
        return actionResponse(for: orders[index], message: "已表示有意向")
    }

    // MARK: 陪跑员订单页 v2（后端 2026-09-26）
    //
    // 只做状态守卫，不做限流（429）—— 限流是后端 Redis 的事，Mock 模拟它只会让 Preview 与单测多一个
    // 看不见的变量。客户端对 429 的处理由 `FakeOrderService` 在单测里直接注入。

    func handleQuickMessage(orderId: Int64) throws -> OrderNudgeResponse {
        guard let order = orders.first(where: { $0.orderId == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        guard order.status == .driverEnRoute || order.status == .driverArrived else {
            throw APIError.serverError(ErrorResponse(
                code: "ORDER_STATUS_NOT_ALLOWED", message: "当前订单状态不允许该操作"))
        }
        return OrderNudgeResponse(success: true, orderId: orderId, ringingUntil: nil, delivered: true)
    }

    func handleRingRunner(orderId: Int64) throws -> OrderNudgeResponse {
        guard let order = orders.first(where: { $0.orderId == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        guard order.status == .driverArrived else {
            throw APIError.serverError(ErrorResponse(
                code: "ORDER_STATUS_NOT_ALLOWED", message: "当前订单状态不允许该操作"))
        }
        // 后端：受理时刻 + 10 秒，无时区本地时间串。
        let until = DateFormatter.aidRunBackendLocalDateTime.string(from: Date().addingTimeInterval(10))
        return OrderNudgeResponse(success: true, orderId: orderId, ringingUntil: until, delivered: true)
    }

    func handleEndWaiting(orderId: Int64) throws -> EmptyResponse {
        guard let index = orders.firstIndex(where: { $0.orderId == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        guard orders[index].status == .driverArrived else {
            throw APIError.serverError(ErrorResponse(
                code: "ORDER_STATUS_NOT_ALLOWED", message: "当前订单状态不允许该操作"))
        }
        if let earliest = orders[index].earliestEndWaitAt?.backendTimestamp, earliest > Date() {
            throw APIError.serverError(ErrorResponse(
                code: "END_WAIT_TOO_EARLY", message: "还没等满 15 分钟，暂时不能结束等待"))
        }
        orders[index] = updateOrderStatus(orders[index], to: .cancelled)
        return EmptyResponse()
    }

    func handleSetRunPaused(orderId: Int64, paused: Bool) throws -> EmptyResponse {
        let index = try inProgressOrderIndex(orderId)
        var run = orders[index].run ?? RunView()
        run.paused = paused
        orders[index].run = run
        return EmptyResponse()
    }

    private func inProgressOrderIndex(_ orderId: Int64) throws -> Int {
        guard let index = orders.firstIndex(where: { $0.orderId == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        guard orders[index].status == .inProgress else {
            throw APIError.serverError(ErrorResponse(
                code: "ORDER_STATUS_NOT_ALLOWED", message: "当前订单状态不允许该操作"))
        }
        return index
    }

    func handleRunnerMessage(orderId: Int64, body: (any Encodable & Sendable)?) throws -> RunnerMessageResponse {
        guard let data = try? JSONEncoder().encode(MockAnyEncodable(body)),
              let request = try? JSONDecoder().decode(RunnerMessageRequest.self, from: data),
              request.text.utf16.count <= RunnerMessageRequest.maxLength else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "留言最多 40 个字"))
        }
        guard let index = orders.firstIndex(where: { $0.orderId == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        guard orders[index].status.acceptsRunnerMessage else {
            throw APIError.serverError(ErrorResponse(
                code: "ORDER_STATUS_NOT_ALLOWED", message: "当前订单状态不允许该操作"))
        }
        orders[index].messageToVolunteer = request.text.nilIfBlank
        return RunnerMessageResponse(messageToVolunteer: orders[index].messageToVolunteer)
    }

    // MARK: - 订单状态流转（#895 从 +IntroCall 原样搬来）

    /// 接单时距开跑超过这个分钟数就落 `SCHEDULED_CONFIRMED`（跨天预约，后端迁移 `0041`）。
    ///
    /// 镜像后端 `app.order.scheduled-ahead-threshold-minutes`（默认 240）。
    /// **只有 Mock 需要这个数** —— 生产代码一个字都不该算它，状态由后端下发。
    /// 镜像它的唯一理由是：不镜像，跨天预约那一整屏（确认出发入口）在开发期永远走不到，
    /// 只能靠真实后端 + 两个账号 + 一张四小时后的单才看得见。
    private static let mockScheduledAheadThresholdMinutes: TimeInterval = 240

    func handleAcceptOrder(orderId: Int64) throws -> OrderResponse {
        guard let index = orders.firstIndex(where: { $0.orderId == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        guard orders[index].status == .pendingMatch else {
            throw APIError.serverError(ErrorResponse(
                code: "ORDER_ALREADY_ACCEPTED", message: "订单已被其他志愿者接单"))
        }
        // 远期单落 `SCHEDULED_CONFIRMED`，即时单照旧 `PENDING_ACCEPT`。
        // 两条路都下发 `volunteerPhone`：后端 `allowsCounterpartCall()` 对这两态都判 true。
        let target: RunOrderStatus = Self.isFarFuture(orders[index]) ? .scheduledConfirmed : .pendingAccept
        orders[index] = updateOrderStatus(orders[index], to: target, volunteerPhone: "13800000002")
        return actionResponse(for: orders[index], message: target == .scheduledConfirmed ? "已接下这张预约单" : "接单成功")
    }

    /// 拿不到 `plannedStart` 时判 **false**（当成即时单）：Mock 里造的订单大多不带计划时间，
    /// 让它们默认落进预约态会把所有既有用例的状态机改掉。
    static func isFarFuture(_ order: OrderDetailResponse) -> Bool {
        guard let start = order.plannedStart?.nilIfBlank?.backendTimestamp else { return false }
        return start.timeIntervalSinceNow > mockScheduledAheadThresholdMinutes * 60
    }

    /// `POST /api/orders/{id}/confirm-departure` —— 临期闸门，`SCHEDULED_CONFIRMED → PENDING_ACCEPT`。
    ///
    /// 409 的文案照后端契约：最常见成因是闸门已经把这一单退回重新匹配了，客户端此刻才把确认发上来。
    func handleConfirmDeparture(orderId: Int64) throws -> OrderResponse {
        guard let index = orders.firstIndex(where: { $0.orderId == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        guard orders[index].status == .scheduledConfirmed else {
            throw APIError.serverError(ErrorResponse(
                code: "ORDER_STATUS_NOT_ALLOWED", message: "这一单已经不在待确认状态了"))
        }
        orders[index] = updateOrderStatus(orders[index], to: .pendingAccept)
        return actionResponse(for: orders[index], message: "已确认出发")
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
        // 契约（#346）：两端都能开始，先按的生效；「调用时订单已是 `IN_PROGRESS`（另一端先按了）
        // → 两端都返回 200，不报错」。不照做的话，两人几乎同时按时后按的那一端会念一句报错。
        if orders[index].status == .inProgress {
            return actionResponse(for: orders[index], message: "服务已开始")
        }
        guard orders[index].status == .driverArrived else {
            throw APIError.serverError(ErrorResponse(
                code: "ORDER_STATUS_NOT_ALLOWED", message: "当前订单状态不允许该操作"))
        }
        orders[index] = updateOrderStatus(orders[index], to: .inProgress)
        return actionResponse(for: orders[index], message: "服务已开始")
    }

    /// 契约：响应是裸的 `CancelOrderResponse`（后端 #361）。`countedAsLateCancel` 照后端口径算：
    /// 陪跑员取消且距开跑**严格小于**窗口（默认 12 小时，开跑之后也算）为 `true`，盲人恒为 `false`。
    func handleCancel(orderId: Int64) throws -> CancelOrderResponse {
        guard let index = orders.firstIndex(where: { $0.orderId == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        // 汇合态的跑者取消（后端 #682）：只在后端给了时刻时放行，早于它回 409，message 带时刻。
        if mockRole == .blind, orders[index].status == .driverArrived,
           let raw = orders[index].earliestBlindCancelAt?.nilIfBlank {
            if let opensAt = raw.backendTimestamp, opensAt > Date() {
                let clock = DateFormatter.aidRunDisplayClock.string(from: opensAt)
                throw APIError.serverError(ErrorResponse(
                    code: "BLIND_CANCEL_TOO_EARLY",
                    message: "陪跑员刚到不久，请先打电话联系对方；若一直没碰上，\(clock)之后可以取消"))
            }
            orders[index] = updateOrderStatus(orders[index], to: .cancelled)
            return CancelOrderResponse(success: true, countedAsLateCancel: false)
        }
        guard let role = mockRole, orders[index].status.canCancel(as: role) else {
            throw APIError.serverError(ErrorResponse(
                code: "ORDER_STATUS_NOT_ALLOWED", message: "当前订单状态不允许取消"))
        }
        let countedAsLateCancel = role == .volunteer
            && Self.isWithinLateCancelWindow(plannedStart: orders[index].plannedStart?.backendTimestamp)
        let nextStatus: RunOrderStatus = role == .volunteer ? .rematching : .cancelled
        orders[index] = updateOrderStatus(orders[index], to: nextStatus)
        return CancelOrderResponse(success: true, countedAsLateCancel: countedAsLateCancel)
    }

    /// UI 用例把汇合态的可取消时刻钉在「现在 + N 秒」（`AIDRUN_UI_TEST_BLIND_CANCEL_AFTER_SECONDS`，
    /// 负数 = 已经可以取消）。不设 ⇒ `nil`，正是「后端关了这条出口」那一支 ——
    /// 其余 UI 用例按现有行数断言，凭空多一行会假失败（同种子订单「刻意不带终点」）。
    static func seededBlindCancelAt(for status: RunOrderStatus) -> String? {
        guard status == .driverArrived,
              let raw = ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_BLIND_CANCEL_AFTER_SECONDS"],
              let seconds = Double(raw) else { return nil }
        return DateFormatter.aidRunBackendLocalDateTime.string(from: Date().addingTimeInterval(seconds))
    }

    /// 没有开跑时间的单按「不在窗口内」算 —— Mock 不编一个时间去判罚。
    private static func isWithinLateCancelWindow(plannedStart: Date?, now: Date = Date()) -> Bool {
        guard let plannedStart else { return false }
        return plannedStart.timeIntervalSince(now) < Double(RuleParams.fallback.lateCancelWindowHours) * 3600
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
}
