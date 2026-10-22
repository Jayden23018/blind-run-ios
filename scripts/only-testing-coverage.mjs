#!/usr/bin/env node
//
// 按每个 `-only-testing` 目标，数它在 result bundle 里命中了几条用例。
// 任何一个目标命中 0 条，这次真机测试就不算通过，并点名是哪个目标。
//
// 为什么需要它（#478）：xcodebuild 会**静默忽略**写错的 `-only-testing` 目标。
// `xcresult-verdict.mjs` 只在**总数**为 0 时判「零执行」，所以只要另一个目标命中了用例，
// 写错的那个目标一条没跑也照样报通过。2026-10-19 #473 实测：
// `-only-testing:blindRunTests/BlindIdentityAndContactModelTests` 是**文件名**，
// 文件里的类叫 `MockBlindIdentityVerificationTests` 等；连同另外两个正确的类一起传，
// 结果 `passed=33 failed=0`，新写的用例一次都没跑。
//
// 用法：
//   xcrun xcresulttool get test-results tests --path <bundle> --format json \
//     | node scripts/only-testing-coverage.mjs <传给 xcodebuild 的全部参数>
// 参数里没有 `-only-testing` 时不读 stdin、直接退出 0（全量跑不受影响）。
// `-skip-testing` 不参与判定。
// 退出码：0 = 每个目标都命中了用例（或没传 -only-testing）  2 = 有目标零命中 / 结果读不出
// 自测：scripts/validate-only-testing-coverage.mjs

/**
 * 从 xcodebuild 参数里取出 `-only-testing` 目标。
 * 两种写法都认：`-only-testing:T/C` 与 `-only-testing T/C`（两个参数）。
 * @param {string[]} args
 * @returns {string[]}
 */
export function onlyTestingTargets(args) {
  const targets = [];
  for (let i = 0; i < args.length; i += 1) {
    const arg = args[i];
    if (arg.startsWith('-only-testing:')) {
      targets.push(arg.slice('-only-testing:'.length));
    } else if (arg === '-only-testing' && i + 1 < args.length) {
      targets.push(args[i + 1]);
      i += 1;
    }
  }
  return targets;
}

// `testFoo()` 与 `testFoo` 是同一个方法：xcresulttool 的节点名带括号，
// 而 xcodebuild 两种写法都接受。
const segments = (path) =>
  path
    .split('/')
    .filter((part) => part !== '')
    .map((part) => part.replace(/\(\)$/, ''));

/**
 * 把 `get test-results tests` 的树展开成每条用例的路径 [目标, 类, …, 方法]。
 * 目标取最近的 `… test bundle` 祖先，类取路径上的 `Test Suite` 节点。
 * @param {unknown} tests
 * @returns {string[][] | null} 结构不对时返回 null
 */
export function testCasePaths(tests) {
  if (tests === null || typeof tests !== 'object' || !Array.isArray(tests.testNodes)) {
    return null;
  }
  const paths = [];
  const walk = (node, bundle, suites) => {
    if (node === null || typeof node !== 'object') return;
    const type = typeof node.nodeType === 'string' ? node.nodeType : '';
    const name = typeof node.name === 'string' ? node.name : '';
    let nextBundle = bundle;
    let nextSuites = suites;
    if (/test bundle$/i.test(type)) {
      nextBundle = name;
      nextSuites = [];
    } else if (type === 'Test Suite') {
      nextSuites = [...suites, name];
    } else if (type === 'Test Case') {
      if (bundle !== null) paths.push(segments([bundle, ...suites, name].join('/')));
      // 用例下面只剩附件 / 运行时警告之类，不会再有用例。
      return;
    }
    for (const child of Array.isArray(node.children) ? node.children : []) {
      walk(child, nextBundle, nextSuites);
    }
  };
  for (const node of tests.testNodes) walk(node, null, []);
  return paths;
}

/**
 * @param {unknown} tests 已解析的 `get test-results tests` JSON（解析失败请传 null）
 * @param {string[]} targets `-only-testing` 目标
 * @returns {{verdict:'pass'|'error', counts:{target:string,count:number}[], reason:string}}
 */
export function coverageFromTests(tests, targets) {
  if (targets.length === 0) return { verdict: 'pass', counts: [], reason: '' };

  const paths = testCasePaths(tests);
  if (paths === null) {
    return {
      verdict: 'error',
      counts: [],
      reason:
        '读不出 result bundle 的用例树（`xcresulttool get test-results tests` 的 JSON 缺失或没有 testNodes），' +
        '没法核对每个 -only-testing 目标有没有命中。xcresulttool 的输出格式可能变了，先人工核对再改这里。',
    };
  }

  // 目标的每一段都要与用例路径的开头逐段相等：`T`、`T/C`、`T/C/m` 三种粒度同一条规则。
  // 逐段比而不是比字符串前缀 —— 否则 `T/Foo` 会误命中 `T/FooTests`。
  const counts = targets.map((target) => {
    const want = segments(target);
    const count = paths.filter(
      (path) => want.length > 0 && want.length <= path.length && want.every((part, i) => part === path[i]),
    ).length;
    return { target, count };
  });

  const missing = counts.filter((item) => item.count === 0);
  if (missing.length === 0) return { verdict: 'pass', counts, reason: '' };

  return {
    verdict: 'error',
    counts,
    reason:
      `${missing.length} 个 -only-testing 目标一条用例都没命中（xcodebuild 会静默忽略写错的目标，` +
      `其余目标照常跑，所以总数不为 0 也不代表它们跑过）：\n` +
      missing.map((item) => `    -only-testing:${item.target}`).join('\n') +
      '\n  怎么修：\n' +
      '    · 中间那段要写类名，不是文件名。查类名：\n' +
      "        grep -rn 'class .*: XCTestCase' blindRunTests blindRunUITests\n" +
      '    · 第一段是测试目标名（blindRunTests / blindRunUITests），不是 App 名。\n' +
      '    · 方法级目标确认方法名拼对、且确实在那个类里（不是在同文件的另一个类里）。\n' +
      '    · 同时传了 -skip-testing 的，确认它没有把这个目标的用例全部排掉。',
  };
}

// 只有被直接执行时才读参数和 stdin；被 import 时（自测）不做任何事。
if (import.meta.url === `file://${process.argv[1]}`) {
  const targets = onlyTestingTargets(process.argv.slice(2));
  if (targets.length === 0) process.exit(0);

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

  const { verdict, counts, reason } = coverageFromTests(parsed, targets);
  if (counts.length) {
    console.log('按 -only-testing 目标统计命中用例数：');
    for (const item of counts) console.log(`    ${item.count === 0 ? '✗' : '✓'} ${item.target}  ${item.count} 条`);
  }
  if (verdict !== 'pass') console.error(reason);
  process.exit(verdict === 'pass' ? 0 : 2);
}
