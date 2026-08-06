#!/usr/bin/env node
//
// scripts/hooks/stop-checklist.mjs 的回归测试。
//
// 为什么需要它：Stop 钩子靠 exit 2 阻止停止，靠 `stop_hook_active` 跳出循环。
// 那个跳出条件一旦坏掉，每次会话结束都会无限自我唤醒 —— 而且不会报错，只会看起来「卡住」。
// AGENTS.md §1.3 要求这类事落到机器归宿，这就是那个归宿。
//
// 只测与仓库状态无关的两条（脏树/未推送的判定是直白的 git 管道，且随仓库状态变化，
// 放进断言只会变成假失败）。

import { spawnSync } from 'node:child_process';
import path from 'node:path';

const hook = path.resolve(import.meta.dirname, 'hooks/stop-checklist.mjs');

function run(stdin) {
  return spawnSync('node', [hook], { input: stdin, encoding: 'utf8' });
}

const cases = [
  {
    name: 'stop_hook_active=true 必须静默放行（防无限循环）',
    stdin: '{"stop_hook_active":true}',
    check: (r) => (r.status === 0 && !r.stderr.trim() ? null : `期望 exit 0 且无 stderr，实得 exit ${r.status} / stderr ${JSON.stringify(r.stderr.slice(0, 80))}`),
  },
  {
    name: '非法 JSON 不许崩（崩了会被当成钩子故障，静默失效）',
    stdin: '{ 这不是 JSON',
    check: (r) => ([0, 2].includes(r.status) ? null : `期望 exit 0 或 2，实得 ${r.status}`),
  },
  {
    name: '空 stdin 不许崩',
    stdin: '',
    check: (r) => ([0, 2].includes(r.status) ? null : `期望 exit 0 或 2，实得 ${r.status}`),
  },
];

let failed = 0;
for (const c of cases) {
  const err = c.check(run(c.stdin));
  if (err) {
    console.error(`✗ ${c.name}\n  ${err}`);
    failed += 1;
  } else {
    console.log(`✓ ${c.name}`);
  }
}

if (failed) {
  console.error(`\n${failed} 条失败。`);
  process.exit(1);
}
console.log(`\n${cases.length} 条全部通过。`);
