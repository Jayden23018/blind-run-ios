// pre 段 · UI 测试与 App 的 accessibilityIdentifier 对不上（规则 8，`stale-ui-test-identifier`）。
// 本守卫里唯一的跨文件规则：要同时读 blindRun/ 与 blindRunUITests/ 才判得了。

import fs from 'node:fs';
import path from 'node:path';
import { codeOnly, collectSwiftFiles, fail, nonCommentLines, readFileOrEmpty } from './common.mjs';

// ---- accessibilityIdentifier 漂移检测（规则 8，见下面用到它的地方的完整说明）----

// XCUITest 里「按 identifier 找元素」的几种写法。
const UI_TEST_QUERY_KEY =
  /(?:staticTexts|buttons|textFields|switches|navigationBars|alerts|scrollViews|otherElements|images|cells)\[\s*"([^"]+)"\s*\]|matching\(identifier:\s*"([^"]+)"\)|descendants\(matching:\s*\.any\)\[\s*"([^"]+)"\s*\]/g;

// 只判 ASCII 标识符形状的键。中文文案不在此列 —— 理由见规则 8 的注释。
const IDENTIFIER_SHAPED = /^[A-Za-z][A-Za-z0-9._]*$/;

// iOS 系统键盘的按键（收键盘用），不是 App 挂的 identifier，App 侧永远找不到它们。
// 白名单只有这两个，且必须写明理由 —— 白名单一长，这条规则就被架空了。
const SYSTEM_KEYBOARD_IDENTIFIERS = new Set(['Done', 'Return']);

// 取 `accessibilityIdentifier(` 的**整个实参**，再从里面取全部字符串字面量 ——
// 实参不一定是单个字面量：`isCloud ? "a" : "b"` 的两支都是真实产出的 id（#274）。
// 实参 = 非括号非引号字符 | 完整字符串字面量（里面的 `\(x)` 插值括号被它吞掉）| 一层嵌套括号。
// 已知上限：嵌套两层以上的实参匹配不上，等于没收集到（A 方向会把它产出的 id 当成不存在，B 方向会漏），
// 与改动前的误报面相同；本仓库目前没有这种写法。
const SWIFT_STRING = String.raw`"(?:[^"\\]|\\.)*"`;
const ACCESSIBILITY_IDENTIFIER_ARG = new RegExp(
  String.raw`accessibilityIdentifier\(((?:[^()"]|${SWIFT_STRING}|\((?:[^()"]|${SWIFT_STRING})*\))*)\)`,
  'g'
);

// 另一种挂法：辅助视图把 id 当参数收下，自己再挂 `.accessibilityIdentifier(identifier)`，
// 调用点只有 `identifier: "runRecordHistoryPreviousMonth"` 这个字面量（#412）。
// 只认带 `identifier:` 实参标签的字符串字面量；`Locale(identifier:)` / `TimeZone(identifier:)`
// 是系统 API 的同名标签，与 a11y 无关，用负向后顾排除。
// 已知上限：id 先赋给变量再传、或经 `identifierPrefix:` 这类带后缀的标签传入，匹配不上
// （与改动前相同，只会漏、不会误报）。
const IDENTIFIER_PARAMETER_ARG = /(?<!Locale\()(?<!TimeZone\()\bidentifier\s*:\s*("(?:[^"\\]|\\.)*")/g;

// 方向 A（建匹配器）与方向 B（判删除 / 判还在）都走这一个函数，口径必须一致。
function identifierLiterals(text) {
  const viaModifier = [...text.matchAll(ACCESSIBILITY_IDENTIFIER_ARG)].flatMap((m) =>
    [...m[1].matchAll(/"((?:[^"\\]|\\.)*)"/g)].map((lit) => lit[1])
  );
  const viaParameter = [...text.matchAll(IDENTIFIER_PARAMETER_ARG)].map((m) => m[1].slice(1, -1));
  return [...viaModifier, ...viaParameter];
}

function escapeRegExp(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// App 侧字面量里的插值段当通配：`"\(identifierPrefix)AgreeButton"` 要能匹配
// `appLaunchConsentAgreeButton`，`"volunteerRegistrationStep.\(step.displayIndex)"`
// 要能匹配 `volunteerRegistrationStep.1`。
// 已知上限：插值里再套括号（`\(f(x))`）会截断在第一个 `)` —— 本仓库目前没有这种写法，
// 真出现了它只会让规则更宽松（多匹配），不会误报。
function identifierLiteralToRegExp(literal) {
  const parts = literal.split(/\\\([^)]*\)/).map(escapeRegExp);
  return new RegExp(`^${parts.join('.+')}$`);
}

