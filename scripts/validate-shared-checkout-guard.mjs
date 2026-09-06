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

// transcript：本轮用 Edit 写过 `edited` 里的路径（`dir` 相对），用 Bash 跑过 `ran` 里的命令。
//
// `startedAt` 默认落在**过去**，让靶子仓库的 reflog 一定比会话开始更新 ——
// 即「HEAD 在本会话期间被动过」，判据 ① 走原来那条严格分支。要测跨会话继承分支那条豁免，
// 显式传一个未来时刻（见 `FUTURE`）。
const FUTURE = new Date(Date.now() + 3_600_000).toISOString();

function writeTranscript(dir, { edited = [], ran = [], startedAt = '2026-08-16T00:00:00.000Z' } = {}) {
  const p = path.join(dir, 'transcript.jsonl');
  const blocks = [
    ...edited.map((rel) => ({ name: 'Edit', input: { file_path: path.resolve(dir, rel) } })),
    ...ran.map((cmd) => ({ name: 'Bash', input: { command: cmd } })),
  ];
  // 至少写一行：空文件会让 transcriptEntries 返回 []，与「读不到」这条放行分支混淆。
  if (blocks.length === 0) blocks.push({ name: 'Bash', input: { command: 'echo noop' } });
  fs.writeFileSync(
    p,
    blocks
      .map((b) =>
        JSON.stringify({
          timestamp: startedAt,
          message: { content: [{ type: 'tool_use', name: b.name, input: b.input }] },
        })
      )
      .join('\n') + '\n'
  );
  return p;
}

