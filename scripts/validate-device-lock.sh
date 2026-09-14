#!/usr/bin/env bash
set -uo pipefail

# device-test.sh 在 xcodebuild 之前那几道闸的自测：设备锁（1–3）与工作区完整性（4–5）。
#
# 锁存在的理由见 device-test.sh 的「0. 设备互斥」注释：并发跑同一台真机会互相把
# runner 装掉，两边都报 `Test crashed with signal kill`，与真回归无法区分。
# 工作区完整性见「0.5」注释：worktree 里缺 LocalConfig.xcconfig / Pods/ 时报错全指着工程配置。
#
# 五条都**不碰真机**、不跑 xcodebuild：1–3 用 AIDRUN_LOCK_SELFTEST 拿到锁就待命，
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

echo "[validate-device-lock] 1/5 并发的第二次被拦下"
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

echo "[validate-device-lock] 2/5 正常退出会释放锁"
rm -rf "$LOCK"
AIDRUN_DEVICE_ID="$FAKE_ID" AIDRUN_LOCK_SELFTEST=0 bash "$SCRIPT" >/dev/null 2>&1
if [ -d "$LOCK" ]; then
  bad "脚本退出后锁还在：$LOCK"
else
  ok "退出时锁已删除"
fi

echo "[validate-device-lock] 3/5 死锁（持有者已不在）会被自动回收"
# 先拿一个确定不存在的 pid：起一个立刻结束的子进程，等它回收掉再借用它的号。
( exit 0 ) &
DEAD_PID=$!
wait "$DEAD_PID" 2>/dev/null
mkdir -p "$LOCK"
printf '%s\n' "$DEAD_PID" >"$LOCK/pid"
THIRD="$(AIDRUN_DEVICE_ID="$FAKE_ID" AIDRUN_LOCK_SELFTEST=0 bash "$SCRIPT" 2>&1)"
THIRD_STATUS=$?
if [ "$THIRD_STATUS" -ne 0 ]; then
  bad "死锁没被回收，退出码 $THIRD_STATUS，输出：$THIRD"
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

echo "[validate-device-lock] 4/5 缺 LocalConfig.xcconfig 时说清是工作区没初始化"
FOURTH="$(cd "$SANDBOX" && AIDRUN_DEVICE_ID="$FAKE_ID" bash "$SCRIPT_ABS" 2>&1)"
case "$FOURTH" in
  *"缺少 LocalConfig.xcconfig"*) ok "点名了 LocalConfig.xcconfig" ;;
  *) bad "没点名 LocalConfig.xcconfig，实际输出：$FOURTH" ;;
esac

echo "[validate-device-lock] 5/5 LocalConfig 有了但缺 Pods/ 时改口"
: >"$SANDBOX/LocalConfig.xcconfig"
FIFTH="$(cd "$SANDBOX" && AIDRUN_DEVICE_ID="$FAKE_ID" bash "$SCRIPT_ABS" 2>&1)"
case "$FIFTH" in
  *"缺少 Pods/"*) ok "改口点名 Pods/ —— 证明第 4 条不是恒失败" ;;
  *) bad "期望点名 Pods/，实际输出：$FIFTH" ;;
esac

echo
printf '[validate-device-lock] 通过 %s 条，失败 %s 条\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