export function checkStaleUITestIdentifier({ input, filePath, body }) {
  const isUITest = /blindRunUITests\/.*\.swift$/.test(filePath);
  // 8. UI 测试与 App 的 accessibilityIdentifier 对不上（2026-08-22）
  //
  // 2026-08-14 `30b0770` 把盲人首页装饰地图对读屏隐藏，连同
  // `.accessibilityIdentifier("blindRunnerHomeAuxiliaryMap")` 一起删掉 —— 那是隐藏它的既定代价。
  // 同一个提交改了 blindRunUITests 58 行，但**漏了一处**，`testRealAMapEnabledSmoke` 从那天起
  // 一直红，8 天后才被查出来（`docs/review/ui-test-red-triage-20260822.md`）。
  // 本仓库 CI 跑不了 XCTest（高德无 arm64-sim slice），红用例照样能合进 main，
  // 所以这类漂移**没有任何运行时信号**，只能靠静态检查。
  //
  // 两个方向都查：
  //   A. 改 UI 测试时写了一个 App 侧不存在的 identifier
  //   B. 改 App 代码时删掉了一个 UI 测试还在用的 identifier（`30b0770` 就是这个方向）
  //
  // **只判 identifier 形状的键。** 中文文案那版实测过：149 个查询键报 28 个，其中 26 个是
  // 插值拼出来的 a11y label（「张三，关系家人，电话139****9001，非主联系人」这种），误报 93%
  // —— 白名单会比信号还长，那种守卫会被下一个人直接关掉。identifier 版实测 45 个键报 5 个：
  // 2 个系统键盘键（已白名单），3 个是真问题。所以「积分」那类中文文案漂移这条**管不了**，
  // 别以为它覆盖了。
  //
  // 故意断言某个 identifier **不存在**（例如 `matching(identifier:).count == 0`）是合法的，
  // 行尾加 `// guard:allow stale-ui-test-identifier` —— 标注本身就是「这个 id 是被有意删掉的」的声明。
  //
  // 下面**每一处**取 identifier 都走 codeOnly / nonCommentLines，注释一律不算数（2026-08-22）。
  // 两个方向的理由不同，别只改一半：
  //   · 注释里引用一个已删掉的 id（讲「为什么删」）不是查询 → 不该拦，也不该算「还有人在用」
  //   · App 侧**被注释掉的** `.accessibilityIdentifier("x")` 运行时并不存在 → 不能算它还在，
  //     否则把 identifier 注释掉就能让这条规则闭嘴，而那正是它要防的漂移（`30b0770` 的同款）
  const repoRootMatch = filePath.match(/^(.*)\/blindRun(?:Tests|UITests)?\//);
  const repoRoot = repoRootMatch ? repoRootMatch[1] : '';
  const appDir = repoRoot ? path.join(repoRoot, 'blindRun') : '';
  const uiTestDir = repoRoot ? path.join(repoRoot, 'blindRunUITests') : '';
  // 两侧都读得到才判。读不到（工程结构变了、跑在别的目录里）时宁可漏，不可误报。
  const canCrossCheck = Boolean(appDir) && fs.existsSync(appDir) && fs.existsSync(uiTestDir);

  if (canCrossCheck && isUITest) {
    const matchers = [];
    for (const file of collectSwiftFiles(appDir)) {
      for (const lit of identifierLiterals(codeOnly(readFileOrEmpty(file)))) {
        matchers.push(identifierLiteralToRegExp(lit));
      }
    }
    // 一个都没读到说明扫描本身出了问题，别把它当成「App 侧什么 id 都没有」。
    if (matchers.length > 0) {
      for (const line of nonCommentLines(body)) {
        if (line.includes('guard:allow stale-ui-test-identifier')) continue;
        for (const m of line.matchAll(UI_TEST_QUERY_KEY)) {
          const key = m[1] || m[2] || m[3];
          if (!key || !IDENTIFIER_SHAPED.test(key)) continue;
          if (SYSTEM_KEYBOARD_IDENTIFIERS.has(key)) continue;
          if (matchers.some((re) => re.test(key))) continue;
          fail(
            'stale-ui-test-identifier',
            `${filePath}\n  ${line.trim()}\n\n` +
              `UI 测试引用了 identifier \`${key}\`，但 blindRun/ 里没有任何 accessibilityIdentifier 会产出它。\n` +
              `这条断言永远命中不了：正面断言必然红，反面断言（XCTAssertFalse）恒真、等于没写。\n` +
              `本仓库 CI 跑不了 XCTest，所以这种漂移合进 main 时不会有任何信号。\n` +
              `改法：用 App 侧真实存在的 identifier，或改成按 label 断言。\n` +
              `确实是想断言它**不存在**，行尾加 \`// guard:allow stale-ui-test-identifier\`。`
          );
        }
      }
    }
  }

  // B：App 侧删掉 identifier，而 UI 测试还在用它。
  // 只对 Edit 生效（要有 old_string 才知道删了什么）。Write 整文件重写查不到，
  // 那种改法本来就会被方向 A 在改测试时拦下。
  const removedIdentifiers = canCrossCheck && /\.swift$/.test(filePath) && appDir && filePath.startsWith(`${appDir}/`)
    ? identifierLiterals(codeOnly(input.old_string || '')).filter(
        (lit) => !lit.includes('\\(') && !identifierLiterals(codeOnly(body)).includes(lit)
      )
    : [];
  for (const removed of removedIdentifiers) {
    // 同一个 id 可能在别处还挂着（挪了位置而不是删了），那不算删除。
    const stillInApp = collectSwiftFiles(appDir).some(
      (file) =>
        file !== filePath &&
        identifierLiterals(codeOnly(readFileOrEmpty(file))).includes(removed)
    );
    if (stillInApp) continue;
    const referencing = collectSwiftFiles(uiTestDir).filter((file) =>
      nonCommentLines(readFileOrEmpty(file)).some(
        (l) => l.includes(`"${removed}"`) && !l.includes('guard:allow stale-ui-test-identifier')
      )
    );
    if (referencing.length === 0) continue;
    fail(
      'stale-ui-test-identifier',
      `${filePath}\n  删掉了 accessibilityIdentifier("${removed}")\n\n` +
        `但这些 UI 测试还在按它找元素：\n` +
        referencing.map((f) => `  · ${path.relative(repoRoot, f)}`).join('\n') +
        `\n\n先把 UI 测试改掉再删 identifier。本仓库 CI 跑不了 XCTest，漏改的那一处不会有任何信号：\n` +
        `2026-08-14 \`30b0770\` 就是这么让 testRealAMapEnabledSmoke 红了 8 天。\n` +
        `确实是有意让它消失、且测试那边断的就是「不存在」，在测试那一行加 \`// guard:allow stale-ui-test-identifier\`。`
    );
  }
}
