#!/usr/bin/env node
//
// scripts/xcresult-verdict.mjs 的回归测试。
//
// 为什么需要它：真机跑测的统计口径已经错过两次，两次都是「看起来全绿，其实没数到」：
//   1. 按 `Test Case`（大写 C）grep，全部计成 0 —— 于是 0 失败像是全过。
//   2. xcodebuild 进度、XCTest runner stdout、设备 os_log 三路并发写同一个 fd，
//      `Test case '...' passed` 被拦腰截断。2026-08-07 同一天四次实测（旧脚本 → bundle 真值）：
//      528→535、29→30、73→73、530→539。
//
// 两次都属于「命令回来了、看起来一切正常，但结论是错的」。这个文件钉住的就是这类：
// **任何读不出/对不上的情况都必须报不可信，绝不能落到 pass。**

import { readFileSync } from 'node:fs';
import { verdictFromSummary } from './xcresult-verdict.mjs';

const cases = [
  {
    name: '全过 → pass',
    input: { passedTests: 539, failedTests: 0, skippedTests: 0, expectedFailures: 0, totalTestCount: 539, result: 'Passed' },
    check: (r) => (r.verdict === 'pass' && r.line.includes('passed=539') ? null : `期望 pass，实得 ${r.verdict} / ${r.line}`),
  },
  {
    name: '有失败 → fail，且带出失败用例名与断言原文',
    input: {
      passedTests: 30, failedTests: 3, skippedTests: 0, expectedFailures: 0, totalTestCount: 33, result: 'Failed',
      testFailures: [{ testName: 'testFoo()', failureText: 'XCTAssertEqual failed: ("a") is not equal to ("b")' }],
    },
    check: (r) =>
      r.verdict === 'fail' && r.failures.length === 1 && r.failures[0].includes('testFoo()') && r.failures[0].includes('not equal')
        ? null
        : `期望 fail 且带失败详情，实得 ${r.verdict} / ${JSON.stringify(r.failures)}`,
  },
  {
    name: '零执行 → error（不是 pass）',
    input: { passedTests: 0, failedTests: 0, skippedTests: 0, expectedFailures: 0, totalTestCount: 0, result: 'Passed' },
    check: (r) => (r.verdict === 'error' && r.reason.includes('零执行') ? null : `期望 error/零执行，实得 ${r.verdict} / ${r.reason}`),
  },
  {
    // 最阴的一种：xcresulttool 换了输出格式，字段没了。用 0 兜底就会变成「零执行」甚至「全过」。
    name: '统计字段缺失 → error（不许用 0 兜底）',
    input: { result: 'Passed' },
    check: (r) => (r.verdict === 'error' && r.reason.includes('统计字段不全') ? null : `期望 error/字段不全，实得 ${r.verdict} / ${r.reason}`),
  },
  {
    name: 'JSON 解析失败（传 null）→ error',
    input: null,
    check: (r) => (r.verdict === 'error' ? null : `期望 error，实得 ${r.verdict}`),
  },
  {
    name: '数组而不是对象 → error',
    input: [],
    check: (r) => (r.verdict === 'error' ? null : `期望 error，实得 ${r.verdict}`),
  },
  {
    // failed=0 但整体不是 Passed（异常终止之类）—— 不许糊过去。
    name: 'failed=0 但 result 不是 Passed → error',
    input: { passedTests: 10, failedTests: 0, skippedTests: 0, expectedFailures: 0, totalTestCount: 10, result: 'Failed' },
    check: (r) => (r.verdict === 'error' && r.reason.includes('对不上') ? null : `期望 error/对不上，实得 ${r.verdict} / ${r.reason}`),
  },
  {
    name: 'expectedFailures 不算失败，仍是 pass',
    input: { passedTests: 10, failedTests: 0, skippedTests: 1, expectedFailures: 2, totalTestCount: 13, result: 'Passed' },
    check: (r) =>
      r.verdict === 'pass' && r.line.includes('expectedFailures=2') ? null : `期望 pass 且报出 expectedFailures，实得 ${r.verdict} / ${r.line}`,
  },
  {
    name: 'expectedFailures 字段缺失时按 0 处理（它本就可选）',
    input: { passedTests: 5, failedTests: 0, skippedTests: 0, totalTestCount: 5, result: 'Passed' },
    check: (r) => (r.verdict === 'pass' && r.line.includes('expectedFailures=0') ? null : `期望 pass，实得 ${r.verdict} / ${r.line}`),
  },
];

// ---------------------------------------------------------------------------
// 附带守一条不在 verdictFromSummary 里、但属于同一族的东西：
// `device-test.sh` 的 preflight 看门狗靠 grep 日志判断「已经开始跑用例」。
//
// 2026-09-10 第三次栽在同一个坑上：那条 grep 只认小写 `Test case '`，而本机 Xcode
// **只产出大写 `Test Case '`** ⇒ 条件恒为假、看门狗永远等不到进度信号，
// 全量跑必然在超时时被当成锁屏掐掉（日志里 UI 用例明明在跑，结尾 `** BUILD INTERRUPTED **`）。
// 定向跑没暴露，是因为它们在超时前整个跑完了 —— 循环因进程结束而退出，不是因为找到了标记。
//
// 这条断言的作用是**逼下一个改这行的人保持大小写兼容**，不是测 grep 本身。
{
  const script = readFileSync(new URL('./device-test.sh', import.meta.url), 'utf8');
  const markerGreps = script
    .split('\n')
    .filter((line) => !line.trim().startsWith('#'))
    // 三种写法都要认得出来：`Test Case` / `Test case` / 已修好的 `Test [Cc]ase`。
    // 少认一种的后果是这条断言自己报「找不到 grep」——那和它想守的东西无关，纯噪音。
    .filter((line) => /grep[^\n]*Test\s+(\[Cc\]|[Cc])ase/.test(line));

  cases.push({
    name: 'device-test.sh 的用例进度标记 grep 必须大小写兼容',
    input: null,
    check: () => {
      if (markerGreps.length === 0) {
        return 'device-test.sh 里找不到判断「已经开始跑用例」的 grep —— 改了名字就把这条断言一起更新';
      }
      const caseSensitive = markerGreps.filter((line) => !/\[Cc\]/.test(line));
      return caseSensitive.length === 0
        ? null
        : `这些 grep 只认一种大小写，全量跑会被误判成锁屏：\n    ${caseSensitive.map((l) => l.trim()).join('\n    ')}`;
    },
  });
}

let failed = 0;
for (const c of cases) {
  let err;
  try {
    err = c.check(verdictFromSummary(c.input));
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
