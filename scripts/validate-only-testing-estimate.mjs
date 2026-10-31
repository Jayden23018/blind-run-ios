#!/usr/bin/env node
//
// scripts/only-testing-estimate.mjs 的回归测试（#616）。
//
// 这道闸有两种坏法，这里各守一边：
// - 估算恒为 0（正则漂了、目录名错了）：闸静默失效，看上去一切正常。最后一组对着真仓库核。
// - 上限被放宽：所以边界用例取 100 和 101，放宽成任何更大的值，101 那条都会红。

import {
  WIDE_RUN_LIMIT,
  addTestCounts,
  countsFromRepository,
  estimate,
  wideRunMessage,
} from './only-testing-estimate.mjs';

const counted = (...sources) => {
  const counts = new Map();
  for (const source of sources) addTestCounts(source, counts);
  return counts;
};

const swift = `
import XCTest

final class FooTests: XCTestCase {
    func testA() {}
    func testB() async throws {}
    @MainActor func testC() {}
    // func testCommentedOut() {}
    private func testHelper() {}
    func helper() {}

    final class Nested {
        func testNotReallyATest() {}
    }
    func testAfterNested() {}
}

@MainActor
final class BarTests: XCTestCase {
    func testD() {}
}
`;

const countsByTarget = {
  blindRunTests: new Map([
    ['FooTests', 60],
    ['BarTests', 41],
  ]),
  blindRunUITests: new Map([['BazTests', 5]]),
};

const cases = [
  {
    name: '方法级目标算 1 条，哪怕类名不存在',
    run: () => estimate(['blindRunTests/Nope/testA'], countsByTarget).total === 1,
  },
  {
    name: '类级目标按类算',
    run: () => estimate(['blindRunTests/FooTests'], countsByTarget).total === 60,
  },
  {
    name: '目标级（整个 bundle）把类加起来',
    run: () => estimate(['blindRunTests'], countsByTarget).total === 101,
  },
  {
    name: '裸跑算全部',
    run: () => estimate([], countsByTarget).total === 106,
  },
  {
    name: '写错的类名算 0（零命中归 only-testing-coverage 管）',
    run: () => estimate(['blindRunTests/Nope'], countsByTarget).total === 0,
  },
  {
    name: '同一目标传两次只算一次',
    run: () => estimate(['blindRunTests/FooTests', 'blindRunTests/FooTests'], countsByTarget).total === 60,
  },
  {
    name: '类级目标盖住同类的方法级目标，不重复算',
    run: () => estimate(['blindRunTests/FooTests', 'blindRunTests/FooTests/testA'], countsByTarget).total === 60,
  },
  {
    name: '类名是另一个类名的前缀时不算盖住',
    run: () => estimate(['blindRunTests/FooTests', 'blindRunTests/FooTestsMore/testA'], countsByTarget).total === 61,
  },
  {
    name: '解析：注释、private、嵌套类型里的都不算，嵌套类型后面的还算',
    run: () => counted(swift).get('FooTests') === 4 && counted(swift).get('BarTests') === 1,
  },
  {
    name: '解析：别的文件里的 extension 累加到同一个类',
    run: () => counted(swift, 'extension BarTests {\n    func testE() {}\n}\n').get('BarTests') === 2,
  },
  {
    name: `上限是 ${WIDE_RUN_LIMIT}：正好 100 条放行`,
    run: () => wideRunMessage({ total: 100, rows: [{ target: 'x', count: 100 }] }) === null,
  },
  {
    name: '101 条拦下，说明里点名最大的目标和放行开关',
    run: () => {
      const message = wideRunMessage({ total: 101, rows: [{ target: 'blindRunTests/FooTests', count: 101 }] });
      return message?.includes('blindRunTests/FooTests') && message.includes('AIDRUN_ALLOW_WIDE_RUN=1');
    },
  },
  {
    // 真仓库兜底：估算恒为 0 时上面的用例照样全绿，只有这一组看得出闸失效了。
    name: '真仓库：blindRunTests 这个大类能数出来，且单独跑就会被拦',
    run: () => {
      const real = countsFromRepository('.');
      const result = estimate(['blindRunTests/blindRunTests'], real);
      return result.total > WIDE_RUN_LIMIT && wideRunMessage(result) !== null;
    },
  },
  {
    name: '真仓库：UI 测试目标也数得出来，裸跑一定被拦',
    run: () => {
      const real = countsFromRepository('.');
      return estimate(['blindRunUITests'], real).total > 0 && wideRunMessage(estimate([], real)) !== null;
    },
  },
  {
    name: '目录不存在时两个目标都是空的（device-test 的自测在空沙箱里跑，不能被拦）',
    run: () => estimate([], countsFromRepository('/nonexistent-aidrun')).total === 0,
  },
];

let failed = 0;
for (const c of cases) {
  let ok = false;
  try {
    ok = c.run();
  } catch (error) {
    console.error(`  ${error.message}`);
  }
  if (ok) {
    console.log(`✓ ${c.name}`);
  } else {
    console.error(`✗ ${c.name}`);
    failed += 1;
  }
}

if (failed) {
  console.error(`\n${failed} 条失败。`);
  process.exit(1);
}
console.log(`\n${cases.length} 条全部通过。`);
