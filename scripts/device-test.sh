#!/usr/bin/env bash
set -uo pipefail

# 真机 XCTest —— 本仓库唯一的 XCTest 通道（模拟器因高德无 arm64-sim slice 永久不可用）。
#
# 这个脚本存在，是因为直接敲 xcodebuild 踩过两个坑，两个都会让人以为测试跑过了：
#
#   1. 设备锁屏时 xcodebuild 会静默等在 "Run Destination Preflight: Unlock ... to Continue"，
#      不报错、不退出，输出文件 0 字节，看着像在跑。这里改成主动检出并立刻失败。
#   2. 从日志里数用例根本不可靠。先是大小写坑（`Test case` 小写 c，按 `Test Case` grep 全计成 0），
#      后来发现更深的一层：三路输出并发写同一个 fd，会把统计行拦腰截断（详见第 3 节注释）。
#      现在统计**只认 result bundle**，日志仅用于人看和 preflight 探活。
#
# 用法：
#   scripts/device-test.sh                      # 全量
#   scripts/device-test.sh -only-testing:blindRunTests/EmergencySOSTests
#
# 环境变量：
#   AIDRUN_DEVICE_ID    真机**硬件 UDID**（默认见下；设备名会变，所以默认用 id 不用 name）
#                       ⚠️ 不是 `devicectl list devices` 那列 Identifier —— 那是 CoreDevice
#                       的 UUID（`3B6214C9-BA98-…` 这种），xcodebuild 不认，传了会以
#                       退出码 70 失败，报「Unable to find a device matching」，
#                       看起来像设备掉线。要的是 `00008103-001C71490E62201E` 这种形状，
#                       取自 `xcrun xctrace list devices` 或本脚本失败时打印的 destination 列表。
#                       格式不对会被下面的 preflight 直接拦住并给出正确取法。
#   AIDRUN_SCHEME       默认 blindRun
#   AIDRUN_TEAM         默认 ZW39BS8NXT（工程里写死的 R6PH2TFB3Q 是原开发者的团队，
#                       用命令行覆盖，不要改 pbxproj）

DEVICE_ID="${AIDRUN_DEVICE_ID:-00008140-000161D62112801C}"
SCHEME="${AIDRUN_SCHEME:-blindRun}"
TEAM="${AIDRUN_TEAM:-ZW39BS8NXT}"
WORKSPACE="blindRun.xcworkspace"
LOG="$(mktemp -t aidrun-device-test)"
# xcodebuild 要求 -resultBundlePath 指向一个**还不存在**的路径，所以只建父目录。
BUNDLE="$(mktemp -d -t aidrun-device-test-bundle)/result.xcresult"
PREFLIGHT_TIMEOUT="${AIDRUN_PREFLIGHT_TIMEOUT:-180}"

say() { printf '[device-test] %s\n' "$*"; }
die() { printf '[device-test] ERROR: %s\n' "$*" >&2; exit 1; }

# 硬件 UDID 是 8 位十六进制 + '-' + 16 位十六进制。CoreDevice 的 UUID 是标准的
# 8-4-4-4-12。后者是 `devicectl list devices` 的 Identifier 列，两台设备都在时最容易
# 顺手复制的就是它 —— 而 xcodebuild 不认，只回一句「Unable to find a device matching」
# 加退出码 70，与「设备掉线」长得一模一样，会把人支去查 USB 线。
case "${AIDRUN_DEVICE_ID:-}" in
  '') ;;
  [0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]-*)
    # 再排掉 8-4-4-4-12：硬件 UDID 只有一个 '-'。
    if [ "$(printf '%s' "$AIDRUN_DEVICE_ID" | tr -cd '-' | wc -c | tr -d ' ')" != "1" ]; then
      die "AIDRUN_DEVICE_ID='$AIDRUN_DEVICE_ID' 看起来是 CoreDevice UUID（\`devicectl list devices\` 的 Identifier 列），xcodebuild 不认。
     要的是硬件 UDID（一个连字符，形如 00008103-001C71490E62201E）：
       xcrun xctrace list devices"
    fi
    ;;
  *)
    die "AIDRUN_DEVICE_ID='$AIDRUN_DEVICE_ID' 不像硬件 UDID（形如 00008103-001C71490E62201E）。取法：
       xcrun xctrace list devices"
    ;;
esac

