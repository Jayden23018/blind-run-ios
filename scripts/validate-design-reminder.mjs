#!/usr/bin/env node
//
// scripts/hooks/design-direction-reminder.mjs 的回归测试。
//
// 为什么需要它：这个钩子的两种死法都是**静默**的 —— 判据写宽了就变成每次编辑都响的噪音
// （然后被人无视，等于没有），判据写窄了或吐出非法 JSON 就完全不响
// （而「没提醒」和「不需要提醒」在日志里长得一模一样）。两种情况都不报错。
// AGENTS.md §1.2 的归宿就是这里。

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { isSwiftUIViewEdit } from './hooks/design-direction-reminder.mjs';

const hook = path.resolve(import.meta.dirname, 'hooks/design-direction-reminder.mjs');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'aidrun-design-reminder-'));
fs.mkdirSync(path.join(tmp, '.git'), { recursive: true });

const VIEW = 'struct BlindHomeView: View {\n  var body: some View { Text("x") }\n}\n';
const SERVICE = 'final class LocationService: NSObject {\n  func start() {}\n}\n';

function writeFile(rel, body) {
  const p = path.join(tmp, rel);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, body);
  return p;
}

const viewPath = writeFile('blindRun/BlindRunner/BlindHomeView.swift', VIEW);
const servicePath = writeFile('blindRun/Map/LocationService.swift', SERVICE);
const testPath = writeFile('blindRunTests/BlindHomeViewTests.swift', VIEW);
const docPath = writeFile('docs/ui/design-direction.md', '# doc\n');

/** 跑一次钩子，返回 { fired, code }。fired = 是否注入了提醒。 */
function run(payload) {
  const r = spawnSync('node', [hook], {
    input: JSON.stringify(payload),
    encoding: 'utf8',
    env: { ...process.env, CLAUDE_PROJECT_DIR: tmp },
  });
  const out = (r.stdout || '').trim();
  let fired = false;
  if (out) {
    // 吐出来的必须是合法 JSON —— 非法 JSON 是这个钩子最隐蔽的死法之一。
    const parsed = JSON.parse(out);
    fired = parsed?.hookSpecificOutput?.hookEventName === 'PreToolUse'
      && typeof parsed?.hookSpecificOutput?.additionalContext === 'string'
      && parsed.hookSpecificOutput.additionalContext.length > 0;
  }
  return { fired, code: r.status };
}

function clearSeen() {
  fs.rmSync(path.join(tmp, '.git', 'aidrun-design-reminder-seen'), { force: true });
}

const edit = (file, sid = 's1') => ({
  tool_name: 'Edit',
  tool_input: { file_path: file },
  session_id: sid,
});

const cases = [
  // ---- 纯判据（不碰进程） ----
  ['判据：View 文件命中', () => isSwiftUIViewEdit('Edit', '/x/blindRun/A/BView.swift', VIEW) === true],
  ['判据：非 View 的 .swift 不命中', () => isSwiftUIViewEdit('Edit', '/x/blindRun/Map/S.swift', SERVICE) === false],
  ['判据：测试目录不命中（哪怕内容是 View）', () => isSwiftUIViewEdit('Edit', '/x/blindRunTests/AViewTests.swift', VIEW) === false],
  ['判据：UI 测试目录不命中', () => isSwiftUIViewEdit('Edit', '/x/blindRunUITests/A.swift', VIEW) === false],
  ['判据：仓库外的 .swift 不命中', () => isSwiftUIViewEdit('Edit', '/other/Pods/A.swift', VIEW) === false],
  ['判据：Read 工具不命中', () => isSwiftUIViewEdit('Read', '/x/blindRun/A/BView.swift', VIEW) === false],
  ['判据：内容拿不到时不命中（宁可漏不可吵）', () => isSwiftUIViewEdit('Edit', '/x/blindRun/A/BView.swift', '') === false],

  // ---- 端到端 ----
  ['编辑 View 文件会提醒', () => { clearSeen(); return run(edit(viewPath)).fired === true; }],
  ['编辑 Service 不提醒', () => { clearSeen(); return run(edit(servicePath)).fired === false; }],
  ['编辑测试文件不提醒', () => { clearSeen(); return run(edit(testPath)).fired === false; }],
  ['编辑 .md 不提醒', () => { clearSeen(); return run(edit(docPath)).fired === false; }],
  ['Write 新 View 文件（磁盘上还没有）也提醒', () => {
    clearSeen();
    return run({
      tool_name: 'Write',
      tool_input: { file_path: path.join(tmp, 'blindRun/New/NewView.swift'), content: VIEW },
      session_id: 's1',
    }).fired === true;
  }],
  ['同一会话第二次不再提醒', () => {
    clearSeen();
    const first = run(edit(viewPath, 'same')).fired;
    const second = run(edit(viewPath, 'same')).fired;
    return first === true && second === false;
  }],
  ['换一个会话会重新提醒', () => {
    clearSeen();
    run(edit(viewPath, 'sessA'));
    return run(edit(viewPath, 'sessB')).fired === true;
  }],
  ['拿不到 session_id 时不提醒', () => {
    clearSeen();
    return run({ tool_name: 'Edit', tool_input: { file_path: viewPath } }).fired === false;
  }],
  ['空 stdin 不崩', () => {
    const r = spawnSync('node', [hook], { input: '', encoding: 'utf8', env: { ...process.env, CLAUDE_PROJECT_DIR: tmp } });
    return r.status === 0 && !(r.stdout || '').trim();
  }],
  ['非法 JSON 不崩', () => {
    const r = spawnSync('node', [hook], { input: '{ 这行不是 JSON', encoding: 'utf8', env: { ...process.env, CLAUDE_PROJECT_DIR: tmp } });
    return r.status === 0 && !(r.stdout || '').trim();
  }],
  ['缺 file_path 不崩', () => {
    clearSeen();
    const r = spawnSync('node', [hook], {
      input: JSON.stringify({ tool_name: 'Edit', tool_input: {}, session_id: 's1' }),
      encoding: 'utf8',
      env: { ...process.env, CLAUDE_PROJECT_DIR: tmp },
    });
    return r.status === 0 && !(r.stdout || '').trim();
  }],
  ['提醒内容带得动四步流程与关键红线', () => {
    clearSeen();
    const r = spawnSync('node', [hook], {
      input: JSON.stringify(edit(viewPath, 'content-check')),
      encoding: 'utf8',
      env: { ...process.env, CLAUDE_PROJECT_DIR: tmp },
    });
    const text = JSON.parse(r.stdout).hookSpecificOutput.additionalContext;
    // 钉住的是「这几件事必须被说到」，不是逐字文案 —— 文案可以改，这几条不能丢。
    return ['design-direction.md', '自审', 'AppColors', 'emoji', 'happy path', '64pt', '占位图']
      .every((kw) => text.includes(kw));
  }],
];

let failed = 0;
for (const [name, fn] of cases) {
  let ok = false;
  let err = '';
  try {
    ok = fn();
  } catch (e) {
    err = ` (${e.message})`;
  }
  if (ok) {
    console.log(`✓ ${name}`);
  } else {
    console.error(`✗ ${name}${err}`);
    failed += 1;
  }
}

fs.rmSync(tmp, { recursive: true, force: true });

if (failed) {
  console.error(`\n${failed} 条失败。`);
  process.exit(1);
}
console.log(`\n${cases.length} 条全部通过。`);
