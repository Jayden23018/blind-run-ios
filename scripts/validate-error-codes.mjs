#!/usr/bin/env node

// 错误码比对：前端 `ErrorCode` 枚举的 raw value vs 后端 `ErrorCode.java` 的枚举常量。
//
// 存在理由：错误码文案会被 TTS 念给盲人听，**语义错的代价是用户按错误信息做出错误行动**。
// 而本仓库已经栽过两次：
//
//   · `PROFILE_INCOMPLETE` —— 文档里写了很久，后端 ErrorCode.java 里根本没有，真实后端永不返回
//   · `DUPLICATE_ORDER` 一码两义 —— 重复评价被念成「下单受阻」，2026-07-31 才拆出 REVIEW_ALREADY_SUBMITTED
//
// 前端映射一个后端不存在的码 = 一条永远走不到的分支，而它长得和真分支一模一样，
// 读代码看不出来。只有拿两边的枚举对撞才能发现。
//
// 刻意不做的事：
//   · **不在本仓库存一份错误码副本**（AGENTS.md 第 7 节）。两边都直接读源文件。
//   · **「后端有、前端没映射」不算失败** —— 后端有大量客服/管理员端点的码，iOS 本来就见不到。
//     只打印出来供人扫一眼。
//
// 用法：
//   node scripts/validate-error-codes.mjs [ErrorCode.java 路径]
//   AIDRUN_BACKEND_ERROR_CODES=/path/to/ErrorCode.java node scripts/validate-error-codes.mjs

import fs from 'node:fs';
import path from 'node:path';

const repoRoot = path.resolve(import.meta.dirname, '..');
const swiftPath = path.join(repoRoot, 'blindRun/Core/Models/ErrorModels.swift');

const javaPath = path.resolve(
  repoRoot,
  process.argv[2] ??
    process.env.AIDRUN_BACKEND_ERROR_CODES ??
    '../demo/src/main/java/com/example/demo/exception/ErrorCode.java'
);

if (!fs.existsSync(javaPath)) {
  console.error(`[error-codes] 读不到后端错误码枚举：${javaPath}`);
  console.error('[error-codes] 这不算通过 —— 契约源在后端仓库，用 --add-dir 挂载或传路径参数。');
  process.exit(1);
}

// 后端：枚举常量名，形如 `    ORDER_NOT_FOUND(HttpStatus.NOT_FOUND, "...")`
const backend = new Set(
  [...fs.readFileSync(javaPath, 'utf8').matchAll(/^\s{4}([A-Z][A-Z0-9_]+)\s*\(/gm)].map((m) => m[1])
);

// 前端：`case foo = "WIRE_CODE"` 的 raw value
const swift = fs.readFileSync(swiftPath, 'utf8');
const enumBody = swift.match(/enum ErrorCode: String[^{]*\{([\s\S]*?)\n\}/);
if (!enumBody) {
  console.error(`[error-codes] 在 ${swiftPath} 里找不到 ErrorCode 枚举，格式可能变了。`);
  process.exit(1);
}
const frontend = new Set(
  [...enumBody[1].matchAll(/case\s+\w+\s*=\s*"([A-Z][A-Z0-9_]*)"/g)].map((m) => m[1])
);

if (!backend.size || !frontend.size) {
  console.error(`[error-codes] 解析异常：后端 ${backend.size} 个、前端 ${frontend.size} 个。`);
  process.exit(1);
}

// 前端映射了但后端没有 —— 这是死分支，失败。
// 白名单：确实由前端本地产生、不来自后端的码。
const CLIENT_ONLY = new Set([]);
const dead = [...frontend].filter((c) => !backend.has(c) && !CLIENT_ONLY.has(c)).sort();

// 后端有但前端没映射 —— 大多是客服/管理员端点的码，不算失败，只列出来。
const unmapped = [...backend].filter((c) => !frontend.has(c)).sort();

console.log(`[error-codes] 后端 ${backend.size} 个码，前端映射 ${frontend.size} 个。`);

if (unmapped.length) {
  console.log(`\n[error-codes] · 后端有、前端未映射（${unmapped.length} 个，不计入失败）：`);
  console.log(`  ${unmapped.join(', ')}`);
}

if (dead.length) {
  console.error(`\n[error-codes] ✗ 前端映射了后端不存在的码（${dead.length} 个）：`);
  for (const code of dead) console.error(`  · ${code}`);
  console.error(
    '\n这些是永远走不到的死分支 —— 它们和真分支长得一样，读代码看不出来。' +
      '\n要么后端删了这个码（跟着删前端映射），要么码名从一开始就抄错了。' +
      `\n后端源：${javaPath}`
  );
  process.exit(1);
}

console.log('\n[error-codes] 通过：前端映射的每个码后端都存在');
