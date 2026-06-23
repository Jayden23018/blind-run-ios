# UI Reference Audit: Legacy Flutter

本文审计旧 Flutter 项目 `/Users/jerry/A/blind-run/blind-run-frontend/lib/`，仅作为 AidRun / 助盲跑 Swift 原生 iOS MVP 的 UI 行为参考。

旧 Flutter 不是 source of truth。若旧 UI、旧接口、旧状态机与 `AGENTS.md`、`docs/01-10`、`openspec/changes/remove-local-backend-use-cloud-only/` 冲突，必须以后者为准。

本审计不迁移 Flutter 代码，不生成 Swift，不生成 Figma，不把旧 Flutter 架构、状态名、API 路径或组件实现作为新版本依据。

## 1. 审计边界

纳入审计：

- `lib/features/auth/loading_page.dart`
- `lib/features/auth/login_page.dart`
- `lib/features/role_selection/role_selection_page.dart`
- `lib/features/blind/blind_dashboard_page.dart`
- `lib/features/blind/request_run_page.dart`
- `lib/features/blind/place_search_page.dart`
- `lib/features/blind/blind_active_run_page.dart`
- `lib/features/volunteer/volunteer_dashboard_page.dart`
- `lib/features/volunteer/volunteer_active_run_page.dart`
- `lib/features/settings/settings_page.dart`
- `lib/core/navigation/app_router.dart`
- `lib/core/widgets/common_widgets.dart`
- `lib/core/widgets/blind_page_scaffold.dart`
- `lib/core/widgets/amap_map_view.dart`

旧 Flutter Demo 截图已归档在 `docs/ui/legacy-screenshots/`（盲人端 12 张、志愿者端 10 张），完整索引见 [`00-index.md`](legacy-screenshots/00-index.md)。

排除：

- 旧项目 `src/` React / Vite / Firebase demo。
- 旧项目内历史 OpenSpec 作为 source of truth。
- Flutter、Riverpod、go_router、Flutter AMap plugin、MethodChannel、WebSocket 实现细节。

## 2. 旧页面清单

| 旧页面 | 旧路由 | 主要用途 | 当前 MVP 对应 |
| --- | --- | --- | --- |
| LoadingPage | `/loading` | 启动和会话恢复中间页 | App 启动会话恢复状态 |
| LoginPage | `/login` | 手机号、验证码登录 | 页面 1：登录页 |
| RoleSelectionPage | `/role-selection` | 选择盲人跑者或志愿者 | 页面 2：角色选择页 |
| BlindDashboardPage | `/blind` | 盲人首页，有/无活跃订单切换主操作 | 页面 4：盲人首页 |
| RequestRunPage | `/blind/request` | 创建预约：选地点、选时间、提交 | 页面 5：创建预约页 |
| BlindPlaceSearchPage | `/blind/request/place` | 地点文字/语音搜索与候选选择 | 页面 5 的地点选择子流程 |
| BlindActiveRunPage | `/blind/run/:id` | 盲人订单状态、取消、完成评价 | 页面 6、7、8 的旧合并形态 |
| VolunteerDashboardPage: 地图 Tab | `/volunteer` | 地图、可服务开关、附近需求列表 | 页面 10、11 的旧合并形态 |
| VolunteerDashboardPage: 历史 Tab | `/volunteer` | 历史行程列表 | 页面 14：志愿者服务记录页 |
| VolunteerDashboardPage: 商城 Tab | `/volunteer` | 积分余额和商品网格 | 页面 15：积分/商城占位页 |
| VolunteerDashboardPage: 我的 Tab | `/volunteer` | 志愿者资料、指标、设置、退出 | 页面 9、16 的部分内容 |
| VolunteerActiveRunPage | `/volunteer/run/:id` | 志愿者接单后执行页和结算页 | 页面 12、13 的旧合并形态 |
| SettingsPage | `/settings` | 双角色资料编辑、紧急联系人、退出 | 页面 3、9、16 的旧合并形态 |
| 紧急联系人弹窗 | 设置页内 Dialog | 新增/编辑/删除/设为主要联系人 | 页面 3 的紧急联系人表单应内聚 |

