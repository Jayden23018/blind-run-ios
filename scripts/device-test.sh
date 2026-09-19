#!/usr/bin/env bash
set -uo pipefail

# 真机 XCTest —— 本仓库唯一的 XCTest 通道（模拟器因高德无 arm64-sim slice 永久不可用）。
#
# 这个脚本存在，是因为直接敲 xcodebuild 踩过两个坑，两个都会让人以为测试跑过了：
#
#   1. 设备锁屏时 xcodebuild 会静默等在 "Run Destination Preflight: Unlock ... to Continue"，
#      不报错、不退出，输出文件 0 字节，看着像在跑。这里改成主动检出并立刻失败。
#   2. 从日志里数用例根本不可靠。先是大小写坑（**两种形态都出现过**，来自不同的写入方：
#      `Test case '...' passed` 与 `Test Case '-[...]' started`；只认一种就会全计成 0），
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
# 用例级停滞时限。见第 2.5 节 —— 没有它，一条挂死的用例就能让**整个全量永远跑不到
# 终点**，而且不留下任何失败记录。与 PREFLIGHT_TIMEOUT 管的是两个互不重叠的窗口。
STALL_TIMEOUT="${AIDRUN_STALL_TIMEOUT:-420}"

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

# ---------- 0.5 工作区完整性 ----------
#
# `LocalConfig.xcconfig` 与 `Pods/` 都在 .gitignore 里，**不随 git worktree / clone 过来**。
# 缺了它们 xcodebuild 挂在构建阶段，一条用例都跑不到：
#   error: Unable to open base configuration reference file '.../LocalConfig.xcconfig'
#   error: Unable to load contents of file list: '/Target Support Files/Pods-blindRun/…'
#
# 第 3 节会正确地把它判成「零执行」并硬失败 —— 那部分没问题。问题是打出来的一屏错误
# 全指着工程配置，读起来像 pbxproj 坏了，而真因只是「这个工作区没初始化过」。
# 2026-09-14 实测被绊了一次，第一反应就是去查工程文件。本仓库常年挂着十几个 worktree，
# 每开一个都要重做这两步，所以这不是偶发，是每个新工作区必然撞一次。
#
# 位置刻意在设备锁**之后**：上面的 selftest 分支够不到这里，而 CI 上跑设备锁自测的
# 机器既没有 Pods/ 也没有 LocalConfig.xcconfig —— 放到锁之前会把那条自测拦死。
# 反过来，真要跑测试的路径必经此处，且这两个 stat 比下面的 devicectl 探活便宜得多。
if [ ! -f LocalConfig.xcconfig ]; then
  # 在 worktree 里 --git-common-dir 指向主 checkout 的 .git，正好能算出该去哪儿抄。
  # 不在 git 仓库里（例如自测从临时目录跑）时退回占位符，不要瞎猜一个路径。
  GIT_COMMON="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  case "$GIT_COMMON" in
    */.git) FROM="${GIT_COMMON%/.git}/LocalConfig.xcconfig" ;;
    *)      FROM="<另一个 checkout>/LocalConfig.xcconfig" ;;
  esac
  die "缺少 LocalConfig.xcconfig —— 这个工作区没初始化过（它在 .gitignore 里，不随 worktree/clone 过来）。
     xcodebuild 会挂在 \"Unable to open base configuration reference file\"，一条用例都跑不到，
     而报错一律指着工程配置，看起来像 pbxproj 坏了。补齐：
       cp $FROM .
     没有别的 checkout 可抄，就照模板自己填高德 key：
       cp LocalConfig.xcconfig.example LocalConfig.xcconfig"
fi

if [ ! -d Pods ]; then
  die "缺少 Pods/ —— 这个工作区没跑过 pod install（Pods/ 同样在 .gitignore 里）。
     缺它时 xcodebuild 报的是一串 \"Unable to load contents of file list\"，同样一条用例都跑不到。补齐：
       LANG=en_US.UTF-8 pod install
     LANG 不能省：裸跑会因 locale 崩在 ruby 内部帧，那个报错和 CocoaPods 本身无关。
     Pods/ 在但和 Podfile.lock 对不上时不归这里管 —— CocoaPods 自己的
     \"[CP] Check Pods Manifest.lock\" 构建阶段会说清楚，照它说的重跑 pod install。"
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
  # 大小写**两种都要认**。2026-09-10 实测这台 Xcode 只产出 `Test Case '`（大写 C），
  # 于是这条 grep 恒为假、看门狗永远等不到「已经开始跑用例」，全量跑必然在
  # PREFLIGHT_TIMEOUT 到点时被当成锁屏掐掉（日志里 UI 用例明明在跑，结尾是
  # `** BUILD INTERRUPTED **`）。定向跑之所以没暴露，是因为它们在超时前整个跑完了 ——
  # 循环是因进程结束而退出的，不是因为找到了标记。
  if grep -qE "Test [Cc]ase '" "$LOG" 2>/dev/null; then
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

