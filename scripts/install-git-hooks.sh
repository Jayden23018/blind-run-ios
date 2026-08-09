#!/usr/bin/env bash
set -euo pipefail

# 装 pre-push 钩子。.git/hooks 不入库，所以每台机器跑一次这个脚本。
#
# 为什么本地也要拦：契约覆盖校验在 CI 里需要 BACKEND_REPO_TOKEN 才能拿到后端 spec。
# 后端仓库私有、且与本仓库不同 owner，而本仓库的 admin 不是我们 —— secret 配不上，
# 所以这 4 个契约门禁（契约覆盖 / 生成代码比对 / 错误码对撞 / 黄金语料）**只在这里跑**，
# CI 上永远是 warning 空过。本地的 ../demo 是真的能读到的，这一环在本地补是唯一选择。
#
# 正因为是唯一一道，它读的必须是契约本身 —— 所以是从后端仓库的 origin/main 取，
# 而不是读 ../demo 的工作区文件（那是共享 checkout，随时带着别人的 WIP）。见下面 backend_file。

# 用 --git-path 而不是写死 .git/hooks/：在 worktree 里 .git 是个文件，写死会报
# 「Not a directory」装不上。--git-path 在普通 clone 里就回显 .git/hooks/pre-push，行为不变。
HOOK="$(git rev-parse --git-path hooks/pre-push)"

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

# 校验脚本存在与否**随分支变化**，而 .git/hooks 不随 `git checkout` 变化。
# 于是在 A 分支装的钩子，切到还没有那个校验脚本的 B 分支时会让 push 整个失败 ——
# 失败原因还是 `Cannot find module`，跟本次改动毫无关系，很容易被当成仓库坏了。
# 2026-08-07 实测踩到：`validate-xcresult-verdict.mjs` 只在它自己的分支上存在。
#
# 缺文件按「这个分支还没有这条校验」跳过，但**明说没跑**，不静默 ——
# 与下面那几条读后端仓库的门禁同一个口径：跳过不等于通过。
run_node() {
  label="$1"
  script="$2"
  if [ ! -f "$script" ]; then
    echo "[pre-push] ⚠ 跳过 $label：本分支没有 $script。这不算通过。"
    return
  fi
  run "$label" node "$script"
}

run "openspec validate --all --strict" openspec validate --all --strict --no-interactive
run_node "validate-docs" scripts/validate-docs.mjs
run_node "validate-guard（冻结文件守卫自测）" scripts/validate-guard.mjs
run_node "validate-stop-checklist（收尾钩子自测）" scripts/validate-stop-checklist.mjs
run_node "validate-session-context（开场钩子自测）" scripts/validate-session-context.mjs
run_node "validate-xcresult-verdict（真机测试判定自测）" scripts/validate-xcresult-verdict.mjs
run_node "validate-prepush-contract-source（契约来源自测）" scripts/validate-prepush-contract-source.mjs
run "swift test AidRunAPI（本机唯一不用真机的测试）" swift test --package-path Packages/AidRunAPI

# 下面这几道门禁读的后端契约文件（3 份，4 道门禁），
# **一律取自后端仓库的 origin/main，不是 ../demo 的工作区文件**。
#
# 为什么不能读工作区：../demo 是共享 checkout，随时可能停在某个特性分支、或带着同事
# 未提交的契约 WIP。而 CI 是从后端默认分支拉契约的（verify.yml 把 ref: main checkout
# 到 .backend）。拿工作区文件当契约，两个方向都会给出错误结论：
#   - 门禁绿、CI 红 —— WIP 里有的字段上游根本没有；
#   - 门禁红，还照它说的「把重新生成的结果一起提交」—— 等于把别人未合并的契约烘进自己的 PR。
# 2026-08-09 实测踩到的是后者。
#
# 旧版本靠一道「../demo 必须与 origin/main 一致」的新鲜度检查挡这件事，删掉了，因为：
# 直接读 origin/main 之后它无事可挡；而它给的修法 `checkout main && pull` 在共享 checkout
# 上是叫人清掉同事的工作区；且它只拦 push，拦不住「读错文件」本身（AIDRUN_ALLOW_BACKEND_DRIFT=1
# 会跳过它，却不影响读哪份文件 —— 那正是这个坑最容易踩的地方）。
#
# 确实要拿未合并的后端改动验证 iOS 侧：AIDRUN_ALLOW_BACKEND_DRIFT=1 git push
# ——现在它的含义就是字面意思「改读工作区文件」。也可以用 AIDRUN_API_SPEC= 等变量逐个指定路径。
# fetch 失败（离线）就拿手上已有的 origin/main 比，不因为没网就拦住 push。
BACKEND_DIR="${AIDRUN_BACKEND_DIR:-../demo}"
BACKEND_WORKTREE="${AIDRUN_ALLOW_BACKEND_DRIFT:-0}"
BACKEND_TMP="$(mktemp -d 2>/dev/null)" || BACKEND_TMP="/tmp/aidrun-prepush-contract.$$"
mkdir -p "$BACKEND_TMP"
trap 'rm -rf "$BACKEND_TMP"' EXIT

