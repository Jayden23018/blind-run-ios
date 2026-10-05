#!/usr/bin/env bash
set -uo pipefail
# scripts/lib/preflight-watchdog.sh 的自测。不碰真机、不跑 xcodebuild：用一个往日志里写东西的
# 后台进程扮演 xcodebuild。
#
# 第 1 条是把「编译中」和「卡住」分开的那一条：进程持续输出 5 秒才开始跑用例、超时设 2 秒。
# 旧实现按启动以来的总时间计，会在 2 秒时判卡住（2026-10-05 真机跑测两次被这样掐掉）；
# 新实现按日志停滞计，必须等到它。验红：AIDRUN_WATCHDOG_LIB 指向按总时间计的旧实现，第 1 条必须红。
cd "$(dirname "$0")/.."
LIB="${AIDRUN_WATCHDOG_LIB:-scripts/lib/preflight-watchdog.sh}"
# shellcheck source=lib/preflight-watchdog.sh
. "$LIB"

PASS=0
FAIL=0
ok()  { printf '  ✅ %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  ❌ %s\n' "$1"; FAIL=$((FAIL + 1)); }
LOG="$(mktemp -t aidrun-watchdog)"
trap 'rm -f "$LOG"' EXIT

echo "[validate-preflight-watchdog] 1/3 编译期间持续有输出，不算卡住"
: >"$LOG"
( for i in $(seq 1 25); do echo "CompileSwift file$i.swift" >>"$LOG"; sleep 0.2; done
  echo "Test Case '-[Suite test]' started." >>"$LOG"; sleep 2 ) &
PID=$!
preflight_watch "$PID" "$LOG" 2 1; RC=$?
kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null
[ "$RC" -eq 0 ] && ok "等到了第一条用例（退出 0）" || bad "编译 5 秒、超时 2 秒时被判成 $RC —— 计的是总时间不是停滞时间"

echo "[validate-preflight-watchdog] 2/3 日志静止超过时限，判卡住"
: >"$LOG"
( echo "Run Destination Preflight" >>"$LOG"; sleep 10 ) &
PID=$!
START=$(date +%s)
preflight_watch "$PID" "$LOG" 2 1; RC=$?
DUR=$(( $(date +%s) - START ))
kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null
[ "$RC" -eq 3 ] && ok "判卡住（退出 3）" || bad "日志静止 10 秒没判卡住，退出 $RC"
[ "$DUR" -le 6 ] && ok "在 ${DUR}s 内判出，没有等到进程结束" || bad "用了 ${DUR}s，看门狗没在时限内动作"

echo "[validate-preflight-watchdog] 3/3 锁屏提示立刻判锁屏"
: >"$LOG"
( echo "Unlock mac’s iPhone to Continue" >>"$LOG"; sleep 10 ) &
PID=$!
preflight_watch "$PID" "$LOG" 30 1; RC=$?
kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null
[ "$RC" -eq 2 ] && ok "判锁屏（退出 2）" || bad "锁屏提示没被认出，退出 $RC"

echo "[validate-preflight-watchdog] passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
