// 测试 helper 里「造了被 weak 持有的依赖、却没交还给调用方」的检测（#450）。由 guard.mjs 的 post 段调用，
// 判据与三次现场见那里的注释；正反用例在 scripts/validate-guard.mjs（搜 weak-helper）。
//
// 只做词法级判断（去掉注释与字符串后数括号），不解析 Swift。漏判的形状写在下面，误判走 `guard:allow weak-helper`。
// ponytail: 只认函数 / init / setUp 体内 `let|var X = 类型(` 与 `let X = X ?? 类型(`（#601）这两种建法、
// 经 `configure…()` 交出去这一种入口；工厂方法（`AppState.make()`）、计算属性里建的、经 init 注入或
// `attach(to:)` 交出去的、无返回值的普通 helper、字符串插值里的嵌套字符串与 `#"…"#` 原始字符串都不查。
// `PlaceSearchProvider` 的测试替身类型名各不相同，也不在名单里。
// 元组解构（#598）只查得到本文件里的 helper 和 `类型.helper(` 且该类型有同名文件的夹具，别的文件里的自由函数查不到。
// 真出现下一种形状再加。

// 在 view model 里**全部**以 `weak var` 存的依赖类型（核对于 2026-10-28：`weak var appState: AppState` 24 处等）。
// `SpeechService` 不在内：它在 3 处是 weak、十几处是强引用，按类型拦全是误报（与 `weak-temporary` 同一取舍）。
const WEAK_HELD_TYPES = new Set(['AppState', 'LocationService', 'SpeechInputService', 'BlindBookingViewModel']);

// 注释与字符串字面量换成空格，保留换行 —— 行号要对得上原文。
function blankCommentsAndStrings(src) {
  let out = '';
  let i = 0;
  const blank = (s) => s.replace(/[^\n]/g, ' ');
  while (i < src.length) {
    if (src.startsWith('//', i)) {
      const end = src.indexOf('\n', i);
      const stop = end < 0 ? src.length : end;
      out += blank(src.slice(i, stop));
      i = stop;
    } else if (src.startsWith('/*', i)) {
      const end = src.indexOf('*/', i + 2);
      const stop = end < 0 ? src.length : end + 2;
      out += blank(src.slice(i, stop));
      i = stop;
    } else if (src.startsWith('"""', i)) {
      const end = src.indexOf('"""', i + 3);
      const stop = end < 0 ? src.length : end + 3;
      out += `"${blank(src.slice(i + 1, stop - 1))}"`;
      i = stop;
    } else if (src[i] === '"') {
      let j = i + 1;
      while (j < src.length && src[j] !== '"' && src[j] !== '\n') j += src[j] === '\\' ? 2 : 1;
      out += `"${blank(src.slice(i + 1, j))}"`;
      i = j + 1;
    } else {
      out += src[i];
      i += 1;
    }
  }
  return out;
}

// 从 `open` 处的开括号（`(` 或 `{`）数到与它配对的闭括号，返回闭括号下标；配不上返回 -1。
function matching(code, open) {
  const pair = { '(': ')', '{': '}' }[code[open]];
  let depth = 0;
  for (let i = open; i < code.length; i++) {
    if (code[i] === code[open]) depth++;
    else if (code[i] === pair && --depth === 0) return i;
  }
  return -1;
}

// 每个 `return` 语句的文本：从 `return` 到同一层括号内的行尾（多行的 `return Harness(\n…\n)` 整段取）。
function returnStatements(body) {
  const out = [];
  for (const m of body.matchAll(/\breturn\b/g)) {
    let depth = 0;
    let end = m.index;
    for (; end < body.length; end++) {
      const c = body[end];
      if (c === '(' || c === '[' || c === '{') depth++;
      else if (c === ')' || c === ']' || c === '}') {
        if (depth === 0) break;
        depth--;
      } else if (c === '\n' && depth === 0) {
        // 下一行以 `.` / `?` / `:` 开头是同一条语句（链式调用、三元），接着取。
        if (!/^\s*[.?:]/.test(body.slice(end + 1))) break;
      }
    }
    out.push(body.slice(m.index, end));
  }
  return out;
}

