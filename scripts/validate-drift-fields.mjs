#!/usr/bin/env node
//
// scripts/report-drift-fields.mjs 的回归测试 —— 契约漂移闸的「字段接没接上」判据。
//
// 为什么需要它：这个闸只在漂移发生时才跑，而它给的是**绿灯**。绿灯坏掉不会报错，
// 只会安静地放过缺口 —— 它已经这样假绿过两次，两次都是同一个根因：
// 按裸字段名在整个 blindRun/ 里全局搜，「某处有同名字段」被当成「这个字段接上了」。
// 下面头两条用例逐字复现那两次，改坏判据就会红。
//
// 判据本身写成纯函数 + 注入的 findTypeBody，就是为了让这些用例不碰仓库、不碰 git。
// 最后一条例外：范围切割（从声明行找同缩进的 `}`）只能对着真文件验，
// 它悄悄跑飞的话会把半个文件当成模型体 —— 那是另一种形态的假绿。

import { parseAddedFields, ownerOfRef, checkField, findHandwrittenType } from './report-drift-fields.mjs';

// 假仓库：只有这几个手写模型。两条回归用例的全部张力都在这里 ——
// 被查的字段名**确实存在**于某个模型上，只是不在它该在的那个上。
const REPO = {
  IntroCallView: `nonisolated struct IntroCallView: Decodable, Sendable, Equatable {
    let counterpartName: String?
    let counterpartPhone: String?
    let counterpartPhoneMasked: String?
    let myDecision: String?
    let windowEndsAt: String?
}`,
  OrderDetailResponse: `struct OrderDetailResponse: Codable, Identifiable, Sendable {
    let startAddress: String?
    let plannedStartTime: String?
}`,
  WSNewOrder: `nonisolated struct WSNewOrder: Codable, Sendable {
    let startAddress: String?
    let plannedEndTime: String?
}`,
  VolunteerBadgeWall: `struct VolunteerBadgeWall: Decodable {
    let badges: [VolunteerBadge]
    let hasMore: Bool
}`,
};
const findTypeBody = (n) => REPO[n] ?? null;

// 旧判据的等价物，只用来证明「这条用例真的能骗过旧逻辑」。
// 没有它，两条回归用例读起来就只是普通的 missing 用例，看不出复现的是什么。
const oldGateWouldSayPresent = (field) =>
  Object.values(REPO).some((b) => new RegExp(`\\b${field}\\b`).test(b));

const statuses = (diff) =>
  parseAddedFields(diff).map((e) => ({ name: e.name, ...checkField(e, findTypeBody) }));

// ① 2026-08-2x：后端往 IntroCallView 加了三个字段，全被标成 ✅ ——
//    命中的是 OrderDetailResponse.startAddress / plannedStartTime 和 WSNewOrder.plannedEndTime。
const INTRO_CALL_DIFF = `diff --git a/Packages/AidRunAPI/Sources/AidRunAPI/Types.swift b/Packages/AidRunAPI/Sources/AidRunAPI/Types.swift
--- a/Packages/AidRunAPI/Sources/AidRunAPI/Types.swift
+++ b/Packages/AidRunAPI/Sources/AidRunAPI/Types.swift
@@ -5819,6 +5819,18 @@ public struct IntroCallView: Codable, Hashable, Sendable {
             /// - Remark: Generated from \`#/components/schemas/IntroCallView/windowEndsAt\`.
             public var windowEndsAt: Foundation.Date?
+            /// 起跑点文字地址。**双方角色都给**——它是「这一单的信息」不是「对方的信息」。
+            ///
+            /// - Remark: Generated from \`#/components/schemas/IntroCallView/startAddress\`.
+            public var startAddress: Swift.String?
+            /// 计划开始时间
+            ///
+            /// - Remark: Generated from \`#/components/schemas/IntroCallView/plannedStartTime\`.
+            public var plannedStartTime: Foundation.Date?
+            /// 计划结束时间
+            ///
+            /// - Remark: Generated from \`#/components/schemas/IntroCallView/plannedEndTime\`.
+            public var plannedEndTime: Foundation.Date?
             /// Creates a new \`IntroCallView\`.
`;

// ② 2026-08-29：GET /api/notifications/since 的响应**信封顶层**加了 hasMore，
//    被标成「手写模型已有」—— 命中的是成就墙的 VolunteerBadgeWall.hasMore，毫无关系。
//    信封字段的归属路径是 #/paths/...，压根不在任何 schema 上，没有「对应的手写模型」可查。
const ENVELOPE_DIFF = `--- a/Packages/AidRunAPI/Sources/AidRunAPI/Types.swift
+++ b/Packages/AidRunAPI/Sources/AidRunAPI/Types.swift
@@ -17150,6 +17150,8 @@ public struct jsonPayload: Codable, Hashable, Sendable {
                         /// - Remark: Generated from \`#/paths/api/notifications/since/GET/responses/200/content/json/code\`.
                         public var code: Swift.Int?
+                        /// - Remark: Generated from \`#/paths/api/notifications/since/GET/responses/200/content/json/hasMore\`.
+                        public var hasMore: Swift.Bool?
`;

