## Why

负责人 2026-11-05 真机走了一遍志愿者注册（iOS #768），提了四件事：

1. 登录收验证码时已经填过手机号，实名页又要再填一次。
2. 人脸识别通过后停在完成页，要自己点「返回志愿者首页」才进首页。期望识别完自动进首页。
3. 人脸识别做了很多次。
4. 两个不同手机号的账号能填同一个身份证号。负责人定「一证一个志愿者」，后端 #924 加错误码。

## What Changes

- 实名第 1 步去掉手机号输入框和手机号校验。提交 `step1` 时不再带 `phone`，后端用登录账号的手机号（后端 #924 把 `phone` 改为可选）。`/api/auth/me` 只返回脱敏号码，客户端拿不到完整号码，所以不传。
- 人脸核验通过、注册状态报完成后，立即把完成态交给 `AppState`，根路由自动切到志愿者首页。先播完成那一句，播报不受路由切换影响（首页进入时不播任何话）。完成页和「返回志愿者首页」按钮删除。接单前还差什么，在首页点「查看接单前进度」看。
- 拒绝人脸走替代路径的人不变：仍停在替代路径落地页，上传材料入口和「返回志愿者首页」照旧（他还要从这一页去上传材料）。
- 接住后端 #924 的「身份证已被其他志愿者账号使用」错误码（暂按 `ID_CARD_ALREADY_REGISTERED`，以后端合并的契约为准）：停在身份信息页，给明确文案，不引导「核对证件」。
- 「识别很多次」：客户端没有自动重发刷脸。查不清的部分写进 PR 交接，请负责人下次复现时记屏幕提示。

## Capabilities

### New Capabilities

### Modified Capabilities
- `direct-volunteer-registration`：第 1 步不再收手机号；人脸通过后自动进首页；一证一个志愿者的错误码处理。

## Impact

- 代码：`blindRun/Volunteer/VolunteerRegistrationFlowView.swift`、`VolunteerRegistrationBasicInfoPages.swift`、`VolunteerReadinessProgress.swift`（完成播报文案）、`blindRun/Core/Models/VolunteerRegistrationModels.swift`（`phone` 可选）、`blindRun/Core/Models/ErrorModels.swift`（新错误码）。
- 契约：依赖后端 Jayden23018/blind-run-backend#924（`BasicInfoRequest.phone` 改可选、新错误码）。后端未合时本变更不能合入。
- 测试：按负责人 2026-11-05 决定，本次不跑真机测试，只做编译检查。
