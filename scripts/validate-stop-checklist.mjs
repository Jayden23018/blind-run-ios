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

const scratches = [];

// 判据依赖 git 状态的两条用例拿临时仓库当靶子（AIDRUN_REPO_ROOT）。
// 在本仓库里造分支/脏文件太脏，且结论会随本仓库当时的状态漂移。
function scratchRepo() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'aidrun-stopcheck-repo-'));
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

// 一条 transcript：blocks 里每项是 {name, input}，会被包成 tool_use。
function writeTranscript(dir, name, blocks, startedAt) {
  const p = path.join(dir, name);
  const lines = blocks.map((b) =>
    JSON.stringify({
      timestamp: startedAt,
      message: { content: [{ type: 'tool_use', name: b.name, input: b.input }] },
    })
  );
  fs.writeFileSync(p, lines.join('\n') + '\n');
  return p;
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
    // 2026-08-13 真实误报：同一份调研已分 4 个提交推到单开的 docs 分支
    // （`origin/docs/demo-runbook-research`），当前 HEAD 与工作树自然查不到它，
    // 于是连报 4 次「本轮联网 N 次但 docs/research/ 没有任何改动」。
    // 误报的代价是钩子开始被习惯性无视 —— 那等于把它废掉。
    name: '调研提交在别的分支上时不许报「没落盘」',
    stdin: '{}',
    check: () => {
      const { dir, g } = scratchRepo();
      const base = g('rev-parse', '--abbrev-ref', 'HEAD').stdout.trim();
      g('checkout', '-qb', 'docs/x');
      fs.mkdirSync(path.join(dir, 'docs/research'), { recursive: true });
      fs.writeFileSync(path.join(dir, 'docs/research/INDEX.md'), '| 日期 | 问题 |\n');
      fs.writeFileSync(path.join(dir, 'docs/research/topic-20260813.md'), '# 调研\n');
      g('add', '-A');
      g('commit', '-qm', 'docs: 调研落盘');
      g('checkout', '-q', base); // 回到没有 docs/research 的分支，工作树干净
      const startedAt = new Date(Date.now() - 3600_000).toISOString();
      const transcript = writeTranscript(
        dir,
        'web.jsonl',
        [{ name: 'WebSearch', input: { query: 'x' } }],
        startedAt
      );
      const r = run(JSON.stringify({ transcript_path: transcript }), { AIDRUN_REPO_ROOT: dir });
      // 临时仓库必然「无 upstream」，钩子一定会拦 —— 拦不住说明这条根本没跑到判定。
      if (r.status !== 2) return `期望钩子被其他欠账拦住（exit 2），实得 ${r.status}`;
      return r.stderr.includes('调研没落盘')
        ? '调研已提交到别的分支，却仍在报「没落盘」'
        : null;
    },
  },
  {
    // 同一场景的另一半：并行会话正在改的脏文件被算成本轮欠账（那次列了 8 个没碰过的文件）。
    name: '不是本轮写的脏文件不算欠账，只作提示',
    stdin: '{}',
    check: () => {
      const { dir } = scratchRepo();
      fs.writeFileSync(path.join(dir, 'theirs.txt'), '并行会话在改\n');
      fs.writeFileSync(path.join(dir, 'mine.txt'), '本轮写的\n');
      const transcript = writeTranscript(
        dir,
        'edits.jsonl',
        [{ name: 'Edit', input: { file_path: path.join(dir, 'mine.txt') } }],
        new Date().toISOString()
      );
      const payload = JSON.stringify({ transcript_path: transcript });
      const r = run(payload, { AIDRUN_REPO_ROOT: dir });
      const line = r.stderr.split('\n').find((l) => l.includes('**未提交**'));
      if (!line) return '本轮确实写过 mine.txt，却没进欠账';
      if (!line.includes('mine.txt')) return `欠账里没有本轮写的文件：${line}`;
      if (line.includes('theirs.txt')) return `别人的脏文件被算进欠账：${line}`;
      if (!r.stderr.includes('theirs.txt')) return '别人的脏文件既没进欠账也没作提示，等于被吞掉';

      // 只剩别人的脏文件时，「未提交」这条欠账整条都不该出现。
      fs.rmSync(path.join(dir, 'mine.txt'));
      const cleaned = run(payload, { AIDRUN_REPO_ROOT: dir });
      return cleaned.stderr.includes('**未提交**')
        ? '本轮没写任何文件，却仍把别人的脏文件报成未提交'
        : null;
    },
  },
  {
    // 2026-08-21 真实误报：同一条「无 upstream」连报三轮。分支的 PR 早已 squash 合并、
    // 远端分支随 --delete-branch 删掉，于是 `@{u}` 解析不了 —— 但内容早在 main 里，不是欠账。
    // 本仓库一律 squash 合并，所以这是每个合完的分支的终局状态，会反复发生。
    name: 'upstream 曾设过、远端分支已删、内容已在 main → 不报「无 upstream」',
    stdin: '{}',
    check: () => {
      const { dir, g } = scratchRepo();
      g('update-ref', 'refs/remotes/origin/main', g('rev-parse', 'HEAD').stdout.trim());
      g('checkout', '-qb', 'claude/merged-and-deleted');
      // upstream 配置还在，但 refs/remotes/origin/<branch> 不存在 —— 正是 --delete-branch 之后的样子
      g('config', 'branch.claude/merged-and-deleted.remote', 'origin');
      g('config', 'branch.claude/merged-and-deleted.merge', 'refs/heads/claude/merged-and-deleted');
      const r = run('{}', { AIDRUN_REPO_ROOT: dir });
      return r.stderr.includes('无 upstream')
        ? '分支内容与 origin/main 完全一致，却仍报「无 upstream」'
        : null;
    },
  },
  {
    // 反例，防止上一条修过头把真欠账一起放过：内容没进 main 就还是欠账，必须照报。
    name: 'upstream 曾设过但内容没进 main → 仍要报「无 upstream」',
    stdin: '{}',
    check: () => {
      const { dir, g } = scratchRepo();
      g('update-ref', 'refs/remotes/origin/main', g('rev-parse', 'HEAD').stdout.trim());
      g('checkout', '-qb', 'feat/not-landed');
      g('config', 'branch.feat/not-landed.remote', 'origin');
      g('config', 'branch.feat/not-landed.merge', 'refs/heads/feat/not-landed');
      fs.writeFileSync(path.join(dir, 'new-work.txt'), '还没进 main 的活\n');
      g('add', '-A');
      g('commit', '-qm', 'feat: 尚未合并');
      const r = run('{}', { AIDRUN_REPO_ROOT: dir });
      return r.stderr.includes('无 upstream')
        ? null
        : '分支有 main 上没有的内容，却没报「无 upstream」—— 真欠账被放过了';
    },
  },
  {
    // 2026-09-23 真实误报：新开 worktree 的分支从没推过、也没有任何提交，
    // 本轮只改了仓库外的文件，却连报两次「push 要带 -u」。
    // 靶子让 HEAD 落后 origin/main 一个提交 —— worktree 从旧点切出来是常态，
    // 「比内容」的实现会把 main 领先的那部分当成本分支的改动而误报。
    name: '从没设过 upstream、也没有 origin/main 之外的提交 → 不报「无 upstream」',
    stdin: '{}',
    check: () => {
      const { dir, g } = scratchRepo();
      const seed = g('rev-parse', 'HEAD').stdout.trim();
      fs.writeFileSync(path.join(dir, 'main-moved-on.txt'), 'main 领先的提交\n');
      g('add', '-A');
      g('commit', '-qm', 'main 又往前走了一步');
      g('update-ref', 'refs/remotes/origin/main', g('rev-parse', 'HEAD').stdout.trim());
      g('checkout', '-qb', 'claude/fresh-worktree', seed);
      const r = run('{}', { AIDRUN_REPO_ROOT: dir });
      return r.stderr.includes('无 upstream')
        ? '分支上没有任何 origin/main 之外的提交，却仍报「无 upstream」'
        : null;
    },
  },
  {
    // 反例：同样从没设过 upstream，但有了自己的提交 —— 这是真欠账，必须照报。
    // 挡的是「没有 upstream 配置就一律放行」这种修过头的实现。
    name: '从没设过 upstream、有自己的提交 → 仍要报「无 upstream」',
    stdin: '{}',
    check: () => {
      const { dir, g } = scratchRepo();
      g('update-ref', 'refs/remotes/origin/main', g('rev-parse', 'HEAD').stdout.trim());
      g('checkout', '-qb', 'feat/never-pushed');
      fs.writeFileSync(path.join(dir, 'new-work.txt'), '从没推过的活\n');
      g('add', '-A');
      g('commit', '-qm', 'feat: 从没推过');
      const r = run('{}', { AIDRUN_REPO_ROOT: dir });
      return r.stderr.includes('无 upstream')
        ? null
        : '从没推过的分支有自己的提交，却没报「无 upstream」—— 真欠账被放过了';
    },
  },
  {
    // 2026-09-23 真实误报：分支已推完（HEAD == origin/feat/...），为了把分支腾给新 worktree
    // 故意 `checkout --detach`（AGENTS §10 教的正是这个），钩子报「`HEAD` 还没跟远端」。
    // 提交不在 main 上 —— 靶子要让「origin/main..HEAD 为 0」那条判据兜不住它。
    name: '游离 HEAD、提交已在某条远端分支上 → 不报「无 upstream」',
    stdin: '{}',
    check: () => {
      const { dir, g } = scratchRepo();
      g('update-ref', 'refs/remotes/origin/main', g('rev-parse', 'HEAD').stdout.trim());
      g('checkout', '-qb', 'feat/pushed');
      fs.writeFileSync(path.join(dir, 'pushed.txt'), '已推上去的活\n');
      g('add', '-A');
      g('commit', '-qm', 'feat: 已推送');
      g('update-ref', 'refs/remotes/origin/feat/pushed', g('rev-parse', 'HEAD').stdout.trim());
      g('checkout', '-q', '--detach');
      const r = run('{}', { AIDRUN_REPO_ROOT: dir });
      return r.stderr.includes('无 upstream')
        ? '游离 HEAD 的提交已在 origin/feat/pushed 上，却仍报「无 upstream」'
        : null;
    },
  },
  {
    // 反例：游离后又提交了一个 —— 它不在任何远端分支上，丢了就找不回来，必须照报。
    // 远端分支停在上一个提交：挡「有远端分支就放行」和「游离一律放行」两种修过头的实现。
    name: '游离 HEAD、有提交不在任何远端分支上 → 仍要报「无 upstream」',
    stdin: '{}',
    check: () => {
      const { dir, g } = scratchRepo();
      g('update-ref', 'refs/remotes/origin/main', g('rev-parse', 'HEAD').stdout.trim());
      g('checkout', '-qb', 'feat/pushed');
      fs.writeFileSync(path.join(dir, 'pushed.txt'), '已推上去的活\n');
      g('add', '-A');
      g('commit', '-qm', 'feat: 已推送');
      g('update-ref', 'refs/remotes/origin/feat/pushed', g('rev-parse', 'HEAD').stdout.trim());
      g('checkout', '-q', '--detach');
      fs.writeFileSync(path.join(dir, 'detached.txt'), '游离之后才写的\n');
      g('add', '-A');
      g('commit', '-qm', 'feat: 游离后的提交');
      const r = run('{}', { AIDRUN_REPO_ROOT: dir });
      return r.stderr.includes('无 upstream')
        ? null
        : '游离 HEAD 上有没推过的提交，却没报「无 upstream」—— 真欠账被放过了';
    },
  },
  {
    // workflow-review-20260924 A8：把三个特例收成「HEAD 可从任一远端分支到达」之后新覆盖的形状。
    // 旧实现三条特例都兜不住它（有 origin/main 之外的提交、没设过 upstream、不是游离 HEAD）。
    name: '推到了同名远端分支但没带 -u → 不报「无 upstream」',
    stdin: '{}',
    check: () => {
      const { dir, g } = scratchRepo();
      g('update-ref', 'refs/remotes/origin/main', g('rev-parse', 'HEAD').stdout.trim());
      g('checkout', '-qb', 'feat/pushed-no-u');
      fs.writeFileSync(path.join(dir, 'x.txt'), 'x\n');
      g('add', '-A');
      g('commit', '-qm', 'feat: 推了但没 -u');
      g('update-ref', 'refs/remotes/origin/feat/pushed-no-u', g('rev-parse', 'HEAD').stdout.trim());
      const r = run('{}', { AIDRUN_REPO_ROOT: dir });
      return r.stderr.includes('无 upstream')
        ? '提交已在 origin/feat/pushed-no-u 上，却仍报「无 upstream」'
        : null;
    },
  },
  {
    // workflow-review-20260924：worktree 里 `.git` 是个文件，旧实现拼 `.git/aidrun-stop-checklist-seen`
    // 写不进去（ENOTDIR 被吞掉），去重静默失效 —— 桌面 App 每个会话都是 worktree，于是每轮都叫。
    name: 'worktree 里同一份欠账也只叫一次（签名不能写到 .git/ 这个「文件」下面）',
    stdin: '{}',
    check: () => {
      const { dir, g } = scratchRepo();
      const wt = path.join(dir, 'wt');
      g('worktree', 'add', '-q', '-b', 'wt-branch', wt);
      fs.writeFileSync(path.join(wt, 'dirty.txt'), 'dirty\n');
      const env = { AIDRUN_REPO_ROOT: wt, AIDRUN_STOP_CHECKLIST_NO_SNOOZE: '0' };
      const first = run('{}', env);
      if (first.status !== 2) return `靶子没造出欠账（exit ${first.status}）`;
      const second = run('{}', env);
      return second.status === 0 ? null : `worktree 里同样的欠账第二次仍在拦（exit ${second.status}），去重没生效`;
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
  {
    // OpenSpec 闭环（2026-09-23）。四个靶子各自区分一种错误判据：
    //   done    —— 全打勾：必须报
    //   partial —— 有 [x] 也有 [ ]：「只看有没有 [x]」的实现会误报它
    //   empty   —— 一个勾都没有：「只看没有 [ ]」的实现会误报它
    //   archive/old —— 已归档：不看目录层级的实现会误报它
    name: 'OpenSpec：只有任务全打勾且未归档的变更才报「待归档」',
    stdin: '{}',
    check: () => {
      const { dir } = scratchRepo();
      const tasks = {
        'done': '- [x] 1.1 a\n- [X] 1.2 b\n',
        'partial': '- [x] 1.1 a\n- [ ] 1.2 b\n',
        'empty': '# Tasks\n',
        'archive/old': '- [x] 1.1 a\n',
      };
      for (const [name, text] of Object.entries(tasks)) {
        const d = path.join(dir, 'openspec/changes', name);
        fs.mkdirSync(d, { recursive: true });
        fs.writeFileSync(path.join(d, 'tasks.md'), text);
      }
      const r = run('{}', { AIDRUN_REPO_ROOT: dir });
      const line = r.stderr.split('\n').find((l) => l.includes('**待归档**'));
      if (!line) return '全打勾的 done 没被报成待归档';
      if (!line.includes('openspec archive done -y')) return `没给出归档命令：${line}`;
      const wrong = ['partial', 'empty', 'old'].filter((n) => line.includes(n));
      return wrong.length ? `不该报的也报了：${wrong.join('、')}` : null;
    },
  },
  {
    // 三个场景对应三条出路：只改源码 → 报；同时碰了变更 → 不报；只改测试 → 不报。
    name: 'OpenSpec：改了 App 源码却没碰 openspec/changes/ 才报「无变更记录」',
    stdin: '{}',
    check: () => {
      const { dir } = scratchRepo();
      // 目录要真的存在（realish 只解析目录，否则 /var 与 /private/var 对不上，路径被当成仓库外）。
      for (const d of ['blindRun/Feature', 'blindRunTests', 'openspec/changes/x']) {
        fs.mkdirSync(path.join(dir, d), { recursive: true });
      }
      const edits = (...files) =>
        run(
          JSON.stringify({
            transcript_path: writeTranscript(
              dir,
              `t-${files.length}-${files[0].replace(/\W/g, '')}.jsonl`,
              files.map((f) => ({ name: 'Edit', input: { file_path: path.join(dir, f) } })),
              new Date().toISOString()
            ),
          }),
          { AIDRUN_REPO_ROOT: dir }
        ).stderr.includes('**无变更记录**');
      if (!edits('blindRun/Feature/A.swift')) return '只改了 App 源码却没报';
      if (edits('blindRun/Feature/A.swift', 'openspec/changes/x/tasks.md')) return '已经碰了变更记录仍在报';
      if (edits('blindRunTests/ATests.swift')) return '只改测试也被报了';
      return null;
    },
  },
];

let failed = 0;
for (const c of cases) {
  let err;
  try {
    err = c.check(run(c.stdin));
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

for (const dir of scratches) fs.rmSync(dir, { recursive: true, force: true });

if (failed) {
  console.error(`\n${failed} 条失败。`);
  process.exit(1);
}
console.log(`\n${cases.length} 条全部通过。`);
