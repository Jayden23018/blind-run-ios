#!/usr/bin/env node
//
// scripts/hooks/openspec-reminder.mjs 的回归测试（开工前提醒 + 收尾核对共用的判据）。
//
// 判据写错时两个方向都是静默的：太宽 → 每次改源码都响，被当噪音无视；
// 太窄 → 永远不响，而「没提醒」和「不需要提醒」在日志里长得一模一样。
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { completedUnarchivedChanges, isOpenSpecChange, isProductionSwift } from './hooks/openspec-reminder.mjs';

const hook = path.resolve(import.meta.dirname, 'hooks/openspec-reminder.mjs');
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'aidrun-openspec-reminder-'));

function run(payload, seen) {
  const r = spawnSync('node', [hook], {
    input: JSON.stringify(payload),
    encoding: 'utf8',
    env: { ...process.env, AIDRUN_REPO_ROOT: scratch, AIDRUN_OPENSPEC_REMINDER_SEEN: seen },
  });
  if (r.status !== 0) throw new Error(`钩子 exit ${r.status}：${r.stderr}`);
  if (!r.stdout.trim()) return false;
  // 吐出来的必须是合法 JSON —— 非法 JSON 会被 Claude Code 丢掉，等于不响。
  return JSON.parse(r.stdout).hookSpecificOutput.additionalContext.includes('OpenSpec 提醒');
}

function transcript(name, files) {
  const p = path.join(scratch, name);
  // 目录要真的存在：transcript.mjs 的 realish 只解析目录，目录不在时路径停在 /var/…
  // 而仓库根被解析成 /private/var/…，两边对不上就被当成仓库外的文件。
  for (const f of files) fs.mkdirSync(path.dirname(path.join(scratch, f)), { recursive: true });
  fs.writeFileSync(
    p,
    files
      .map((f) =>
        JSON.stringify({
          timestamp: new Date().toISOString(),
          message: { content: [{ type: 'tool_use', name: 'Edit', input: { file_path: path.join(scratch, f) } }] },
        })
      )
      .join('\n') + '\n'
  );
  return p;
}

let n = 0;
const seenFile = () => path.join(scratch, `seen-${++n}`);
const edit = (file, extra = {}) => ({
  tool_name: 'Edit',
  tool_input: { file_path: path.join(scratch, file) },
  session_id: `s-${n}`,
  ...extra,
});

const cases = [
  ['App 源码判为生产代码', () => isProductionSwift('blindRun/Xinghuo/XinghuoMapView.swift')],
  ['单测目标不算（前缀 blindRunTests/ 不能被 blindRun/ 误吃）', () => !isProductionSwift('blindRunTests/ATests.swift')],
  ['UI 测试目标不算', () => !isProductionSwift('blindRunUITests/AuditTests.swift')],
  ['非 Swift 不算', () => !isProductionSwift('blindRun/Info.plist')],
  ['变更目录里的文件算走了 OpenSpec', () => isOpenSpecChange('openspec/changes/x/tasks.md')],
  ['主规格目录不算（那是归档的产物，不是本轮在走变更）', () => !isOpenSpecChange('openspec/specs/x/spec.md')],
  ['改 App 源码时响', () => run(edit('blindRun/A.swift'), seenFile())],
  ['改测试时不响', () => !run(edit('blindRunTests/ATests.swift'), seenFile())],
  ['Read 不响', () => !run({ ...edit('blindRun/A.swift'), tool_name: 'Read' }, seenFile())],
  ['拿不到 session_id 不响（提醒宁可漏不可吵）', () => !run({ ...edit('blindRun/A.swift'), session_id: undefined }, seenFile())],
  [
    '同一会话只响一次，换会话重新响',
    () => {
      const seen = seenFile();
      const p = { ...edit('blindRun/A.swift'), session_id: 'same' };
      return run(p, seen) && !run(p, seen) && run({ ...p, session_id: 'other' }, seen);
    },
  ],
  [
    '本会话已经碰过 openspec/changes/ 就不响',
    () =>
      !run(
        edit('blindRun/A.swift', {
          transcript_path: transcript('with-spec.jsonl', ['openspec/changes/x/tasks.md']),
        }),
        seenFile()
      ),
  ],
  [
    '本会话只碰过别的文件时照响',
    () => run(edit('blindRun/A.swift', { transcript_path: transcript('no-spec.jsonl', ['docs/x.md']) }), seenFile()),
  ],
  [
    '待归档判据：全勾才算，一个没勾 / 部分勾 / 已归档都不算',
    () => {
      const root = fs.mkdtempSync(path.join(os.tmpdir(), 'aidrun-openspec-changes-'));
      const put = (name, text) => {
        fs.mkdirSync(path.join(root, 'openspec/changes', name), { recursive: true });
        fs.writeFileSync(path.join(root, 'openspec/changes', name, 'tasks.md'), text);
      };
      put('done', '- [x] a\n  - [x] nested\n');
      put('partial', '- [x] a\n  - [ ] nested\n');
      put('empty', '# Tasks\n');
      put('archive/old', '- [x] a\n');
      const got = completedUnarchivedChanges(root);
      fs.rmSync(root, { recursive: true, force: true });
      return JSON.stringify(got) === '["done"]' || (console.error(`  实得 ${JSON.stringify(got)}`), false);
    },
  ],
];

let failed = 0;
for (const [name, fn] of cases) {
  let ok;
  try {
    ok = fn();
  } catch (e) {
    console.error(`  ${e.message}`);
    ok = false;
  }
  console.log(`${ok ? '✓' : '✗'} ${name}`);
  if (!ok) failed += 1;
}
fs.rmSync(scratch, { recursive: true, force: true });
if (failed) {
  console.error(`\n${failed} 条失败。`);
  process.exit(1);
}
console.log(`\n[validate-openspec-reminder] ${cases.length} 条全部通过`);
