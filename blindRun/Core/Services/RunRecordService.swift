//
//  RunRecordService.swift
//  blindRun
//
//  跑后运动记录片（OpenSpec `add-post-run-record`，阶段 2 数据层）。照 `IncentiveService.swift` 的写法。
//

import Foundation

// MARK: - Endpoints

/// 一个 case 一条完整字面量路径，理由见 `IncentiveEndpoint`（`validate-spec-coverage.mjs` 只认字面量）。
enum RunRecordEndpoint {
    case record(orderId: Int64)
    case myMonthlyRecords
    case postMessage(orderId: Int64)

    var request: EndpointRequest {
        switch self {
        case .record(let orderId):
            return EndpointRequest(.get, "/api/orders/\(orderId)/run-record")
        case .myMonthlyRecords:
            return EndpointRequest(.get, "/api/orders/mine/run-records")
        case .postMessage(let orderId):
            return EndpointRequest(.post, "/api/orders/\(orderId)/run-record/messages")
        }
    }
}

// MARK: - Protocol

/// 跑后记录片对外的全部能力。
///
/// ⚠️ 与 `IncentiveServing` 的「每个方法都必须有生产调用点」不同：阶段 2 刻意先交数据层，
/// 调用点在后续阶段落地 —— `monthlyRecords` 是阶段 3（记录 tab），`record` 是阶段 4/5（两端详情），
/// `postMessage` 是阶段 6（留言）。哪个阶段做完还没接上，就当场删掉那个方法。
///
/// 错误一律 `throws`，这一层不吞，也不重试 `GENERATING`（1–2 秒后重读由界面层决定）。
protocol RunRecordServing: Sendable {
    /// 订单不是 `COMPLETED` → 409 `ORDER_STATUS_NOT_ALLOWED`；非双方 → 403。
    func record(orderId: Int64) async throws -> RunRecordResponse
    /// `month` 取 1–12。按当前登录角色返回。
    func monthlyRecords(year: Int, month: Int) async throws -> RunRecordHistoryResponse
    /// 1–200 字、去首尾空白由**后端**校验；这一层原样发送。
    func postMessage(orderId: Int64, text: String) async throws -> RunRecordMessageResponse
}

// MARK: - Implementation

struct RunRecordService: RunRecordServing {
    let transport: any APIClientProtocol

    func record(orderId: Int64) async throws -> RunRecordResponse {
        try await transport.send(RunRecordEndpoint.record(orderId: orderId).request)
    }

    func monthlyRecords(year: Int, month: Int) async throws -> RunRecordHistoryResponse {
        try await transport.send(
            RunRecordEndpoint.myMonthlyRecords.request,
            query: ["month": Self.monthQuery(year: year, month: month)]
        )
    }

    func postMessage(orderId: Int64, text: String) async throws -> RunRecordMessageResponse {
        try await transport.send(
            RunRecordEndpoint.postMessage(orderId: orderId).request,
            body: RunRecordMessageRequest(text: text)
        )
    }

    /// 契约 pattern `^\d{4}-(0[1-9]|1[0-2])$`。
    static func monthQuery(year: Int, month: Int) -> String {
        String(format: "%04d-%02d", year, month)
    }
}
