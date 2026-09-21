#!/bin/bash
# 「一束光地图」方向 A 验证：**没有底图，地图完全由人点出来**。
#
# 和 render-lantern-scale-preview.sh 是两件事：
#   - scale-preview  = 方向 C，卫星照片当底 + 光点叠上去
#   - 本脚本         = 方向 A，**画面上一个像素的照片都没有**，中国的形状（如果出现）
#                      完全来自志愿者的位置
#
# 这回答 09-11 报告没回答的一个问题：报告 §2.2 ⑤ 引 deck.gl 的 UK Road Safety
# 「14 万个点画出完整英国轮廓，完全没有底图瓦片」，并据此把方向 A 判为高风险
#（「需要 14 万点才有这个效果」）。但**中国的面积是英国的 40 倍**，到底要多少人才够，
# 报告没量过 —— 它只说了「40 人不够」。
#
# ⚠️ 方向 A 的合规风险是三个方向里最高的（报告第一部分 §1.5：自绘轮廓 = 自己编制地图，
#    2018 年 8 起「问题地图」通报全是自制地图）。但那条针对的是**画国界线**，
#    而点云没有线。两者是不是一回事**没有官方定性** —— 和方向 C 那条「卫星影像算不算地图」
#    一样，是待确认，不是已解决。
#
# 用法：
#   scripts/render-lantern-pointcloud.sh                       # 默认 2000/20000/200000/2000000
#   scripts/render-lantern-pointcloud.sh 500 5000 50000

set -euo pipefail
cd "$(dirname "$0")/.."

DENSITY_SOURCE="blindRun/LanternMap/LanternBasemapChina.jpg"
if [ ! -f "$DENSITY_SOURCE" ]; then
  echo "缺少人口密度采样源。先跑：scripts/crop-lantern-basemap.sh" >&2
  exit 1
fi

SCALES=("$@")
if [ ${#SCALES[@]} -eq 0 ]; then
  SCALES=(2000 20000 200000 2000000)
fi

OUT="${TMPDIR:-/tmp}/lantern-pointcloud.png"

xcrun swift - "$DENSITY_SOURCE" "$OUT" "${SCALES[@]}" <<'SWIFT'
import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 4 else { exit(1) }
let densityPath = args[1]
let outPath = args[2]
let scales = args[3...].compactMap(Int.init)

let WEST = 73.0, EAST = 136.0, SOUTH = 17.0, NORTH = 54.0

// MARK: - 志愿者住在哪
//
// 模拟数据要像真实用户分布，否则量出来的「多少人才够」没有意义。
// 用夜光亮度当人口密度的代理 —— 这是遥感领域的常规做法，亮的地方人多。
//
// 🔑 **那张卫星图只进采样，不进画面。** 最终图上一个像素的照片都没有，
//    这正是方向 A 与方向 C 的分界。
//
// 🚩 **下面这个粗轮廓不是国界，也不上屏。** 它只用来把采样限制在中国境内 ——
//    否则印度和日韩的灯火会被一起采进来（框里最亮的一块本来就不是中国）。
//    真实产品里不需要它：中国境外没有注册用户，分布天然就是境内的。
//    精度只到「几十公里」，写它是为了让模拟数据像真实数据，不是为了画一张地图。
let chinaOutline: [[(Double, Double)]] = [
    // 大陆。顺时针，从漠河起。约 60 个点，误差到几十公里 —— 它只决定「模拟的人撒在哪」，
    // 不决定画面上任何一根线。
    [
        (122.4, 53.5), (127.5, 50.2), (134.8, 48.4), (132.0, 45.0), (131.3, 42.9),
        (128.0, 41.4), (124.4, 40.0), (121.1, 38.7), (118.0, 39.2), (117.8, 38.3),
        (119.2, 37.8), (122.1, 37.4), (120.4, 36.1), (119.4, 34.7), (120.5, 33.4),
        (121.9, 31.2), (121.2, 30.3), (122.2, 29.9), (121.0, 27.9), (119.8, 26.1),
        (118.2, 24.5), (117.0, 23.4), (114.3, 22.2), (111.9, 21.7), (110.2, 20.2),
        (109.1, 21.5), (108.0, 21.6), (106.7, 22.8), (104.8, 22.8), (103.3, 22.6),
        (101.7, 21.2), (100.4, 21.2), (99.0, 22.5), (97.5, 24.0), (97.8, 25.6),
        (98.2, 27.5), (96.5, 28.5), (94.5, 29.2), (91.5, 27.8), (88.8, 27.3),
        (85.0, 28.3), (81.5, 30.4), (78.8, 31.3), (78.0, 35.5), (76.0, 36.0),
        (75.4, 37.0), (73.6, 38.5), (73.9, 40.0), (75.0, 40.5), (78.0, 41.5),
        (80.2, 42.8), (80.4, 44.3), (82.5, 45.2), (85.0, 47.0), (87.8, 49.2),
        (90.0, 47.9), (95.0, 44.3), (100.0, 42.6), (105.0, 41.8), (112.0, 43.7),
        (115.5, 45.4), (119.0, 46.7), (117.8, 49.5), (120.0, 52.0),
    ],
    // 海南岛
    [(108.6, 19.9), (110.6, 20.1), (111.0, 19.6), (110.5, 18.2), (109.1, 18.3), (108.6, 19.3)],
    // 台湾
    [(120.0, 23.0), (121.0, 25.3), (122.0, 25.0), (121.9, 24.0), (120.9, 22.0), (120.2, 22.5)],
]

func insideChina(_ lon: Double, _ lat: Double) -> Bool {
    for ring in chinaOutline {
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let (xi, yi) = ring[i]
            let (xj, yj) = ring[j]
            if (yi > lat) != (yj > lat),
               lon < (xj - xi) * (lat - yi) / (yj - yi) + xi {
                inside.toggle()
            }
            j = i
        }
        if inside { return true }
    }
    return false
}

// MARK: - 读密度源

guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: densityPath) as CFURL, nil),
      let density = CGImageSourceCreateImageAtIndex(src, 0, nil) else { exit(1) }

