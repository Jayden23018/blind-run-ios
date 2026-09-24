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
# 而不是读 ../demo 的工作区文件（那是共享 checkout，随时带着别人的 WIP）。见 scripts/hooks/pre-push.sh 的 backend_file。

# 用 --git-path 而不是写死 .git/hooks/：在 worktree 里 .git 是个文件，写死会报
# 「Not a directory」装不上。--git-path 在普通 clone 里就回显 .git/hooks/pre-push，行为不变。
HOOK="$(git rev-parse --git-path hooks/pre-push)"

# 只装一个壳，正文在工作树的 scripts/hooks/pre-push.sh（入库，跟着当前分支走）。
# ⚠️ 别改回「把正文 heredoc 复制进 .git/hooks」：那是一份快照，停在最后一次跑安装脚本的那个分支上。
# 2026-09-24 实测装着的是一个还没合并的 PR 分支上的版本；更早 2026-08-07 因此在别的分支上
# push 报 `Cannot find module`（workflow-review-20260924 A3）。后端仓库一直是这种壳写法。
cat > "$HOOK" <<'STUB'
#!/usr/bin/env bash
# 壳：由 scripts/install-git-hooks.sh 生成。正文在工作树里，改钩子改 scripts/hooks/pre-push.sh。
script="$(git rev-parse --show-toplevel)/scripts/hooks/pre-push.sh"
if [ ! -f "$script" ]; then
  echo "[pre-push] ⚠ 本分支没有 scripts/hooks/pre-push.sh（早于 2026-09-24 的分支），一道门禁都没跑。这不算通过。"
  exit 0
fi
exec bash "$script" "$@"
STUB
chmod +x "$HOOK"
echo "已安装 $HOOK"

# ── post-checkout：新 worktree 自动带上 LocalConfig.xcconfig ─────────────────────
#
# 2026-09-23 立：桌面 App 每个会话一个新 worktree，LocalConfig.xcconfig 不入库 ⇒ 每次都缺，
# 而 Claude 被 deny 规则挡着建不了它（那条规则是对的），于是每次都要用户手动 cp。
# 钩子本体入库在 scripts/hooks/，理由与说明写在它自己的头注释里；自测 scripts/validate-worktree-localconfig.mjs。
# 已有别的 post-checkout 钩子时不覆盖，明说没装。
POST_CHECKOUT="$(git rev-parse --git-path hooks/post-checkout)"
POST_CHECKOUT_SRC="$(dirname "$0")/hooks/post-checkout-localconfig.sh"
if [ -f "$POST_CHECKOUT" ] && ! cmp -s "$POST_CHECKOUT" "$POST_CHECKOUT_SRC"; then
  echo "⚠ 没装 post-checkout：$POST_CHECKOUT 已有别的内容。新 worktree 需要手动复制 LocalConfig.xcconfig。"
else
  cp "$POST_CHECKOUT_SRC" "$POST_CHECKOUT"
  chmod +x "$POST_CHECKOUT"
  echo "已安装 $POST_CHECKOUT（新 worktree 自动复制 LocalConfig.xcconfig）"
fi

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
