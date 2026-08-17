#!/usr/bin/env node

// 黄金语料对齐检查：后端 `demo/docs/voice-golden-corpus.json` vs 前端 `VoiceOrderWizardTests` 里的镜像清单。
//
// 存在理由：那份清单是**人工誊抄**进 Swift 的。后端改一条语料，前端的抄件不会自己变，
// 而 Swift 测试照样全绿 —— 它测的是抄件，不是语料。
//
// ⚠️ 2026-08-06：本脚本此前只比对 `field === 'DURATION'` 的 11 条，而语料共 45 条 ——
// START_TIME / ADDRESS / GUIDE_DOG / PACE 四族共 34 条既无镜像也无告警，脚本却照样打印「通过」。
// 假绿比没有守卫更坏：它让人以为查过了。现在改成**语料里出现的每一族都必须有镜像**，
// 没有镜像就报错，不再静默跳过。
//
// 刻意**不**把语料复制进本仓库（AGENTS.md 第 7 节：契约唯一源在后端仓库，这里不留副本）。
// 所以校验放在 node 侧：开发机和配了 token 的 CI 都能读到后端仓库，设备上的 XCTest 读不到。
//
// 用法：
//   node scripts/validate-golden-corpus.mjs [corpus.json 路径]
//   AIDRUN_GOLDEN_CORPUS=/path/to/voice-golden-corpus.json node scripts/validate-golden-corpus.mjs

import fs from 'node:fs';
import path from 'node:path';

const repoRoot = path.resolve(import.meta.dirname, '..');
const corpusPath = path.resolve(
  repoRoot,
  process.argv[2] ?? process.env.AIDRUN_GOLDEN_CORPUS ?? '../demo/docs/voice-golden-corpus.json'
);
const swiftPath = path.join(repoRoot, 'blindRunTests/VoiceOrderWizardTests.swift');

if (!fs.existsSync(corpusPath)) {
  console.error(`[golden-corpus] 读不到语料：${corpusPath}`);
  console.error('[golden-corpus] 这不算通过 —— 契约源在后端仓库，用 --add-dir 挂载或传路径参数。');
  process.exit(1);
}

const corpus = JSON.parse(fs.readFileSync(corpusPath, 'utf8'));
const cases = Array.isArray(corpus.cases) ? corpus.cases : [];
if (!cases.length) {
  console.error(`[golden-corpus] ${corpusPath} 里没有 cases 数组，格式可能变了。`);
  process.exit(1);
}

const swift = fs.readFileSync(swiftPath, 'utf8');

