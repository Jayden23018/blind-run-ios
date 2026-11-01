#!/usr/bin/env bash
set -uo pipefail

# device-test.sh 在 xcodebuild 之前那几道闸的自测：设备锁（1–3）、工作区完整性（4–5）、Xcode 图形界面占用（6–7）、
# 个人前缀用独立 DerivedData（8–10，#452）、一次跑多少条（11–12，#616）。
#
# 锁存在的理由见 device-test.sh 的「0. 设备互斥」注释：并发跑同一台真机会互相把
# runner 装掉，两边都报 `Test crashed with signal kill`，与真回归无法区分。
# 工作区完整性见「0.5」注释：worktree 里缺 LocalConfig.xcconfig / Pods/ 时报错全指着工程配置。
#
# 全部都**不碰真机**、不跑 xcodebuild：1–3 用 AIDRUN_LOCK_SELFTEST 拿到锁就待命，
# 4–5 在设备探活之前就 die。用的设备 id 是假的，不会和真设备的锁撞上。
#
# 文件名只说了锁，是因为改名要动 CI 引用而收益为零 —— 内容以本注释为准。

cd "$(dirname "$0")/.."
# 可覆盖是为了能验红：把它指向加锁之前的那份 device-test.sh，本文件必须变红。
SCRIPT="${AIDRUN_LOCK_SCRIPT:-scripts/device-test.sh}"
# 4–5 要从别的目录跑它，相对路径在那边解不出来。
case "$SCRIPT" in /*) SCRIPT_ABS="$SCRIPT" ;; *) SCRIPT_ABS="$PWD/$SCRIPT" ;; esac
FAKE_ID="00000000-0000000000000000"
LOCK="${TMPDIR:-/tmp}/aidrun-device-test.lock.${FAKE_ID}"

PASS=0
FAIL=0
ok()   { printf '  ✅ %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  ❌ %s\n' "$1"; FAIL=$((FAIL + 1)); }

rm -rf "$LOCK"
trap 'rm -rf "$LOCK"' EXIT

echo "[validate-device-lock] 1/9 并发的第二次被拦下"
AIDRUN_DEVICE_ID="$FAKE_ID" AIDRUN_LOCK_SELFTEST=6 bash "$SCRIPT" >/dev/null 2>&1 &
HOLDER=$!
# 等持有者真正建出锁再发第二次，否则测的是「谁先跑到」而不是互斥。
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  [ -f "$LOCK/pid" ] && break
  sleep 0.25
done
if [ ! -f "$LOCK/pid" ]; then
  bad "持有者没能在 5s 内建出锁，后两条无从谈起"
else
  SECOND="$(AIDRUN_DEVICE_ID="$FAKE_ID" AIDRUN_LOCK_SELFTEST=1 bash "$SCRIPT" 2>&1)"
  SECOND_STATUS=$?
  if [ "$SECOND_STATUS" -eq 0 ]; then
    bad "第二次拿到了锁（退出码 0）—— 互斥没生效"
  else
    ok "第二次被拒，退出码 $SECOND_STATUS"
  fi
  case "$SECOND" in
    *"正被另一次 device-test 占用"*) ok "拒绝文案说清了原因" ;;
    *) bad "拒绝文案没提占用，实际输出：$SECOND" ;;
  esac
fi

kill "$HOLDER" 2>/dev/null
wait "$HOLDER" 2>/dev/null

echo "[validate-device-lock] 2/9 正常退出会释放锁"
rm -rf "$LOCK"
AIDRUN_DEVICE_ID="$FAKE_ID" AIDRUN_LOCK_SELFTEST=0 bash "$SCRIPT" >/dev/null 2>&1
if [ -d "$LOCK" ]; then
  bad "脚本退出后锁还在：$LOCK"
else
  ok "退出时锁已删除"
fi

echo "[validate-device-lock] 3/9 死锁（持有者已不在）会被自动回收"
# 先拿一个确定不存在的 pid：起一个立刻结束的子进程，等它回收掉再借用它的号。
( exit 0 ) &
DEAD_PID=$!
wait "$DEAD_PID" 2>/dev/null
mkdir -p "$LOCK"
printf '%s\n' "$DEAD_PID" >"$LOCK/pid"
THIRD="$(AIDRUN_DEVICE_ID="$FAKE_ID" AIDRUN_LOCK_SELFTEST=0 bash "$SCRIPT" 2>&1)"
THIRD_STATUS=$?
if [ "$THIRD_STATUS" -ne 0 ]; then
  bad "死锁没被回收，退出码 ${THIRD_STATUS}，输出：$THIRD"
else
  case "$THIRD" in
    *"回收上次异常退出留下的设备锁"*) ok "死锁被回收且说明了原因" ;;
    *) bad "回收了但没说明，实际输出：$THIRD" ;;
  esac
fi

# ---- 4–5：工作区完整性（device-test.sh 第 0.5 节）----
#
# 两条故意造**两种不同的缺法**，期望**两句不同的文案**。只验「会失败」远远不够 ——
# 从一个空目录跑这个脚本有一万种失败方式，任何一种都能让「会失败」通过，
# 分辨不出这道闸到底在查什么、有没有在查。第 5 条把 LocalConfig 补上之后文案必须改口，
# 那才证明第 4 条点的是 LocalConfig 而不是随便撞上的什么东西。
#
# 两条都在设备探活之前 die，所以不碰真机；锁会照常拿到又释放。
# ⚠️ `mktemp -t` 两种实现语义相反：BSD（macOS）把它当**前缀**，
# GNU（CI 跑的 Linux）把它当**模板**、必须以 XXXXXX 结尾，否则报
# `too few X's in template` 且**不产出目录** —— 于是 $SANDBOX 为空、
# 第 5 条写成 /LocalConfig.xcconfig（Permission denied）必挂。
# 本机 macOS 永远跑不出来，只有 CI 会红。写全模板，两边行为一致。
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/aidrun-device-test-worktree.XXXXXX")"
trap 'rm -rf "$LOCK" "$SANDBOX"' EXIT

echo "[validate-device-lock] 4/9 缺 LocalConfig.xcconfig 时说清是工作区没初始化"
FOURTH="$(cd "$SANDBOX" && AIDRUN_DEVICE_ID="$FAKE_ID" bash "$SCRIPT_ABS" 2>&1)"
case "$FOURTH" in
  *"缺少 LocalConfig.xcconfig"*) ok "点名了 LocalConfig.xcconfig" ;;
  *) bad "没点名 LocalConfig.xcconfig，实际输出：$FOURTH" ;;
esac

echo "[validate-device-lock] 5/9 LocalConfig 有了但缺 Pods/ 时改口"
: >"$SANDBOX/LocalConfig.xcconfig"
FIFTH="$(cd "$SANDBOX" && AIDRUN_DEVICE_ID="$FAKE_ID" bash "$SCRIPT_ABS" 2>&1)"
case "$FIFTH" in
  *"缺少 Pods/"*) ok "改口点名 Pods/ —— 证明第 4 条不是恒失败" ;;
  *) bad "期望点名 Pods/，实际输出：$FIFTH" ;;
esac

# ---- 6–7：Xcode 图形界面占用（device-test.sh 第 0.6 节）----
#
# 造一个名字固定的进程冒充 Xcode（AIDRUN_XCODE_PROCESS_NAME），第 6 条期望被拦、第 7 条带放行开关
# 期望**不**出现这句 —— 两条对照才证明第 6 条拦的是「Xcode 开着」，而不是工作区里别的缺口。
# 两条都要先补齐 LocalConfig、Pods/ 和阿里云 SDK，否则会提前死在 0.5 节，测不到 0.6。
mkdir -p "$SANDBOX/Pods"
echo "[validate-device-lock] 5b/9 Pods/ 有了但没下载阿里云 SDK 时再改口"
FIFTH_B="$(cd "$SANDBOX" && AIDRUN_DEVICE_ID="$FAKE_ID" bash "$SCRIPT_ABS" 2>&1)"
case "$FIFTH_B" in
  *"缺少阿里云实人认证 SDK"*) ok "点名了阿里云 SDK" ;;
  *) bad "期望点名阿里云 SDK，实际输出：$FIFTH_B" ;;
esac
mkdir -p "$SANDBOX/Vendor/AliyunCloudAuth/test/Frameworks/AliyunFaceAuthFacade.framework"
: >"$SANDBOX/Vendor/AliyunCloudAuth/test/Frameworks/AliyunFaceAuthFacade.framework/AliyunFaceAuthFacade"
# 名字要短：进程名 macOS 只留 16 字符、Linux 15 字符，超长被截断后 `pgrep -x` 全名匹配不上。
FAKE_XCODE="fxc$$"
FAKE_BIN="$SANDBOX/$FAKE_XCODE"
# 先用符号链接不用 cp：macOS 上复制出来的系统 sleep 一启动就被杀（签名校验），进程根本不存在；
# 符号链接的进程名取链接名，`pgrep -x` 能认出来。
ln -s "$(command -v sleep)" "$FAKE_BIN"
"$FAKE_BIN" 30 2>/dev/null &
FAKE_PID=$!
trap 'kill "$FAKE_PID" 2>/dev/null; rm -rf "$LOCK" "$SANDBOX"' EXIT
sleep 0.3
# Rust 版 coreutils（GitHub Ubuntu 运行器 2026-10-27 起）是多合一程序，按 argv[0] 认身份：
# 链接名不是 sleep 就报 `Security violation` 退出，假进程没起来，第 6 条被误报成「没拦 Xcode」。
# 认不出来就换同名 shell 脚本 —— Linux 上脚本进程的名字就是脚本文件名。
if ! pgrep -x "$FAKE_XCODE" >/dev/null; then
  kill "$FAKE_PID" 2>/dev/null
  rm -f "$FAKE_BIN"
  printf '#!/bin/sh\nwhile :; do sleep 1; done\n' > "$FAKE_BIN"
  chmod +x "$FAKE_BIN"
  "$FAKE_BIN" &
  FAKE_PID=$!
  sleep 0.3
fi
# 两种都造不出来就直说，别让「假进程没起来」冒充「Xcode 检查坏了」。
if ! pgrep -x "$FAKE_XCODE" >/dev/null; then
  echo "[validate-device-lock] ❌ 造不出名叫 $FAKE_XCODE 的进程，第 6–7 条测不了（不是 device-test.sh 的问题）"
  exit 1
fi

echo "[validate-device-lock] 6/9 Xcode 开着时在 xcodebuild 之前拦下"
SIXTH="$(cd "$SANDBOX" && AIDRUN_DEVICE_ID="$FAKE_ID" AIDRUN_XCODE_PROCESS_NAME="$FAKE_XCODE" bash "$SCRIPT_ABS" 2>&1)"
case "$SIXTH" in
  *"Xcode 图形界面开着"*) ok "点名了 Xcode 图形界面" ;;
  *) bad "没拦 Xcode，实际输出：$SIXTH" ;;
esac

echo "[validate-device-lock] 7/9 AIDRUN_ALLOW_XCODE_OPEN=1 时放行"
SEVENTH="$(cd "$SANDBOX" && AIDRUN_DEVICE_ID="$FAKE_ID" AIDRUN_XCODE_PROCESS_NAME="$FAKE_XCODE" AIDRUN_ALLOW_XCODE_OPEN=1 bash "$SCRIPT_ABS" 2>&1)"
case "$SEVENTH" in
  *"Xcode 图形界面开着"*) bad "放行开关没生效，实际输出：$SEVENTH" ;;
  *) ok "放行后不再拦 —— 证明第 6 条不是恒失败" ;;
esac

# ---- 8–9：设了个人前缀就用独立的 DerivedData（device-test.sh 开头，#452）----
#
# 不分开时，不带前缀的编译门禁会把 runner 改写成默认 bundle id，下一次带前缀跑测时 runner 装不上
# （`Failed to create directory on device … runtime profiles`）。第 8 条对照「不设 / 设了」两种，
# 第 9 条对照同一前缀下两个工作区 —— 按工作区分才不会让两个 worktree 互相覆盖编译产物。
# 都走 AIDRUN_LOCK_SELFTEST：拿到锁就报出路径并退出，不跑 xcodebuild。
echo "[validate-device-lock] 8/9 设了 AIDRUN_BUNDLE_ID_PREFIX 才换成独立的 DerivedData"
dd_of() { printf '%s\n' "$1" | sed -n 's/^\[device-test\] derivedDataPath=//p'; }
# `env -u`：开发者 shell 里 export 过个人前缀时，「不设前缀」这一问不能被它污染。
DEFAULT_DD="$(dd_of "$(env -u AIDRUN_BUNDLE_ID_PREFIX -u AIDRUN_DERIVED_DATA_PATH -u DERIVED_DATA AIDRUN_DEVICE_ID="$FAKE_ID" AIDRUN_LOCK_SELFTEST=0 bash "$SCRIPT" 2>&1)")"
PREFIX_DD="$(dd_of "$(AIDRUN_DEVICE_ID="$FAKE_ID" AIDRUN_BUNDLE_ID_PREFIX=com.example.aidrun AIDRUN_LOCK_SELFTEST=0 bash "$SCRIPT" 2>&1)")"
case "$DEFAULT_DD" in
  "（默认）") ok "不设前缀时不改 DerivedData（与编译门禁同一份，bundle id 两边一致）" ;;
  *) bad "不设前缀时期望用默认目录，实际：'$DEFAULT_DD'" ;;
esac
case "$PREFIX_DD" in
  */DerivedData/aidrun-device-com.example.aidrun-*) ok "设了前缀改用独立目录：$PREFIX_DD" ;;
  *) bad "设了前缀却没换成独立的 DerivedData，实际：'$PREFIX_DD'" ;;
