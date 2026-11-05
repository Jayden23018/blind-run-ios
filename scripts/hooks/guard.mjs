#!/usr/bin/env node

// AidRun 项目守卫 —— 把 AGENTS.md 里代价最高的几条红线从「散文约束」变成「机器强制」。
//
// 存在理由：这些规则全部写在 AGENTS.md 里很久了，但每一条都至少被违反过一次。
// 文档是建议，hook 每次都执行。
//
// 用法（由 .claude/settings.json 调用）：
//   node scripts/hooks/guard.mjs pre    # PreToolUse：阻断
//   node scripts/hooks/guard.mjs post   # PostToolUse：写完再查，Claude 收到后会自己改回来
//
// 退出码 2 = 拦下并把 stderr 反馈给 Claude；0 = 放行。
// 任何内部异常一律放行（守卫本身不该成为阻塞源），但会在 stderr 留痕。
//
// 抑制：在触发行尾加 `// guard:allow <rule-id>`。
// 刻意做成需要显式标注 —— 白名单文件会腐烂，行内标注跟着代码走。
//
// 本文件只做入口与调度（#722 拆分）。规则按主题放在 `scripts/hooks/guard/` 下，改一条规则只读一个模块：
//   common.mjs               fail()、注释行过滤、读文件等共用工具
//   repo-files.mjs           pre：归档契约、冻结文件与架构排除设置、隐私清单、高德 key、OpenAPI 运行时
//   swift-edits.mjs          pre：weak 临时对象、UI 测试敲正中、裸 open URL、盲人端触达 64pt、通知播报档位
//   scripts-and-ci.mjs       pre：workflow if 里的 secrets、真机 xcodebuild 团队号、文档里写死团队号
//   ui-test-identifiers.mjs  pre：UI 测试与 App 的 accessibilityIdentifier 漂移（跨文件）
//   test-target.mjs          post：无障碍审计类型全集、测试 helper 漏交 weak 依赖
//   content-scan.mjs         post：对生产 Swift 逐行跑规则表；规则表在 rules-copy / rules-ui / rules-safety
// 下面两张清单的顺序就是检查顺序：一次改动同时命中多条时，先报排在前面的那条。
// 自测：`node scripts/validate-guard.mjs`（CI 与 pre-push 都跑）。

import fs from 'node:fs';
import path from 'node:path';
import { scanSwift } from './guard/content-scan.mjs';
import {
  checkAmapKey,
  checkArchExclusion,
  checkArchivedContract,
  checkFrozenFile,
  checkOpenAPIInAppTarget,
  checkSdkOnlyReasonCode,
  checkVendorPrivacyManifest,
} from './guard/repo-files.mjs';
import { checkHardcodedTeamId, checkMissingTeam, checkSecretsInIf } from './guard/scripts-and-ci.mjs';
import {
  checkBannerSpeechPriority,
  checkBlindTapCenter,
  checkRawOpenURL,
  checkSmallTouchTarget,
  checkWeakTemporary,
} from './guard/swift-edits.mjs';
import { checkA11yAuditTypes, checkWeakHelper } from './guard/test-target.mjs';
import { checkStaleUITestIdentifier } from './guard/ui-test-identifiers.mjs';

const MODE = process.argv[2] === 'pre' ? 'pre' : 'post';

// pre 段：Edit / Write 落盘之前，查本次写入的内容（`content` / `new_string`）。
const PRE_EDIT_CHECKS = [
  checkFrozenFile,
  checkArchExclusion,
  checkVendorPrivacyManifest,
  checkSdkOnlyReasonCode,
  checkAmapKey,
  checkOpenAPIInAppTarget,
  checkWeakTemporary,
  checkBlindTapCenter,
  checkRawOpenURL,
  checkSmallTouchTarget,
  checkSecretsInIf,
  checkMissingTeam,
  checkHardcodedTeamId,
  checkBannerSpeechPriority,
  checkStaleUITestIdentifier,
];

// post 段：落盘之后从磁盘读真实内容再查。这两条查测试 target，必须排在下面「只查生产 target」的过滤之前。
const POST_TEST_TARGET_CHECKS = [checkA11yAuditTypes, checkWeakHelper];

function readStdin() {
  try {
    return fs.readFileSync(0, 'utf8');
  } catch {
    return '';
  }
}

function main() {
  const raw = readStdin();
  if (!raw.trim()) process.exit(0);

  let payload;
  try {
    payload = JSON.parse(raw);
  } catch {
    process.exit(0);
  }

  const tool = payload.tool_name || '';
  const input = payload.tool_input || {};
  const filePath = input.file_path || '';

  if (MODE === 'pre') {
    // 1. 禁读已知有错的归档契约副本（AGENTS.md 第 2 节）
    checkArchivedContract({ tool, filePath });

    if (tool !== 'Edit' && tool !== 'Write') process.exit(0);

    const body = input.content || input.new_string || '';
    for (const check of PRE_EDIT_CHECKS) check({ input, filePath, body });

    process.exit(0);
  }

  // post：从磁盘读改动后的真实内容再查，比解析 diff 可靠
  if (tool !== 'Edit' && tool !== 'Write') process.exit(0);
  if (!filePath.endsWith('.swift')) process.exit(0);
  if (!path.isAbsolute(filePath) || !fs.existsSync(filePath)) process.exit(0);

  for (const check of POST_TEST_TARGET_CHECKS) check({ filePath });

  // 只查生产 target。测试里出现这些字符串是**正确**的 —— 红线用例本身就得把违规文案
  // 写成断言清单（`EmergencySOSTests.forbidden`），在那儿拦等于把守住红线的人抓起来。
  if (!/\/blindRun\/[^/]/.test(filePath) || /\/blindRun(Tests|UITests)\//.test(filePath)) {
    process.exit(0);
  }

  scanSwift(filePath);
  process.exit(0);
}

try {
  main();
} catch (err) {
  // 守卫自身出错绝不阻塞开发
  process.stderr.write(`[guard] internal error (ignored): ${err.message}\n`);
  process.exit(0);
}
