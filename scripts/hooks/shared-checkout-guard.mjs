#!/usr/bin/env node

// PreToolUse(Bash)：共享 checkout 里的 git 安全网。
//
// 存在理由（AGENTS.md §1.1）：这个仓库是**共享 checkout** —— 另一个人可能正在同一个
// 工作目录里编辑、提交、切分支（记忆 `shared-checkout-concurrent-colleague-edits`）。
// `.git` 整个是共用的：不只 index，**HEAD 也是共用的一份**。
//
// 2026-08-16 的事故走的是后一条，而且当时先按前一条误判过：
//
//   我提交完自己的分支 → **同事把 HEAD 切到他们自己的分支 `fix/api-client-missing-token-guard`
//   并提交了 dd0d795** → 我以为还在自己的分支上，跑了 `git commit --amend` 改提交信息，
//   把**同事那条提交**改成了我的 message → 又跑 `git reset --mixed` 把他们的分支
//   退回上一个提交，那条提交从分支上消失。
//
// 全程零报错。发现它靠的是事后手动核对 `git show --stat` 和 reflog，不是任何自动检查。
//
// 两条判据，对应两种失手方式：
//
//   ① rewrite-foreign-history —— 改写历史的命令（amend / reset / rebase / branch -f）
//      落在**本会话没切过、也没在上面提交过**的分支上。这是上面那次事故的直接判据。
//   ② implicit-staging —— 不带显式路径的暂存命令（add -A / commit -a / stash）
//      会捎带上本轮没碰过的文件。
//
// 两条都只在「确实会波及别人的东西」时才响：在自己开的分支上 amend、暂存区里全是自己写的
// 文件，都放行。**做成会误报的守卫等于把守卫废掉**，而且不会有任何东西提示它已经废了。
//
// 拿不到 transcript 时一律放行 —— 与 stop-checklist 同口径：与其每轮误报，不如少拦一次。
//
// 退出码 2 = 拦下并把 stderr 反馈给 Claude；0 = 放行。
// 任何内部异常一律放行（守卫本身不该成为阻塞源）。

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import { sessionEditedPaths, transcriptEntries } from './transcript.mjs';

function readStdin() {
  try {
    return fs.readFileSync(0, 'utf8');
  } catch {
    return '';
  }
}

const REPO = process.env.AIDRUN_REPO_ROOT || repoRoot();

function repoRoot() {
  const r = spawnSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8' });
  return r.status === 0 ? r.stdout.trim() : process.cwd();
}

function git(...args) {
  const r = spawnSync('git', args, { cwd: REPO, encoding: 'utf8' });
  if (r.status !== 0) return [];
  return r.stdout.split('\n').map((s) => s.trim()).filter(Boolean);
}

// 一条 shell 命令行拆成若干条子命令。`&&` / `;` / `|` / 换行都算分隔。
// 目的只是别让 `pwd && git commit --amend` 从正则缝里漏过去，不追求完整的 shell 解析。
function subCommands(command) {
  return command
    .split(/\n|;|\|\||&&|\||&/)
    .map((s) => s.trim())
    .filter(Boolean);
}

// 这条子命令会隐式暂存吗？返回 null = 不会；否则返回它会波及的文件集合的取法。
//
// 只认**不带显式路径**的形态。`git add path/to/file` 是本守卫鼓励的写法，永远放行。
function implicitStagingKind(cmd) {
  if (!/^git\s/.test(cmd)) return null;
  const args = cmd.split(/\s+/).slice(1);
  const sub = args.find((a) => !a.startsWith('-'));

  if (sub === 'commit') {
    // --amend 用当前 index 重建 tree：暂存区里有什么就带走什么。
    if (args.some((a) => a === '--amend')) return 'amend';
    // -a / -am 无差别暂存所有已跟踪的改动。
    if (args.some((a) => /^-[a-zA-Z]*a[a-zA-Z]*$/.test(a) || a === '--all')) return 'commit-all';
    return null;
  }

  if (sub === 'add') {
    const rest = args.slice(args.indexOf('add') + 1);
    if (rest.some((a) => a === '-A' || a === '--all' || a === '.' || a === ':/' || a === '-u')) {
      return 'add-all';
    }
    return null;
  }

  if (sub === 'stash') {
    // stash 会把同事未提交的改动一起卷走，而且现场没了更难发现。
    const rest = args.slice(args.indexOf('stash') + 1);
    const explicit = rest.some((a) => !a.startsWith('-') && a !== 'push' && a !== 'save');
    return explicit ? null : 'stash';
  }

  return null;
}

