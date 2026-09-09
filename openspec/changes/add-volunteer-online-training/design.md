## 门槛为什么落在派单侧，而不是注册完成度

旧培训是注册的 `STEP_4`，未完成就出不了注册引导。本轮**刻意不那样做**。

后端 N139（2026-09-08）刚因为同一个形状出过合规缺陷：依法拒绝人脸的志愿者被 `isRegistrationCompleted` 永远关在注册引导里，而上传材料的入口在注册流程之外 —— 他永远够不到那一步。把培训塞进 `registrationCompleted` 会把这个坑再挖一次：走完实名的人卡在引导页，而培训入口在「我的」里。

所以本轮：`registrationCompleted` 不等培训，培训门槛只影响**能不能接单**。两个布尔正交。

## 三处口径必须一致，且展示那一处不能省

`verified` 的既有约定是三处一致（`ScoringService` 过滤 + `DispatchService` 守卫 + `getDispatchSummary` 展示），`ScoringService.java:194` 的注释明确写着「三处一致，勿单独删除」。培训照同样的形状落。

**展示那一处是这次最容易被当成可选项、而实际最要紧的一处。** 因果链是：

```
必修没做完 → 不进候选池 → 收不到任何派单推送
          → 首页那句「已上线，等待系统派单」永远不会变
          → 而屏幕上没有任何东西说明为什么
```

`DispatchBlockReason` 这个枚举存在的全部意义就是让这种状态可解释（它的类注释原话：「前端按枚举值给出精确引导，而非一句模糊的『暂时无法接单』」）。所以客户端不仅要认得 `TRAINING_INCOMPLETE`，还要在同一处给出去处 —— 只念一句「尚未完成必修培训」而没有按钮，就是装饰性提示。

⚠️ 本仓库今天的 `NOT_VERIFIED` 就只有一行字、没有去处。那是既有缺口，本轮**不夹带修它**，但也不复制它。

## 为什么 `ScoringService` 不注入 `TrainingService`

`ScoringService` 的类注释第一行写着「纯函数式、无状态，不操作 Redis/DB」。注入一个查库的 service 会当场破掉这个契约。

所以走既有的 `declinedVolunteerIds` 那条路：`DispatchService` 批量查好集合，作参数传进去。

🚩 **该参数 `null` 与空集合含义相反**，这是设计上的坑，两处都钉住了：
- `null` = 调用方明确不参与培训过滤（历史重载与不关心培训的单测）
- `Set.of()` = 一个人都没完成培训 ⇒ **候选池清零**

单测 `nullTrainedSetSkipsTheTrainingFilterEntirely` 同时断言这两种，理由写在用例里：有人为了让测试变绿把 `null` 改成 `Set.of()` 时，只断言 null 的那半条会照常绿，而生产上那等于把所有人挡在门外。

## 批量 vs 单人：两个方法都要留

`TrainingService` 暴露两个同口径方法：

| 方法 | 用在哪 | 为什么不能只留一个 |
|---|---|---|
| `hasCompletedRequired(userId)` | 接单守卫、首页派单摘要 | 一次只判一个人 |
| `completedRequiredUserIds(userIds)` | **派单候选池** | 一次筛几十人，循环里调单人版就是 N+1，而派单是在盲人等着的时候跑的 |

两个查询的 WHERE 条件必须逐字一致（`isRequired` + `isActive` + `completedAt IS NOT NULL`）。不一致的后果正是上面那条「首页说能接单但收不到派单」。

`countCompletedRequiredGroupedByUserId` 的 `getOrDefault(userId, 0L)` 不可省：一门必修都没通过的人**不会出现在 GROUP BY 结果里**，漏了这一点会把新志愿者当成已完成放进候选池。用例 `batchGateDoesNotSilentlyPassUsersWithNoProgress` 钉住。

## `submitQuiz` 为什么没有 `@Transactional`

不是遗漏。`PointService.insert` 的类注释写明「调用方不要给本路径套外层事务」：幂等键撞车时它 catch 得住并返回 null（正常路径），但如果外面包了事务，那次约束冲突会把**外层事务**标成 rollback-only，日志照打，而外层在提交时抛 `UnexpectedRollbackException`。「catch 了就等于降级了」在那种形状下不成立。

因此写入顺序有讲究，**不可重排**：

1. `TrainingProgress`（门槛相关的权威事实）
2. `TrainingQuizAttempt`（记录）
3. 发分（有自己的幂等键）

