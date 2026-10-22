#!/usr/bin/env node
//
// scripts/only-testing-coverage.mjs 的回归测试（#478）。
//
// 它守的是「部分零执行」：传多个 -only-testing 时，写错的那个目标被 xcodebuild 静默忽略，
// 而总数不为 0，于是 `xcresult-verdict.mjs` 照常报通过。2026-10-19 #473 实测
// `passed=33 failed=0`，新写的用例一次都没跑。
//
// 下面的样本按真机 `xcrun xcresulttool get test-results tests --format json` 的形状造
// （2026-10-22 从 iPhone 16 Pro / iOS 27.0.1 的 result bundle 核对过层级与字段名）：
//   Test Plan → Unit test bundle / UI test bundle → Test Suite（类）→ Test Case（方法，名字带 `()`）
//   → 附件 / Runtime Warning 之类的叶子。

import { readFileSync } from 'node:fs';
import { coverageFromTests, onlyTestingTargets } from './only-testing-coverage.mjs';

const testCase = (suite, method) => ({
  name: `${method}()`,
  nodeIdentifier: `${suite}/${method}()`,
  nodeType: 'Test Case',
  result: 'Passed',
  // 真实样本里用例节点下面会挂运行时警告，不能被当成用例。
  children: [{ name: 'AVAudioSession_iOS.mm:978 …', nodeType: 'Runtime Warning' }],
});

const suite = (name, methods) => ({
  name,
  nodeType: 'Test Suite',
  result: 'Passed',
  children: methods.map((method) => testCase(name, method)),
});

const SAMPLE = {
  devices: [{ deviceName: 'iPhone', platform: 'iOS' }],
  testNodes: [
    {
      name: 'blindRun',
      nodeType: 'Test Plan',
      result: 'Passed',
      children: [
        {
          name: 'blindRunTests',
          nodeType: 'Unit test bundle',
          result: 'Passed',
          children: [
            suite('MockBlindIdentityVerificationTests', ['testA', 'testB']),
            suite('EmergencySOSTests', ['testTrigger', 'testCancel', 'testDial']),
            // 名字是另一个类的前缀，用来钉住「逐段比较、不比字符串前缀」。
            suite('EmergencySOSTestsExtra', ['testExtra']),
          ],
        },
        {
          name: 'blindRunUITests',
          nodeType: 'UI test bundle',
          result: 'Passed',
          children: [suite('BlindHomeUITests', ['testHomeShowsSOS'])],
        },
      ],
    },
  ],
};

const run = (args, tests = SAMPLE) => coverageFromTests(tests, onlyTestingTargets(args));
const countOf = (r, target) => r.counts.find((item) => item.target === target)?.count;

