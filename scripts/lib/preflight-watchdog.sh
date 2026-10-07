#!/usr/bin/env bash
# 真机跑测「还没开始跑用例」那个窗口的看门狗。由 scripts/device-test.sh source，
# 自测在 scripts/validate-preflight-watchdog.sh（不碰真机、不跑 xcodebuild）。
#
# preflight_watch <pid> <log> <idle-timeout-seconds> [poll-seconds]
#   0 = 已经开始跑用例（日志出现 `Test Case '` / `Test case '`），或进程自己结束了
#   2 = 设备锁屏（xcodebuild 会一直等下去）
#   3 = 日志连续 <idle-timeout> 秒没有任何新输出，也没开始跑用例
#
# 🔴 计的是**日志停滞**的时间，不是从启动起的总时间（2026-10-05 改）。
# 原来是总时间：代码一改要整个重编，编译本身就超过 180 秒，于是**正在编译**的
# xcodebuild 被当成「锁屏 / 掉线」掐掉（日志结尾 `** BUILD INTERRUPTED **`），
# 当天踩了两次、第一次连一行输出都没留下。编译时日志在持续增长，锁屏或掉线时日志是静止的 ——
# 这才是能把两者分开的信号。
#
# 大小写**两种都要认**（2026-09-10 实测这台 Xcode 只产出大写 C 的 `Test Case '`）。
preflight_watch() {
  local pid="$1" log="$2" timeout="$3" poll="${4:-2}"
  local idle=0 last_size=-1 size
  while kill -0 "$pid" 2>/dev/null; do
    if grep -qE "Test [Cc]ase '" "$log" 2>/dev/null; then
      return 0
    fi
    if grep -qi 'Unlock .* to Continue\|Preflight: Unlock\|device is locked' "$log" 2>/dev/null; then
      return 2
    fi
    size=$(wc -c <"$log" 2>/dev/null | tr -d ' ')
    size=${size:-0}
    if [ "$size" != "$last_size" ]; then
      last_size=$size
      idle=0
    else
      idle=$((idle + poll))
      if [ "$idle" -ge "$timeout" ]; then
        return 3
      fi
    fi
    sleep "$poll"
  done
  return 0
}
