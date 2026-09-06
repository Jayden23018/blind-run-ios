#!/usr/bin/env node
//
// 报告契约漂移里的**新字段**，并交叉查它们在**对应的**手写模型里有没有。
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
//
// 🚨 **判归属，不判字段名。** 2026-08-29 之前这里是拿裸字段名在整个 blindRun/ 里 grep，
// 于是「某处存在同名字段」就被当成「这个字段接上了」。假绿两次，两次都差点放过真缺口：
//   ① 后端往 `IntroCallView` 加的 startAddress / plannedStartTime / plannedEndTime
//      —— 命中的是 OrderDetailResponse / WSNewOrder 上的同名字段
//   ② GET /api/notifications/since 响应信封顶层加的 hasMore
//      —— 命中的是 VolunteerBadgeWall.hasMore，一个成就墙分页标志
// 名字越通用越容易假绿，而通用名恰恰最常见。现在按生成代码里每个字段自带的
// `Generated from` 归属路径定位**那一个**手写模型；找不到就报「无法判定」，绝不报 ✅。

import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const GEN_DIR = 'Packages/AidRunAPI/Sources/AidRunAPI';
const HANDWRITTEN = 'blindRun';

const git = (...args) => {
  try {
    return execFileSync('git', args, { encoding: 'utf8' });
  } catch {
    return null;
  }
};

// diff 的 stat 摘要行（'+16 -0'、'123 ++++----'）长得像代码行。
// 2026-08-21 就是被它骗过一次：按「有没有非注释行」粗判，把含 4 个真字段的漂移
// 先报成了「全是文档注释」。
export const isStat = (s) => /^[+-]?\d+\s*[+-]*\s*$/.test(s.trim());
export const isComment = (s) => s.trim().startsWith('///');

const REMARK = /- Remark: Generated from `([^`]+)`/;
const FIELD = /^\s*public var (\w+):/;

/**
 * 从生成代码的 diff 里取出新增字段，**连同它的归属路径**。
 *
 * 生成器总是把 `- Remark: Generated from` 紧挨在字段声明上方发出来，所以配对方式是
 * 「往上找最近的一条 Remark」。配错的代价是判错模型，所以还要求 Remark 的末段
 * 与字段名一致 —— 对不上就宁可当没有归属（后续报「无法判定」）。
 */
export function parseAddedFields(diff) {
  const out = [];
  let remark = null;
  for (const raw of diff.split('\n')) {
    if (raw.startsWith('@@')) {
      remark = null;
      continue;
    }
    if (raw.startsWith('---') || raw.startsWith('+++')) continue;
    if (raw.startsWith('-')) continue; // 删除行不参与配对
    const line = raw.startsWith('+') ? raw.slice(1) : raw;

    const m = line.match(REMARK);
    if (m) {
      remark = m[1];
      continue;
    }
    const f = raw.startsWith('+') && line.match(FIELD);
    if (f) {
      const name = f[1];
      const ref = remark && remark.split('/').pop() === name ? remark : null;
      out.push({ name, ref });
      remark = null;
    }
  }
  // 同一个字段可能在 diff 里出现多次（属性 + init 参数不算，但嵌套 payload 会）
  const seen = new Set();
  return out.filter((e) => {
    const key = `${e.ref ?? '?'}|${e.name}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

const METHODS = new Set(['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS']);

/**
 * 归属路径 → 该查哪个手写模型。
 *
 * - `#/components/schemas/<模型>/<字段>`（可再嵌套）→ 就查那个模型
 * - `#/paths/<路径>/<方法>/responses/.../<字段>` → **响应信封顶层字段，不属于任何 schema**。
 *   信封在手写侧没有一个稳定的同名类型（`APIClient` 拆信封的方式按端点各不相同），
 *   自动判会退回按名字全局搜 —— 那正是 hasMore 那次假绿的成因。一律交给人。
 */