## 3. 页面审计

### LoadingPage

| 维度 | 审计结果 |
| --- | --- |
| 截图参考 | 无对应旧截图 |
| 功能目标 | 启动时展示加载状态，等待本地 session 和路由守卫完成。 |
| 主要布局 | 简单 `Scaffold` + 居中加载反馈。 |
| 按钮和输入 | 无。 |
| 跳转关系 | 根据登录态和角色由路由守卫进入登录、角色选择、盲人首页或志愿者首页。 |
| 适合保留 | 启动期间用轻量中间状态避免白屏。 |
| 不适合新版本 | 不迁移 go_router/Riverpod 守卫实现。 |
| 无障碍重设计 | 加载状态应有简短 VoiceOver 文案，例如"正在启动助盲跑"。 |

### LoginPage

| 维度 | 审计结果 |
| --- | --- |
| 截图参考 | 无对应旧截图（旧 demo 录屏未单独截取登录页） |
| 功能目标 | 手机号 + 验证码登录，验证码发送后启用登录按钮。 |
| 主要布局 | 黑色背景，居中单列表单，顶部品牌标题，手机号输入、发送验证码按钮、验证码输入、登录按钮、错误文本。 |
| 按钮和输入 | 手机号输入、验证码输入、"发送验证码"、"登录"。 |
| 跳转关系 | 登录成功后按旧 `role` 跳转到 `/blind`、`/volunteer` 或 `/role-selection`。 |
| 适合保留 | 黑底高对比、单列布局、明确 loading 文案、错误提示。 |
| 不适合新版本 | 旧流程是发送验证码和校验验证码两步；当前 API 以 `POST /api/auth/phone-login` 为准。旧页面没有环境切换入口。 |
| 无障碍重设计 | 必须补齐手机号和验证码的 `accessibilityLabel` / `accessibilityHint`，验证码应按当前规格支持 6 位填完后提交或手动登录。 |

### RoleSelectionPage

| 维度 | 审计结果 |
| --- | --- |
| 截图参考 | 无对应旧截图（旧 demo 录屏未单独截取角色选择页） |
| 功能目标 | 选择"我是盲人跑者"或"我是志愿者"。 |
| 主要布局 | 黑色背景，大标题，两个纵向大卡片按钮；盲人卡片黄色，志愿者卡片深色。 |
| 按钮和输入 | "我是盲人跑者"、"我是志愿者"。无输入项。 |
| 跳转关系 | 选择后提交角色，旧实现直接进入 `/blind` 或 `/volunteer`。 |
| 适合保留 | 大面积角色卡片、强对比、角色说明副标题。 |
| 不适合新版本 | 旧代码未体现当前 MVP 的首次资料页分流和活跃订单角色切换拦截 UI。 |
| 无障碍重设计 | 每张角色卡片应是单个 VoiceOver 元素，文案按 `docs/05-page-specs.md` 使用完整 label。 |

### BlindDashboardPage

| 维度 | 审计结果 |
| --- | --- |
| 截图参考 | `legacy-screenshots/blind-runner/01-blind-home.png` |
| 功能目标 | 盲人首页：无活跃订单时发起预约，有活跃订单时查看当前订单。 |
| 主要布局 | 黑色背景，顶部标题和设置/退出按钮，中间状态卡片，下方一个超大主按钮。 |
| 按钮和输入 | "设置"、"退出登录"、"发起预约"或"查看当前订单"。无输入项。 |
| 跳转关系 | "发起预约"到 `/blind/request`；"查看当前订单"到 `/blind/run/:id`；设置到 `/settings`。 |
| 适合保留 | 一屏一个主任务、超大按钮、订单状态摘要卡片、状态变化 TTS 思路。 |
| 不适合新版本 | 固定底部"AI语音助手"违反当前 non-goals；退出登录缺少二次确认；首页缺少当前规格要求的小地图、当前位置描述和"重复当前状态"按钮。 |
| 无障碍重设计 | 保留大按钮方向，但必须增加"重复当前状态"；退出登录必须二次确认；地图和状态卡片需要 VoiceOver 可读摘要。 |