// 返回 [{ fn, name, type, line }]，line 是那句 `let X = 类型(` 在原文里的行号（1 起）。
export function findWeakHelperLeaks(src) {
  const code = blankCommentsAndStrings(src);
  const leaks = [];
  // 函数与 init 的签名：名字后面第一对圆括号是参数表，参数表之后、`{` 之前是返回类型等。
  // `(?<![.\w])`：`.init(` / `super.init(` 是调用，不是声明。
  for (const m of code.matchAll(/(?:\bfunc\s+(\w+)\s*(?:<[^>{]*>)?|(?<![.\w])(init)\s*[?!]?)\s*\(/g)) {
    const paramsOpen = m.index + m[0].length - 1;
    const paramsClose = matching(code, paramsOpen);
    if (paramsClose < 0) continue;
    const bodyOpen = code.indexOf('{', paramsClose);
    if (bodyOpen < 0) continue;
    const signatureTail = code.slice(paramsClose + 1, bodyOpen);
    // 没有函数体的声明（协议要求）：下一个 `{` 落在别的声明上，中间会跨过新声明、`}` 或 `;`，跳过。
    if (/\b(func|var|let|init)\b|[};]/.test(signatureTail)) continue;
    const isInit = m[2] === 'init';
    // `setUp` 没有返回值，但它的局部变量同样在它结束时释放，而 view model 存在测试类上活到下一条用例。
    const isSetUp = /^setUp(WithError)?$/.test(m[1] ?? '');
    const returnType = signatureTail.match(/->\s*([^{]*?)\s*(?:where\b|$)/);
    const returnsNothing = !returnType || /^(Void|\(\s*\))$/.test(returnType[1].trim());
    if (!isInit && !isSetUp && returnsNothing) continue;
    const bodyClose = matching(code, bodyOpen);
    if (bodyClose < 0) continue;
    const body = code.slice(bodyOpen + 1, bodyClose);
    const returns = returnStatements(body);

    // `(?:\w+\s*\?\?\s*)?`：`let vm = vm ?? BlindBookingViewModel()`，不传参时走的就是这个临时对象（#601）。
    for (const decl of body.matchAll(/\b(?:let|var)\s+(\w+)\s*(?::\s*[\w.?!]+\s*)?=\s*(?:\w+\s*\?\?\s*)?(\w+)\s*\(/g)) {
      const [, name, type] = decl;
      if (!WEAK_HELD_TYPES.has(type)) continue;
      const word = new RegExp(`\\b${name}\\b`);
      // 只认 `configure…()`：三次现场都是它。按实参标签认会把强持有的接收方（`Harness(appState:)`、
      // `SupportTicketView(appState:)`）也当成 view model，把正确写法拦下。
      const handedToViewModel = [...body.matchAll(/\.configure\w*\s*\(/g)].some((call) => {
        const open = call.index + call[0].length - 1;
        const close = matching(body, open);
        return close > 0 && word.test(body.slice(open + 1, close));
      });
      if (!handedToViewModel) continue;
      // return 里要是这个值本身：`appState:` 是实参标签，`appState.count` 是取它的成员，都不算交出去。
      const asValue = new RegExp(`(?<![\\w.])${name}\\b(?!\\s*[:.])`);
      const kept =
        returns.some((r) => asValue.test(r)) ||
        // 赋给测试类自己的东西才算持有：`self.x = X`、裸属性名、`_ = X`（teardown 闭包）。
        // `vm.appState = X` 赋的是 view model 自己的 weak 属性，不算；`let/var Y = X` 只是又一个局部，也不算。
        new RegExp(`(?<!\\b(?:let|var)\\s+)(?<![\\w.])(?:self\\.\\w+|_|\\w+)\\s*=\\s*${name}\\b(?!\\s*\\.)`).test(body) ||
        new RegExp(`withExtendedLifetime\\(\\s*${name}\\b|\\.append\\(\\s*${name}\\b`).test(body);
      if (kept) continue;
      const line = code.slice(0, bodyOpen + 1 + decl.index).split('\n').length;
      leaks.push({ fn: isInit ? 'init' : `${m[1]}()`, name, type, line });
    }
  }
  return leaks;
}

// 元组返回类型的各项类型：去掉 `标签:`、结尾的 `?` / `!`。只按顶层逗号切，泛型与闭包类型里的逗号不算。
function tupleElementTypes(text) {
  const items = [];
  let depth = 0;
  let current = '';
  for (const c of text) {
    if ('(<['.includes(c)) depth++;
    else if (')>]'.includes(c)) depth--;
    if (c === ',' && depth === 0) {
      items.push(current);
      current = '';
    } else {
      current += c;
    }
  }
  items.push(current);
  return items.map((item) => item.replace(/^\s*\w+\s*:/, '').trim().replace(/[?!]+$/, ''));
}

// 找 `func name(…) -> (A, B, …)` 里项数等于 `arity` 的那个声明，返回各项类型；找不到返回 null。
function helperTupleTypes(code, name, arity) {
  for (const m of code.matchAll(new RegExp(`\\bfunc\\s+${name}\\s*(?:<[^>{]*>)?\\s*\\(`, 'g'))) {
    const paramsClose = matching(code, m.index + m[0].length - 1);
    if (paramsClose < 0) continue;
    const arrow = code.slice(paramsClose + 1).match(/^\s*(?:async\s+)?(?:throws\s+)?->\s*\(/);
    if (!arrow) continue;
    const open = paramsClose + arrow[0].length;
    const close = matching(code, open);
    if (close < 0) continue;
    const types = tupleElementTypes(code.slice(open + 1, close));
    if (types.length === arity) return types;
  }
  return null;
}

// 从夹具返回的元组里用 `_` 丢掉了「被测对象靠它活着」的那一项（#598、#601 同一类，第四、五次现场）：
// - 被 weak 持有的依赖：`let (_, viewModel) = makeHome()` 丢的是 `AppState`，`load()` 开头 `guard let appState` 直接早退；
// - view model 本身：它对协调器的订阅都是 `[weak self]`，丢掉后没人处理事件。
// 两种都是断言「会发生」的用例红、断言「不会发生」的用例永远假绿。
// `readFixture(类型名)` 返回 `类型名.swift` 的内容，夹具在别的文件时用；读不到返回 ''。
// 返回 [{ helper, type, line }]，line 是那句解构在原文里的行号（1 起）。
export function findDiscardedHolders(src, readFixture = () => '') {
  const code = blankCommentsAndStrings(src);
  const found = [];
  const isHolder = (type) => WEAK_HELD_TYPES.has(type) || /ViewModel$/.test(type);
  for (const m of code.matchAll(/\b(?:let|var)\s*\(([^()]*)\)\s*=\s*(?:(?:try|await)\s+)*(?:(\w+)\.)?(\w+)\s*\(/g)) {
    const names = m[1].split(',').map((name) => name.trim());
    if (!names.includes('_')) continue;
    const [, , host, helper] = m;
    const types =
      helperTupleTypes(code, helper, names.length) ??
      (host && host !== 'Self' ? helperTupleTypes(blankCommentsAndStrings(readFixture(host)), helper, names.length) : null);
    if (!types) continue;
    names.forEach((name, index) => {
      if (name !== '_' || !isHolder(types[index])) return;
      found.push({ helper, type: types[index], line: code.slice(0, m.index).split('\n').length });
    });
  }
  return found;
}