// 这条命令实际会碰到的仓库相对路径。
function affectedPaths(kind) {
  switch (kind) {
    case 'amend':
      return git('diff', '--cached', '--name-only');
    case 'commit-all':
      return [...new Set([...git('diff', '--cached', '--name-only'), ...git('diff', '--name-only')])];
    case 'add-all':
    case 'stash':
      return [
        ...new Set([
          ...git('diff', '--cached', '--name-only'),
          ...git('diff', '--name-only'),
          ...(kind === 'add-all' ? git('ls-files', '--others', '--exclude-standard') : []),
        ]),
      ];
    default:
      return [];
  }
}

// ── 判据 ①：这条命令会改写历史吗 ───────────────────────────────────────────
//
// 只认真的会移动分支指针 / 重写提交的那些。`git reset -- <path>`（取消暂存某文件）
// 不移动指针，放行。
function rewritesHistory(cmd) {
  if (!/^git\s/.test(cmd)) return null;
  const args = cmd.split(/\s+/).slice(1);
  const sub = args.find((a) => !a.startsWith('-'));

  if (sub === 'commit' && args.includes('--amend')) return 'amend';
  if (sub === 'rebase' && !args.includes('--abort') && !args.includes('--quit')) return 'rebase';
  if (sub === 'reset') {
    // `git reset -- <path>` / `git reset <path>` 只动 index。带 `--` 的一律当取消暂存。
    if (args.includes('--')) return null;
    return 'reset';
  }
  if (sub === 'branch' && args.some((a) => a === '-f' || a === '--force' || a === '-D')) {
    return 'branch-force';
  }
  return null;
}

// 本会话在 Bash 里跑过的所有命令文本。用来回答两个问题：
//   - 本会话切到过哪些分支（`checkout -b` / `checkout` / `switch`）
//   - HEAD 上那条提交的 message 是不是本会话自己写的
function sessionBashCommands(transcriptPath) {
  const entries = transcriptEntries(transcriptPath);
  if (entries === null) return null;
  const commands = [];
  for (const entry of entries) {
    const content = entry?.message?.content;
    if (!Array.isArray(content)) continue;
    for (const block of content) {
      if (block?.type !== 'tool_use' || block?.name !== 'Bash') continue;
      const c = block.input?.command;
      if (typeof c === 'string' && c.trim()) commands.push(c);
    }
  }
  return commands;
}

function sessionBranches(commands) {
  const names = new Set();
  for (const c of commands) {
    for (const m of c.matchAll(/git\s+(?:checkout|switch)\s+(?:-[a-zA-Z-]+\s+)*([^\s;&|]+)/g)) {
      const name = m[1];
      if (name && !name.startsWith('-')) names.add(name);
    }
  }
  return names;
}

// HEAD 这条提交是不是本会话做的 —— 用 subject 在本会话命令文本里找。
// 我们自己的 commit message 一定出现在某条 Bash 命令里（heredoc 或 -m）；
// 同事的不会。比对时间戳做不到这件事：同事的提交也落在本会话时间窗内。
function headCommitIsOurs(commands) {
  const r = spawnSync('git', ['log', '-1', '--format=%s'], { cwd: REPO, encoding: 'utf8' });
  if (r.status !== 0) return true; // 读不到就别拦
  const subject = r.stdout.trim();
  if (!subject) return true;
  return commands.some((c) => c.includes(subject));
}

