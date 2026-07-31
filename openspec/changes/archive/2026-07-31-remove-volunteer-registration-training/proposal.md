## Why

志愿者当前必须在身份与活体认证后完成课程学习和测验才能注册并接单，这为主流程增加了不再需要的阻塞步骤。注册流程应在活体认证通过后直接完成，同时保留旧培训接口供外部后端平滑过渡。

## What Changes

- 将志愿者主注册流程缩减为基本信息/身份证二要素核验和动作活体认证两步。
- 要求外部后端在活体认证结果通过时直接将注册状态置为 `STEP_4_COMPLETED` 且 `canAcceptOrders = true`。
- 移除 iOS 课程、学习进度和测验 UI、DTO、Mock 路由及调用。
- 为完成注册提供明确成功页；后端状态尚未完成时仅显示同步等待和刷新，不重复发起活体认证；遗留 `STEP_4_TRAINING` 由 iOS 兼容归一化为完成。
- 保留现有培训及管理员课程 API 以兼容旧后端，但在 OpenAPI 中标记为弃用，iOS 不再调用。
- 将 `STEP_4_TRAINING` 和培训统计字段定义为仅供遗留兼容；新注册不得进入该状态。

## Capabilities

### New Capabilities
- `direct-volunteer-registration`: 定义两步志愿者注册、活体通过后的原子完成合同、状态同步 UI 和遗留培训兼容行为。

### Modified Capabilities
- `formal-dispatch-service-flow`: 将志愿者接单资格的注册门槛明确为主注册完成状态，而不是课程、测验或可选资质证书状态。

## Impact

- iOS 志愿者注册 View/ViewModel、注册 DTO、Mock 客户端和相关单元/UI 测试。
- `docs/05-page-specs.md`、`docs/06-data-model.md`、`docs/07-api-contract.openapi.yaml` 和 `docs/websocket-protocol.md`。
- 外部后端仍应调整活体通过后的状态写入；iOS 同时兼容尚未升级的后端和已有 `STEP_4_TRAINING` 用户，本仓库不包含后端实现。
