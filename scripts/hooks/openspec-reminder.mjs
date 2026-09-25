#!/usr/bin/env node
/**
 * OpenSpec「提议 → 实现 → 归档」闭环的机器检查（项目负责人 2026-09-23 要求它每次自动走完）。
 *
 * 两处用它：
 * - 本文件自己是 PreToolUse（Edit|Write）的**开工前提醒**：本会话第一次写 App 源码、
 *   而还没碰过 `openspec/changes/` 时，把「行为有变先提议」灌回来。非阻断 —— 修 bug、
 *   改文案本来就不需要提议，机器分不出，所以只提醒不拦。
 * - `stop-checklist.mjs` 引用下面的判据做**收尾核对**：任务全打勾没归档 → 硬拦；
 *   改了 App 源码却没有变更记录 → 拦一次，一句「不改变行为」即可放行。
 *
 * 立此钩子的理由（AGENTS.md §1.3）：规则早就在 `AGENTS.md` 的按需加载表里（PR #176），
 * 而 09-23 盘点时有 14 个变更没归档 —— 文档挡不住「忘了走最后一步」。
 */
import fs from 'node:fs';
import path from 'node:path';

import { sessionEditedPaths } from './transcript.mjs';

/** App 源码：`blindRun/` 下的 `.swift`，测试目标不算。参数是仓库根相对路径。 */
export function isProductionSwift(rel) {
  return rel.startsWith('blindRun/') && rel.endsWith('.swift');
}

/** OpenSpec 变更目录里的任何文件（含已归档的 —— 归档本身也算走了这一步）。 */
export function isOpenSpecChange(rel) {
  return rel.startsWith('openspec/changes/');
}

/**
 * 任务全打勾、却还没归档的变更名。判据：`tasks.md` 至少一个 `- [x]` 且没有 `- [ ]`。
 * 一个都没勾的不算 —— 那是刚提议还没开工，不是「做完了忘了归档」。
 */
export function completedUnarchivedChanges(root) {
  const dir = path.join(root, 'openspec', 'changes');
  let names = [];
  try {
    names = fs.readdirSync(dir, { withFileTypes: true })
      .filter((d) => d.isDirectory() && d.name !== 'archive')
      .map((d) => d.name);
  } catch {
    return [];
  }
  return names
    .filter((name) => {
      let text = '';
      try {
        text = fs.readFileSync(path.join(dir, name, 'tasks.md'), 'utf8');
      } catch {
        return false;
      }
      return /^\s*- \[x\]/im.test(text) && !/^\s*- \[ \]/m.test(text);
    })
    .sort();
}

export const REMINDER = `【OpenSpec 提醒 —— 本会话只提示这一次】
你要改 App 源码，而本会话还没碰过 \`openspec/changes/\`。先判一次：
- **行为会变**（新功能、改流程、改接口用法）→ 先 \`openspec list\` 看有没有现成的变更；
  有就在它的 \`tasks.md\` 里接着做，没有就用 skill \`openspec-propose\` 建一个再动手。
  实现中做完一项勾一项；**全部打勾就在同一个 PR 里 \`openspec archive <name> -y\`**。
- **不改变行为**（修 bug、改文案、重构、加日志）→ 忽略这条。
收尾时 Stop 钩子会核对：改了 App 源码却没有变更记录会拦一次（回一句「不改变行为」即可放行），
任务全打勾没归档会一直拦。`;

function main() {
  let payload;
  try {
    payload = JSON.parse(fs.readFileSync(0, 'utf8') || '{}');
  } catch {
    process.exit(0);
  }
  const root = process.env.AIDRUN_REPO_ROOT || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const tool = payload.tool_name || '';
  const filePath = payload.tool_input?.file_path || '';
  if ((tool !== 'Edit' && tool !== 'Write') || !filePath) process.exit(0);
  if (!isProductionSwift(path.relative(root, path.resolve(root, filePath)))) process.exit(0);

  // 每会话一次；拿不到 session_id 时不提示（提醒多响一次就会被当噪音，与 design-direction-reminder 同理）。
  const sessionId = typeof payload.session_id === 'string' ? payload.session_id : '';
  if (!sessionId) process.exit(0);

  // 本会话已经在走 OpenSpec 了，不必再提醒。
  const edited = sessionEditedPaths(payload.transcript_path, root);
  if (edited && [...edited].some(isOpenSpecChange)) process.exit(0);

  const seenFile =
    process.env.AIDRUN_OPENSPEC_REMINDER_SEEN || path.join(root, '.git', 'aidrun-openspec-reminder-seen');
  try {
    if (fs.readFileSync(seenFile, 'utf8') === sessionId) process.exit(0);
  } catch {
    /* 没有标记文件 = 本会话还没提醒过 */
  }
  try {
    fs.writeFileSync(seenFile, sessionId);
  } catch {
    /* .git 不可写（worktree 里 .git 是文件）就每次都提醒，好过静默失效 */
  }

  process.stdout.write(
    JSON.stringify({ hookSpecificOutput: { hookEventName: 'PreToolUse', additionalContext: REMINDER } })
  );
  process.exit(0);
}

if (import.meta.url === `file://${process.argv[1]}`) main();
