// post 段的内容规则扫描：对改动后的生产 Swift 文件逐行跑规则表。
//
// 规则表按主题分在三个文件里，合并顺序就是扫描顺序（同一行命中多条时先报前面那条），别调换：
//   rules-copy.mjs   文案红线
//   rules-ui.mjs     界面与交互
//   rules-safety.mjs 数据、安全与状态机
//
// 每条规则的字段：`pattern`（逐行匹配）、可选的 `check(line, statement, src, before)`（二次判定）、
// 可选的 `files` / `exceptFiles`（路径闸）、`why`（拦下时给 Claude 的说明）。

import fs from 'node:fs';
import { COMMENT_LINE, fail } from './common.mjs';
import { copyRules } from './rules-copy.mjs';
import { safetyRules } from './rules-safety.mjs';
import { uiRules } from './rules-ui.mjs';

const rules = { ...copyRules, ...uiRules, ...safetyRules };

export function scanSwift(filePath) {
  let src;
  try {
    src = fs.readFileSync(filePath, 'utf8');
  } catch {
    return; // 文件可能已被删除或改名，不是守卫该管的事
  }

  const lines = src.split('\n');
  for (const [id, rule] of Object.entries(rules)) {
    // `files` 是可选的路径闸：多数内容规则对整个生产 target 生效，少数只在特定文件里成立
    // （某个字段在别处读是对的，只在某一屏读是错的）。不写这个字段就是全量，行为不变。
    if (rule.files && !rule.files.test(filePath)) continue;
    // `exceptFiles` 反过来：规则只在这些文件**以外**成立（例：求助状态只许在 coordinator 自己的文件里写）。
    if (rule.exceptFiles && rule.exceptFiles.test(filePath)) continue;
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      // 纯注释行跳过：守卫管的是出货代码。引用后端的坏文案来解释「为什么要覆盖它」
      // 恰恰是我们希望留在代码里的东西，不该被拦。判据与上面的 nonCommentLines 同源。
      if (COMMENT_LINE.test(line)) continue;
      // 标注可以写在同一行，也可以写在紧邻的上一行 —— Swift 经常把长字符串折到
      // 声明的下一行，强制同行标注会把标注挤成噪声。
      const marker = `guard:allow ${id}`;
      if (line.includes(marker) || (i > 0 && lines[i - 1].includes(marker))) continue;
      if (!rule.pattern.test(line)) continue;
      // check 拿得到后续几行：SwiftUI 经常把动画曲线折到 `.animation(` 的下一行，
      // 只看当前行会把已经做了降级的写法误判成违规。
      // 第三个实参是整份文件：少数规则要看「本文件声明过什么」才判得了（`emergency-state-write`）。
      // 第四个实参是**前向**窗口（本行之前的全部行）：`status-set-literal` 要判「这个字面量在不在一个 switch 块里」，
      // 而那个 `switch` 可能在 30 行以上的地方（迁移表逐态列完很长）。
      if (rule.check && !rule.check(line, lines.slice(i, i + 4).join('\n'), src, lines.slice(0, i))) continue;
      fail(id, `${filePath}:${i + 1}\n  ${line.trim()}\n\n${rule.why}`);
    }
  }
}
