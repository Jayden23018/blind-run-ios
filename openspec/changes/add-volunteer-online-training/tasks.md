## 1. 调研与决策

- [x] 1.1 查政策依据与同类做法，落 `docs/research/volunteer-training-model-20260909.md` 并回写 INDEX
- [x] 1.2 与产品确认七项：门槛形态、内容形态、及格线、记录范围、有效期、选修激励、首页排法
- [x] 1.3 确认「身份证上传/OCR」不在本轮（二要素一直在跑、被删的是 step2 照片、OCR 全仓 0 提交）

## 2. 后端：数据与契约（`demo` 仓库分支 `feat/volunteer-online-training`）

- [x] 2.1 迁移 `0043_volunteer_training.sql`：4 张新表 + 3 门课 9 道题的种子数据
- [x] 2.2 在真实 MySQL 8.0.46 容器上执行并验幂等（跑两遍仍 3 课 9 题），5 条自带核对查询全过
- [x] 2.3 4 个 `@Entity` + `TrainingProgressStatus` + 4 个 repository
- [x] 2.4 逐列比对实体与迁移（4 张表全对齐），并落成 `SchemaTypeDriftTest` 第 4 条用例常驻
- [x] 2.5 5 个 DTO（志愿者 4 + 管理端 1），课程详情 DTO **不含** `correctOption`
- [x] 2.6 `docs/api_spec.yaml`：5 个端点 + 6 个 schema + 3 处枚举取值 + `TRAINING_NOT_COMPLETED`（enum 数组与 description 总表两处）

## 3. 后端：业务与门槛

- [x] 3.1 `TrainingService`：列表 / 详情 / 上报时长 / 判卷 / 管理端记录 + 两个门槛判定方法
- [x] 3.2 `DispatchBlockReason` 追加 `TRAINING_INCOMPLETE` 并更新引导优先级注释
- [x] 3.3 `ScoringService` 候选池过滤（参数传入，保持「不查库」契约）
- [x] 3.4 `DispatchService.assertVolunteerCanRespond` 兜底守卫（位置在 `wantsDispatch` 之前）
- [x] 3.5 `VolunteerService.getDispatchSummary` 下发 `TRAINING_INCOMPLETE`
- [x] 3.6 `PointReason.TRAINING_REWARD` + `PointService.awardTrainingCompletion`（幂等键以课程为轴）
- [x] 3.7 `CertReviewItemResponse.trainingCompleted`（批量查，不在 map 里逐条）+ 管理端记录端点
- [x] 3.8 `cert-review.html` 加培训列与按需展开的答题记录

## 4. 后端：测试

- [x] 4.1 `TrainingServiceTest` 14 条：判卷 / 门槛 / 发分幂等 / 学习时长 / 答案不泄漏 / 管理端记录
- [x] 4.2 `ScoringServiceTest` +2：未培训被过滤；`null` 与空集合含义相反
- [x] 4.3 `DispatchServiceTest` +2：兜底守卫抛 `TRAINING_NOT_COMPLETED`；顺序在 `wantsDispatch` 之前
- [x] 4.4 `VolunteerDispatchSummaryTest` +1：`TRAINING_INCOMPLETE` 下发且与 `NOT_VERIFIED` 共存
- [x] 4.5 `AuthzMatrixTest` 登记 5 个新端点（该门禁抓出它们本会落到 `anyRequest().authenticated()`）
- [x] 4.6 **三条核心不变式验红**：及格线放宽成 80% → 5 题用例红；`correctOption` 带进响应 →
      防泄漏用例红；去掉并发约束冲突处理 → 连跑 3 次全红，装回连跑 3 次全绿（证明不是 flaky）
- [x] 4.7 全量 **1302** tests / 0 failures / 1 skipped（改动前 1282，其中 4 条 drift gate 红。
      1301 → 1302 是 review 后补的并发首次交卷用例）

## 5. iOS：模型与服务

- [x] 5.1 `TrainingModels.swift`：枚举字段一律 `String?` + 归一化计算属性
- [x] 5.2 `TrainingService.swift`（`TrainingEndpoint` / `TrainingServing` / `TrainingService`）+ `AppState.training`
- [x] 5.3 `VolunteerDispatchNotAvailableReason.trainingIncomplete`（含 `allCases` 与 `displayText`）
- [x] 5.4 `ErrorCode.trainingNotCompleted` + 与「去传资质证件」区分开的文案
- [x] 5.5 `VolunteerPoints.reasonText` 加 `TRAINING_REWARD`（不加不会崩，所以最容易漏）
- [x] 5.6 `MockAPIClient+Training` + 路由 + `MockAPIClient+Profile` 下发 `TRAINING_INCOMPLETE`

## 6. iOS：界面

- [x] 6.1 `VolunteerTrainingView`（排法 C：门槛横幅永远在第一屏 + 课程清单）
- [x] 6.2 `VolunteerTrainingCourseView`：Markdown 正文 + 情景题 + 结果与逐题解释 + 只清错题的重答
- [x] 6.3 派单卡片的「去培训」按钮 —— 放在 `.combine` **之外**，否则 VoiceOver 够不到
- [x] 6.4 志愿者设置里的常驻入口（培训完成后入口不能消失，否则选修课再也找不到）
- [x] 6.5 学习时长在 `onDisappear` 上报增量；失败只记日志不弹框

## 7. iOS：测试与门禁

- [x] 7.1 `VolunteerTrainingTests` 14 条：告知 / 解码宽容 / 积分文案 / 答题闸 / Mock 全链路 / 错误码文案
- [x] 7.2 `validate-spec-coverage`、`validate-error-codes`、`validate-guard`（105 条）全过
- [x] 7.3 编译门禁 `build-for-testing` 通过
- [ ] 7.4 **真机跑测** —— iPhone 16 Pro 当前 `unavailable`，iPad Air 5 需要解锁并关闭自动锁定
- [ ] 7.5 按 `verified-on-one-device-is-not-verified`：在 PR 里写清只验了哪台

## 8. 收尾

- [x] 8.1 openspec 四份 artifact（proposal / design / tasks / specs）
- [x] 8.2 handoff 通报契约新增（后端 `docs/handoff.md`，三个口径变化 + 迁移执行顺序）
- [x] 8.3 独立 subagent code review（全报，自分 A/B 两档）—— 4 条 A 档，逐条复核后 3 条已修：
      契约漏 `trainingCompleted`、并发首次交卷报 500（已验红）、死方法；
      第 4 条是真机测试未跑（不是代码问题，见 7.4）。iOS 侧另修一条：错误文案指向了
      不存在的「我的」页面
- [x] 8.4a 后端 commit + push + PR（`blind-run-backend#261`）
- [ ] 8.4b iOS push + PR —— **被 8.4a 阻塞**：iOS 的 pre-push 门禁按后端 `origin/main`
      校验错误码与契约，`TRAINING_NOT_COMPLETED` 要等 #261 合并后才在那里。
      本地 3 个提交已就绪。⚠️ 不要用 `AIDRUN_SKIP_PREPUSH=1` 绕 —— 那会一次跳过全部 5 道门禁
- [ ] 8.5 **提醒运维**：迁移 `0043` 必须先于新 JAR 执行，并登记进 `migrations_applied.log`
