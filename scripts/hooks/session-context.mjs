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

// 后端契约源是否挂载 —— 没挂就说清楚，别让 Agent 去猜契约。
const specPath = process.env.AIDRUN_API_SPEC || path.resolve(root, '../demo/docs/api_spec.yaml');
lines.push(
  fs.existsSync(specPath)
    ? `后端契约源可读：${specPath}`
    : `⚠️ 后端契约源不可读（找过 ${specPath}）。需要契约时用 \`claude --add-dir /Users/mac/Downloads/demo\` 挂载，不要猜，也不要在本仓库建副本。`
);

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
export function localGuardrailWarnings({ prePushInstalled, forkUrl, pushUrls }) {
  const out = [];
  if (!prePushInstalled) {
    out.push(
      '⚠️ pre-push 钩子未装 —— 那 4 条读后端契约的门禁在本地一条都不会跑，而它们在上游 CI 上是 warning 空过。装：`scripts/install-git-hooks.sh`'
    );
  }
  if (!forkUrl) {
    out.push(
      '⚠️ 没有名为 `fork` 的 remote —— fork 上那套真跑契约门禁的 CI 不会被你的 push 触发。加：`git remote add fork <你的 fork URL>` 后重跑 `scripts/install-git-hooks.sh`'
    );
  } else if (!pushUrls.includes(forkUrl)) {
    // 有 fork 却没进 pushurl：多半是先加了 remote、装钩子脚本没重跑，或后来 remote 改了 URL。
    out.push(
      `⚠️ 双推未生效 —— \`git push origin\` 不会推到 ${forkUrl}，fork 上的契约 CI 等于没配。修：重跑 \`scripts/install-git-hooks.sh\``
    );
  }
  return out;
}

lines.push(
  ...localGuardrailWarnings({
    prePushInstalled: fs.existsSync(path.join(root, '.git/hooks/pre-push')),
    forkUrl: git('remote', 'get-url', 'fork'),
    pushUrls: git('config', '--get-all', 'remote.origin.pushurl').split('\n').filter(Boolean),
  })
);

// import 时不输出 —— 自测要 import 这个模块拿 localGuardrailWarnings。
const isMain = process.argv[1] && path.resolve(process.argv[1]) === path.resolve(import.meta.filename);
if (lines.length && isMain) {
  process.stdout.write(`AidRun 仓库当前状态（由 session-context hook 自动生成）：\n- ${lines.join('\n- ')}\n`);
}
