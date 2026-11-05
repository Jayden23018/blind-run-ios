## 1. 实现

- [x] 1.1 删除盲人引导流（`BlindRunnerOnboardingView`、`RootRoute.blindProfile`、`AppState.blindOnboardingStep`），资料不全与档案 404 都进首页
- [x] 1.2 根路由刷新键去掉 `isBlindBookingReady`
- [x] 1.3 约跑页顶部加「约跑前还差 N 项」卡；门槛文案指向它
- [x] 1.4 从补资料页回到约跑页时不重开语音，只更新「还差什么」：撤掉已补齐那项的旧句子（表单底部的提示与语音降级时顶上那句）

## 2. 验证

- [x] 2.1 单测跟着改：删引导步骤用例，加「新账号直接进首页」「卡片只列还缺的」「补齐后撤掉那句」「语音降级句随补齐更新」四条
- [x] 2.2 编译检查（`build-for-testing`）通过；`validate-spec-coverage.mjs` 通过
