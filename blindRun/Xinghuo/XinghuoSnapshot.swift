import CoreLocation
import Foundation

/// 星火页一屏要画的全部东西：顶部四个数 + 地图上的聚合片区。
///
/// **这个形状就是二期要向后端要的契约**（`openspec/changes/add-xinghuo-companion-map`）。
/// 片区的 `center` 是网格中心，不是任何人的坐标 —— 网格化与 k 阈值必须在服务端做完
/// （09-13 调研：客户端拿到明细坐标，Tinder / Bumble 那种三边定位就成立）。
/// 一期后端没有这个端点，页面只吃 `demo(around:seed:)`，且只在调试版出现。
struct XinghuoSnapshot: Equatable {
    enum Kind: Equatable {
        case volunteer
        case runner
    }

    struct Cell: Equatable, Identifiable {
        let id: String
        let center: CLLocationCoordinate2D
        let kind: Kind
        let count: Int
    }

    let regionName: String
    let volunteersOnline: Int
    let runnersWaiting: Int
    let pairsRunning: Int
    let todayRuns: Int
    let todayKm: Double
    let cells: [Cell]

    /// 盲人端只看志愿者：盲人要的是「有人愿意帮我」，不是「还有别的盲人」（09-21 调研）。
    func cells(for role: UserRole) -> [Cell] {
        role == .volunteer ? cells : cells.filter { $0.kind == .volunteer }
    }

    /// 页面第一个读屏元素，也是「听见星光」念的那一句。
    ///
    /// 只有汇总数字：不带方位（「东边」还是「右前方」没定）、不带地点、不逐条播报 ——
    /// 逐条的「某处刚亮了一位」是 09-13 判过的时序攻击通道。人数为 0 时如实说没有。
    func summaryText(for role: UserRole) -> String {
        var sentences: [String] = []
        if volunteersOnline > 0 {
            var head = "\(regionName)现在有 \(volunteersOnline) 位志愿者在线"
            if role == .volunteer {
                head += "，\(runnersWaiting) 位视障跑者在等待陪跑，\(pairsRunning) 对正在同行"
            }
            sentences.append(head)
        } else {
            sentences.append("\(regionName)暂时没有志愿者在线")
        }
        if todayRuns > 0 {
            sentences.append("今天完成了 \(todayRuns) 次陪跑，一共 \(Self.kmText(todayKm)) 公里")
        } else {
            sentences.append("今天还没有完成的陪跑")
        }
        return sentences.joined(separator: "。") + "。"
    }

    static func kmText(_ km: Double) -> String {
        String(format: "%.1f", km)
    }

    /// 片区人数 → 画多大。封顶三档：光晕不封顶时规模一大就糊成一片（09-11 调研）。
    static func tier(forCount count: Int) -> Int {
        switch count {
        case ..<5: return 1
        case 5..<15: return 2
        default: return 3
        }
    }
}

/// 「我的足迹」：星火页上唯一的真实数据 —— 自己今天跑完的那几单的路线。
enum XinghuoFootprints {
    /// 今天（按开跑时间算）已完成的订单。只看 `myOrders()` 第一页：一天跑完的单不会多到翻页。
    static func todaysCompletedOrderIDs(
        in orders: [OrderDetailResponse],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Int64] {
        orders.compactMap { order in
            guard order.status == .completed,
                  let start = order.plannedStart?.backendTimestamp,
                  calendar.isDate(start, inSameDayAs: now) else { return nil }
            return order.orderId
        }
    }
}

#if DEBUG
extension XinghuoSnapshot {
    /// 演示数据：以 `center` 为中心、约 500 m 网格上撒 150 位志愿者、40 位跑者，按格聚合。
    /// 固定种子 ⇒ 同一个中心每次画出来一样（测试与截图对照都靠这一点）。
    // ponytail: 二期换成聚合端点的响应，这个函数随调试入口一起删掉。
    static func demo(around center: CLLocationCoordinate2D, seed: UInt64 = 20260923) -> XinghuoSnapshot {
        var state = seed
        func next(_ upper: Int) -> Int {
            // 线性同余，够用且与平台无关（`SystemRandomNumberGenerator` 不能设种子）。
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(upper))
        }

        let latStep = 0.0045
        let lngStep = 0.0045 / max(cos(center.latitude * .pi / 180), 0.1)
        let span = 13   // −6…+6 格 ≈ 方圆 3 公里
        var counts: [String: (kind: Kind, x: Int, y: Int, count: Int)] = [:]
        for (kind, people) in [(Kind.volunteer, 150), (Kind.runner, 40)] {
            for _ in 0..<people {
                let x = next(span) - span / 2
                let y = next(span) - span / 2
                let key = "\(kind)-\(x)-\(y)"
                counts[key, default: (kind, x, y, 0)].count += 1
            }
        }
        let cells = counts.keys.sorted().compactMap { key -> Cell? in
            guard let entry = counts[key] else { return nil }
            return Cell(
                id: key,
                center: CLLocationCoordinate2D(
                    latitude: center.latitude + Double(entry.y) * latStep,
                    longitude: center.longitude + Double(entry.x) * lngStep
                ),
                kind: entry.kind,
                count: entry.count
            )
        }
        return XinghuoSnapshot(
            regionName: "本市",
            volunteersOnline: 150,
            runnersWaiting: 40,
            pairsRunning: 14,
            todayRuns: 23,
            todayKm: 86.5,
            cells: cells
        )
    }
}
#endif
