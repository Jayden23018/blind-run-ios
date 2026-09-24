import CoreLocation
import Foundation

/// 星火页一屏要画的全部东西：顶部四个数 + 地图上的聚合片区。
///
/// **这个形状就是二期要向后端要的契约**（`openspec/changes/add-xinghuo-companion-map`）。
/// 片区的 `center` 是网格中心，不是任何人的坐标 —— 网格化与 k 阈值必须在服务端做完
/// （09-13 调研：客户端拿到明细坐标，Tinder / Bumble 那种三边定位就成立）。
/// 一期后端没有这个端点，页面只吃 `demo(around:seed:)`，且只在调试版出现。
struct XinghuoSnapshot: Equatable {
    enum Kind: Equatable, Sendable {
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

    // MARK: - 片区 → 一簇星（纯视觉）

    /// 一个片区最多画几颗星。人再多也不加：星太密就糊成一团光，和光晕封顶三档是同一个理由。
    static let maxSparksPerCell = 12

    /// 星在片区中心周围散开的半径。片区约 500 m 见方（半宽约 250 m），180 m 保证
    /// **一颗星也不会画进隔壁片区** —— 否则画面会暗示一个数据里根本没有的位置。
    // ponytail: 二期的格子可能被归并到更粗一级，那时半径要跟着响应里的格子尺寸走（已记 handoff）。
    static let sparkScatterMeters = 180.0