esac

echo "[validate-device-lock] 9/9 同一前缀在两个工作区各用各的"
OTHER_DD="$(dd_of "$(cd "$SANDBOX" && AIDRUN_DEVICE_ID="$FAKE_ID" AIDRUN_BUNDLE_ID_PREFIX=com.example.aidrun AIDRUN_LOCK_SELFTEST=0 bash "$SCRIPT_ABS" 2>&1)")"
if [ -n "$OTHER_DD" ] && [ -n "$PREFIX_DD" ] && [ "$OTHER_DD" != "$PREFIX_DD" ]; then
  ok "两个工作区目录不同 —— 不会互相覆盖编译产物"
else
  bad "两个工作区算出同一个（或空的）目录：'$PREFIX_DD' / '$OTHER_DD'"
fi

# 8–9 只证明算出了对的路径。真正决定修复生不生效的是 `xcodebuild test` 那条命令里有没有把它传进去 ——
# `${X[@]+...}` 写错名字时不会触发 `set -u`，静默展开成空，8–9 照样全绿（#544 审查 A1）。
echo "[validate-device-lock] 10 xcodebuild test 那条命令真的带上了 DerivedData 参数"
XCB_CMD="$(awk '/^xcodebuild test \\$/ { on = 1 } on { print } on && !/\\$/ { exit }' "$SCRIPT")"
case "$XCB_CMD" in
  *'${DERIVED_DATA_ARGS[@]+"${DERIVED_DATA_ARGS[@]}"}'*) ok "xcodebuild test 命令里展开了 DERIVED_DATA_ARGS" ;;
  '') bad "在 $SCRIPT 里找不到以「xcodebuild test \\」开头的那条命令，自测失去了对象" ;;
  *) bad "xcodebuild test 命令里没有展开 DERIVED_DATA_ARGS —— 算出的独立目录根本没传给 xcodebuild" ;;
