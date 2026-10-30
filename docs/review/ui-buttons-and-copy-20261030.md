# 按钮外观与界面文案复核（2026-10-30）

- 对象：iOS `origin/main` `b589664d`。
- 方法：① 脚本盘点全部按钮写法；② iPhone 16 Pro（iOS 27.0.1）真机巡游 41 屏，得 77 个附件；③ 复核 10-28 文案审查的 37 条建议；④ 临时用例量「保存」与「紧急呼叫」的位置。
- 真机结果：`ScreenTourTests` `passed=40 failed=1`。失败的是 `testTour_B11`，报错 `Failed to get launch progress`，App 没启动起来，与界面无关。走的是进程内 Mock。
- 限制：
  - 陪跑员注册流程、证书上传、积分页不在巡游里，这几处只读了代码。
  - 只验了 iPhone，没验 iPad。
  - 只验了默认字号和浅色。

## 0. 结论

**最要紧的不是好不好看：盲人端「我的 → 个人资料」的「保存」被「紧急呼叫」盖住了。** 真机量到「保存」`y 715–779`、「紧急呼叫」`y 723–787`，64pt 高的按钮有 56pt 被盖住，只露 8pt。按「保存」的位置，按到的是紧急呼叫。

主流程（首页、下单、订单页、跑步中、完成页头卡）已经有统一设计。基础款集中在二级页和失败状态：设置、资料、紧急联系人、跑后记录、重试按钮。

## 1. 问题清单

| # | 级别 | 问题 | 证据 | 状态 |
|---|---|---|---|---|
| 1 | A | 红色「紧急呼叫」在「我的」每一层都常驻 | `BlindRunnerTabView.swift:165` 挂在 `NavigationStack` 外层，所以二级页也有；巡游 B33–B35 | 负责人 2026-09-16 拍板的结果，要改需重新定 |
| 2 | A | 「保存」被红条盖住 56pt | `ProfileModule.swift:306` 页内底栏与外层红条叠在一起；真机 frame 见第 0 节；`isHittable` 报 true，是假象 | 新发现，无 issue |
| 3 | A | 紧急联系人每位 2–3 行裸文字，每行 64pt，联系人多时操作比内容长 | `EmergencyContactsView.swift:462-489`；#565（10-30 合入）为满足 64pt 改成现在这样 | 新发现，无 issue |
| 4 | B | 「重复当前状态」是一行裸文字，同一组件全 App 有多种外观 | `EmergencyContactsView.swift:328`；#527 B 档 | #527 |
| 5 | B | 灰底粗黑字的手写按钮，不属于任何组件，看着像输入框 | `ProfileModule.swift:426`、`:620` | 新发现 |
| 6 | B | 同屏两个主按钮：蓝「提交评价」+ 黄「完成」 | 巡游 B19-bottom；`BlindOrderStatusView.swift` | 新发现 |
| 7 | B | 系统 `.bordered` 灰胶囊，发布包 9 处 | 见第 2 节；另有帮助页灰块「停止播报」 | 新发现 |
| 8 | B | 第三级文字按钮字号、颜色、排法不一，有的蓝有的灰，有的两个并排 | 见第 2 节 | 新发现 |

⚠️ 第 1 条不能直接删：`activateSOS()` 先切到「我的」，靠这条红条显示云端求助失败和兜底拨号（`BlindRunnerTabView.swift:208-233`）。帮助页也写着平时入口在「我的」。

## 2. 按钮写法盘点

| 写法 | 数量 | 判断 |
|---|---|---|
| `PrimaryButton(` | 43 | 有设计 |
| `FlowActionButton(` | 31 | 有设计 |
| `OutlineSecondaryButtonStyle` | 4 | 好用，但只用了 4 处，是最该推广的一种 |
| `TextButtonStyle` | 8 | 单个做附带操作可以；问题 3 是把它竖排当操作区 |
| `.bordered` | 18，其中 9 处仅调试 | **发布包 9 处是系统默认样式** |
| `.plain` | 36 | 大多包着自绘内容，不等于没设计 |

**发布包的 9 处 `.bordered`**：`SessionExpiryNotice.swift:64`、`VolunteerProfileFirstScreenView+Dispatch.swift:39`、`VolunteerProfileFirstScreenView+Todo.swift:87`、`:103`、`VolunteerOrderFlowViews.swift:708`、`VolunteerRunRecordView.swift:472`、`RunnerRunRecordView.swift:584`、`:620`、`BlindBookingView.swift:1936`。

**字体颜色临时写在调用点的文字按钮**：`VolunteerRegistrationFlowView.swift:1463`、`:1480`、`:1490`、`:1631`、`:1644`，`PartnerListViews.swift:239`、`:278`，`BlindOrderStatusView.swift:2835`、`:2892`、`:3429`，`VolunteerOrderFlowViews.swift:2913`，`VolunteerProfileFirstScreenView+Impact.swift:36`，`BlindIdentityVerificationView.swift:382`。

### 查过了不是问题

- 列表里的红字「退出登录」「删除账户」：iOS 设置页的标准做法。
- 「求助与安全」描边红按钮、陪跑员右上「求助」胶囊：有设计，两端分工是 `design-direction.md` §6.1 的决定。
- 灰胶囊「模拟志愿者接单」：调试面板，不进发布包。
- 盲人端次级操作竖排、64pt：无障碍硬规则，不算丑。

## 3. 文案

10-28 已审过（#558，Notion 报告）。本轮在 `b589664d` 上复核：

- **37 条改写建议还有 36 条没改**，只有「说完再点一下就好」已不在代码里。
- 字符串里「您」17 处、「一单」65 处、「没能」33 处、「聊聊」6 处、「试试」4 处。
- 按钮类字符串约 240 条，脚本筛出 57 条 ≥8 字或带标点。这个数字混入了读屏标签，只当线索。
- 37 条之外新增的典型例子：

| 原文 | 位置 | 建议 |
|---|---|---|
| 接下这一单并通知跑者 | `VolunteerOrderFlowPage.swift:536` | 接受预约 |
| 接下这一单并进入服务流程 | `VolunteerInviteSheet.swift:410` | 接受预约 |
| 我在他身边，去处理 | `SafetyModule.swift:369` | 我在现场，前往处理 |
| 暂时没能读到课程内容。 | `VolunteerTrainingCourseView.swift:77` | 课程加载失败 |
| 这条记录没能生成。 | `VolunteerRunRecordView.swift:622` | 记录生成失败 |
| 把这次行程告诉家人 | `RunPlanShareMessage.swift:14` | 分享行程给家人 |

- 动手前要定 #558 留下的三件事：陪跑方叫什么、你还是您、感谢类文案留不留。`#567` 已在把盲人端统一成「陪跑员」，文案批次要排在它后面。

## 4. 建议的修法

- **按钮只留四级**：实心主按钮（每屏一个）→ 描边次按钮 → 第三级文字按钮 → 列表行。9 处 `.bordered` 和 2 处灰块并入描边次按钮。
- **紧急联系人**：行里只放姓名、主联系人标记、掩码号码、关系，行尾小箭头进编辑页；「设为主联系人」和「删除联系人」放编辑页。本仓库有先例（#481）。
- 外部依据见 `docs/research/ios-design-repos-and-list-row-actions-20261030.md`。
