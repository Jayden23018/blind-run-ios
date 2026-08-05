#!/usr/bin/env node

// 黄金语料对齐检查：后端 `demo/docs/voice-golden-corpus.json` vs 前端 `VoiceOrderWizardTests` 里的镜像清单。
//
// 存在理由：那份清单目前是**人工誊抄**进 Swift 的（`VoiceOrderWizardTests.swift:390` 附近，
// 以及 `MockAPIClient.swift` 的注释）。后端改一条语料，前端的抄件不会自己变，
// 而 Swift 测试照样全绿 —— 它测的是抄件，不是语料。
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

const backendRegex = new Map(
  cases
    .filter((c) => c.field === 'DURATION' && c.source === 'regex')
    .map((c) => [c.transcript, c.expected])
);
const backendLLM = new Set(
  cases.filter((c) => c.field === 'DURATION' && c.source === 'llm').map((c) => c.transcript)
);

const swift = fs.readFileSync(swiftPath, 'utf8');

// 前端镜像：`("跑一小时", 60),` 这种元组行
const frontRegex = new Map(
  [...swift.matchAll(/\("([^"]+)",\s*(\d+)\)/g)].map((m) => [m[1], Number(m[2])])
);
// 以及 needReask 那几组：`for transcript in ["随便说点什么", ...]`
// 用 matchAll 取全部 —— 文件里不止一处 `for transcript in [...]`，只取第一处会把清单抓空，
// 然后每次都报「不在清单里」，变成一个恒红的假警报。
const frontLLM = new Set(
  [...swift.matchAll(/for transcript in \[([^\]]+)\]/g)].flatMap((block) =>
    [...block[1].matchAll(/"([^"]+)"/g)].map((m) => m[1])
  )
);

const problems = [];

for (const [transcript, expected] of backendRegex) {
  if (!frontRegex.has(transcript)) {
    problems.push(`后端 regex 语料「${transcript}」→ ${expected}，前端镜像里没有`);
  } else if (frontRegex.get(transcript) !== expected) {
    problems.push(
      `「${transcript}」期望值漂移：后端 ${expected}，前端 ${frontRegex.get(transcript)}`
    );
  }
}
for (const transcript of frontRegex.keys()) {
  if (!backendRegex.has(transcript)) {
    problems.push(`前端镜像里的「${transcript}」在后端 regex 语料里已不存在`);
  }
}
for (const transcript of backendLLM) {
  if (!frontLLM.has(transcript)) {
    problems.push(`后端 llm 语料「${transcript}」不在前端的 needReask 清单里`);
  }
}

if (problems.length) {
  console.error('[golden-corpus] 与后端黄金语料不一致：');
  for (const p of problems) console.error(`  · ${p}`);
  console.error(`\n语料：${corpusPath}`);
  console.error(`镜像：${path.relative(repoRoot, swiftPath)}`);
  process.exit(1);
}

console.log(
  `[golden-corpus] 通过：DURATION regex ${backendRegex.size} 条、llm ${backendLLM.size} 条与前端镜像一致`
);
