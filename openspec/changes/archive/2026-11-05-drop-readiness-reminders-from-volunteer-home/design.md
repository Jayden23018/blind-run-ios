## Context

作业区原来有三类「接不了单」提醒：培训卡（`VolunteerProfileTodoGate.needsTrainingEntry`）、资质入口（`needsCertificateEntry`）、`acceptBlockMessage` 原因句。#658 之后底部胶囊在被资质、培训、停用挡住时显示「暂不能接单」并通往接单前进度页，两处重复。

## Decisions

### 每种原因仍至少说一次

| 原因 | 去掉作业区后在哪说 |
|---|---|
| `TRAINING_INCOMPLETE` | 底部胶囊「还没完成必修培训」→ 进度页培训一步（可点进培训页） |
| `NOT_VERIFIED` | 底部胶囊「还没上传证书 / 证书审核中 …」→ 进度页证书、审核两步 |
| `ACCOUNT_SUSPENDED` | 底部胶囊停用说明 |
| `OFFLINE` | 开着时胶囊「暂时收不到派单 · 未在线」；接单页状态卡 |
| `DISPATCH_DISABLED` | 胶囊本身就是「向右滑开启」 |
| 未识别取值 | 接单页状态卡兜底句 |

接单页的派单状态卡原来省掉培训、资质（理由是作业区画成了整卡）。作业区不再画，省略集合清空，卡里照说全部原因。单测改成断「每个原因在胶囊说明或状态卡里至少出现一次」。

### `acceptBlockMessage` 原因句直接删

它只剩三句：「请先完善志愿者资料」「请先完成志愿者注册流程」「请等待管理员审核通过」。前两句的人进不了首页（根路由留在注册流程）；第三句对应后端 `NOT_VERIFIED`，由胶囊说。`requiresDispatchOptIn` 参数只为作业区存在，一起删。接单 / 有意向两条动作路径的拦截不变。

### 接单被 403 `VOLUNTEER_NOT_APPROVED` 而摘要没说 `NOT_VERIFIED`

原来作业区会给资质入口。现在这次 403 的错误文案仍在作业区「加载出错」那一条里，进度页也能从设置进。两个来源不一致属于后端数据问题，不为它在首页留一个常驻入口。`VolunteerHomeViewModel.needsCertificateUpload` 只被作业区读，一起删。

## Risks

- 培训卡原来满足「在首屏、整卡可点、一下直达」（2026-09 用户意见）。现在路径是胶囊 → 进度页 → 培训一步，多一页。负责人 2026-11-05 已接受这个取舍。
