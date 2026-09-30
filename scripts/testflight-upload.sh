#!/usr/bin/env bash
# 打 Release 包并上传 App Store Connect（TestFlight）。拿到付费开发者账号后一条命令走完。
#
#   scripts/testflight-upload.sh --dry-run          # 无账号可跑：无签名 archive + 产物检查，不上传
#   TEAM_ID=XXXXXXXXXX scripts/testflight-upload.sh # 签名 archive + 产物检查 + 上传
#
# 认证：默认用 Xcode → Settings → Accounts 里登录的账号。无头机器改传 App Store Connect API key：
#   ASC_KEY_PATH=/path/AuthKey_XXXX.p8 ASC_KEY_ID=XXXX ASC_ISSUER_ID=xxxxxxxx-...
#
# 为什么要有：三件事在 Debug 真机调试里都看不出来，只在送审包上暴露（2026-09-27 核实，
# 见 docs/review/testflight-readiness-20260927.md）——
#   1. 高德 key 是占位值 → 地图/定位/检索 SDK 全部失效（本机 LocalConfig 一直是 CHANGE_ME）
#   2. 没有 aps-environment → 离线推送（含求助相关的 time-sensitive 通知）静默失效
#   3. build 号取提交数，从不在 main 线上的提交打包 → 之后 main 上的包号可能更小，上传被拒
# scheme 固定 blindRun-Prod：DemoRelease 带 UI 测试钩子（`#if DEBUG || DEMO`），不该进送审包。
set -euo pipefail

cd "$(dirname "$0")/.."

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

OUT="${OUT_DIR:-build/testflight}"
ARCHIVE="${OUT}/AidRun.xcarchive"

fail() { echo "❌ $*" >&2; exit 1; }

# ── 1. 前置 ─────────────────────────────────────────────
if [[ $DRY_RUN -eq 0 ]]; then
  [[ -n "${TEAM_ID:-}" ]] || fail "缺 TEAM_ID（付费账号的 Team ID，developer.apple.com → Membership）"
  [[ -z "$(git status --porcelain)" ]] || fail "工作区不干净：送审包必须对应一个确定的提交"
  git fetch -q origin main
  git merge-base --is-ancestor HEAD origin/main \
    || fail "HEAD 不在 origin/main 线上：build 号取提交数，从旁支打包会让之后 main 上的包号回退"
fi

AUTH_ARGS=()
if [[ -n "${ASC_KEY_PATH:-}" ]]; then
  AUTH_ARGS=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

if [[ $DRY_RUN -eq 1 ]]; then
  SIGN_ARGS=(CODE_SIGNING_ALLOWED=NO)
else
  SIGN_ARGS=(DEVELOPMENT_TEAM="$TEAM_ID" -allowProvisioningUpdates ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"})
fi

# ── 2. archive ──────────────────────────────────────────
rm -rf "$ARCHIVE"
mkdir -p "$OUT"
echo "▶ archive（日志 $OUT/archive.log）"
set +e
xcodebuild -workspace blindRun.xcworkspace -scheme blindRun-Prod -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" "${SIGN_ARGS[@]}" archive \
  > "$OUT/archive.log" 2>&1
rc=$?
set -e
tail -n 3 "$OUT/archive.log"
[[ $rc -eq 0 ]] || fail "archive 失败（rc=$rc），看 $OUT/archive.log"

# ── 3. 产物检查 ─────────────────────────────────────────
APP="$ARCHIVE/Products/Applications/blindRun.app"
WIDGET="$APP/PlugIns/blindRunWidget.appex"
pl() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Info.plist" 2>/dev/null || true; }

amap="$(pl "$APP" AMapApiKey)"
if [[ -z "$amap" || "$amap" == *CHANGE_ME* || "$amap" == YOUR_* || "$amap" == *'$('* ]]; then
  fail "包里的高德 key 是占位值「${amap}」。去 console.amap.com 按 Bundle ID $(pl "$APP" CFBundleIdentifier) 申请 iOS key，填进 LocalConfig.xcconfig 的 AMAP_API_KEY"
fi

build="$(pl "$APP" CFBundleVersion)"
[[ "$build" == "$(pl "$WIDGET" CFBundleVersion)" ]] || fail "App 与 Widget 的 CFBundleVersion 不一致，上传校验会拒"
echo "✅ $(pl "$APP" CFBundleIdentifier) $(pl "$APP" CFBundleShortVersionString) ($build)，高德 key 已配置"

if [[ $DRY_RUN -eq 1 ]]; then
  echo "（dry-run：无签名，跳过推送 entitlement 检查与上传）"
  exit 0
fi

if ! codesign -d --entitlements - "$APP" 2>/dev/null | grep -q aps-environment; then
  [[ "${SKIP_PUSH_CHECK:-0}" == "1" ]] \
    || fail "签名产物里没有 aps-environment：Xcode → blindRun target → Signing & Capabilities → + Push Notifications（确认要发一个没有离线推送的包，传 SKIP_PUSH_CHECK=1）"
fi

# ── 4. 导出并上传 ───────────────────────────────────────
# manageAppVersionAndBuildNumber 默认 YES 会覆盖 set-build-number.sh 算好的号，必须关。
cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>${TEAM_ID}</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
EOF

echo "▶ 上传 App Store Connect（日志 $OUT/export.log）"
set +e
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -exportPath "$OUT/export" -allowProvisioningUpdates ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"} \
  > "$OUT/export.log" 2>&1
rc=$?
set -e
tail -n 5 "$OUT/export.log"
[[ $rc -eq 0 ]] || fail "上传失败（rc=$rc），看 $OUT/export.log"
echo "✅ build $build 已上传。约 10–30 分钟后出现在 App Store Connect → TestFlight，处理完才能加进测试组"
