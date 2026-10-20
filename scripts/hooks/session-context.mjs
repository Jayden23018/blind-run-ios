#!/usr/bin/env node

// SessionStart hook：把「每次开会话都要重新查一遍」的仓库事实直接注进上下文。
// stdout 会被 Claude Code 作为上下文注入，所以这里只输出结论，不输出噪声。
//
// 存在理由：这些事实此前靠 .claude/state.md 手工维护，而手工维护的东西会过期。
// 分支、脏文件数、未归档变更的未完成任务数都是可以算出来的，不该让人记。

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

import { completedUnarchivedChanges } from './openspec-reminder.mjs';

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

// 未归档的 OpenSpec 变更：只报计数，只点名「待归档」的（#482）。
// 逐个列名 30 个变更每次约 1.5KB，几乎从不被用到；「待归档」是唯一要当场动手的 —— Stop 钩子会因它拦人。
// 「多个未归档变更先确认没有 delta 同一能力」那条也删了：30 个变更时它每次都响，按本文件下面「全绿时不输出」的原则会被无视。
// 「待归档」直接用 Stop 钩子那一份判据（openspec-reminder.mjs 的 completedUnarchivedChanges），开场说的和拦人的才是同一批。
// 其余按有没有勾过一项分成进行中 / 未开工，三类加起来恒等于总数。
export function countCheckboxes(body) {
  return {
    done: (body.match(/^\s*- \[x\]/gim) || []).length,
    todo: (body.match(/^\s*- \[ \]/gm) || []).length,
  };
}

export function openSpecSummary(changes, toArchive) {
  if (!changes.length) return [];
  const archive = new Set(toArchive);
  const rest = changes.filter((c) => !archive.has(c.name));
  const inProgress = rest.filter((c) => c.done > 0).length;
  const notStarted = rest.length - inProgress;
  const names = changes.map((c) => c.name).filter((n) => archive.has(n)).sort();
  const out = [
    `OpenSpec 未归档 ${changes.length} 个：进行中 ${inProgress}、未开工 ${notStarted}、任务全勾待归档 ${names.length}。列表：\`openspec list\`。`,
  ];
  if (names.length) out.push(`⚠️ 待归档（全勾却没归档，Stop 钩子会拦）：${names.join('、')}`);
  return out;
}

const changesDir = path.join(root, 'openspec/changes');
if (fs.existsSync(changesDir)) {
  const changes = [];
  for (const name of fs.readdirSync(changesDir)) {
    if (name === 'archive') continue;
    const tasks = path.join(changesDir, name, 'tasks.md');
    if (!fs.existsSync(tasks)) continue;
    changes.push({ name, ...countCheckboxes(fs.readFileSync(tasks, 'utf8')) });
  }
  lines.push(...openSpecSummary(changes, completedUnarchivedChanges(root)));
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
// 能列出这批分支的命令。只报条数不列名（#482）：squash 合并后的旧分支永远 ahead>0，实测 65 条，
// 原来只列前 5 条也要 ~1KB/会话，而开场几乎用不到；要判活时跑这一条就全有。
// 与下面的计数同一口径：排除 origin/main、裸 origin 与当前分支，否则命令列出的条数会比报的多一条。
export function staleListCommand(currentBranch) {
  return `git for-each-ref --format='%(refname:short) %(ahead-behind:origin/main)' refs/remotes/origin | awk '$1!="origin/${currentBranch}" && $2>0 && $3>${STALE_BEHIND_THRESHOLD}'`;
}

export function staleUnmergedBranches({ refs, currentBranch }) {
  const stale = refs
    .filter((r) => r.name !== 'origin' && r.name !== 'origin/main')
    .filter((r) => r.name !== `origin/${currentBranch}`)
    .filter((r) => r.ahead > 0 && r.behind > STALE_BEHIND_THRESHOLD);
  if (!stale.length) return [];
  return [
    `⚠️ ${stale.length} 条远端分支有独有提交却长期没跟进（领先 main 且落后 >${STALE_BEHIND_THRESHOLD}），别默认它们已在某个 PR 里。查看：\`${staleListCommand(currentBranch)}\`。`,
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
