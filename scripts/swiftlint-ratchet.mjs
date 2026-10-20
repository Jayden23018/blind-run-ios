#!/usr/bin/env node
//
// SwiftLint 只拦新增（#488）。规则与 baseline 在 `.swiftlint.yml` / `.swiftlint-baseline.json`。
//
// 为什么不直接用 `swiftlint lint --baseline`：SwiftLint 按「违规所在那一行的原文 + 提示文字」认旧账，
// 而 file_length / *_body_length / cyclomatic_complexity 的提示文字里带当前数字
// （「currently contains 459」）。于是超长文件**删掉一行**也变成「新违规」——
// 2026-10-20 实测 blindRun/Auth/LoginView.swift 459 → 458 行照样报出。冻结时有 97 个文件超 400 行，
// 照原样接 CI，几乎每个 PR 都会红，最后只会被人整份重写 baseline 绕过。
//
// 这里只在 SwiftLint 过滤之后再补一道：同一处（同文件、同规则、同一行声明原文；file_length 每个文件只有一处）
// 在 baseline 里有记录、且数字**没变大** → 放过；变大了、或 baseline 里没有这一处 → 失败。
//
// 用法：
//   node scripts/swiftlint-ratchet.mjs                          # 调本机 swiftlint（brew install swiftlint）
//   node scripts/swiftlint-ratchet.mjs --json out.json --root /work   # 读别处跑出的 JSON（CI 用 Docker 镜像）
//   node scripts/swiftlint-ratchet.mjs --write-baseline         # 冻结现状（重写 baseline）
//   node scripts/swiftlint-ratchet.mjs --self-test

import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

// 与 .github/workflows/verify.yml 里的镜像标签保持一致。版本一变，规则的计数口径可能跟着变。
export const SWIFTLINT_VERSION = '0.65.1';
export const BASELINE_FILE = '.swiftlint-baseline.json';

const METRIC = /currently (?:contains|spans|complexity is) (\d+)/;

export function metricOf(reason) {
  const m = METRIC.exec(reason);
  return m ? Number(m[1]) : null;
}

// 与 SwiftLint 的 LineCache 同口径：第 1 行取不到原文，记成空串。
export function lineText(lines, line) {
  const index = (line ?? 0) - 1;
  return index > 0 && index < lines.length ? lines[index] : '';
}

// file_length 落在文件最后一行，最后一行的原文随增删而变，所以它只按文件认。
function entityKey(file, rule, text) {
  return [file, rule, rule === 'file_length' ? '' : text].join('\u0000');
}

// reported：SwiftLint 过滤后仍报出的违规，{ file（相对仓库根）, line, rule, reason }。
// baseline：.swiftlint-baseline.json 原样解析后的数组。
// readLines(file)：返回该文件当前的行数组。
export function judge({ reported, baseline, readLines }) {
  const pool = new Map();
  for (const entry of baseline) {
    const v = entry.violation;
    const key = entityKey(v.location.file, v.ruleIdentifier, entry.text);
    const list = pool.get(key) ?? [];
    list.push(metricOf(v.reason));
    pool.set(key, list);
  }
  for (const list of pool.values()) list.sort((a, b) => a - b);

  const failures = [];
  const tolerated = [];
  for (const v of reported) {
    const now = metricOf(v.reason);
    const key = entityKey(v.file, v.rule, lineText(readLines(v.file), v.line));
    const list = pool.get(key) ?? [];
    // 取「不小于现值」的最小那条旧账，一条旧账只抵一处。
    const at = now === null ? -1 : list.findIndex((old) => old !== null && old >= now);
    if (at === -1) {
      failures.push(v);
      continue;
    }
    tolerated.push({ ...v, was: list[at] });
    list.splice(at, 1);
  }
  return { failures, tolerated };
}

function toRelative(file, root) {
  const abs = path.resolve(root, file);
  return path.relative(root, abs).split(path.sep).join('/');
}

