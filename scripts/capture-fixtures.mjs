#!/usr/bin/env node

// 采集**真实后端响应的原始字节**，落盘到 blindRunTests/Fixtures/，供 ContractFixtureTests 回归。
//
// 存在理由：本仓库的契约测试此前全部把 JSON 手写成 Swift 字符串字面量 ——
// 手写的是「我以为后端发的」。小数秒那次事故，手写的是 `...:42`，服务器发的是 `...:42.644571`，
// 于是测试永远绿而盲人听到的是一串 ISO 原文。
//
// 三条设计原则（都是刻意的）：
//
//   1. **只打只读端点。** 不建订单、不触发求助、不改任何服务端状态。
//      写端点的响应体要采，得单独想清楚清理方案，不在这个脚本里顺手做。
//   2. **保留原始字节。** 不 pretty-print、不重排 key。小数秒、字段顺序、
//      `null` vs 字段缺失，全都是要捕获的信息，格式化一次就全丢了。
//   3. **脱敏但保持格式合法。** 手机号换成同样 11 位的假号，token 换成等长占位。
//      换成 `***` 会让「明文手机号」那条断言失去意义。
//
// 用法：
//   node scripts/capture-fixtures.mjs --dry-run     # 只打印会打哪些端点，不发请求（默认）
//   node scripts/capture-fixtures.mjs --write       # 真的请求并落盘
//
// 环境变量：
//   AIDRUN_FIXTURE_BLIND_PHONE       默认 18664945138（生产 sms.test-phones 白名单里的盲人号）
//   AIDRUN_FIXTURE_VOLUNTEER_PHONE   默认 13823594196（白名单里的志愿者号）
//   AIDRUN_FIXTURE_CODE              默认 000000
//   AIDRUN_FIXTURE_BLIND_TOKEN       给了就跳过 send-code/verify-code（零写入、零短信）
//   AIDRUN_FIXTURE_VOLUNTEER_TOKEN   同上
//
// ⚠️ 号码分配跟直觉相反：**138 是志愿者、186 是盲人**。
//    原因见 docs/test-accounts.md —— 13823594196 在生产上早就是 verified=1 的现成志愿者，
//    而角色一旦设定不可更改。这是定论，不是笔误，别"顺手改回来"。
//
// 🚨 别把号码换成白名单以外的号。白名单外的号会走 `smsService.sendVerificationCode` 真发短信，
//    且 Redis 里存的是随机码 —— 固定码 000000 必然校验失败，脚本第一步就挂。
//    白名单当前值以生产实测为准：
//      sudo systemctl cat blindrun | grep -oE '\-Dsms\.test-phones=[^ ]*'
//
// 🚨 verify-code 是**写路径**（AuthService `findByPhone().orElseGet(新建 User)`）——
//    号码在生产库不存在时会建出一个 role=UNSET 的用户。所以只用已存在的账号，
//    或者干脆走 AIDRUN_FIXTURE_*_TOKEN 完全绕开登录。

import fs from 'node:fs';
import path from 'node:path';

const BASE_URL = 'http://47.114.113.171';
const OUT_DIR = path.resolve(import.meta.dirname, '../blindRunTests/Fixtures');

const BLIND_PHONE = process.env.AIDRUN_FIXTURE_BLIND_PHONE ?? '18664945138';
const VOLUNTEER_PHONE = process.env.AIDRUN_FIXTURE_VOLUNTEER_PHONE ?? '13823594196';
const CODE = process.env.AIDRUN_FIXTURE_CODE ?? '000000';

const WRITE = process.argv.includes('--write');
const DRY = !WRITE;