// 采样网格：比画布粗一点就够，339k 个格子建累积分布是瞬时的
let gw = 760, gh = 446
var gray = [Float](repeating: 0, count: gw * gh)
do {
    var buf = [UInt8](repeating: 0, count: gw * gh * 4)
    guard let c = CGContext(data: &buf, width: gw, height: gh, bitsPerComponent: 8,
                            bytesPerRow: gw * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
    c.draw(density, in: CGRect(x: 0, y: 0, width: gw, height: gh))
    for i in 0..<(gw * gh) {
        // ⚠️ **这里不能做行翻转。** `CGBitmapContext` 的绘图坐标系原点在左下，
        // 但它的**内存布局**第一行就是图像顶部 —— 两者是两回事。
        // 按坐标系直觉去翻行，会让整张密度图上下颠倒：印度的灯火落到新疆的位置上，
        // 表现是「西部比东部还亮」，而那在图上看起来只是「形状怪」，不像 bug。
        let s = i * 4
        let lum = 0.2126 * Float(buf[s]) + 0.7152 * Float(buf[s + 1]) + 0.0722 * Float(buf[s + 2])
        // 🔑 **暗部必须狠狠压掉，否则西部的月照雪地会被当成人。**
        // 夜光影像上青藏高原有一大片淡紫（月光下的雪和云，亮度 30–50），
        // 阈值定低时它会贡献海量采样点 —— 而西部面积占中国一半以上，
        // 结果是整个西半边浮起一层均匀的雾，把真实结构盖掉。
        //
        // 中国的人口分布本来就极度不均（胡焕庸线两侧差一个数量级），
        // 压到 35/2.2 之后西部只剩下乌鲁木齐、拉萨、西宁这几个真实城市 ——
        // **那才是志愿者点出来的中国该有的样子**：东部连成片，西部几粒孤灯。
        // 45 这个阈值是量出来的：青藏高原的月照雪地落在 40–60，小城镇也在 60–100 ——
        // 两者重叠，所以压到 45 会同时损失一部分真实小城镇。这是刻意的取舍：
        // 留着雾比丢几个小城镇更糟（雾会让整个西部假装有人，而那正是报告否掉方向 A 的理由）。
        let cleaned = max(0, lum - 45) / 210
        gray[i] = pow(cleaned, 1.6)
    }
}

// 掩码。**边界必须软化**，否则那条粗轮廓的直边会直接出现在画面上 ——
// 一张本该「由人点出来」的图，边上却有几条笔直的线，那是最刺眼的假。
// 真实的人口分布在边境也是渐变的（越靠边境人越少），软化同时更像真的。
//
// 做法：0/1 掩码跑两遍 box blur（各 4px）。够软到看不出直边，又不至于把形状一起糊掉。
// 而且这里只要「边上糊掉」不要精确核形。
var mask = [Float](repeating: 0, count: gw * gh)
for i in 0..<(gw * gh) {
    let col = i % gw, row = i / gw
    let lon = WEST + (Double(col) + 0.5) / Double(gw) * (EAST - WEST)
    let lat = NORTH - (Double(row) + 0.5) / Double(gh) * (NORTH - SOUTH)
    mask[i] = insideChina(lon, lat) ? 1 : 0
}
for _ in 0..<2 {
    var tmp = [Float](repeating: 0, count: gw * gh)
    let r = 4
    for row in 0..<gh {
        for col in 0..<gw {
            var sum: Float = 0, n: Float = 0
            for d in -r...r {
                let c = col + d
                guard c >= 0, c < gw else { continue }
                sum += mask[row * gw + c]; n += 1
            }
            tmp[row * gw + col] = sum / n
        }
    }
    for col in 0..<gw {
        for row in 0..<gh {
            var sum: Float = 0, n: Float = 0
            for d in -r...r {
                let rr = row + d
                guard rr >= 0, rr < gh else { continue }
                sum += tmp[rr * gw + col]; n += 1
            }
            mask[row * gw + col] = sum / n
        }
    }
}

var cdf = [Double](repeating: 0, count: gw * gh)
var running = 0.0
for i in 0..<(gw * gh) {
    running += Double(gray[i] * mask[i])
    cdf[i] = running
}
guard running > 0 else {
    FileHandle.standardError.write("密度全为 0\n".data(using: .utf8)!)
    exit(1)
}

struct Rng {
    var state: UInt64
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 11) & 0xFFFFFFFF) / Double(0xFFFFFFFF)
    }
}

