#!/usr/bin/env node
//
// scripts/hooks/shared-checkout-guard.mjs 的回归测试。
//
// 为什么需要它：这个守卫的价值全在「判据准不准」上。太松放过真事故
// （2026-08-16 那条 `--amend` 改掉了同事的提交、`reset` 又把它抹掉），
// 太紧就每次 amend 都报一次然后被习惯性无视 —— 后者等于把守卫废掉，
// 而且不会有任何东西提示它已经废了。
//
// 靶子用临时 git 仓库（AIDRUN_REPO_ROOT），不碰本仓库：在本仓库里造脏文件既脏，
// 结论也会随当时的仓库状态漂移成假失败。

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const hook = path.resolve(import.meta.dirname, 'hooks/shared-checkout-guard.mjs');
const scratches = [];

function scratchRepo() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'aidrun-sc-guard-'));
  scratches.push(dir);
  const g = (...args) =>
    spawnSync(
      'git',
      ['-c', 'user.email=t@t', '-c', 'user.name=t', '-c', 'commit.gpgsign=false', ...args],
      { cwd: dir, encoding: 'utf8' }
    );
  g('init', '-q');
  fs.writeFileSync(path.join(dir, 'seed.txt'), 'seed\n');
  g('add', '-A');
  g('commit', '-qm', 'seed');
  return { dir, g };
}

// transcript：本轮用 Edit 写过 `edited` 里的路径，用 Bash 跑过 `ran` 里的命令。
function writeTranscript(dir, { edited = [], ran = [] } = {}) {
  const p = path.join(dir, 'transcript.jsonl');
  const blocks = [
    ...edited.map((rel) => ({ name: 'Edit', input: { file_path: path.join(dir, rel) } })),
    ...ran.map((cmd) => ({ name: 'Bash', input: { command: cmd } })),
  ];
  // 至少写一行：空文件会让 transcriptEntries 返回 []，与「读不到」这条放行分支混淆。
  if (blocks.length === 0) blocks.push({ name: 'Bash', input: { command: 'echo noop' } });
  fs.writeFileSync(
    p,
    blocks
      .map((b) =>
        JSON.stringify({
          timestamp: '2026-08-16T00:00:00.000Z',
          message: { content: [{ type: 'tool_use', name: b.name, input: b.input }] },
        })
      )
      .join('\n') + '\n'
  );
  return p;
}

function run({ command, repo, transcriptPath, tool = 'Bash' }) {
  return spawnSync('node', [hook], {
    input: JSON.stringify({
      tool_name: tool,
      tool_input: { command },
      transcript_path: transcriptPath,
    }),
    encoding: 'utf8',
    env: { ...process.env, AIDRUN_REPO_ROOT: repo },
  });
}

const BLOCKED = 2;
const ALLOWED = 0;

// 同事那条分支的场景：本会话从没切过它，HEAD 上是别人的提交。
function foreignBranchRepo() {
  const { dir, g } = scratchRepo();
  g('checkout', '-qb', 'fix/api-client-missing-token-guard');
  fs.writeFileSync(path.join(dir, 'colleague.txt'), 'wip\n');
  g('add', 'colleague.txt');
  g('commit', '-qm', 'fix: 没有 Token 时不要发请求');
  return { dir, g };
}

// 自己的分支：本会话 checkout -b 开的，HEAD 是自己的提交。
function ownBranchRepo() {
  const { dir, g } = scratchRepo();
  g('checkout', '-qb', 'fix/my-own-work');
  fs.writeFileSync(path.join(dir, 'mine.txt'), 'mine\n');
  g('add', 'mine.txt');
  g('commit', '-qm', 'fix: 我自己的提交');
  return { dir, g };
}

const OWN_SESSION = { edited: ['mine.txt'], ran: ['git checkout -b fix/my-own-work'] };

