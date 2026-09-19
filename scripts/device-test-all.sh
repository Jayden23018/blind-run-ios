#!/usr/bin/env bash
set -uo pipefail

# 分批跑完整测试 —— **本仓库拿到完整结果的唯一可行方式**。
#
# 为什么不能裸跑 `scripts/device-test.sh`（全量一次）：
#
#   2026-09-19 在 iPhone 16 Pro 上实测两次，**两次都挂死，且挂在不同的用例上**：
#     · 第一次跑到 1217 条，挂在 blindRunTests/testHomeLoadCoordinatorReturnsAtDeadline…
#     · 第二次跑到  538 条，挂在 LiveEscortTrackTests/testSessionLifecycleEnablesBackgroundOnly…
#   两条用例**单独跑都在 30–60 秒内通过**。所以不是某条用例有 bug，是同一个
#   xcodebuild 进程跑到一定量之后进入了某种状态，下一条用例就再也出不来。
#   根因未查明（见记忆 `full-test-run-hangs-on-one-deadline-case`）。
#
#   `device-test.sh` 的停滞看门狗能把它抓住并点名（不会再无限挂），但**抓住不等于跑完** ——
#   那一轮后面的用例仍然一条没跑。要拿到完整结果，只能让每一批用**各自独立的
#   xcodebuild 进程**跑，状态不跨批累积。
#
#   实测：同样这些用例，分批跑 **1379 passed / 0 failed**，一次没挂。
#
# 用法：
#   scripts/device-test-all.sh              # 单测 + UI 测试
#   scripts/device-test-all.sh --unit-only  # 只跑单测
#   AIDRUN_DEVICE_ID=<UDID> scripts/device-test-all.sh   # 指定设备，同 device-test.sh
#
# 退出码：任一批有失败用例就返回 1。汇总表永远会打印完。

cd "$(dirname "$0")/.."

UNIT_ONLY=0
[ "${1:-}" = "--unit-only" ] && UNIT_ONLY=1

# 单测按 suite 分 4 批。`blindRunTests` 自己就有 300+ 条，单独一批。
# 批次大小刻意保守（每批远低于观测到的 538 条挂死点）——批多一点的代价只是多几次
# 编译缓存命中，比跑到一半挂掉便宜得多。
UNIT_SUITES="$(grep -rhoE '(final +)?class +[A-Za-z0-9_]+ *: *XCTestCase' blindRunTests \
  | sed -E 's/.*class +([A-Za-z0-9_]+).*/\1/' | sort -u)"
UI_SUITES="$(grep -rhoE '(final +)?class +[A-Za-z0-9_]+ *: *XCTestCase' blindRunUITests \
  | sed -E 's/.*class +([A-Za-z0-9_]+).*/\1/' | sort -u)"

TOTAL_PASS=0
TOTAL_FAIL=0
FAILED_BATCHES=""

