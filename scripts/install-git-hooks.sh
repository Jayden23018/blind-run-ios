#!/usr/bin/env bash
set -euo pipefail

# 装 pre-push 钩子。.git/hooks 不入库，所以每台机器跑一次这个脚本。
#
# 为什么本地也要拦：契约覆盖校验在 CI 里需要 BACKEND_REPO_TOKEN 才能拿到后端 spec，
# 没配就会跳过。本地的 ../demo 是真的能读到的，所以这一环在本地补最划算。

HOOK=".git/hooks/pre-push"

cat > "$HOOK" <<'HOOK_BODY'
#!/usr/bin/env bash
set -uo pipefail

# 跳过：AIDRUN_SKIP_PREPUSH=1 git push
if [ "${AIDRUN_SKIP_PREPUSH:-0}" = "1" ]; then
  echo "[pre-push] 已按 AIDRUN_SKIP_PREPUSH=1 跳过校验"
  exit 0
fi

fail=0
run() {
  echo "[pre-push] $1"
  shift
  "$@" >/tmp/aidrun-prepush.log 2>&1 || { echo "[pre-push] ✗ 失败："; tail -n 15 /tmp/aidrun-prepush.log; fail=1; }
}

run "openspec validate --all --strict" openspec validate --all --strict --no-interactive
run "validate-docs" node scripts/validate-docs.mjs
run "validate-guard（冻结文件守卫自测）" node scripts/validate-guard.mjs
run "validate-stop-checklist（收尾钩子自测）" node scripts/validate-stop-checklist.mjs
run "swift test AidRunAPI（本机唯一不用真机的测试）" swift test --package-path Packages/AidRunAPI

# 契约覆盖：只有能读到后端 spec 时才跑，读不到就明说没跑，不假装通过。
SPEC="${AIDRUN_API_SPEC:-../demo/docs/api_spec.yaml}"
if [ -f "$SPEC" ]; then
  run "validate-spec-coverage" node scripts/validate-spec-coverage.mjs "$SPEC"

  # 契约改了却忘了重新生成，生成代码就成了过期快照 —— 那比没有更糟，因为它看起来还是绿的。
  # 用 status --porcelain 而不是 diff：diff 看不见未跟踪文件，契约新增路径时会漏。
  GEN_DIR="Packages/AidRunAPI/Sources/AidRunAPI"
  echo "[pre-push] 重新生成 API 客户端并比对"
  if scripts/generate-api-client.sh "$SPEC" >/tmp/aidrun-prepush.log 2>&1; then
    DIRTY="$(git status --porcelain -- "$GEN_DIR")"
    if [ -n "$DIRTY" ]; then
      echo "[pre-push] ✗ 生成代码与契约不同步，把重新生成的结果一起提交："
      echo "$DIRTY"
      fail=1
    fi
  else
    echo "[pre-push] ✗ 生成失败："; tail -n 15 /tmp/aidrun-prepush.log; fail=1
  fi
else
  echo "[pre-push] ⚠ 跳过契约覆盖校验与生成代码比对：读不到 $SPEC。这不算通过。"
fi

CORPUS="${AIDRUN_GOLDEN_CORPUS:-../demo/docs/voice-golden-corpus.json}"
if [ -f "$CORPUS" ]; then
  run "validate-golden-corpus" node scripts/validate-golden-corpus.mjs "$CORPUS"
else
  echo "[pre-push] ⚠ 跳过黄金语料对齐：读不到 $CORPUS。这不算通过。"
fi

CODES="${AIDRUN_BACKEND_ERROR_CODES:-../demo/src/main/java/com/example/demo/exception/ErrorCode.java}"
if [ -f "$CODES" ]; then
  run "validate-error-codes" node scripts/validate-error-codes.mjs "$CODES"
else
  echo "[pre-push] ⚠ 跳过错误码对撞：读不到 $CODES。这不算通过。"
fi

if [ "$fail" -ne 0 ]; then
  echo "[pre-push] 校验未通过，push 已中止。确需绕过：AIDRUN_SKIP_PREPUSH=1 git push"
  exit 1
fi

echo "[pre-push] 全部通过。提醒：编译通过 ≠ 测试通过，真机跑测用 scripts/device-test.sh。"
HOOK_BODY

chmod +x "$HOOK"
echo "已安装 $HOOK"