export function ownerOfRef(ref) {
  if (!ref) return { kind: 'unknown' };
  const segs = ref.replace(/^#\//, '').split('/').filter(Boolean);
  if (segs[0] === 'components' && segs[1] === 'schemas' && segs.length >= 4) {
    return {
      kind: 'schema',
      schema: segs[2],
      nested: segs.slice(3, -1),
    };
  }
  if (segs[0] === 'paths') {
    const i = segs.findIndex((s) => METHODS.has(s.toUpperCase()));
    if (i > 0) {
      return {
        kind: 'envelope',
        method: segs[i].toUpperCase(),
        endpoint: '/' + segs.slice(1, i).join('/'),
      };
    }
    return { kind: 'envelope', method: '?', endpoint: '/' + segs.slice(1).join('/') };
  }
  return { kind: 'unknown' };
}

/**
 * 判一个字段接没接上。`findTypeBody(name)` 返回该手写类型的源码（含 extension），
 * 没有这个类型返回 null —— 注入进来是为了让自测能不碰仓库跑。
 */
export function checkField(entry, findTypeBody) {
  const owner = ownerOfRef(entry.ref);
  if (owner.kind === 'envelope') {
    return {
      status: 'manual',
      owner,
      detail: `响应信封顶层字段（${owner.method} ${owner.endpoint}），不属于任何 schema —— 自己去看这个端点的手写响应模型`,
    };
  }
  if (owner.kind !== 'schema') {
    return { status: 'manual', owner, detail: '生成代码里没有可信的归属路径，判不了' };
  }
  const body = findTypeBody(owner.schema);
  const where = [owner.schema, ...owner.nested].join('.');
  if (body == null) {
    return {
      status: 'manual',
      owner,
      detail: `契约模型 ${where}，手写侧没有同名类型 —— 可能改了名、也可能压根没接`,
    };
  }
  const hit = new RegExp(`\\b${entry.name}\\b`).test(body);
  return {
    status: hit ? 'present' : 'missing',
    owner,
    detail: hit ? `${where} 已有` : `${where} 没有，运行时读不到`,
  };
}

// 手写类型的源码范围：从声明行往下找**同缩进**的 `}`。
// 不数花括号是因为字符串字面量里有 `{orderId}` 这类路径模板，数了会错位。
const fileCache = new Map();
const linesOf = (f) => {
  if (!fileCache.has(f)) fileCache.set(f, readFileSync(f, 'utf8').split('\n'));
  return fileCache.get(f);
};

export function findHandwrittenType(name) {
  // POSIX ERE：git grep 不保证认 \b 和 \w 这类 GNU 扩展，用字符类写死。
  const decl =
    `^[[:blank:]]*([A-Za-z0-9_@()]+[[:blank:]]+)*` +
    `(struct|class|enum|actor|protocol|extension)[[:blank:]]+${name}([^A-Za-z0-9_]|$)`;
  const hits = git('grep', '-n', '-E', decl, '--', HANDWRITTEN);
  if (!hits || !hits.trim()) return null;
  const bodies = [];
  for (const hit of hits.trim().split('\n')) {
    const [file, lineNo] = hit.split(':');
    const lines = linesOf(file);
    const start = Number(lineNo) - 1;
    const indent = lines[start].match(/^[ \t]*/)[0];
    let end = lines.length;
    for (let i = start + 1; i < lines.length; i += 1) {
      if (lines[i] === `${indent}}`) {
        end = i;
        break;
      }
    }
    bodies.push(lines.slice(start, end + 1).join('\n'));
  }
  return bodies.join('\n');
}

function main() {
  const diff = git('diff', '--', GEN_DIR) ?? '';
  if (!diff.trim()) {
    console.log('[drift-fields] 生成代码无未提交改动，跳过。');
    return;
  }

  const added = diff
    .split('\n')
    .filter((l) => l.startsWith('+') && !l.startsWith('+++'))
    .map((l) => l.slice(1));

  const comments = added.filter(isComment);
  const code = added.filter((s) => !isComment(s) && s.trim() && !isStat(s));

  console.log(
    `[drift-fields] 漂移 ${added.length} 行：注释 ${comments.length}，代码 ${code.length}`
  );

  const fields = parseAddedFields(diff);
  if (fields.length === 0) {
    console.log('[drift-fields] 纯文档注释同步，无新字段。可以直接提交。');
    return;
  }

  console.log(
    `\n[drift-fields] ⚠ 契约新增 ${fields.length} 个字段，按归属路径逐个查对应的手写模型：\n`
  );

  const missing = [];
  const manual = [];
  for (const entry of fields) {
    const r = checkField(entry, findHandwrittenType);
    const mark = { present: '✅', missing: '❌', manual: '❓' }[r.status];
    console.log(`  ${mark} ${entry.name} —— ${r.detail}`);
    if (r.status === 'missing') missing.push(entry.name);
    if (r.status === 'manual') manual.push(entry.name);
  }

  if (manual.length) {
    console.log(`
[drift-fields] ${manual.length} 个字段**无法自动判定**（上面标 ❓ 的）。
按名字去全局搜是错的 —— 同名字段到处都是，这条路已经假绿过两次。照归属路径手查那一个模型。`);
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
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main();
}