# ---------- 2.5 用例级停滞看门狗 ----------
#
# 🔴 上面那个 preflight 看门狗**只盯第一条用例出现之前**的窗口（见它自己的注释：
# 一旦有用例产出就 break）。用例跑到一半挂死时它已经不看了，而 xcodebuild 默认
# 也没有单条用例时限 —— 两边都不管，进程就那么挂着，直到有人发现并手动 kill。
#
# 2026-09-19 实测：`blindRunTests.swift:467` 的
# `testHomeLoadCoordinatorReturnsAtDeadlineWhenRequestIgnoresCancellation`
# 在 iPhone 16 Pro 上跑全量时挂死 **19 分钟零输出**（日志最后时间戳 12:24:43，
# 观测到 12:43 仍无新行）。后果比「一条用例红了」严重得多：
#   · 它后面的用例**一条都没跑**，而终止时的计数（passed=1217）看着像一份正常结果；
#   · result bundle 没写完，`xcresulttool` 报 `Info.plist ... does not exist`，
#     看起来像 bundle 损坏，会把人支去查磁盘和 xcodebuild 本身。
# 同一条用例**单独跑 0.158 秒通过**，iPad 上跑全量也通过 —— 不是必现的代码错误，
# 只在特定累积条件下触发。这类东西未必修得干净，但可以保证它**不再拖垮整轮**。
#
# ⛔ **不要改用 xcodebuild 的 `-test-timeouts-enabled YES`** —— 本仓库的 scheme 是
# `shouldAutocreateTestPlan = "YES"`（没有显式 `.xctestplan`），该参数连同
# `-default-test-execution-time-allowance` 会被**静默忽略**。2026-09-19 实测：
# 给一条实测 6.5 秒的用例设 2 秒时限，它照样 `passed (6.545 seconds)`。
# 留一个不生效的开关比没有更糟 —— 它会让人以为挂死已经有人管了。
#
# 判据是「**有没有新用例产出**」，不是「日志有没有变大」：设备侧 os_log 转发会持续
# 写入，文件大小和 mtime 在挂死期间照样会动。
STALL_LAST=-1
STALL_ELAPSED=0
while kill -0 "$XCB_PID" 2>/dev/null; do
  sleep 10
  STALL_NOW="$(grep -cE "Test [Cc]ase '" "$LOG" 2>/dev/null || true)"
  STALL_NOW="${STALL_NOW:-0}"
  if [ "$STALL_NOW" != "$STALL_LAST" ]; then
    STALL_LAST="$STALL_NOW"
    STALL_ELAPSED=0
    continue
  fi
  STALL_ELAPSED=$((STALL_ELAPSED + 10))
  [ "$STALL_ELAPSED" -lt "$STALL_TIMEOUT" ] && continue

  # 卡住的那条 = 日志里最后一条 `started` 却没有对应结果的用例。这个名字是整件事里
  # 最贵的信息：没有它就只能靠人去翻几千行日志找断点（本条注释的来历就是那样翻出来的）。
  STALLED="$(grep -E "Test [Cc]ase '" "$LOG" 2>/dev/null | tail -n 1 || true)"
  kill "$XCB_PID" 2>/dev/null
  wait "$XCB_PID" 2>/dev/null
  die "${STALL_TIMEOUT}s 内没有任何新用例产出，判定为用例挂死（不是锁屏 —— 锁屏在
     preflight 阶段就被拦了，跑到这里说明用例已经在跑）。
     卡住的位置（日志里最后一条用例行）：
       ${STALLED:-（日志里没有用例行，异常）}
     这一轮的结果**不可用**：后面的用例一条都没跑，result bundle 也没写完。
     下一步：单独跑那条用例确认是不是必现（很可能不是），完整日志：$LOG"
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

# ---------- 3.5 导出附件（截图 / 录像），否则拍了没人看得见 ----------
#
# UI 测试里有 9 处 `attachScreenshot(...)`，拍完就躺在 result bundle 里 —— 除非有人
# 在 Xcode 里手动打开，否则**谁也看不到**，包括跑测试的 agent。视觉相关的验收
# （布局、间距、截断、层级压盖）因此一直只能靠人肉复核。
#
# 一并导出的 manifest.json 记录了每个附件属于哪条用例，比文件名更可靠。
#
# 导出失败**不改变测试结论**：走 if/else 各自打印，两条路都不 exit。
# 本脚本是 `set -uo pipefail`（没有 -e），所以这里不需要也没有 `|| true`。
SHOTS="$(dirname "$BUNDLE")/attachments"
if xcrun xcresulttool export attachments --path "$BUNDLE" --output-path "$SHOTS" >/dev/null 2>&1; then
  SHOT_COUNT="$(find "$SHOTS" -type f ! -name manifest.json 2>/dev/null | wc -l | tr -d ' ')"
  say "附件已导出（${SHOT_COUNT} 个）：$SHOTS"
  say "  归属见 $SHOTS/manifest.json；只要失败截图可加 --only-failures 重跑导出。"
else
  say "附件导出失败（不影响上面的测试结论）。手动重试："
  say "  xcrun xcresulttool export attachments --path \"$BUNDLE\" --output-path <目录>"
fi

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
