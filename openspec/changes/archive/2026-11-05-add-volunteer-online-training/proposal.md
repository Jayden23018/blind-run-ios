## Why

志愿者线上培训 2026-07-29 被**整体移除**：后端迁移 `0006_drop_training.sql` 真删了 4 张表，`docs/api_spec.yaml` 里 8 个端点全部删除；前端对应的变更 `2026-07-31-remove-volunteer-registration-training` 已归档，注册从 3 步变 2 步。当时的判断是「培训是个走过场的门槛，两端一起去掉」。

产品于 2026-09-09 决定重新加回，形态从旧的「图文 + 视频 + 多种题型 + 管理端 CRUD」收窄为「Markdown 图文 + 情景单选题」。

**依据不是体验判断，是政策要求**。中央社会工作部《关于志愿者招募和培训的工作指引（试行）》（2025-06-05）原文四条：

> 对需要专门知识、技能的志愿服务坚持先培训再上岗。志愿者在**培训合格后**参与志愿服务活动。
> 可采用**线上**或线下的笔试、面试，以及**情景模拟**、实地演练、团队活动等形式进行考核。
> 考核通过的，可**颁发培训证书**并根据安排参加志愿服务；考核不通过的，以适当方式反馈。
> 及时、如实记录志愿者的培训情况，内容包括但不限于：培训的主题名称、主要内容、举办培训的单位、培训日期和**学习时长**等。

助盲陪跑毫无疑问属于「需要专门知识、技能」——牵引绳指令、路面口头提醒、突发情况处置都是。⇒ **「未完成必修培训不能接单」是政策要求的形状，不是我们自己加的门槛。**

最后一条直接决定了数据模型：**必须记录学习时长**。旧实体 `TrainingProgress` 没有这个字段 —— 不查那份文件不会想到要存它。完整调研见 `docs/research/volunteer-training-model-20260909.md`。

## What Changes

- **必修硬门槛落三处，不造第二套机制**。沿用 `verified` 的既有三处约定：后端 `ScoringService` 候选池过滤（批量一条 SQL）+ `DispatchService.assertVolunteerCanRespond` 兜底守卫 + `getDispatchSummary` 的 `DispatchBlockReason.TRAINING_INCOMPLETE` 展示。三处口径必须一致，否则会出现「首页说你能接单，但你永远收不到派单」这种查不出来的缺陷。
- **展示那一处是主角，不是附带**。未完成培训的人被挡在候选池外，他打开可服务开关、首页显示「等待系统派单」，然后永远等不到一张单 —— 不下发这条原因，那个状态在屏幕上没有任何东西能解释。前端因此在派单卡片里给「去培训」按钮，而不是只多一行字。
- **及格线是全对，可无限重考**。业界锚点其实是 85 分（国内跑团的陪跑员笔试口径），本项目取更严的全对：每道题都是人身安全底线，「对 4/5」意义不大。
- **答错必须给逐题解释**。「全对才过 + 无限重考」的组合下只给题号，用户唯一的策略就是改选项猜到过 —— 那样这个模块从培训退化成一道验证码。
- **视频不做**。Achilles International 确实用 guide training video，但它是**审核通过后邮件单向发送、不承担考核职责**的，与我们要产出「合格/不合格」的用途不同；拿它论证 App 内视频课是错引。视频还要托管、防拖拽、配字幕（无障碍 App 里字幕是必需不是可选）。
- **必修不发分，选修才发**（`PointReason.TRAINING_REWARD`）。给「达到最低要求」发奖会让积分失去意义。
- **不进注册流程**。走完注册（含拒绝人脸的替代路径）也可能还没培训，`registrationCompleted` 不等它；路径因此是 `/api/volunteer/training/*` 而不是旧的 `/api/volunteer/registration/training/*`。
- **客服后台能看逐课进度与每次答题记录**。走「拒绝人脸 → 二要素 + 人工审核」替代路径的志愿者，「是不是本人」没有任何机器核验过（后端 N139），人工审核是唯一判断点 —— 答题过程是那一步能拿到的少数行为证据之一。

## Capabilities

### Added Capabilities

- `volunteer-online-training`：志愿者线上培训课程、学习时长记录、情景题考核、培训证书，以及「必修未完成不得接单」这道派单门槛与它的告知义务。

## Impact

- **后端**（`demo` 仓库，分支 `feat/volunteer-online-training`）：迁移 `0043` 新建 4 张表 + 种子课程；`TrainingService` / `TrainingCourseRepository` 等 4 个 repository / 5 个 DTO / `VolunteerTrainingController`；`DispatchBlockReason` 追加 `TRAINING_INCOMPLETE`；`PointReason` 追加 `TRAINING_REWARD`；`ErrorCode` 追加 `TRAINING_NOT_COMPLETED`；`ScoringService` / `DispatchService` / `VolunteerService` / `AdminVolunteerService` 各接一处；管理端 `cert-review.html` 加一列 + 培训记录展开。
- **iOS**：新增 `TrainingModels` / `TrainingService` / `VolunteerTrainingView` / `VolunteerTrainingCourseView` / `MockAPIClient+Training`；`VolunteerDispatchNotAvailableReason` 加 `.trainingIncomplete`；`ErrorCode` 加 `.trainingNotCompleted`；`VolunteerPoints.reasonText` 加 `TRAINING_REWARD`；`AppState.training`；派单卡片与志愿者设置各加一个入口。
- **契约**：`docs/api_spec.yaml` 加 5 个端点 + 6 个 schema + 3 处枚举取值 + 1 个错误码（enum 数组与 description 总表两处）。
- **发版顺序**：迁移 `0043` **必须先于新 JAR 执行**（生产 `ddl-auto=validate`，缺表起不来），且要登记进服务器的 `migrations_applied.log`，否则 `deploy.sh` 的迁移闸门会 `exit 1`。
- **不在本轮**：管理端课程 CRUD（内容走迁移种子数据，改错字要发版，已知取舍）；培训有效期与复训（本轮永久有效）；派单优先级激励。
