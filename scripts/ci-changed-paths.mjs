#!/usr/bin/env node
//
// CI 按 PR 改动的路径决定编译门禁跑哪几步（#714，负责人 2026-11-05 批准放松）。
//
// 输出两个值（写进 $GITHUB_OUTPUT，同时打印到标准输出）：
//   docs_only   = true  → 只改了文档类路径，编译门禁整个 job 跳过（job 级 if，必需检查算通过）
//   api_package = false → 没碰 AidRunAPI 包和生成链路，`swift test` 与「重新生成并比对」两步跳过
//
// 拿不准的方向一律多跑：空列表、读不出来都当「全跑」。判错成「少跑」才是事故（门禁静默空过）。
//
// 用法：
//   git diff --name-only --no-renames BASE HEAD | node scripts/ci-changed-paths.mjs
//   node scripts/ci-changed-paths.mjs --self-test
//
// ⚠️ 一定带 --no-renames：默认开着改名检测时 --name-only 只打新路径，
// 「blindRun/X.swift 改名成 docs/X.md」会被看成只改了文档，而 App 里少了一个源文件。

import fs from 'node:fs';

// 改了这些就跑 AidRunAPI 两步。verify.yml 与本脚本也在内：判据本身变了，那次必须全跑。
const API_PREFIXES = ['Packages/AidRunAPI/', 'scripts/openapi/'];
const API_FILES = [
  'scripts/generate-api-client.sh',
  'scripts/sync-api-client.sh', // 与 scripts/hooks/pre-push.sh 的分档口径一致
  '.github/workflows/verify.yml',
  'scripts/ci-changed-paths.mjs',
];

const DOC_PREFIXES = ['docs/', 'openspec/', '.claude/'];
// 这些目录里的 .md 不算文档：blindRun* 三个是 Xcode 同步文件夹，里面的任何文件都会进包
// （同名文件还会撞「Multiple commands produce」编不过）；Packages / Vendor / Pods 参与构建。
const BUILD_DIRS = new Set(['blindRun', 'blindRunTests', 'blindRunUITests', 'Packages', 'Vendor', 'Pods']);

export function isDocPath(file) {
  if (DOC_PREFIXES.some((p) => file.startsWith(p))) return true;
  if (!file.endsWith('.md')) return false;
  return !BUILD_DIRS.has(file.split('/')[0]);
}

export function touchesApiPackage(file) {
  return API_PREFIXES.some((p) => file.startsWith(p)) || API_FILES.includes(file);
}

export function classify(files) {
  const list = files.map((f) => f.trim()).filter(Boolean);
  if (list.length === 0) return { docsOnly: false, apiPackage: true };
  // 以 " 开头 = git 把路径加引号转义了（忘了 -z），真实路径读不出来，当全跑。
  if (list.some((f) => f.startsWith('"'))) return { docsOnly: false, apiPackage: true };
  return {
    docsOnly: list.every(isDocPath),
    apiPackage: list.some(touchesApiPackage),
  };
}

function selfTest() {
  const cases = [
    // [名称, 改动文件, 期望 docsOnly, 期望 apiPackage]
    ['空列表当全跑', [], false, true],
    ['只改 docs', ['docs/review/a.md', 'docs/ui/x.png'], true, false],
    ['只改 openspec 与 .claude', ['openspec/changes/x/tasks.md', '.claude/skills/y/SKILL.md'], true, false],
    ['根目录 md', ['README.md', 'AGENTS.md'], true, false],
    ['同步文件夹里的 md 会进包，不算文档', ['blindRun/Notes.md'], false, false],
    ['Vendor 里的 md 不算文档', ['Vendor/AliyunCloudAuth/2.3.50/SOURCE.md'], false, false],
    ['文档加一个 Swift 文件就要编译', ['docs/a.md', 'blindRun/Home/HomeView.swift'], false, false],
    ['改 App 的 Swift 不跑 AidRunAPI 两步', ['blindRun/Core/APIClient.swift'], false, false],
    ['改 AidRunAPI 包', ['Packages/AidRunAPI/Sources/AidRunAPI/Types.swift'], false, true],
    ['改生成脚本', ['scripts/generate-api-client.sh'], false, true],
    ['改一键同步脚本', ['scripts/sync-api-client.sh'], false, true],
    ['改生成器钉版本的包', ['scripts/openapi/Package.resolved'], false, true],
    ['改 verify.yml 全跑', ['.github/workflows/verify.yml'], false, true],
    ['改本判定脚本全跑', ['scripts/ci-changed-paths.mjs'], false, true],
    ['md 大写扩展名不当文档（多跑）', ['NOTES.MD'], false, false],
    ['前缀只认整段目录', ['docsx/a.swift', 'Packages/AidRunAPIx/a.swift'], false, false],
    ['空白行忽略', ['docs/a.md', '', '  '], true, false],
    ['Packages 里的 md 不算文档', ['Packages/AidRunAPI/README.md'], false, true],
    ['中文文件名（-z 原样输出）算文档', ['docs/ui/mockups/running-state/screens/A-跑者端.png'], true, false],
    ['带引号的转义路径读不出来，当全跑', ['"docs/ui/\\350\\267\\221.png"'], false, true],
  ];
  let failed = 0;
  for (const [name, files, wantDocs, wantApi] of cases) {
    const got = classify(files);
    const ok = got.docsOnly === wantDocs && got.apiPackage === wantApi;
    if (!ok) failed++;
    console.log(`${ok ? 'ok  ' : 'FAIL'} ${name} → docs_only=${got.docsOnly} api_package=${got.apiPackage}`);
  }
  console.log(`${cases.length - failed}/${cases.length} 通过`);
  if (failed > 0) process.exit(1);
}

function main() {
  if (process.argv.includes('--self-test')) return selfTest();
  // CI 用 `git diff -z`（\0 分隔），手工试用时按行喂也行。
  const files = fs.readFileSync(0, 'utf8').split(/[\0\n]/);
  const { docsOnly, apiPackage } = classify(files);
  const out = `docs_only=${docsOnly}\napi_package=${apiPackage}\n`;
  process.stdout.write(`改动 ${files.filter((f) => f.trim()).length} 个文件\n${out}`);
  if (process.env.GITHUB_OUTPUT) fs.appendFileSync(process.env.GITHUB_OUTPUT, out);
}

main();
