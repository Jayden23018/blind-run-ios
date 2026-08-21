#!/usr/bin/env node

// Stop hook：拦住「改完就跑」。收尾三件事 —— handoff 打勾/提问 → commit → push。
//
// 存在理由：这三件事此前每轮都靠用户手动提醒，属于 AGENTS.md §1 里说的
// 「已经犯过第二次」。文档挡不住，所以落成钩子。
//
// 行为：有活没干完 → exit 2 + stderr（Claude Code 会把 stderr 回灌给模型，阻止本次停止）。
// 每轮只拦一次：第二次停止时 stop_hook_active === true，直接放行。
// 所以「用户说了先不提交」不会死循环 —— 说明一句再停即可。

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

import { researchTodo } from './research-log.mjs';
import { sessionEditedPaths } from './transcript.mjs';

// AIDRUN_REPO_ROOT 只给自测用（拿一个临时 git 仓库当靶子），生产路径永远走仓库根。
const root = process.env.AIDRUN_REPO_ROOT || path.resolve(import.meta.dirname, '../..');

function gitRaw(...args) {
  try {
    return execFileSync('git', args, {
      cwd: root,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    });
  } catch {
    return null; // null = 命令失败（如无 upstream），'' = 成功但空输出
  }
}

// 标量用（分支名、计数、时间戳）：可以放心 trim。
function git(...args) {
  const out = gitRaw(...args);
  return out === null ? null : out.trim();
}

// `git status --porcelain` 每行是 `XY<空格>路径`，前两位可能含前导空格（` M path`）。
// 不能对整段输出 trim —— 那会吃掉**第一行**的前导空格，让 slice(3) 多切一个字符，
// 提醒里就会出现 `lindRun/...` 这种不存在的路径。逐行取，按前 3 位切。
function dirtyPaths() {
  const out = gitRaw('status', '--porcelain');
  if (!out) return [];
  return out.split('\n').filter(Boolean).map((l) => l.slice(3));
}

const input = await new Promise((resolve) => {
  let buf = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (c) => (buf += c));
  process.stdin.on('end', () => resolve(buf));
  process.stdin.on('error', () => resolve(''));
});

let payload = {};
try {
  payload = JSON.parse(input || '{}');
} catch {
  payload = {};
}

// 已经拦过一次就放行，否则会无限循环。
if (payload.stop_hook_active) process.exit(0);

const todo = [];

// 调研落盘。放在最前面：它是「本轮做了但没留下痕迹」，比未提交更容易随会话一起消失。
const research = researchTodo(payload);
if (research) todo.push(research);

const sample = (ps) => `${ps.slice(0, 4).join('、')}${ps.length > 4 ? ' …' : ''}`;

// 脏文件不一定是本轮的：这个 checkout 可能被并行会话或同事同时在改。
// 只把本轮 Edit/Write 写过的算欠账，其余降级为提示 —— 2026-08-13 一次会话里
// 「未提交」列了 8 个本会话一个字节都没碰过的文件，那种提醒只会训练人忽略钩子。
// 拿不到 transcript（mine === null）时分不出来，保守全算欠账：宁可多拦，不要静默失效。
const dirty = dirtyPaths();
const mine = sessionEditedPaths(payload.transcript_path, root);
const ownDirty = mine === null ? dirty : dirty.filter((p) => mine.has(p));
const otherDirty = mine === null ? [] : dirty.filter((p) => !mine.has(p));
if (ownDirty.length) {
  todo.push(`**未提交**：${ownDirty.length} 个文件（${sample(ownDirty)}）`);
}

// `@{u}` 解析失败有两种成因，只有第一种是欠账：
//   ① 从没设过 upstream —— 真的没推过，该拦
//   ② 设过，但远端分支已经没了 —— 本仓库一律 squash 合并 + `--delete-branch`，
//      所以这是每个合完的分支的**终局状态**，不是欠账
// 分不出这两种，②就会每轮都被报成「还没跟远端」，而分支内容其实早在 main 里。
// 每轮都响的提醒会被无视 —— 这个钩子自己在下面就是这么写的，那条道理对它自己也成立。
function branchLandedOnMain(branch) {
  if (!branch || branch === 'HEAD') return false;
  // 配置还在 = upstream 曾经设过。从没推过的分支没有这两项，照常走欠账分支。
  if (git('config', `branch.${branch}.merge`) === null) return false;
  if (git('rev-parse', '--verify', '--quiet', 'origin/main') === null) return false;
  // 比内容，不比祖先：squash 之后 HEAD 的提交对象根本不在 main 的历史里，
  // `branch --merged` 和 `rev-list origin/main..HEAD` 一律把它判成「有独有提交」。
  // 两步缺一不可 —— 三点取「这个分支改过哪些文件」，两点比「那些文件在 main 上一不一样」。
  // 不限定文件的裸 `git diff origin/main..HEAD` 是双向差异，会把 main 领先的部分也算进来。
  const files = git('diff', '--name-only', 'origin/main...HEAD');
  if (files === null) return false;
  if (files === '') return true;
  return git('diff', 'origin/main..HEAD', '--', ...files.split('\n')) === '';
}

const upstream = git('rev-parse', '--abbrev-ref', '@{u}');
if (upstream === null) {
  const branch = git('rev-parse', '--abbrev-ref', 'HEAD');
  if (!branchLandedOnMain(branch)) {
    todo.push(`**无 upstream**：\`${branch}\` 还没跟远端，push 要带 \`-u\``);
  }
} else {
  const ahead = Number(git('rev-list', '--count', '@{u}..HEAD') || 0);
  if (ahead > 0) todo.push(`**未推送**：领先 \`${upstream}\` ${ahead} 个提交`);
}