const cases = [
  {
    name: '回归①：IntroCallView 的三个新字段不认 OrderDetailResponse / WSNewOrder 上的同名字段',
    run: () => statuses(INTRO_CALL_DIFF),
    check: (out) => {
      const notFooling = ['startAddress', 'plannedStartTime', 'plannedEndTime'].filter(
        (f) => !oldGateWouldSayPresent(f)
      );
      if (notFooling.length) return `用例失去意义：${notFooling} 在假仓库里根本搜不到，骗不过旧判据`;
      if (out.length !== 3) return `期望解析出 3 个字段，实得 ${JSON.stringify(out.map((o) => o.name))}`;
      const bad = out.filter((o) => o.status !== 'missing');
      return bad.length ? `期望三个都判 missing，实得 ${JSON.stringify(bad)}` : null;
    },
  },
  {
    name: '回归②：信封顶层 hasMore 判「无法判定」，不认 VolunteerBadgeWall.hasMore',
    run: () => statuses(ENVELOPE_DIFF),
    check: (out) => {
      if (!oldGateWouldSayPresent('hasMore')) return '用例失去意义：假仓库里搜不到 hasMore';
      if (out.length !== 1) return `期望恰好 1 个字段，实得 ${JSON.stringify(out)}`;
      const r = out[0];
      if (r.status !== 'manual') return `期望 manual，实得 ${r.status}（${r.detail}）`;
      return r.detail.includes('GET /api/notifications/since')
        ? null
        : `期望说清是哪个端点的信封，实得「${r.detail}」`;
    },
  },
  {
    name: '字段真的在对应模型上 → ✅（别把闸改成一律报红）',
    run: () =>
      statuses(`+            /// - Remark: Generated from \`#/components/schemas/IntroCallView/counterpartPhoneMasked\`.
+            public var counterpartPhoneMasked: Swift.String?
`),
    check: (out) =>
      out.length === 1 && out[0].status === 'present'
        ? null
        : `期望 present，实得 ${JSON.stringify(out)}`,
  },
  {
    name: '手写侧没有同名类型 → 无法判定，不是 ✅ 也不是 ❌',
    run: () =>
      statuses(`+            /// - Remark: Generated from \`#/components/schemas/EscortTrackSummary/startAddress\`.
+            public var startAddress: Swift.String?
`),
    check: (out) =>
      out.length === 1 && out[0].status === 'manual' && out[0].detail.includes('EscortTrackSummary')
        ? null
        : `期望 manual 且点名 EscortTrackSummary，实得 ${JSON.stringify(out)}`,
  },
  {
    name: 'Remark 末段与字段名对不上 → 不敢认这个归属，判无法判定',
    run: () =>
      statuses(`+            /// - Remark: Generated from \`#/components/schemas/IntroCallView/somethingElse\`.
+            public var counterpartPhoneMasked: Swift.String?
`),
    check: (out) =>
      out.length === 1 && out[0].status === 'manual'
        ? null
        : `期望 manual，实得 ${JSON.stringify(out)}`,
  },
  {
    name: '删除行不参与配对（-Remark 后面跟 +var 不算它的归属）',
    run: () =>
      parseAddedFields(`-            /// - Remark: Generated from \`#/components/schemas/IntroCallView/windowEndsAt\`.
+            public var windowEndsAt: Foundation.Date?
`),
    check: (out) =>
      out.length === 1 && out[0].ref === null ? null : `期望 ref 为 null，实得 ${JSON.stringify(out)}`,
  },
  {
    name: 'hunk 边界会清掉上一段的 Remark（跨 hunk 不配对）',
    run: () =>
      parseAddedFields(`             /// - Remark: Generated from \`#/components/schemas/IntroCallView/startAddress\`.
@@ -1,2 +1,2 @@
+            public var startAddress: Swift.String?
`),
    check: (out) =>
      out.length === 1 && out[0].ref === null ? null : `期望 ref 为 null，实得 ${JSON.stringify(out)}`,
  },
  {
    name: '纯注释同步解析不出字段',
    run: () =>
      parseAddedFields(`+            /// 起跑点文字地址。改了一句描述而已。
+            /// - Remark: Generated from \`#/components/schemas/IntroCallView/startAddress\`.
`),
    check: (out) => (out.length === 0 ? null : `期望无字段，实得 ${JSON.stringify(out)}`),
  },
  {
    name: '嵌套 payload 的归属仍落到顶层 schema，展示带上嵌套路径',
    run: () => ownerOfRef('#/components/schemas/IntroCallView/myDecision/value1'),
    check: (o) =>
      o.kind === 'schema' && o.schema === 'IntroCallView' && o.nested.join('.') === 'myDecision'
        ? null
        : `实得 ${JSON.stringify(o)}`,
  },
  {
    name: '信封路径能还原成端点与方法',
    run: () => ownerOfRef('#/paths/api/orders/{orderId}/intro-call/POST/responses/200/content/json/x'),
    check: (o) =>
      o.kind === 'envelope' && o.method === 'POST' && o.endpoint === '/api/orders/{orderId}/intro-call'
        ? null
        : `实得 ${JSON.stringify(o)}`,
  },
  {
    // 范围切割跑飞 = 把后面的类型也算进模型体，于是任何字段都能命中 —— 又一种假绿。
    // 用真仓库验：IntroCallView 与 IntroCallCopy 同文件，前者不该吃到后者。
    name: '真仓库：模型体切在自己的 `}` 上，不吃掉同文件的下一个类型',
    run: () => findHandwrittenType('IntroCallView'),
    check: (body) => {
      if (!body) return '取不到 IntroCallView 的手写模型体（改名了？那闸也该同步改）';
      if (!/counterpartPhoneMasked/.test(body)) return '模型体里缺自己的字段，范围切早了';
      if (/IntroCallCopy/.test(body)) return '模型体吃到了同文件的 IntroCallCopy，范围切晚了';
      return null;
    },
  },
];

let failed = 0;
for (const c of cases) {
  let err;
  try {
    err = c.check(c.run());
  } catch (e) {
    err = `抛异常：${e.message}`;
  }
  if (err) {
    console.error(`✗ ${c.name}\n  ${err}`);
    failed += 1;
  } else {
    console.log(`✓ ${c.name}`);
  }
}

if (failed) {
  console.error(`\n${failed} 条失败。`);
  process.exit(1);
}
console.log(`\n${cases.length} 条全部通过。`);
