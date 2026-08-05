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

if (lines.length) {
  process.stdout.write(`AidRun 仓库当前状态（由 session-context hook 自动生成）：\n- ${lines.join('\n- ')}\n`);
}
