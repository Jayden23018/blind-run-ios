#!/usr/bin/env node
//
// scripts/hooks/research-log.mjs 的回归测试。
//
// 为什么需要它：这个钩子的两种死法都是**静默**的 —— `pre` 吐出非法 JSON，
// Claude Code 只会当没注入过；`researchTodo` 读 transcript 崩掉，Stop 钩子就整个不拦了。
// 两种情况都不报错、看起来一切正常，而约束已经没了。AGENTS.md §1.2 的归宿就是这里。

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { isResearchTool, researchLanded, researchToolsUsed, researchTodo } from './hooks/research-log.mjs';
// 会话起点在 #8 的重构里搬去了 transcript.mjs（stop-checklist 也用它），研究钩子只是消费方。
import { sessionStartedAt } from './hooks/transcript.mjs';

const hook = path.resolve(import.meta.dirname, 'hooks/research-log.mjs');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'aidrun-research-'));

function writeTranscript(name, toolNames) {
  const p = path.join(tmp, name);
  const lines = toolNames.map((n) =>
    JSON.stringify({ message: { content: [{ type: 'tool_use', name: n, input: {} }] } })
  );
  // 掺一行损坏的 JSON 和一行非工具消息：真实 transcript 里两者都会出现。
  lines.splice(1, 0, '{ 这行不是 JSON', JSON.stringify({ message: { content: ' 纯文本' } }));
  fs.writeFileSync(p, lines.join('\n') + '\n');
  return p;
}

