#!/usr/bin/env bash
# git post-checkout 钩子：新 worktree 缺 LocalConfig.xcconfig 时，从主 worktree 复制一份。
# 由 scripts/install-git-hooks.sh 装进 .git/hooks/post-checkout；自测 scripts/validate-worktree-localconfig.mjs。
#
# 为什么需要它：LocalConfig.xcconfig 装高德 key，在 .gitignore 里，`git worktree add`
# 出来的副本没有它 ⇒ xcodebuild 在工程解析阶段就红。Claude Code 桌面 App 每个会话都开一个
# 新 worktree，所以每次都缺，只能让用户手动 cp。Claude 自己建不了这个文件：
# `.claude/settings.json` 的 `deny: Edit(./LocalConfig.xcconfig)` 是故意的（不让 key 进对话）。
# 这里是 git 在复制，不经过 Claude —— key 不进上下文，deny 规则原样保留。
#
# git 在 `worktree add` 以及每次 checkout 之后跑本钩子，cwd 是工作树根。
# 已有文件一律不动；任何情况都 exit 0 —— 钩子出错不该让 checkout 失败。

dest="$PWD/LocalConfig.xcconfig"
[ -f "$dest" ] && exit 0

common_dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || exit 0
src="$(dirname "$common_dir")/LocalConfig.xcconfig"
[ "$src" = "$dest" ] && exit 0

if [ -f "$src" ]; then
  cp "$src" "$dest" && echo "[post-checkout] 已从主 worktree 复制 LocalConfig.xcconfig（高德 key，不入库）"
else
  echo "[post-checkout] ⚠ 主 worktree 也没有 LocalConfig.xcconfig（$src），编译前先照 LocalConfig.xcconfig.example 建一份"
fi
exit 0
