// post 段 · 测试 target：无障碍审计类型必须是全集（a11y-audit-types）、测试 helper 漏交 weak 依赖（weak-helper）。
// 这两条必须排在「只查生产 target」的过滤之前 —— 被查的代码住在 blindRunUITests/ 与 blindRunTests/。

import path from 'node:path';
import { codeOnly, fail, readFileOrEmpty } from './common.mjs';
import { findDiscardedHolders, findWeakHelperLeaks } from '../weak-helper-leaks.mjs';

// ---- 无障碍审计类型全集（规则 a11y-audit-types，见 post 分支）----
//
// iOS 侧 `XCUIAccessibilityAuditType` 的**全部**取值，本机 SDK 头文件实证：
// `Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/Library/Frameworks/`
// `XCUIAutomation.framework/Headers/XCUIAccessibilityAuditTypes.h`
// （action / parentChild 在 `#elif TARGET_OS_OSX || TARGET_OS_MACCATALYST` 分支里，不属于这里）。
const A11Y_AUDIT_TYPES = [
  'contrast',
  'elementDetection',
  'hitRegion',
  'sufficientElementDescription',
  'dynamicType',
  'textClipped',
  'trait'
];

export function checkA11yAuditTypes({ filePath }) {
  // a11y-audit-types：审计类型集合必须是全集。
  //
  // 少一项**从测试结果上完全看不出来** —— 用例照跑照绿，绿的是剩下那几项。
  // 2026-09-02 实测的形状：`.textClipped` 与 `.trait` 从未启用，而同文件的注释逐字
  // 宣称「审计里真正抓这件事的是 `.textClipped`」，还把三条横屏用例定成
  // 「本仓库唯一能验横屏裁切的通道」。于是「横屏裁切有覆盖」这个判断错了三周，
  // 且比「完全没覆盖」更难发现 —— 有绿灯在替它背书。
  //
  // **判据走 codeOnly，注释一个字都不算数。** 这不是顺手加的：本次缺陷的形状
  // 恰恰就是「注释里有、参数列表里没有」。拿注释当证据的检查会原样放过它。
  //
  // 这条必须排在下面「只查生产 target」的过滤**之前** —— 那条过滤会跳过
  // blindRunUITests/，而审计代码就住在那里。
  //
  // 证据**只取 `for: [ ... ]` 列表内部**，且列表内部再剥一次行尾注释。
  // 初版是「在整份 codeOnly 文本里找类型名」，2026-09-02 的 code review 抓出两个洞，
  // 两个都已复现（见 validate-guard.mjs 对应用例）：
  //   · `codeOnly` 只剥**整行**注释，剥不掉行尾注释 ⇒ 在缺项旁边写一句
  //     `// TODO: 补 .textClipped` 就让规则反向失效 —— 而「注释里有、参数列表里没有」
  //     正是这条规则要堵的那个形状，被它自己的判据放过去，等于没写
  //   · `guard:allow` 当时是全文 `.includes()`，在文件任意角落写一次就能整条失效
  //
  // 另一个方向的误伤（同轮自查发现）：`performAccessibilityAudit()` 不传实参时默认
  // 就是 `.all`，是完全正确、甚至更好的写法（自动跟随 SDK 新增类型），初版会把它
  // 判成「七项全缺」拦下。⇒ **匹配不到 `for: [` 一律放行。**
  //
  // `.all.subtracting(.textClipped)` 这类**显式**排除同样绕得过。那是有意为之、
  // 且在 diff 里一眼可见 —— 本规则防的是静默缺失，不是防有意规避（后者走 guard:allow）。
  const auditSrc = codeOnly(readFileOrEmpty(filePath));
  for (const match of auditSrc.matchAll(/performAccessibilityAudit\s*\(\s*for:\s*\[([^\]]*)\]/g)) {
    const rawList = match[1];
    // 抑制标记必须落在**这个列表**里（写成列表内的行尾注释），不是文件任意一处。
    if (rawList.includes('guard:allow a11y-audit-types')) continue;
    const list = rawList
      .split('\n')
      .map((l) => l.split('//')[0])
      .join('\n');
    const missing = A11Y_AUDIT_TYPES.filter((t) => !new RegExp(`\\.${t}\\b`).test(list));
    if (missing.length === 0) continue;
    fail(
      'a11y-audit-types',
      `${filePath}\n  缺少审计类型：${missing.map((t) => `.${t}`).join(', ')}\n\n` +
        `\`performAccessibilityAudit(for:)\` 的集合必须覆盖 iOS 侧全部 7 个类型：\n` +
        `  ${A11Y_AUDIT_TYPES.map((t) => `.${t}`).join(', ')}\n\n` +
        `少一项不会让任何用例变红 —— 它只是不再检查那一类缺陷，而绿灯照常亮。\n` +
        `盲人端的直接后果：漏 .textClipped 则文本被截断查不出，漏 .trait 则按钮\n` +
        `缺 \`.button\` 时 VoiceOver 不念「按钮」，用户不知道那是能点的东西。\n\n` +
        `判据只认这个 \`for: [ ... ]\` 列表里的内容，**注释一个字都不算数**（行尾注释也剥掉）——\n` +
        `因为这条规则要堵的缺陷形状恰恰就是「注释里写了、参数列表里没有」。\n` +
        `不想查某一项：把 \`// guard:allow a11y-audit-types\` 写进**这个列表内部**并说明理由。\n` +
        `想用全集又不想逐个列：\`performAccessibilityAudit()\` 不传实参即默认 \`.all\`，本规则放行。`
    );
  }
}

