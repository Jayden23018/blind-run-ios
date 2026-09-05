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
        // 提前量（422 APPOINTMENT_TOO_SOON）→ 实名（403 IDENTITY_NOT_VERIFIED）
        // → 紧急联系人（403 EMERGENCY_CONTACT_REQUIRED）。
        // 顺序错了会让 Mock 引导用户先补一个后端根本不会先拒的项。
        // 注意：后端**不校验** `BlindProfile.name`，Mock 也不能比后端严；
        // 之前那条 `PROFILE_INCOMPLETE` 是真实后端永不返回的死码，已删除。
        //
        // ⚠️ 后端 N134 在提前量之后还加了两道，Mock **刻意不镜像**（2026-09-05）：
        // `APPOINTMENT_TOO_LONG`（>300 分钟）和 `APPOINTMENT_IN_NIGHT_WINDOW`
        // （整段落进 `[22:00, 05:00)`）。前者客户端到不了 —— 表单选择器最大 120 分钟、
        // 语音被 `VoiceOrderWizard.acceptedDurationMinutes` 夹在 10–300，Mock 加了也是死分支。
        // 后者会把整个测试套件变成看墙钟的：本仓多条用例按 `Date() + 45 分钟` 下单
        // （`blindRunTests.swift:1220`、`OrderReviewAndStatusLogDecodingTests.swift:152`、
        // `BlindIdentityAndContactModelTests.swift:347`），镜像之后它们白天全绿、
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

        guard BlindVerifyStatus.parse(blindVerifyStatus) == .verified else {
            throw APIError.serverError(ErrorResponse(
                code: "IDENTITY_NOT_VERIFIED", message: "请先完成实名认证再下单"))
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
}