function run({ command, repo, transcriptPath, tool = 'Bash', cwd }) {
  return spawnSync('node', [hook], {
    input: JSON.stringify({
      tool_name: tool,
      tool_input: { command },
      transcript_path: transcriptPath,
      ...(cwd ? { cwd } : {}),
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

// 判据 ③ 的靶子：一条分支被**另一个** worktree 检出着，所以在主工作区
// `git checkout <它>` 必然失败。这是本仓库的日常状态（当时 19 个 worktree），不是构造出来的边角。
function heldBranchRepo() {
  const { dir, g } = scratchRepo();
  g('branch', 'feat/held-elsewhere');
  const wt = fs.mkdtempSync(path.join(os.tmpdir(), 'aidrun-sc-guard-wt-'));
  scratches.push(wt);
  // `worktree add <已存在目录>` 要 --force；用一个不存在的子路径更干净。
  g('worktree', 'add', '-q', path.join(wt, 'held'), 'feat/held-elsewhere');
  return { dir, g };
}

const OWN_SESSION = { edited: ['mine.txt'], ran: ['git checkout -b fix/my-own-work'] };

const FOREIGN_BRANCH = 'fix/api-client-missing-token-guard';
const OWN_BRANCH = 'fix/my-own-work';

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

  // ── ⓐ 命令作用于哪个仓库（2026-08-24 误报一）──
  //
  // 老实现把判据全打在 `$CLAUDE_PROJECT_DIR` 上：在后端仓库里跑 `git reset --keep` 被拦下，
  // 文案里印的却是 iOS 仓库的分支和提交。正反两例都要有 —— 后端仓库同样是共享 checkout，
  // 「非本仓库一律放行」是另一种把守卫废掉的方式。
  {
    name: '⭐ ⓐ 在另一个仓库里 `git reset --keep` 按那个仓库判：那边是本会话开的分支 → 放行（本仓库这边正停在同事分支上，不许据此误报）',
    build: () => {
      const { dir } = foreignBranchRepo(); // 本仓库：同事的分支 —— 老实现的误报来源
      const other = ownBranchRepo(); // 目标仓库：本会话自己开的分支
      return {
        command: `cd ${other.dir} && git reset --keep HEAD~1`,
        repo: dir,
        transcriptPath: writeTranscript(dir, OWN_SESSION),
      };
    },
    expect: ALLOWED,
  },
  {
    name: '⭐ ⓐ 反例：另一个仓库停在同事的分支上 → 照样拦，且文案印的是那个仓库的分支',
    build: () => {
      const { dir } = ownBranchRepo(); // 本仓库一切正常
      const other = foreignBranchRepo();
      return {
        command: `git -C ${other.dir} commit --amend -m x`,
        repo: dir,
        transcriptPath: writeTranscript(dir, OWN_SESSION),
        stderrIncludes: FOREIGN_BRANCH,
        stderrExcludes: OWN_BRANCH, // 印错仓库的分支名正是这次误报的表征
      };
    },
    expect: BLOCKED,
  },
  {
    name: '⭐ ⓐ `cd <另一仓库> && git add -A` 用那个仓库的暂存区判 → 拦，列的是那边的文件',
    build: () => {
      const { dir } = ownBranchRepo();
      const other = ownBranchRepo();
      fs.writeFileSync(path.join(other.dir, 'their-wip.txt'), 'wip\n');
      return {
        command: `cd ${other.dir} && git add -A`,
        repo: dir,
        transcriptPath: writeTranscript(dir, OWN_SESSION), // transcript 落在本仓库，别污染目标仓库的未跟踪列表
        stderrIncludes: 'their-wip.txt',
      };
    },
    expect: BLOCKED,
  },
  {
    name: '⭐ ⓐ 同上但那边的改动是本轮自己写的 → 放行（「本轮写过的文件」要按目标仓库取相对路径）',
    build: () => {
      const { dir } = ownBranchRepo();
      const other = ownBranchRepo();
      fs.writeFileSync(path.join(other.dir, 'my-other-repo-file.txt'), 'mine\n');
      return {
        command: `cd ${other.dir} && git add -A`,
        repo: dir,
        transcriptPath: writeTranscript(dir, {
          edited: [path.join(other.dir, 'my-other-repo-file.txt')],
          ran: OWN_SESSION.ran,
        }),
      };
    },
    expect: ALLOWED,
  },
  {
    name: 'ⓐ 钩子 payload 的 cwd 也算（Bash 的工作目录跨调用保留，可能早就不在本仓库了）',
    build: () => {
      const { dir } = ownBranchRepo();
      const other = ownBranchRepo();
      fs.writeFileSync(path.join(other.dir, 'their-wip.txt'), 'wip\n');
      return {
        command: 'git add -A',
        repo: dir,
        cwd: other.dir,
        transcriptPath: writeTranscript(dir, OWN_SESSION),
        stderrIncludes: 'their-wip.txt',
      };
    },
    expect: BLOCKED,
  },
  {
    name: 'ⓐ cd 的目标解析不出来（变量未展开）→ 放行，别猜目录（猜错就是把判据打到别的仓库上）',
    build: () => {
      const { dir } = ownBranchRepo();
      fs.writeFileSync(path.join(dir, 'colleague.txt'), 'wip\n');
      return {
        command: 'cd $BACKEND_REPO && git add -A',
        repo: dir,
        transcriptPath: writeTranscript(dir, OWN_SESSION),
      };
    },
    expect: ALLOWED,
  },
  {
    name: '⭐ ⓐ `git -C` 不许把子命令解析歪：`-C <path> commit --amend` 仍然要认出 amend',
    build: () => {
      const { dir } = ownBranchRepo();
      const other = ownBranchRepo();
      fs.writeFileSync(path.join(other.dir, 'their-wip.txt'), 'wip\n');
      other.g('add', 'their-wip.txt');
      return {
        command: `git -C ${other.dir} commit --amend -m x`,
        repo: dir,
        transcriptPath: writeTranscript(dir, OWN_SESSION),
        stderrIncludes: 'their-wip.txt',
      };
    },
    expect: BLOCKED,
  },
  {
    name: '⭐ ⓐ `git commit -C <ref> --amend` 里的 -C 是复用提交信息，不是路径 → 不许因此漏拦',
    build: () => {
      const { dir } = foreignBranchRepo();
      return {
        command: 'git commit -C HEAD --amend',
        repo: dir,
        transcriptPath: writeTranscript(dir, OWN_SESSION),
        stderrIncludes: 'rewrite-foreign-history',
      };
    },
    expect: BLOCKED,
  },

  // ── ⓑ 跨会话继续同一条分支（2026-08-24 误报二）──
  //
  // 「本会话没切到过 + HEAD 提交不是本会话写的」在跨会话继承分支时恒为真，而那是本仓库
  // 最常见的干法。豁免的判据是 **HEAD 在本会话开始之后有没有被移动过**（reflog），
  // 不是「HEAD 作者 == git config user.name」—— 本仓库全部提交的 author 都是同一个人，
  // 含 2026-08-16 事故里同事那条 dd0d795，那条判据恒成立，等于把判据 ① 整条废掉。
  //
  // 下面两条只差一个变量：会话开始时刻在 reflog 顶端之后（继承）还是之前（被人切走）。
  {
    name: '⭐ ⓑ 跨会话继承的分支：HEAD 在本会话期间没被动过 → 放行（合法 rebase 不许被拦）',
    build: () => {
      const { dir } = foreignBranchRepo(); // HEAD 那条提交是「上一个会话」做的
      return {
        command: 'git rebase origin/main',
        repo: dir,
        transcriptPath: writeTranscript(dir, { ran: ['git status'], startedAt: FUTURE }),
      };
    },
    expect: ALLOWED,
  },
  {
    name: '⭐ ⓑ 反例：同一条 rebase，但 HEAD 是在本会话开始之后被移动的（同事切走了）→ 拦',
    build: () => {
      const { dir } = foreignBranchRepo();
      return {
        command: 'git rebase origin/main',
        repo: dir,
        transcriptPath: writeTranscript(dir, { ran: ['git status'] }), // 会话开始时刻在过去
        stderrIncludes: 'rewrite-foreign-history',
      };
    },
    expect: BLOCKED,
  },

  // ── ⓒ rebase 进行中的控制子命令（2026-09-06 误报三）──
  //
  // rebase 一开跑 HEAD 就是 detached，三条判据恒同时成立 ⇒ `--continue` 100% 被拦，
  // 「遇冲突 → 解完继续」这条常规路径整个走不通（当天只能改用 merge 绕过）。
  // 下面两条正例用的都是「同事分支 + 会话开始时刻在过去」这个最严格的场景 ——
  // 判据 ① 在这里必然成立，所以放行只可能来自 rebase 自己的豁免。
  {
    name: '⭐ ⓒ `git rebase --continue` → 放行（决策在 `git rebase <base>` 那步已判过一次）',
    build: () => {
      const { dir } = foreignBranchRepo();
      return {
        command: 'git rebase --continue',
        repo: dir,
        transcriptPath: writeTranscript(dir, { ran: ['git status'] }),
      };
    },
    expect: ALLOWED,
  },
  {
    name: 'ⓒ `git rebase --skip` 同理 → 放行',
    build: () => {
      const { dir } = foreignBranchRepo();
      return {
        command: 'git rebase --skip',
        repo: dir,
        transcriptPath: writeTranscript(dir, { ran: ['git status'] }),
      };
    },
    expect: ALLOWED,
  },
  {
    name: '⭐ ⓒ 反向哨兵：`git rebase --onto <base> ...` 是改写入口 → 照样拦（豁免不许放宽成「带 -- 的就放行」）',
    build: () => {
      const { dir } = foreignBranchRepo();
      return {
        command: 'git rebase --onto origin/main HEAD~1',
        repo: dir,
        transcriptPath: writeTranscript(dir, { ran: ['git status'] }),
        stderrIncludes: 'rewrite-foreign-history',
      };
    },
    expect: BLOCKED,
  },

  {
    name: '⭐ ⓑ 豁免不许漏进判据 ②：继承来的分支上 `git add -A` 照样拦住同事的文件',
    build: () => {
      const { dir } = foreignBranchRepo();
      fs.writeFileSync(path.join(dir, 'their-wip.txt'), 'wip\n');
      return {
        command: 'git add -A',
        repo: dir,
        transcriptPath: writeTranscript(dir, { ran: ['git status'], startedAt: FUTURE }),
        stderrIncludes: 'their-wip.txt',
      };
    },
    expect: BLOCKED,
  },

  // ── 判据 ③：注定失败的 checkout 后面用 `;` 接了会改状态的命令 ──
  //
  // 2026-09-06 一天里中了两次：`git checkout <被 worktree 占着的分支>` 失败，
  // 紧跟的 `git merge origin/main` 照跑，落在**当前**分支上，零报错。
  // 本仓库当时有 19 个 worktree —— checkout 失败是常态而不是意外。
  {
    name: '⭐ ⓓ `git checkout <被别的 worktree 占着的分支>; git merge …` → 拦',
    build: () => {
      const { dir, g } = heldBranchRepo();
      return {
        command: 'git checkout feat/held-elsewhere\ngit merge origin/main --no-edit',
        repo: dir,
        transcriptPath: writeTranscript(dir, { ran: ['git status'] }),
        stderrIncludes: 'unguarded-checkout-chain',
      };
    },
    expect: BLOCKED,
  },
  {
    name: 'ⓓ 同上但用 `&&` 连接 → 放行（失败即短路，正是推荐写法）',
    build: () => {
      const { dir } = heldBranchRepo();
      return {
        command: 'git checkout feat/held-elsewhere && git merge origin/main --no-edit',
        repo: dir,
        transcriptPath: writeTranscript(dir, { ran: ['git status'] }),
      };
    },
    expect: ALLOWED,
  },
  {
    name: '⭐ ⓓ 反向哨兵：分支**没被**别的 worktree 占着时，`;` 接 merge 照样放行',
    build: () => {
      // 判据必须是「这条 checkout 会不会失败」，不是「有没有用 &&」——
      // 后者会把每一条 `git checkout x; git status` 都拦掉，守卫当天就会被无视。
      const { dir, g } = scratchRepo();
      g('branch', 'feat/free');
      return {
        command: 'git checkout feat/free\ngit merge origin/main --no-edit',
        repo: dir,
        transcriptPath: writeTranscript(dir, { ran: ['git status'] }),
      };
    },
    expect: ALLOWED,
  },
  {
    name: 'ⓓ 只读命令跟在后面 → 放行（跑错分支只是看错，不产生后果）',
    build: () => {
      const { dir } = heldBranchRepo();
      return {
        command: 'git checkout feat/held-elsewhere\ngit status -sb',
        repo: dir,
        transcriptPath: writeTranscript(dir, { ran: ['git status'] }),
      };
    },
    expect: ALLOWED,
  },
  {
    name: 'ⓓ `git checkout -b <占着的同名分支>` → 放行（新建不会撞 worktree，它会以别的方式失败）',
    build: () => {
      const { dir } = heldBranchRepo();
      return {
        command: 'git checkout -b feat/held-elsewhere\ngit commit -m x',
        repo: dir,
        transcriptPath: writeTranscript(dir, { ran: ['git status'] }),
      };
    },
    expect: ALLOWED,
  },
];

let failed = 0;
for (const c of cases) {
  // 靶子里现造的路径（另一个仓库、临时分支）只有 build() 知道，所以断言也允许它给。
  const built = c.raw ? null : c.build();
  const r = built ? run(built) : spawnSync('node', [hook], { input: c.raw, encoding: 'utf8' });
  const includes = built?.stderrIncludes ?? c.stderrIncludes;
  const excludes = built?.stderrExcludes ?? c.stderrExcludes;
  const problems = [];
  if (r.status !== c.expect) {
    problems.push(
      `期望 exit ${c.expect}，实得 ${r.status}；stderr=${JSON.stringify(r.stderr.slice(0, 300))}`
    );
  }
  if (includes && !r.stderr.includes(includes)) {
    problems.push(
      `stderr 里应出现 ${JSON.stringify(includes)}，实得 ${JSON.stringify(r.stderr.slice(0, 300))}`
    );
  }
  if (excludes && r.stderr.includes(excludes)) {
    problems.push(`stderr 里不该出现 ${JSON.stringify(excludes)}（印错了仓库）`);
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