/// 二分找第一个 cdf >= target 的格子
func sampleCell(_ target: Double) -> Int {
    var lo = 0, hi = cdf.count - 1
    while lo < hi {
        let mid = (lo + hi) / 2
        if cdf[mid] < target { lo = mid + 1 } else { hi = mid }
    }
    return lo
}

// MARK: - 渲染
//
// 不用 CoreGraphics 逐点画渐变 —— 两百万个点那样画要几分钟。
// 改成往一个能量缓冲里累加，最后一次性 tone-map。这也更接近「光」的物理：
// 一盏灯的能量叠在另一盏上，亮度是加出来的，不是画上去的。

let cellW = 760, cellH = 446
let labelH = 44
let cols = scales.count >= 4 ? 2 : scales.count
let rows = Int(ceil(Double(scales.count) / Double(cols)))
let totalW = cellW * cols
let totalH = (cellH + labelH) * rows

var canvas = [Float](repeating: 0, count: totalW * totalH * 3)

// 一盏灯的能量核。**不随人数变大** —— 方向 A 的前提就是「一个人一盏灯」，
// 灯的大小是常数，画面的丰满度只由人数决定。
//
// `LANTERN_SHAPE=star`（默认）在高斯芯之外加四道衍射尖峰，让单点在小规模下
// 真的像一颗星而不是一个光斑。🔑 **这只在几百人以下看得出来** ——
// 两万人以上点会互相重叠，星芒糊成一片，那时 `dot` 和 `star` 没有区别。
// 而几百人正是 AidRun 现在的量级，所以这个细节在当下比在未来重要。
let shape = ProcessInfo.processInfo.environment["LANTERN_SHAPE"] ?? "star"

let kernel: [(Int, Int, Float)] = {
    var k: [(Int, Int, Float)] = []
    let sigma: Float = 0.9
    let reach = shape == "star" ? 5 : 2
    for dy in -reach...reach {
        for dx in -reach...reach {
            let d2 = Float(dx * dx + dy * dy)
            var w = exp(-d2 / (2 * sigma * sigma))
            if shape == "star" {
                // 四道尖峰（上下左右）+ 弱一些的对角 —— 相机拍星点的衍射十字。
                // 纯十字太像"加号"，配上对角线才像星。
                if dx == 0 || dy == 0 {
                    w += 0.42 * exp(-Float(abs(dx) + abs(dy)) / 1.9)
                }
                if abs(dx) == abs(dy) {
                    w += 0.16 * exp(-Float(abs(dx)) / 1.5)
                }
            }
            if w > 0.012 { k.append((dx, dy, w)) }
        }
    }
    return k
}()

// 调色板。`LANTERN_PALETTE=cyan` 切回报告 §3 维度 6 定的冷青。
//
// 🔑 **默认改成暖金，因为定冷青的那个理由在方向 A 下不成立了。**
// 报告要冷青是为了「与底层暖橙灯火形成最大对比」—— 而方向 A 没有底图，
// 没有要对比的东西。「万家灯火」本来就是暖的，冷青反而是数据大屏的语气。
let warmPalette = (ProcessInfo.processInfo.environment["LANTERN_PALETTE"] ?? "gold") != "cyan"
//                        孤灯的色                     灯海的色（叠加后趋近）
let glowRGB: (Float, Float, Float) = warmPalette ? (1.00, 0.72, 0.28) : (0.25, 0.83, 0.78)
let coreRGB: (Float, Float, Float) = warmPalette ? (1.00, 0.97, 0.86) : (0.75, 1.00, 0.98)

