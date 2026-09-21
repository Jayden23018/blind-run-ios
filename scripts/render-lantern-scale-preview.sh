#!/bin/bash
# 「一束光地图」规模对比预览 —— 回答「多少人的时候这张图才成立」。
#
# 这是 09-11 报告里**唯一能证伪整个功能**的问题：第一部分实测「40 个用户散在中国地图上，
# 传达的是『原来只有这么几个人』」，而方向 C 被选中的全部理由就是「夜光底图让画面的丰满度
# 不再由用户数决定」。那条论断到目前为止**只在文字里成立过**。
#
# ⚠️ **这是离线预览，不是真机效果。** 辉光参数照抄 LanternMapView（双层结构、
#    4.2r 光晕 / 0.6r 芯、plusLighter 叠加），但它是脚本里的第二份数值 ——
#    两边漂移时**以真机为准**。这个脚本的用途是产品决策，不是像素验收。
#
# 用法：
#   scripts/render-lantern-scale-preview.sh              # 默认 40 / 200 / 1000 / 5000
#   scripts/render-lantern-scale-preview.sh 40 10000     # 自己指定
#
# 前置：先跑 scripts/crop-lantern-basemap.sh 拿到底图。

set -euo pipefail
cd "$(dirname "$0")/.."

BASEMAP="blindRun/LanternMap/LanternBasemapChina.jpg"
if [ ! -f "$BASEMAP" ]; then
  echo "没有底图。先跑：scripts/crop-lantern-basemap.sh" >&2
  exit 1
fi

SCALES=("$@")
if [ ${#SCALES[@]} -eq 0 ]; then
  SCALES=(40 200 1000 5000)
fi

OUT="${TMPDIR:-/tmp}/lantern-scale-preview.png"

xcrun swift - "$BASEMAP" "$OUT" "${SCALES[@]}" <<'SWIFT'
import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 4 else { exit(1) }
let basemapPath = args[1]
let outPath = args[2]
let scales = args[3...].compactMap(Int.init)

// MARK: - 与 LanternMap.GeoBounds.china 一致
let WEST = 73.0, EAST = 136.0, SOUTH = 17.0, NORTH = 54.0

// MARK: - 种子：LanternMap.sampleSites 的前 24 条（省·区县 → 经纬度 + 相对权重）
//
// 规模变化不能只是「把每个点的数字乘以 10」—— 那样光点个数不变，看不出任何东西。
// 真实情况是：人多了之后**亮起来的地方也变多了**（周边区县陆续出现第一个志愿者）。
// 所以下面按权重抽样出一个个「人」，每个人在种子附近抖动，再按 0.25°（≈25km，区县尺度）
// 网格聚回光点。40 人时只有十几个格子亮，5000 人时几百个格子亮 —— 这才是规模的真实形状。
let seeds: [(Double, Double, Double)] = [
    (116.5, 39.9, 37), (116.3, 40.0, 29), (116.4, 39.9, 14), (117.2, 39.1, 11),
    (114.5, 38.0, 6), (121.4, 31.2, 33), (121.5, 31.2, 41), (121.5, 31.2, 18),
    (118.8, 32.1, 16), (120.6, 31.3, 12), (120.1, 30.3, 22), (121.5, 29.9, 8),
    (113.4, 23.1, 27), (113.9, 22.5, 31), (114.1, 22.5, 19), (114.3, 30.5, 17),
    (112.9, 28.2, 9), (104.1, 30.7, 21), (106.6, 29.6, 13), (108.9, 34.2, 15),
    (106.7, 26.6, 5), (123.4, 41.8, 10), (126.6, 45.8, 7), (87.6, 43.8, 5),
    (91.1, 29.7, 3), (101.8, 36.6, 2),
]

/// 固定种子的线性同余 —— 每次跑出同一张图，否则两次对比看到的差异分不清是规模还是随机。
struct Rng {
    var state: UInt64
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 11) & 0xFFFFFFFF) / Double(0xFFFFFFFF)
    }
    /// Box-Muller，用来做种子周围的抖动。
    mutating func gaussian() -> Double {
        let u1 = max(next(), 1e-9), u2 = next()
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}

/// 抽 `total` 个「人」，落回 0.25° 网格。返回每个亮起来的格子 (lon, lat, 人数)。
/// 聚合网格（度）。默认 0.25° ≈ 25km ≈ 区县尺度。
///
/// 🔑 **这个数和光晕半径是一对，不能各调各的。** 全国视图下 390pt 宽承载 63 个经度
/// ⇒ 6.19 pt/度；而一盏灯的光晕直径约 8.4r ≈ 22pt ⇒ 相邻光点要不重叠，网格至少 3.5°。
/// 也就是说 0.25° 的区县粒度在全国视图下**必然糊成一团**，这不是画法问题，是粒度问题。
let grid = ProcessInfo.processInfo.environment["LANTERN_GRID"].flatMap(Double.init) ?? 0.25

