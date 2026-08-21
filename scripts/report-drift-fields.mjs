#!/usr/bin/env node
//
// 报告契约漂移里的**新字段**，并交叉查它们在手写模型里有没有。
//
//   node scripts/report-drift-fields.mjs
//
// 读当前工作区里 Packages/AidRunAPI 的未提交 diff（pre-push 与 sync-api-client.sh
// 都会先把重新生成的结果留在那儿），所以它不自己跑生成、也不需要后端仓库。
//
// 为什么要单独有这一步：生成代码**不投入运行时**（运行时走手写 APIClient，
// 理由见 Packages/AidRunAPI/Package.swift），它唯一的作用就是当漂移探测器。
// 只报「不同步」而不查字段落没落到手写模型，等于探了个寂寞 —— 契约加了字段、
// 生成代码跟上了、门禁绿了，而 App 运行时依然读不到那个字段，没有任何东西会说话。

import { execFileSync } from 'node:child_process';

const GEN_DIR = 'Packages/AidRunAPI/Sources/AidRunAPI';
const HANDWRITTEN = 'blindRun';

const git = (...args) => {
  try {
    return execFileSync('git', args, { encoding: 'utf8' });
  } catch {
    return null;
  }
};

const diff = git('diff', '--', GEN_DIR) ?? '';
if (!diff.trim()) {
  console.log('[drift-fields] 生成代码无未提交改动，跳过。');
  process.exit(0);
}

const added = diff
  .split('\n')
  .filter((l) => l.startsWith('+') && !l.startsWith('+++'))
  .map((l) => l.slice(1));

// diff 的 stat 摘要行（'+16 -0'、'123 ++++----'）长得像代码行。
// 2026-08-21 就是被它骗过一次：按「有没有非注释行」粗判，把含 4 个真字段的漂移
// 先报成了「全是文档注释」。
const isStat = (s) => /^[+-]?\d+\s*[+-]*\s*$/.test(s.trim());
const isComment = (s) => s.trim().startsWith('///');

const comments = added.filter(isComment);
const code = added.filter((s) => !isComment(s) && s.trim() && !isStat(s));

console.log(
  `[drift-fields] 漂移 ${added.length} 行：注释 ${comments.length}，代码 ${code.length}`
);

const fields = [
  ...new Set(
    code.map((s) => s.match(/public var (\w+):/)?.[1]).filter(Boolean)
  ),
].sort();

if (fields.length === 0) {
  console.log('[drift-fields] 纯文档注释同步，无新字段。可以直接提交。');
  process.exit(0);
}

console.log(
  `\n[drift-fields] ⚠ 契约新增 ${fields.length} 个字段，逐个查手写模型有没有：\n`
);

const missing = [];
for (const f of fields) {
  // 只搜手写模型目录 —— 生成代码里当然有，那不算数
  const hit = git('grep', '-l', f, '--', HANDWRITTEN);
  if (hit && hit.trim()) {
    console.log(`  ✅ ${f} —— 手写模型已有`);
  } else {
    console.log(`  ❌ ${f} —— 手写模型没有，运行时读不到`);
    missing.push(f);
  }
}

if (missing.length) {
  console.log(`
[drift-fields] ${missing.length} 个字段只存在于生成代码里，当前等于不存在。

**先读契约里每个字段的 description 判后果，不要看字段名猜**，然后分流：
  · 触及盲人端红线（静默失败 / TTS 播报 / null 与 0 语义相反）→ 单独开变更，要测试
  · 纯展示且无播报 → 可并入下一个相关 PR
  · 前端用不上 → 什么都不做，但在 PR body 写明为什么不接

判断结论写进 PR body，别让它停在「探测到了」—— 否则下次同样的字段会被重新探测、
重新讨论一遍。完整判据见 skill aidrun-contract-sync。`);
}
