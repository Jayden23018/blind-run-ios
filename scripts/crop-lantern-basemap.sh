#!/bin/bash
# 「一束光地图」原型的夜光底图素材生成。
#
# 从 NASA "Earth at Night" (Black Marble) 全球图裁出 LanternMap.GeoBounds.china 那一块。
#
# 🔴 裁图范围必须和 blindRun/LanternMap/LanternMap.swift 的 GeoBounds.china 逐字一致 ——
#    不一致时光点会整体离开灯火，而那在画面上不像 bug，像「数据不准」，没人会去怀疑这两处。
#
# 素材版权（NASA Images and Media Usage，逐字）：
#   "NASA content … generally are not subject to copyright in the United States."
#   使用条件两条：① 必须注明来源 ② 不得暗示 NASA 为我们背书；NASA 徽标不得使用。
#   署名已落在 LanternMapView 的页脚。
#
# 产物不进 git（约 1–2MB，且随时可重新生成）。换机器 / 新 worktree 要重跑一次。

set -euo pipefail

cd "$(dirname "$0")/.."

SOURCE_URL="https://assets.science.nasa.gov/content/dam/science/esd/eo/images/imagerecords/144000/144898/BlackMarble_2016_3km.jpg"
CACHE="${TMPDIR:-/tmp}/BlackMarble_2016_3km.jpg"
OUT="blindRun/LanternMap/LanternBasemapChina.jpg"

# 全球图是等距圆柱投影，13500×6750 覆盖 经度 -180..180 / 纬度 90..-90 ⇒ 每度 37.5px。
# 下面四个数来自 GeoBounds.china = (west 73, east 136, south 17, north 54)。
PX_PER_DEGREE=37.5
WEST=73; EAST=136; SOUTH=17; NORTH=54

CROP_X=$(python3 -c "print(round(($WEST + 180) * $PX_PER_DEGREE))")
CROP_Y=$(python3 -c "print(round((90 - $NORTH) * $PX_PER_DEGREE))")
CROP_W=$(python3 -c "print(round(($EAST - $WEST) * $PX_PER_DEGREE))")
CROP_H=$(python3 -c "print(round(($NORTH - $SOUTH) * $PX_PER_DEGREE))")

if [ ! -f "$CACHE" ]; then
  echo "下载 NASA 全球夜光图（约 8.1 MB）…"
  curl -fL --retry 3 -o "$CACHE" "$SOURCE_URL"
else
  echo "复用缓存：$CACHE"
fi

mkdir -p "$(dirname "$OUT")"

# 用 CoreGraphics 裁 —— macOS 自带，零依赖。
# 不用 sips：它的 --cropOffset 语义在不同 macOS 版本上不一致，而裁错一个像素
# 就是光点整体偏移，偏移本身不会报错。
# 经纬度也传进去（校验图要用）——**不在 Swift 段里再写一份**，
# 那就成了第三份常量源（另两份：本文件上面那四行、LanternMap.GeoBounds.china）。
xcrun swift - "$CACHE" "$OUT" "$CROP_X" "$CROP_Y" "$CROP_W" "$CROP_H" \
    "$WEST" "$EAST" "$SOUTH" "$NORTH" <<'SWIFT'
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 11,
      let x = Int(args[3]), let y = Int(args[4]),
      let w = Int(args[5]), let h = Int(args[6]),
      let west = Double(args[7]), let east = Double(args[8]),
      let south = Double(args[9]), let north = Double(args[10]) else {
    FileHandle.standardError.write("参数不对\n".data(using: .utf8)!)
    exit(1)
}

let inURL = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])

guard let source = CGImageSourceCreateWithURL(inURL as CFURL, nil),
      let full = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write("读不出源图\n".data(using: .utf8)!)
    exit(1)
}

// 源图分辨率若不是 13500×6750（NASA 换了文件），像素换算就全错了 —— 当场失败，不要静默裁一块错的。
guard full.width == 13500, full.height == 6750 else {
    FileHandle.standardError.write(
        "源图是 \(full.width)×\(full.height)，预期 13500×6750。NASA 可能换了文件，重算 PX_PER_DEGREE 再跑。\n"
            .data(using: .utf8)!)
    exit(1)
}

guard let cropped = full.cropping(to: CGRect(x: x, y: y, width: w, height: h)) else {
    FileHandle.standardError.write("裁剪失败\n".data(using: .utf8)!)
    exit(1)
}

guard let dest = CGImageDestinationCreateWithURL(
    outURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
    FileHandle.standardError.write("写不出目标文件\n".data(using: .utf8)!)
    exit(1)
}
CGImageDestinationAddImage(dest, cropped, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
guard CGImageDestinationFinalize(dest) else {
    FileHandle.standardError.write("编码失败\n".data(using: .utf8)!)
    exit(1)
}
print("已裁出 \(cropped.width)×\(cropped.height) → \(outURL.path)")

// MARK: - 对齐校验图
//
// 裁剪偏移算错时，光点会整体离开灯火 —— 而那在画面上**不像 bug，像「数据不准」**，
// 没人会去怀疑这两处常量不同步。单测钉不住这一层：它验的是代码内部一致性
// （`LanternMapTests.testProjectionPinsTheFourCornersOfTheBasemap`），
// 而这里要验的是**这个脚本裁出来的像素**和那些常量对不对得上。
//
// 所以每次重裁都自动产出一张证据图：八个已知城市的圈应当各自落在对应的灯火亮斑上。
// 校验点是独立选的（不读 `sampleSites`）—— 它们验的是投影，不是那份假数据。

let probes: [(String, Double, Double)] = [
    ("北京", 116.5, 39.9), ("上海", 121.5, 31.2), ("广州", 113.4, 23.1),
    ("成都", 104.1, 30.7), ("哈尔滨", 126.6, 45.8), ("乌鲁木齐", 87.6, 43.8),
    ("拉萨", 91.1, 29.7), ("西宁", 101.8, 36.6),
]

let checkW = 1000
let checkH = Int(Double(checkW) / Double(cropped.width) * Double(cropped.height))
if let ctx = CGContext(
    data: nil, width: checkW, height: checkH, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) {
    ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: checkW, height: checkH))
    ctx.setStrokeColor(CGColor(red: 1, green: 0.2, blue: 0.2, alpha: 1))
    ctx.setLineWidth(2)
    for (_, lon, lat) in probes {
        // 归一化用的是左上原点（同 `LanternMap.normalizedPoint`），
        // 而 CoreGraphics 原点在左下 ⇒ y 要翻回来。写反了图上一切正常、只是南北颠倒。
        let nx = (lon - west) / (east - west)
        let ny = (north - lat) / (north - south)
        let px = nx * Double(checkW)
        let py = (1 - ny) * Double(checkH)
        ctx.strokeEllipse(in: CGRect(x: px - 9, y: py - 9, width: 18, height: 18))
    }
    let checkURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("lantern-projection-check.png")
    if let checkImage = ctx.makeImage(),
       let checkDest = CGImageDestinationCreateWithURL(
        checkURL as CFURL, UTType.png.identifier as CFString, 1, nil) {
        CGImageDestinationAddImage(checkDest, checkImage, nil)
        if CGImageDestinationFinalize(checkDest) {
            print("对齐校验图 → \(checkURL.path)")
            print("  打开看一眼：八个红圈应当各自落在一团灯火上。拉萨那个圈里没有光是**预期的**")
            print("  —— 夜光图上西藏几乎全黑，这正是 09-11 报告 §5 第 1 条要产品方回答的问题。")
        }
    }
}
SWIFT

ls -lh "$OUT"