run_batch() {
  local label="$1" target="$2"; shift 2
  local args=()
  for s in "$@"; do args+=("-only-testing:${target}/${s}"); done

  echo
  echo "════ $label（$# 个 suite）════"
  local out line
  out="$(scripts/device-test.sh "${args[@]}" 2>&1)"

  # 统计行由 device-test.sh 从 result bundle 产出，是权威来源（不是数日志）。
  line="$(printf '%s\n' "$out" | grep -E 'passed=[0-9]+ ' | tail -n 1)"

  # 没有统计行 = 这一批没跑到底，绝大多数是停滞看门狗把挂死的那条掐了。
  # **重试一次**：分批把挂死概率压低了但没消除（2026-09-19 实测分 4 批仍有 1 批中招），
  # 而挂死是随机的 —— 同样的用例单独跑、或换一次进程跑，都能过。
  # 只重一次：连挂两次就不是随机了，那时要的是人去看，不是脚本继续刷。
  if [ -z "$line" ]; then
    echo "  ⚠️ 没拿到统计行，多半是挂死被看门狗掐了。原因："
    printf '%s\n' "$out" | grep -A2 -E '^\[device-test\] ERROR' | sed 's/^/    /' | head -n 8
    echo "  ↻ 重试这一批（挂死是随机的，重试通常能过）…"
    out="$(scripts/device-test.sh "${args[@]}" 2>&1)"
    line="$(printf '%s\n' "$out" | grep -E 'passed=[0-9]+ ' | tail -n 1)"
  fi

  if [ -z "$line" ]; then
    echo "  ❌ 重试后仍没有统计行 —— 按失败处理，这一批的结果不可用。"
    printf '%s\n' "$out" | grep -A2 -E '^\[device-test\] ERROR' | sed 's/^/    /' | head -n 8
    FAILED_BATCHES="${FAILED_BATCHES}\n  · ${label}（连续两次没跑到底）"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
    return
  fi

  echo "  $line"
  local p f
  p="$(printf '%s' "$line" | sed -E 's/.*passed=([0-9]+).*/\1/')"
  f="$(printf '%s' "$line" | sed -E 's/.*failed=([0-9]+).*/\1/')"
  TOTAL_PASS=$((TOTAL_PASS + p))
  TOTAL_FAIL=$((TOTAL_FAIL + f))
  if [ "$f" -ne 0 ]; then
    FAILED_BATCHES="${FAILED_BATCHES}\n  · ${label}：${f} 条"
    # 失败用例明细。**不要**只 grep `    test…` 那种形状 —— bundle 级失败
    # （runner 装不上 / signal kill / 设备掉线）打出来的根本不是用例行，
    # 那一类会表现为 `total=1 failed=1` 且明细为空，看着像「有一条用例红了」，
    # 实际是**整批一条都没跑**。2026-09-19 实测撞到一次（blindRunTests 批
    # 从 317 条变成 total=1），当时因为模式太窄而查不出原因。
    printf '%s\n' "$out" | sed -n '/失败用例/,$p' | head -n 22 | sed 's/^/  /'
    # total 远小于该批 suite 数时，多半根本不是「用例失败」。
    local t
    t="$(printf '%s' "$line" | sed -E 's/.*\(total=([0-9]+)\).*/\1/')"
    if [ "$t" -le "$#" ]; then
      echo "  🚩 total=${t} 但这一批有 $# 个 suite —— 这不是用例失败，是整批没跑起来。"
      echo "     按错误签名分诊，别去查代码（见记忆 ui-test-runner-needs-usb-not-wifi）。"
    fi
  fi
}

# ---- 单测 ----
# blindRunTests 单独一批，其余平均分 3 批。
BIG="blindRunTests"
REST="$(printf '%s\n' "$UNIT_SUITES" | grep -vx "$BIG" || true)"
REST_COUNT="$(printf '%s\n' "$REST" | grep -c . || true)"
PER=$(( (REST_COUNT + 2) / 3 ))

run_batch "单测 1/4" blindRunTests "$BIG"
i=0; batch=()
n=1
while IFS= read -r s; do
  [ -z "$s" ] && continue
  batch+=("$s"); i=$((i+1))
  if [ "$i" -ge "$PER" ]; then
    n=$((n+1)); run_batch "单测 ${n}/4" blindRunTests "${batch[@]}"
    batch=(); i=0
  fi
done <<< "$REST"
[ "${#batch[@]}" -gt 0 ] && { n=$((n+1)); run_batch "单测 ${n}/4" blindRunTests "${batch[@]}"; }

# ---- UI 测试 ----
# UI 测试每个 suite 一批：它们本来就少，而且每批之间 App 会重装重启，
# 正好把「状态不跨批累积」这件事做实。
if [ "$UNIT_ONLY" -eq 0 ]; then
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    run_batch "UI · $s" blindRunUITests "$s"
  done <<< "$UI_SUITES"
fi

echo
echo "════════ 汇总 ════════"
echo "  passed=${TOTAL_PASS}  failed=${TOTAL_FAIL}"
if [ -n "$FAILED_BATCHES" ]; then
  printf '  有失败的批次：%b\n' "$FAILED_BATCHES"
  exit 1
fi
echo "  全部通过。"