// 只读端点清单。`model` 必须与 ContractFixtureTests.checkers 的 key 对上，
// 否则那条测试会失败 —— 采集了却没人检查的 fixture 等于没采集。
//
// ⚠️ 这些路径是 2026-08-05 逐条比对 controller 注解 + docs/api_spec.yaml 核实过的。
//    上一版有四条是**臆想出来的**，全部会 404/405 —— 而脚本只 console.warn 跳过，
//    于是 manifest 里静悄悄少了四个 fixture，看着像"采集成功"。改路径前请重新核实。
//
// `{userId}` 会被替换成对应角色 token 里的 userId（JWT subject）。
const ENDPOINTS = [
  // 曾错写成 /api/user/me（不存在）
  { model: 'CurrentUserResponse', label: 'blind', method: 'GET', path: '/api/auth/me', as: 'blind' },
  { model: 'BlindProfileResponse', label: 'self', method: 'GET', path: '/api/blind/profile', as: 'blind' },
  // 曾错写成 /api/blind/emergency-contacts（不存在）。真实路径带 userId，
  // 且 controller 的 verifyUser 强制 JWT userId == 路径 userId。
  { model: 'EmergencyContactResponse', label: 'list', method: 'GET', path: '/api/users/{userId}/emergency-contacts', as: 'blind' },
  // 曾错写成 /api/orders（根路径只有 POST → 405）
  { model: 'PagedOrderResponse', label: 'blind-history', method: 'GET', path: '/api/orders/mine?page=0&size=5', as: 'blind' },
  { model: 'LegalLinksResponse', label: 'public', method: 'GET', path: '/api/misc/legal-links', as: 'none' },
  { model: 'VolunteerProfileResponse', label: 'self', method: 'GET', path: '/api/volunteer/profile', as: 'volunteer' },
  // 曾错写成 /api/volunteer/orders（不存在）。志愿者历史订单走同一个 /mine + role 参数；
  // 刻意不用 /api/orders/available —— 那条依赖 Redis 里有该志愿者的位置，否则返空数组。
  { model: 'PagedOrderResponse', label: 'volunteer-history', method: 'GET', path: '/api/orders/mine?role=VOLUNTEER&page=0&size=5', as: 'volunteer' },
];

// ---------------------------------------------------------------- 脱敏

const PHONE_PLACEHOLDER = '13900000000';

// ⚠️ 手机号/身份证两条**必须带前后数字边界** `(?<![0-9])` / `(?![0-9])`。
// 不带边界时，13 位毫秒时间戳（2026 年形如 `17xxxxxxxxxxx`，第二位是 7 ∈ [3-9]）
// 的前 11 位会被当成手机号替换掉，18 位以上的纯数字会被当成身份证 ——
// 那就把 fixture 的原始字节污染了，而"保留原始字节"正是这个脚本存在的理由。
// 后端 SentryConfig.java 的 PHONE 正则踩过一模一样的坑（注释在 :41-45），这里是同一个修法。
const REDACTIONS = [
  // token / JWT：等长占位，保持「非空字符串」这一契约事实
  [/"(token|accessToken|refreshToken)"\s*:\s*"[^"]*"/g, '"$1":"REDACTED_JWT_FOR_FIXTURE_ONLY"'],
  // 手机号：换成同样 11 位的假号，保持长度与「明文」语义
  [/(?<![0-9])1[3-9]\d{9}(?![0-9])/g, PHONE_PLACEHOLDER],
  // 身份证
  [/(?<![0-9])\d{17}[\dXx](?![0-9Xx])/g, '110101199001011234'],
];

/// 坐标：保留城市级前 2 位小数，其余补 0，**长度与原值一致**。
///
/// 为什么不整个替换掉：`22.526319162152376` 这种 17 位有效数字正是 Double 解析的契约事实，
/// 换成 `0` 或 `22.5` 就把「后端会发长小数」这条信息丢了，而那类精度问题恰恰是要防的。
/// 为什么必须动：真机测出来的「当前位置」订单带的是**真人此刻的物理位置**，
/// 而 fixture 是要提交进 git 的。CLAUDE.md 把 GPS 列为高敏感数据，
/// 连推给客服的 WS 消息都只给 hasGpsLocation 布尔，更不该进公开仓库。
function redactCoords(text) {
  return text.replace(
    /("(?:startLatitude|startLongitude|endLatitude|endLongitude|lat|lng|gpsLat|gpsLng)"\s*:\s*)(-?\d+\.\d+)/g,
    (_, key, num) => {
      const [int, dec] = num.split('.');
      const coarse = dec.slice(0, 2).padEnd(dec.length, '0');
      return `${key}${int}.${coarse}`;
    },
  );
}

