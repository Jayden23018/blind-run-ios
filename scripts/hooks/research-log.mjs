#!/usr/bin/env node

// 调研必须落盘，且只落一个地方：`docs/research/`，索引 `docs/research/INDEX.md`。
//
// 存在理由：位置约定早就有（skill `tech-decision-research` 第四步写死了这两个路径），
// 但没有任何东西强制它 —— skill 不被显式调用就不生效，于是调研结果散落在会话里、
// 散落在临时文件里，下次同一个问题被原样重搜一遍。AGENTS.md §1：只写文档不算完成。
//
// 两个入口：
//   `pre`  —— PreToolUse(联网工具) 前把整份索引灌回给模型。「先查记录再决定要不要重搜」
//             这件事靠提醒挡不住，靠把答案直接塞到眼前才挡得住。
//   `researchTodo(payload)` —— 由 stop-checklist.mjs import：本轮联网调研过、
//             但 `docs/research/` 一个字节都没动 → 记一条欠账。
//
// 自测 scripts/validate-research-log.mjs。

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

import { sessionStartedAt, transcriptEntries } from './transcript.mjs';

// AIDRUN_REPO_ROOT 只给自测用（拿一个临时 git 仓库当靶子），生产路径永远走仓库根。
const root = process.env.AIDRUN_REPO_ROOT || path.resolve(import.meta.dirname, '../..');

export const RESEARCH_DIR = 'docs/research';
export const INDEX_PATH = path.join(RESEARCH_DIR, 'INDEX.md');

// 联网调研类工具。新增抓取类 MCP 时加进来 —— 漏一个，那条路径就绕过了整套约束。
const RESEARCH_TOOL = /^(WebSearch|WebFetch|mcp__firecrawl__|mcp__.*__firecrawl_)/;

// 灌回给模型的索引有上限：索引长到几千行时全量塞回去会挤掉真正的工作上下文。
// 超了就截断并明说被截断，不静默丢尾巴（丢了尾巴等于「表里没有」，会触发重复调研）。
const MAX_INDEX_CHARS = 12000;

export function isResearchTool(name) {
  return typeof name === 'string' && RESEARCH_TOOL.test(name);
}

// cwd 可覆盖，只为让 validate-research-log.mjs 能在临时仓库里跑真函数而不是复刻命令串
// —— 复刻的命令串会跟实现漂移，而这个钩子的 bug 恰恰就出在命令选错。
function git(cwd, ...args) {
  try {
    return execFileSync('git', args, {
      cwd,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    });
  } catch {
    return null;
  }
}

export function readIndex() {
  try {
    return fs.readFileSync(path.join(root, INDEX_PATH), 'utf8');
  } catch {
    return null;
  }
}

// 本轮用过哪些联网工具。transcript 是 JSONL，每行一条消息，
// 工具调用在 message.content[] 里 type === 'tool_use'。
// 读不到就当没调研过：这里宁可漏报也不要每轮误报。
export function researchToolsUsed(transcriptPath) {
  const used = [];
  for (const entry of transcriptEntries(transcriptPath) || []) {
    const content = entry?.message?.content;
    if (!Array.isArray(content)) continue;
    for (const block of content) {
      if (block?.type === 'tool_use' && isResearchTool(block.name)) used.push(block.name);
    }
  }
  return used;
}

// 落盘判定要覆盖三种「已经做了」：还没提交（工作树脏）、本轮任意一笔提交动过、
// 以及拿不到会话起点时退回只看最后一笔。
//
// ⚠️ 只看 HEAD 是不够的，2026-08-13 实测踩到：调研提交之后只要再叠**任何**一笔
// （merge、契约同步、fixup），HEAD 就不再是调研那笔，钩子照样报「调研没落盘」。
// 当时 HEAD 是一个只动 Types.swift 的 merge commit，而调研在 HEAD~1/HEAD~2 ——
// 落盘做完了、还推送了，钩子仍然拦。误报一次这个钩子就开始被无视，
// 所以判据必须覆盖**整个会话**，不是最后一笔。
//
// ⚠️ `--all` 也不是可选项：`git log` 默认只走 HEAD 的祖先，而一个会话里开两三条
// 分支是常态（本仓库 §「一个 PR 只装一件事」正是这么要求的）。调研落在 A 分支、
// 停止时站在 B 分支，不带 `--all` 就照样误报 —— 修第一版时当场又踩了一次。
export function researchLanded(sinceIso, cwd = root) {
  const dirty = git(cwd, 'status', '--porcelain', '--', RESEARCH_DIR);
  if (dirty && dirty.trim()) return true;
  if (sinceIso) {
    const inSession = git(cwd, 'log', '--all', `--since=${sinceIso}`, '--name-only', '--pretty=format:', '--', RESEARCH_DIR);
    return Boolean(inSession && inSession.trim());
  }
  const lastCommit = git(cwd, 'diff-tree', '--no-commit-id', '--name-only', '-r', 'HEAD', '--', RESEARCH_DIR);
  return Boolean(lastCommit && lastCommit.trim());
}

// 给 Stop 钩子用：返回一条欠账文本，或 null（无需提醒）。
export function researchTodo(payload) {
  const used = researchToolsUsed(payload?.transcript_path);
  if (!used.length) return null;
  if (researchLanded(sessionStartedAt(payload?.transcript_path))) return null;
  const kinds = [...new Set(used)].join('、');
  return (
    `**调研没落盘**：本轮联网 ${used.length} 次（${kinds}），但 \`${RESEARCH_DIR}/\` 没有任何改动` +
    `（工作树、HEAD、本轮会话内所有分支的提交都查过）。` +
    `落到 \`${RESEARCH_DIR}/{topic}-{YYYYMMDD}.md\` 并回写 \`${INDEX_PATH}\` 一行` +
    `（日期/问题/一句话结论/复核触发条件/报告，五列齐全）。` +
    `只是查一个 API 签名、不构成调研的，回一句说明再停。`
  );
}

// ── CLI：PreToolUse ────────────────────────────────────────────────────────
// matcher 已经把非联网工具滤掉了，这里不再判一次工具名 —— 两处判定会漂移。
if (process.argv[2] === 'pre') {
  const index = readIndex();
  const body =
    index === null
      ? `\`${INDEX_PATH}\` 不存在。本仓库所有调研只落 \`${RESEARCH_DIR}/\`，` +
        `开搜前先建索引（表头：日期 | 问题 | 一句话结论 | 复核触发条件 | 报告）。`
      : `开搜前先读已有调研（唯一位置 \`${RESEARCH_DIR}/\`）。表里已有且「复核触发条件」没触发的，` +
        `直接用结论，不要重搜；缺的那一段才是本次该搜的范围。\n\n` +
        (index.length > MAX_INDEX_CHARS
          ? `${index.slice(0, MAX_INDEX_CHARS)}\n\n（索引已截断，完整内容见 ${INDEX_PATH}）`
          : index) +
        `\n\n调研完必须落盘 \`${RESEARCH_DIR}/{topic}-{YYYYMMDD}.md\` 并回写索引一行，否则不算完成。`;

  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: { hookEventName: 'PreToolUse', additionalContext: body },
    })
  );
  process.exit(0);
}
