#!/usr/bin/env bash
# 集成预览包：把「最新 origin/main + 开着的 PR」合成一个 Debug 包，装到 iPhone 上看，不用等合并。
#
#   scripts/preview-build.sh            # main + 全部开着的非草稿 PR（按 PR 号从小到大合）
#   scripts/preview-build.sh 784 790    # main + 只合这几个
#   scripts/preview-build.sh --no-pr    # 只装最新 main
#
# 为什么有它（docs/research/parallel-session-preview-build-20261106.md）：
#   - 并行会话改完，负责人要等 PR 合进 main 才能装到手机上看，合并是串行的。
#   - 会话的 worktree 默认从远端 main 切（Claude Code `worktree.baseRef: "fresh"`），
#     看不见别人还没合的 PR —— 「已删掉的功能又出现」就是这样来的。
#   做法照 GitHub merge queue：在临时的合成分支上把几个 PR 叠起来，只是检查换成「装到手机上人眼看」。
#
# 只合本仓库分支开的 PR；fork 来的 PR 不合（公开仓库，合了等于在本机执行外人的构建脚本）。
# 它只动自己的预览工作区（默认在主 checkout 旁边的 blind-run-ios-preview/）：
# 不改 main、不推送、不碰任何会话的分支。合不进去的 PR 跳过并列出冲突文件，退出码仍为 0。
#
# 环境变量（设备与签名的默认值从 scripts/device-test.sh 读，只留一个来源）：
#   AIDRUN_DEVICE_ID / AIDRUN_TEAM / AIDRUN_BUNDLE_ID_PREFIX   含义同 device-test.sh
#   AIDRUN_PREVIEW_DIR       预览工作区位置
#   AIDRUN_PREVIEW_LOCK_WAIT 等设备锁最多多少秒（默认 1800）
#   AIDRUN_PREVIEW_SKIP_INSTALL=1  只合成并编译，不装机（没插手机时验脚本用）
set -euo pipefail

say() { printf '[preview-build] %s\n' "$*"; }
die() { printf '[preview-build] ERROR: %s\n' "$*" >&2; exit 1; }

REPO_SLUG="Jayden23018/blind-run-ios"   # gh 默认会打到 upstream，一律显式带 --repo
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMMON_DIR="$(git -C "$SCRIPT_DIR" rev-parse --path-format=absolute --git-common-dir)"
MAIN_CHECKOUT="$(dirname "$COMMON_DIR")"
PREVIEW_DIR="${AIDRUN_PREVIEW_DIR:-$(dirname "$MAIN_CHECKOUT")/blind-run-ios-preview}"
LOCK_WAIT="${AIDRUN_PREVIEW_LOCK_WAIT:-1800}"
WORKSPACE="blindRun.xcworkspace"
SCHEME="blindRun"

# 从 device-test.sh 取 `NAME="${AIDRUN_X:-默认值}"` 那一行的默认值。取不到就停，别猜。
default_from_device_test() {
  local name="$1" value
  value="$(sed -n "s/^${name}=\"\\\${[A-Z_]*:-\\([^}]*\\)}\"\$/\\1/p" "$SCRIPT_DIR/device-test.sh" | head -n 1)"
  [ -n "$value" ] || die "读不到 scripts/device-test.sh 里 ${name} 的默认值（那一行的写法变了？）"
  printf '%s' "$value"
}
DEVICE_ID="${AIDRUN_DEVICE_ID:-$(default_from_device_test DEVICE_ID)}"
TEAM="${AIDRUN_TEAM:-$(default_from_device_test TEAM)}"
SIGNING_ARGS=()
if [ -n "${AIDRUN_BUNDLE_ID_PREFIX:-}" ]; then
  SIGNING_ARGS=("AIDRUN_BUNDLE_ID_PREFIX=${AIDRUN_BUNDLE_ID_PREFIX}" "CODE_SIGN_ENTITLEMENTS=")
fi

# ---------- 参数 ----------
WANT_ALL_OPEN=1
REQUESTED=()
for arg in "$@"; do
  case "$arg" in
    --no-pr) WANT_ALL_OPEN=0 ;;
    -h|--help) awk 'NR > 1 && /^#/ { print; next } NR > 1 { exit }' "$0"; exit 0 ;;
    *[!0-9]*|'') die "参数只能是 PR 号或 --no-pr，收到：$arg" ;;
    *) WANT_ALL_OPEN=0; REQUESTED+=("$arg") ;;
  esac
done

