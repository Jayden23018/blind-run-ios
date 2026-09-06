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
// 三条判据，对应三种失手方式：
//
//   ① rewrite-foreign-history —— 改写历史的命令（amend / reset / rebase / branch -f）
//      落在**本会话没切过、也没在上面提交过**的分支上。这是上面那次事故的直接判据。
//   ② implicit-staging —— 不带显式路径的暂存命令（add -A / commit -a / stash）
//      会捎带上本轮没碰过的文件。
//   ③ unguarded-checkout-chain —— `git checkout <被别的 worktree 占着的分支>` 后面用
//      `;` / 换行接了会改状态的 git 命令。**同一个仓库不能在两个 worktree 里检出同一条分支**，
//      所以那条 checkout 是**必然失败**的，而后面那条会照常执行、落在你**当前**这条分支上。
//
// 两条都只在「确实会波及别人的东西」时才响：在自己开的分支上 amend、暂存区里全是自己写的
// 文件，都放行。**做成会误报的守卫等于把守卫废掉**，而且不会有任何东西提示它已经废了。
//
// 拿不到 transcript 时一律放行 —— 与 stop-checklist 同口径：与其每轮误报，不如少拦一次。
//
// 2026-08-24 修两处误报（各实测一次）：
//
//   ⓐ 判据全部打在 `$CLAUDE_PROJECT_DIR` 上，不看命令实际作用于哪个仓库。于是在后端仓库
//      `../demo` 里跑 `git reset --keep` 被拦下，而文案里印的是 iOS 仓库的分支和提交。
//      现在按 `git -C <path>` / `cd <path> &&` / 钩子 payload 的 `cwd` 解析目标仓库，
//      **用那个仓库的 HEAD 和暂存区来判** —— 不是放行，后端仓库同样是共享 checkout。
//
//   ⓑ 判据 ① 的「本会话没切到过 + HEAD 提交不是本会话写的」在**跨会话继续同一条分支**时
//      恒为真，而那是本仓库最常见的干法（上个会话建分支，这个会话继承 HEAD 接着干）。
//      补一条豁免：**HEAD 在本会话开始之后没被移动过** —— 那就没人在你脚下换过 HEAD，
//      现在这条分支就是会话开始时看到的那条（SessionStart 钩子会把它印出来）。
//      事故那次 HEAD 是在会话中途被同事切走并提交的，reflog 上有痕迹，照样拦。
//
//      ⚠️ 不要改用「HEAD 作者 == `git config user.name`」当豁免：本仓库 200 条提交的
//      author 全是 `Jayden23018`，**包括事故里同事那条 dd0d795**。那条判据恒成立，
//      等于把判据 ① 整条废掉，而且没有任何东西会提示它已经废了。
//
// 退出码 2 = 拦下并把 stderr 反馈给 Claude；0 = 放行。
// 任何内部异常一律放行（守卫本身不该成为阻塞源）。

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { sessionEditedPaths, sessionStartedAt, transcriptEntries } from './transcript.mjs';

function readStdin() {
  try {
    return fs.readFileSync(0, 'utf8');
  } catch {
    return '';
  }
}

// 某个目录属于哪个 git 仓库。null = 不是仓库 / 路径不存在 ⇒ 调用方放行。
function repoRoot(dir) {
  if (!dir) return null;
  const r = spawnSync('git', ['-C', dir, 'rev-parse', '--show-toplevel'], { encoding: 'utf8' });
  return r.status === 0 && r.stdout.trim() ? r.stdout.trim() : null;
}

// 一律过一遍 `rev-parse`，路径口径才和下面解析出来的目标仓库一致
// （macOS 上 `/var/folders/...` 与 `/private/var/folders/...` 是同一个目录的两个名字）。
const REPO = repoRoot(process.env.AIDRUN_REPO_ROOT || process.cwd());

