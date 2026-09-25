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
        // 所有时刻都从同一个起点往后推，时间轴才不会前后错乱。
        let base = order.acceptedAt?.backendTimestamp ?? Date(timeIntervalSince1970: 1_784_592_000)
        let at: (TimeInterval) -> String = { DateFormatter.aidRunBackendLocalDateTime.string(from: base.addingTimeInterval($0)) }
        let startedAt = at(0)
        let points = order.startLatitude.flatMap { lat in
            order.startLongitude.map { Self.mockLoop(startLatitude: lat, startLongitude: $0) }
        } ?? []
        let hasTrack = points.count >= 2
        // 一圈 3.2 公里：三段满公里 + 最后 200 米，第 1.5 公里处歇了 100 秒。
        // 分段够 3 段才演得出「最快」，有休息点才验得出地图上的休息标注和时间轴那一行。
        let splitPaces = [372, 348, 395, 410]
        let splits = splitPaces.enumerated().map { offset, pace in
            let distance = offset < 3 ? 1_000 : 200
            return RunSplit(
                index: offset + 1, distanceM: distance, durationSec: pace * distance / 1_000, paceSecPerKm: pace,
                avgCadence: isBlind ? 168 - offset : 162 - offset
            )
        }
        let restPoint = points.first { $0.d >= 1_500 }
        return RunRecordResponse(
            orderId: orderId,
            status: hasTrack ? .ready : .insufficientTrack,
            viewerRole: isBlind ? .blind : .volunteer,
            place: order.startAddress,
            blindName: order.blindName,
            volunteerName: order.volunteerName,
            runStartedAt: hasTrack ? startedAt : nil,
            runEndedAt: hasTrack ? at(1_297) : nil,
            summary: hasTrack ? RunSummary(
                distanceM: 3_200, movingSec: 1_197, elapsedSec: 1_297, restSec: 100,
                avgPaceSecPerKm: 374,
                // 两台手机各自的数据（D3）：Mock 让两端看到不同的数，界面阶段才验得出「没挑错人」。
                steps: isBlind ? 3_320 : 3_180,
                avgCadence: isBlind ? 168 : 162,
                elevationGainM: isBlind ? 14 : 12
            ) : nil,
            splits: hasTrack ? splits : [],
            fastestSplitIndex: hasTrack ? 2 : nil,
            paceSamples: hasTrack ? stride(from: 0, through: 3_200, by: 50).map { distance in
                // 前段稳、中段提速、休息后变慢：着色能看出三档。
                let wave = sin(Double(distance) / 3_200 * .pi * 2) * 30
                return RunPaceSample(distanceM: distance, paceSecPerKm: 372 - Int(wave) + (distance > 2_000 ? 30 : 0))
            } : [],
            stops: restPoint.map {
                [RunStop(startedAt: at(558), durationSec: 100, atDistanceM: 1_500, lat: $0.lat, lng: $0.lng, placeName: nil)]
            } ?? [],
            events: [
                RunEvent(type: .arrived, at: at(-300), inferred: false, durationSec: nil, lat: nil, lng: nil),
                RunEvent(type: .runStarted, at: startedAt, inferred: false, durationSec: nil, lat: nil, lng: nil),
                RunEvent(type: .rest, at: at(558), inferred: true, durationSec: 100, lat: restPoint?.lat, lng: restPoint?.lng),
                RunEvent(type: .runEnded, at: at(1_297), inferred: true, durationSec: nil, lat: nil, lng: nil),
                RunEvent(type: .orderCompleted, at: at(1_380), inferred: false, durationSec: nil, lat: nil, lng: nil)
            ],
            sosTriggered: false,
            service: RunService(
                startedAt: startedAt,
                completedAt: at(1_380),
                durationMin: 23,
                volunteerTotalServiceMinutes: 1_260
            ),
            // 只给跑者（D6）。
            comparison: isBlind ? RunComparison(previousOrderId: orderId - 1, previousDistanceM: 2_900, deltaDistanceM: 300) : nil,
            // 跑者那一侧默认带一条陪跑员留言：讲述的最后一句要读它（HANDOFF 6.3 第 2 条）。
            // 谁发过一条（阶段 6）就换成真实发出的那些。
            messages: runRecordMessages[orderId] ?? (isBlind ? [RunRecordMessageResponse(
                id: 1, fromRole: .volunteer, type: .text, text: "今天节奏很稳，第二公里你跑得特别好，下周六还一起跑。", createdAt: at(1_500)
            )] : []),
            track: hasTrack ? RunTrack(coordSystem: "GCJ02", startedAt: startedAt, points: points) : nil
        )
    }

    /// 从起点出发绕一个半径约 509 米的圈回到起点（周长 ≈ 3.2 公里），每 100 米一个点。
    /// 起终点重合，演的是「起终点」合并那一支。
    static func mockLoop(startLatitude lat: Double, startLongitude lng: Double) -> [RunTrackPoint] {
        let radius = 3_200 / (2 * Double.pi)
        let metresPerDegreeLat = 111_000.0
        let metresPerDegreeLng = metresPerDegreeLat * cos(lat * .pi / 180)
        return stride(from: 0, through: 3_200, by: 100).map { distance in
            let theta = Double(distance) / 3_200 * 2 * .pi
            let restSeconds = distance > 1_500 ? 100.0 : 0
            return RunTrackPoint(
                t: Double(distance) * 0.374 + restSeconds,
                lat: lat + radius * sin(theta) / metresPerDegreeLat,
                lng: lng + radius * (1 - cos(theta)) / metresPerDegreeLng,
                d: distance
            )
        }
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
                // 缩略图只给陪跑员。一圈 8 个点绕回起点：只给一个点的话，列表里的路线形状
                // 在 Mock 下永远是一个圆点，界面阶段验不出折线画没画对。
                thumbnail: isBlind ? nil : order.startLatitude.flatMap { lat in
                    order.startLongitude.map { lng in
                        [(0, 0), (4, 1), (7, 4), (8, 8), (6, 11), (2, 10), (-1, 6), (0, 0)].map {
                            RunLatLng(lat: lat + Double($0.0) * 0.0005, lng: lng + Double($0.1) * 0.0005)
                        }
                    }
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
        // 与后端同口径：`@NotBlank` + `@Size(max = 200)` 校验的是**原串**（Java `length()` = UTF-16 码元），存之前才去空白。
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, request.text.utf16.count <= 200 else {
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