### RequestRunPage

| 维度 | 审计结果 |
| --- | --- |
| 截图参考 | `legacy-screenshots/blind-runner/02-create-booking-1.png` ~ `05-create-booking-4.png` |
| 功能目标 | 创建盲人跑步预约，旧实现简化为地点 + 出发时间。 |
| 主要布局 | 顶部返回和标题；大按钮进入地点搜索；出发时间卡片；语音时间按钮；时间 ChoiceChip；底部确认预约按钮。 |
| 按钮和输入 | "返回首页"、"选择/重新选择地点"、"语音输入时间"、预设时间 Chip、"确认预约"。无 DatePicker。 |
| 跳转关系 | 地点按钮到 `/blind/request/place`；提交成功旧实现回到 `/blind`。 |
| 适合保留 | 分步降低认知负担，先地点后时间；地点选择用大按钮；提交前 disabled 状态清晰。 |
| 不适合新版本 | "现在出发""明天上午""今天晚上"和语音时间解析与当前预约至少 30 分钟后、DatePicker 规则冲突；缺少目的地/路线、预计时长、预计距离、配速、同性志愿者、备注等当前表单项；提交后应进入订单状态页。 |
| 无障碍重设计 | 时间必须使用系统 DatePicker；语音输入只用于地点描述、路线备注等文本字段；提交按钮 64pt+；定位拒绝时应阻止创建并提供去设置指引。 |

### BlindPlaceSearchPage

| 维度 | 审计结果 |
| --- | --- |
| 截图参考 | `legacy-screenshots/blind-runner/04-create-booking-3.png`（地点搜索子页面） |
| 功能目标 | 搜索并选择出发地点，支持文字搜索和语音搜索。 |
| 主要布局 | 顶部返回和标题；搜索输入卡片；语音状态文案；语音搜索按钮；结果列表卡片。 |
| 按钮和输入 | 地点关键词输入、搜索 icon、语音搜索地点、每个结果的"选择"。 |
| 跳转关系 | 选择候选后 `pop(place)` 返回预约页。 |
| 适合保留 | 地点搜索独立子流程、搜索结果逐条读出地点和地址、语音失败回退文字输入。 |
| 不适合新版本 | 旧实现可在未配置 Web key 时回退本地演示 POI；新版本必须明确区分真实定位/搜索与 demo fallback，不能把 fallback 当真实业务结果。 |
| 无障碍重设计 | 搜索框、麦克风按钮、候选行都应有 label/hint；结果为空时读出"未搜索到相关地点"。 |

### BlindActiveRunPage

| 维度 | 审计结果 |
| --- | --- |
| 截图参考 | `legacy-screenshots/blind-runner/06-order-matching-1.png` ~ `12-service-completed-result.png`（旧版合并页，对应新版 P6/P7/P8） |
| 功能目标 | 盲人查看当前订单状态、志愿者联系方式、订单信息；旧实现也承载完成评价。 |
| 主要布局 | 顶部返回和标题；大号状态卡片；志愿者联系方式卡片；订单信息卡片；可取消状态下显示取消按钮；完成后显示三档评价按钮。 |
| 按钮和输入 | "返回主页"、"取消行程"、三档评价"好评/一般/差评"。无星级评分输入。 |
| 跳转关系 | 返回主页到 `/blind`；取消后回 `/blind`；评价后回 `/blind`。 |
| 适合保留 | 5 秒轮询、状态变化 TTS、状态大字卡片、联系方式与订单信息分区。 |
| 不适合新版本 | 旧状态 `pendingMatch/pendingAccept/inProgress/driverEnRoute/driverArrived/rematching/noVolunteer` 不可继承；缺少 `arrived` 时盲人"确认开始服务"；缺少 accepted/arrived/in_progress 的一键求助；取消没有二次确认和固定原因；完成评价是三档而非 1-5 星；缺少 terminal `emergency` 页面。 |
| 无障碍重设计 | 拆成订单等待页、服务中页、完成/评分页；每页必须有"重复当前状态"；危险操作二次确认；状态文案使用当前 MVP 状态中文。 |