for (index, total) in scales.enumerated() {
    let col = index % cols, row = index / cols
    let ox = col * cellW
    let oy = row * (cellH + labelH)

    var energy = [Float](repeating: 0, count: cellW * cellH)
    var rng = Rng(state: 0x5EED_1A47)
    for _ in 0..<total {
        let cell = sampleCell(rng.next() * running)
        // 在格子内抖动，否则点会排成规则网格
        let px = Double(cell % gw) + rng.next()
        let py = Double(cell / gw) + rng.next()
        let x = Int(px / Double(gw) * Double(cellW))
        let y = Int(py / Double(gh) * Double(cellH))
        for (dx, dy, w) in kernel {
            let nx = x + dx, ny = y + dy
            guard nx >= 0, nx < cellW, ny >= 0, ny < cellH else { continue }
            energy[ny * cellW + nx] += w
        }
    }

    // tone map。**固定曲线，不按格归一化。**
    //
    // 🔴 上一版按每格的 99.5 分位归一化，结果四档图长得几乎一模一样 ——
    // 把唯一要看的东西（规模差异）亲手抹平了。
    //
    // 🔑 正确的想法是：**规模差异不该体现在"单点多亮"，而该体现在"多少地方亮了"**。
    // 一盏灯永远是一盏灯的亮度（`e=1` → 0.55，看得见但不刺眼），
    // 叠到三四盏才接近白。于是 2000 人是黑底上的一把散点，200 万人是连成片的光海 ——
    // 这正是它真实的样子，不需要任何曲线去"表达"。
    for i in 0..<(cellW * cellH) {
        let e = energy[i]
        guard e > 0 else { continue }
        let v = 1 - exp(-0.55 * e)
        // 芯变白比整体变亮慢得多 —— 一盏孤灯是冷青的，一片灯海才发白
        let warmth = 1 - exp(-0.12 * e)
        let r = v * (glowRGB.0 + (coreRGB.0 - glowRGB.0) * warmth)
        let g = v * (glowRGB.1 + (coreRGB.1 - glowRGB.1) * warmth)
        let b = v * (glowRGB.2 + (coreRGB.2 - glowRGB.2) * warmth)
        let cx = ox + i % cellW
        let cy = oy + labelH + i / cellW
        let o = (cy * totalW + cx) * 3
        canvas[o] = r; canvas[o + 1] = g; canvas[o + 2] = b
    }
}

// 写出
var pixels = [UInt8](repeating: 0, count: totalW * totalH * 4)
for i in 0..<(totalW * totalH) {
    // 底色 #0A0E17
    let br: Float = 0.039, bg: Float = 0.055, bb: Float = 0.090
    let r = max(canvas[i * 3], br), g = max(canvas[i * 3 + 1], bg), b = max(canvas[i * 3 + 2], bb)
    pixels[i * 4] = UInt8(min(255, r * 255))
    pixels[i * 4 + 1] = UInt8(min(255, g * 255))
    pixels[i * 4 + 2] = UInt8(min(255, b * 255))
    pixels[i * 4 + 3] = 255
}

guard let ctx = CGContext(data: &pixels, width: totalW, height: totalH, bitsPerComponent: 8,
                          bytesPerRow: totalW * 4, space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }

// 标签（CoreGraphics 原点左下 ⇒ y 要翻）
for (index, total) in scales.enumerated() {
    let col = index % cols, row = index / cols
    let x = Double(col * cellW) + 18
    let y = Double(totalH - (row + 1) * (cellH + labelH)) + 12
    let pretty = total >= 10000 ? "\(total / 10000) 万" : "\(total)"
    let font = CTFontCreateUIFontForLanguage(.system, 26, "zh-Hans" as CFString)
        ?? CTFontCreateWithName("Helvetica" as CFString, 26, nil)
    let attr = NSAttributedString(string: "\(pretty) 位志愿者", attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String):
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.95),
    ])
    ctx.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(CTLineCreateWithAttributedString(attr), ctx)
}

guard let img = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: outPath) as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    exit(1)
}
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("纯点云（无底图）→ \(outPath) (\(totalW)×\(totalH))")
SWIFT
