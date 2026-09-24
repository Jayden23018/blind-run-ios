#!/usr/bin/env node
//
// scripts/hooks/session-context.mjs 里两个告警函数的回归测试。
//
// 为什么需要它：本机配置全绿，所以真实运行只覆盖「什么都不输出」那一条路径。
// 告警分支在这台机器上永远走不到 —— 坏了也看不出来，只会安静地不再提醒，
// 而它存在的全部意义就是提醒。各种组合在这里钉死。
//
// 顺带保证「全绿不输出」：每轮都响的提醒会被无视，这条和 stop-checklist 的去重同理。
// 2026-08-15 删掉 fork / 双推那四条用例 —— 被测的告警本身已删（口径见 AGENTS.md §11），
// 留着测一个不该存在的行为，等于把过期口径钉死。

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import {
  backendContractReadable,
  localGuardrailWarnings,
  staleUnmergedBranches,
  STALE_BEHIND_THRESHOLD,
} from './hooks/session-context.mjs';

const T = STALE_BEHIND_THRESHOLD;

// 后端契约源靶子：一个临时 git 仓库，origin/main 上有没有 docs/api_spec.yaml 由参数决定。
// 目录存在但读不到契约的两种形状都要能判出来 —— 旧写法只看目录在不在（复核 A-1）。
function scratchBackend({ git = true, withSpec = true } = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'aidrun-sctx-backend-'));
  if (!git) return dir;
  const g = (...a) => spawnSync('git', ['-c', 'user.email=t@t', '-c', 'user.name=t', ...a], { cwd: dir });
  g('init', '-q');
  fs.mkdirSync(path.join(dir, 'docs'));
  fs.writeFileSync(path.join(dir, withSpec ? 'docs/api_spec.yaml' : 'docs/other.md'), 'x\n');
  g('add', '-A');
  g('commit', '-qm', 'seed');
  g('update-ref', 'refs/remotes/origin/main', 'HEAD');
  return dir;
}
const ref = (name, ahead, behind) => ({ name, ahead, behind });

const cases = [
  {
    name: '后端目录存在但不是 git 仓库 → 契约源不可读',
    run: () => backendContractReadable(scratchBackend({ git: false })),
    check: (ok) => (ok === false ? null : '非 git 目录被判成「可读」'),
  },
  {
    name: '后端 origin/main 上没有 docs/api_spec.yaml → 契约源不可读',
    run: () => backendContractReadable(scratchBackend({ withSpec: false })),
    check: (ok) => (ok === false ? null : 'origin/main 上没有契约却被判成「可读」'),
  },
  {
    name: '后端 origin/main 上有 docs/api_spec.yaml → 可读',
    run: () => backendContractReadable(scratchBackend()),
    check: (ok) => (ok === true ? null : '契约明明在 origin/main 上，却被判成不可读'),
  },
  {
    name: 'pre-push 已装 → 不输出（全绿时保持安静）',
    run: () => localGuardrailWarnings({ prePushInstalled: true }),
    check: (out) => (out.length === 0 ? null : `期望无输出，实得 ${JSON.stringify(out)}`),
  },
  {
    name: 'pre-push 未装 → 提醒装钩子',
    run: () => localGuardrailWarnings({ prePushInstalled: false }),
    check: (out) =>
      out.length === 1 && out[0].includes('install-git-hooks.sh') && out[0].includes('pre-push')
        ? null
        : `期望恰好一条 pre-push 提醒，实得 ${JSON.stringify(out)}`,
  },
  {
    name: '没有陈旧分支 → 不输出',
    run: () =>
      staleUnmergedBranches({
        refs: [ref('origin/main', 0, 0), ref('origin/feat/live', 3, 2)],
        currentBranch: 'feat/live',
      }),
    check: (out) => (out.length === 0 ? null : `期望无输出，实得 ${JSON.stringify(out)}`),
  },
  {
    // 本次立此条的原型：feat/run-track-replay 领先 2、落后 88，主线上零 PR，
    // 而 review 里把它记成「已有在途 PR #24」挂了三天。
    name: '领先且落后超阈值 → 报出来，带 ahead/behind 数字',
    run: () =>
      staleUnmergedBranches({
        refs: [ref('origin/feat/run-track-replay', 2, 88)],
        currentBranch: 'main',
      }),
    check: (out) =>
      out.length === 1 && out[0].includes('feat/run-track-replay(+2/-88)') && !out[0].includes('origin/feat')
        ? null
        : `期望一条带 +2/-88 且去掉 origin/ 前缀的提醒，实得 ${JSON.stringify(out)}`,
  },
  {
    // 已合入的分支落后再多也无所谓 —— 它没有会丢失的东西。只有 ahead > 0 才值得报。
    name: '零独有提交但落后很多 → 不报（已合入的分支不是欠账）',
    run: () =>
      staleUnmergedBranches({
        refs: [ref('origin/chore/merged-long-ago', 0, 200)],
        currentBranch: 'main',
      }),
    check: (out) => (out.length === 0 ? null : `期望无输出，实得 ${JSON.stringify(out)}`),
  },
  {
    name: '正在开发的分支不报自己（哪怕它落后很多）',
    run: () =>
      staleUnmergedBranches({
        refs: [ref('origin/feat/wip', 4, T + 50)],
        currentBranch: 'feat/wip',
      }),
    check: (out) => (out.length === 0 ? null : `期望无输出，实得 ${JSON.stringify(out)}`),
  },
  {
    name: '刚好等于阈值不报，超一个才报（边界）',
    run: () => [
      ...staleUnmergedBranches({ refs: [ref('origin/a', 1, T)], currentBranch: 'main' }),
      ...staleUnmergedBranches({ refs: [ref('origin/b', 1, T + 1)], currentBranch: 'main' }),
    ],
    check: (out) =>
      out.length === 1 && out[0].includes('b(+1/-')
        ? null
        : `期望只报 b 一条，实得 ${JSON.stringify(out)}`,
  },
  {
    name: '多条时按落后程度降序（最久没跟进的排最前）',
    run: () =>
      staleUnmergedBranches({
        refs: [ref('origin/near', 1, T + 5), ref('origin/far', 1, T + 200)],
        currentBranch: 'main',
      }),
    check: (out) =>
      out.length === 1 && out[0].indexOf('far(') < out[0].indexOf('near(')
        ? null
        : `期望 far 排在 near 之前，实得 ${JSON.stringify(out)}`,
  },
  {
    name: 'origin/main 与裸 origin 不算欠账',
    run: () =>
      staleUnmergedBranches({
        refs: [ref('origin', 0, 0), ref('origin/main', 5, T + 10)],
        currentBranch: 'feat/x',
      }),
    check: (out) => (out.length === 0 ? null : `期望无输出，实得 ${JSON.stringify(out)}`),
  },
];

let failed = 0;
for (const c of cases) {
  const err = c.check(c.run());
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
