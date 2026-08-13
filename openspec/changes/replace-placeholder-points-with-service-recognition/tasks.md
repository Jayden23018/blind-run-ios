# Tasks

## 1. 契约投递（与实现并行）

- [ ] 1.1 投 handoff「待后端确认」：要不要做真的积分体系？要的话给出产生规则、
      有没有兑换出口、会不会过期。注明前端已撤掉假实现，**不阻塞**后端将来做真的。
- [ ] 1.2 投 handoff：完成单数多的志愿者要不要在派单里加权（滴滴「点亮勋章后接单概率增加」）？
      这决定成就体系是纯荣誉还是有实际收益，会影响前端文案措辞。
- [x] 1.3 ~~投 handoff：`dispatch-summary` 能否补**累计服务时长**？~~
      **当场作废（2026-08-13）**：不用补。`GET /api/volunteer/achievements` 一直就有
      `totalServiceMinutes`，后端刻意与 dispatch-summary 分开（扫全部已完成订单的代价
      不该压在首页最热的端点上）。是本变更起初没查这条端点。见第 7 节。

## 2. 删除假积分

- [x] 2.1 `VolunteerDispatchSummaryModels.swift`：删 `pointsBalance` 字段与 `resolvedPointsBalance`；
      删 `resolvedPointsDelta` 的 `+100` 兜底，`pointsText` 改为 `String?`（`nil` 时整行不显示），
      **保留 `pointsDelta` 字段本身**（见 D6）。
- [x] 2.2 `VolunteerHomeView.swift`：四格改三格（不补第四格凑数）；
      `accessibilityLabel` 里的「积分 N」同步删——**这条最容易漏，视觉上没了但读屏还在念**；
      入口图标 `gift` → `rosette`，标题「积分」→「成就」，label/hint 同步。
      最近订单卡的积分行改为「后端真发了才显示」。
- [x] 2.3 `VolunteerOrderFlowViews.swift`：删 `VolunteerServiceRecord.pointsText`（恒为「+100 积分」）
      及其在 accessibility label 里的引用；服务记录卡里那行积分整行删掉。
      `.completed` 的描述文案由「服务完成，获得 +100 积分」改为「服务完成，感谢你的陪伴」——
      **不是只删**：这是志愿者跑完一趟唯一的正反馈，把假承诺删掉不该连正反馈一起删掉，
      一句感谢不涉及任何数字且是真的。
- [x] 2.4 `MockAPIClient.swift`：`pointsDelta` 改 `nil`，删 `pointsBalance` 传参。
      Mock 造出后端不存在的字段值会让 Mock 环境的 UI 与真实环境长得不一样，而 UI 是照着 Mock 调的。

## 3. 服务成就页

- [x] 3.1 新建 `blindRun/Volunteer/VolunteerServiceRecognition.swift`：
      `ServiceRecognitionTier`（5 档，见 D2）、`ServiceRecognitionProgress`、
      `progress(completedCount:)` / `currentTier` / `nextTierRemaining` / `summarySpeech`。
      **不 import SwiftUI**，保证可单测。
- [x] 3.2 `VolunteerPointsPlaceholderView` → `VolunteerServiceRecognitionView`：
      删掉 `VolunteerPointsViewModel` 整个类（死代码）；头部是真实完成单数 + 当前称号；
      5 档列表每档带档位名 + 独立 SF Symbol + 状态文字（颜色不是唯一指示）；
      未解锁写「还差 N 单」；`accessibilityLabel` 给完整语义；
      页面无自己的网络请求与状态，`dispatchSummary` 由调用方传入。
- [x] 3.3 调用点导航与标题更新（「积分商城」→「服务成就」）。

## 4. 规格

- [ ] 4.1 MODIFIED `openspec/specs/system-dispatch-flow/spec.md` 的
      **Requirement: Volunteer statistics and temporary points are displayed**——
      本变更的 spec delta 已写好，归档时生效。确认无其它未归档变更改同一条
      （2026-08-13 已核：零命中）。

## 5. 测试

- [x] 5.1 `blindRunTests/VolunteerServiceRecognitionTests.swift`（纯单测，12 条）：
      边界值 0/1/9/10/24/25/49/50/99/100/101 逐个钉解锁档数与当前称号；
      已解锁档 `remaining == 0`；负数按 0 处理；每档靠名称与图标可区分（非颜色）；
      未解锁 label 说清还差几单；播报不出现「积分」「兑换」。
- [x] 5.2 回归断言：`pointsDelta` 为 `null` 时 `pointsText` 为 `nil`（不再编「+100」）；
      后端真发时如实显示；`VolunteerDispatchSummaryResponse` 解码一份**含** `pointsBalance`
      的 JSON 时该键被忽略，成就页仍只用 `completedCount`。
      同时改掉 `blindRunTests.swift` 两处断言 `resolvedPointsBalance == 100 / 200` 的旧用例
      —— 它们钉住的正是本变更要撤掉的合成值。
- [x] 5.3 **落成守卫**（`AGENTS.md` §1.1）：`guard.mjs` 新增 `placeholder-promise`，
      拦出货代码里的「敬请期待 / 即将上线 / 敬请关注」。占位 UI 本身不禁，
      拦的是「会兑现」的暗示。全仓复扫确认零误伤，`validate-guard.mjs` 加 3 条正反用例
      （并带上 post 模式 runner —— 内容级规则要从磁盘读真实文件，此前 runner 只跑 `pre`）。
      `node scripts/validate-guard.mjs` → 31 条全过。
