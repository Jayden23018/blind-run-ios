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

const root = path.resolve(import.meta.dirname, '../..');

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

const dirty = dirtyPaths();
if (dirty.length) {
  todo.push(`**未提交**：${dirty.length} 个文件（${dirty.slice(0, 4).join('、')}${dirty.length > 4 ? ' …' : ''}）`);
}

const upstream = git('rev-parse', '--abbrev-ref', '@{u}');
if (upstream === null) {
  const branch = git('rev-parse', '--abbrev-ref', 'HEAD');
  todo.push(`**无 upstream**：\`${branch}\` 还没跟远端，push 要带 \`-u\``);
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
    handoffNote +
    archiveNote +
    '\n顺序固定：① 需要投递时先同步 handoff（`- [ ]` → `- [x]`，答写在 `答：` 后面，' +
    '并追加本轮产生的新问题）② commit（`type: 描述`，不带 co-author）③ push。\n' +
    '不是本轮产生的脏文件不要顺手提交 —— 说清楚哪些留着、为什么留着。\n' +
    '用户明确说过「先不提交」的，回一句说明再停 —— 本钩子每轮只拦一次，不会死循环。\n'
);
process.exit(2);