# ---------- 锁 ----------
# 两把锁：预览工作区一把（两次运行同时改同一个目录会把正在编译的源码换掉），
# 设备一把（与 device-test.sh 同名同目录，装机不打断别人的测试）。
LOCKS_HELD=()
release_locks() { local d; for d in ${LOCKS_HELD[@]+"${LOCKS_HELD[@]}"}; do rm -rf "$d"; done; }
trap release_locks EXIT
STALE_EMPTY_LOCK_SECONDS=30
acquire_lock() {   # $1 锁目录  $2 给人看的名字
  local dir="$1" what="$2" waited=0 owner age
  while ! mkdir "$dir" 2>/dev/null; do
    [ -w "$(dirname "$dir")" ] || die "建不了锁目录 ${dir}（所在目录不可写）"
    if [ ! -d "$dir" ]; then continue; fi        # 刚被释放：马上再抢
    owner="$(cat "$dir/pid" 2>/dev/null || true)"
    if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then
      rm -rf "$dir"; continue                     # 持有者已不在：回收死锁
    fi
    if [ -z "$owner" ]; then
      # 对方刚 mkdir、还没写 pid。空 pid 放久了才当死锁，免得把别人刚拿到的锁删掉。
      age=$(( $(date +%s) - $(stat -f %m "$dir" 2>/dev/null || date +%s) ))
      if [ "$age" -gt "$STALE_EMPTY_LOCK_SECONDS" ]; then rm -rf "$dir"; continue; fi
    fi
    [ "$waited" = 0 ] && say "${what}正被占用（pid ${owner:-刚建}），排队等…"
    [ "$waited" -ge "$LOCK_WAIT" ] && die "等${what}超过 ${LOCK_WAIT}s，放弃。"
    sleep 5; waited=$((waited + 5))
  done
  printf '%s\n' "$$" >"$dir/pid"
  LOCKS_HELD+=("$dir")
}
acquire_lock "${TMPDIR:-/tmp}/aidrun-preview-build.lock" "预览工作区"

# ---------- 1. 预览工作区 ----------
git -C "$MAIN_CHECKOUT" fetch -q origin main || die "取不到 origin/main（断网或连不上 GitHub）"
if [ ! -d "$PREVIEW_DIR" ]; then
  say "第一次运行：建预览工作区 $PREVIEW_DIR"
  # post-checkout 钩子会从主 checkout 复制 LocalConfig.xcconfig（scripts/install-git-hooks.sh 装的）。
  git -C "$MAIN_CHECKOUT" worktree add -q --detach "$PREVIEW_DIR" origin/main
fi
cd "$PREVIEW_DIR"
[ -f LocalConfig.xcconfig ] || die "预览工作区缺 LocalConfig.xcconfig（post-checkout 钩子没装？先跑一次 scripts/install-git-hooks.sh，
     再删掉 $PREVIEW_DIR 重来）。"

# 上次被中途掐掉可能留着半截合并。
if [ -f "$(git rev-parse --git-path MERGE_HEAD)" ]; then
  git merge --abort
fi
# pod install 可能改写 Podfile.lock；目录归本脚本管，还原它，不当成「有人手改」。
git checkout -q -- Podfile.lock 2>/dev/null || true
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  die "预览工作区 $PREVIEW_DIR 有人手改过（下面这些文件）。它只该由本脚本管理；确认不要后删掉整个目录重来：
$(git status --short --untracked-files=no | sed 's/^/     /')"
fi
git checkout -q --detach origin/main
BASE_SHA="$(git rev-parse --short origin/main)"

# ---------- 2. 选 PR ----------
# 🔒 只合本仓库分支开的 PR，fork 来的一律跳过。仓库是公开的，任何人都能从 fork 开 PR；
# 合进来就会在本机执行它的构建阶段脚本，而且带着签名团队。能在本仓库开分支的人都有写权限。
PRS=()
if [ "$WANT_ALL_OPEN" = 1 ]; then
  # 先存再判：写成 `< <(gh ...)` 时 gh 失败（没登录、令牌过期、断网）会被吞掉，看着像「没有开着的 PR」。
  if ! open_list="$(gh pr list --repo "$REPO_SLUG" --state open --base main --limit 100 \
      --json number,isDraft -q '[.[] | select(.isDraft | not) | .number] | sort | .[]' 2>&1)"; then
    die "列不出开着的 PR：${open_list}"
  fi
  while IFS= read -r n; do [ -n "$n" ] && PRS+=("$n"); done <<<"$open_list"
elif [ "${#REQUESTED[@]}" -gt 0 ]; then
  PRS=("${REQUESTED[@]}")
fi

# ---------- 3. 逐个合 ----------
MERGED=()
SKIPPED=()
for n in ${PRS[@]+"${PRS[@]}"}; do
  info="$(gh pr view "$n" --repo "$REPO_SLUG" --json isCrossRepository,state,baseRefName \
    -q '"\(.isCrossRepository) \(.state) \(.baseRefName)"' 2>/dev/null || true)"
  if [ -z "$info" ]; then
    SKIPPED+=("#${n}：查不到这个 PR（号写错，或 gh 没登录）"); continue
  fi
  read -r cross state base <<<"$info"
  if [ "$cross" != false ]; then
    SKIPPED+=("#${n}：fork 开的 PR，不在本机编译外部代码"); continue
  fi
  if [ "$state" != OPEN ]; then
    SKIPPED+=("#${n}：状态是 ${state}，不是开着的"); continue
  fi
  if [ "$base" != main ]; then
    SKIPPED+=("#${n}：目标分支是 ${base}，不是 main"); continue
  fi
  if ! git fetch -q origin "pull/$n/head" 2>/dev/null; then
    SKIPPED+=("#${n}：取不到（PR 号写错？）")
    continue
  fi
  before="$(git rev-parse HEAD)"
  if merge_out="$(git merge -q --no-ff --no-edit -m "preview: 合入 #$n" FETCH_HEAD 2>&1)"; then
    if [ "$(git rev-parse HEAD)" = "$before" ]; then
      SKIPPED+=("#${n}：改动已经都在 main 里"); continue
    fi
    MERGED+=("$n")
  else
    conflicts="$(git diff --name-only --diff-filter=U | head -n 5 | tr '\n' ' ')"
    git merge --abort 2>/dev/null || true
    if [ -n "$conflicts" ]; then
      SKIPPED+=("#${n}：冲突 ${conflicts}")
    else
      SKIPPED+=("#${n}：合并失败（不是冲突）：$(printf '%s' "$merge_out" | head -n 1)")
    fi
  fi
