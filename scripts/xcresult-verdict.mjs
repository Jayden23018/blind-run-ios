#!/usr/bin/env node
//
// 把 `xcrun xcresulttool get test-results summary --format json` 的输出翻译成
// 「这次真机测试算不算通过」，并打印人可读的统计行。
//
// 为什么这段逻辑在这里而不是内联在 `scripts/device-test.sh` 里：
// 内联的话没法写自测，而自测正是这条链路最需要的东西 —— 统计口径已经错过两次
// （先是 `Test Case` 大小写全计成 0，后是三路输出并发写同一 fd 把统计行截断，
// 2026-08-07 实测 539 条只数出 530）。逻辑抽出来，`validate-xcresult-verdict.mjs` 才能钉住它。
//
// 用法：  cat summary.json | node scripts/xcresult-verdict.mjs
// 退出码：0=全过  1=有用例失败  2=结果不可信（读不出 / 零执行 / 整体结论对不上）

/**
 * @param {unknown} summary 已解析的 summary JSON（解析失败请传 null）
 * @returns {{verdict:'pass'|'fail'|'error', line:string, failures:string[], reason:string}}
 */
export function verdictFromSummary(summary) {
  if (summary === null || typeof summary !== 'object' || Array.isArray(summary)) {
    return {
      verdict: 'error',
      line: '',
      failures: [],
      reason: '读不出 result bundle 的测试统计（JSON 缺失或不是对象）。',
    };
  }

  const num = (key) => (Number.isFinite(summary[key]) ? summary[key] : null);
  const passed = num('passedTests');
  const failed = num('failedTests');
  const skipped = num('skippedTests');
  const expectedFailures = num('expectedFailures') ?? 0;
  const total = num('totalTestCount');
  const result = typeof summary.result === 'string' ? summary.result : 'Unknown';

  // 缺字段一律当不可信，不要用 0 兜底 —— 那正是「把没跑当成跑过」的入口。
  if (passed === null || failed === null || skipped === null || total === null) {
    return {
      verdict: 'error',
      line: '',
      failures: [],
      reason:
        'result bundle 的统计字段不全（passedTests/failedTests/skippedTests/totalTestCount 缺一）。' +
        ' xcresulttool 的输出格式可能变了，先人工核对再改这里。',
    };
  }

  const line =
    `passed=${passed}  failed=${failed}  skipped=${skipped}` +
    `  expectedFailures=${expectedFailures}  (total=${total})  result=${result}`;

  const failures = Array.isArray(summary.testFailures)
    ? summary.testFailures.map((item) => {
        const name = item?.testName ?? '?';
        const text = item?.failureText ?? '';
        return `${name} - ${text}`.slice(0, 400);
      })
    : [];

  if (total === 0) {
    return {
      verdict: 'error',
      line,
      failures,
      reason: '一条用例都没执行。零执行不能算通过。',
    };
  }

  if (failed > 0) {
    return { verdict: 'fail', line, failures, reason: `${failed} 条用例失败。` };
  }

  // 没有失败用例但整体结论不是 Passed：可能是异常终止之类。宁可停下来让人看一眼。
  if (result !== 'Passed') {
    return {
      verdict: 'error',
      line,
      failures,
      reason: `failed=0 但整体结论是 ${result}（不是 Passed），两者对不上，需人工确认。`,
    };
  }

  return { verdict: 'pass', line, failures, reason: '' };
}

// 只有被直接执行时才读 stdin；被 import 时（自测）不做任何事。
if (import.meta.url === `file://${process.argv[1]}`) {
  const raw = await new Promise((resolve) => {
    let buffer = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (chunk) => (buffer += chunk));
    process.stdin.on('end', () => resolve(buffer));
  });

  let parsed = null;
  try {
    parsed = JSON.parse(raw);
  } catch {
    parsed = null;
  }

  const { verdict, line, failures, reason } = verdictFromSummary(parsed);
  if (line) console.log(line);
  if (verdict !== 'pass') {
    if (failures.length) {
      console.error('失败用例：');
      for (const item of failures) console.error(`    ${item}`);
    }
    console.error(reason);
  }
  process.exit(verdict === 'pass' ? 0 : verdict === 'fail' ? 1 : 2);
}