esac

# ---- 11–12：一次跑多少条（device-test.sh 第 0.4 节，#616）----
# 判定逻辑的边界在 scripts/validate-only-testing-estimate.mjs，这里只验脚本真的接上了：
# 只有那份自测的话，把 0.4 节整段删掉它照样全绿。
echo "[validate-device-lock] 11 裸跑超过上限，在编译之前就被拦下"
ELEVENTH="$(AIDRUN_DEVICE_ID="$FAKE_ID" bash "$SCRIPT" 2>&1)"
case "$ELEVENTH" in
  *'超过上限'*'AIDRUN_ALLOW_WIDE_RUN=1'*) ok "裸跑被拦下，说明里给了放行开关" ;;
  *) bad "裸跑没有被 100 条上限拦下：$ELEVENTH" ;;
esac

echo "[validate-device-lock] 12 AIDRUN_ALLOW_WIDE_RUN=1 放行"
TWELFTH="$(AIDRUN_DEVICE_ID="$FAKE_ID" AIDRUN_ALLOW_WIDE_RUN=1 bash "$SCRIPT" 2>&1)"
case "$TWELFTH" in
  *'超过上限'*) bad "设了 AIDRUN_ALLOW_WIDE_RUN=1 仍被拦下" ;;
  *) ok "放行后往下走（假设备会在后面的闸停下，不碰真机）" ;;
esac

echo
printf '[validate-device-lock] 通过 %s 条，失败 %s 条\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