function git(repo, ...args) {
  const r = spawnSync('git', args, { cwd: repo, encoding: 'utf8' });
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

// `cd <path>` 之后的每一条子命令都换了工作目录。解析不出来（变量、通配、`cd -`、目录不存在）
// 就返回 null，后续子命令一律放行 —— 猜错目录会把判据打到另一个仓库上，正是 ⓐ 那个 bug。
// ponytail: 不做变量展开。真要绕过守卫，直接写 `git add -A` 也不会被拦到别处去。
function resolveCd(cmd, cwd) {
  const arg = cmd
    .replace(/^cd\s*/, '')
    .trim()
    .replace(/^(['"])(.*)\1$/, '$2');
  if (!arg || arg === '-' || /[$`*?]/.test(arg)) return null;
  const dir = path.resolve(cwd || '/', arg.replace(/^~(?=\/|$)/, os.homedir()));
  try {
    return fs.statSync(dir).isDirectory() ? dir : null;
  } catch {
    return null;
  }
}

// 剥掉 `git` 自己的全局选项，拆出 `-C <path>`（这条子命令的工作目录）和子命令及其参数。
//
// 两处都非剥不可：
//   - `-C <path>` / `-c k=v` 会吃掉一个值。不剥就会把那个值当成子命令 ——
//     `git -C /demo commit --amend` 的子命令会被认成 `/demo`，两条判据都不认得它。
//   - `-C` 只在**子命令之前**才是「切目录」。`git commit -C <ref> --amend` 里的 `-C`
//     是「复用那条提交的 message」，当成路径会解析失败 ⇒ 整条命令被放行。
function parseGit(cmd) {
  const tokens = cmd.split(/\s+/).slice(1);
  let at = null;
  let i = 0;
  while (i < tokens.length && tokens[i].startsWith('-')) {
    const t = tokens[i];
    if (t === '-C' || t === '-c') {
      if (t === '-C') at = tokens[i + 1];
      i += 2;
      continue;
    }
    if (t.startsWith('-C') && t.length > 2) at = t.slice(2);
    i += 1;
  }
  return { at, args: tokens.slice(i) };
}

// ── 判据 ③ 用到的两个 helper ──

// 会改仓库状态的子命令。`checkout` 失败之后它们会落在**当前**分支上，而不是你以为的那条。
// `status` / `log` / `diff` 这类只读的不在内：跑错分支只是看错，不产生后果。
const MUTATING_SUBCOMMANDS = new Set([
  'merge', 'rebase', 'reset', 'commit', 'cherry-pick', 'revert',
  'stash', 'push', 'am', 'apply', 'restore', 'switch',
]);

// 这条分支是不是被**别的** worktree 占着。占着 ⇒ 在本工作区 `git checkout <它>` 必然失败
// （git 自己报 `fatal: '<branch>' is already used by worktree at '<path>'`）。
// 返回占着它的那个 worktree 路径，没被占返回 null。
function heldByOtherWorktree(repo, branch, cwd) {
  let wt = null;
  for (const line of git(repo, 'worktree', 'list', '--porcelain')) {
    if (line.startsWith('worktree ')) wt = line.slice('worktree '.length).trim();
    else if (line.startsWith('branch ') && wt) {
      const held = line.slice('branch '.length).trim().replace(/^refs\/heads\//, '');
      if (held === branch && path.resolve(wt) !== path.resolve(cwd || '')) return wt;
    }
  }
  return null;
}

// 拆成 [子命令, 分隔符, 子命令, …]。`subCommands` 把分隔符扔了，而这条判据的全部信息
// 就在分隔符上：`&&` 是安全的（前一条失败就不会跑后一条），`;` / 换行不是。
function segmentsWithSeparators(command) {
  return command
    .split(/(\n|;|&&|\|\||\||&)/)
    .map((s) => s.trim())
    .filter((s, i) => s || i % 2 === 1);
}

// 这条子命令是不是「切到一条具名分支」。返回分支名，不是就返回 null。
//
// 刻意排掉的几种：`-b` / `-B` / `--orphan` 是**新建**（不会撞 worktree）；`--detach` detached
// 检出同一条提交是允许的；带 `--` 的是**恢复文件**不是切分支。
// 只认第一个非 flag 参数，且要求它是本仓库真实存在的本地分支 —— 拿路径当分支名会误报。
function checkoutBranch(cmd, repo) {
  const { args } = parseGit(cmd);
  if (args[0] !== 'checkout' && args[0] !== 'switch') return null;
  const rest = args.slice(1);
  if (rest.includes('--') || rest.some((a) => ['-b', '-B', '--orphan', '--detach', '-d'].includes(a))) {
    return null;
  }
  const name = rest.find((a) => !a.startsWith('-'));
  if (!name) return null;
  const exists = git(repo, 'rev-parse', '--verify', '--quiet', `refs/heads/${name}`);
  return exists.length ? name : null;
}

// 这条子命令是不是会改状态的 git 命令。
function mutatingGit(cmd) {
  if (!/^git(\s|$)/.test(cmd)) return null;
  const { args } = parseGit(cmd);
  return MUTATING_SUBCOMMANDS.has(args[0]) ? args[0] : null;
}

// 这条子命令实际作用于哪个仓库。null = 不是 git 命令 / 不在任何仓库里 ⇒ 放行。
// `git -C <path>` 只影响它自己那一条，不改后续子命令的工作目录。
function targetRepo(cmd, cwd) {
  if (!/^git(\s|$)/.test(cmd)) return null;
  let { at } = parseGit(cmd);
  if (!at) return repoRoot(cwd);
  at = at.replace(/^(['"])(.*)\1$/, '$2');
  if (/[$`*?]/.test(at)) return null;
  return repoRoot(path.resolve(cwd || '/', at.replace(/^~(?=\/|$)/, os.homedir())));
}

// 这条子命令会隐式暂存吗？返回 null = 不会；否则返回它会波及的文件集合的取法。
//
// 只认**不带显式路径**的形态。`git add path/to/file` 是本守卫鼓励的写法，永远放行。
function implicitStagingKind(cmd) {
  if (!/^git\s/.test(cmd)) return null;
  const { args } = parseGit(cmd);
  const sub = args[0];

  if (sub === 'commit') {
    // --amend 用当前 index 重建 tree：暂存区里有什么就带走什么。
    if (args.some((a) => a === '--amend')) return 'amend';
    // -a / -am 无差别暂存所有已跟踪的改动。
    if (args.some((a) => /^-[a-zA-Z]*a[a-zA-Z]*$/.test(a) || a === '--all')) return 'commit-all';
    return null;
  }

  if (sub === 'add') {
    const rest = args.slice(1);
    if (rest.some((a) => a === '-A' || a === '--all' || a === '.' || a === ':/' || a === '-u')) {
      return 'add-all';
    }
    return null;
  }

  if (sub === 'stash') {
    // stash 会把同事未提交的改动一起卷走，而且现场没了更难发现。
    const rest = args.slice(1);
    const explicit = rest.some((a) => !a.startsWith('-') && a !== 'push' && a !== 'save');
    return explicit ? null : 'stash';
  }

  return null;
}

// 这条命令实际会碰到的仓库相对路径。
function affectedPaths(repo, kind) {
  switch (kind) {
    case 'amend':
      return git(repo, 'diff', '--cached', '--name-only');
    case 'commit-all':
      return [
        ...new Set([
          ...git(repo, 'diff', '--cached', '--name-only'),
          ...git(repo, 'diff', '--name-only'),
        ]),
      ];
    case 'add-all':
    case 'stash':
      return [
        ...new Set([
          ...git(repo, 'diff', '--cached', '--name-only'),
          ...git(repo, 'diff', '--name-only'),
          ...(kind === 'add-all' ? git(repo, 'ls-files', '--others', '--exclude-standard') : []),
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
  const { args } = parseGit(cmd);
  const sub = args[0];

  if (sub === 'commit' && args.includes('--amend')) return 'amend';
  // rebase **进行中**的控制子命令一律放行：它们不是改写历史的入口 —— 要不要改写的决策在
  // `git rebase <base>` 那一步做过、也被本守卫判过一次了。而 rebase 进行中 HEAD 必然是
  // detached，三条判据（没切过这条分支 / HEAD 提交不是本会话写的 / HEAD 在会话开始后动过）
  // 恒同时成立 ⇒ 误报率 100%，还把「遇冲突 → 解完 → --continue」这条常规路径拦死
  // （2026-09-06 一天踩到 3 次，只能改用 merge 绕过）。
  // ⚠️ 只放行这几个具名的，别放宽成「带 -- 开头的参数就放行」：`git rebase --onto <base> ...`
  // 是不折不扣的改写入口。
  if (sub === 'rebase') {
    const inProgress = ['--abort', '--quit', '--continue', '--skip'];
    return args.some((a) => inProgress.includes(a)) ? null : 'rebase';
  }
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
function headCommitIsOurs(repo, commands) {
  const subject = git(repo, 'log', '-1', '--format=%s')[0];
  if (!subject) return true; // 读不到就别拦
  return commands.some((c) => c.includes(subject));
}

// HEAD 在本会话开始之后被移动过吗（切分支、提交、reset —— 谁干的都算）？
// 没动过 ⇒ 现在这条分支就是会话开始时继承的那条，没人在你脚下换过 HEAD ⇒ 判据 ① 放行。
// 事故那次同事是在会话中途切走 HEAD 并提交的，reflog 顶端因此落在会话开始之后 ⇒ 照样拦。
// 证不了「没动过」（没有 reflog、不知道会话何时开始）就返回 true，退回原判据。
function headMovedDuringSession(repo, startedAt) {
  const start = Date.parse(startedAt || '');
  if (!Number.isFinite(start)) return true;
  const entry = git(repo, 'reflog', 'show', '-1', '--date=unix', '--format=%gd')[0] || '';
  const at = entry.match(/\{(\d+)\}/);
  if (!at) return true;
  return Number(at[1]) * 1000 >= start;
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

  // 本轮跑过的命令。null = 读不到 transcript ⇒ 放行（宁可漏拦，不要每轮误报）。
  const commands = sessionBashCommands(payload.transcript_path);
  if (commands === null) process.exit(0);
  const startedAt = sessionStartedAt(payload.transcript_path);
  const known = sessionBranches(commands);

  // 起点是钩子拿到的工作目录（Bash 工具的 cwd 跨调用保留，可能早就不是仓库根了）。
  let cwd = typeof payload.cwd === 'string' && payload.cwd.trim() ? payload.cwd : REPO;

  // ── 判据 ③：注定失败的 checkout 后面跟着会改状态的命令，而分隔符不是 `&&` ──
  // 这条要在整串上判，不能进下面那个循环：全部信息都在**分隔符**上，而 `subCommands` 把它扔了。
  {
    const segs = segmentsWithSeparators(command);
    let dir = cwd;
    for (let i = 0; i < segs.length; i += 2) {
      const cmd = segs[i];
      if (/^cd(\s|$)/.test(cmd)) {
        dir = resolveCd(cmd, dir);
        continue;
      }
      const repo = targetRepo(cmd, dir);
      if (!repo) continue;
      const branch = checkoutBranch(cmd, repo);
      if (!branch) continue;
      const holder = heldByOtherWorktree(repo, branch, git(repo, 'rev-parse', '--show-toplevel')[0]);
      if (!holder) continue;
      // 往后找第一条会改状态的 git 命令；中间只要出现过一个 `&&` 就算安全（失败即短路）。
      for (let j = i + 1; j < segs.length; j += 2) {
        if (segs[j] === '&&') break;
        const next = segs[j + 1];
        const verb = next && mutatingGit(next);
        if (!verb) continue;
        process.stderr.write(
          `[guard: unguarded-checkout-chain] ${cmd}\n\n` +
            `分支 \`${branch}\` 正被另一个 worktree 检出：\n` +
            `  ${holder}\n\n` +
            `同一个仓库**不允许**两个 worktree 检出同一条分支，所以上面那条 checkout\n` +
            `**必然失败**（\`fatal: '${branch}' is already used by worktree at ...\`）。\n` +
            `而你用 \`${segs[i + 1] === '\\n' ? '换行' : segs[i + 1]}\` 而不是 \`&&\` 连接，后面这条会照常执行：\n\n` +
            `  ${next}\n\n` +
            `它会落在**你当前这条分支**上，不是 \`${branch}\`，而且不会有任何报错。\n` +
            `2026-09-06 一天里中了两次，\`git merge origin/main\` 分别落到了另外两个 PR 的分支上。\n` +
            `本仓库有 ${git(repo, 'worktree', 'list').length} 个 worktree —— checkout 失败是常态，不是意外。\n\n` +
            `两条出路，挑一条：\n` +
            `  · 用 \`&&\` 连接：\`git checkout ${branch} && ${verb} …\`（失败就短路，最省事）\n` +
            `  · 或者先腾开那个 worktree：\`git -C ${holder} checkout --detach\`\n` +
            `  · 或者干脆在那个 worktree 里做：\`git -C ${holder} ${verb} …\``
        );
        process.exit(2);
      }
    }
  }

  for (const cmd of subCommands(command)) {
    if (/^cd(\s|$)/.test(cmd)) {
      cwd = resolveCd(cmd, cwd);
      continue;
    }

    const repo = targetRepo(cmd, cwd);
    if (!repo) continue;
    const elsewhere = repo === REPO ? '' : `（目标仓库：${repo}）`;

    // ── 判据 ①：改写历史前，先确认这条分支/提交是不是自己的 ──
    if (rewritesHistory(cmd)) {
      const branch = git(repo, 'rev-parse', '--abbrev-ref', 'HEAD')[0] || '';
      if (
        !known.has(branch) &&
        !headCommitIsOurs(repo, commands) &&
        headMovedDuringSession(repo, startedAt)
      ) {
        const head = git(repo, 'log', '-1', '--format=%h %an: %s')[0] || '(读不到)';
        process.stderr.write(
          `[guard: rewrite-foreign-history] ${cmd}${elsewhere}\n\n` +
            `当前分支是 \`${branch}\`，**本会话从没切到过它**，HEAD 上那条提交也不是本会话做的，\n` +
            `而且 HEAD 在本会话开始之后被移动过（reflog）—— 三条同时成立：\n` +
            `  ${head}\n\n` +
            `这个仓库是共享 checkout —— \`.git/HEAD\` 是共用的，同事切分支、提交，你这边跟着就换了。\n` +
            `2026-08-16 一条 \`git commit --amend\` 就是这样把同事的提交改成了我的 message，\n` +
            `随后的 \`git reset\` 又把它从分支上抹掉，全程零报错。\n\n` +
            `先 \`git -C ${repo} reflog -5\` 看清 HEAD 这一路是谁在动，确认是自己的分支再改写历史。\n` +
            `如果这条提交确实该由你改写，先切回/新建你自己的分支。`
        );
        process.exit(2);
      }
    }

    // ── 判据 ②：不带显式路径的暂存命令会不会捎带别人的文件 ──
    const kind = implicitStagingKind(cmd);
    if (!kind) continue;

    // 本轮自己写过的文件，按**目标仓库**取相对路径 —— 换了仓库这份集合就不一样。
    const mine = sessionEditedPaths(payload.transcript_path, repo);
    if (mine === null) continue;

    const foreign = affectedPaths(repo, kind).filter((p) => !mine.has(p));
    if (foreign.length === 0) continue;

    process.stderr.write(
      `[guard: implicit-staging] ${cmd}${elsewhere}\n\n` +
        `这条命令不带显式路径，会一并带走下面这些**本轮没有碰过**的文件：\n` +
        foreign.map((p) => `  - ${p}`).join('\n') +
        `\n\n这个仓库是共享 checkout —— \`.git/index\` 是共用的，同事的 \`git add\` 会进你的暂存区。\n` +
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