// 镜像块：`// golden-corpus: <FIELD> <source>` 标记行之后，到该块第一个 `]` 为止。
//
// 用标记定位而不是全文抓元组，是因为后者会把测试文件里**任何**形如 ("x", 123) 的元组
// 都当成镜像 —— 那正是它此前只支持一个 field 的原因。
function mirrorBlocks() {
  const blocks = new Map();
  const marker = /\/\/ golden-corpus:\s*(\w+)\s+(\w+)/g;
  for (const match of swift.matchAll(marker)) {
    const key = `${match[1]}/${match[2]}`;
    const rest = swift.slice(match.index + match[0].length);
    // 从 `= [` / `in [` 之后开始，**不能**直接取第一个 `]` ——
    // `let x: [(transcript: String, expected: Int)] = [` 的类型注解里就有一个 `]`，
    // 从那里截断会把清单抓成空，然后每条语料都报「不在镜像里」。
    const open = rest.match(/(?:=|\bin)\s*\[/);
    // 找收尾的 `]` 时**跳过行注释里的内容**。清单里的条目常带一段解释，而解释里随手写一个
    // 正则字符组（`[二2]`）或一句「见 docs/x.md[1]」就会在这里截断 —— 报出来的错是
    // 「这几条不在镜像里」，看起来像漏写，实际是被截掉了。2026-08-10 连续踩了两次，
    // 第二次踩在「提醒不要踩这个坑」的那句注释本身上。掩码而不是禁止写注释。
    const masked = rest.replace(/\/\/[^\n]*/g, (m) => ' '.repeat(m.length));
    const end = open ? masked.indexOf(']', open.index + open[0].length) : -1;
    if (!open || end === -1) {
      console.error(`[golden-corpus] 标记「${key}」后面找不到清单（应形如 \`= [\` 或 \`in [\` … \`]\`）`);
      process.exit(1);
    }
    blocks.set(key, rest.slice(open.index + open[0].length, end));
  }
  return blocks;
}

// 期望值字面量归一：Swift 的 `60` / `"五角场"` / `true` → 与 JSON 里的值可比的形式。
function normalize(literal) {
  const text = String(literal).trim().replace(/,$/, '');
  if (/^".*"$/.test(text)) return text.slice(1, -1);
  if (text === 'true') return true;
  if (text === 'false') return false;
  if (/^-?\d+$/.test(text)) return Number(text);
  return text;
}

// 有期望值的族：`("转录", 期望)` 元组。无期望值的族（llm / none）：裸字符串数组。
function parseMirror(block, withExpectation) {
  const entries = new Map();
  if (withExpectation) {
    for (const m of block.matchAll(/\(\s*"((?:[^"\\]|\\.)*)"\s*,\s*([^)]+?)\s*\)/g)) {
      entries.set(m[1], normalize(m[2]));
    }
  } else {
    for (const m of block.matchAll(/"((?:[^"\\]|\\.)*)"/g)) {
      entries.set(m[1], null);
    }
  }
  return entries;
}

const blocks = mirrorBlocks();
const problems = [];
const summary = [];

// 语料里实际出现的每一族都要有镜像 —— 后端新增一族而前端没跟，必须报出来。
const families = new Map();
for (const c of cases) {
  const key = `${c.field}/${c.source}`;
  if (!families.has(key)) families.set(key, []);
  families.get(key).push(c);
}

for (const [key, group] of [...families].sort()) {
  const block = blocks.get(key);
  if (block === undefined) {
    problems.push(
      `语料有「${key}」${group.length} 条，前端没有对应镜像 ——` +
        ` 在 ${path.relative(repoRoot, swiftPath)} 里加一段带` +
        ` \`// golden-corpus: ${key.replace('/', ' ')}\` 标记的清单`
    );
    continue;
  }

  // 期望值恒为 null 的族（llm / none）后端只断言「正则解析不出」，前端镜像也只列转录。
  const withExpectation = group.some((c) => c.expected !== null && c.expected !== undefined);
  const mirror = parseMirror(block, withExpectation);

  for (const c of group) {
    if (!mirror.has(c.transcript)) {
      problems.push(`后端 ${key} 语料「${c.transcript}」不在前端镜像里`);
    } else if (withExpectation && mirror.get(c.transcript) !== c.expected) {
      problems.push(
        `「${c.transcript}」（${key}）期望值漂移：后端 ${JSON.stringify(c.expected)}，` +
          `前端 ${JSON.stringify(mirror.get(c.transcript))}`
      );
    }
  }
  for (const transcript of mirror.keys()) {
    if (!group.some((c) => c.transcript === transcript)) {
      problems.push(`前端镜像里的「${transcript}」在后端 ${key} 语料里已不存在`);
    }
  }
  summary.push(`${key} ${group.length} 条`);
}

// 反向：前端有标记块，语料里却没有这一族（后端删了整族而前端还留着）。
for (const key of blocks.keys()) {
  if (!families.has(key)) {
    problems.push(`前端有「${key}」镜像，但后端语料里已没有这一族`);
  }
}

if (problems.length) {
  console.error('[golden-corpus] 与后端黄金语料不一致：');
  for (const p of problems) console.error(`  · ${p}`);
  console.error(`\n语料：${corpusPath}`);
  console.error(`镜像：${path.relative(repoRoot, swiftPath)}`);
  process.exit(1);
}

console.log(`[golden-corpus] 通过：${cases.length} 条全部与前端镜像一致（${summary.join('、')}）`);
