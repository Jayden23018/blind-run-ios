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
            // 契约 `RunRecordResponse.blindName` 是脱敏的（`张*`）。订单种子存全名，原样回传等于 Mock 替
            // 后端放宽了脱敏，「读屏不念星号」的用例也就分不出修没修（#247 验红时红不起来）。
            blindName: WeChatShareCard.maskedName(order.blindName),
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

    /// UI 用例种首页的跑步记录：`this` = 本月跑过三次，`last` = 只有上月跑过。
    func seedHomeHistoryForUITestIfRequested() {
        guard let period = ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_SEED_HOME_HISTORY"] else { return }
        let date = period == "last" ? Calendar.current.date(byAdding: .month, value: -1, to: Date())! : Date()
        let stamp = ISO8601DateFormatter().string(from: date)
        orders = (1...3).map { index in
            OrderDetailResponse(
                orderId: Int64(index),
                status: .completed,
                startAddress: "朝阳公园南门",
                startLatitude: 39.9342,
                startLongitude: 116.4740,
                endAddress: nil,
                endLatitude: nil,
                endLongitude: nil,
                plannedStart: stamp,
                plannedEnd: stamp,
                blindName: "李明",
                blindPhone: "13800001001",
                volunteerPhone: nil,
                acceptedAt: nil,
                createdAt: stamp,
                expectedDurationMinutes: 60,
                pacePreference: .moderate,
                routePreference: .parkTrail,
                routeNotes: nil,
                hasGuideDogThisRun: false,
                specialNotes: nil,
                visionLevel: "TOTAL_BLIND",
                tetherPreference: "TETHER_ROPE",
                chatPreference: "PREFER_CHAT"
            )
        }
        nextOrderId = 10
    }

    /// UI 用例与截图种「连续陪跑」跑步数据页的近半年样例（#710）：`AIDRUN_UI_TEST_SEED_RUN_DATA=1`。
    ///
    /// 照定稿 `run-data-final.html` 页内脚本生成（同一个伪随机种子 11）：26 周里有两周中断、
    /// 每周 1–3 次、每次 2–6.6 公里；第 12–18 周与最后 3 周的第一单都和「李*」跑 ——
    /// 与 `handleGetPartnerStreaks` 的「李* 连续 3 周、最好 7 周」对得上。
    /// 数字是写死的样例，不是从轨迹算的；只为截图里看得出图的起伏。
    func seedRunDataForUITestIfRequested() {
        guard ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_SEED_RUN_DATA"] == "1" else { return }
        let calendar = Calendar.volunteerRunData
        let fullNames = ["李*": "李明", "王*": "王芳", "张*": "张伟"]
        let formatter = DateFormatter.aidRunBackendLocalDateTime
        let now = Date()
        orders = Self.mockRunDataSchedule(now: now, calendar: calendar)
            .sorted { $0.day > $1.day }
            .enumerated()
            .map { index, run in
                let orderId = Int64(2_000 + index)
                // 落在今天时不晚于现在：周一清早 6:30 之前跑测，「将来」的一单会被数据页过滤掉，
                // 而 Mock 火花仍说本周记上了，两边对不上。
                let planned = calendar.date(bySettingHour: 6, minute: 30, second: 0, of: run.day) ?? run.day
                let finished = min(planned, now.addingTimeInterval(-60))
                runRecordSamples[orderId] = MockRunRecordSample(
                    distanceM: Int((run.km * 1_000).rounded()),
                    serviceMin: Int((run.km * 8.5 + 18).rounded())
                )
                return Self.mockCompletedOrder(
                    orderId: orderId, stamp: formatter.string(from: finished), place: run.place, blindName: fullNames[run.partner]
                )
            }
        nextOrderId = 3_000
    }

    /// 定稿脚本的那份日程：(哪天, 公里, 搭档掩码名, 地点)。
    static func mockRunDataSchedule(now: Date, calendar: Calendar) -> [(day: Date, km: Double, partner: String, place: String)] {
        let thisMonday = VolunteerRunDataSummary.monday(of: now, calendar: calendar)
        let todayIndex = (calendar.component(.weekday, from: now) + 5) % 7
        guard let start = calendar.date(byAdding: .weekOfYear, value: -25, to: thisMonday) else { return [] }
        var seed: UInt64 = 11
        func random() -> Double {
            seed = (seed * 16_807) % 2_147_483_647
            return Double(seed - 1) / 2_147_483_646
        }
        let places = ["西湖", "钱塘江边", "运河公园", "西湖"]
        let pool = [5, 6, 5, 6, 2, 3, 1]
        var runs: [(day: Date, km: Double, partner: String, place: String)] = []
        for week in 0..<26 where week != 9 && week != 10 {
            guard let monday = calendar.date(byAdding: .weekOfYear, value: week, to: start) else { continue }
            if week == 25 {
                // 本周一单，落在今天之前（今天是周一就落在今天一早）。
                runs.append((calendar.date(byAdding: .day, value: min(1, todayIndex), to: monday) ?? monday, 4.2, "李*", "西湖"))
                continue
            }
            let count = random() < 0.3 ? 1 : (random() < 0.75 ? 2 : 3)
            var used = Set<Int>()
            for index in 0..<count {
                var weekday = pool[Int(random() * Double(pool.count))]
                if used.contains(weekday) { weekday = (weekday + 3) % 7 }
                used.insert(weekday)
                let partner = index == 0
                    ? ((12...18).contains(week) || week >= 23 ? "李*" : "王*")
                    : (random() < 0.5 ? "张*" : "王*")
                let km = ((2 + random() * 4.6) * 10).rounded() / 10
                let place = places[Int(random() * Double(places.count))]
                if let day = calendar.date(byAdding: .day, value: weekday, to: monday) {
                    runs.append((day, km, partner, place))
                }
            }
        }
        return runs
    }

    /// 一张已完成的样例单。`stamp` 是后端无时区的 `LocalDateTime` 串（`finishedAt` 归月靠它）。
    static func mockCompletedOrder(orderId: Int64, stamp: String, place: String, blindName: String?) -> OrderDetailResponse {
        OrderDetailResponse(
            orderId: orderId,
            status: .completed,
            startAddress: place,
            startLatitude: 30.2590,
            startLongitude: 120.1480,
            endAddress: nil,
            endLatitude: nil,
            endLongitude: nil,
            plannedStart: stamp,
            plannedEnd: stamp,
            blindName: blindName,
            blindPhone: "13800001001",
            volunteerPhone: nil,
            acceptedAt: nil,
            createdAt: stamp,
            expectedDurationMinutes: 60,
            pacePreference: .moderate,
            routePreference: .parkTrail,
            routeNotes: nil,
            hasGuideDogThisRun: false,
            specialNotes: nil,
            visionLevel: "TOTAL_BLIND",
            tetherPreference: "TETHER_ROPE",
            chatPreference: "PREFER_CHAT"
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
                partnerName: isBlind ? order.volunteerName : WeChatShareCard.maskedName(order.blindName),
                distanceM: runRecordSamples[order.orderId]?.distanceM ?? 1_040,
                // 两个角色都给缩略图（blind-run-backend#940：跑者也拿自己的路线，列表每行一张 88pt 小地图，#823）。
                // 一圈 8 个点绕回起点：只给一个点的话，列表里的路线形状在 Mock 下永远是一个圆点，界面阶段验不出折线画没画对。
                thumbnail: order.startLatitude.flatMap { lat in
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
                distanceM: items.isEmpty ? nil : items.compactMap(\.distanceM).reduce(0, +),
                serviceMin: isBlind ? nil : Int64(completed.map { runRecordSamples[$0.orderId]?.serviceMin ?? 13 }.reduce(0, +)),
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

/// 跑步数据页样例的一单（#710）。
struct MockRunRecordSample {
    let distanceM: Int?
    let serviceMin: Int
}
