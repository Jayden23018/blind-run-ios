//
//  MockAPIClient+OrderNudge.swift
//  blindRun
//
//  从 MockAPIClient+Order.swift 原样搬出的 陪跑员订单页 v2 动作分段（#895）。行为零改动。
//  这几条只读写订单上的附属字段，不改订单状态；状态流转都在 +Order.swift。
//

import Foundation

extension MockAPIClient {

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
}