// 没有欠账就放行。handoff 只在有欠账时**附带**提醒，不做独立触发条件 ——
// 纯客户端改动（UI 时序、测试 helper、本仓库自己的工具链）本来就不该投递 handoff，
// 拿「提交晚于 handoff」当触发条件会让每次工具类提交都误报，而天天误报的钩子等于没有钩子。
if (!todo.length) process.exit(0);

// 同一份欠账只叫一次。长期存在的脏文件（别人没写完的活）会让钩子每轮都响，
// 而每轮都响的提醒会被无视 —— 那等于把这个钩子废掉。欠账内容变了才重新叫。
// 签名落在 .git/ 里：天然不入库、天然每个 clone 独立。
// 上限：只比对「路径集合 + 领先数」，同一批文件内容再改也不会重新提醒。
const seenFile =
  process.env.AIDRUN_STOP_CHECKLIST_SEEN ||
  path.join(root, '.git', 'aidrun-stop-checklist-seen');
const signature = JSON.stringify(todo);
if (process.env.AIDRUN_STOP_CHECKLIST_NO_SNOOZE !== '1') {
  try {
    if (fs.readFileSync(seenFile, 'utf8') === signature) process.exit(0);
  } catch {
    // 没读到就当没提醒过
  }
  try {
    fs.writeFileSync(seenFile, signature);
  } catch {
    // 写不进去只影响去重，不该让钩子失效
  }
}

// 别人的脏文件只作提示，不作阻断条件（上面已经把它们排除在欠账外了）。
// 有欠账时才附带，没欠账时整个钩子已经放行 —— 提示不该单独把人拦下来。
let otherNote = '';
if (otherDirty.length) {
  otherNote =
    `\n参考：另有 ${otherDirty.length} 个脏文件不是本轮 Edit/Write 写的` +
    `（${sample(otherDirty)}）—— 多半是并行会话或同事在改，别顺手提交。\n`;
} else if (mine === null && dirty.length) {
  otherNote =
    '\n参考：拿不到本轮 transcript，上面的「未提交」里可能混着并行会话的改动，提交前自己认一眼。\n';
}

// handoff 是后端仓库的文件，前端 session 未必挂载了 —— 挂了才看。
const handoff =
  process.env.AIDRUN_HANDOFF || path.resolve(root, '../demo/docs/handoff.md');
let handoffNote = '';
if (fs.existsSync(handoff)) {
  const lastCommitAt = Number(git('log', '-1', '--format=%ct') || 0);
  const handoffAt = Math.floor(fs.statSync(handoff).mtimeMs / 1000);
  if (lastCommitAt > 0 && handoffAt < lastCommitAt) {
    handoffNote =
      '\n参考：`demo/docs/handoff.md` 比最后一次提交旧。本轮若动了契约用法、错误码语义、' +
      '字段依赖或新增端点调用，要同步过去；纯客户端改动不投递。\n';
  }
}

// 归档提问。AGENTS.md §1 的触发条件本来只有「犯过第二次」—— 于是第一次就卡了两小时、
// 试了六遍才对的东西没人管，下次换个人（或换个会话）从头再踩一遍。
// 「反复查」和「反复错」同等对待，「一次卡很久」也是同一类：代价已经付了，不落地就是白付。
//
// 每会话只问一次，且与欠账去重分开算：欠账在一轮里可能变好几次（提交了一半、又改了一个文件），
// 而这个问题问一次就够，跟着欠账重复问会变成噪声，那就等于废掉它。
// 拿不到 session_id 时照问 —— 宁可多问一次，也不要静默失效。
const askedFile =
  process.env.AIDRUN_STOP_ARCHIVE_ASKED ||
  path.join(root, '.git', 'aidrun-stop-archive-asked');
const sessionId = typeof payload.session_id === 'string' ? payload.session_id : '';
let archiveNote = '';
let alreadyAsked = false;
if (sessionId) {
  try {
    alreadyAsked = fs.readFileSync(askedFile, 'utf8') === sessionId;
  } catch {
    // 没读到就当没问过
  }
}
if (!alreadyAsked) {
  archiveNote =
    '\n本轮有没有「卡了很久」或「试了三次以上才对」的东西？有就**现在**按 §1 归档 ——\n' +
    'guard.mjs 守卫 / 测试 / Stop 钩子 / 项目记忆，四选一，只写文档不算。\n' +
    '第一次就付过的代价不落地，下个会话会从头再踩一遍。没有就跳过这条。\n';
  if (sessionId) {
    try {
      fs.writeFileSync(askedFile, sessionId);
    } catch {
      // 写不进去只影响去重，不该让钩子失效
    }
  }
}

process.stderr.write(
  `收尾没做完（scripts/hooks/stop-checklist.mjs）：\n- ${todo.join('\n- ')}\n` +
    otherNote +
    handoffNote +
    archiveNote +
    '\n顺序固定：① 需要投递时先同步 handoff（`- [ ]` → `- [x]`，答写在 `答：` 后面，' +
    '并追加本轮产生的新问题）② commit（`type: 描述`，不带 co-author）③ push。\n' +
    '用户明确说过「先不提交」的，回一句说明再停 —— 本钩子每轮只拦一次，不会死循环。\n'
);
process.exit(2);
