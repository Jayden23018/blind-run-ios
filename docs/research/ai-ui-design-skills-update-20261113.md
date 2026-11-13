# 「去 AI 味」与「让 AI 设计更好看」的 skill 和方法：09-07 之后的增量（2026-11-13）

> Notion 版：https://app.notion.com/p/417dd43bda7d813cac7ff823f84156a6

> 本轮只补 [ai-ui-design-workflow-for-swiftui-20260907.md](./ai-ui-design-workflow-for-swiftui-20260907.md) 之后的新东西。
> 那份的结论（两遍工作法、截图自评、iOS 版指纹清单要自己写、三个缺口）**本轮没有被推翻**，照旧用。
> 仓库数据全部是 2026-11-13 用 `gh api repos/<owner>/<repo>` 实测；评价来自 HN Algolia API 的原始评论。

## 一、结论

1. **两个月里出了三个大体量的「反 AI 味」skill**：Impeccable、taste-skill、Hallmark。它们都比 09-07 时调研过的 `ui-ux-pro-max` 更直接地针对「AI 味」。
2. **只有 Impeccable 有原生 iOS 模式**（`PRODUCT.md` 里写 `## Platform: ios` 就会改用 Apple HIG 和原生审计）。taste-skill 和 Hallmark 都只做 Web。
3. **Impeccable 的 iOS 规则标准低于本仓库**，而且它的截图闭环要求用模拟器。这两条跟我们冲突：它要求 44pt 触达，我们盲人端要 64pt；我们的模拟器因为高德 SDK 永久不可用。⇒ **不整装，只拿它的 iOS「slop test」那几条当自查清单**。
4. **真实用户的普遍反馈是：这类 skill 能修不一致和无障碍，但改不掉「长得都一样」**（HN 上多人用过 Impeccable、ui-ux-pro-max、Hallmark 后得出同一结论）。真正起作用的仍然是：人给方向、给参考、反复迭代。
5. **新的通用方法：Google 开源的 `DESIGN.md` 格式**（把设计 token 和规则写进一个文件给 AI 读）。它和我们缺的「审美方向声明」是同一件事。我们已有 `docs/ui/design-direction.md`，不必换格式。
6. **09-07 的复核条件逐条结论**：官方 `frontend-design` 只是搬了家，内容没改；`ui-ux-pro-max` 仍是 44pt；都**没触发**。

## 二、新 skill 逐个看

| skill | 仓库（实测 11-13） | 平台 | 做法 | 对本仓库 |
|---|---|---|---|---|
| **Impeccable** | `pbakaus/impeccable` · 109,013★ · Apache-2.0 · 最近 push 2026-11-12 | Web + 原生 iOS / Android / Flutter / RN | 23 个命令（`critique` 打分评审、`audit` 技术审计、`polish`、`bolder` 等）；62 条确定性规则的「slop 检测器」，不用大模型；可挂成 hook，在 agent 改 UI 文件后自动扫 | 唯一有 iOS 模式的。只抄 `skill/reference/ios.md` 的 slop test，不装 |
| **taste-skill** | `Leonxlnx/taste-skill` · 114,330★ · MIT · 2026-11-08 | 只 Web（React / Vue / Svelte / Next / Tailwind） | 静态指导文件 + 脚本（`shoot.mjs` 截全页图、`perf.mjs`）；改旧页前先在浏览器里审一遍 | 不适用 |
| **Hallmark** | `Nutlope/hallmark` · 54,027★ · MIT · 2026-11-11 | 只 Web | 50 套主题；`audit` 只报告、`redesign` 重做；在 `.hallmark/log.json` 记录历次产出，**结构或主题和最近几次重复就直接判失败** | 不适用，但「记录历次产出、防止收敛」的思路值得记住 |
| **Uncodixfy** | `cyxzdev/Uncodixfy` · 2,682★ · MIT · 最近 push 2026-03-18 | 只 Web | 一份反 AI UI 规则清单；多个二次封装 skill 以它为来源 | 不适用，且已半年没更新 |
| **garden-skills（原 web-design-skill）** | `ConardLi/garden-skills` · 15,026★ · MIT · 2026-11-08 | 只 Web | 把 Claude Design 的系统提示词整理成 SKILL.md | 不适用 |
| **DESIGN.md 格式** | `google-labs-code/design.md` · 28,841★ · Apache-2.0 · 2026-11-06 | 与平台无关 | YAML 头写 token、正文写规则；Stitch 是参考实现；规范仍是 alpha | 思路已有（`docs/ui/design-direction.md`），不迁移 |

09-07 已经评过、本轮复核的：