func lanterns(total: Int) -> [(Double, Double, Int)] {
    var rng = Rng(state: 0x5EED_1A47)
    let weightSum = seeds.reduce(0) { $0 + $1.2 }

    // 人越多，越往周边区县扩散：40 人时都还挤在市中心，5000 人时周边区县陆续有人。
    // 0.18° ≈ 18km，0.9° ≈ 90km —— 前者是市区尺度，后者是都市圈尺度。
    let spread = 0.18 + 0.72 * min(1.0, log(Double(max(total, 1))) / log(20000))

    var buckets: [String: (Double, Double, Int)] = [:]
    for _ in 0..<total {
        // 按权重挑一个种子
        var pick = rng.next() * weightSum
        var chosen = seeds[0]
        for s in seeds {
            pick -= s.2
            if pick <= 0 { chosen = s; break }
        }
        let lon = chosen.0 + rng.gaussian() * spread
        let lat = chosen.1 + rng.gaussian() * spread * 0.8  // 纬度方向压一点，贴合平原走向
        guard lon > WEST, lon < EAST, lat > SOUTH, lat < NORTH else { continue }

        let gx = (lon / grid).rounded(.down), gy = (lat / grid).rounded(.down)
        let key = "\(gx),\(gy)"
        if let old = buckets[key] {
            buckets[key] = (old.0, old.1, old.2 + 1)
        } else {
            buckets[key] = (lon, lat, 1)
        }
    }
    return Array(buckets.values)
}

// MARK: - 渲染（辉光参数照抄 LanternMapView）

/// LanternMapView.radius(forCount:)
///
/// `LANTERN_RADIUS_CAP` 给半径封顶（单位 pt），用来验证一件事：
/// 大规模下画面糊成白团，是**半径随人数一路涨**造成的，还是方向 C 本身不成立。
/// 报告 §4.3 引用 Stellarium 的教训原话是「密集处靠叠加自然变亮，而不是把单点调亮」——
/// 而光晕半径 = 4.2r，r 又随人数涨，等于恰好在做它反对的事。
let radiusCap = ProcessInfo.processInfo.environment["LANTERN_RADIUS_CAP"].flatMap(Double.init)
    ?? Double.infinity
func radius(_ count: Int) -> Double { min(2.0 + Double(count).squareRoot() * 0.7, radiusCap) }

let cellW = 760.0
let cellH = cellW / ((EAST - WEST) / (NORTH - SOUTH))
let labelH = 44.0
let cols = scales.count >= 4 ? 2 : scales.count
let rows = Int(ceil(Double(scales.count) / Double(cols)))
let totalW = cellW * Double(cols)
let totalH = (cellH + labelH) * Double(rows)

// 真机上地图区宽约 390pt，这里 760px ⇒ 辉光半径按这个系数放大，否则看到的不是真机的比例
let ptToPx = cellW / 390.0

guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: basemapPath) as CFURL, nil),
      let basemap = CGImageSourceCreateImageAtIndex(src, 0, nil),
      let ctx = CGContext(data: nil, width: Int(totalW), height: Int(totalH),
                          bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    FileHandle.standardError.write("初始化失败\n".data(using: .utf8)!)
    exit(1)
}

// #0A0E17，LanternMapView.canvasColor
ctx.setFillColor(CGColor(red: 0.039, green: 0.055, blue: 0.090, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: totalW, height: totalH))

let glow = CGColor(red: 0.25, green: 0.83, blue: 0.78, alpha: 1)   // #3FD3C6
let core = CGColor(red: 0.75, green: 1.00, blue: 0.98, alpha: 1)

for (index, total) in scales.enumerated() {
    let col = index % cols, row = index / cols
    let originX = Double(col) * cellW
    // CoreGraphics 原点左下 ⇒ 行号要翻过来
    let originY = totalH - Double(row + 1) * (cellH + labelH)

    ctx.saveGState()
    ctx.clip(to: CGRect(x: originX, y: originY + labelH, width: cellW, height: cellH))
    ctx.draw(basemap, in: CGRect(x: originX, y: originY + labelH, width: cellW, height: cellH))

    let points = lanterns(total: total)
    ctx.setBlendMode(.plusLighter)
    for (lon, lat, count) in points {
        let nx = (lon - WEST) / (EAST - WEST)
        let ny = (NORTH - lat) / (NORTH - SOUTH)
        let px = originX + nx * cellW
        let py = originY + labelH + (1 - ny) * cellH
        let r = radius(count) * ptToPx

        // 双层辉光：宽而暗的底 + 窄而亮的芯（LanternMapView.lanternLayer）
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: [glow.copy(alpha: 0.28)!, glow.copy(alpha: 0)!] as CFArray,
                                 locations: [0, 1]) {
            ctx.drawRadialGradient(grad, startCenter: CGPoint(x: px, y: py), startRadius: 0,
                                   endCenter: CGPoint(x: px, y: py), endRadius: r * 4.2,
                                   options: [])
        }
        ctx.setFillColor(core)
        ctx.fillEllipse(in: CGRect(x: px - r * 0.6, y: py - r * 0.6, width: r * 1.2, height: r * 1.2))
    }
    ctx.setBlendMode(.normal)
    ctx.restoreGState()

    // 标签
    let text = "\(total) 位志愿者 · \(points.count) 处亮起"
    let font = CTFontCreateUIFontForLanguage(.system, 24, "zh-Hans" as CFString)
        ?? CTFontCreateWithName("Helvetica" as CFString, 24, nil)
    // 只 import 了 Foundation/CoreText（没有 AppKit/UIKit），所以用 CoreText 的 key，
    // 不是 `.font` / `.foregroundColor` 那两个 —— 后者来自 UI 框架。
    let attr = NSAttributedString(string: text, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String):
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.92),
    ])
    let line = CTLineCreateWithAttributedString(attr)
    ctx.textPosition = CGPoint(x: originX + 18, y: originY + 12)
    CTLineDraw(line, ctx)
}

guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: outPath) as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    exit(1)
}
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("规模对比图 → \(outPath) (\(Int(totalW))×\(Int(totalH)))")
for total in scales {
    print("  \(total) 位 → \(lanterns(total: total).count) 处亮起")
}
SWIFT