- [x] 5.4 跑收窄范围的真机测试（范围按符号搜 `blindRunTests` 定；本变更不碰全局单例）：
      ```bash
      scripts/device-test.sh -only-testing:blindRunTests/VolunteerServiceRecognitionTests \
                             -only-testing:blindRunTests/blindRunTests \
                             -only-testing:blindRunTests/OrderEnumLeniencyDecodingTests
      ```
      **`passed=311 failed=0 skipped=0 result=Passed`**（iPhone 16 Pro）。
      逐 suite 核过日志确认不是零执行：`VolunteerServiceRecognitionTests` 12 条
      （逐条 passed）、`blindRunTests` 281 条、`OrderEnumLeniencyDecodingTests` 17 条。
      `blindRunTests` 全绿说明改掉的那两处旧断言（`resolvedPointsBalance == 100 / 200`）
      没有连累同套件的其它用例。

## 7. 改用真端点 + 国标星级（后端 SPEC-D D1，2026-08-13 追加）

- [x] 7.1 `scripts/openapi/openapi-generator-config.yaml` 加 `/api/volunteer/achievements`
      并重新生成（`scripts/generate-api-client.sh`，+492 行纯新增）。
      生成代码只当漂移探测器，运行时仍走手写 `APIClient` —— 但正因为进了 filter，
      后端发布 `nextBadge` / `starLevel` 的当天 CI 的「重新生成并比对」会变红，
      那就是联调信号。
- [x] 7.2 新建 `blindRun/Volunteer/VolunteerAchievements.swift`：
      响应模型（全字段可选）、`VolunteerStarLevel`（GB/T 阈值 + 本地推算 fallback）、
      `VolunteerAchievementsCopy`、`VolunteerBadgeWall`（主页 4 枚 + 二级页）。
      **不 import SwiftUI**，保证可单测。
- [x] 7.3 `VolunteerServiceRecognitionView` 改读 `GET /api/volunteer/achievements`
      （一个 `.task`，无 `AnyCancellable`）；国标星级栏与平台勋章栏**分两栏**；
      进度条 `accessibilityHidden`，进度作为独立文本节点存在；
      新增 `VolunteerBadgeWallView` 二级页；失败态给重试。
- [x] 7.4 删除 `VolunteerServiceRecognition.swift` 与 `VolunteerServiceRecognitionTests.swift`
      （客户端自编的五档称号）；`VolunteerHomeView` 调用点去掉 `summary:` 传参。
- [x] 7.5 `MockAPIClient` 加 `/api/volunteer/achievements` 分支，勋章判定逐条抄后端
      `VolunteerBadge.isUnlockedBy`；`nextBadge` / `starLevel` **一律返回 nil**
      —— Mock 造后端不会下发的字段，会让「字段缺失」这条真实分支永远跑不到。
- [x] 7.6 **落成守卫**（`AGENTS.md` §1.1）：`guard.mjs` 新增 `volunteer-hours-credential`，
      拦「服务/时长/志愿证明·证书」「时长已认证」。词表刻意不含「资质证书」「实名认证」
      （注册流程的真实动作）。全仓复扫零误伤，`validate-guard.mjs` 加 7 条正反用例
      → 44 条全过。
- [x] 7.7 `blindRunTests/VolunteerAchievementsTests.swift`：国标阈值逐条对国标、
      向下取整、服务端值优先于本地推算、**badges 只含已解锁**（回归门）、
      未知 code 不崩、进度是可读文本、文案不含「证明/证书/已认证」、主页 4 枚上限。
- [ ] 7.8 真机跑上面这些 suite。⚠️ **未执行**：两台设备当前都是 `unavailable`
      （`xcrun devicectl list devices`），本仓库唯一 XCTest 通道不可用。
      编译门禁已过（`build-for-testing` → `TEST BUILD SUCCEEDED`）。
- [x] 7.9 ~~投 handoff 问 `nextBadge` 的单位~~ **不用问了**：写这条的同一天后端就发布了 D1
      （`9f8606d`），契约里写清楚了 —— `RUNS_*` 是次、`HOURS_*` 是**分钟**、
      `HIGH_RATED` 是条评价，且没有 `unit` 字段（按 `code` 查表）。
      客户端原先准备的「不拼单位、只渲染分数」方案在 `HOURS_*` 上会显示
      「已完成 360 / 600」—— 分母对但读起来像小时，实际是分钟。已改成按 code 换算。
- [x] 7.10 后端 D1 上线后的跟进（同日）：
      `nextBadge` 按 code 选量词并把分钟换算成小时；`starLevel` 契约里恒非 null，
      本地推算降为防御路径（字段真缺时不让整栏空白）；Mock 补齐两个字段并照分钟口径给；
      重新生成 API 客户端（Types.swift +222 行）。
      **`HIGH_RATED` 满格不解锁**（双条件，进度只跟条数）已单独立测，文案一律不写
      「还差 N 就解锁」。

## 6. 收尾

- [ ] 6.1 真机 `111` 上开 VoiceOver 走一遍成就页：遍历顺序、每档 label 语义完整、
      未解锁档位听得出「还差几单」。低视力档位（AX3 以上字号 + 深色模式）看一眼不裁切。
- [ ] 6.2 按 skill `aidrun-ship-check` 输出验证结论，贴真实测试输出。
- [ ] 6.3 同步 handoff（第 1 节三条），commit，push，开 PR。