# ---------- 0. 设备互斥 ----------
#
# 真机只有一台，而本机常同时开着多个 worktree 会话（2026-09-05 实测 7 个）。两次
# xcodebuild 同时打同一台设备时，后起的那次 install 会把前一次的 runner 装掉，
# 前一次报 `Test crashed with signal kill`、失败用例是 `(0.000 seconds)` ——
# **看起来和真回归一模一样**，而且失败集合每次都不同，正好落进
# 「跨两次运行零重叠就不是代码问题」那条判据里，于是被当成随机崩去查设备。
# 那天下午 16:08–16:31 的全部结果因此作废（16:08:26 起的全量 UI 与 16:08:32 起的
# 四条用例只差 6 秒；16:30 三个并发甚至报出 `Failed to create directory`）。
#
# 锁按设备分，所以两台设备可以并行跑。
LOCK_DIR="${TMPDIR:-/tmp}/aidrun-device-test.lock.${DEVICE_ID}"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  LOCK_OWNER="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
  # 上次被 Ctrl-C / kill -9 掐掉会留下死锁。死锁比并发更坏 —— 它让所有人都跑不了，
  # 所以持有者进程不在了就直接回收，不要求人工清理。
  if [ -z "$LOCK_OWNER" ] || ! kill -0 "$LOCK_OWNER" 2>/dev/null; then
    say "回收上次异常退出留下的设备锁（持有者 pid ${LOCK_OWNER:-未知} 已不存在）"
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR" 2>/dev/null || die "设备锁 $LOCK_DIR 回收失败，手动删掉它再重试。"
  else
    die "设备 $DEVICE_ID 正被另一次 device-test 占用（pid $LOCK_OWNER）。
     并发跑同一台真机会互相把 runner 装掉，两边都会报 signal kill 且看着像代码回归。
     等它跑完，或先确认那次是不是跑飞了：
       ps -p $LOCK_OWNER -o pid,etime,args"
  fi
fi
printf '%s\n' "$$" >"$LOCK_DIR/pid"
trap 'rm -rf "$LOCK_DIR"' EXIT

# 自测钩子：拿到锁后原地待命，让 validate-device-lock.sh 能验并发/死锁回收两条分支
# 而不用真去跑 xcodebuild。生产路径上这个变量永远是空的。
if [ -n "${AIDRUN_LOCK_SELFTEST:-}" ]; then
  say "已持有设备锁（pid $$），selftest 模式待命 ${AIDRUN_LOCK_SELFTEST}s"
  sleep "$AIDRUN_LOCK_SELFTEST"
  exit 0
fi

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
  -resultBundlePath "$BUNDLE" \
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

# ---------- 3. 统计（权威来源是 result bundle，不是日志）----------
#
# 为什么不再 grep 日志：xcodebuild 的进度输出、XCTest runner 的 stdout、以及设备侧
# os_log 转发，三路并发写同一个 fd，`Test case '...' passed` 会被拦腰截断并与另一路拼接，例如：
#   Test case 'AppRealtimeCoordinatorTests.testProductionOrderStatusPayloadDecoTest Case '-[...]' started.
# 被截断的行匹配不上，于是数目偏少。2026-08-07 同一天四次实测（脚本数 → bundle 真值）：
#   528→535、29→30、73→73、530→539。少的都是 passed，但**同样的截断一样会吞掉 failed 行**，
#   而「不许把没通过的测试当成通过」正是本脚本存在的全部理由。
#
# result bundle 是 xcodebuild 自己写的结构化产物，不受日志交错影响。
# 判定逻辑抽在 `xcresult-verdict.mjs`，因为内联在这里就没法写自测 ——
# 而这条链路的统计口径已经错过两次。自测：scripts/validate-xcresult-verdict.mjs
echo
xcrun xcresulttool get test-results summary --path "$BUNDLE" --format json 2>/dev/null \
  | node "$(dirname "$0")/xcresult-verdict.mjs" 2>&1 \
  | sed 's/^/[device-test] /'
VERDICT_STATUS="${PIPESTATUS[1]}"

say "日志：$LOG"
say "result bundle：$BUNDLE"

if [ "$VERDICT_STATUS" -eq 1 ]; then
  # 有用例失败，失败清单已由 verdict 打印过了。
  exit 1
fi

# 0 以外的都不是「通过」。2 = 结果不可信（读不出 / 零执行 / 整体结论对不上）；
# 其它退出码（例如 127 = 没装 node）同样按不可信处理 —— 未知状态绝不能落到通过那一侧。
if [ "$VERDICT_STATUS" -ne 0 ]; then
  tail -n 30 "$LOG" >&2
  die "测试结果不可信（verdict 退出码 ${VERDICT_STATUS}，xcodebuild 退出码 ${XCB_STATUS}）。
     刻意不退回 grep 日志兜底：那条路会少数用例、也会漏掉 failed 行，
     等于把「没通过」报成「通过」—— 本脚本存在的全部意义就是不许这样。"
fi

if [ "$XCB_STATUS" -ne 0 ]; then
  tail -n 30 "$LOG" >&2
  die "用例全过但 xcodebuild 退出码是 ${XCB_STATUS}（构建/打包/签名阶段出错）。"
fi

say "TEST SUCCEEDED"
