#!/usr/bin/env bash
set -euo pipefail

# 装 pre-push 钩子。.git/hooks 不入库，所以每台机器跑一次这个脚本。
#
# 为什么本地也要拦：那 5 个契约门禁（契约覆盖 / 生成代码比对 / 错误码对撞 / 黄金语料 /
# 确认轮词表）在 CI 里需要 BACKEND_REPO_TOKEN 才能拿到后端 spec。主线仓库
# `Jayden23018/blind-run-ios` 配了这个 secret，所以那边真跑；但那是 push 之后才知道结果，
# 而本地的 ../demo 本来就读得到 —— 在这里拦住，比推上去等 CI 红一轮便宜。
# `JerryZhao-1/blind-run-ios` 那边配不上 secret（不是 admin），这 5 条是 warning 空过。
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

# git 跑钩子时会导出 GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE，指向**本仓库**。
# 它们会污染钩子里所有子进程的 git：SwiftPM 解析依赖时要 git clone/checkout 到自己的
# 缓存目录，带着 GIT_WORK_TREE 就报 `fatal: this operation must be run in a work tree`，
# 于是 `swift test` 在任何冷缓存的机器上必挂 —— 热缓存时不触发，所以一直没被发现。
# 2026-08-09 实测：同一个包、同一台机器，unset 后 17s 编完，不 unset 一条依赖都拉不下来。
# 本钩子自己用的 git 命令都在仓库根跑，靠 cwd 就能发现仓库，不需要这些变量。
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PREFIX GIT_COMMON_DIR GIT_NAMESPACE

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
run_node "validate-research-log（调研落盘钩子自测）" scripts/validate-research-log.mjs
run_node "validate-shared-checkout-guard（共享 checkout 守卫自测）" scripts/validate-shared-checkout-guard.mjs
run_node "validate-xcresult-verdict（真机测试判定自测）" scripts/validate-xcresult-verdict.mjs
run_node "validate-drift-fields（契约漂移字段归属自测）" scripts/validate-drift-fields.mjs
run_node "validate-prepush-contract-source（契约来源自测）" scripts/validate-prepush-contract-source.mjs
run "swift test AidRunAPI（本机唯一不用真机的测试）" swift test --package-path Packages/AidRunAPI

# 下面这几道门禁读的后端契约文件（5 份，5 道门禁），
# **一律取自后端仓库的 origin/main，不是 ../demo 的工作区文件**。
#
# ⚠️ **这张清单必须覆盖每一个门禁真正读的后端文件。** 少列一个，那个门禁就会回退成读工作区，
# 于是能悄悄拿未合并的分支报绿 —— 2026-08-10 新加 validate-voice-intent-words 时就漏了它读的
# 两个 .java（当次是 api_spec.yaml 恰好也漂了才被旧的新鲜度检查拦下，纯属运气）。加门禁时一起加这里。
#
# 读错文件的代价是双向的，两个方向都实际发生过：
#   - 2026-08-06 / 08-10：../demo 停在特性分支，门禁拿未合并的契约报绿；
#   - 2026-08-12：../demo 停在 feat/voice-query-intent（语料 96 条，origin/main 已 101 条），
#     门禁把一份**正确**的语料镜像改动报成「后端语料里已不存在」，差点被据此删掉。
#     方向最坏的那种错误 —— 把对的判成错的。
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
# `../demo` 相对于**主 worktree**解析，不是相对于当前 worktree。
#
# 2026-08-14 踩到：为了不打扰并行会话，在 /tmp/aidrun-pr8 开了个隔离 worktree 解冲突，
# 从那里 push —— `../demo` 变成 `/tmp/demo`，不存在，于是读后端契约的 4 条门禁**全部跳过**，
# 而末行照样打印「全部通过」。隔离 worktree 恰恰是本仓库推荐的复验方式
# （记忆 `shared-checkout-concurrent-colleague-edits`），所以这条会反复发生。
# `--git-common-dir` 在任何 worktree 里都指向主仓库的 .git，它的父目录就是主 worktree。
BACKEND_DIR="${AIDRUN_BACKEND_DIR:-}"
if [ -z "$BACKEND_DIR" ]; then
  BACKEND_DIR="../demo"
  if _common_git_dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
    BACKEND_DIR="$(dirname "$(dirname "$_common_git_dir")")/demo"
  fi
fi
BACKEND_WORKTREE="${AIDRUN_ALLOW_BACKEND_DRIFT:-0}"

# 有没有门禁被跳过。跳过不等于失败（离线、没有后端 checkout 都是合理的），
# 但**绝不能汇报成「全部通过」** —— 那正是上面那次事故里最危险的一环：
# 4 行 ⚠「这不算通过」之后紧跟一行「全部通过」，只看末行的人会以为验过了。
SKIPPED_GATES=0
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
        echo "[pre-push] ✗ 生成代码与契约不同步。**重新生成的结果已经在你工作区里了**，"
        echo "      不用再跑任何生成命令，直接 git add + commit 即可："
        echo "$DIRTY"
        # 只报「不同步」不够：生成代码不投入运行时，契约新增的字段落没落到手写模型
        # 才是真问题。这一步不需要人记得去查，红的时候直接把答案打出来。
        node scripts/report-drift-fields.mjs || true
      fi
      fail=1
    fi
  else
    echo "[pre-push] ✗ 生成失败："; tail -n 15 /tmp/aidrun-prepush.log; fail=1
  fi
