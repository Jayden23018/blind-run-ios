#!/usr/bin/env bash
#
# 契约漂移的一键处理：取正式契约 → 重新生成 → 报告漂移。
#
#   scripts/sync-api-client.sh            # 生成并报告
#   scripts/sync-api-client.sh --check    # 只报告，生成后还原（CI / 想先看看时用）
#
# 为什么不是直接跑 generate-api-client.sh：那个脚本只做「生成」这一步，
# 它默认读 ../demo 的**工作区文件**。而工作区是共享 checkout，随时停在别人的特性分支上
# —— 2026-08-21 实测就停在 review/backend-audit-20260820。照它生成 = 把别人未合并的 WIP
# 烘进你的提交，而 pre-push 门禁比对的是后端 origin/main，两边永远对不上。
#
# 本脚本多做三件事，每一件都是踩过的坑：
#   ① 先 fetch 再读 origin/main —— 不 fetch 的话本地 ref 停在几小时前，
#      曾因此凭空报出一个不存在的高危缺陷（记忆 prepush-contract-gate-reads-backend-worktree）
#   ② 把新增字段从注释里分离出来 —— diff 的 stat 摘要行 `+16 -0` 长得像代码行，
#      按「有没有非注释行」粗判会把纯注释同步误判成有行为变更
#   ③ 交叉查这些字段在手写模型里有没有 —— 生成代码不投入运行时（见
#      Packages/AidRunAPI/Package.swift），它唯一的作用就是当漂移探测器。
#      探到了不交叉查，等于探了个寂寞

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_REPO="${AIDRUN_BACKEND_REPO:-/Users/mac/Downloads/demo}"
BACKEND_REF="${AIDRUN_BACKEND_REF:-origin/main}"
OUT_DIR="$REPO_ROOT/Packages/AidRunAPI/Sources/AidRunAPI"
CHECK_ONLY=0
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=1

if [[ ! -d "$BACKEND_REPO/.git" ]]; then
  echo "[sync-api-client] 找不到后端仓库：$BACKEND_REPO" >&2
  echo "[sync-api-client] 用 AIDRUN_BACKEND_REPO 指定，或 claude --add-dir 挂载。" >&2
  exit 1
fi

# ① 必须先 fetch。本地 ref 停在几小时前时，下面 git show 会读到旧契约，
#    然后你会「修好」一个早就不存在的漂移，或者报一个已经被后端补上的缺口。
echo "[sync-api-client] fetch 后端…"
git -C "$BACKEND_REPO" fetch origin --quiet

SPEC_SHA="$(git -C "$BACKEND_REPO" rev-parse --short "$BACKEND_REF")"
SPEC_TMP="$(mktemp -t aidrun-spec).yaml"
git -C "$BACKEND_REPO" show "$BACKEND_REF:docs/api_spec.yaml" > "$SPEC_TMP"
echo "[sync-api-client] 契约取自 $BACKEND_REF ($SPEC_SHA)，$(wc -l < "$SPEC_TMP" | tr -d ' ') 行"

WORKTREE_BRANCH="$(git -C "$BACKEND_REPO" branch --show-current || echo '(detached)')"
if [[ "$WORKTREE_BRANCH" != "main" ]]; then
  echo "[sync-api-client] 提示：后端工作区当前在 '$WORKTREE_BRANCH'，本脚本刻意不读它。"
fi

BEFORE="$(git -C "$REPO_ROOT" rev-parse HEAD)"
AIDRUN_BACKEND_SPEC="$SPEC_TMP" "$REPO_ROOT/scripts/generate-api-client.sh" >/dev/null
rm -f "$SPEC_TMP"

DIFF_TMP="$(mktemp -t aidrun-drift).diff"
git -C "$REPO_ROOT" diff -- "$OUT_DIR" > "$DIFF_TMP"

if [[ ! -s "$DIFF_TMP" ]]; then
  echo "[sync-api-client] ✅ 生成代码与契约 $SPEC_SHA 一致，无漂移。"
  rm -f "$DIFF_TMP"
  exit 0
fi

# ②③ 分离注释与字段，再交叉查手写模型
python3 - "$DIFF_TMP" "$REPO_ROOT" <<'PYEOF'
import re, subprocess, sys, pathlib

diff_path, repo = sys.argv[1], pathlib.Path(sys.argv[2])
added = [l[1:] for l in open(diff_path)
         if l.startswith('+') and not l.startswith('+++')]

# stat 摘要行（'123 ++++----' / '+16 -0'）不是代码，别算进来 —— 这是坑 ②
def is_stat(s):
    return bool(re.fullmatch(r'[+\-]?\d+\s*[+\-]*\s*', s.strip()))

comments = [s for s in added if s.strip().startswith('///')]
code     = [s for s in added if not s.strip().startswith('///')
            and s.strip() and not is_stat(s)]

print(f"\n[sync-api-client] 漂移 {len(added)} 行：注释 {len(comments)}，代码 {len(code)}")

# 从代码行里抽字段名：public var <name>:
fields = sorted({m.group(1) for s in code
                 for m in [re.search(r'public var (\w+):', s)] if m})
if not fields:
    print("[sync-api-client] 纯文档注释同步，无新字段。可以直接提交。")
    sys.exit(0)

print(f"\n[sync-api-client] ⚠ 契约新增 {len(fields)} 个字段，逐个查手写模型有没有：\n")
missing = []
for f in fields:
    # 手写模型在 blindRun/ 下；生成代码在 Packages/ 下，不能算数
    hit = subprocess.run(
        ['grep', '-rl', f, str(repo / 'blindRun')],
        capture_output=True, text=True).stdout.strip()
    if hit:
        print(f"  ✅ {f} —— 手写模型已有")
    else:
        print(f"  ❌ {f} —— 手写模型没有，运行时读不到")
        missing.append(f)

if missing:
    print(f"""
[sync-api-client] {len(missing)} 个字段只存在于生成代码里。生成代码**不投入运行时**
（运行时走手写 APIClient，见 Packages/AidRunAPI/Package.swift），所以这些字段当前等于不存在。

下一步不是顺手加进模型 —— 先读契约里每个字段的 description 判后果，再决定：
  · 触及盲人端红线（静默失败 / TTS 播报 / null 与 0 语义相反）→ 单独开变更，要测试
  · 纯展示且无播报 → 可以并入下一个相关 PR
  · 前端用不上 → 什么都不做，但在 PR body 里写明为什么不接

判完把结论写进 PR body，别让它悄悄消失 —— 这正是 skill aidrun-contract-sync 存在的理由。""")
PYEOF

rm -f "$DIFF_TMP"

if [[ "$CHECK_ONLY" == "1" ]]; then
  git -C "$REPO_ROOT" checkout -- "$OUT_DIR"
  echo "[sync-api-client] --check：已还原生成产物，工作区未改动。"
fi