function runSwiftlint(args) {
  const version = spawnSync('swiftlint', ['version'], { encoding: 'utf8' });
  if (version.error) {
    console.error(`找不到 swiftlint。装：brew install swiftlint（CI 用的是 ${SWIFTLINT_VERSION}）`);
    process.exit(1);
  }
  if (version.stdout.trim() !== SWIFTLINT_VERSION) {
    console.warn(`⚠️ 本机 swiftlint ${version.stdout.trim()}，CI 用 ${SWIFTLINT_VERSION}，结果可能对不上。`);
  }
  const lint = spawnSync('swiftlint', ['lint', '--quiet', ...args], {
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
  });
  // 0 = 没有 error 级违规，2 = 有。其余是 swiftlint 自己出错（配置写错、baseline 读不了）。
  if (lint.status !== 0 && lint.status !== 2) {
    process.stderr.write(lint.stderr);
    console.error(`swiftlint 异常退出（${lint.status}），不是 lint 结论。`);
    process.exit(1);
  }
  return lint.stdout;
}

// SwiftLint 写出的 baseline 整份一行、键顺序每次随机（同样 264 条两次写出字节不同），
// PR 里看不出冻结了什么。改成一条违规一行、键按字母排，diff 才读得懂。SwiftLint 读它不受影响。
export function canonicalBaseline(entries) {
  const sortKeys = (value) => {
    if (Array.isArray(value)) return value.map(sortKeys);
    if (value && typeof value === 'object') {
      return Object.fromEntries(Object.keys(value).sort().map((k) => [k, sortKeys(value[k])]));
    }
    return value;
  };
  return `[\n${entries.map((e) => JSON.stringify(sortKeys(e))).join(',\n')}\n]\n`;
}

function writeBaseline() {
  // 同时传 --baseline 同一路径：配置里写了 baseline，文件还不存在时 SwiftLint 只在两者相同时才不报错。
  runSwiftlint(['--baseline', BASELINE_FILE, '--write-baseline', BASELINE_FILE]);
  const entries = JSON.parse(fs.readFileSync(BASELINE_FILE, 'utf8'));
  fs.writeFileSync(BASELINE_FILE, canonicalBaseline(entries));
  console.log(`已重写 ${BASELINE_FILE}：${entries.length} 条。在 PR 描述里写清楚为什么冻结。`);
}

export function parseReport(json, root) {
  const data = JSON.parse(json);
  if (!Array.isArray(data)) throw new Error('swiftlint JSON 报告应是数组');
  return data.map((v) => ({
    file: toRelative(v.file, root),
    line: v.line,
    rule: v.rule_id,
    reason: v.reason,
    severity: v.severity,
  }));
}

function main(argv) {
  const jsonAt = argv.indexOf('--json');
  const rootAt = argv.indexOf('--root');
  const reportRoot = rootAt === -1 ? process.cwd() : argv[rootAt + 1];
  const raw = jsonAt === -1 ? runSwiftlint(['--reporter', 'json']) : fs.readFileSync(argv[jsonAt + 1], 'utf8');

  let reported;
  try {
    reported = parseReport(raw, reportRoot);
  } catch (error) {
    console.error(`读不了 swiftlint 的 JSON 报告：${error.message}`);
    process.exit(1);
  }
  const baseline = JSON.parse(fs.readFileSync(BASELINE_FILE, 'utf8'));
  const readLines = (file) => fs.readFileSync(file, 'utf8').split(/\r\n|\n|\r/);
  const { failures, tolerated } = judge({ reported, baseline, readLines });

  for (const v of tolerated) console.log(`· 放过（没变大）${v.file}:${v.line} ${v.rule} ${v.was} → ${metricOf(v.reason)}`);
  if (failures.length === 0) {
    console.log(`SwiftLint：没有新增违规（baseline ${baseline.length} 条，其中 ${tolerated.length} 处变小或持平）。`);
    return;
  }
  const annotate = process.env.GITHUB_ACTIONS === 'true';
  for (const v of failures) {
    if (annotate) console.log(`::error file=${v.file},line=${v.line},title=SwiftLint ${v.rule}::${v.reason}`);
    else console.log(`✗ ${v.file}:${v.line} ${v.rule}: ${v.reason}`);
  }
  console.log(`\n${failures.length} 处新增或变大的违规。先拆分；确需冻结，重写 baseline 并在 PR 里说明为什么：`);
  console.log('  node scripts/swiftlint-ratchet.mjs --write-baseline');
  process.exit(1);
}