### VolunteerDashboardPage: 地图 Tab

| 维度 | 审计结果 |
| --- | --- |
| 截图参考 | `legacy-screenshots/volunteer/01-volunteer-home.png`、`legacy-screenshots/volunteer/03-available-orders.png` |
| 功能目标 | 志愿者查看附近需求、开关可服务、地图定位、接单。 |
| 主要布局 | 全屏地图，顶部在线状态卡片和 Switch，右侧回到当前位置按钮，底部半屏抽屉展示"附近需求"列表。 |
| 按钮和输入 | 可服务 Switch、"回到当前位置"、"婉拒"、"立即接单"、当前行程入口。无文本输入。 |
| 跳转关系 | 当前行程或接单成功后进入 `/volunteer/run/:id`。 |
| 适合保留 | 地图 + 底部列表的志愿者浏览模型、可服务开关、定位失败状态文案、回到当前位置按钮。 |
| 不适合新版本 | WebSocket/实时派单、15 秒位置心跳、实时连接状态不是当前 MVP；"婉拒"不在当前 MVP 必需范围；接单前显示 `blindUserPhone` 违反接单前隐藏联系方式规则；可服务开关文案"推送"容易暗示实时推送。 |
| 无障碍重设计 | 订单行需读出昵称、地点、预约时间、距离；不可用/未批准/无定位时接单按钮禁用并说明原因；接单前不得展示电话。 |

### VolunteerDashboardPage: 历史 Tab

| 维度 | 审计结果 |
| --- | --- |
| 截图参考 | `legacy-screenshots/volunteer/08-service-records.png` |
| 功能目标 | 展示志愿者历史行程。 |
| 主要布局 | AppBar + 纵向历史卡片列表。 |
| 按钮和输入 | 无主要按钮；空状态只有文案。 |
| 跳转关系 | 旧实现无只读详情入口。 |
| 适合保留 | 简洁倒序记录卡片。 |
| 不适合新版本 | 旧完成积分显示 `+50`，当前必须是 `+100`；缺少"去接单"空状态按钮。 |
| 无障碍重设计 | 每条记录应读出时间、盲人昵称、地点、状态和积分。 |

### VolunteerDashboardPage: 商城 Tab

| 维度 | 审计结果 |
| --- | --- |
| 截图参考 | `legacy-screenshots/volunteer/09-points-shop-placeholder.png` |
| 功能目标 | 展示积分余额和商品网格。 |
| 主要布局 | 大标题、积分余额卡片、两列商品网格。 |
| 按钮和输入 | 每个商品有"兑换"按钮。 |
| 跳转关系 | 旧实现无真实跳转。 |
| 适合保留 | 积分余额大数字和占位商品视觉可参考。 |
| 不适合新版本 | 当前 MVP 只是积分/商城占位，不做真实兑换；旧固定余额 `1,250 分` 不应继承。 |
| 无障碍重设计 | 商品卡片应读出"敬请期待"，不要提供可误解为真实兑换的按钮。 |

### VolunteerDashboardPage: 我的 Tab

| 维度 | 审计结果 |
| --- | --- |
| 截图参考 | `legacy-screenshots/volunteer/02-volunteer-profile-verification.png`、`legacy-screenshots/volunteer/10-settings.png` |
| 功能目标 | 展示志愿者资料、认证状态、统计指标、设置和退出入口。 |
| 主要布局 | 头像字母、昵称、认证状态、三项指标、菜单卡片。 |
| 按钮和输入 | "设置"、"退出登录"。无输入项。 |
| 跳转关系 | 设置进入 `/settings`；退出后到 `/login`。 |
| 适合保留 | 资料摘要和服务指标卡片。 |
| 不适合新版本 | 退出缺少二次确认；志愿者认证页应是独立首次流程，不应只散落在我的/设置页。 |
| 无障碍重设计 | 退出必须二次确认；认证状态、积分、可接订单应有明确 label。 |

