#!/usr/bin/env bash
# 检查 .app 里每个 Mach-O（主程序、Frameworks/*、PlugIns/*.appex）不含 x86_64 / i386。
#   scripts/check-app-archs.sh path/to/blindRun.app
#
# 为什么：Vendor/AliyunCloudAuth 的 10 个 .framework 是 `x86_64 arm64` 胖包，混进 Frameworks/ 会被
# 上传校验拒（ITMS-90087 / 90209 一类）。2026-09-30 实测：它们是**静态库**（`ar archive`），
# 链接时只取 arm64 切片进主二进制、不会被嵌入 Frameworks/，所以当前 archive 是干净的；
# 这道检查防的是以后有人把它改成动态库，或加了别的胖 dylib。
# 放行 arm64e：Swift 兼容 dylib（libswiftCompatibilitySpan）就是 `arm64 arm64e`。
set -euo pipefail

APP="${1:?用法：$0 <path/to/App.app>}"
[[ -d "$APP" ]] || { echo "❌ 找不到 $APP" >&2; exit 2; }

checked=0
bad=0
while IFS= read -r -d '' f; do
  file -b "$f" | grep -q 'Mach-O' || continue
  archs="$(lipo -archs "$f")"
  checked=$((checked + 1))
  echo "  ${f#"$APP"/}: $archs"
  if [[ " $archs " == *" x86_64 "* || " $archs " == *" i386 "* ]]; then
    echo "❌ ${f#"$APP"/} 含模拟器/Intel 架构（${archs}）" >&2
    bad=$((bad + 1))
  fi
done < <(find "$APP" -type f -print0)

[[ $checked -gt 0 ]] || { echo "❌ $APP 里一个 Mach-O 都没找到，检查本身失效" >&2; exit 2; }
[[ $bad -eq 0 ]] || { echo "❌ $bad 个二进制含 x86_64/i386，上传会被拒。修法：动态库改成静态链接，或用 lipo -remove x86_64 / build phase 剥掉再打包" >&2; exit 1; }
echo "✅ $checked 个 Mach-O 均无 x86_64/i386"
