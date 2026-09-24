//
//  MockAPIClient+RunRecord.swift
//  blindRun
//
//  跑后运动记录的进程内 Mock（OpenSpec `add-post-run-record`）。
//  只演契约里「形状」相关的事实：完成闸、按角色裁剪的字段、留言校验。
//  数字是写死的样例，不是从轨迹算的 —— 计算口径在后端，Mock 算一遍就成了第二个真相源。
//

import Foundation

extension MockAPIClient {

    func handleGetRunRecord(orderId: Int64) throws -> RunRecordResponse {
        let order = try completedOrderForRunRecord(orderId: orderId)
        let isBlind = mockRole == .blind
        let startedAt = order.acceptedAt ?? "2026-07-21T08:00:00"
        let points: [RunTrackPoint] = {
            guard let lat = order.startLatitude, let lng = order.startLongitude else { return [] }
            return [
                RunTrackPoint(t: 0, lat: lat, lng: lng, d: 0),
                RunTrackPoint(t: 360, lat: lat + 0.004, lng: lng + 0.003, d: 520),
                RunTrackPoint(t: 720, lat: lat + 0.008, lng: lng + 0.006, d: 1_040)
            ]
        }()
        return RunRecordResponse(
            orderId: orderId,
            status: points.count >= 2 ? .ready : .insufficientTrack,
            viewerRole: isBlind ? .blind : .volunteer,
            place: order.startAddress,
            blindName: order.blindName,
            volunteerName: order.volunteerName,
            runStartedAt: points.isEmpty ? nil : startedAt,
            runEndedAt: points.isEmpty ? nil : "2026-07-21T08:12:00",
            summary: points.isEmpty ? nil : RunSummary(
                distanceM: 1_040, movingSec: 690, elapsedSec: 720, restSec: 30,
                avgPaceSecPerKm: 663,
                // 两台手机各自的数据（D3）：Mock 让两端看到不同的数，界面阶段才验得出「没挑错人」。
                steps: isBlind ? 1_320 : 1_180,
                avgCadence: isBlind ? 168 : 162,
                elevationGainM: isBlind ? 4 : 3
            ),
            splits: points.isEmpty ? [] : [
                RunSplit(index: 1, distanceM: 1_000, durationSec: 663, paceSecPerKm: 663, avgCadence: isBlind ? 168 : 162),
                RunSplit(index: 2, distanceM: 40, durationSec: 27, paceSecPerKm: 675, avgCadence: nil)
            ],
            fastestSplitIndex: nil,
            paceSamples: points.isEmpty ? [] : [
                RunPaceSample(distanceM: 0, paceSecPerKm: 690),
                RunPaceSample(distanceM: 500, paceSecPerKm: 650),
                RunPaceSample(distanceM: 1_000, paceSecPerKm: 660)
            ],
            stops: [],
            events: [
                RunEvent(type: .runStarted, at: startedAt, inferred: false, durationSec: nil, lat: nil, lng: nil),
                RunEvent(type: .orderCompleted, at: "2026-07-21T08:13:00", inferred: false, durationSec: nil, lat: nil, lng: nil)
            ],
            sosTriggered: false,
            service: RunService(
                startedAt: startedAt,
                completedAt: "2026-07-21T08:13:00",
                durationMin: 13,
                volunteerTotalServiceMinutes: 1_260
            ),
            // 只给跑者（D6）。
            comparison: isBlind ? RunComparison(previousOrderId: orderId - 1, previousDistanceM: 900, deltaDistanceM: 140) : nil,
            messages: runRecordMessages[orderId] ?? [],
            track: points.count >= 2 ? RunTrack(coordSystem: "GCJ02", startedAt: startedAt, points: points) : nil
        )
    }

    /// 后端按 `finishedAt` 归月；`OrderDetailResponse` 没有这个字段，Mock 用 `createdAt` 近似。
    func handleGetMyRunRecords(query: [String: String]?) throws -> RunRecordHistoryResponse {
        guard let month = query?["month"],
              month.range(of: #"^\d{4}-(0[1-9]|1[0-2])$"#, options: .regularExpression) != nil else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "month 格式应为 YYYY-MM"))
        }
        let isBlind = mockRole == .blind
        let completed = orders.filter { $0.status == .completed && ($0.createdAt ?? "").hasPrefix(month) }
        let items = completed.map { order in
            RunHistoryItem(
                orderId: order.orderId,
                finishedAt: order.createdAt ?? "\(month)-01T08:13:00",
                place: order.startAddress,
                partnerName: isBlind ? order.volunteerName : order.blindName,
                distanceM: 1_040,
                // 缩略图只给陪跑员。
                thumbnail: isBlind ? nil : order.startLatitude.flatMap { lat in
                    order.startLongitude.map { [RunLatLng(lat: lat, lng: $0)] }
                }
            )
        }
        return RunRecordHistoryResponse(
            role: isBlind ? .blind : .volunteer,
            month: month,
            monthSummary: RunMonthSummary(
                runs: items.count,
                distanceM: items.isEmpty ? nil : items.count * 1_040,
                serviceMin: isBlind ? nil : Int64(items.count * 13),
                topPartner: items.first.map { RunTopPartner(name: $0.partnerName, runs: items.count) }
            ),
            items: items
        )
    }

    func handlePostRunRecordMessage(orderId: Int64, body: (any Encodable & Sendable)?) throws -> RunRecordMessageResponse {
        _ = try completedOrderForRunRecord(orderId: orderId)
        guard let data = try? JSONEncoder().encode(MockAnyEncodable(body)),
              let request = try? JSONDecoder().decode(MockRunRecordMessageBody.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "请求格式错误"))
        }
        guard request.type == RunRecordMessageType.text.rawValue else {
            throw APIError.serverError(ErrorResponse(code: "BAD_REQUEST", message: "本期只支持文字留言"))
        }
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...200).contains(text.count) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "留言需为 1–200 字"))
        }
        let existing = runRecordMessages[orderId] ?? []
        let message = RunRecordMessageResponse(
            id: Int64(existing.count + 1),
            fromRole: mockRole == .blind ? .blind : .volunteer,
            type: .text,
            text: text,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        runRecordMessages[orderId] = existing + [message]
        return message
    }

    private func completedOrderForRunRecord(orderId: Int64) throws -> OrderDetailResponse {
        guard let order = orders.first(where: { $0.orderId == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        guard order.status == .completed else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_STATUS_NOT_ALLOWED", message: "订单还没完成"))
        }
        return order
    }
}

/// 解请求体用。`RunRecordMessageRequest` 只有 Encodable（它的 `type` 是封闭枚举，
/// 拿它解一条 `VOICE` 会直接失败，Mock 就演不出后端的 400 `BAD_REQUEST`）。
private struct MockRunRecordMessageBody: Decodable {
    let type: String
    let text: String
}