else
  echo "[pre-push] ⚠ 跳过契约覆盖校验与生成代码比对：从 $SPEC_SOURCE 取不到 docs/api_spec.yaml。这不算通过。"
  SKIPPED_GATES=$((SKIPPED_GATES + 1))
fi

CORPUS="$(backend_file docs/voice-golden-corpus.json voice-golden-corpus.json "${AIDRUN_GOLDEN_CORPUS:-}")"
if [ -f "$CORPUS" ]; then
  run "validate-golden-corpus" node scripts/validate-golden-corpus.mjs "$CORPUS"
else
  echo "[pre-push] ⚠ 跳过黄金语料对齐：从 $(source_label "${AIDRUN_GOLDEN_CORPUS:-}" AIDRUN_GOLDEN_CORPUS) 取不到 docs/voice-golden-corpus.json。这不算通过。"
  SKIPPED_GATES=$((SKIPPED_GATES + 1))
fi

CODES="$(backend_file src/main/java/com/example/demo/exception/ErrorCode.java ErrorCode.java "${AIDRUN_BACKEND_ERROR_CODES:-}")"
if [ -f "$CODES" ]; then
  run "validate-error-codes" node scripts/validate-error-codes.mjs "$CODES"
else
  echo "[pre-push] ⚠ 跳过错误码对撞：从 $(source_label "${AIDRUN_BACKEND_ERROR_CODES:-}" AIDRUN_BACKEND_ERROR_CODES) 取不到 ErrorCode.java。这不算通过。"
  SKIPPED_GATES=$((SKIPPED_GATES + 1))
fi

# 这一道读两个 .java：VoiceSlotParser（INTENT_* 正则）与 VoiceOrderService（序数播报用词）。
# 两个都必须走 backend_file —— 2026-08-12 合 #16 时发现它俩漏在外面，仍直接指向工作区路径，
# 于是第 5 道门禁会绕过「取自 origin/main」这条约定，正是本文件上面那段注释警告的情形。
VOICE_PARSER="$(backend_file src/main/java/com/example/demo/util/VoiceSlotParser.java VoiceSlotParser.java "${AIDRUN_BACKEND_VOICE_PARSER:-}")"
VOICE_SERVICE="$(backend_file src/main/java/com/example/demo/service/VoiceOrderService.java VoiceOrderService.java "${AIDRUN_BACKEND_VOICE_SERVICE:-}")"
if [ -f "$VOICE_PARSER" ] && [ -f "$VOICE_SERVICE" ]; then
  run "validate-voice-intent-words" env AIDRUN_BACKEND_VOICE_SERVICE="$VOICE_SERVICE" \
    node scripts/validate-voice-intent-words.mjs "$VOICE_PARSER"
else
  echo "[pre-push] ⚠ 跳过确认轮词表对撞：从 $(source_label "${AIDRUN_BACKEND_VOICE_PARSER:-}" AIDRUN_BACKEND_VOICE_PARSER) 取不到 VoiceSlotParser.java / VoiceOrderService.java。这不算通过。"
  SKIPPED_GATES=$((SKIPPED_GATES + 1))
fi

if [ "$fail" -ne 0 ]; then
  echo "[pre-push] 校验未通过，push 已中止。确需绕过：AIDRUN_SKIP_PREPUSH=1 git push"
  exit 1
fi

if [ "$SKIPPED_GATES" -ne 0 ]; then
  echo "[pre-push] 跑过的都通过了，但**有 $SKIPPED_GATES 道读后端契约的门禁被跳过（见上面的 ⚠）**，不等于契约对过了。"
  echo "          最常见的原因是 $BACKEND_DIR 不存在或不是后端 checkout；用 AIDRUN_BACKEND_DIR= 指到正确路径。"
else
  echo "[pre-push] 全部通过。提醒：编译通过 ≠ 测试通过，真机跑测用 scripts/device-test.sh。"
fi
HOOK_BODY

chmod +x "$HOOK"
echo "已安装 $HOOK"

# ── 推送目标：只推 origin ───────────────────────────────────────────────────
#
# 2026-08-12 起主线就是 `origin`（`Jayden23018/blind-run-ios`），那 5 条契约门禁在它的 CI 上真跑，
# `JerryZhao-1/blind-run-ios` 退成 `upstream`、不再是投递目标。见 AGENTS.md 第 11 节。
#
# 此前这里配过「一次推上游 + fork」的双推。那条配置写在 .git/config 里，不随 checkout 变化，
# 留着会继续把分支推去上游 —— 所以在这里清掉，而不是写一句「记得改一下 remote」。
if git config --get-all remote.origin.pushurl >/dev/null 2>&1; then
  git remote set-url --delete --push origin '.*' 2>/dev/null || true
  echo "已清除 origin 上遗留的双推配置：git push origin 现在只推 $(git remote get-url origin)"
fi
