#!/usr/bin/env node

// 契约覆盖比对：后端 `api_spec.yaml` 的 operation 集合 vs 前端代码里实际请求的路径。
//
// 存在理由（handoff 2026-08-03/08-04）：后端加了 `SpecDriftTest` 保证 **spec 不落后于代码**，
// 但保证不了**前端不落后于 spec** —— `POST /api/orders/voice/parse` 在后端存在了很久、spec 里没登记，
// 前端因此根本无从知道它存在。这个脚本抓的就是那一类漏。
//
// 刻意不做的事：
// - **不引 YAML parser**。只需要 `METHOD + path` 两层缩进，正则够了；为这点事加个依赖不划算。
// - **不做字段级比对**。那更值钱但贵得多，先让这个跑一段时间看还漏什么。
// - **「spec 有、前端没调」不算失败**。67 个 operation 里大量是客服/管理员端点，iOS 本来就不该调。

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, '..');

// 契约唯一源在后端仓库，本仓库不留副本（AGENTS.md 第 7 节）。
const specPath = path.resolve(
  repoRoot,
  process.argv[2] ?? process.env.AIDRUN_API_SPEC ?? '../demo/docs/api_spec.yaml'
);

const METHODS = ['get', 'post', 'put', 'patch', 'delete'];

/** spec 里的 operation 集合。`paths:` 下两层缩进：`  /api/x:` 然后 `    post:`。 */
function readSpecOperations(text) {
  const operations = new Set();
  let inPaths = false;
  let currentPath = null;

  for (const line of text.split('\n')) {
    if (/^paths:\s*$/.test(line)) {
      inPaths = true;
      continue;
    }
    if (!inPaths) continue;
    // 回到顶层键（components: 等）就说明 paths 段结束了。
    if (/^\S/.test(line)) break;

    const pathMatch = line.match(/^ {2}('?)(\/\S*?)\1:\s*$/);
    if (pathMatch) {
      currentPath = pathMatch[2];
      continue;
    }
    const methodMatch = line.match(/^ {4}([a-z]+):\s*$/);
    if (methodMatch && currentPath && METHODS.includes(methodMatch[1])) {
      operations.add(`${methodMatch[1].toUpperCase()} ${currentPath}`);
    }
  }
  return operations;
}

// `MockAPIClient` 是**路由**不是调用方：里面的 `/api/emergency`、`/api/users` 是前缀匹配，
// 还有 `/api/orders/\d+$` 这种正则片段 —— 全部会被当成「前端在调、spec 没有」误报。
// 误报是这类脚本的死因（报几次假的，人就开始无视它），所以整个文件排除。
// 真正的调用路径在 app 代码里，Mock 只是照着它们分支。
const EXCLUDED_FILES = new Set(['MockAPIClient.swift']);

// Mock 环境专用、真实后端本来就没有的路径。每加一条都要写清楚为什么它不该进契约 ——
// 这个白名单是给「已知的例外」用的，不是给「懒得查」用的。
const MOCK_ONLY_PATHS = new Map([
  [
    '/api/volunteer/mock-verification/approve',
    'VolunteerModule.startMockCertification 只在 currentEnvironment == .mock 时可达（:120-123）',
  ],
]);

function swiftFiles(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) swiftFiles(full, out);
    else if (entry.name.endsWith('.swift') && !EXCLUDED_FILES.has(entry.name)) out.push(full);
  }
  return out;
}

/**
 * 前端代码里的路径字面量。
 *
 * Swift 侧路径带插值（`"/api/orders/\(order.orderId)/review"`），归一成 `{param}` 才能和 spec 对齐。
 * 拿不到 HTTP 方法 —— 它在调用点的 `post(...)` / `get(...)` 上，跨行不好抓，所以**只比对 path**，
 * 方法不同但路径相同的算命中。宁可漏报也不误报：误报会让人开始无视这个脚本。
 */
function readClientPaths(files) {
  const paths = new Map(); // normalized path -> 出处
  for (const file of files) {
    const text = fs.readFileSync(file, 'utf8');
    for (const match of text.matchAll(/"(\/api\/[^"]*)"/g)) {
      const normalized = match[1]
        .replace(/\\\([^)]*\)/g, '{param}')
        .replace(/\/+$/, '');
      if (!paths.has(normalized)) paths.set(normalized, path.relative(repoRoot, file));
    }
  }
  return paths;
}

/** spec 的 `{orderId}` 与前端的 `{param}` 名字不同，比对前统一。 */
const eraseParamNames = (p) => p.replace(/\{[^}]*\}/g, '{param}');

if (!fs.existsSync(specPath)) {
  console.error(`[spec-coverage] 找不到契约文件：${specPath}`);
  console.error('[spec-coverage] 用法：node scripts/validate-spec-coverage.mjs [path/to/api_spec.yaml]');
  process.exit(2);
}

const operations = readSpecOperations(fs.readFileSync(specPath, 'utf8'));
if (operations.size === 0) {
  console.error(`[spec-coverage] 从 ${specPath} 里没解析出任何 operation —— 多半是 spec 结构变了，请检查本脚本`);
  process.exit(2);
}

const specPaths = new Set([...operations].map((op) => eraseParamNames(op.split(' ')[1])));
const clientPaths = readClientPaths(swiftFiles(path.join(repoRoot, 'blindRun')));

const unimplemented = [...specPaths].filter((p) => !clientPaths.has(p)).sort();
const unknownToSpec = [...clientPaths.keys()]
  .filter((p) => !specPaths.has(eraseParamNames(p)) && !MOCK_ONLY_PATHS.has(p))
  .sort();

console.log(`[spec-coverage] 契约：${specPath}`);
console.log(`[spec-coverage] spec ${operations.size} 个 operation / ${specPaths.size} 条路径；前端在调 ${clientPaths.size} 条`);

if (unknownToSpec.length > 0) {
  console.error(`\n[spec-coverage] ✗ 前端在调、但 spec 里没有（${unknownToSpec.length} 条）——这是硬错误：`);
  for (const p of unknownToSpec) console.error(`  ${p}  (${clientPaths.get(p)})`);
}

if (unimplemented.length > 0) {
  console.log(`\n[spec-coverage] · spec 有、前端从未调用（${unimplemented.length} 条）——不算失败，但值得扫一眼有没有该用的：`);
  for (const p of unimplemented) console.log(`  ${p}`);
}

const mockOnlyInUse = [...MOCK_ONLY_PATHS.keys()].filter((p) => clientPaths.has(p));
if (mockOnlyInUse.length > 0) {
  console.log(`\n[spec-coverage] · 已知 Mock 专用路径（${mockOnlyInUse.length} 条，不计入失败）：`);
  for (const p of mockOnlyInUse) console.log(`  ${p} —— ${MOCK_ONLY_PATHS.get(p)}`);
}

if (unknownToSpec.length > 0) {
  process.exitCode = 1;
} else {
  console.log('\n[spec-coverage] 通过：前端调用的每条路径都在契约里');
}
