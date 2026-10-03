#!/usr/bin/env bash
# 打 Release 包并上传 App Store Connect（TestFlight）。拿到付费开发者账号后一条命令走完。
#
#   scripts/testflight-upload.sh --dry-run          # 无账号可跑：无签名 archive + 产物检查，不上传
#   TEAM_ID=XXXXXXXXXX scripts/testflight-upload.sh # 签名 archive + 产物检查 + 上传
#
# 认证：默认用 Xcode → Settings → Accounts 里登录的账号。无头机器改传 App Store Connect API key：
#   ASC_KEY_PATH=/path/AuthKey_XXXX.p8 ASC_KEY_ID=XXXX ASC_ISSUER_ID=xxxxxxxx-...
#
# 手动签名（本人进不了 developer.apple.com、Xcode 自动签名拿不到描述文件时用）：
#   TEAM_ID=XXXXXXXXXX PROFILE_APP="<主 App 的 App Store 描述文件名>" PROFILE_WIDGET="<Widget 的>" \
#     scripts/testflight-upload.sh
#   名字是 .mobileprovision 里的 Name（Xcode → Settings → Accounts → Download Manual Profiles 后可见）。
#   两个都传才启用；钥匙串里须已有 "Apple Distribution" 证书（P12 导入）。
#
# 为什么要有：四件事在 Debug 真机调试里都看不出来，只在送审包上暴露（2026-09-27 核实，
# 见 docs/review/testflight-readiness-20260927.md）——
#   1. 高德 key 是占位值 → 地图/定位/检索 SDK 全部失效（本机 LocalConfig 一直是 CHANGE_ME）
#   2. 没有 aps-environment → 离线推送（含求助相关的 time-sensitive 通知）静默失效
#   3. build 号取提交数，从不在 main 线上的提交打包 → 之后 main 上的包号可能更小，上传被拒
#   4. 产物里混进 x86_64 切片（胖 dylib）→ 上传被拒；由 scripts/check-app-archs.sh 逐个 Mach-O 查
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
  # pbxproj 里的 DEVELOPMENT_TEAM 不是本人团队，免费个人团队又不能上 TestFlight，所以不给默认值。
  [[ -n "${TEAM_ID:-}" ]] || fail "缺 TEAM_ID：须传**付费** Apple Developer Program 的 Team ID（developer.apple.com → Membership）。免费个人团队不能上传 TestFlight；pbxproj 里的 DEVELOPMENT_TEAM 也不是本人团队，脚本刻意不用它"
  [[ -z "$(git status --porcelain)" ]] || fail "工作区不干净：送审包必须对应一个确定的提交"
  git fetch -q origin main
  git merge-base --is-ancestor HEAD origin/main \
    || fail "HEAD 不在 origin/main 线上：build 号取提交数，从旁支打包会让之后 main 上的包号回退"
fi

AUTH_ARGS=()
if [[ -n "${ASC_KEY_PATH:-}" ]]; then
  AUTH_ARGS=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

MANUAL=0
if [[ -n "${PROFILE_APP:-}" || -n "${PROFILE_WIDGET:-}" ]]; then
  [[ -n "${PROFILE_APP:-}" && -n "${PROFILE_WIDGET:-}" ]] \
    || fail "手动签名要同时传 PROFILE_APP 和 PROFILE_WIDGET（主 App 与 Widget 各一个描述文件名）"
  MANUAL=1
fi

if [[ $DRY_RUN -eq 1 ]]; then
  SIGN_ARGS=(CODE_SIGNING_ALLOWED=NO)
elif [[ $MANUAL -eq 1 ]]; then
  security find-identity -v -p codesigning | grep -q '"Apple Distribution' \
    || fail "钥匙串里没有 Apple Distribution 证书：先双击导师给的 P12 导入（密码问导师要，别发给别人）"
  # 两个 target 的描述文件名经变量传进 project.pbxproj 的 Release 配置（AIDRUN_PROFILE_APP / _WIDGET）
  SIGN_ARGS=(DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Apple Distribution"
    AIDRUN_PROFILE_APP="$PROFILE_APP" AIDRUN_PROFILE_WIDGET="$PROFILE_WIDGET")
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
[[ $rc -eq 0 ]] || fail "archive 失败（rc=${rc}），看 $OUT/archive.log"

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
scripts/check-app-archs.sh "$APP" || fail "产物架构检查未过（详见上方）"

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
if [[ $MANUAL -eq 1 ]]; then
  SIGN_PLIST="  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Apple Distribution</string>
  <key>provisioningProfiles</key><dict>
    <key>$(pl "$APP" CFBundleIdentifier)</key><string>${PROFILE_APP}</string>
    <key>$(pl "$WIDGET" CFBundleIdentifier)</key><string>${PROFILE_WIDGET}</string>
  </dict>"
  EXPORT_AUTH=()
else
  SIGN_PLIST="  <key>signingStyle</key><string>automatic</string>"
  EXPORT_AUTH=(-allowProvisioningUpdates ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"})
fi
cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>${TEAM_ID}</string>
${SIGN_PLIST}
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
EOF
plutil -lint "$OUT/ExportOptions.plist" >/dev/null || fail "ExportOptions.plist 格式不对：$OUT/ExportOptions.plist"

echo "▶ 上传 App Store Connect（日志 $OUT/export.log）"
set +e
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -exportPath "$OUT/export" ${EXPORT_AUTH[@]+"${EXPORT_AUTH[@]}"} \
  > "$OUT/export.log" 2>&1
rc=$?
set -e
tail -n 5 "$OUT/export.log"
[[ $rc -eq 0 ]] || fail "上传失败（rc=${rc}），看 $OUT/export.log"
echo "✅ build $build 已上传。约 10–30 分钟后出现在 App Store Connect → TestFlight，处理完才能加进测试组"
