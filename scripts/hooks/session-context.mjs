#!/usr/bin/env node

// SessionStart hook：把「每次开会话都要重新查一遍」的仓库事实直接注进上下文。
// stdout 会被 Claude Code 作为上下文注入，所以这里只输出结论，不输出噪声。
//
// 存在理由：这些事实此前靠 .claude/state.md 手工维护，而手工维护的东西会过期。
// 分支、脏文件数、未归档变更的未完成任务数都是可以算出来的，不该让人记。

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '../..');

// execFileSync 而非 execSync：不起 shell，参数按数组传，没有注入面。
function git(...args) {
  try {
    return execFileSync('git', args, {
      cwd: root,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
  } catch {
    return '';
  }
}

const lines = [];

const branch = git('rev-parse', '--abbrev-ref', 'HEAD');
const dirty = git('status', '--porcelain').split('\n').filter(Boolean).length;
if (branch) lines.push(`分支 \`${branch}\`，未提交改动 ${dirty} 个文件。`);

// 未归档的 OpenSpec 变更 —— 两个未归档变更 delta 同一能力会打架，这是已经踩过的坑。
const changesDir = path.join(root, 'openspec/changes');
if (fs.existsSync(changesDir)) {
  const open = [];
  for (const name of fs.readdirSync(changesDir)) {
    if (name === 'archive') continue;
    const tasks = path.join(changesDir, name, 'tasks.md');
    if (!fs.existsSync(tasks)) continue;
    const body = fs.readFileSync(tasks, 'utf8');
    const todo = (body.match(/^- \[ \]/gm) || []).length;
    open.push({ name, todo });
  }
  if (open.length) {
    const detail = open.map((c) => `${c.name}(${c.todo} 未完成)`).join('、');
    lines.push(`未归档 OpenSpec 变更 ${open.length} 个：${detail}。`);
    if (open.length > 1) {
      lines.push('⚠️ 多个未归档变更同时存在时，先确认它们没有 delta 同一个能力，否则规格会打架。');
    }
  }
}

// 后端契约源在哪、读哪一份 —— 没有就说清楚，别让 Agent 去猜契约。
// ⚠️ 后端目录按**主 worktree** 的兄弟目录找，不按 root：在 .claude/worktrees/<x> 里 `root/../demo`
// 是个不存在的路径，于是每个桌面 App 会话开场都报「契约源不可读」（workflow-review-20260924 A7）。
// pre-push 2026-08-14 就这么修过一次，这里当时没跟上。
// ⚠️ 读 origin/main，不读它的工作区：那是共享 checkout，常停在别人的特性分支上（pre-push 注释里 08-09/08-12 两次事故）。
export function backendDir(repoRoot, env = process.env) {
  if (env.AIDRUN_BACKEND_DIR) return env.AIDRUN_BACKEND_DIR;
  const common = git('-C', repoRoot, 'rev-parse', '--path-format=absolute', '--git-common-dir');
  return path.join(path.dirname(path.dirname(common || path.join(repoRoot, '.git'))), 'demo');
}
// 能不能从后端的 origin/main 读到契约。⚠️ 别用上面的 git()：它失败时也返回 ''，而 `cat-file -e`
// 成功时本来就没有输出 ⇒ 用 `=== ''` 判断永远成立，只剩「目录在不在」在起作用（复核 A-1 抓到）。
export function backendContractReadable(backend) {
  try {
    execFileSync('git', ['-C', backend, 'cat-file', '-e', 'origin/main:docs/api_spec.yaml'], { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}
if (process.env.AIDRUN_API_SPEC) {
  lines.push(`后端契约源（AIDRUN_API_SPEC 指定）：${process.env.AIDRUN_API_SPEC}`);
} else {
  const backend = backendDir(root);
  const onMain = backendContractReadable(backend);
  lines.push(
    onMain
      ? `后端契约源：${backend} 的 origin/main —— 读 \`git -C ${backend} show origin/main:docs/api_spec.yaml\`，别读它的工作区（常停在别人的分支上）。交接走 \`gh issue list --repo Jayden23018/blind-run-backend --label 待前端确认\`。`
      : `⚠️ 后端契约源不可读（找过 ${backend} 的 origin/main）。需要契约时用 \`claude --add-dir /Users/mac/Downloads/demo\` 挂载，或设 AIDRUN_BACKEND_DIR，不要猜，也不要在本仓库建副本。`
  );
}

// state.md 里「开始前必须先做」那类阻塞项
const state = path.join(root, '.claude/state.md');
if (fs.existsSync(state)) {
  const body = fs.readFileSync(state, 'utf8');
  const m = body.match(/^##+ .*(必须先做|前置障碍|未开始).*$/gm);
  if (m) lines.push(`\`.claude/state.md\` 有待办小节：${m.map((s) => s.replace(/^#+\s*/, '')).join(' / ')}`);
}

// 「每台机器装一次」的那几项。装过之后没有任何地方显示它还在不在 ——
// 于是每次都要重查 AGENTS.md 或重跑命令才敢下结论，这正是 §1 说的「反复查」。
// 全绿时不输出：开场上下文已经够长，「一切正常」是噪声，只报缺口。
//
// 2026-08-15：这里原本还报「没有 `fork` remote」「双推未生效」两条，已删。
// AGENTS.md §11 在 08-12 就改了口径（主线即 origin，不再需要双推），而
// `install-git-hooks.sh` 末尾「推送目标：只推 origin」那段现在会**主动清掉**遗留的双推配置 —— 于是这两条告警
// 每次开场都响、照它做又会被安装脚本撤销，成了本文件自己警告过的那种「每轮都响就被无视」。
export function localGuardrailWarnings({ prePushInstalled }) {
  const out = [];
  if (!prePushInstalled) {
    out.push(
      '⚠️ pre-push 钩子未装 —— 那 5 条读后端契约的门禁在本地一条都不会跑。装：`scripts/install-git-hooks.sh`'
    );
  }
  return out;
}

// 推上去了、却再没人管的分支。2026-08-12 主线从旧上游切到 `Jayden23018` 时，
// 一批在途 PR 被孤儿化：**分支还在 origin 上，但主线没有对应的 PR**，于是
// 「已有在途 PR #24」这类记录全部作废，而没人会发现 —— 直到有人照着它宣称功能已完成
// （`BlindRunHistoryView` 就是这么在 review 里挂了三天「已实现」）。
//
// 判据只用 git，不打网络：**领先 main（有独有提交）且落后 main 很多**（久没跟进）。
// 落后阈值取 30：正常在途分支不会落这么多，落这么多的基本都是被忘了。
// 不查 PR 状态 —— 那要 `gh` 联网，开场卡住比漏报更糟；这里只负责让分支重新被看见。
export const STALE_BEHIND_THRESHOLD = 30;

export function staleUnmergedBranches({ refs, currentBranch }) {
  const stale = refs
    .filter((r) => r.name !== 'origin' && r.name !== 'origin/main')
    .filter((r) => r.name !== `origin/${currentBranch}`)
    .filter((r) => r.ahead > 0 && r.behind > STALE_BEHIND_THRESHOLD)
    .sort((a, b) => b.behind - a.behind);
  if (!stale.length) return [];
  const detail = stale.map((r) => `${r.name.replace(/^origin\//, '')}(+${r.ahead}/-${r.behind})`).join('、');
  return [
    `⚠️ ${stale.length} 条远端分支有独有提交却长期没跟进（领先 main 且落后 >${STALE_BEHIND_THRESHOLD}）：${detail}。` +
      '逐条判活：意图已被主线重新落地的判死存档，仍有价值的合 main 后开 PR。别默认它们「已经在某个 PR 里」。',
  ];
}

lines.push(
  ...localGuardrailWarnings({
    // --git-path：worktree 里 `.git` 是个文件，拼 `.git/hooks/pre-push` 永远不存在 ⇒ 每个 worktree 会话都误报「未装」。
    prePushInstalled: fs.existsSync(path.resolve(root, git('rev-parse', '--git-path', 'hooks/pre-push') || '.git/hooks/pre-push')),
  }),
  ...staleUnmergedBranches({
    refs: git('for-each-ref', '--format=%(refname:short) %(ahead-behind:origin/main)', 'refs/remotes/origin')
      .split('\n')
      .filter(Boolean)
      .map((line) => {
        const [name, ahead, behind] = line.split(' ');
        return { name, ahead: Number(ahead), behind: Number(behind) };
      })
      // ahead-behind 对没有共同祖先的 ref 不输出数字，解析出 NaN 时直接丢掉。
      .filter((r) => Number.isFinite(r.ahead) && Number.isFinite(r.behind)),
    currentBranch: branch,
  })
);

// import 时不输出 —— 自测要 import 这个模块拿 localGuardrailWarnings。
const isMain = process.argv[1] && path.resolve(process.argv[1]) === path.resolve(import.meta.filename);
if (lines.length && isMain) {
  process.stdout.write(`AidRun 仓库当前状态（由 session-context hook 自动生成）：\n- ${lines.join('\n- ')}\n`);
}