const cases = [
  {
    name: 'pre 必须吐出合法 JSON 且带 additionalContext（吐错只会静默不注入）',
    check: () => {
      const r = spawnSync('node', [hook, 'pre'], { encoding: 'utf8' });
      if (r.status !== 0) return `期望 exit 0，实得 ${r.status}`;
      let parsed;
      try {
        parsed = JSON.parse(r.stdout);
      } catch (e) {
        return `stdout 不是合法 JSON：${JSON.stringify(r.stdout.slice(0, 120))}`;
      }
      const out = parsed.hookSpecificOutput;
      if (out?.hookEventName !== 'PreToolUse') return 'hookEventName 不是 PreToolUse';
      if (typeof out.additionalContext !== 'string' || !out.additionalContext.trim()) {
        return 'additionalContext 缺失或为空';
      }
      return null;
    },
  },
  {
    name: 'pre 注入的内容必须真的含索引表头（否则等于注入了一句空话）',
    check: () => {
      const r = spawnSync('node', [hook, 'pre'], { encoding: 'utf8' });
      const ctx = JSON.parse(r.stdout).hookSpecificOutput.additionalContext;
      if (!fs.existsSync(path.resolve(import.meta.dirname, '../docs/research/INDEX.md'))) {
        return ctx.includes('不存在') ? null : '索引不存在时没给出建索引的指引';
      }
      return ctx.includes('复核触发条件') ? null : '注入内容里没有索引表头，索引可能没被读进去';
    },
  },
  {
    name: '联网工具识别：命中 WebSearch/WebFetch/firecrawl，不误伤普通工具',
    check: () => {
      const should = ['WebSearch', 'WebFetch', 'mcp__firecrawl__firecrawl_scrape'];
      const shouldNot = ['Read', 'Bash', 'Grep', 'mcp__codegraph__codegraph_explore', ''];
      const missed = should.filter((n) => !isResearchTool(n));
      const wrong = shouldNot.filter((n) => isResearchTool(n));
      if (missed.length) return `漏判为非调研工具：${missed.join('、')}`;
      if (wrong.length) return `误判为调研工具：${wrong.join('、')}`;
      return null;
    },
  },
  {
    name: '损坏的 transcript 行不许让钩子崩（崩了 Stop 钩子会整个不拦）',
    check: () => {
      const p = writeTranscript('mixed.jsonl', ['WebSearch', 'Read', 'WebFetch']);
      const used = researchToolsUsed(p);
      return used.length === 2 ? null : `期望识别出 2 次联网调用，实得 ${used.length}`;
    },
  },
  {
    name: 'transcript 读不到时不报警（宁可漏报，也不要每轮误报）',
    check: () => {
      if (researchToolsUsed(path.join(tmp, '不存在.jsonl')).length) return '读不到却报了调研';
      if (researchToolsUsed(undefined).length) return 'transcript_path 缺失却报了调研';
      return researchTodo({}) === null ? null : '没有 transcript_path 却产生了欠账';
    },
  },
  {
    name: '本轮没联网就没有欠账',
    check: () => (researchTodo({ transcript_path: writeTranscript('none.jsonl', ['Read', 'Bash']) }) === null
      ? null
      : '没联网却产生了欠账'),
  },
  {
    name: '联网过且 docs/research/ 没动 → 必须给出欠账，且指明落盘路径',
    check: () => {
      const p = writeTranscript('web.jsonl', ['WebSearch', 'WebSearch']);
      const todo = researchTodo({ transcript_path: p });
      // ⚠️ 这条判据必须和钩子**同一个**，不能自己另写一个近似的。
      // 2026-08-14 踩到：原先这里用 `diff-tree HEAD` 当「已落盘」，而钩子用的是
      // **按会话时间窗**的 `git log --since`。合成 transcript 没有 timestamp，
      // `sessionStartedAt` 退化成取文件 mtime，也就是「会话从现在开始」——
      // 于是「调研提交就在 HEAD 上、但早于现在」时两边结论相反：
      // 本用例判「已落盘、不该报警」，钩子判「本会话内没落盘、该报警」，用例红。
      // 后果是任何以调研提交收尾的分支都 push 不出去（pre-push 会跑这份自测）。
      if (researchLanded(sessionStartedAt(p))) {
        // 本轮确实动过 docs/research/：此时正确行为是**不**报警。
        return todo === null ? null : 'docs/research 已有改动却仍在报「没落盘」（误报会让钩子被无视）';
      }
      if (!todo) return '联网过、docs/research 没动，却没有欠账';
      return todo.includes('docs/research') ? null : '欠账没写清落盘路径';
    },
  },
  {
    name: 'sessionStartedAt 取得到会话起点；损坏行跳过而不是放弃，只有读不到文件才返回 null',
    check: () => {
      const p = path.join(tmp, 'ts.jsonl');
      fs.writeFileSync(p, `${JSON.stringify({ timestamp: '2026-08-13T14:11:11.722Z', type: 'x' })}\n{坏行\n`);
      if (sessionStartedAt(p) !== '2026-08-13T14:11:11.722Z') return `没取到首行 timestamp，实得 ${sessionStartedAt(p)}`;

      // 首行损坏**不能**放弃整份 transcript：放弃 = 退回只看 HEAD 的旧判据，
      // 而那个判据正是 2026-08-13 连报 4 次误报的成因。要的是跳过坏行接着找。
      const leading = path.join(tmp, 'leading-bad.jsonl');
      fs.writeFileSync(leading, `{ 这行不是 JSON\n${JSON.stringify({ timestamp: '2026-08-13T15:00:00.000Z' })}\n`);
      if (sessionStartedAt(leading) !== '2026-08-13T15:00:00.000Z') {
        return `首行损坏时没跳过去取下一条，实得 ${sessionStartedAt(leading)}`;
      }

      // 一条时间戳都没有（旧格式 / 夹具）：退回文件自身时间，仍然给得出可喂 --since 的值。
      const noTs = path.join(tmp, 'no-timestamp.jsonl');
      fs.writeFileSync(noTs, '{ 这行不是 JSON\n');
      const fallback = sessionStartedAt(noTs);
      if (!fallback || Number.isNaN(Date.parse(fallback))) {
        return `没有时间戳时该退回文件时间，实得 ${fallback}`;
      }

      // 只有「压根读不到」才是 null —— 调用方靠它区分「没有 transcript」和「有但没干活」。
      if (sessionStartedAt(path.join(tmp, '不存在.jsonl')) !== null) return '文件不存在时没返回 null';
      return sessionStartedAt(undefined) === null ? null : '路径缺失时没返回 null';
    },
  },
  {
    name: '调研提交后再叠一笔无关提交，仍要判定为「已落盘」（只看 HEAD 会误报）',
    check: () => {
      // 2026-08-13 的真实事故：调研已落盘并推送，但随后合入了一笔契约同步的 merge，
      // HEAD 变成只动 Types.swift 的那笔，钩子照样拦「调研没落盘」。
      const repo = path.join(tmp, 'repo');
      fs.mkdirSync(path.join(repo, 'docs/research'), { recursive: true });
      const g = (...a) => spawnSync('git', a, { cwd: repo, encoding: 'utf8' });
      g('init', '-q', '-b', 'main');
      g('config', 'user.email', 't@example.com');
      g('config', 'user.name', 'validate-research-log');
      g('commit', '-q', '--allow-empty', '-m', 'base');

      const since = new Date(Date.now() - 3600_000).toISOString();

      fs.writeFileSync(path.join(repo, 'docs/research/INDEX.md'), '| 日期 |\n');
      g('add', '-A');
      g('commit', '-q', '-m', 'docs: 调研落盘');
      if (!researchLanded(since, repo)) return '调研那笔刚提交完就判成没落盘';

      // 再叠一笔与调研无关的提交 —— 这一步正是当初触发误报的动作
      fs.writeFileSync(path.join(repo, 'other.txt'), 'x\n');
      g('add', '-A');
      g('commit', '-q', '-m', 'chore: 无关改动');

      if (!researchLanded(since, repo)) return '叠了一笔无关提交后误判成「调研没落盘」（就是这次的 bug）';
      // 同时钉住：旧判据（只看 HEAD）在这个场景下确实是错的，防止有人改回去
      if (researchLanded(null, repo)) return '只看 HEAD 的兜底路径居然也过了，说明这条用例没真正复现旧 bug';
      return null;
    },
  },
  {
    name: '调研落在 A 分支、停止时站在 B 分支，仍要判定为「已落盘」（缺 --all 会误报）',
    check: () => {
      // 「一个 PR 只装一件事」意味着一个会话里开两三条分支是常态：
      // 调研提交在文档分支上，收尾时人可能站在另一条修复分支上。
      // git log 默认只走 HEAD 祖先，不带 --all 这里就会误报。
      const repo = path.join(tmp, 'repo-branches');
      fs.mkdirSync(path.join(repo, 'docs/research'), { recursive: true });
      const g = (...a) => spawnSync('git', a, { cwd: repo, encoding: 'utf8' });
      g('init', '-q', '-b', 'main');
      g('config', 'user.email', 't@example.com');
      g('config', 'user.name', 'validate-research-log');
      g('commit', '-q', '--allow-empty', '-m', 'base');

      const since = new Date(Date.now() - 3600_000).toISOString();

      g('checkout', '-q', '-b', 'docs/research-branch');
      fs.writeFileSync(path.join(repo, 'docs/research/INDEX.md'), '| 日期 |\n');
      g('add', '-A');
      g('commit', '-q', '-m', 'docs: 调研落盘');

      // 切到一条与调研无关的分支收尾 —— 调研提交不再是 HEAD 的祖先
      g('checkout', '-q', 'main');
      g('checkout', '-q', '-b', 'fix/unrelated');
      fs.writeFileSync(path.join(repo, 'other.txt'), 'x\n');
      g('add', '-A');
      g('commit', '-q', '-m', 'fix: 无关改动');

      return researchLanded(since, repo)
        ? null
        : '调研在另一条分支上就误判成「没落盘」（git log 缺 --all）';
    },
  },

  // ── 后端仓库索引（2026-09-06 立）────────────────────────────────────────
  // 起因：「Opus 5 怎么用」被前后端两个仓库在同一天各查了一遍。本仓库的索引只盖本仓库，
  // 而跨端问题两边都可能已有结论。走 §1.1：能灌回去的别写成「记得也去看看」。
  {
    name: '后端仓库有索引时，pre 要把它的表格行一起灌回去',
    check: () => {
      const sib = path.join(tmp, 'sibling-INDEX.md');
      fs.writeFileSync(
        sib,
        '# 调研索引\n\n说明性正文不该被带过来。\n\n' +
          '| 日期 | 问题 | 一句话结论 | 复核触发条件 | 报告 |\n|---|---|---|---|---|\n' +
          '| 2026-09-06 | 后端那边查过的问题 | 后端那边的结论 | 某某变化 | [x.md](./x.md) |\n'
      );
      const r = spawnSync('node', [hook, 'pre'], {
        encoding: 'utf8',
        env: { ...process.env, AIDRUN_SIBLING_RESEARCH_INDEX: sib },
      });
      let ctx;
      try {
        ctx = JSON.parse(r.stdout).hookSpecificOutput.additionalContext;
      } catch {
        return `pre 吐的不是合法 JSON：${r.stdout.slice(0, 120)}`;
      }
      if (!ctx.includes('后端那边的结论')) return '后端索引的表格行没有被灌回去';
      if (!ctx.includes('两边都要扫')) return '没有说明这是后端仓库的索引，模型会当成本仓库的';
      if (ctx.includes('说明性正文不该被带过来'))
        return '把后端索引的正文也带过来了 —— 只该取表格行';
      return null;
    },
  },
  {
    name: '后端仓库不存在 / 只有空表时，静默跳过而不是报错或塞垃圾',
    check: () => {
      const missing = path.join(tmp, 'no-such-INDEX.md');
      const r1 = spawnSync('node', [hook, 'pre'], {
        encoding: 'utf8',
        env: { ...process.env, AIDRUN_SIBLING_RESEARCH_INDEX: missing },
      });
      let c1;
      try {
        c1 = JSON.parse(r1.stdout).hookSpecificOutput.additionalContext;
      } catch {
        return `后端索引缺席时 pre 吐的不是合法 JSON：${r1.stdout.slice(0, 120)}`;
      }
      if (c1.includes('两边都要扫')) return '后端仓库不存在却还是印了「两边都要扫」';

      // 只有表头 + 分隔行 = 空表，同样不该注入（否则每轮都多一段没信息的噪音）
      const empty = path.join(tmp, 'empty-INDEX.md');
      fs.writeFileSync(empty, '| 日期 | 问题 |\n|---|---|\n');
      const r2 = spawnSync('node', [hook, 'pre'], {
        encoding: 'utf8',
        env: { ...process.env, AIDRUN_SIBLING_RESEARCH_INDEX: empty },
      });
      const c2 = JSON.parse(r2.stdout).hookSpecificOutput.additionalContext;
      return c2.includes('两边都要扫') ? '后端索引是空表却还是注入了' : null;
    },
  },
];

let failed = 0;
for (const c of cases) {
  let err;
  try {
    err = c.check();
  } catch (e) {
    err = `抛异常：${e.message}`;
  }
  if (err) {
    console.error(`✗ ${c.name}\n  ${err}`);
    failed += 1;
  } else {
    console.log(`✓ ${c.name}`);
  }
}

fs.rmSync(tmp, { recursive: true, force: true });

if (failed) {
  console.error(`\n${failed} 条失败。`);
  process.exit(1);
}
console.log(`\n${cases.length} 条全部通过。`);
