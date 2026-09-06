---
name: aidrun-contract-sync
description: 后端契约变了、pre-push 报「生成代码与契约不同步」、或要判断契约新增字段该不该接入前端时读。含一键同步命令与漂移分级判据。
---

# 契约漂移处理

## 为什么这事反复发生（不是 bug，是设计）

契约的唯一源在后端仓库。后端每改一次 `docs/api_spec.yaml`，本仓库 check-in 的生成代码就过期一次，
`pre-push` 与 CI 的比对门禁随即变红。**门禁的意图就是逼前端知道契约变了** —— 它不该被关掉。

需要固化的是「知道之后干什么」，那部分以前每次都靠人重新想一遍，于是每次都要重新查
「契约该从哪取」「fetch 了没」「新字段要不要接」。

## 你不需要记得检查 —— pre-push 自动做

装过 `scripts/install-git-hooks.sh` 的机器上，**每次 push 都会自动**：

1. 从后端 `origin/main` 取契约
2. 重新生成，**并把结果留在你的工作区**
3. 比对，不一致就拦住 push
4. 跑 `scripts/report-drift-fields.mjs`，按每个新字段的**归属路径**查**对应的那一个**手写模型有没有

所以被拦住时**不用再跑任何生成命令** —— 结果已经在工作区里了，直接 `git add` + `commit`。
终端上会直接列出哪几个字段手写模型没有。

> 没装钩子的机器上这一切都不会发生。装：`scripts/install-git-hooks.sh`（每台机器一次）。

## 手动跑（想在 push 之前先看看）

```bash
scripts/sync-api-client.sh          # 取正式契约 → 重新生成 → 报告漂移
scripts/sync-api-client.sh --check  # 同上，但生成后还原，工作区不留改动
node scripts/report-drift-fields.mjs  # 只报告，不生成（读工作区已有的 diff）
```

两条路径共用同一份判据实现（`report-drift-fields.mjs`），不会漂开。

**不要直接跑 `scripts/generate-api-client.sh`** —— 它默认读 `../demo` 的**工作区文件**，
而那是共享 checkout，随时停在别人的特性分支上（2026-08-21 实测停在 `review/backend-audit-20260820`）。
照它生成等于把别人未合并的 WIP 烘进你的提交，而门禁比对的是后端 `origin/main`，两边永远对不上。
包装脚本做的就是「先 fetch、从 `origin/main` 取、再生成」。

## 漂移分四级，处理方式不同

跑完看脚本输出的那行 `漂移 N 行：注释 X，代码 Y`。

> 🚨 **✅ 的含义是「归属模型上有」，不是「某处有同名字段」。** 2026-08-29 之前这个闸是拿裸字段名
> 在整个 `blindRun/` 里 grep 的，假绿过两次：`IntroCallView` 的 `startAddress` 命中了
> `OrderDetailResponse`，`notifications/since` 信封的 `hasMore` 命中了 `VolunteerBadgeWall`。
> 现在按生成代码里 `Generated from` 的归属路径定位模型，判不了就报 ❓，绝不报 ✅。
> 判据自测 `node scripts/validate-drift-fields.mjs`（pre-push 与 CI 都跑）。

### ① 纯注释（代码 0 行）

后端给端点补了 description。**直接提交**，一个 `chore:` PR 了事，不需要真机测试
（生成代码不参与 App target 运行时）。

### ② 有新字段，且**归属的**手写模型上已有（脚本报 ✅）

说明前端早就跟上了，只是生成代码落后。同 ①，直接提交。

### ③ 有新字段但判不了归属（脚本报 ❓）—— 必须手查，不许当 ✅ 放过

两种成因，处理不同：

- **响应信封顶层字段**（归属路径是 `#/paths/...` 而不是 `#/components/schemas/...`）。
  它不属于任何 schema，手写侧也没有稳定的同名类型 —— `APIClient` 拆信封的方式按端点各不相同。
  脚本会把端点打出来（如 `GET /api/notifications/since`），照它去看那个端点的手写响应模型。
- **手写侧没有同名类型**。可能是改了名（那就自己确认那个模型上有没有），也可能压根没接
  （那就按下面 ④ 处理）。

判完照样要写进 PR body，理由与 ④ 相同。

### ④ 有新字段且对应的手写模型没有（脚本报 ❌）—— 唯一需要动脑的一级

**生成代码不投入运行时**（运行时走手写 `APIClient`，理由见 `Packages/AidRunAPI/Package.swift`：
主工程 MainActor 默认隔离与生成代码相撞；且生成的是封闭枚举，会把「未知枚举值不许整条崩」
这条盲人端红线退回去）。所以这些字段**当前等于不存在**，探测到 ≠ 已接入。

**先读契约里每个字段的 `description` 再判**，不要看字段名猜：

| 情形 | 处理 |
|---|---|
| 触及盲人端红线：静默失败、TTS 播报文案、`null` 与 `0` 语义相反 | **单独开变更**，要有测试。不许并进别的 PR |
| 纯展示、无播报、不影响决策 | 可并入下一个相关 PR |
| 前端用不上 | 什么都不做，但**在 PR body 写明为什么不接** |

判断结论必须落进 PR body。让它停在「探测到了」而不写下去，下次同样的字段会被重新探测、
重新讨论一遍 —— 这个 skill 存在的理由就是终止那个循环。

## 当前未接入的字段（2026-08-21，随 PR #62 探测到）

四个都还没接。前两个属上表第一行，**接入前必须单独开变更**：

- `specialNotesTruncated: Bool?` —— 备注被后端截断的标志。备注由后端从转录抽取、天然 ≤200 字，
  所以「说得短」「说了 300 字被截到 200」在客户端**长得一模一样**。用户那句
  「如果我说头晕就扶我坐下」有没有进去，当前无从分辨 —— 对看不见屏幕的人这是静默失败。
- `volunteerAvgRating: Double?` —— 🚨 `null` 与 `0` 语义**相反**：`null` = 新人还没收到过评价。
  念成「0 分」等于把新人说成差评。
- `volunteerTotalRatings: Int?` —— `0` 是真实的 0（新人），不是缺数据。
- `volunteerTotalCompleted: Int?` —— 纯展示，**不进派单权重**，文案别写「完成得多更容易接到单」。

接入任何一个后回来划掉它，四个都划掉就删掉本节。

## 两个会让人误判的细节

- **`git push --delete` 也触发 pre-push**，于是删分支会被代码漂移拦住，理由与分支毫无关系。
  删远端分支不推送任何代码，用 `AIDRUN_SKIP_PREPUSH=1 git push origin --delete <branch>`，
  这不算不当绕过。
- **校验失败时钩子把重新生成的结果留在工作区**，`Packages/AidRunAPI/` 下两个文件变 `M`，
  下次 `git checkout` 会带着走，看起来像同事的未提交改动。查 mtime：等于你刚跑 pre-push
  那一刻的，就是钩子自己留的。

## 为什么不做成 subagent

评估过，不划算。这个任务 90% 是机械命令（fetch / 导出 / 生成 / diff），脚本做得更好也更快；
剩下 10% 是判断字段会不会打到盲人端红线，那需要项目知识 —— 而 subagent **不继承主对话上下文**，
每次都得把 AGENTS.md 的红线重喂一遍，喂漏一条它就自己编一条。
脚本固化机械部分 + 本 skill 承载判断规则，比 subagent 少一层且不会漂。
