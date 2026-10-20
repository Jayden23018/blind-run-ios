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
  countCheckboxes,
  localGuardrailWarnings,
  openSpecSummary,
  staleUnmergedBranches,
  STALE_BEHIND_THRESHOLD,
  STALE_LIST_COMMAND,
} from './hooks/session-context.mjs';
import { completedUnarchivedChanges } from './hooks/openspec-reminder.mjs';

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
const change = (name, done, todo) => ({ name, done, todo });

// OpenSpec 靶子：openspec/changes/<name>/tasks.md，内容由参数给。
function scratchChanges(tasksByName) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'aidrun-sctx-openspec-'));
  for (const [name, body] of Object.entries(tasksByName)) {
    fs.mkdirSync(path.join(root, 'openspec/changes', name), { recursive: true });
    fs.writeFileSync(path.join(root, 'openspec/changes', name, 'tasks.md'), body);
  }
  return root;
}

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
    // 而 review 里把它记成「已有在途 PR #24」挂了三天。#482 起只报条数 + 查看命令，不列名。
    name: '领先且落后超阈值 → 报条数和查看命令，不列分支名',
    run: () =>
      staleUnmergedBranches({
        refs: [ref('origin/feat/run-track-replay', 2, 88)],
        currentBranch: 'main',
      }),
    check: (out) =>
      out.length === 1 && out[0].includes('1 条') && out[0].includes(STALE_LIST_COMMAND) && !out[0].includes('run-track-replay')
        ? null
        : `期望一条只带条数与查看命令、不含分支名的提醒，实得 ${JSON.stringify(out)}`,
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
    // a 落在阈值上不算、b 超一个才算 ⇒ 条数是 1 不是 2（阈值被放宽成 >= 时这条会报 2 条）。
    name: '刚好等于阈值不报，超一个才报（边界，按条数判）',
    run: () => staleUnmergedBranches({ refs: [ref('origin/a', 1, T), ref('origin/b', 1, T + 1)], currentBranch: 'main' }),
    check: (out) =>
      out.length === 1 && out[0].includes('⚠️ 1 条')
        ? null
        : `期望只数到 b 一条，实得 ${JSON.stringify(out)}`,
  },
  {
    // 原来只列前 5 条；现在一条都不列，条数仍是全量。
    name: '12 条陈旧分支 → 条数 12，一个名字都不出现',
    run: () =>
      staleUnmergedBranches({
        refs: Array.from({ length: 12 }, (_, i) => ref(`origin/stale-${i}`, 1, T + 1 + i)),
        currentBranch: 'main',
      }),
    check: (out) =>
      out.length === 1 && out[0].includes('12 条') && !out[0].includes('stale-')
        ? null
        : `期望总数 12 且不列名，实得 ${JSON.stringify(out)}`,
  },
  {
    // 进行中 = 有勾有没勾；未开工 = 一个没勾；待归档 = 有勾且全勾。三类各给不同的数，数错一类就对不上。
    name: 'OpenSpec 计数：进行中 2、未开工 1、待归档 3，只点名待归档',
    run: () =>
      openSpecSummary([
        change('wip-a', 2, 1),
        change('wip-b', 1, 5),
        change('fresh-c', 0, 4),
        change('done-z', 3, 0),
        change('done-x', 1, 0),
        change('done-y', 6, 0),
      ]),
    check: (out) => {
      if (out.length !== 2) return `期望两行（计数 + 待归档），实得 ${JSON.stringify(out)}`;
      if (!out[0].includes('未归档 6 个') || !out[0].includes('进行中 2') || !out[0].includes('未开工 1') || !out[0].includes('待归档 3'))
        return `计数不对：${out[0]}`;
      if (['wip-a', 'wip-b', 'fresh-c', 'done-'].some((n) => out[0].includes(n))) return `计数行里出现了变更名：${out[0]}`;
      if (!out[1].includes('done-x、done-y、done-z') || out[1].includes('wip-') || out[1].includes('fresh-'))
        return `待归档行应只按名字排序列出三个 done-*：${out[1]}`;
      return null;
    },
  },
  {
    name: 'OpenSpec 没有待归档 → 只有计数一行，不出现任何变更名',
    run: () => openSpecSummary([change('wip-a', 1, 1), change('fresh-b', 0, 2)]),
    check: (out) =>
      out.length === 1 && out[0].includes('待归档 0') && !out[0].includes('wip-a') && !out[0].includes('fresh-b')
        ? null
        : `期望只有一行计数，实得 ${JSON.stringify(out)}`,
  },
  {
    name: 'OpenSpec 一个未归档变更都没有 → 不输出',
    run: () => openSpecSummary([]),
    check: (out) => (out.length === 0 ? null : `期望无输出，实得 ${JSON.stringify(out)}`),
  },
  {
    // 两个钩子对「全勾」的判据必须是同一个：开场说 0 个待归档、Stop 钩子却拦人，等于开场在撒谎。
    // 缩进的子任务与大写 X 是两处判据最容易分叉的地方。
    name: '「待归档」与 Stop 钩子（openspec-reminder）判的是同一批（缩进子任务、大写 X）',
    run: () => {
      const bodies = {
        'nested-todo': '- [x] 1.1 a\n  - [ ] 1.2 b\n',
        'upper-x-done': '- [X] 1.1 a\n- [x] 1.2 b\n',
        'nothing-checked': '- [ ] 1.1 a\n',
      };
      const root = scratchChanges(bodies);
      const ours = openSpecSummary(Object.entries(bodies).map(([name, b]) => ({ name, ...countCheckboxes(b) })));
      return { ours, theirs: completedUnarchivedChanges(root) };
    },
    check: ({ ours, theirs }) =>
      theirs.join() === 'upper-x-done' && ours.length === 2 && ours[1].endsWith('：upper-x-done') && ours[0].includes('进行中 1') && ours[0].includes('未开工 1')
        ? null
        : `两边判据分叉：Stop 钩子 ${JSON.stringify(theirs)}，开场 ${JSON.stringify(ours)}`,
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
