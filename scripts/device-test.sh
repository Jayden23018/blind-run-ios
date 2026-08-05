#!/usr/bin/env bash
set -uo pipefail

# 真机 XCTest —— 本仓库唯一的 XCTest 通道（模拟器因高德无 arm64-sim slice 永久不可用）。
#
# 这个脚本存在，是因为直接敲 xcodebuild 踩过两个坑，两个都会让人以为测试跑过了：
#
#   1. 设备锁屏时 xcodebuild 会静默等在 "Run Destination Preflight: Unlock ... to Continue"，
#      不报错、不退出，输出文件 0 字节，看着像在跑。这里改成主动检出并立刻失败。
#   2. 日志里是 `Test case '...' passed`（小写 c）。按 `Test Case` 去 grep 会全部计成 0，
#      于是「0 失败」看起来像全绿，其实是一条都没数到。这里按正确大小写统计并打印三个数。
#
# 用法：
#   scripts/device-test.sh                      # 全量
#   scripts/device-test.sh -only-testing:blindRunTests/EmergencySOSTests
#
# 环境变量：
#   AIDRUN_DEVICE_ID    真机 UDID（默认见下；设备名会变，所以默认用 id 不用 name）
#   AIDRUN_SCHEME       默认 blindRun
#   AIDRUN_TEAM         默认 ZW39BS8NXT（工程里写死的 R6PH2TFB3Q 是原开发者的团队，
#                       用命令行覆盖，不要改 pbxproj）

DEVICE_ID="${AIDRUN_DEVICE_ID:-00008140-000161D62112801C}"
SCHEME="${AIDRUN_SCHEME:-blindRun}"
TEAM="${AIDRUN_TEAM:-ZW39BS8NXT}"
WORKSPACE="blindRun.xcworkspace"
LOG="$(mktemp -t aidrun-device-test)"
PREFLIGHT_TIMEOUT="${AIDRUN_PREFLIGHT_TIMEOUT:-180}"

say() { printf '[device-test] %s\n' "$*"; }
die() { printf '[device-test] ERROR: %s\n' "$*" >&2; exit 1; }

# ---------- 1. 设备探活 ----------
say "检查设备连接…"
DEVICES="$(xcrun devicectl list devices 2>&1 || true)"
# devicectl 的 State 列会报 available / connected / unavailable 等。
# 早期只认 'available'，但 Xcode 26 对已配对且已解锁的设备报的是 **connected** ——
# 于是一台完全可用的真机被判成「没有设备」，测试压根跑不起来（2026-08-05 实测）。
# 两种状态都接受；真正不可用的情况由下面的 preflight 超时兜住。
if ! printf '%s' "$DEVICES" | grep -qE 'available|connected'; then
  printf '%s\n' "$DEVICES" >&2
  die "没有处于 available 状态的真机。先插上/连上设备并信任这台 Mac，再重试。
     模拟器不是备选项：高德 SDK 没有 arm64-sim slice，模拟器通道永久不可用。
     无真机时的编译上限是：
       xcodebuild -workspace $WORKSPACE -scheme $SCHEME \\
         -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build-for-testing"
fi
printf '%s\n' "$DEVICES" | sed 's/^/    /'

say "⚠️  现在请解锁设备并保持屏幕常亮（设置 → 显示与亮度 → 自动锁定 → 永不）。"
say "    锁屏会让 xcodebuild 静默挂起，本脚本会在 ${PREFLIGHT_TIMEOUT}s 后判定为锁屏失败。"

# ---------- 2. 跑测试，同时盯着锁屏挂起 ----------
say "开始 xcodebuild test（日志：$LOG）"
xcodebuild test \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -destination "platform=iOS,id=${DEVICE_ID}" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" \
  "$@" >"$LOG" 2>&1 &
XCB_PID=$!

# 只在「还没开始跑用例」的窗口里盯锁屏。一旦有用例产出就说明 preflight 过了。
ELAPSED=0
while kill -0 "$XCB_PID" 2>/dev/null; do
  if grep -q "Test case '" "$LOG" 2>/dev/null; then
    break
  fi
  if grep -qi 'Unlock .* to Continue\|Preflight: Unlock\|device is locked' "$LOG" 2>/dev/null; then
    kill "$XCB_PID" 2>/dev/null
    wait "$XCB_PID" 2>/dev/null
    die "设备处于锁屏状态，xcodebuild 会一直等下去。解锁并保持常亮后重跑。"
  fi
  sleep 2
  ELAPSED=$((ELAPSED + 2))
  if [ "$ELAPSED" -ge "$PREFLIGHT_TIMEOUT" ]; then
    kill "$XCB_PID" 2>/dev/null
    wait "$XCB_PID" 2>/dev/null
    printf '%s\n' "$(tail -n 20 "$LOG")" >&2
    die "${PREFLIGHT_TIMEOUT}s 内一条用例都没开始跑，判定为 preflight 卡住（多半是锁屏或设备掉线）。
     完整日志：$LOG"
  fi
done

wait "$XCB_PID"
XCB_STATUS=$?

# ---------- 3. 统计（注意是小写 c 的 `Test case`）----------
PASSED=$(grep -c "Test case '.*' passed"  "$LOG" || true)
FAILED=$(grep -c "Test case '.*' failed"  "$LOG" || true)
SKIPPED=$(grep -c "Test case '.*' skipped" "$LOG" || true)
TOTAL=$((PASSED + FAILED + SKIPPED))

echo
say "passed=${PASSED}  failed=${FAILED}  skipped=${SKIPPED}  (total=${TOTAL})"
say "日志：$LOG"

if [ "$TOTAL" -eq 0 ]; then
  tail -n 30 "$LOG" >&2
  die "一条用例都没执行。xcodebuild 退出码 ${XCB_STATUS}，但零执行不能算通过。"
fi

if [ "$FAILED" -gt 0 ]; then
  echo
  say "失败用例："
  grep "Test case '.*' failed" "$LOG" | sed 's/^/    /' >&2
  exit 1
fi

if [ "$XCB_STATUS" -ne 0 ]; then
  tail -n 30 "$LOG" >&2
  die "用例全过但 xcodebuild 退出码是 ${XCB_STATUS}（构建/打包/签名阶段出错）。"
fi

say "TEST SUCCEEDED"
