// 测试 helper 里「造了被 weak 持有的依赖、却没交还给调用方」的检测（#450）。由 guard.mjs 的 post 段调用，
// 判据与三次现场见那里的注释；正反用例在 scripts/validate-guard.mjs（搜 weak-helper）。
//
// 只做词法级判断（去掉注释与字符串后数括号），不解析 Swift。漏判的形状写在下面，误判走 `guard:allow weak-helper`。
// ponytail: 只认函数 / init 体内 `let|var X = 类型(` 这一种建法；工厂方法（`AppState.make()`）、
// 计算属性里建的、或通过 `attach(to:)` 这类非 configure 的入口交出去的都不查。真出现第四次换形状再加。

// 在 view model 里**全部**以 `weak var` 存的依赖类型（核对于 2026-10-28：`weak var appState: AppState` 24 处等）。
// `SpeechService` 不在内：它在 3 处是 weak、十几处是强引用，按类型拦全是误报（与 `weak-temporary` 同一取舍）。
const WEAK_HELD_TYPES = new Set(['AppState', 'LocationService', 'SpeechInputService', 'BlindBookingViewModel']);
// 把依赖交给 view model 的实参标签（`weak-temporary` 的名单，加上 `configure(with:)` 的 `with`）。
const WEAK_DEP_LABEL = '(?:appState|locationService|placeSearchProvider|speechInputService|bookingViewModel|with)';

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
      } else if (c === '\n' && depth === 0) break;
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
  for (const m of code.matchAll(/\b(?:func\s+(\w+)\s*(?:<[^>{]*>)?|(init)\s*[?!]?)\s*\(/g)) {
    const paramsOpen = m.index + m[0].length - 1;
    const paramsClose = matching(code, paramsOpen);
    if (paramsClose < 0) continue;
    const bodyOpen = code.indexOf('{', paramsClose);
    if (bodyOpen < 0) continue;
    const signatureTail = code.slice(paramsClose + 1, bodyOpen);
    // 协议里的声明没有函数体：下一个 `{` 落在别的声明上。签名尾巴里出现换行后的新声明就跳过。
    if (/\b(func|var|let|init)\b/.test(signatureTail)) continue;
    const isInit = m[2] === 'init';
    const returnType = signatureTail.match(/->\s*([^{]*?)\s*(?:where\b|$)/);
    if (!isInit && (!returnType || /^(Void|\(\s*\))$/.test(returnType[1].trim()))) continue;
    const bodyClose = matching(code, bodyOpen);
    if (bodyClose < 0) continue;
    const body = code.slice(bodyOpen + 1, bodyClose);
    const returns = returnStatements(body);

    for (const decl of body.matchAll(/\b(?:let|var)\s+(\w+)\s*(?::\s*[\w.?!]+\s*)?=\s*(\w+)\s*\(/g)) {
      const [, name, type] = decl;
      if (!WEAK_HELD_TYPES.has(type)) continue;
      const word = new RegExp(`\\b${name}\\b`);
      const handedToViewModel =
        [...body.matchAll(/\.configure\w*\s*\(/g)].some((call) => {
          const open = call.index + call[0].length - 1;
          const close = matching(body, open);
          return close > 0 && word.test(body.slice(open + 1, close));
        }) || new RegExp(`\\b${WEAK_DEP_LABEL}\\s*:\\s*${name}\\b`).test(body);
      if (!handedToViewModel) continue;
      const kept =
        returns.some((r) => word.test(r)) ||
        // 赋给别的东西（属性、`_ = X` 的 teardown 闭包…）。`let/var Y = X` 只是又一个局部，不算。
        new RegExp(`(?<!\\b(?:let|var)\\s+)\\b(?:[\\w.]+|_)\\s*=\\s*${name}\\b(?!\\s*\\.)`).test(body) ||
        new RegExp(`withExtendedLifetime\\(\\s*${name}\\b|\\.append\\(\\s*${name}\\b`).test(body);
      if (kept) continue;
      const line = code.slice(0, bodyOpen + 1 + decl.index).split('\n').length;
      leaks.push({ fn: isInit ? 'init' : `${m[1]}()`, name, type, line });
    }
  }
  return leaks;
}
