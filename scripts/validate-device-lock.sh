#!/usr/bin/env bash
set -uo pipefail

# device-test.sh 设备锁的自测。
#
# 锁存在的理由见 device-test.sh 的「0. 设备互斥」注释：并发跑同一台真机会互相把
# runner 装掉，两边都报 `Test crashed with signal kill`，与真回归无法区分。
#
# 这里用 AIDRUN_LOCK_SELFTEST 让脚本拿到锁就待命，所以三条分支都能验，且**不碰真机**、
# 不跑 xcodebuild。用的设备 id 是假的，不会和真设备的锁撞上。

cd "$(dirname "$0")/.."
# 可覆盖是为了能验红：把它指向加锁之前的那份 device-test.sh，本文件必须变红。
SCRIPT="${AIDRUN_LOCK_SCRIPT:-scripts/device-test.sh}"
FAKE_ID="00000000-0000000000000000"
LOCK="${TMPDIR:-/tmp}/aidrun-device-test.lock.${FAKE_ID}"

PASS=0
FAIL=0
ok()   { printf '  ✅ %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  ❌ %s\n' "$1"; FAIL=$((FAIL + 1)); }

rm -rf "$LOCK"
trap 'rm -rf "$LOCK"' EXIT

echo "[validate-device-lock] 1/3 并发的第二次被拦下"
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

echo "[validate-device-lock] 2/3 正常退出会释放锁"
rm -rf "$LOCK"
AIDRUN_DEVICE_ID="$FAKE_ID" AIDRUN_LOCK_SELFTEST=0 bash "$SCRIPT" >/dev/null 2>&1
if [ -d "$LOCK" ]; then
  bad "脚本退出后锁还在：$LOCK"
else
  ok "退出时锁已删除"
fi

echo "[validate-device-lock] 3/3 死锁（持有者已不在）会被自动回收"
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

echo
printf '[validate-device-lock] 通过 %s 条，失败 %s 条\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