### VolunteerActiveRunPage

| 维度 | 审计结果 |
| --- | --- |
| 截图参考 | `legacy-screenshots/volunteer/04-order-detail-after-accept.png` ~ `07-complete-service-summary.png` |
| 功能目标 | 志愿者接单后查看地图和订单信息，推进旧状态，完成后显示结算。 |
| 主要布局 | 地图全屏背景；顶部返回圆按钮；底部白色抽屉展示状态、跑者信息、地点时间、主动作；完成时显示结算卡片。 |
| 按钮和输入 | 返回、旧动作"我已出发 / 我已到达集合点 / 结束行程"、完成后"返回大厅"。无服务总结输入。 |
| 跳转关系 | 返回到 `/volunteer`；完成后返回 `/volunteer`。 |
| 适合保留 | 地图作为主背景、底部操作面板、接单后才展示电话、完成结算反馈。 |
| 不适合新版本 | 旧动作链是 `inProgress -> driverEnRoute -> driverArrived -> completed`，与当前 `accepted -> arrived -> in_progress -> completed` 冲突；缺少等待盲人确认开始的状态；结束服务缺少二次确认和可选服务总结；缺少取消和一键求助；结算积分是 `+50`。 |
| 无障碍重设计 | 按当前状态显示"我已到达""等待盲人确认""结束服务"；危险操作二次确认；完成后显示 `+100` 积分。 |

### SettingsPage

| 维度 | 审计结果 |
| --- | --- |
| 截图参考 | `legacy-screenshots/volunteer/10-settings.png` |
| 功能目标 | 双角色设置页：编辑资料、紧急联系人、可服务开关、退出登录。 |
| 主要布局 | 志愿者为浅色表单；盲人为黑底表单；紧急联系人在盲人设置页中以卡片和弹窗管理。 |
| 按钮和输入 | 盲人姓名、跑步配速、特殊需求；紧急联系人姓名/手机号/关系/主要联系人；志愿者姓名；可服务 Switch；保存设置；退出登录。 |
| 跳转关系 | 返回上一页；退出到 `/login`。 |
| 适合保留 | 紧急联系人管理交互可作为字段参考；资料保存反馈；盲人端黑底高对比。 |
| 不适合新版本 | 当前页面规格要求盲人资料页和志愿者认证页独立；盲人资料必填紧急联系人姓名和电话，不需要旧版"关系/设为主要联系人"作为 MVP 必填；退出缺少二次确认；可服务开关应主要在志愿者首页。 |
| 无障碍重设计 | 资料页必填项要有 hint；紧急联系人字段减少到 MVP 必需项；退出二次确认；设置页保留环境切换入口。 |

## 4. 旧导航关系

旧 Flutter 全局路由：

```text
/loading
  -> /login
  -> /role-selection
  -> /blind
  -> /volunteer

/login
  -> /role-selection
  -> /blind
  -> /volunteer

/role-selection
  -> /blind
  -> /volunteer

/blind
  -> /blind/request
  -> /blind/run/:id
  -> /settings

/blind/request
  -> /blind/request/place
  -> /blind

/blind/request/place
  -> /blind/request

/blind/run/:id
  -> /blind

/volunteer
  -> /volunteer/run/:id
  -> /settings

/volunteer/run/:id
  -> /volunteer

/settings
  -> previous page
  -> /login
```

当前 MVP 需要补齐或拆分的目标页：