| skill | 实测 11-13 | 变化 |
|---|---|---|
| 官方 `frontend-design` | 2026-10-26 从 `anthropics/claude-code` 删除（提交 `10a5141`），搬到 `anthropics/claude-plugins-official`；新位置 SKILL.md 71 行，与旧版 `diff` 无差异，最后一次内容提交仍是 2026-09-01 的 `44490cc` | 只搬家，**复核条件没触发** |
| `ui-ux-pro-max` | `nextlevelbuilder/ui-ux-pro-max-skill` · 148,693★ · MIT；`pro-rules.md:21` 仍写 "at least 44pt on iOS" | 标准没提高，**复核条件没触发** |
| `rshankras/claude-code-apple-skills` | 887★ · MIT · 184 个 SKILL.md（09-07 时 183 个） | 无实质变化 |
| `wshobson/agents` 的 `mobile-ios-design` | 42,454★ · MIT | 已在 [ios-design-repos-and-list-row-actions-20261030.md](./ios-design-repos-and-list-row-actions-20261030.md) 评过 |

## 三、Impeccable 的 iOS 模式（唯一可能用得上的部分）

原文 `skill/reference/ios.md`（51 行，首次提交 2026-07-09；README 在 2026-11-09 的 #1331 才写明原生用法）：

- 它对「iOS 上的 AI 味」的定义是 **"ported from a website"**：自己重画导航栏、自定义返回手势、网页样式的按钮、依赖悬停的交互。
  这条和我们 09-07 自己写的判断一致，而且比 Web 清单（紫渐变、Inter 字体）更适用于原生。
- 可以直接当自查项的几条：用系统文字样式跟随 Dynamic Type、不写死字号（`:24`）；正文与控件用 SF（`:25`）；用语义系统色，原始十六进制在深色和高对比模式下会坏（`:30`）；模糊用系统材质，不手搓玻璃效果（`:33`）；用系统控件，**自造控件是最常见的原生 AI 味**（`:37`）；图标用 SF Symbols（`:38`）。
- **和本仓库冲突的两条**：
  1. `:20` 触达下限 44×44pt。本仓库盲人端是 64pt（`aidrun-a11y-voice`）。照它审会放过不合格的按钮。
  2. `:49` "Screenshots come from the Simulator, never a browser"。本仓库模拟器因高德无 arm64-sim slice 永久不可用，截图只能走真机 `xcresulttool export attachments`。
- `:51` 要求说明证据来自模拟器还是真机。这和我们记忆 `verified-on-one-device-is-not-verified` 的要求一致，可以保留。

## 四、反对意见（原始评论）

- Impeccable 首发帖（HN 46587284，2026-01-12，103 分 64 评）：多人说宣传页的 BEFORE 比 AFTER 好看（`drcongo`、`zx0r4`、`ssgodderidge`：信息密度变差）。作者 `paulbakaus` 承认示例 "were rushed" 并撤下。
- Hallmark 首发帖（HN 49058547，2026-07-26）：
  - `mstkllah`：用过 impeccable、ui-ux-max 和很多别的，"they all seem to converge on the same thing"，能修不一致和无障碍，但设计本身还是一样，除非你说得极具体。
  - `aleksiy123`：还是像 slop，最后只能自己反复指挥和迭代。
  - `opwizardx`：Hallmark 至少用历次产出日志直接对抗收敛，但它自己承认导航轮换规则是「实践中最常被违反的一条」。
- 09-07 已记录的同类争议仍然成立：官方 `frontend-design` 被说是 "placebo at best"，也有人能一眼认出用了它。

## 五、对本仓库的建议

1. **不安装任何一个新 skill**。三个大的只有 Impeccable 支持 iOS，但它的触达标准更松，截图通道我们用不了。
2. **可选的小改动（要负责人点头）**：把 Impeccable `ios.md` 的 slop test 改写成中文，加进 `docs/ui/design-direction.md` 的自查段，触达标准改成 64pt，截图通道改成真机。约 10 行。
3. **方法层面不变**：继续用 09-07 的两遍工作法、参考图同功能（记忆 `ui-references-must-match-function-keep-layout`）、真机截图后按设计规则挑毛病（记忆 `mockup-must-be-design-critiqued-not-just-rendered`）。外部用户的反馈也证明，skill 代替不了「人给方向 + 迭代」。

## 六、来源

- https://github.com/pbakaus/impeccable （README、`skill/reference/ios.md`、`skill/reference/audit.native.md`）
- https://github.com/Leonxlnx/taste-skill
- https://github.com/Nutlope/hallmark
- https://github.com/cyxzdev/Uncodixfy
- https://github.com/ConardLi/garden-skills
- https://github.com/google-labs-code/design.md
- https://github.com/anthropics/claude-plugins-official/blob/main/plugins/frontend-design/skills/frontend-design/SKILL.md
- https://github.com/anthropics/claude-code/commit/10a5141
- https://github.com/nextlevelbuilder/ui-ux-pro-max-skill
- https://news.ycombinator.com/item?id=46587284
- https://news.ycombinator.com/item?id=49058547
- 二手入口（只用来找线索，结论不依赖它们）：https://aicoding.csdn.net/6a629ce9662f9a54cb93ad6f.html 、https://rar.design/posts/claude-code-design-taste-workflow 、https://medium.com/@slakhyani20/anti-ai-slop-design-skill-for-claude-code-cursor-and-codex-to-help-you-build-and-design-better-49543e0f5ff7 、https://departmentofproduct.substack.com/p/designmd-explained-the-format-reshaping
