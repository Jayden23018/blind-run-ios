#!/usr/bin/env node
//
// scripts/hooks/stop-checklist.mjs 的回归测试。
//
// 为什么需要它：Stop 钩子靠 exit 2 阻止停止，靠 `stop_hook_active` 跳出循环。
// 那个跳出条件一旦坏掉，每次会话结束都会无限自我唤醒 —— 而且不会报错，只会看起来「卡住」。
// AGENTS.md §1.3 要求这类事落到机器归宿，这就是那个归宿。
//
// 只测与仓库状态无关的两条（脏树/未推送的判定是直白的 git 管道，且随仓库状态变化，
// 放进断言只会变成假失败）。

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const hook = path.resolve(import.meta.dirname, 'hooks/stop-checklist.mjs');

// 默认关掉「同样欠账只叫一次」的去重，否则第一条用例跑完就把签名写进 .git/，
// 后面的用例全部静默通过 —— 那是测试被自己的副作用架空。
function run(stdin, env = {}) {
  return spawnSync('node', [hook], {
    input: stdin,
    encoding: 'utf8',
    env: { ...process.env, AIDRUN_STOP_CHECKLIST_NO_SNOOZE: '1', ...env },
  });
}

const cases = [
  {
    name: 'stop_hook_active=true 必须静默放行（防无限循环）',
    stdin: '{"stop_hook_active":true}',
    check: (r) => (r.status === 0 && !r.stderr.trim() ? null : `期望 exit 0 且无 stderr，实得 exit ${r.status} / stderr ${JSON.stringify(r.stderr.slice(0, 80))}`),
  },
  {
    name: '非法 JSON 不许崩（崩了会被当成钩子故障，静默失效）',
    stdin: '{ 这不是 JSON',
    check: (r) => ([0, 2].includes(r.status) ? null : `期望 exit 0 或 2，实得 ${r.status}`),
  },
  {
    name: '空 stdin 不许崩',
    stdin: '',
    check: (r) => ([0, 2].includes(r.status) ? null : `期望 exit 0 或 2，实得 ${r.status}`),
  },
  {
    // 2026-08-06 真实回归：git() 对整段输出 trim，吃掉第一行 ` M path` 的前导空格，
    // slice(3) 于是多切一个字符，提醒里出现 `lindRun/...` 这种不存在的路径。
    // 仓库干净时本条自动跳过（拿不到样本），不会变成假失败。
    name: '「未提交」列出的路径必须与 git status 逐字一致（防首行被 trim 切掉一个字符）',
    stdin: '{}',
    check: (r) => {
      const line = r.stderr.split('\n').find((l) => l.includes('**未提交**'));
      if (!line) return null; // 工作树干净，无样本可验
      const listed = (line.match(/（(.+?)）/)?.[1] || '')
        .replace(/\s*…$/, '') // 超过 4 个时消息末尾会附 ' …'，不是路径的一部分
        .split('、')
        .map((s) => s.trim())
        .filter(Boolean);
      if (!listed.length) return '匹配到「未提交」行但没解析出任何路径';
      const raw = spawnSync('git', ['status', '--porcelain'], {
        cwd: path.resolve(import.meta.dirname, '..'),
        encoding: 'utf8',
      }).stdout.split('\n').filter(Boolean);
      // 每个列出的路径都必须是某一行的精确后缀；被切掉首字符时这一条就不成立。
      const bad = listed.filter((p) => !raw.some((l) => l.endsWith(p) && l.length - p.length === 3));
      return bad.length ? `这些路径与 git status 对不上（疑似被切字符）：${bad.join('、')}` : null;
    },
  },
  {
    // 长期存在的脏文件（别人没写完的活）不该每轮都叫 —— 每轮都响的提醒会被无视。
    // 用临时签名文件跑，别污染 .git/ 里那份真的。
    name: '同一份欠账只叫一次，欠账内容变了才重新叫',
    stdin: '{}',
    check: () => {
      const seen = path.join(
        fs.mkdtempSync(path.join(os.tmpdir(), 'aidrun-stopcheck-')),
        'seen'
      );
      const env = { AIDRUN_STOP_CHECKLIST_NO_SNOOZE: '0', AIDRUN_STOP_CHECKLIST_SEEN: seen };
      const first = run('{}', env);
      if (first.status === 0) return null; // 工作树干净且已推送，无样本可验
      const second = run('{}', env);
      if (second.status !== 0 || second.stderr.trim()) {
        return `同样的欠账第二次仍在拦（exit ${second.status}），去重没生效`;
      }
      // 欠账变了必须重新叫：改掉签名模拟「又多了一个未提交文件」
      fs.writeFileSync(seen, '["**未提交**：另一批完全不同的欠账"]');
      const third = run('{}', env);
      return third.status === 2 ? null : `欠账变了却没重新提醒（exit ${third.status}）`;
    },
  },
  {
    // 归档提问必须每会话只问一次：跟着欠账重复问就成了噪声，而噪声等于废掉它。
    // 但换了会话必须重新问 —— 新会话的「卡很久」是新的账。
    name: '归档提问每会话一次，换会话重新问',
    stdin: '{}',
    check: () => {
      const asked = path.join(
        fs.mkdtempSync(path.join(os.tmpdir(), 'aidrun-archive-')),
        'asked'
      );
      const env = { AIDRUN_STOP_ARCHIVE_ASKED: asked };
      const has = (r) => r.stderr.includes('试了三次以上才对');
      const first = run('{"session_id":"s-1"}', env);
      if (first.status === 0) return null; // 无欠账，钩子提前放行，没有样本可验
      if (!has(first)) return '有欠账时第一次没问归档';
      if (has(run('{"session_id":"s-1"}', env))) return '同一会话第二次仍在问，去重没生效';
      return has(run('{"session_id":"s-2"}', env)) ? null : '换了会话却没重新问';
    },
  },
  {
    // 拿不到 session_id 时宁可多问一次，也不要静默不问 —— 静默失效是这类提醒最常见的死法。
    name: '没有 session_id 时照问（不静默失效）',
    stdin: '{}',
    check: (r) =>
      r.status === 0 || r.stderr.includes('试了三次以上才对')
        ? null
        : '缺 session_id 时没问归档',
  },
];

let failed = 0;
for (const c of cases) {
  const err = c.check(run(c.stdin));
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