    /// 把一个片区画成一小簇大小、亮度、闪烁节奏各不相同的星 —— 原型里那种「许多独立的星」。
    ///
    /// **这是纯视觉处理，不是位置。** 输入只有片区中心和人数，散布用 `cell.id` 做种子：
    /// 同一个片区每次画出来一样（不会一刷新就跳），演示数据和二期真数据画法完全相同。
    /// `origin` 只用来排点亮顺序（离「你」越近越先亮），不参与散布。
    static func sparks(
        for cell: Cell,
        origin: CLLocationCoordinate2D
    ) -> [(id: String, coordinate: CLLocationCoordinate2D, spark: XinghuoSpark)] {
        var rng = XinghuoRandom(seed: XinghuoRandom.fnv1a(cell.id))
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLng = metersPerDegreeLat * max(cos(cell.center.latitude * .pi / 180), 0.1)
        return (0..<min(max(cell.count, 0), maxSparksPerCell)).map { index in
            // 圆内均匀：半径取 sqrt，否则星会挤在中心。
            let radius = sparkScatterMeters * Double.random(in: 0..<1, using: &rng).squareRoot()
            let angle = Double.random(in: 0..<(2 * .pi), using: &rng)
            let coordinate = CLLocationCoordinate2D(
                latitude: cell.center.latitude + radius * sin(angle) / metersPerDegreeLat,
                longitude: cell.center.longitude + radius * cos(angle) / metersPerDegreeLng
            )
            let east = (coordinate.longitude - origin.longitude) * metersPerDegreeLng
            let north = (coordinate.latitude - origin.latitude) * metersPerDegreeLat
            // 原型 `begin()`：0.7 s 之后从「你」向外，每公里晚 0.33 s，再加一点随机免得整圈同时亮。
            let igniteDelay = 0.7 + (east * east + north * north).squareRoot() * 0.00033
                + Double.random(in: 0..<0.25, using: &rng)
            let spark = XinghuoSpark(
                kind: cell.kind,
                scale: Double.random(in: 0.75...1.2, using: &rng),
                brightness: Double.random(in: 0.6...1, using: &rng),
                rotation: Double.random(in: -0.3...0.3, using: &rng),
                twinklePeriod: Double.random(in: 3...8, using: &rng),
                phase: Double.random(in: 0..<1, using: &rng),
                igniteDelay: igniteDelay
            )
            return ("\(cell.id)#\(index)", coordinate, spark)
        }
    }
}

/// 一颗星怎么画：大小、亮度、闪烁节奏、点亮时刻。全部由 `XinghuoSnapshot.sparks` 按片区确定性生成。
struct XinghuoSpark: Equatable, Sendable {
    let kind: XinghuoSnapshot.Kind
    let scale: Double
    let brightness: Double
    let rotation: Double
    /// 一次明暗往返的秒数。原型 `tw` 取 0.8–2.2 rad/s，折成周期约 3–8 s。
    let twinklePeriod: Double
    /// 0..<1，把各颗星的闪烁错开。
    let phase: Double
    /// 进页面之后多少秒点亮。「减弱动态效果」打开时不用它，全部直接出现。
    let igniteDelay: Double
}

/// 可设种子的随机源：`SystemRandomNumberGenerator` 不能设种子，而星的散布必须每次一样。
struct XinghuoRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        // 线性同余（Knuth MMIX 常数），再把高低位混一下，低位的周期太短。
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state ^ (state >> 29)
    }

    /// 字符串 → 种子。**不能用 `String.hashValue`**：它每次启动都加盐，同一个片区会换一种撒法。
    static func fnv1a(_ text: String) -> UInt64 {
        text.utf8.reduce(14695981039346656037) { ($0 ^ UInt64($1)) &* 1099511628211 }
    }

    /// 标准正态（Box–Muller）。
    mutating func gaussian() -> Double {
        let u = Double.random(in: Double.leastNonzeroMagnitude..<1, using: &self)
        let v = Double.random(in: 0..<1, using: &self)
        return (-2 * log(u)).squareRoot() * cos(2 * .pi * v)
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
    /// 演示数据：以 `center` 为中心撒 150 位志愿者、40 位跑者，再按约 500 m 网格聚合。
    /// 人不是均匀撒的：原型里人扎堆在海岸、公园和「你」附近，均匀撒出来的是一张棋盘。
    /// 固定种子 ⇒ 同一个中心每次画出来一样（测试与截图对照都靠这一点）。
    // ponytail: 二期换成聚合端点的响应，这个函数随调试入口一起删掉。
    static func demo(around center: CLLocationCoordinate2D, seed: UInt64 = 20260923) -> XinghuoSnapshot {
        var rng = XinghuoRandom(seed: seed)
        // 热点：相对中心往东 / 往北多少米，以及扎堆的范围（米）。第一个就是「你」身边。
        let hotspots: [(east: Double, north: Double, spread: Double)] = [
            (0, 0, 700), (-1600, -900, 450), (1400, -1300, 500), (1800, 1100, 400), (-1200, 1500, 550),
        ]
        let cellMeters = 500.0
        let half = 6   // −6…+6 格 ≈ 方圆 3 公里
        func cellIndex(_ meters: Double) -> Int {
            min(max(Int((meters / cellMeters).rounded()), -half), half)
        }

        let latStep = 0.0045
        let lngStep = 0.0045 / max(cos(center.latitude * .pi / 180), 0.1)
        var counts: [String: (kind: Kind, x: Int, y: Int, count: Int)] = [:]
        for (kind, people) in [(Kind.volunteer, 150), (Kind.runner, 40)] {
            for _ in 0..<people {
                let east: Double
                let north: Double
                if Double.random(in: 0..<1, using: &rng) < 0.2 {
                    east = Double.random(in: -3000...3000, using: &rng)
                    north = Double.random(in: -3000...3000, using: &rng)
                } else {
                    let spot = hotspots[Int.random(in: 0..<hotspots.count, using: &rng)]
                    east = spot.east + rng.gaussian() * spot.spread
                    north = spot.north + rng.gaussian() * spot.spread
                }
                let x = cellIndex(east)
                let y = cellIndex(north)
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

extension XinghuoFootprints {
    /// 演示足迹：绕「你」一圈、带一点起伏的环线（约 2.6 km）。
    ///
    /// 只在**真实足迹加载成功但今天一条都没有**时画（项目负责人 2026-09-23：没有它，
    /// 真机验收时根本看不到光带效果）。加载失败时不拿它顶替 —— 那会把「出错了」伪装成「有数据」。
    static func demoLoop(around center: CLLocationCoordinate2D) -> [CLLocationCoordinate2D] {
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLng = metersPerDegreeLat * max(cos(center.latitude * .pi / 180), 0.1)
        let points = 48
        return (0...points).map { index in
            let t = Double(index) / Double(points) * 2 * .pi
            let wobble = 40 * sin(3 * t)
            let east = -200 + (500 + wobble) * cos(t)
            let north = -150 + (320 + wobble) * sin(t)
            return CLLocationCoordinate2D(
                latitude: center.latitude + north / metersPerDegreeLat,
                longitude: center.longitude + east / metersPerDegreeLng
            )
        }
    }
}
#endif
