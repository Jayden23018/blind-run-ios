#!/usr/bin/env node

// 会话 transcript（JSONL）的共用读法。Stop 侧两条判定都要它：
//   - 调研落盘：本轮会话**什么时候开始** —— 用来去所有分支里找本轮的提交，
//     而不是只看 HEAD 和工作树。
//   - 未提交：这些脏文件**是不是本轮自己写的**。
//
// 存在理由（AGENTS.md §1）：2026-08-13 一次会话里「调研没落盘」连报 4 次误报 ——
// 那份调研已经分 4 个提交推到了单开的 docs 分支（`origin/docs/demo-runbook-research`），
// 只是不在当前 HEAD 上；同一轮「未提交」还列了 8 个本会话一个字节都没碰过的文件。
// 误报的代价不是多说一句话，是钩子开始被习惯性无视，那等于把它废掉。

import fs from 'node:fs';
import path from 'node:path';

// 会写文件的工具。漏一个 → 那条路径写出来的文件被判成「不是本轮的」，欠账降级成提示。
const EDIT_TOOLS = new Set(['Edit', 'Write', 'MultiEdit', 'NotebookEdit']);

// null = 读不到（调用方必须能区分「没有 transcript」和「有 transcript 但什么都没干」），
// [] = 读到了但没有可解析的记录。
export function transcriptEntries(transcriptPath) {
  if (!transcriptPath) return null;
  let raw;
  try {
    raw = fs.readFileSync(transcriptPath, 'utf8');
  } catch {
    return null;
  }
  const entries = [];
  for (const line of raw.split('\n')) {
    if (!line.trim()) continue;
    try {
      entries.push(JSON.parse(line));
    } catch {
      // 半行 / 损坏行跳过，别让整个钩子挂掉
    }
  }
  return entries;
}

// 本轮会话的开始时间，ISO 8601，可以直接喂 `git log --since=`。拿不到返回 null。
export function sessionStartedAt(transcriptPath) {
  for (const entry of transcriptEntries(transcriptPath) || []) {
    if (typeof entry?.timestamp === 'string' && entry.timestamp.trim()) return entry.timestamp;
  }
  // 记录里没有时间戳（旧格式 / 测试夹具）：退回文件自身的时间。
  try {
    const st = fs.statSync(transcriptPath);
    return new Date(st.birthtimeMs || st.mtimeMs).toISOString();
  } catch {
    return null;
  }
}

// macOS 上同一个目录常有两个名字（`/tmp` ↔ `/private/tmp`、`/var` ↔ `/private/var`）。
// transcript 里记的是 Edit 当时用的那个写法，而调用方的 root 可能来自 `git rev-parse`
// （给的是 realpath）—— 两边不一致时 `path.relative` 算出来是 `../…`，整个集合会**静默变成空**，
// 调用方据此判定「这些文件都不是本轮写的」，于是每条隐式暂存命令都误报。
function realish(p) {
  try {
    return path.join(fs.realpathSync(path.dirname(p)), path.basename(p));
  } catch {
    return p; // 目录已不存在：按原样比，退回旧行为
  }
}

// 本轮会话用 Edit/Write 写过的文件，仓库相对路径。null = 拿不到 transcript。
// ponytail: 只认工具写的路径。Bash 里重定向、脚本生成的文件会落在集合外，
// 由调用方降级为提示而不是阻断 —— 与其每轮误报，不如少拦一次。
export function sessionEditedPaths(transcriptPath, root) {
  const entries = transcriptEntries(transcriptPath);
  if (entries === null) return null;
  const base = realish(root);
  const paths = new Set();
  for (const entry of entries) {
    const content = entry?.message?.content;
    if (!Array.isArray(content)) continue;
    for (const block of content) {
      if (block?.type !== 'tool_use' || !EDIT_TOOLS.has(block?.name)) continue;
      const file = block.input?.file_path || block.input?.notebook_path;
      if (typeof file !== 'string' || !file.trim()) continue;
      const rel = path.relative(base, realish(path.resolve(root, file)));
      if (rel && !rel.startsWith('..')) paths.add(rel);
    }
  }
  return paths;
}
