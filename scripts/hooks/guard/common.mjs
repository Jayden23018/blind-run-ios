// 守卫各模块共用的工具：报错退出、注释行过滤、读文件、收集 Swift 文件。
// 入口与模块清单见 `scripts/hooks/guard.mjs` 顶部。

import fs from 'node:fs';
import path from 'node:path';

// 退出码 2 = 拦下并把 stderr 反馈给 Claude。
export function fail(ruleId, detail) {
  process.stderr.write(`[guard:${ruleId}] ${detail}\n`);
  process.exit(2);
}

// 纯注释行不参与扫描 —— 守卫管的是出货代码。
//
// 2026-08-22：`blind-tap-center` 拦住了 `AccessibilityAuditTests.swift` 的整份 Write，
// 因为那个文件自己的注释里写着「不能用 app.tap() —— 它敲的是屏幕正中」。
// 守卫拦住了解释这条守卫的文档，而那段注释正是它存在的理由。
// 每条「别这么写」的规则都要求它的说明能原样写出坏写法，否则规则一落地就锁死自己的文档，
// 逼人去加 `guard:allow` —— 那等于把规则关掉。
//
// `#` 后面直接跟字母的**不算**注释：那是 Swift 编译指令（`#if` / `#Preview("…")`），
// 会真的编进产物。shell / yaml / podspec 的
// `# 说明` 与 `#!` 则照常跳过。
export const COMMENT_LINE = /^\s*(\/\/|\/\*|\*|#(?![A-Za-z]))/;

export const nonCommentLines = (body) => body.split('\n').filter((l) => !COMMENT_LINE.test(l));

// 整段文本里只留代码 —— 给那些按整份内容 `.includes()` 判断的地方用（规则 8 有几处）。
export const codeOnly = (text) => nonCommentLines(text).join('\n');

export function readFileOrEmpty(file) {
  try {
    return fs.readFileSync(file, 'utf8');
  } catch {
    return '';
  }
}

export function collectSwiftFiles(dir, out = []) {
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) collectSwiftFiles(full, out);
    else if (entry.name.endsWith('.swift')) out.push(full);
  }
  return out;
}