const cases = [
  // ── 基础 ──
  {
    name: '非 Bash 工具一律放行',
    build: () => {
      const { dir } = scratchRepo();
      return {
        command: 'git commit --amend',
        repo: dir,
        transcriptPath: writeTranscript(dir),
        tool: 'Edit',
      };
    },
    expect: ALLOWED,
  },
  {
    name: '非法 JSON 不许崩（崩了会被当成钩子故障，静默失效）',
    raw: '{ 这不是 JSON',
    expect: ALLOWED,
  },
  {
    name: '拿不到 transcript 时放行（宁可漏拦，不要每轮误报）',
    build: () => {
      const { dir, g } = scratchRepo();
      fs.writeFileSync(path.join(dir, 'colleague.txt'), 'wip\n');
      g('add', 'colleague.txt');
      return { command: 'git commit --amend', repo: dir, transcriptPath: '' };
    },
    expect: ALLOWED,
  },

  // ── 判据 ①：改写别人的历史（2026-08-16 事故本体）──
  {
    name: '⭐ 事故复现：amend 落在本会话没切过、HEAD 也不是本会话提交的分支上 → 拦',
    build: () => {
      const { dir } = foreignBranchRepo();
      return {
        command: 'git commit --amend -m x',
        repo: dir,
        transcriptPath: writeTranscript(dir, OWN_SESSION),
      };
    },
    expect: BLOCKED,
    stderrIncludes: 'rewrite-foreign-history',
  },
  {
    name: '⭐ 同一场景下 reset 同样要拦（事故的第二步，它才是真正抹掉提交的那一下）',
    build: () => {
      const { dir } = foreignBranchRepo();
      return {
        command: 'git reset --mixed HEAD~1',
        repo: dir,
        transcriptPath: writeTranscript(dir, OWN_SESSION),
      };
    },
    expect: BLOCKED,
  },
  {
    name: 'rebase 与 branch -f 同属改写历史 → 拦',
    build: () => {
      const { dir } = foreignBranchRepo();
      return {
        command: 'git branch -f fix/api-client-missing-token-guard HEAD~1',
        repo: dir,
        transcriptPath: writeTranscript(dir, OWN_SESSION),
      };
    },
    expect: BLOCKED,
  },
  {
    name: '在本会话自己开的分支上 amend → 放行（日常操作，拦了就成噪音）',
    build: () => {
      const { dir } = ownBranchRepo();
      return {
        command: 'git commit --amend -m x',
        repo: dir,
        transcriptPath: writeTranscript(dir, OWN_SESSION),
      };
    },
    expect: ALLOWED,
  },
  {
    name: '分支没切过但 HEAD 提交是本会话写的 → 放行（会话开始时就在这个分支上）',
    build: () => {
      const { dir, g } = scratchRepo();
      g('checkout', '-qb', 'some/preexisting-branch');
      fs.writeFileSync(path.join(dir, 'mine.txt'), 'mine\n');
      g('add', 'mine.txt');
      g('commit', '-qm', 'fix: 我自己的提交');
      return {
        command: 'git commit --amend -m x',
        repo: dir,
        transcriptPath: writeTranscript(dir, {
          edited: ['mine.txt'],
          ran: ['git commit -m "fix: 我自己的提交"'],
        }),
      };
    },
    expect: ALLOWED,
  },
  {
    name: 'git reset -- <path>（只取消暂存，不移动指针）→ 放行',
    build: () => {
      const { dir } = foreignBranchRepo();
      return {
        command: 'git reset -- colleague.txt',
        repo: dir,
        transcriptPath: writeTranscript(dir, OWN_SESSION),
      };
    },
    expect: ALLOWED,
  },

  // ── 判据 ②：隐式暂存 ──
  {
    name: 'amend 会吞掉本轮没碰过的已暂存文件 → 拦',
    build: () => {
      const { dir, g } = ownBranchRepo();
      fs.writeFileSync(path.join(dir, 'colleague.txt'), 'wip\n');
      g('add', 'colleague.txt');
      return {
        command: 'git commit --amend -m x',
        repo: dir,
        transcriptPath: writeTranscript(dir, OWN_SESSION),
      };
    },
    expect: BLOCKED,
    stderrIncludes: 'colleague.txt',
  },
  {
    name: 'amend 且暂存区全是本轮自己写的 → 放行',
    build: () => {
      const { dir, g } = ownBranchRepo();
      fs.writeFileSync(path.join(dir, 'mine.txt'), 'mine v2\n');
      g('add', 'mine.txt');
      return {
        command: 'git commit --amend -m x',
        repo: dir,
        transcriptPath: writeTranscript(dir, OWN_SESSION),
      };
    },
    expect: ALLOWED,
  },
  {
    name: 'git add -A 会捎上别人的文件 → 拦',
    build: () => {
      const { dir } = ownBranchRepo();
      fs.writeFileSync(path.join(dir, 'colleague.txt'), 'wip\n');
      return {
        command: 'git add -A',
        repo: dir,
        transcriptPath: writeTranscript(dir, OWN_SESSION),
      };
    },
    expect: BLOCKED,
    stderrIncludes: 'colleague.txt',
  },
  {
    name: 'git add <显式路径> 永远放行 —— 这正是守卫推荐的写法',
    build: () => {
      const { dir } = ownBranchRepo();
      fs.writeFileSync(path.join(dir, 'colleague.txt'), 'wip\n');
      return {
        command: 'git add colleague.txt',
        repo: dir,
        transcriptPath: writeTranscript(dir, OWN_SESSION),
      };
    },
    expect: ALLOWED,
  },
  {
    name: 'git commit -am 无差别暂存 → 拦',
    build: () => {
      const { dir } = ownBranchRepo();
      fs.writeFileSync(path.join(dir, 'seed.txt'), 'changed by colleague\n');
      return {
        command: 'git commit -am "x"',
        repo: dir,
        transcriptPath: writeTranscript(dir, OWN_SESSION),
      };
    },
    expect: BLOCKED,
    stderrIncludes: 'seed.txt',
  },
  {
    name: '裸 git stash 会把同事的改动卷走 → 拦',
    build: () => {
      const { dir } = ownBranchRepo();
      fs.writeFileSync(path.join(dir, 'seed.txt'), 'changed by colleague\n');
      return {
        command: 'git stash',
        repo: dir,
        transcriptPath: writeTranscript(dir, OWN_SESSION),
      };
    },
    expect: BLOCKED,
  },
  {
    name: '⭐ 串联命令里的危险项不许从缝里漏过去',
    build: () => {
      const { dir } = ownBranchRepo();
      fs.writeFileSync(path.join(dir, 'colleague.txt'), 'wip\n');
      return {
        command: 'echo hi && git add -A',
        repo: dir,
        transcriptPath: writeTranscript(dir, OWN_SESSION),
      };
    },
    expect: BLOCKED,
  },
  {
    name: '不含 git 的普通命令放行',
    build: () => {
      const { dir } = ownBranchRepo();
      fs.writeFileSync(path.join(dir, 'colleague.txt'), 'wip\n');
      return {
        command: 'ls -la && node scripts/validate-docs.mjs',
        repo: dir,
        transcriptPath: writeTranscript(dir, OWN_SESSION),
      };
    },
    expect: ALLOWED,
  },
];

let failed = 0;
for (const c of cases) {
  const r = c.raw ? spawnSync('node', [hook], { input: c.raw, encoding: 'utf8' }) : run(c.build());
  const problems = [];
  if (r.status !== c.expect) {
    problems.push(
      `期望 exit ${c.expect}，实得 ${r.status}；stderr=${JSON.stringify(r.stderr.slice(0, 300))}`
    );
  }
  if (c.stderrIncludes && !r.stderr.includes(c.stderrIncludes)) {
    problems.push(
      `stderr 里应出现 ${JSON.stringify(c.stderrIncludes)}，实得 ${JSON.stringify(r.stderr.slice(0, 300))}`
    );
  }
  if (problems.length) {
    failed += 1;
    console.error(`✗ ${c.name}\n    ${problems.join('\n    ')}`);
  }
}

for (const d of scratches) fs.rmSync(d, { recursive: true, force: true });

if (failed) {
  console.error(`[validate-shared-checkout-guard] ${failed} / ${cases.length} 条失败`);
  process.exit(1);
}
console.log(`[validate-shared-checkout-guard] ${cases.length} 条守卫用例全部通过`);