function selfTest() {
  const files = {
    'A.swift': ['import X', 'struct A {', '    func big() {', '    }', '}'],
    'B.swift': ['import X', '    func twin() {', '    func twin() {'],
  };
  const readLines = (file) => files[file];
  const entry = (file, line, rule, reason) => ({
    text: lineText(files[file], line),
    violation: { reason, location: { file, line, character: 1 }, ruleIdentifier: rule },
  });
  const fileLen = (n) => `File should contain 400 lines or less: currently contains ${n}`;
  const funcLen = (n) => `Function body should span 50 lines or less excluding comments and whitespace: currently spans ${n} lines`;
  const baseline = [
    entry('A.swift', 5, 'file_length', fileLen(459)),
    entry('A.swift', 3, 'function_body_length', funcLen(80)),
    entry('B.swift', 2, 'function_body_length', funcLen(60)),
  ];
  const rep = (file, line, rule, reason) => ({ file, line, rule, reason });
  const cases = [
    ['没有报出任何违规', [], 0],
    ['超长文件删一行（459 → 458），最后一行原文也变了', [rep('A.swift', 4, 'file_length', fileLen(458))], 0],
    ['超长文件持平（459）', [rep('A.swift', 5, 'file_length', fileLen(459))], 0],
    ['超长文件加一行（459 → 460）', [rep('A.swift', 5, 'file_length', fileLen(460))], 1],
    ['长函数变短（80 → 79）', [rep('A.swift', 3, 'function_body_length', funcLen(79))], 0],
    ['长函数变长（80 → 81）', [rep('A.swift', 3, 'function_body_length', funcLen(81))], 1],
    ['同一文件新出现的长函数（声明原文不在 baseline）', [rep('A.swift', 2, 'function_body_length', funcLen(51))], 1],
    ['别的文件的旧账抵不了这里', [rep('B.swift', 1, 'file_length', fileLen(401))], 1],
    // B.swift 两个同名声明，baseline 只记了一条：一条旧账只抵一处。
    ['同名声明一条旧账、两处报出', [
      rep('B.swift', 2, 'function_body_length', funcLen(55)),
      rep('B.swift', 3, 'function_body_length', funcLen(58)),
    ], 1],
    ['提示文字里没有数字，一律当新增', [rep('A.swift', 3, 'function_body_length', 'something else')], 1],
  ];
  let failed = 0;
  for (const [name, reported, expectedFailures] of cases) {
    const { failures } = judge({ reported, baseline: structuredClone(baseline), readLines });
    const ok = failures.length === expectedFailures;
    if (!ok) failed++;
    console.log(`${ok ? '✓' : '✗'} ${name}：失败 ${failures.length} 处（应为 ${expectedFailures}）`);
  }
  // 第 1 行与 SwiftLint 同口径记成空串；绝对路径按 root 转成相对路径。
  const edge = [
    [lineText(files['A.swift'], 1) === '', '第 1 行原文记成空串'],
    [parseReport(JSON.stringify([{ file: '/work/blindRun/X.swift', line: 1, rule_id: 'r', reason: '' }]), '/work')[0].file === 'blindRun/X.swift', '绝对路径转相对路径'],
  ];
  const shuffled = [{ violation: { reason: 'r', location: { line: 2, file: 'f' } }, text: 't' }];
  const canon = canonicalBaseline(shuffled);
  edge.push(
    [JSON.stringify(JSON.parse(canon)) === JSON.stringify(JSON.parse(canonicalBaseline(JSON.parse(canon)))), 'baseline 重写幂等'],
    [canon.split('\n')[1].startsWith('{"text":"t","violation":{"location":{"file":"f","line":2}'), 'baseline 键按字母排、一条一行'],
  );
  for (const [ok, name] of edge) {
    if (!ok) failed++;
    console.log(`${ok ? '✓' : '✗'} ${name}`);
  }
  if (failed) {
    console.error(`\n自测失败 ${failed} 条`);
    process.exit(1);
  }
  console.log('\n自测全部通过');
}

if (process.argv.includes('--self-test')) selfTest();
else if (process.argv.includes('--write-baseline')) writeBaseline();
else main(process.argv.slice(2));