export function checkWeakHelper({ filePath }) {
  // weak-helper：测试 helper 自己造了一个被 view model `weak` 持有的依赖，却没交还给调用方（#450）。
  //
  // helper 一返回那个局部变量就被释放，被测方法在 `guard let appState else { return }` 处整个早退：
  // 一组用例同时红、报错大量是「期望 X 实际 0 / nil」，断言「没发生」的用例则**假绿**。
  // 三次现场：① 2026-08-06 内联临时对象 —— 归 pre 段的 `weak-temporary`；
  // ② 2026-09-08 helper 局部 `let appState = AppState()`，`return (vm, speech)` 漏了它（一整轮真机）；
  // ③ 2026-10-16 #434 / PR #447 `return Harness(viewModel:fake:speech:)` 唯独没装 appState（19 条里 11 红、2 条假绿）。
  // ②③ 传的是变量名不是构造器，`weak-temporary` 抓不到，所以这里按函数体判：
  // 有返回值的函数（或 `init`）里 `let X = <被 weak 持有的类型>(…)`，X 被传进 `configure…(…)` 或带 weak 依赖标签的实参，
  // 而 X 既不在任何 `return` 里、也没被赋给别的东西（`self.x = X` / `retained = X` / `_ = X`）—— 拦。
  // 测试方法本身（没有返回值）不查：局部变量活到方法结束，正是正确写法。
  if (/\/blindRunTests\/.*\.swift$/.test(filePath)) {
    const src = readFileOrEmpty(filePath);
    const leak = findWeakHelperLeaks(src).find(({ line }) => {
      const lines = src.split('\n');
      return ![lines[line - 1], lines[line - 2]].some((l) => (l ?? '').includes('guard:allow weak-helper'));
    });
    if (leak) {
      fail(
        'weak-helper',
        `${filePath}:${leak.line}\n  ${leak.fn} 里的 \`${leak.name}\`（${leak.type}）被传进了 view model，却没随返回值交出去，也没被别处持有。\n\n` +
          `view model 对它是 \`weak\` 持有：helper 一返回它就被释放，被测方法在 \`guard let ${leak.name} else { return }\` 处整个早退，\n` +
          `一组用例同时红（「期望 X 实际 0 / nil」），断言「没发生」的用例则假绿（#450，已发生三次）。\n` +
          `改法（任选其一）：把它放进返回值（元组 / Harness 加一个字段）；或让调用方 \`let\` 住再传进 helper；\n` +
          `或赋给测试类的属性（\`retainedAppState = ${leak.name}\`）。确实就要 nil 语义，在声明行加 \`// guard:allow weak-helper\`。`
      );
    }
    // 同一类缺陷的另一种建法（#598）：夹具把持有者交出来了，调用方却用 `_` 丢掉。
    const discarded = findDiscardedHolders(src, (name) =>
      readFileOrEmpty(path.join(path.dirname(filePath), `${name}.swift`))
    ).find(({ line }) => !(src.split('\n')[line - 1] ?? '').includes('guard:allow weak-helper'));
    if (discarded) {
      fail(
        'weak-helper',
        `${filePath}:${discarded.line}\n  \`${discarded.helper}()\` 返回的元组里，\`${discarded.type}\` 那一项被 \`_\` 丢掉了。\n` +
          `被测对象靠它活着：丢的是 weak 依赖，被测方法在 \`guard let\` 处早退；丢的是 view model，协调器的 \`[weak self]\` 订阅没人接。\n` +
          `断言「会发生」的用例红，断言「不会发生」的用例永远假绿（#598，#551、#556 各踩过一次）。\n` +
          `改法：给它起名字并用到用例结束（真实断言，或 \`withExtendedLifetime\`）。确实就要释放后的语义，在这一行加 \`// guard:allow weak-helper\`。`
      );
    }
  }
}
