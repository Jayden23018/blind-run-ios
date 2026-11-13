# COSCon'26 项目海报：有没有现成的 skill，版式和字号怎么定（2026-11-13）

## 问题

青少年论坛要一张讲助盲跑项目的海报：为什么做、怎么做、技术架构、成果、限制、未来。有没有好用的海报 skill？会议海报的版式和字号有什么公认规则？

## 结论

1. **不装新 skill。** 没有一个现成 skill 同时满足「中文、信息量大、放 App 截图、印刷尺寸」。用 HTML/CSS 排版，再用 headless Chrome 截图。
2. **只借两个做法。**
   - `paper-poster-html`：画布尺寸以会议官方要求为准，不许猜。每次导出都要测量，测量没过就不算完成。
   - #betterposter：一句话大结论放在最显眼的位置，细节放进窄栏，参考资料换成二维码。
3. **字号按观看距离定。** 1.5 m 外看，正文 ≥ 32pt；能走近看的展板，正文 24–36pt，标题约为正文的两倍。中文笔画多，字号宁大勿小（这条是我们的判断，来源没有写）。
4. **内容量和尺寸要一起定。** 实测同一份内容（7 块，含 5 张截图和架构图）放进 A1 会超出画布将近一倍。改成 90×120cm 竖版，正文约 24pt 时才放得下。

## 候选 skill

| 名称 | 做什么 | 适用度 | 理由 |
|---|---|---|---|
| anthropics/skills `canvas-design` | 先写「设计哲学」，再出 PNG/PDF 艺术海报 | 低 | 要求约 90% 视觉、10% 文字，元素不许重叠，和信息型海报冲突 |
| anthropics/skills `frontend-design` | 先定字体和字阶，再写有个性的网页 | 中 | 同样走 HTML 流程，但没有物理尺寸和观看距离的概念，和已装的 Impeccable 重复 |
| `paper-poster-html`（wanshuiyin/Auto-claude-code-research-in-sleep） | HTML/CSS 学术海报，测量通过才导出 PDF | 中高 | 测量门槛值得借；输入是论文目录，文档没写中文，也没处理 App 截图 |
| K-Dense-AI `latex-posters` | LaTeX 学术海报 | 低 | 中文排版和放截图都麻烦 |
| alchaincyf/huashu-design | 中文设计 skill，带风格库，可导出 PDF/PNG | 中 | README 没写海报；可以当风格参考 |
| op7418/guizang-social-card-skill | 小红书卡片 / 公众号封面，HTML 截图 PNG，带溢出检查脚本 | 中 | 流程一样，但画布是社交媒体尺寸 |

中文社区（小红书、知乎、V2EX）没找到专门讲「用 Claude 做中文会议海报」的帖子。

## 本次实际做法

- 文件放在设计存档 `~/Documents/aidrun-design-archive/2026-11-13-coscon26-poster/`（不进仓库）：`drafts/build.py` 用同一份文案生成三版，`drafts/measure.js` 检查超出画布、最小字号和被裁掉的文字。
- 参考方向对比板（斯坦福 CS147 最佳海报、#betterposter、Apple 无障碍页、Behance 发布海报和瑞士网格海报）被负责人否掉，原话是「都不好看，要信息最多的」。负责人又补充了一句：「poster 是讲自己做的一个项目……不是单纯的产品宣传图」。

## 来源

- https://github.com/anthropics/skills/blob/main/skills/canvas-design/SKILL.md
- https://github.com/anthropics/skills/blob/main/skills/frontend-design/SKILL.md
- https://github.com/wanshuiyin/Auto-claude-code-research-in-sleep （`skills/paper-poster-html`）
- https://github.com/K-Dense-AI/scientific-agent-skills
- https://github.com/alchaincyf/huashu-design
- https://github.com/op7418/guizang-social-card-skill
- https://betterposters.beehiiv.com/p/your-poster-text-is-too-damn-small-20-08-20
- https://knightadrc.wustl.edu/professionals-clinicians/poster-printing/fonts-posters/
- https://hci.stanford.edu/courses/cs147/2024/au/projects/Design-for-Healthy-Behaviors/Unfold/

skill 调研由子代理用 WebFetch 完成，引文可能是近似原文；正式引用前请回原页核对。