反过来（先写 attempt）中途失败时，用户会被告知「通过了」而门槛仍然拦着他 —— 那是最难排查的一种不一致。当前顺序下最坏情况是「已通过但少一条答题记录」，客服少看一行，不影响任何人的资格。

## 及格线：全对，而不是百分比

产品决策。业界锚点是 85 分，本项目更严。

⚠️ **这条的用例一开始是假绿的**，值得记下来：最初只用 2 道题验「错一题不通过」——而 2 题时错 1 题 = 50%，在 100% 和 80% 两种及格线下都不通过，**用例分辨不出及格线被偷偷放宽**。RED 实测（把判定改成 `correctCount * 100 >= size * 80`）时那条用例照常绿，才补了 5 题的 `eightyPercentIsStillNotAPass`。

## 学习时长：时间戳差值，不用定时器

政策要求记录学习时长。实现取「进入课程页 → 离开」这一对时间戳的差值，在 `onDisappear` 上报增量。

不用定时器的理由：定时器要处理进后台、被电话打断、页面被 push 覆盖三种情况，而这里只需要一个近似值。

⚠️ 也**不用 `scenePhase`**：进后台不代表离开这门课，回来还在同一页。把生命周期事件当成「用户走了」会算错（同 `permission-alert-makes-scenephase-inactive` 的教训形状）。

⚠️ 上报失败**只记日志不弹框**：学习时长是合规记录，不是用户此刻在等的结果，为它打断人不值得。但也不用静默 `try?` —— 那样后端一直收不到时长时没人会发现。

**刻意不做「最短阅读时间」门槛**：那会把考核从「会不会」变成「熬够时间没有」，而客户端上报的秒数本来就不可信。真正的门槛是全对通过考核。

## 正确答案不出服务端

`TrainingQuestion.correctOption` 存在于实体和数据库里，判卷只在 `TrainingService.submitQuiz`。所有响应 DTO 都没有这个字段，`courseDetail` 组装时显式剥掉。

Mock 侧同构：`MockTrainingQuestion` 有 `correctOption`，`handleGetTrainingCourseDetail` 不带它。**Mock 多给了答案就等于 Mock 比真实后端宽松，而 UI 是照着 Mock 调的。**

两侧都有验红过的用例：后端 `courseDetailNeverLeaksTheCorrectAnswer`（把字段加进 DTO 当场红），iOS `testMockCourseDetailNeverCarriesTheCorrectAnswer`。

## Mock 默认「一门课都没学」

`MockAPIClient.trainingProgress` 初始为空，且 `MockAPIClient+Profile` 的 `notAvailableReasons` 会因此产出 `TRAINING_INCOMPLETE`。

这是刻意的：Mock 环境下第一次进志愿者首页就应该看到门槛，否则「未完成培训 → 首页说清原因 → 点『去培训』」整条主路径在开发期和 UI 测试里一次都走不到 —— `MockAPIClient+Profile` 那段代码上方的注释原话就是「Mock 不得造后端没有的原因值，否则某些分支永远跑不到（曾因此漏掉 `NOT_VERIFIED` 解码 bug）」，反过来同样成立。

与培训无关的志愿者用例在 setUp 里调 `completeAllRequiredTrainingForTesting()` 即可。

## 课程内容：迁移种子数据，没有管理端 CRUD

`ponytail:` 改一个错字要发一次版，这是已知取舍。升级路径是加回旧设计里那 3 条 `POST/PUT/DELETE /api/admin/training/courses`（git 历史里有原貌）。

首批内容写的是**真内容不是占位符** —— 空课程等于模块不可测，而「敬请期待」页正是 `guard.mjs` 的 `placeholder-promise` 规则立起来的原因。素材来自调研里逐句核对过原文的两个来源（人民政协网 2023-12-04 的国内跑团报道、Achilles 的 guide 资料），运营随时整份替换。**没内容的课不进种子表**，而不是进了表再显示占位符。

## 表名用单数，与旧表不同名

旧表是 `training_courses`（复数），本仓库其余业务表一律单数。新表跟单数走，副作用是好的：万一某个环境的 `0006` 没跑干净、旧表还在，两者也不会撞在一起。

`training_progress.status` 用 `VARCHAR` 而不是原生 ENUM —— `0040` / `0042` 两次坑都出在原生 ENUM 上（`validate` 不比对成员，加值当场 `1265 Data truncated`）。新表没有历史包袱，用 VARCHAR 就永远不会再踩。
