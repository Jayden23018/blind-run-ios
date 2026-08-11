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

import { isResearchTool, researchToolsUsed, researchTodo } from './hooks/research-log.mjs';

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
      const dirty = spawnSync('git', ['status', '--porcelain', '--', 'docs/research'], {
        cwd: path.resolve(import.meta.dirname, '..'),
        encoding: 'utf8',
      }).stdout.trim();
      const landed = spawnSync('git', ['diff-tree', '--no-commit-id', '--name-only', '-r', 'HEAD', '--', 'docs/research'], {
        cwd: path.resolve(import.meta.dirname, '..'),
        encoding: 'utf8',
      }).stdout.trim();
      if (dirty || landed) {
        // 本轮确实动过 docs/research/：此时正确行为是**不**报警。
        return todo === null ? null : 'docs/research 已有改动却仍在报「没落盘」（误报会让钩子被无视）';
      }
      if (!todo) return '联网过、docs/research 没动，却没有欠账';
      return todo.includes('docs/research') ? null : '欠账没写清落盘路径';
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