if [ "$BACKEND_WORKTREE" = "1" ]; then
  BACKEND_SOURCE="$BACKEND_DIR 的工作区"
  echo "[pre-push] ⚠ 按 AIDRUN_ALLOW_BACKEND_DRIFT=1 读 $BACKEND_SOURCE，不是 origin/main。结论不代表上游。"
else
  BACKEND_SOURCE="$BACKEND_DIR 的 origin/main"
  git -C "$BACKEND_DIR" fetch --quiet origin main 2>/dev/null || true
fi

# 回显本次要用的契约文件路径；取不到回显空串（调用方按「读不到」处理）。
#   $1 后端仓库内的相对路径   $2 落地文件名   $3 显式覆盖（环境变量值，可为空）
backend_file() {
  if [ -n "$3" ]; then echo "$3"; return; fi
  if [ "$BACKEND_WORKTREE" = "1" ]; then
    [ -f "$BACKEND_DIR/$1" ] && echo "$BACKEND_DIR/$1"
    return
  fi
  dest="$BACKEND_TMP/$2"
  git -C "$BACKEND_DIR" show "origin/main:$1" >"$dest" 2>/dev/null && [ -s "$dest" ] && echo "$dest"
}

# 报错信息里得说清这份文件到底哪来的，否则「取自 origin/main」会盖在一个显式指定的
# 路径上 —— 那正是本次要根治的那类误导。$1 环境变量的值，$2 环境变量名。
source_label() { if [ -n "$1" ]; then echo "$2 指定的 $1"; else echo "$BACKEND_SOURCE"; fi; }

# 契约覆盖：只有能读到后端 spec 时才跑，读不到就明说没跑，不假装通过。
SPEC="$(backend_file docs/api_spec.yaml api_spec.yaml "${AIDRUN_API_SPEC:-}")"
SPEC_SOURCE="$(source_label "${AIDRUN_API_SPEC:-}" AIDRUN_API_SPEC)"
if [ -f "$SPEC" ]; then
  run "validate-spec-coverage" node scripts/validate-spec-coverage.mjs "$SPEC"

  # 契约改了却忘了重新生成，生成代码就成了过期快照 —— 那比没有更糟，因为它看起来还是绿的。
  # 用 status --porcelain 而不是 diff：diff 看不见未跟踪文件，契约新增路径时会漏。
  GEN_DIR="Packages/AidRunAPI/Sources/AidRunAPI"
  echo "[pre-push] 重新生成 API 客户端并比对（契约取自 $SPEC_SOURCE）"
  if scripts/generate-api-client.sh "$SPEC" >/tmp/aidrun-prepush.log 2>&1; then
    DIRTY="$(git status --porcelain -- "$GEN_DIR")"
    if [ -n "$DIRTY" ]; then
      if [ "$BACKEND_WORKTREE" = "1" ] || [ -n "${AIDRUN_API_SPEC:-}" ]; then
        # 这份契约不是 origin/main 的版本，所以这里的「不同步」不构成提交理由 ——
        # 提交它就是把未合并的契约烘进 PR，而 CI 从后端默认分支拉契约，两边必然对不上。
        echo "[pre-push] ✗ 生成代码与这份**非 origin/main** 的契约不同步。别提交重新生成的结果："
        echo "$DIRTY"
        echo "      本次读的是 $SPEC_SOURCE"
        echo "      丢弃刚生成的结果：git checkout -- $GEN_DIR"
        echo "      只是想把 iOS 侧改动推上去：unset AIDRUN_ALLOW_BACKEND_DRIFT AIDRUN_API_SPEC 再 push（默认就按 origin/main 验）"
      else
        echo "[pre-push] ✗ 生成代码与契约不同步，把重新生成的结果一起提交："
        echo "$DIRTY"
      fi
      fail=1
    fi
  else
    echo "[pre-push] ✗ 生成失败："; tail -n 15 /tmp/aidrun-prepush.log; fail=1
  fi
else
  echo "[pre-push] ⚠ 跳过契约覆盖校验与生成代码比对：从 $SPEC_SOURCE 取不到 docs/api_spec.yaml。这不算通过。"
fi

CORPUS="$(backend_file docs/voice-golden-corpus.json voice-golden-corpus.json "${AIDRUN_GOLDEN_CORPUS:-}")"
if [ -f "$CORPUS" ]; then
  run "validate-golden-corpus" node scripts/validate-golden-corpus.mjs "$CORPUS"
else
  echo "[pre-push] ⚠ 跳过黄金语料对齐：从 $(source_label "${AIDRUN_GOLDEN_CORPUS:-}" AIDRUN_GOLDEN_CORPUS) 取不到 docs/voice-golden-corpus.json。这不算通过。"
fi

CODES="$(backend_file src/main/java/com/example/demo/exception/ErrorCode.java ErrorCode.java "${AIDRUN_BACKEND_ERROR_CODES:-}")"
if [ -f "$CODES" ]; then
  run "validate-error-codes" node scripts/validate-error-codes.mjs "$CODES"
else
  echo "[pre-push] ⚠ 跳过错误码对撞：从 $(source_label "${AIDRUN_BACKEND_ERROR_CODES:-}" AIDRUN_BACKEND_ERROR_CODES) 取不到 ErrorCode.java。这不算通过。"
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