done

STAMP="main"
for n in ${MERGED[@]+"${MERGED[@]}"}; do STAMP="$STAMP,$n"; done

# ---------- 4. 依赖（Pods 与阿里云 SDK 不入库，只在变了时重装）----------
if ! ls Vendor/AliyunCloudAuth/*/Frameworks/AliyunFaceAuthFacade.framework/AliyunFaceAuthFacade >/dev/null 2>&1; then
  say "下载阿里云实人认证 SDK…"
  bash scripts/fetch-aliyun-cloudauth.sh >/dev/null
fi
if ! cmp -s Podfile.lock Pods/Manifest.lock 2>/dev/null; then
  say "pod install（Podfile.lock 与 Pods 不一致或第一次运行）…"
  LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 pod install >/dev/null
fi

# ---------- 5. 设备锁（与 device-test.sh 同一把）----------
DEVICE_LOCK_DIR="${TMPDIR:-/tmp}/aidrun-device-test.lock.${DEVICE_ID}"

# ---------- 6. 编译 ----------
DERIVED="$PREVIEW_DIR/.xcodebuild-derived-preview"   # 名字落在 .gitignore 的 .xcodebuild-derived*/ 里
LOG="$(mktemp -t aidrun-preview-build)"
if [ "${AIDRUN_PREVIEW_SKIP_INSTALL:-}" = 1 ]; then
  DESTINATION="generic/platform=iOS"
  BUILD_SIGNING=(CODE_SIGNING_ALLOWED=NO)
else
  acquire_lock "$DEVICE_LOCK_DIR" "设备 ${DEVICE_ID} "
  DESTINATION="platform=iOS,id=${DEVICE_ID}"
  BUILD_SIGNING=(-allowProvisioningUpdates "DEVELOPMENT_TEAM=$TEAM" ${SIGNING_ARGS[@]+"${SIGNING_ARGS[@]}"})
fi
say "编译（日志：${LOG}）…"
set +e
xcodebuild build -workspace "$WORKSPACE" -scheme "$SCHEME" -configuration Debug \
  -destination "$DESTINATION" -derivedDataPath "$DERIVED" \
  "AIDRUN_PREVIEW_PRS=$STAMP" "${BUILD_SIGNING[@]}" >"$LOG" 2>&1
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  grep -E 'error:|BUILD FAILED' "$LOG" | head -n 15 >&2 || true
  die "编译失败（xcodebuild 退出码 ${rc}）。合进去的 PR：${MERGED[*]:-无}。完整日志：$LOG"
fi

APP="$DERIVED/Build/Products/Debug-iphoneos/$SCHEME.app"
[ -d "$APP" ] || die "编译报成功却找不到 $APP"

# ---------- 7. 装机并启动 ----------
if [ "${AIDRUN_PREVIEW_SKIP_INSTALL:-}" = 1 ]; then
  say "AIDRUN_PREVIEW_SKIP_INSTALL=1：只编译，不装机。"
else
  BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
  say "装到设备 ${DEVICE_ID}…"
  xcrun devicectl device install app --device "$DEVICE_ID" "$APP" >>"$LOG" 2>&1 \
    || die "装机失败（设备没连上或签名问题，按 skill aidrun-device-test 分诊）。日志：$LOG"
  if ! xcrun devicectl device process launch --device "$DEVICE_ID" --terminate-existing "$BUNDLE_ID" >>"$LOG" 2>&1; then
    say "⚠️  已装好，但启动失败（多半是手机锁着）。解锁后手动点开 App。"
  fi
fi

# ---------- 8. 汇报 ----------
say "基点：origin/main @ $BASE_SHA"
if [ "${#MERGED[@]}" -gt 0 ]; then
  say "合进去的 PR：$(printf '#%s ' "${MERGED[@]}")"
else
  say "合进去的 PR：无（只有 main）"
fi
for s in ${SKIPPED[@]+"${SKIPPED[@]}"}; do say "⏭ 跳过 $s"; done
say "包里的标记值：AidRunPreviewPRs=${STAMP}（Debug 包顶部显示，规则见 blindRun/Core/DebugBuildStamp.swift）"