const ADVICE = {
  amend:
    '要改上一条提交信息：先确认暂存区干净（`git diff --cached --name-only` 无输出）再 amend。\n' +
    '要往上一条提交补文件：`git add <显式路径>` 之后再 amend。',
  'commit-all': '改用 `git add <显式路径>` + `git commit`。',
  'add-all': '改用 `git add <显式路径>`。别人的文件不该由你决定何时进版本库。',
  stash: '改用 `git stash push -- <显式路径>`，或者干脆别 stash（同事的改动被卷走后现场就没了）。',
};

function main() {
  const raw = readStdin();
  if (!raw.trim()) process.exit(0);

  let payload;
  try {
    payload = JSON.parse(raw);
  } catch {
    process.exit(0);
  }

  if ((payload.tool_name || '') !== 'Bash') process.exit(0);
  const command = payload.tool_input?.command;
  if (typeof command !== 'string' || !command.trim()) process.exit(0);

  // 本轮自己写过的文件 / 跑过的命令。null = 读不到 transcript ⇒ 放行
  // （宁可漏拦，不要每轮误报）。
  const mine = sessionEditedPaths(payload.transcript_path, REPO);
  const commands = sessionBashCommands(payload.transcript_path);
  if (mine === null || commands === null) process.exit(0);

  // ── 判据 ①：改写历史前，先确认这条分支/提交是不是自己的 ──
  const branch = git('rev-parse', '--abbrev-ref', 'HEAD')[0] || '';
  const known = sessionBranches(commands);
  for (const cmd of subCommands(command)) {
    const kind = rewritesHistory(cmd);
    if (!kind) continue;
    if (known.has(branch) || headCommitIsOurs(commands)) continue;

    const head = git('log', '-1', '--format=%h %an: %s')[0] || '(读不到)';
    process.stderr.write(
      `[guard: rewrite-foreign-history] ${cmd}\n\n` +
        `当前分支是 \`${branch}\`，**本会话从没切到过它**，HEAD 上那条提交也不是本会话做的：\n` +
        `  ${head}\n\n` +
        `本仓库是共享 checkout —— \`.git/HEAD\` 是共用的，同事切分支、提交，你这边跟着就换了。\n` +
        `2026-08-16 一条 \`git commit --amend\` 就是这样把同事的提交改成了我的 message，\n` +
        `随后的 \`git reset\` 又把它从分支上抹掉，全程零报错。\n\n` +
        `先 \`git rev-parse --abbrev-ref HEAD\` 看清自己在哪，确认是自己的分支再改写历史。\n` +
        `如果这条提交确实该由你改写，先切回/新建你自己的分支。`
    );
    process.exit(2);
  }

  // ── 判据 ②：不带显式路径的暂存命令会不会捎带别人的文件 ──
  for (const cmd of subCommands(command)) {
    const kind = implicitStagingKind(cmd);
    if (!kind) continue;

    const foreign = affectedPaths(kind).filter((p) => !mine.has(p));
    if (foreign.length === 0) continue;

    process.stderr.write(
      `[guard: implicit-staging] ${cmd}\n\n` +
        `这条命令不带显式路径，会一并带走下面这些**本轮没有碰过**的文件：\n` +
        foreign.map((p) => `  - ${p}`).join('\n') +
        `\n\n本仓库是共享 checkout —— \`.git/index\` 是共用的，同事的 \`git add\` 会进你的暂存区。\n` +
        `2026-08-16 一笔编译不过的 WIP 就是这样被 \`--amend\` 吞进 PR 并推到远端的。\n\n` +
        `${ADVICE[kind]}\n\n` +
        `确认这些文件真的该由你提交，就显式写出它们的路径。`
    );
    process.exit(2);
  }

  process.exit(0);
}

try {
  main();
} catch (err) {
  process.stderr.write(`[guard: implicit-staging] 守卫内部异常，已放行：${err?.message || err}\n`);
  process.exit(0);
}
