#!/usr/bin/env node
//
// 跑真机之前估算这次要跑多少条用例，超过上限就拦下（#616）。
//
// 为什么需要它：负责人四次指出真机跑得太多（2026-09-24、10-09 两次、10-31）。
// 规则一直写在记忆和 skill 里，脚本本身不限制，于是为了一条用例带上整个类、
// 叠着的 PR 逐个重跑。2026-10-28 晚到 10-31 实测：141 轮、8039 次用例，
// 不同用例只有 2394 条。这道闸在编译之前就拦下，不占手机。
//
// 估算只读源码里的 `func test…`，不是权威数字：继承来的用例不算，`-skip-testing` 不扣。
// 够判断「这次是不是跑多了」就行，真值仍然只认 result bundle（`xcresult-verdict.mjs`）。
//
// 用法（从仓库根目录跑）：node scripts/only-testing-estimate.mjs <传给 xcodebuild 的全部参数>
// 退出码：0 = 没超上限  2 = 超了，stdout 是给人看的说明  其他 = 脚本自己出错，调用方不拦
// 放行：调用方判 `AIDRUN_ALLOW_WIDE_RUN=1`，这个脚本本身不读环境变量。
// 自测：scripts/validate-only-testing-estimate.mjs

import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { onlyTestingTargets } from './only-testing-coverage.mjs';

export const WIDE_RUN_LIMIT = 100;
export const TEST_TARGETS = ['blindRunTests', 'blindRunUITests'];

// 只认顶格的声明：缩进的是嵌套在测试类里的替身，用例不归它们。
const TYPE_DECLARATION = /^(?:@\w+\s+)*(?:(?:final|public|internal|open)\s+)*(?:class|extension)\s+(\w+)/;
// `private func test…` 不匹配：XCTest 不跑它，它只是名字碰巧以 test 开头的 helper。
// 缩进卡死 4 个空格：更深的是嵌套类型里的方法，XCTest 不会把它们当这个类的用例。
const TEST_METHOD = /^ {4}(?:@\w+\s+)*func\s+test\w*\s*\(/;

/**
 * 把一个 Swift 文件里的用例数累加进 `counts`（类名 → 条数）。
 * 同一个类的 extension 可能在别的文件，所以是累加。
 * @param {string} source
 * @param {Map<string, number>} counts
 */
export function addTestCounts(source, counts) {
  let current = null;
  for (const line of source.split('\n')) {
    const declaration = line.match(TYPE_DECLARATION);
    if (declaration) current = declaration[1];
    else if (current && TEST_METHOD.test(line)) counts.set(current, (counts.get(current) ?? 0) + 1);
  }
}

/**
 * 去掉被类级目标盖住的方法级目标，否则同一条算两次。
 * @param {string[]} targets
 * @returns {string[]}
 */
function withoutOverlaps(targets) {
  const unique = [...new Set(targets)];
  const covers = (wide, narrow) => wide !== narrow && narrow.startsWith(`${wide}/`);
  return unique.filter((target) => !unique.some((other) => covers(other, target)));
}

/**
 * 按 `-only-testing` 目标估算条数。
 * @param {string[]} targets 空数组 = 裸跑，也就是全部。
 * @param {Record<string, Map<string, number>>} countsByTarget
 * @returns {{ total: number, rows: { target: string, count: number }[] }}
 */
export function estimate(targets, countsByTarget) {
  const sum = (counts) => [...counts.values()].reduce((a, b) => a + b, 0);
  const countOf = (target) => {
    const [bundle, type, method] = target.split('/');
    if (method) return 1;
    const counts = countsByTarget[bundle] ?? new Map();
    return type ? counts.get(type) ?? 0 : sum(counts);
  };
  const expanded = targets.length ? withoutOverlaps(targets) : Object.keys(countsByTarget);
  const rows = expanded.map((target) => ({ target, count: countOf(target) })).sort((a, b) => b.count - a.count);
  return { total: rows.reduce((a, b) => a + b.count, 0), rows };
}

/**
 * 超上限时给人看的说明，没超返回 null。
 * @param {{ total: number, rows: { target: string, count: number }[] }} result
 * @returns {string | null}
 */
export function wideRunMessage({ total, rows }) {
  if (total <= WIDE_RUN_LIMIT) return null;
  const top = rows.slice(0, 5).map((row) => `    ${row.count}  ${row.target}`);
  return [
    `这次要跑约 ${total} 条用例，超过上限 ${WIDE_RUN_LIMIT} 条（负责人 2026-10-31：只测改了的地方）。`,
    '  最大的几个目标：',
    ...top,
    '  改法：写到方法级，只跑新增或改过的用例：-only-testing:blindRunTests/类名/方法名',
    '  叠着的 PR 只在栈顶跑一次；已有绿灯的不重跑；小改动攒齐一起跑。',
    '  确实要跑这么多（比如改了解析器，一次影响整个类）：先说明为什么，再加 AIDRUN_ALLOW_WIDE_RUN=1。',
  ].join('\n');
}

/**
 * 读仓库里两个测试目标的全部 Swift 文件。目录不存在时那个目标是空的。
 * @param {string} root
 * @returns {Record<string, Map<string, number>>}
 */
export function countsFromRepository(root) {
  const countsByTarget = {};
  for (const target of TEST_TARGETS) {
    const counts = new Map();
    const directory = join(root, target);
    if (existsSync(directory)) {
      for (const file of readdirSync(directory, { recursive: true })) {
        if (String(file).endsWith('.swift')) addTestCounts(readFileSync(join(directory, String(file)), 'utf8'), counts);
      }
    }
    countsByTarget[target] = counts;
  }
  return countsByTarget;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const result = estimate(onlyTestingTargets(process.argv.slice(2)), countsFromRepository('.'));
  const message = wideRunMessage(result);
  if (message) {
    console.log(message);
    process.exit(2);
  }
  console.log(`这次估算 ${result.total} 条用例`);
}
