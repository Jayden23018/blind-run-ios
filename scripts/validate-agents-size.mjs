#!/usr/bin/env node
//
// AGENTS.md 体积闸（#482）。
//
// `CLAUDE.md:1` 的 `@AGENTS.md` 每个会话无条件注入，每一轮都按 cache read 价重读。
// 它 09-05 压到 22.6KB，六周后长回 51.7KB —— 只靠自觉挡不住，按 AGENTS.md §1.1 落成静态检查。
//
// 只数**会被注入**的部分：块级 HTML 注释（`<!-- … -->`）在注入前被剥掉
// （官方 memory 文档原话，#482 SPEC 实测 @import 的 AGENTS.md 同样被剥：57,317 vs 原样 78,200 token），
// 所以历史说明写成注释不占上下文，也不该被这道闸逼着删。代码块里的 `<!--` 不剥，与官方行为一致。
//
// 用法：
//   node scripts/validate-agents-size.mjs              # 查仓库根的 AGENTS.md
//   node scripts/validate-agents-size.mjs <file>       # 查任意文件（验红：喂 origin/main 的旧版）
//   node scripts/validate-agents-size.mjs --self-test

import fs from 'node:fs';
import path from 'node:path';

export const MAX_BYTES = 16384;
export const MAX_LINES = 200;

// 剥掉块级 HTML 注释：行首（去缩进后）以 `<!--` 开头，到含 `-->` 的那一行为止，整行去掉。
// 行内注释（`文字 <!-- x -->`）不是块级，不剥。围栏代码块（``` / ~~~）里的一律不动。
export function injectedText(src) {
  const kept = [];
  let fence = null;
  let inComment = false;
  for (const line of src.split('\n')) {
    if (inComment) {
      if (line.includes('-->')) inComment = false;
      continue;
    }
    const trimmed = line.trimStart();
    const fenceMark = trimmed.match(/^(`{3,}|~{3,})/);
    if (fenceMark) {
      if (!fence) fence = fenceMark[1][0];
      else if (fenceMark[1][0] === fence) fence = null;
      kept.push(line);
      continue;
    }
    if (!fence && trimmed.startsWith('<!--')) {
      if (!trimmed.slice(4).includes('-->')) inComment = true;
      continue;
    }
    kept.push(line);
  }
  return kept.join('\n');
}

// 行数按 `wc -l` 口径：数换行符，末行没换行也算一行。
export function measure(src) {
  const text = injectedText(src);
  const bytes = Buffer.byteLength(text, 'utf8');
  const newlines = (text.match(/\n/g) || []).length;
  const lines = newlines + (text.length && !text.endsWith('\n') ? 1 : 0);
  return { bytes, lines, ok: bytes <= MAX_BYTES && lines <= MAX_LINES };
}

// 造一段恰好 n 字节、每行 100 字节以内的正文（行数远低于上限，只让字节说话）。
function bodyOfBytes(n) {
  const row = 'a'.repeat(99) + '\n';
  return row.repeat(Math.floor(n / row.length)) + 'b'.repeat(n % row.length);
}

const selfTests = [
  {
    // 落在闸门正上方一字节：上限被偷偷放宽成 16,385 时这条会转绿。
    name: '16,385 B 正文 → 红',
    src: bodyOfBytes(MAX_BYTES + 1),
    expectOk: false,
  },
  {
    // 恰好卡在上限，再加 50KB 注释：按原始字节算会红，只数注入部分才绿。
    name: '16,384 B 正文 + 50KB 块级 HTML 注释 → 绿',
    src: '<!--\n' + bodyOfBytes(50 * 1024) + '\n-->\n' + bodyOfBytes(MAX_BYTES),
    expectOk: true,
  },
  {
    name: '201 行短行 → 红',
    src: 'x\n'.repeat(MAX_LINES + 1),
    expectOk: false,
  },
  {
    // 代码块里的注释照样注入，剥了就会少算。
    name: '代码块里的 <!-- 不剥（正文超限照样红）',
    src: '```html\n<!--\n' + bodyOfBytes(MAX_BYTES) + '\n-->\n```\n',
    expectOk: false,
  },
];

function selfTest() {
  let failed = 0;
  for (const t of selfTests) {
    const r = measure(t.src);
    if (r.ok === t.expectOk) {
      console.log(`✓ ${t.name}（${r.bytes} B / ${r.lines} 行）`);
    } else {
      console.error(`✗ ${t.name}：期望 ${t.expectOk ? '绿' : '红'}，实得 ${r.bytes} B / ${r.lines} 行`);
      failed += 1;
    }
  }
  if (failed) {
    console.error(`\n${failed} 条失败。`);
    process.exit(1);
  }
  console.log(`\n${selfTests.length} 条全部通过。`);
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === path.resolve(import.meta.filename);
if (isMain) {
  const arg = process.argv[2];
  if (arg === '--self-test') {
    selfTest();
  } else {
    const file = arg || path.resolve(import.meta.dirname, '..', 'AGENTS.md');
    const r = measure(fs.readFileSync(file, 'utf8'));
    const verdict = `${file}：注入部分 ${r.bytes} B（上限 ${MAX_BYTES}）/ ${r.lines} 行（上限 ${MAX_LINES}）`;
    if (r.ok) {
      console.log(`✓ ${verdict}`);
    } else {
      console.error(`✗ ${verdict}`);
      console.error('细节下沉到 skill，历史说明改成块级 <!-- --> 注释（不进上下文）。去向见 docs/specs/482-agents-md-slimming.md。');
      process.exit(1);
    }
  }
}