function redact(text) {
  return redactCoords(REDACTIONS.reduce((acc, [re, to]) => acc.replace(re, to), text));
}

// ---------------------------------------------------------------- HTTP

async function http(method, urlPath, token) {
  const response = await fetch(new URL(urlPath, BASE_URL), {
    method,
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
  });
  return { status: response.status, text: await response.text() };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/// 从 JWT 里取 userId。后端把 userId 放在 subject（见后端 CLAUDE.md「JWT：subject = userId(Long)」）。
/// 走 token 而不是登录响应，是为了让 AIDRUN_FIXTURE_*_TOKEN 那条零写入路径也拿得到 userId。
/// 只解 base64 读 payload，不验签 —— 这里不需要验，服务端会验。
function userIdFromToken(token) {
  const payload = token.split('.')[1];
  if (!payload) throw new Error('token 不是 JWT，取不到 userId');
  const json = Buffer.from(payload.replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8');
  const sub = JSON.parse(json).sub;
  if (!sub) throw new Error(`JWT 里没有 sub，取不到 userId：${json}`);
  return String(sub);
}

/// send-code 有短信限流（429 + retryAfterSeconds，实测窗口 60s）。
/// 429 说明这条链路真的会消耗短信配额，所以：能复用 token 就别再发码。
async function sendCode(phone, attempt = 0) {
  const response = await fetch(new URL('/api/auth/send-code', BASE_URL), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ phone }),
  });
  if (response.status === 429 && attempt < 2) {
    const body = await response.json().catch(() => ({}));
    const wait = Number(body.retryAfterSeconds ?? 60) + 1;
    console.log(`  · send-code 被限流，${wait}s 后重试（第 ${attempt + 1} 次）…`);
    await sleep(wait * 1000);
    return sendCode(phone, attempt + 1);
  }
  if (!response.ok) {
    throw new Error(`send-code ${phone} 失败：${response.status} ${await response.text()}`);
  }
}

async function login(phone) {
  // 已有 token 就直接用，跳过 send-code —— 别为了采 fixture 烧短信配额。
  const envToken =
    phone === BLIND_PHONE
      ? process.env.AIDRUN_FIXTURE_BLIND_TOKEN
      : process.env.AIDRUN_FIXTURE_VOLUNTEER_TOKEN;
  if (envToken) {
    console.log(`  · ${phone} 复用环境变量里的 token，跳过 send-code`);
    return { token: envToken, loginRaw: null };
  }

  await sendCode(phone);

  const verify = await fetch(new URL('/api/auth/verify-code', BASE_URL), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ phone, code: CODE }),
  });
  const text = await verify.text();
  if (!verify.ok) throw new Error(`verify-code ${phone} 失败：${verify.status} ${text}`);

  const parsed = JSON.parse(text);
  const token = parsed?.data?.token ?? parsed?.token;
  if (!token) throw new Error(`verify-code ${phone} 没返回 token：${text}`);

  // 登录响应本身也是一条契约，顺手采（脱敏后 token 是占位串，但「有 token 字段」的事实保住了）
  return { token, loginRaw: text };
}

// ---------------------------------------------------------------- main

