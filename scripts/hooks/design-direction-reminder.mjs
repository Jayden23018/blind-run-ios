#!/usr/bin/env node
/**
 * PreToolUse（Edit|Write）：动 SwiftUI 视图之前，把设计流程灌回来。
 *
 * 立此钩子的理由（AGENTS.md §1）：`docs/ui/design-direction.md` 定下了双端视觉方向与四步流程，
 * 但**文档挡不住「忘了看」** —— 这正是第 1 节说的那种「只写文档不算完成」。
 * 官方两遍工作法里最容易被跳过的就是第 2 步（对着 brief 自审是不是默认值），
 * 因为跳过它不会报错、不会变红，只会让界面回到统计默认值。
 *
 * 三条约束让它不至于变成噪音：
 * 1. **每会话只响一次**（session_id 存 `.git/aidrun-design-reminder-seen`）；
 * 2. **只在真的动视图时响** —— 文件要在 `blindRun/` 下、是 `.swift`、且内容里有 `: View` /
 *    `some View`。改 Service、Model、测试都不响；
 * 3. **只灌要点不灌全文**（全文 230 行，每次灌进去等于劝人无视它）。
 *
 * 它是**非阻断**的：走 `hookSpecificOutput.additionalContext` + `exit(0)`，
 * 与 `research-log.mjs` 同一个机制。设计流程走没走没有机器判据 —— 拦不了，只能提醒。
 */

import fs from 'node:fs';
import path from 'node:path';

const root = process.env.CLAUDE_PROJECT_DIR || process.cwd();
const SEEN_FILE = path.join(root, '.git', 'aidrun-design-reminder-seen');

/** 视图文件判据。`content` 传空串时只按路径判（拿不到内容就不响，宁可漏不可吵）。 */
export function isSwiftUIViewEdit(tool, filePath, content) {
  if (tool !== 'Edit' && tool !== 'Write') return false;
  if (!filePath.endsWith('.swift')) return false;
  if (!/(^|\/)blindRun\//.test(filePath)) return false;
  if (/(^|\/)blindRun(Tests|UITests)\//.test(filePath)) return false;
  return /:\s*View\b|\bsome View\b/.test(content || '');
}

export const REMINDER = `【设计方向提醒 —— 本会话只提示这一次】

你正在改 SwiftUI 视图。动手前先走 \`docs/ui/design-direction.md\` 的四步，第 2 步最容易被跳过：

1. 出 design plan（色/字/布局/原则各一句话，色与字**直接引用 AppColors / AppFonts，不新造**）
2. **对着 design-direction.md 自审**：「这是不是我对任何同类页面都会产出的默认值？」
   是就改掉，并说清改了什么、为什么。跳过这步不会报错，只会让界面回到统计默认值。
3. 写代码
4. 截图自评：跑 \`scripts/device-test.sh\`，附件在 result bundle 旁的 \`attachments/\`。
   不要问「好不好看」，要问「差在哪」——
   \`take a screenshot of the result and compare it to the original. list differences and fix them\`
   ⚠️ 看图结论必须注明：UI 测试构建没有高德 key，地图恒为占位图，那**不是生产形态**。

最常被违反的四条（完整清单见文档 §7）：
- 两端**跟随系统明暗**，盲人端不强制深色；配色只用 \`AppColors\`，**不新增强调色**
- 不用 emoji 当图标（VoiceOver 会把 🎉 念成「派对拉炮」，且不随 Dynamic Type 缩放）
- 不只做 happy path —— 加载中 / 空 / 错误 / 禁用 / 离线都要交代；盲人端「点了没反应」就是事故
- 盲人端主按钮 ≥64pt，次级操作整行铺满竖直堆叠、绝不并排

志愿者端对标 Keep / 悦跑圈 / 咕咚，但**只抄**成长曲线、徽章分级、总结页排布；
**不抄**排行榜、社交流、成就抢播。安全相关界面（进行中 / SOS / 位置上报）在两端都退回最克制的一档。`;

function readStdin() {
  try {
    return fs.readFileSync(0, 'utf8');
  } catch {
    return '';
  }
}

function contentFor(tool, filePath, input) {
  // Write 新文件时磁盘上还没有它，只能看 content；Edit 一律以磁盘为准。
  if (tool === 'Write' && typeof input.content === 'string') return input.content;
  try {
    return fs.readFileSync(filePath, 'utf8');
  } catch {
    return '';
  }
}

function main() {
  const raw = readStdin();
  if (!raw.trim()) process.exit(0);

  let payload;
  try {
    payload = JSON.parse(raw);
  } catch {
    process.exit(0);
  }

  const tool = payload.tool_name || '';
  const input = payload.tool_input || {};
  const filePath = input.file_path || '';
  if (!filePath) process.exit(0);

  if (!isSwiftUIViewEdit(tool, filePath, contentFor(tool, filePath, input))) process.exit(0);

  // 每会话一次。拿不到 session_id 时**不提示** —— 与 stop-checklist 相反：
  // 那个是欠账（宁可多问），这个是提醒（多响一次就会被当噪音无视）。
  const sessionId = typeof payload.session_id === 'string' ? payload.session_id : '';
  if (!sessionId) process.exit(0);
  try {
    if (fs.readFileSync(SEEN_FILE, 'utf8') === sessionId) process.exit(0);
  } catch {
    /* 没有标记文件 = 本会话还没提醒过 */
  }
  try {
    fs.writeFileSync(SEEN_FILE, sessionId);
  } catch {
    /* .git 不可写就每次都提醒，好过静默失效 */
  }

  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: { hookEventName: 'PreToolUse', additionalContext: REMINDER },
    })
  );
  process.exit(0);
}

if (import.meta.url === `file://${process.argv[1]}`) main();