- 盲人资料页：旧设置页的一部分，应成为首次角色选择后的独立资料页。
- 志愿者认证页：旧我的/设置页的一部分，应成为首次志愿者角色后的独立 Mock 认证页。
- 盲人订单等待页、服务中页、完成/评分页：旧 `BlindActiveRunPage` 合并过多，应按状态拆分 UI。
- 志愿者订单列表页、订单详情页、服务中页：旧 Dashboard 与 ActiveRun 合并过多，应拆成列表、详情、执行。
- 紧急求助页：旧 Flutter 缺少完整 terminal `emergency` UI。
- 设置页：需要增加 API 环境切换、角色切换拦截说明、退出二次确认。

## 5. 适合保留的旧 UI 设计

- 盲人端黑底高对比、大字体、少层级。
- 盲人端每屏一个主任务：发起预约、选择地点、确认预约、查看当前状态。
- 大按钮和整块可点击卡片，适合 VoiceOver 用户定位主操作。
- 状态卡片用大号中文状态词和一句辅助说明。
- 地点搜索独立页面，避免创建预约页过度拥挤。
- 地点搜索支持语音输入失败后的键盘回退。
- 订单状态轮询时只在状态变化后播报，避免重复 TTS。
- 志愿者端地图 + 底部订单列表的空间模型。
- 可服务开关放在志愿者首页首屏。
- 地图未配置、定位失败、权限失败时显示明确降级文案。
- 接单后进入地图执行页，底部固定主要操作。
- 资料页和紧急联系人使用清晰分区。

## 6. 不适合新 Swift 原生版本的旧设计

- AI 语音助手入口：当前 MVP 明确排除 AI assistant。
- WebSocket / 实时派单连接状态：当前 MVP REST + 轮询，不做 WebSocket。
- 复杂自然语言时间解析：当前 MVP 使用 DatePicker，不做复杂自然语言时间解析。
- 旧订单状态名：不得继承 `pendingMatch`、`pendingAccept`、`driverEnRoute`、`driverArrived`、`rematching`、`noVolunteer`。
- 旧动作链："我已出发"不是当前 MVP 状态机动作。
- 接单前展示跑者电话：违反志愿者接单前隐藏联系方式规则。
- 取消、结束服务、退出登录没有二次确认：违反危险操作规则。
- 缺少固定取消原因选择：违反当前取消规则。
- 缺少 terminal `emergency` UI：当前 MVP 必须支持 accepted/arrived/in_progress 进入 emergency。
- 三档评价：当前 MVP 是可选 1-5 星评分。
- `+50` 积分：当前 MVP 志愿者完成服务获得 `+100` 积分。
- 商城"兑换"按钮：当前 MVP 仅占位，不做兑换。
- Flutter 风格大圆角卡片和过重阴影：SwiftUI 新版应更克制，尤其志愿者工作台应偏工具型。
- 全局设置页承载资料、认证、可服务、联系人和退出：新版本应按模块拆分，避免把业务逻辑堆到设置页。

## 7. 需要重新设计以符合无障碍要求的页面

| 页面 | 重设计原因 | 必须补齐 |
| --- | --- | --- |
| 盲人首页 | 旧版缺小地图、当前位置描述和重复状态按钮 | 地图摘要、重复当前状态、退出确认 |
| 创建预约页 | 旧版时间输入与当前规则冲突，字段不足 | DatePicker、30 分钟校验、定位权限阻断、完整可选字段 |
| 地点搜索页 | 可保留结构，但要避免 fallback 被误认为真实地点 | 空状态、权限说明、候选行 VoiceOver |
| 盲人订单状态页 | 旧状态机冲突，缺确认开始和求助 | matching/accepted/arrived UI、确认开始、取消原因、求助确认 |
| 盲人服务中页 | 旧版未独立拆出 in_progress | 志愿者电话、一键求助、重复状态、轮询 completed/emergency |
| 盲人完成/评分页 | 旧版三档评分 | 1-5 星、可跳过、反馈文本语音输入 |
| 志愿者首页/列表 | 旧版接单前可能暴露电话，实时派单概念过重 | 接单前隐藏敏感信息、定位拒绝隐藏距离并禁接单 |
| 志愿者订单详情页 | 旧版列表卡片内直接接单，详情页不足 | 接单前/后信息分级、接单确认、地图位置 |
| 志愿者服务中页 | 旧动作和当前状态机冲突 | 到达、等待盲人确认、完成、取消、求助 |
| 设置页 | 旧版退出无确认，环境切换缺失 | API 环境、切换角色拦截、退出二次确认 |

