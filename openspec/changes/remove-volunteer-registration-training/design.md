## Context

志愿者注册当前由 Step 1 身份信息、Step 3 原生活体认证和 Step 4 培训测验组成。iOS 只有在培训测验完成后才把 `STEP_4_COMPLETED` 或 `canAcceptOrders = true` 视为注册完成；真实状态由仓库外的云端服务控制，Mock 必须保持离线且复刻同一合同。

## Goals / Non-Goals

**Goals:**
- 将 iOS 注册体验收敛为身份信息和动作活体两步。
- 让活体通过成为注册完成的最后业务动作，同时兼容后端权威状态中的遗留终态。
- 为后端最终一致性提供不会重复活体认证的等待状态，并将 `STEP_4_TRAINING` 归一化为完成。
- 停止 iOS 对所有培训 API 的调用，并保留 OpenAPI 弃用合同供外部系统过渡。

**Non-Goals:**
- 在本仓库实现后端迁移、课程管理或数据库变更。
- 移除外部后端现存培训端点或兼容 schema。
- 自动开启志愿者的 `isAvailable` / `wantsDispatch`。
- 改变 Step 1 身份核验、阿里云原生活体 SDK 或可选资质证书上传流程。

## Decisions

1. **后端注册状态仍是完成依据，并兼容遗留终态。** Step 3 result 返回通过后，iOS 立即刷新 `/api/volunteer/registration/status`；`STEP_4_COMPLETED`、`canAcceptOrders = true` 或遗留 `STEP_4_TRAINING` 均进入成功页。旧流程只有完成活体后才进入 `STEP_4_TRAINING`，因此该状态可安全归一化；新后端仍不得产生它。

2. **完成页不是第三个注册步骤。** 步骤指示器只展示基本信息和活体认证；完成是独立结果状态，文案为“注册完成，请返回首页开启可服务状态”，并提供 VoiceOver/TTS 和显式返回按钮。

3. **活体通过但注册终态尚不可见时进入同步等待。** `step3Completed = true` 或已通过的 face status 且状态仍未进入 `STEP_4_TRAINING` / `STEP_4_COMPLETED`、也没有 `canAcceptOrders = true` 时，客户端显示“活体已通过，注册状态同步中，无需课程或答题”，每 5 秒刷新并提供手动刷新。此状态禁用新的活体 init，避免消耗重复 `certifyId`。

4. **iOS 完全删除培训领域代码。** 删除培训 DTO、ViewModel 状态/动作、视图和 Mock 路由；Swift 解码继续忽略后端可能返回的遗留培训字段。相比保留隐藏死代码，这能确保客户端不会意外恢复课程门槛。

5. **Mock 在活体通过时直接完成注册。** Mock result 同时设置 `STEP_4_COMPLETED`、`canAcceptOrders = true` 和认证通过状态，但保持可服务开关为 false，以匹配生产注册与上线接单的分离。

6. **培训 HTTP 合同仅弃用。** OpenAPI 的志愿者培训和管理员课程/题库/统计 operation 全部保留并标记 `deprecated: true`；`STEP_4_TRAINING` 与培训统计字段保留为遗留兼容，描述明确新注册不得产生这些值。

## Risks / Trade-offs

- **[Risk] 外部后端仍返回 `STEP_4_TRAINING` 且 `canAcceptOrders = false`** → iOS 允许完成注册并返回主页，但真实派单接口仍可能拒绝开启服务；客户端展示服务端错误，不伪造派单资格。
- **[Risk] Step 3 result 已通过但状态刷新暂时失败** → 保持已通过/同步中状态和手动刷新，不重新发起活体认证。
- **[Risk] 遗留培训 API 继续存在引发误用** → OpenAPI 全部标记弃用，维护文档明确 iOS 禁止调用，并用测试断言注册流程无培训请求。
- **[Risk] “注册完成”被误解为已经上线接单** → 成功页明确提示返回首页手动开启可服务状态，Mock 和生产均不自动修改 availability。

## Migration Plan

1. 外部后端先保证新的活体通过操作原子写入 `STEP_4_COMPLETED` 和 `canAcceptOrders = true`。
2. iOS 将已有或尚未升级后端返回的 `STEP_4_TRAINING` 兼容归一化为注册完成，同时保持 availability 关闭。
3. 发布包含两步 UI、遗留终态归一化和同步等待逻辑的 iOS 版本；旧培训端点继续可用但标记弃用。
4. 真机验证注册完成和手动开启可服务后再签署发布结论。若后端未就绪，回滚客户端发布，不恢复课程作为新注册门槛。

## Open Questions

- `需要人工确认`：外部后端完成状态原子写入的部署时间，以及遗留账号能否通过真实派单接口开启服务。