const cases = [
  {
    name: '全部目标都命中（三种粒度 + 两个测试目标）→ pass',
    check: () => {
      const r = run([
        '-only-testing:blindRunTests',
        '-only-testing:blindRunTests/EmergencySOSTests',
        '-only-testing:blindRunTests/EmergencySOSTests/testCancel',
        '-only-testing:blindRunUITests/BlindHomeUITests/testHomeShowsSOS()',
      ]);
      if (r.verdict !== 'pass') return `期望 pass，实得 ${r.verdict} / ${r.reason}`;
      const want = { blindRunTests: 6, 'blindRunTests/EmergencySOSTests': 3, 'blindRunTests/EmergencySOSTests/testCancel': 1,
        'blindRunUITests/BlindHomeUITests/testHomeShowsSOS()': 1,
      };
      for (const [target, n] of Object.entries(want)) {
        if (countOf(r, target) !== n) return `${target} 期望 ${n} 条，实得 ${countOf(r, target)}`;
      }
      return null;
    },
  },
  {
    // #473 原样：文件名当类名，另外两个目标正确。总数不为 0，旧判定会报通过。
    name: '一个类级目标零命中 → error，并点名那个目标',
    check: () => {
      const r = run([
        '-only-testing:blindRunTests/BlindIdentityAndContactModelTests',
        '-only-testing:blindRunTests/MockBlindIdentityVerificationTests',
        '-only-testing:blindRunTests/EmergencySOSTests',
      ]);
      if (r.verdict !== 'error') return `期望 error，实得 ${r.verdict}`;
      if (!r.reason.includes('-only-testing:blindRunTests/BlindIdentityAndContactModelTests')) {
        return `失败文案没点名零命中的目标：${r.reason}`;
      }
      if (r.reason.includes('-only-testing:blindRunTests/EmergencySOSTests')) return '把命中了的目标也报成了零命中';
      if (!r.reason.includes("grep -rn 'class .*: XCTestCase'")) return '失败文案没给查类名的命令';
      return null;
    },
  },
  {
    name: '方法级目标零命中（方法在别的类里）→ error',
    check: () => {
      const r = run([
        '-only-testing:blindRunTests/EmergencySOSTests/testTrigger',
        '-only-testing:blindRunTests/EmergencySOSTests/testA',
      ]);
      if (r.verdict !== 'error') return `期望 error，实得 ${r.verdict}`;
      return countOf(r, 'blindRunTests/EmergencySOSTests/testA') === 0 &&
        countOf(r, 'blindRunTests/EmergencySOSTests/testTrigger') === 1
        ? null
        : `计数不对：${JSON.stringify(r.counts)}`;
    },
  },
  {
    name: '测试目标名写错（写成 App 名）→ error',
    check: () => {
      const r = run(['-only-testing:blindRun/EmergencySOSTests', '-only-testing:blindRunTests/EmergencySOSTests']);
      return r.verdict === 'error' && countOf(r, 'blindRun/EmergencySOSTests') === 0 ? null : `实得 ${r.verdict} / ${JSON.stringify(r.counts)}`;
    },
  },
  {
    // `EmergencySOS` 是 `EmergencySOSTests` 的字符串前缀；按字符串比会误判成命中。
    name: '类名只是另一个类的前缀 → 不算命中',
    check: () => {
      const r = run(['-only-testing:blindRunTests/EmergencySOS']);
      return r.verdict === 'error' && countOf(r, 'blindRunTests/EmergencySOS') === 0 ? null : `实得 ${r.verdict} / ${JSON.stringify(r.counts)}`;
    },
  },
  {
    name: '不传 -only-testing → pass，不读用例树（全量跑行为不变）',
    check: () => {
      const r = run(['-skip-testing:blindRunTests/EmergencySOSTests'], null);
      return r.verdict === 'pass' && r.counts.length === 0 ? null : `实得 ${r.verdict} / ${r.reason}`;
    },
  },
  {
    name: '-skip-testing 不被当成目标；两参数写法 `-only-testing T/C` 也认',
    check: () => {
      const targets = onlyTestingTargets([
        '-skip-testing:blindRunTests/EmergencySOSTests/testDial',
        '-only-testing',
        'blindRunTests/EmergencySOSTests',
        'DEVELOPMENT_TEAM=X',
      ]);
      return JSON.stringify(targets) === JSON.stringify(['blindRunTests/EmergencySOSTests']) ? null : `实得 ${JSON.stringify(targets)}`;
    },
  },
  {
    name: '用例树读不出（null / 没有 testNodes）→ error，不许当通过',
    check: () => {
      const a = run(['-only-testing:blindRunTests'], null);
      const b = run(['-only-testing:blindRunTests'], { devices: [] });
      return a.verdict === 'error' && b.verdict === 'error' ? null : `实得 ${a.verdict} / ${b.verdict}`;
    },
  },
  {
    // 判定写对了但 device-test.sh 没调它，或调了不看退出码，一样是假绿。
    name: 'device-test.sh 把全部参数传给这个判定，并按退出码硬失败',
    check: () => {
      const lines = readFileSync(new URL('./device-test.sh', import.meta.url), 'utf8')
        .split('\n')
        .filter((line) => !line.trim().startsWith('#'));
      const code = lines.join('\n');
      if (!lines.some((line) => /only-testing-coverage\.mjs"?\s+"\$@"/.test(line))) {
        return 'device-test.sh 里没有把 "$@" 传给 only-testing-coverage.mjs 的调用';
      }
      if (!/COVERAGE_STATUS="\$\{PIPESTATUS\[1\]\}"/.test(code)) return '没取管道里 node 那一段的退出码';
      if (!/if \[ "\$COVERAGE_STATUS" -ne 0 \]; then\s*\n\s*die /.test(code)) return '没有按 COVERAGE_STATUS 非 0 硬失败';
      return null;
    },
  },
];

let failed = 0;
for (const c of cases) {
  let err;
  try {
    err = c.check();
  } catch (error) {
    err = `抛异常：${error.message}`;
  }
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
