#!/usr/bin/env bash
set -euo pipefail

# 装 pre-push 钩子。.git/hooks 不入库，所以每台机器跑一次这个脚本。
#
# 为什么本地也要拦：契约覆盖校验在 CI 里需要 BACKEND_REPO_TOKEN 才能拿到后端 spec。
# 后端仓库私有、且与本仓库不同 owner，而本仓库的 admin 不是我们 —— secret 配不上，
# 所以这 4 个契约门禁（契约覆盖 / 生成代码比对 / 错误码对撞 / 黄金语料）**只在这里跑**，
# CI 上永远是 warning 空过。本地的 ../demo 是真的能读到的，这一环在本地补是唯一选择。
#
# 正因为是唯一一道，它读的那份后端 checkout 必须是契约本身 —— 见下面的新鲜度检查。

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

# 后端 checkout 的新鲜度。下面 4 个门禁的结论，只和它们读到的那份契约一样可信 ——
# ../demo 停在某个特性分支、或工作区脏着，门禁照样报绿，校验的却不是契约。
# 这不是假想：2026-08-06 那次 ../demo 正停在 docs/spec-required-fields 上。
# CI 上这 4 条是 warning 空过（secret 配不上），所以这里是唯一一道，读错等于没读。
#
# fetch 失败（离线）就拿手上已有的 origin/main 比，不因为没网就拦住 push。
# 确实在拿未合并的后端改动验证 iOS 侧：AIDRUN_ALLOW_BACKEND_DRIFT=1 git push
BACKEND_DIR="${AIDRUN_BACKEND_DIR:-../demo}"
if [ -d "$BACKEND_DIR/.git" ] && [ "${AIDRUN_ALLOW_BACKEND_DRIFT:-0}" != "1" ]; then
  git -C "$BACKEND_DIR" fetch --quiet origin main 2>/dev/null || true
  if git -C "$BACKEND_DIR" rev-parse --verify -q origin/main >/dev/null 2>&1; then
    echo "[pre-push] 后端 checkout 与 origin/main 一致性"
    drift=""
    for f in docs/api_spec.yaml docs/voice-golden-corpus.json \
             src/main/java/com/example/demo/exception/ErrorCode.java; do
      git -C "$BACKEND_DIR" diff --quiet origin/main -- "$f" || drift="$drift $f"
    done
    if [ -n "$drift" ]; then
      echo "[pre-push] ✗ 后端 checkout 与 origin/main 不一致，下面的门禁校验的不是契约本身："
      for f in $drift; do echo "      $f"; done
      echo "      $BACKEND_DIR 当前在 $(git -C "$BACKEND_DIR" rev-parse --abbrev-ref HEAD)"
      echo "      修：git -C $BACKEND_DIR checkout main && git -C $BACKEND_DIR pull"
      echo "      确实在验证未合并的后端改动：AIDRUN_ALLOW_BACKEND_DRIFT=1 git push"
      fail=1
    fi
  else
    echo "[pre-push] ⚠ $BACKEND_DIR 没有 origin/main 引用，跳过新鲜度检查。这不算通过。"
  fi
fi

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

# ── 双推：上游 + fork ───────────────────────────────────────────────────────
#
# 那 4 条契约门禁在上游仓库跑不了（配不了 secret，见 AGENTS.md 第 11 节），
# 只在 fork 上真跑。于是「推了上游、忘了 fork」= 那套 CI 等于没配。
#
# 靠记性挡不住这种事（第 1 节说的就是它），所以让 `git push origin` 一次推两个地方，
# 而不是写一句「记得两边都推」。
#
# 只在**已经有 fork remote** 的机器上生效 —— 不替别人凭空造一个指向某人 fork 的推送。
# 需要它的机器先执行一次：
#   git remote add fork https://github.com/<你的账号>/blind-run-ios.git
FORK_URL="$(git remote get-url fork 2>/dev/null || true)"
if [ -n "$FORK_URL" ]; then
  UPSTREAM_URL="$(git remote get-url origin)"
  # 先清空再加两条，重复执行不会越堆越多
  git remote set-url --delete --push origin '.*' 2>/dev/null || true
  git remote set-url --add --push origin "$UPSTREAM_URL"
  git remote set-url --add --push origin "$FORK_URL"
  echo "已配置双推：git push origin → $UPSTREAM_URL + $FORK_URL"
else
  echo "未配置双推：没有名为 fork 的 remote。若 CI 在 fork 上跑，先 git remote add fork <URL> 再重跑本脚本。"
fi
