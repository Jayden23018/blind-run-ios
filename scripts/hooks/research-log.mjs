#!/usr/bin/env node

// 调研必须落盘，且只落一个地方：`docs/research/`，索引 `docs/research/INDEX.md`。
//
// 存在理由：位置约定早就有（skill `tech-decision-research` 第四步写死了这两个路径），
// 但没有任何东西强制它 —— skill 不被显式调用就不生效，于是调研结果散落在会话里、
// 散落在临时文件里，下次同一个问题被原样重搜一遍。AGENTS.md §1：只写文档不算完成。
//
// 两个入口：
//   `pre`  —— PreToolUse(联网工具) 前把索引表头 + 最近 20 行灌回给模型。「先查记录再决定要不要重搜」
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

// 灌回给模型的只有表头 + 文件里最后 N 行数据（#715，负责人 2026-11-05 定）。
// 索引按日期追加，最新的在文件尾。旧实现从文件头截 12,000 字符，
// 69 行时只注入了 08-05 至 08-21 的 14 行，9 月以后的 55 行全看不到。
// 更早的行明说「在文件里」，不静默丢（丢了等于「表里没有」，会触发重复调研）。
export const RECENT_INDEX_ROWS = 20;

// 找不到表格（索引被改坏）时才用：退回从头截取，至少不把几万字全灌进去。
const FALLBACK_INDEX_CHARS = 12000;

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

// 「查过再搜」这条规则每次都要说，索引正文只需要说一次 —— 见下方 indexAlreadyInjected。
const RULES_TAIL =
  `\n\n调研完必须落盘 \`${RESEARCH_DIR}/{topic}-{YYYYMMDD}.md\` 并回写索引一行，否则不算完成。` +
  `\n\n⚠️ 写下「本仓库还没有 X / 建议引入 X」之前，先在仓库里搜一次 X，并换一组近义词再搜一次。` +
  `调研在回答「外面有什么」时会默认「我们没有」：2026-09-02 一路搜到「该给这个项目引入 iOS 无障碍` +
  `自动审计」，而 \`blindRunUITests/AccessibilityAuditTests.swift\` 已经在那儿躺了 859 行。` +
  `同类还犯过两次（记忆 \`synonym-mismatch-fakes-a-missing-feature\`）。成本一次 grep。`;

// 同一会话内第 2…N 次联网调用时，索引正文已经在上下文里了，再灌一遍是纯重复。
//
// ⚠️ 这不是省小钱。2026-09-17 实测：一次调研会话触发 4 次，每次注入 12.1KB（约 4k tok）
// ≈ 16k 纯重复；而注入进的是**对话层**，此后每一轮都会把它按 cache read 价重读一遍
// （官方 prompt-caching 文档：cache read 按标准输入价 10% 计）⇒ 成本随轮数累积，
// 不是一次性的。详见 docs/research/claude-code-token-optimization-20260917.md §6。
//
// 判据只用 session_id，不用「索引文件有没有变」—— 会话中途回写索引是常态（落盘那一步就在改它），
// 拿内容哈希判会在最该省的那一刻失效。拿不到 session_id 就照常全量注入：
// 宁可多灌一次，也不要因为标识符缺失而静默跳过第一次（那等于整个钩子失效）。
export function indexAlreadyInjected(sessionId, cwd = root) {
  if (!sessionId) return false;
  const seenFile = path.join(cwd, '.git', 'aidrun-research-index-seen');
  try {
    if (fs.readFileSync(seenFile, 'utf8') === sessionId) return true;
  } catch {
    /* 没有标记文件 = 本会话还没注入过 */
  }
  try {
    fs.writeFileSync(seenFile, sessionId);
  } catch {
    /* 写不进去就每次都注入，退化成旧行为，不影响正确性 */
  }
  return false;
}

// 取表头（列名行 + 分隔行）和最后 RECENT_INDEX_ROWS 行数据，按文件顺序。
// 表头之前的说明文字不注入：那几条规则 RULES_TAIL 和开头那句已经说了。
export function recentIndexExcerpt(index) {
  const lines = index.split('\n');
  const headerAt = lines.findIndex(
    (l, i) => l.startsWith('|') && /^\|[\s|:-]+\|?\s*$/.test(lines[i + 1] ?? '')
  );
  if (headerAt === -1) {
    return index.length > FALLBACK_INDEX_CHARS
      ? `${index.slice(0, FALLBACK_INDEX_CHARS)}\n\n（索引没找到表格，已截断，完整内容见 ${INDEX_PATH}）`
      : index;
  }
  const rows = lines.slice(headerAt + 2).filter((l) => l.startsWith('|'));
  const recent = rows.slice(-RECENT_INDEX_ROWS);
  const header = lines.slice(headerAt, headerAt + 2).join('\n');
  const note =
    rows.length > recent.length
      ? `\n\n（以上是最近 ${recent.length} 行；更早的 ${rows.length - recent.length} 行在 \`${INDEX_PATH}\` 里，` +
        `要查的问题这里没有时去那里搜，别直接重搜。）`
      : '';
  return `${header}\n${recent.join('\n')}${note}`;
}

export function buildPreContext(index, repeated) {
  if (index === null) {
    return (
      `\`${INDEX_PATH}\` 不存在。本仓库所有调研只落 \`${RESEARCH_DIR}/\`，` +
      `开搜前先建索引（表头：日期 | 问题 | 一句话结论 | 复核触发条件 | 报告）。`
    );
  }
  if (repeated) {
    return (
      `本会话已经注入过 \`${INDEX_PATH}\` 的表头与最近 ${RECENT_INDEX_ROWS} 行，不再重复 —— 往上翻即可。` +
      `表里已有且「复核触发条件」没触发的，直接用结论，不要重搜。` +
      RULES_TAIL
    );
  }
  return (
    `开搜前先读已有调研（唯一位置 \`${RESEARCH_DIR}/\`）。表里已有且「复核触发条件」没触发的，` +
    `直接用结论，不要重搜；缺的那一段才是本次该搜的范围。\n\n` +
    recentIndexExcerpt(index) +
    RULES_TAIL
  );
}

// ── CLI：PreToolUse ────────────────────────────────────────────────────────
// matcher 已经把非联网工具滤掉了，这里不再判一次工具名 —— 两处判定会漂移。
if (process.argv[2] === 'pre') {
  const input = await new Promise((resolve) => {
    let buf = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (c) => (buf += c));
    process.stdin.on('end', () => resolve(buf));
    process.stdin.on('error', () => resolve(''));
  });
  let sessionId = '';
  try {
    const payload = JSON.parse(input || '{}');
    if (typeof payload.session_id === 'string') sessionId = payload.session_id;
  } catch {
    /* 拿不到 payload 就当新会话，全量注入 */
  }

  const body = buildPreContext(readIndex(), indexAlreadyInjected(sessionId));

  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: { hookEventName: 'PreToolUse', additionalContext: body },
    })
  );
  process.exit(0);
}
