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
xcrun swift - "$CACHE" "$OUT" "$CROP_X" "$CROP_Y" "$CROP_W" "$CROP_H" <<'SWIFT'
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 7,
      let x = Int(args[3]), let y = Int(args[4]),
      let w = Int(args[5]), let h = Int(args[6]) else {
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
SWIFT

ls -lh "$OUT"