async function main() {
  console.log(`[capture-fixtures] 目标：${BASE_URL}`);
  console.log(`[capture-fixtures] 模式：${DRY ? 'dry-run（不发请求）' : 'write（真实请求并落盘）'}`);
  console.log(`[capture-fixtures] 只读端点 ${ENDPOINTS.length} 条，不建订单、不触发求助、不改服务端状态。\n`);

  for (const e of ENDPOINTS) {
    console.log(`  ${e.method.padEnd(4)} ${e.path.padEnd(42)} → ${e.model}__${e.label}.json  [${e.as}]`);
  }

  if (DRY) {
    console.log('\n[capture-fixtures] dry-run 结束。确认无误后加 --write 真正采集。');
    return;
  }

  fs.mkdirSync(OUT_DIR, { recursive: true });

  const tokens = { none: null };
  const manifest = {
    capturedAt: new Date().toISOString(),
    baseURL: BASE_URL,
    note: '原始字节，未 pretty-print。手机号/token/身份证已脱敏但保持格式合法。',
    files: {},
  };

  console.log('\n[capture-fixtures] 登录…');
  const blind = await login(BLIND_PHONE);
  tokens.blind = blind.token;
  if (blind.loginRaw) writeFixture('LoginResponse', 'blind', blind.loginRaw, manifest);

  try {
    const volunteer = await login(VOLUNTEER_PHONE);
    tokens.volunteer = volunteer.token;
  } catch (err) {
    console.warn(`[capture-fixtures] ⚠ 志愿者账号登录失败，跳过志愿者端点：${err.message}`);
  }

  const userIds = {};
  for (const role of ['blind', 'volunteer']) {
    if (tokens[role]) userIds[role] = userIdFromToken(tokens[role]);
  }
  console.log(`[capture-fixtures] userId: ${JSON.stringify(userIds)}`);

  // 采集失败要能让调用方看见。上一版只 console.warn 就往下走，于是四条路径写错时
  // manifest 静悄悄少了四个文件，输出看着仍像"完成"—— 这类"少了但不报错"是最难发现的。
  const failures = [];

  for (const e of ENDPOINTS) {
    if (e.as !== 'none' && !tokens[e.as]) {
      failures.push(`${e.path}（没有 ${e.as} token）`);
      console.warn(`  ⚠ 跳过 ${e.path}（没有 ${e.as} token）`);
      continue;
    }
    const urlPath = e.path.replace('{userId}', userIds[e.as] ?? '');
    try {
      const { status, text } = await http(e.method, urlPath, tokens[e.as]);
      if (status < 200 || status >= 300) {
        failures.push(`${e.method} ${urlPath} → ${status}`);
        console.warn(`  ⚠ ${e.method} ${urlPath} → ${status}，不落盘`);
        continue;
      }
      writeFixture(e.model, e.label, text, manifest);
    } catch (err) {
      failures.push(`${e.method} ${urlPath} → ${err.message}`);
      console.warn(`  ⚠ ${e.method} ${urlPath} 失败：${err.message}`);
    }
  }

  fs.writeFileSync(path.join(OUT_DIR, '_manifest.json'), JSON.stringify(manifest, null, 2));
  console.log(`\n[capture-fixtures] 写入 ${Object.keys(manifest.files).length} 个 fixture 到 ${OUT_DIR}`);
  console.log('[capture-fixtures] 落盘后请**人工过一遍**再提交：确认没有残留真实个人信息。');

  if (failures.length) {
    console.error(`\n[capture-fixtures] ❌ ${failures.length} 条端点没采到：`);
    for (const f of failures) console.error(`    ${f}`);
    console.error('部分采集不算成功 —— 少一个 fixture 就少一条契约防线。');
    process.exit(1);
  }
  console.log('[capture-fixtures] ✅ 全部端点采集成功。');
}

function writeFixture(model, label, rawText, manifest) {
  const name = `${model}__${label}.json`;
  const body = redact(rawText);
  fs.writeFileSync(path.join(OUT_DIR, name), body);
  manifest.files[name] = { model, label, bytes: body.length };
  console.log(`  ✓ ${name} (${body.length}B)`);
}

main().catch((err) => {
  console.error(`[capture-fixtures] 失败：${err.message}`);
  process.exit(1);
});
