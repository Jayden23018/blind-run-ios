#!/usr/bin/env node
//
// scripts/hooks/session-context.mjs 里 localGuardrailWarnings 的回归测试。
//
// 为什么需要它：本机三项配置全绿，所以真实运行只覆盖「什么都不输出」那一条路径。
// 告警分支在这台机器上永远走不到 —— 坏了也看不出来，只会安静地不再提醒，
// 而它存在的全部意义就是提醒。四种组合在这里钉死。
//
// 顺带保证「全绿不输出」：每轮都响的提醒会被无视，这条和 stop-checklist 的去重同理。

import { localGuardrailWarnings } from './hooks/session-context.mjs';

const UPSTREAM = 'https://github.com/JerryZhao-1/blind-run-ios.git';
const FORK = 'https://github.com/Jayden23018/blind-run-ios.git';

const cases = [
  {
    name: '三项齐全 → 不输出（全绿时保持安静）',
    input: { prePushInstalled: true, forkUrl: FORK, pushUrls: [UPSTREAM, FORK] },
    check: (out) => (out.length === 0 ? null : `期望无输出，实得 ${JSON.stringify(out)}`),
  },
  {
    name: 'pre-push 未装 → 提醒装钩子',
    input: { prePushInstalled: false, forkUrl: FORK, pushUrls: [UPSTREAM, FORK] },
    check: (out) =>
      out.length === 1 && out[0].includes('install-git-hooks.sh') && out[0].includes('pre-push')
        ? null
        : `期望恰好一条 pre-push 提醒，实得 ${JSON.stringify(out)}`,
  },
  {
    name: '没有 fork remote → 提醒加 remote，且不重复报双推',
    input: { prePushInstalled: true, forkUrl: '', pushUrls: [UPSTREAM] },
    check: (out) =>
      out.length === 1 && out[0].includes('git remote add fork')
        ? null
        : `期望恰好一条 fork remote 提醒，实得 ${JSON.stringify(out)}`,
  },
  {
    // 最容易悄无声息发生的一种：remote 加了、装钩子脚本没重跑，push 只到上游。
    name: '有 fork 但 pushurl 里没有它 → 报双推未生效',
    input: { prePushInstalled: true, forkUrl: FORK, pushUrls: [UPSTREAM] },
    check: (out) =>
      out.length === 1 && out[0].includes('双推未生效') && out[0].includes(FORK)
        ? null
        : `期望一条双推提醒且带 fork URL，实得 ${JSON.stringify(out)}`,
  },
  {
    name: 'pushurl 完全没配（只有默认 origin）→ 同样报双推未生效',
    input: { prePushInstalled: true, forkUrl: FORK, pushUrls: [] },
    check: (out) =>
      out.length === 1 && out[0].includes('双推未生效')
        ? null
        : `期望一条双推提醒，实得 ${JSON.stringify(out)}`,
  },
  {
    name: '全都没配 → 两条提醒（钩子 + fork remote）',
    input: { prePushInstalled: false, forkUrl: '', pushUrls: [] },
    check: (out) => (out.length === 2 ? null : `期望 2 条，实得 ${out.length}：${JSON.stringify(out)}`),
  },
];

let failed = 0;
for (const c of cases) {
  const err = c.check(localGuardrailWarnings(c.input));
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
