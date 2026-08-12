# Review 索引

本仓库**所有**成体系的 review（前后端对齐、功能缺口、无障碍审计、发布前复核）的唯一落脚点。
规则与 `docs/research/INDEX.md` 同构，只有三条：

1. **开新 review 前整份读这个文件**，不要 `ls | grep` —— `ls` 只匹配文件名，搜「无障碍」命中不了
   `frontend-backend-alignment-review-20260812.md`；能搜到的词在下面「范围」和「一句话结论」两列里。
2. 上一份的结论还作不作数，看「复核触发条件」那列。**没触发就直接引用，不要重新审一遍。**
   触发了、或表里没有这个范围、或有但缺你要的那一段 —— 才开新一轮。
3. review 完落盘到 `docs/review/{topic}-{YYYYMMDD}.md`，**并回写下面一行**。
   不回写等于没做：下次找不到，同一份 review 会被原样重跑。

**与 `docs/research/` 的分工**：research 记「外面是怎么做的」（联网事实，带来源与核实日期）；
review 记「我们做成了什么样」（对着代码与契约的判断，带 `文件:行号`）。一次 review 引用一次 research 是常态，
反过来不成立 —— 不要把竞品事实写进 review，会漂移。

> 与 research 不同，这里**没有 hook 强制**。`scripts/hooks/research-log.mjs` 只管联网调研。
> 若这条规则被漏过第二次，按 `AGENTS.md` §1 把它落成守卫，别再加一段文档。

| 日期 | 范围 | 一句话结论 | 复核触发条件 | 报告 |
|------|------|-----------|-------------|------|
| 2026-08-12 | 前后端契约对齐：错误码、语音语料、坐标、枚举、字段级漂移 | 逐条对撞后端 `origin/main` 契约；期间因未 `git fetch` 误判两次（删过一份正确的语料镜像、报过一个不存在的 `blindPhone` 缺陷），§B1 记录了这个坑 | 后端契约有 breaking change；前端新增调用后端端点；`scripts/validate-*.mjs` 任一条红 | [frontend-backend-alignment-review-20260812.md](./frontend-backend-alignment-review-20260812.md) |
| 2026-08-12 | 盲人端完整 review：功能缺口（vs 同类产品）、无障碍适配、全流程顺畅度、前后端职责划分 | VoiceOver 通道做得比多数同类产品深（284 label / 遍历序刻意设计），但**必须项 20 条只达成 9 条**；P0 是拨号直暴露真实手机号而隐私号端点 `call/initiate` 零调用；P1 是盲人端无历史订单（注释却写了有）与低视力视觉通道仍空白（`horizontalSizeClass` 0 命中、触觉仅 2 处且都在录音起停） | 上述 P0/P1 修复后；`openspec/changes/` 有变更归档；后端新增 C 端可调用的端点；盲人端信息架构改动 | [blind-app-full-review-20260812.md](./blind-app-full-review-20260812.md) |
