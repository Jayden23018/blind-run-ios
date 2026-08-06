#!/usr/bin/env node

// Stop hook：拦住「改完就跑」。收尾三件事 —— handoff 打勾/提问 → commit → push。
//
// 存在理由：这三件事此前每轮都靠用户手动提醒，属于 AGENTS.md §1 里说的
// 「已经犯过第二次」。文档挡不住，所以落成钩子。
//
// 行为：有活没干完 → exit 2 + stderr（Claude Code 会把 stderr 回灌给模型，阻止本次停止）。
// 每轮只拦一次：第二次停止时 stop_hook_active === true，直接放行。
// 所以「用户说了先不提交」不会死循环 —— 说明一句再停即可。

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '../..');

function git(...args) {
  try {
    return execFileSync('git', args, {
      cwd: root,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
  } catch {
    return null; // null = 命令失败（如无 upstream），'' = 成功但空输出
  }
}

const input = await new Promise((resolve) => {
  let buf = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (c) => (buf += c));
  process.stdin.on('end', () => resolve(buf));
  process.stdin.on('error', () => resolve(''));
});

let payload = {};
try {
  payload = JSON.parse(input || '{}');
} catch {
  payload = {};
}

// 已经拦过一次就放行，否则会无限循环。
if (payload.stop_hook_active) process.exit(0);

const todo = [];

const dirty = (git('status', '--porcelain') || '').split('\n').filter(Boolean);
if (dirty.length) {
  todo.push(`**未提交**：${dirty.length} 个文件（${dirty.slice(0, 4).map((l) => l.slice(3)).join('、')}${dirty.length > 4 ? ' …' : ''}）`);
}

const upstream = git('rev-parse', '--abbrev-ref', '@{u}');
if (upstream === null) {
  const branch = git('rev-parse', '--abbrev-ref', 'HEAD');
  todo.push(`**无 upstream**：\`${branch}\` 还没跟远端，push 要带 \`-u\``);
} else {
  const ahead = Number(git('rev-list', '--count', '@{u}..HEAD') || 0);
  if (ahead > 0) todo.push(`**未推送**：领先 \`${upstream}\` ${ahead} 个提交`);
}

// 没有欠账就放行。handoff 只在有欠账时**附带**提醒，不做独立触发条件 ——
// 纯客户端改动（UI 时序、测试 helper、本仓库自己的工具链）本来就不该投递 handoff，
// 拿「提交晚于 handoff」当触发条件会让每次工具类提交都误报，而天天误报的钩子等于没有钩子。
if (!todo.length) process.exit(0);

// handoff 是后端仓库的文件，前端 session 未必挂载了 —— 挂了才看。
const handoff =
  process.env.AIDRUN_HANDOFF || path.resolve(root, '../demo/docs/handoff.md');
let handoffNote = '';
if (fs.existsSync(handoff)) {
  const lastCommitAt = Number(git('log', '-1', '--format=%ct') || 0);
  const handoffAt = Math.floor(fs.statSync(handoff).mtimeMs / 1000);
  if (lastCommitAt > 0 && handoffAt < lastCommitAt) {
    handoffNote =
      '\n参考：`demo/docs/handoff.md` 比最后一次提交旧。本轮若动了契约用法、错误码语义、' +
      '字段依赖或新增端点调用，要同步过去；纯客户端改动不投递。\n';
  }
}

process.stderr.write(
  `收尾没做完（scripts/hooks/stop-checklist.mjs）：\n- ${todo.join('\n- ')}\n` +
    handoffNote +
    '\n顺序固定：① 需要投递时先同步 handoff（`- [ ]` → `- [x]`，答写在 `答：` 后面，' +
    '并追加本轮产生的新问题）② commit（`type: 描述`，不带 co-author）③ push。\n' +
    '不是本轮产生的脏文件不要顺手提交 —— 说清楚哪些留着、为什么留着。\n' +
    '用户明确说过「先不提交」的，回一句说明再停 —— 本钩子每轮只拦一次，不会死循环。\n'
);
process.exit(2);
