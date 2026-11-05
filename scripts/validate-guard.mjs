#!/usr/bin/env node
//
// scripts/hooks/guard.mjs 的回归测试。
//
// 为什么需要它：守卫的每条规则都是「改坏了没有任何东西会报警」的类型，
// AGENTS.md 第 1 节要求这类事落到机器归宿，这就是那个归宿。
// （2026-10-03 起 project.pbxproj 已解冻，只剩 Podfile 整文件冻结与内容级规则。）
//
// 用例按主题分在 `scripts/validate-guard/` 下，与 `scripts/hooks/guard/` 的模块一一对应（#722）：
// 改哪条规则，就读那个主题的用例文件。本文件只管搭台子（materialize）和逐条跑。

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { cases as casesRepoFiles } from './validate-guard/repo-files.mjs';
import { cases as casesSwiftEdits } from './validate-guard/swift-edits.mjs';
import { cases as casesScriptsAndCI } from './validate-guard/scripts-and-ci.mjs';
import { cases as casesUITestIdentifiers } from './validate-guard/ui-test-identifiers.mjs';
import { cases as casesTestTarget } from './validate-guard/test-target.mjs';
import { cases as casesRulesCopy } from './validate-guard/rules-copy.mjs';
import { cases as casesRulesUI } from './validate-guard/rules-ui.mjs';
import { cases as casesRulesSafety } from './validate-guard/rules-safety.mjs';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const guard = path.join(scriptDir, 'hooks', 'guard.mjs');

// exit 2 = 守卫拦下（Claude Code 的 PreToolUse 约定），exit 0 = 放行。
const cases = [
  ...casesRepoFiles,
  ...casesSwiftEdits,
  ...casesScriptsAndCI,
  ...casesUITestIdentifiers,
  ...casesTestTarget,
  ...casesRulesCopy,
  ...casesRulesUI,
  ...casesRulesSafety,
];

// post 模式的内容规则是**从磁盘读改动后的真实文件**再查的，所以这类用例得落一个真文件。
//
// 路径放在临时目录里，但要造出 `/blindRun/` 这一段 —— 守卫用它区分生产代码与测试代码
// （`guard.mjs` 末尾的路径过滤）。**不要**写进真实的 `blindRun/` 目录：本工程是文件系统
// 同步式的（`PBXFileSystemSynchronizedRootGroup`），那里多一个 .swift 会直接被编进 target，
// 用例中断时残留文件会让整个工程编译不过。
// `stale-ui-test-identifier` 是本文件里唯一的**跨文件**规则：它要同时读 blindRun/ 与
// blindRunUITests/ 才判得了。所以这类用例得先造一个最小仓库出来，再对里面某个文件发 Edit。
// 用 `/x/...` 那种假路径不行 —— 守卫读不到两侧目录时会按「宁可漏不可误」直接放行，
// 于是所有用例都变成恒过，测不出任何东西。
function materializeRepo(testCase) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'aidrun-guard-repo-'));
  for (const [relative, contents] of Object.entries(testCase.repoFiles)) {
    const full = path.join(dir, relative);
    fs.mkdirSync(path.dirname(full), { recursive: true });
    fs.writeFileSync(full, contents, 'utf8');
  }
  return {
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: path.join(dir, testCase.editPath),
        old_string: testCase.oldString ?? 'PLACEHOLDER_OLD',
        new_string: testCase.newString ?? ''
      }
    },
    cleanup: () => fs.rmSync(dir, { recursive: true, force: true })
  };
}

function materialize(testCase) {
  if (testCase.mode === 'repo') return materializeRepo(testCase);
  if (testCase.mode !== 'post') return { input: testCase.input, cleanup: () => {} };

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'aidrun-guard-'));
  // 默认落进生产 target —— 内容级规则只查那里（post 段有一道 `/blindRun/` 过滤）。
  // 少数规则按**文件名**匹配且被查的文件住在测试 target（`a11y-audit-types` 只认
  // `AccessibilityAuditTests.swift`），这类用例用 `swiftPath` 指定相对路径。
  // 名字写错会静默变成「规则没触发」= 恒过，所以每条这样的用例都要配一条反向用例。
  const relative = testCase.swiftPath ?? path.join('blindRun', 'Shared', 'GuardSelfTest.swift');
  const filePath = path.join(dir, relative);
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${testCase.swift}\n`, 'utf8');

  return {
    input: { tool_name: 'Edit', tool_input: { file_path: filePath } },
    cleanup: () => fs.rmSync(dir, { recursive: true, force: true })
  };
}

let failed = false;

for (const testCase of cases) {
  const { input, cleanup } = materialize(testCase);
  // `mode` 说的是**用例怎么搭台子**（假路径 / 落一个真文件 / 造一个最小仓库），
  // 不是守卫的运行模式。只有 'post' 两者同名 —— 其余一律按 pre 跑。
  // 混用过一次：`mode: 'repo'` 被原样传成 argv，`guard.mjs` 把它归成 post，
  // 整个 pre 段（含被测的那条规则）压根没执行，两条「该拦」的用例安静地返回 0。
  const guardMode = testCase.mode === 'post' ? 'post' : 'pre';
  const result = spawnSync('node', [guard, guardMode], {
    input: JSON.stringify(input),
    encoding: 'utf8'
  });
  cleanup();
  const status = result.status ?? -1;
  if (status !== testCase.expect) {
    console.error(
      `[validate-guard] ${testCase.name}：期望 exit=${testCase.expect}，实际 exit=${status}` +
        (result.stderr ? `\n  守卫输出：${result.stderr.trim().split('\n')[0]}` : '')
    );
    failed = true;
  }
}

if (failed) {
  process.exitCode = 1;
} else {
  console.log(`[validate-guard] ${cases.length} 条守卫用例全部通过`);
}