## 8. 与当前 docs/OpenSpec 的冲突

| 主题 | 旧 Flutter UI / 行为 | 当前要求 |
| --- | --- | --- |
| 技术栈 | Flutter + Riverpod + go_router | Swift 原生 iOS，SwiftUI + MVVM |
| 平台 | Flutter 保留 Android/iOS 壳 | iOS only |
| 实时通信 | WebSocket 派单和重连状态 | REST only，无 WebSocket |
| 状态机 | `PENDING_*`、`DRIVER_*`、`REMATCHING`、`NO_VOLUNTEER` | `matching/accepted/arrived/in_progress/completed/cancelled/emergency` |
| 服务开始 | 志愿者"我已出发/我已到达"后旧流程推进 | 志愿者"我已到达"进入 `arrived`，盲人确认后进入 `in_progress` |
| 取消 | 可直接取消，缺固定原因 | 二次确认，固定原因，记录 `cancelledBy` |
| 求助 | 未完整覆盖 emergency | accepted/arrived/in_progress 可进入 terminal `emergency` |
| AI | 固定 AI 语音助手按钮 | AI assistant out of scope |
| 时间输入 | 语音自然语言时间和预设"现在出发" | DatePicker，预约至少 30 分钟后，不做复杂自然语言解析 |
| 联系方式 | 旧列表可出现跑者电话 | 接单前隐藏电话，接单后展示完整电话 |
| 积分 | `+50` 或固定余额 | 完成服务 `+100`，商城只占位 |
| 评分 | 好评/一般/差评 | 可选 1-5 星评分 |
| 商城 | 商品"兑换"按钮 | 不做真实兑换 |
| 退出 | 直接退出 | 退出登录需二次确认 |

## 9. 对 SwiftUI 实现的审计建议

- 把旧页面当作"交互意图"素材，不复刻 Flutter 文件结构。
- 新 SwiftUI 页面必须按 `docs/05-page-specs.md` 的 16 页规格实现。
- 盲人端页面优先使用大按钮、清晰状态文案、短路径导航。
- 业务状态和副作用放入 ViewModel：API、轮询、TTS、校验、状态转换都不放进 View。
- 地图桥接应封装在 `Map` 模块，SwiftUI 页面只传入当前位置、订单 marker 和错误状态。
- TTS 使用共享 `SpeechService`，状态变化去重，避免轮询造成重复播报。
- 语音输入只用于文本字段：地点描述、路线备注、备注、服务总结。
- 危险动作统一走 `Safety` 模块确认弹窗：取消、求助、完成服务、退出。
- 志愿者 UI 可以比盲人端更密，但接单、到达、完成、求助等按钮必须有明确 disabled 状态和可读说明。
- 设计文案使用当前文档中文状态词，不沿用旧 Flutter 英文/旧中文状态。

## 10. 结论

旧 Flutter UI 中值得保留的是无障碍方向、盲人端大按钮、地点搜索流程、状态播报、地图与列表组合、定位失败提示和订单轮询经验。

不应保留的是 Flutter 实现、旧状态机、旧 API、WebSocket、AI 助手、自然语言时间解析、接单前电话展示、三档评分、`+50` 积分和缺少二次确认的危险操作。

后续 iOS UI handoff 应以当前 `AGENTS.md`、`docs/01-10`、OpenSpec 为准，把旧 UI 转化为 SwiftUI 原生、MVVM、VoiceOver/TTS 优先的设计说明。
