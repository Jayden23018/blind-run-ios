# iOS UI Handoff: SwiftUI MVP

> 基于旧 Flutter UI 审计报告（`docs/ui-reference-audit.md`）、`docs/01-05` 产品文档、`AGENTS.md` 冻结规则整理。
> 旧 Flutter 代码位于 `/Users/jerry/A/blind-run/blind-run-frontend/lib/`，仅作为 UI 行为参考，**不作为 source of truth**。
> 当前所有规则以 `AGENTS.md` > `docs/01-10` > `openspec/` 为准。
> 旧 Flutter Demo 截图索引见 [`legacy-screenshots/00-index.md`](legacy-screenshots/00-index.md)。

---

## 截图路径速查表

| 页面 | 参考截图路径 |
|------|-------------|
| 1. 登录页 | 无对应旧截图 |
| 2. 角色选择页 | 无对应旧截图 |
| 3. 盲人资料页 | 无对应旧截图 |
| 4. 盲人首页 | `legacy-screenshots/blind-runner/01-blind-home.png` |
| 5. 创建预约页 | `legacy-screenshots/blind-runner/02-create-booking-1.png` ~ `05-create-booking-4.png` |
| 5a. 地点搜索子流程 | `legacy-screenshots/blind-runner/04-create-booking-3.png` |
| 6. 盲人订单状态等待页 | `legacy-screenshots/blind-runner/06-order-matching-1.png` ~ `10-volunteer-arrived.png` |
| 7. 盲人服务中页 | 无对应旧截图（旧版合并在 BlindActiveRunPage） |
| 8. 盲人完成/评分页 | `legacy-screenshots/blind-runner/11-service-completed-rating.png`、`12-service-completed-result.png` |
| 9. 志愿者资料认证页 | `legacy-screenshots/volunteer/02-volunteer-profile-verification.png` |
| 10. 志愿者首页 | `legacy-screenshots/volunteer/01-volunteer-home.png` |
| 11. 志愿者订单列表页 | `legacy-screenshots/volunteer/03-available-orders.png` |
| 12. 志愿者订单详情页 | `legacy-screenshots/volunteer/04-order-detail-after-accept.png` |
| 13. 志愿者服务中页 | `legacy-screenshots/volunteer/05-arrived-confirmation.png` ~ `07-complete-service-summary.png` |
| 14. 志愿者服务记录页 | `legacy-screenshots/volunteer/08-service-records.png` |
| 15. 志愿者积分/商城占位页 | `legacy-screenshots/volunteer/09-points-shop-placeholder.png` |
| 16. 设置页 | `legacy-screenshots/volunteer/10-settings.png` |

---

## 全局 UI 原则

### 盲人端（Blind Runner）

| 原则 | 细则 |
|------|------|
| 视觉 | 深色背景（黑/近黑）、高对比度文字、大字号（≥20pt body）、无多余装饰 |
| 触控 | 关键主按钮最小高度 **64pt**，点击区域充足，按钮间距 ≥16pt |
| 层级 | 每屏一个主任务，避免嵌套导航和过多选择 |
| 语音 | TTS 播报所有关键状态变化；每个关键页面有"重复当前状态"按钮 |
| 危险操作 | 取消订单、进入求助、退出登录必须**二次确认** |
| 状态文案 | 仅使用 MVP 7 个订单状态中文，不显示英文状态名 |

### 志愿者端（Volunteer）

| 原则 | 细则 |
|------|------|
| 视觉 | 浅色/标准主题，信息密度可高于盲人端，但关键按钮仍需清晰 |
| 地图 | 全屏或半屏高德地图，显示当前位置和订单 marker |
| 隐私 | 接单前**隐藏**盲人联系电话、紧急联系人；接单后显示完整电话 |
| 危险操作 | 取消订单、进入求助、结束服务、退出登录必须**二次确认** |
| 积分 | 完成服务 `+100` 积分（不是旧版 `+50`） |

### 双端共享

- 订单状态：`matching` / `accepted` / `arrived` / `in_progress` / `completed` / `cancelled` / `emergency`
- 禁止旧状态名：`pendingMatch`、`pendingAccept`、`driverEnRoute`、`driverArrived`、`rematching`、`noVolunteer`、`submitted`、`contacted`、`expired`
- 不做：WebSocket、实时轨迹、路线导航、AI 助手、App 内聊天
- API 环境切换入口：Mock / Local Backend / Production Backend（所有页面底部角落不显眼位置）

---

## 1. 登录页

### 页面名称
登录页（手机号 + 验证码）

### 页面目标
用户通过手机号 + 固定验证码 `123456` 登录，首次登录自动创建账号。

### 适用角色
盲人跑者、志愿者（通用）

### 页面入口
App 启动（UserDefaults 中无有效 JWT 时）

### 页面主要内容
- App 品牌标识 "助盲跑"（顶部居中，大号文字，无需 logo 图片）
- 手机号输入框（11 位中国大陆手机号）
- "获取验证码" 按钮
- 验证码输入框（6 位数字）
- 倒计时显示（60 秒）+ "重新发送" 链接
- 环境切换入口（底部角落，灰色小字，不干扰主流程）

### 主要按钮
| 按钮 | 条件 | 行为 |
|------|------|------|
| "获取验证码" | 手机号格式正确时启用 | 调用 `POST /api/auth/phone-login`（先只发验证码的语义由 API 统一处理），按钮变为 60 秒倒计时 |
| "登录" / 自动提交 | 6 位验证码填完后 | 调用 `POST /api/auth/phone-login`，成功后存储 JWT 到 AppState |

### 表单字段
| 字段 | 类型 | 校验规则 |
|------|------|----------|
| 手机号 | 数字键盘，11 位 | 必须 1 开头 11 位数字 |
| 验证码 | 数字键盘，6 位 | 固定 `123456`，其他值返回 `INVALID_VERIFICATION_CODE` |

### 状态展示
- 默认：手机号输入 + "获取验证码" 按钮（验证码输入区隐藏或灰色）
- 发送验证码后：验证码输入区显示，"获取验证码"变为倒计时按钮
- 登录中：loading spinner + "正在登录..."
- 登录成功：自动跳转

### 错误状态
- 手机号格式错误 → 红框 + 红色文字 "请输入正确的手机号"
- 验证码错误 → 验证码输入框抖动动画 + "验证码错误，请重新输入"
- 网络错误 → Toast "网络错误，请重试"

### 空状态
不适用（登录页始终有输入控件）

### TTS 播报文案
进入页面不自动播报（避免每次启动都打扰用户）。登录成功时不播报（由下一页 TTS 接管）。

### VoiceOver 建议
| 元素 | accessibilityLabel | accessibilityHint |
|------|--------------------|-------------------|
| 手机号输入框 | "手机号输入框，请输入 11 位手机号" | — |
| 获取验证码按钮 | "获取验证码" | "点击后发送验证码到手机" |
| 验证码输入框 | "验证码输入框，请输入 6 位验证码" | — |
| 环境切换入口 | "API 环境切换" | "当前环境：Mock 模式" |

### SwiftUI 布局建议
```
VStack(spacing: 24) {
    Spacer()
    Text("助盲跑").font(.largeTitle).fontWeight(.bold)
    Spacer().frame(height: 40)
    TextField("手机号", ...).keyboardType(.numberPad)
    Button("获取验证码") { ... }.frame(height: 52)
    TextField("验证码", ...).keyboardType(.numberPad)
    // 倒计时 Text
    Spacer()
    // 环境切换（小字，灰色）
}
.padding(.horizontal, 32)
```

### 旧 UI 可保留的部分
- 黑底高对比度单列表单布局
- 明确 loading 状态的交互反馈
- 错误提示的即时展示方式

### 旧 UI 必须修改的部分
- 旧版两接口（发送验证码 + 校验验证码），现在 API 统一为 `POST /api/auth/phone-login`
- 旧版缺少环境切换入口 → 必须补充
- 旧版无障碍标注不完整 → 补齐所有 label/hint

---

## 2. 角色选择页

### 页面名称
角色选择页

### 页面目标
用户选择本次使用的 activeRole：盲人跑者或志愿者。

### 适用角色
盲人跑者、志愿者（通用，首次登录 / 手动切换时）

### 页面入口
首次登录验证成功（后端返回无 activeRole）→ 此页；设置页 → 切换角色 → 此页

### 页面主要内容
- 标题："请选择您的角色"
- 两个大面积角色卡片（纵向排列）：
  - **盲人跑者卡片**：黄色/暖色背景，图标，标题 "我是盲人跑者"，副标题 "预约志愿者陪我跑步"
  - **志愿者卡片**：蓝色/深色背景，图标，标题 "我是志愿者"，副标题 "陪伴盲人跑者完成跑步"
- 底部说明文字："一个手机号可同时拥有两个身份，后续可在设置中切换"

### 主要按钮
| 按钮 | 行为 |
|------|------|
| "我是盲人跑者" 卡片 | 检查活跃订单 → 如被拦截弹窗 → 保存 activeRole → 有资料则进入盲人首页，无资料则进入盲人资料页 |
| "我是志愿者" 卡片 | 检查活跃订单 → 如被拦截弹窗 → 保存 activeRole → 有认证则进入志愿者首页，无认证则进入志愿者认证页 |

### 表单字段
无（纯选择页，无输入）

### 状态展示
- 默认：两个卡片并排/纵向排列，均可点击
- 切换角色时被拦截：弹窗 "您有进行中的订单，无法切换角色"，角色不切换
- 选择中：卡片点击后短暂 loading → 跳转

### 错误状态
- 网络错误 → Toast "网络错误，请重试"
- 角色保存失败 → Toast "角色设置失败"

### 空状态
不适用

### TTS 播报文案
进入页面播报："请选择您的角色。左侧，我是盲人跑者，预约志愿者陪我跑步。右侧，我是志愿者，陪伴盲人跑者完成跑步。"

### VoiceOver 建议
| 元素 | accessibilityLabel | accessibilityHint |
|------|--------------------|-------------------|
| 盲人跑者卡片 | "我是盲人跑者，预约志愿者陪我跑步" | "点击后进入盲人跑者模式" |
| 志愿者卡片 | "我是志愿者，陪伴盲人跑者完成跑步" | "点击后进入志愿者模式" |

### SwiftUI 布局建议
```
VStack(spacing: 24) {
    Text("请选择您的角色").font(.title2)
    // 盲人跑者卡片
    Button(action: { selectRole(.blindRunner) }) {
        VStack {
            Image(systemName: "figure.run")
            Text("我是盲人跑者").font(.title3)
            Text("预约志愿者陪我跑步").font(.subheadline)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(Color.orange.opacity(0.15))
        .cornerRadius(16)
    }
    // 志愿者卡片
    Button(action: { selectRole(.volunteer) }) {
        VStack {
            Image(systemName: "figure.and.child.holdinghands")
            Text("我是志愿者").font(.title3)
            Text("陪伴盲人跑者完成跑步").font(.subheadline)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(Color.blue.opacity(0.15))
        .cornerRadius(16)
    }
    Text("一个手机号可同时拥有两个身份，后续可在设置中切换")
        .font(.caption).foregroundColor(.secondary)
}
.padding(.horizontal, 32)
```

### 旧 UI 可保留的部分
- 双大卡片纵向布局（旧 Flutter 黄色/深色高对比卡片）
- 角色说明副标题
- 盲人端深色背景

### 旧 UI 必须修改的部分
- 旧版选择后直接进首页 → 新版本需检查是否有活跃订单（拦截弹窗）
- 旧版无首次资料页分流 → 新版本按资料完整性分流
- 旧版无障碍不完整 → 补齐卡片 label/hint

---

## 3. 盲人资料页

### 页面名称
盲人资料页

### 页面目标
盲人跑者首次填写个人资料和紧急联系人信息，完成注册。

### 适用角色
盲人跑者

### 页面入口
角色选择页选择 "盲人跑者"（首次无资料时） / 设置页 → 编辑资料

### 页面主要内容
- 标题："完善信息"（首次）/ "编辑资料"（编辑模式）
- 必填标识说明
- 昵称输入框（必填）
- 紧急联系人姓名输入框（必填）
- 紧急联系人电话输入框（必填）
- 跑步经验选择器（选填：无经验 / 偶尔跑 / 经常跑，使用 Picker 或分段选择器）
- "完成" / "保存" 按钮（底部固定，最小 64pt）

### 主要按钮
| 按钮 | 条件 | 行为 |
|------|------|------|
| "完成" / "保存" | 必填项全部有效时启用 | 保存到后端 → 进入盲人首页 |

### 表单字段
| 字段 | 类型 | 必填 | 校验规则 |
|------|------|------|----------|
| 昵称 | 文本输入 | 是 | 非空 |
| 紧急联系人姓名 | 文本输入 | 是 | 非空 |
| 紧急联系人电话 | 数字键盘 11 位 | 是 | 1 开头 11 位 |
| 跑步经验 | Picker | 否 | 三选一 |

### 状态展示
- 首次模式：标题 "完善信息"，字段为空
- 编辑模式：标题 "编辑资料"，字段预填已有数据
- 提交中：按钮显示 loading spinner

### 错误状态
- 必填项为空 → 对应字段红框 + "请填写必填信息"，按钮禁用
- 手机号格式错误 → "请输入正确的手机号"
- 网络错误 → "保存失败，请重试"

### 空状态
不适用

### TTS 播报文案
进入页面播报："请填写个人资料。昵称、紧急联系人姓名、紧急联系人电话为必填项。"

### VoiceOver 建议
| 元素 | accessibilityLabel | accessibilityHint |
|------|--------------------|-------------------|
| 昵称输入框 | "昵称，必填" | — |
| 紧急联系人姓名输入框 | "紧急联系人姓名，必填" | — |
| 紧急联系人电话输入框 | "紧急联系人电话，必填，11 位手机号" | — |
| 跑步经验选择器 | "跑步经验，选填" | "点击选择跑步经验" |
| 完成按钮 | "完成，保存资料" | — |

### SwiftUI 布局建议
```
Form {
    Section("必填信息") {
        TextField("昵称", text: $nickname)
        TextField("紧急联系人姓名", text: $contactName)
        TextField("紧急联系人电话", text: $contactPhone)
            .keyboardType(.numberPad)
    }
    Section("选填信息") {
        Picker("跑步经验", selection: $experience) {
            Text("无经验").tag("none")
            Text("偶尔跑").tag("occasional")
            Text("经常跑").tag("frequent")
        }
    }
}
// 底部固定按钮
VStack {
    Button("完成") { submit() }
        .buttonStyle(.borderedProminent)
        .frame(minHeight: 64)
}
.padding()
```

### 旧 UI 可保留的部分
- 旧 SettingsPage 中盲人资料字段（昵称、紧急联系人）作为字段参考
- 黑底高对比表单风格

### 旧 UI 必须修改的部分
- 旧版紧急联系人有 "关系/主要联系人" 管理 → MVP 去掉，仅保留姓名和电话
- 旧版资料散落在设置页 → 新版本为独立首次流程页
- 旧版缺少跑步经验选填项

---

## 4. 盲人首页

### 页面名称
盲人首页

### 页面目标
盲人跑者功能入口，根据是否有活跃订单展示不同的主内容。

### 适用角色
盲人跑者

### 页面入口
登录成功（已有盲人资料）/ 资料填写完成 / 服务完成返回 / 切换角色

### 页面主要内容（无活跃订单）
- 高德小地图（上 1/3 区域）：显示当前位置蓝色圆点，文字标注当前位置如 "深圳市南山区科技园附近"
- "开始约跑" 大按钮（屏幕中下部，占主要视觉区域，最小 64pt）
- 当前位置文字描述
- "重复当前状态" 按钮

### 页面主要内容（有活跃订单）
- 高德小地图：显示订单地点 marker
- 订单状态卡片（大号，覆盖 "开始约跑" 位置）：
  - matching：旋转动画 + "匹配中，等待志愿者接单"
  - accepted：绿色 + "志愿者已接单，正在赶来"
  - arrived：蓝色 + "志愿者已到达约定地点"
  - in_progress：绿色 + "服务进行中"
- "查看当前订单" 按钮（点击进入对应状态页）
- "重复当前状态" 按钮

### 主要按钮
| 按钮 | 可见条件 | 行为 |
|------|----------|------|
| "开始约跑" | 无活跃订单 | 进入创建预约页 |
| "查看当前订单" | 有活跃订单 | 进入对应订单状态页 |
| "重复当前状态" | 始终 | TTS 重新播报当前状态 |
| 设置入口 | 始终 | 进入设置页 |
| 切换角色入口 | 始终 | 检查活跃订单后切换 |

### 表单字段
无

### 状态展示
- 无订单 → 地图 + "开始约跑" 大按钮
- 有订单 → 地图 + 订单状态卡片 + "查看当前订单" 按钮
- 活跃订单状态变化 → 状态卡片实时更新（由 ViewModel 驱动，不在此页轮询）

### 错误状态
- 定位失败 → 地图区域显示 "定位失败" 占位 + 降级文案，页面仍可用（显示默认坐标）
- 网络错误 → 保留上次缓存的状态卡片
- 定位权限拒绝 → 地图区域显示 "需要定位权限"，显示 "去设置" 按钮

### 空状态
不适用（盲人首页总是有内容："开始约跑" 或订单卡片）

### TTS 播报文案
**无活跃订单时**："欢迎来到助盲跑。当前位置：深圳市南山区科技园附近。开始约跑按钮。"

**有活跃订单时**：播报当前订单状态，如 "您有一个进行中的订单。志愿者已接单，正在赶来。预约时间：今天下午 3 点。"

### VoiceOver 建议
| 元素 | accessibilityLabel | accessibilityHint |
|------|--------------------|-------------------|
| "开始约跑" 按钮 | "开始约跑" | "点击后创建跑步预约" |
| 订单状态卡片 | "当前订单：" + 状态中文 + "，" + 时间 + "，" + 地点 | "点击查看订单详情" |
| "重复当前状态" 按钮 | "重复当前状态" | "点击后重新播报当前页面信息" |
| 地图区域 | "地图，显示当前位置" | — |

### SwiftUI 布局建议
```
VStack(spacing: 0) {
    // 地图区域（上 1/3）
    AMapContainer(location: currentLocation, markers: orderMarkers)
        .frame(height: UIScreen.main.bounds.height / 3)
    
    // 当前位置文字
    Text(currentLocationDescription)
        .font(.subheadline)
        .padding(.horizontal)
    
    Spacer()
    
    // 主操作区（下 2/3 居中）
    if let order = activeOrder {
        StatusCard(order: order)
        LargePrimaryButton("查看当前订单") { navigateToOrder(order) }
            .frame(minHeight: 64)
    } else {
        LargePrimaryButton("开始约跑") { navigateToCreateBooking() }
            .frame(minHeight: 64)
            .padding(.horizontal, 32)
    }
    
    RepeatStatusButton(action: speakCurrentStatus)
    
    Spacer()
}
```
注意：盲人首页只判断导航目标，不做轮询。轮询在订单详情页内启动。

### 旧 UI 可保留的部分
- 超大 "开始约跑" 按钮（旧 Flutter 有高达 240pt 的大按钮，新版本保留大按钮方向但不必复刻极端高度）
- 一屏一个主任务的极简设计
- 订单状态摘要卡片
- 状态变化 TTS 播报思路

### 旧 UI 必须修改的部分
- 旧版缺地图和当前位置描述 → 新版本必须加入 AMap 小地图
- 旧版 AI 语音助手入口 → 必须删除
- 旧版退出登录无二次确认 → 必须补齐
- 旧版缺 "重复当前状态" 按钮 → 必须补齐
- 旧版使用旧状态名 → 全部替换为 MVP 7 状态中文

---

## 5. 创建预约页

### 页面名称
创建预约页

### 页面目标
盲人跑者填写预约信息，创建跑步订单。

### 适用角色
盲人跑者

### 页面入口
盲人首页 → 点击 "开始约跑"

### 页面主要内容
分区表单布局，自上而下：

1. **出发地点区**（必填）
   - 大按钮 "选择出发地点"（显示已选地点名称，默认填充当前位置文字描述）
   - 点击进入地点搜索子流程

2. **预约时间区**（必填）
   - iOS 原生 `DatePicker`（`.graphical` 或 `.compact` 样式）
   - 限制：只能选择当前时间 30 分钟后的时间
   - 下方提示文字："预约时间需至少在 30 分钟后"

3. **可选项区**（选填，可折叠或直接展开）
   - 目的地/路线：文本输入框 + 麦克风按钮
   - 预计跑步时长：Picker（15 分钟 / 30 分钟 / 45 分钟 / 1 小时 / 1.5 小时 / 2 小时）
   - 预计距离：数字输入框（单位：公里）
   - 配速偏好：分段选择器（慢跑 / 中速 / 较快）
   - 是否需要同性志愿者：Toggle
   - 备注：多行文本输入框 + 麦克风按钮

4. **提交区**（底部固定）
   - "提交预约" 按钮（最小 64pt，必填项全部完成时启用）

### 主要按钮
| 按钮 | 行为 |
|------|------|
| "选择出发地点" | 进入地点搜索子流程 |
| 麦克风按钮（地点描述/备注旁） | 启动 Speech Framework 语音识别 |
| "提交预约" | 校验 → `POST /api/orders` → 进入订单状态等待页 |

### 表单字段
| 字段 | 类型 | 必填 | 语音输入 | 说明 |
|------|------|------|----------|------|
| 出发地点 | 地点选择器 | 是 | 是（在地点搜索子流程） | 默认当前定位 |
| 预约时间 | DatePicker | 是 | 否 | ≥ 当前时间 + 30 分钟 |
| 目的地/路线 | 文本 | 否 | 是 | — |
| 预计时长 | Picker | 否 | 否 | 6 个选项 |
| 预计距离 | 数字键盘 | 否 | 否 | 单位公里 |
| 配速偏好 | 分段选择 | 否 | 否 | 3 个选项 |
| 同性志愿者 | Toggle | 否 | 否 | 默认关 |
| 备注 | 多行文本 | 否 | 是 | — |

### 状态展示
- 定位初始化中 → 出发地点显示 "正在获取位置..."
- 地点已选择 → 显示已选地点名称和地址
- 地点使用默认坐标 → 显示 "当前位置（演示模式）"

### 错误状态
- 定位权限拒绝 → 全页拦截："需要开启定位权限才能创建预约" + "去设置" 按钮 + TTS 播报
- 定位失败 → 使用默认测试坐标，显示 "使用演示位置"
- 预约时间不足 30 分钟 → 红色提示 + 按钮禁用
- 出发地点未选择 → 按钮禁用
- 提交失败 → Toast "提交失败，请重试" + TTS 播报

### 空状态
不适用

### TTS 播报文案
- 进入页面：不自动播报（避免干扰）
- 提交成功："订单提交成功，等待志愿者接单"（在跳转后的订单等待页播报）
- 定位权限拒绝："定位权限未开启。请前往系统设置开启定位，以便创建跑步预约。"

### VoiceOver 建议
| 元素 | accessibilityLabel | accessibilityHint |
|------|--------------------|-------------------|
| 选择出发地点按钮 | "选择出发地点，" + 当前选中地点名 | "点击搜索并选择出发地点" |
| 预约时间选择器 | "预约时间，" + 当前选择时间 | "选择至少 30 分钟后的时间" |
| 麦克风按钮 | "语音输入" | "点击后说出内容，语音自动转文字" |
| 提交预约按钮 | "提交预约" | "提交后等待志愿者接单" |

### SwiftUI 布局建议
```
ScrollView {
    VStack(spacing: 20) {
        // 出发地点（大卡片）
        Button(action: { showPlaceSearch = true }) {
            HStack {
                Image(systemName: "mappin.and.ellipse")
                VStack(alignment: .leading) {
                    Text("出发地点").font(.headline)
                    Text(selectedPlace ?? "点击选择").font(.body)
                }
                Spacer()
                Image(systemName: "chevron.right")
            }
            .padding()
            .frame(minHeight: 64)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        
        // 预约时间
        DatePicker("预约时间", selection: $bookingTime, in: dateRange)
            .padding()
        
        // 可选项区
        DisclosureGroup("更多选项（选填）") {
            VStack(spacing: 16) {
                TextField("目的地/路线", text: $destination)
                Picker("预计时长", selection: $duration) { ... }
                TextField("预计距离（公里）", text: $distance)
                Picker("配速偏好", selection: $pace) { ... }
                Toggle("需要同性志愿者", isOn: $sameGender)
                TextField("备注", text: $notes)
            }
        }
    }
    .padding()
}
// 底部固定提交按钮
VStack {
    Button("提交预约") { submit() }
        .buttonStyle(.borderedProminent)
        .frame(minHeight: 64)
        .disabled(!isFormValid)
}
.padding()
```

### 旧 UI 可保留的部分
- 分步降低认知负担的思路（先地点后时间）
- 出发地点用大按钮进入独立搜索
- 提交前 disabled 状态清晰

### 旧 UI 必须修改的部分
- 旧版 "现在出发" "明天上午" 语音时间解析 → 替换为系统 DatePicker
- 旧版缺少目的地/路线、时长、距离、配速、同性志愿者、备注字段 → 补齐
- 旧版预约不足 30 分钟未拦截 → 增加校验
- 旧版提交后直接回首页 → 改为进入订单状态等待页

---

### 5a. 地点搜索子流程（嵌入创建预约页）

### 页面名称
地点搜索（创建预约的子流程）

### 页面目标
搜索和选择出发地点，返回创建预约页。

### 适用角色
盲人跑者

### 页面入口
创建预约页 → 点击 "选择出发地点"

### 页面主要内容
- 顶部搜索栏：输入框 + 麦克风按钮 + 搜索按钮
- 搜索结果列表（来自高德 POI 搜索）
  - 每项：地点名称、地址详情、距当前位置距离
- "使用当前位置" 快捷选项（列表第一项）

### 主要按钮
| 按钮 | 行为 |
|------|------|
| 搜索结果行 | 选中 → pop 回创建预约页，传入地点 |
| 麦克风按钮 | 启动 Speech Framework 语音识别，填入搜索框 |
| "使用当前位置" | 直接使用当前定位 → pop 回创建预约页 |

### 表单字段
| 字段 | 类型 |
|------|------|
| 地点搜索关键词 | 文本输入 + 语音输入 |

### 状态展示
- 搜索中 → 搜索框内 loading spinner
- 搜索结果 → 列表显示
- 语音识别中 → 麦克风按钮高亮脉冲动画 + "正在聆听..."

### 错误状态
- POI 搜索无结果 → "未搜索到相关地点"
- 语音识别失败 → Toast "语音识别失败，请使用键盘输入"
- 语音权限拒绝 → Toast "语音输入不可用"，允许键盘输入
- 高德 Key 未配置 → "地图服务暂不可用"

### 空状态
搜索关键词无匹配 → "未搜索到相关地点，请尝试其他关键词"

### TTS 播报文案
- 进入页："请说出或输入出发地点"
- 每个搜索结果：读出 "第 N 项，" + 地点名 + 地址
- 选中地点回退时：不额外播报（创建预约页已播报）

### VoiceOver 建议
| 元素 | accessibilityLabel | accessibilityHint |
|------|--------------------|-------------------|
| 搜索输入框 | "搜索出发地点" | "输入地点关键词进行搜索" |
| 麦克风按钮 | "语音输入出发地点" | "点击后说出地点" |
| 搜索结果行 | 地点名 + "，" + 地址 | "点击选择此地点" |
| "使用当前位置" | "使用当前位置，" + 当前地址 | — |

### SwiftUI 布局建议
```
VStack(spacing: 0) {
    // 搜索栏
    HStack {
        TextField("搜索出发地点", text: $searchText)
        Button(action: startVoiceInput) {
            Image(systemName: "mic.fill")
        }
    }
    .padding()
    
    // 使用当前位置
    Button(action: useCurrentLocation) {
        HStack {
            Image(systemName: "location.fill")
            Text("使用当前位置")
            Spacer()
        }
        .padding()
    }
    
    // 搜索结果
    List(searchResults) { place in
        Button(action: { selectPlace(place) }) {
            VStack(alignment: .leading) {
                Text(place.name).font(.headline)
                Text(place.address).font(.caption).foregroundColor(.secondary)
            }
        }
    }
}
```

### 旧 UI 可保留的部分
- 独立地点搜索页面（避免创建预约页过度拥挤）
- 语音搜索 + 文字搜索双输入模式
- 语音失败后键盘回退
- 候选行读出地点名和地址

### 旧 UI 必须修改的部分
- 旧版 fallback POI 可能被误认为是真实结果 → 新版本必须标注 "演示模式"
- 旧版无障碍不完整 → 补齐所有候选行的 label/hint

---

## 6. 盲人订单状态等待页

### 页面名称
盲人订单状态等待页

### 页面目标
展示订单 `matching`、`accepted`、`arrived` 状态，等待志愿者接单和到达。此页面是盲人端的核心等待中枢。

### 适用角色
盲人跑者

### 页面入口
创建预约提交成功 / 盲人首页点击 "查看当前订单"（状态为 matching/accepted/arrived 时）

### 页面主要内容
- **大号状态指示区**（上半部分）：
  - matching：动画旋转圆圈 + "匹配中，请稍候" + 预计等待提示
  - accepted：绿色勾 + "志愿者已接单" + 志愿者昵称
  - arrived：蓝色铃铛 + "志愿者已到达约定地点" + 志愿者昵称
- **志愿者信息卡片**（accepted / arrived 时显示）：
  - 昵称（大字）
  - 联系电话（arrived 起显示，可点击拨打）
- **订单信息卡片**：
  - 出发地点
  - 预约时间
  - 其他可选项（目的地、时长等，如有）
- **底部操作区**：
  - arrived："确认开始服务" 按钮（最小 64pt，绿色醒目）
  - matching / accepted / arrived："取消订单" 按钮（灰色，次要位置）
  - accepted / arrived："一键求助" 按钮（红色醒目）

### 主要按钮
| 按钮 | 可见状态 | 行为 |
|------|----------|------|
| "确认开始服务" | arrived | 调用 `POST /api/orders/{id}/confirm-start` → 进入服务中页 |
| "取消订单" | matching / accepted / arrived | 弹出 CancelReasonSheet（5 个固定原因）→ 确认 → cancelled |
| "一键求助" | accepted / arrived | DangerConfirmDialog → emergency |
| "重复当前状态" | 始终 | TTS 重新播报 |

### 表单字段
无（取消时弹出 CancelReasonSheet 选择原因）

### 状态展示
| 订单状态 | UI | 轮询 |
|----------|-----|------|
| matching | 旋转圆 + "匹配中" + 取消按钮 | 每 5 秒 `GET /api/orders/{id}` |
| accepted | 志愿者昵称 + "已接单" + 取消按钮 + 求助按钮 | 每 5 秒轮询 |
| arrived | 志愿者信息 + "已到达" + 确认开始按钮 + 取消按钮 + 求助按钮 | 每 5 秒轮询 |

### 错误状态
- 网络错误 → 保留上次查询结果，静默重试，不重复播报
- 轮询接口异常 → Toast "获取订单状态失败"
- 确认开始失败 → Toast "操作失败，请重试"
- 取消失败 → Toast "取消失败"

### 空状态
不适用（订单已创建）

### TTS 播报文案
- matching → "订单提交成功，正在等待志愿者接单"
- matching → accepted（状态变化时）："志愿者已接单，志愿者正在赶来"
- accepted → arrived（状态变化时）："志愿者已到达约定地点，请确认开始服务"
- matching → cancelled："抱歉，暂无志愿者可用。本次预约已取消。"
- accepted / arrived → cancelled："预约已取消"
- **注意**：轮询期间只在状态变化时播报一次，不重复播报同一状态

### VoiceOver 建议
| 元素 | accessibilityLabel | accessibilityHint |
|------|--------------------|-------------------|
| 状态指示器 | 状态中文 + 说明，如 "匹配中，正在等待志愿者接单" | — |
| 志愿者信息卡片 | "志愿者：" + 昵称 | — |
| 志愿者电话 | "拨打志愿者电话 " + 完整号码 | — |
| "确认开始服务" | "确认开始服务" | "点击后正式开始跑步" |
| "取消订单" | "取消订单" | "需要选择取消原因并确认" |
| "一键求助" | "一键求助，遇到紧急情况时点击" | "需要使用二次确认" |
| "重复当前状态" | "重复当前状态" | — |

### SwiftUI 布局建议
```
VStack(spacing: 0) {
    ScrollView {
        VStack(spacing: 24) {
            // 状态指示区（占主要视觉空间）
            StatusIndicator(status: order.status)
                .padding(.top, 60)
            
            // 志愿者信息卡片（accepted/arrived 时）
            if order.status == .accepted || order.status == .arrived {
                VolunteerInfoCard(volunteer: order.volunteer, showPhone: order.status == .arrived)
            }
            
            // 订单信息卡片
            OrderInfoCard(order: order)
            
            // 确认开始按钮（arrived）
            if order.status == .arrived {
                LargePrimaryButton("确认开始服务") { confirmStart() }
                    .frame(minHeight: 64)
            }
            
            // 取消订单（matching/accepted/arrived）
            Button("取消订单") { showCancelSheet = true }
                .foregroundColor(.red)
            
            // 一键求助（accepted/arrived）
            if order.status == .accepted || order.status == .arrived {
                Button("一键求助") { showEmergencyConfirm = true }
                    .foregroundColor(.red)
                    .frame(minHeight: 64)
            }
        }
        .padding()
    }
    
    // 底部固定
    RepeatStatusButton(action: speakStatus)
}
.onAppear { startPolling() }
.onDisappear { stopPolling() }
```

### 旧 UI 可保留的部分
- 状态大字卡片和轮询机制
- 5 秒轮询间隔
- 状态变化时 TTS 播报思路

### 旧 UI 必须修改的部分
- 旧状态名 `pendingMatch/pendingAccept/driverEnRoute/driverArrived` → 全部替换
- 旧版缺少 arrived 状态的 "确认开始服务" → 补齐
- 旧版缺少 "一键求助" 入口 → 补齐
- 旧版取消无双确认和固定原因 → 补齐 CancelReasonSheet
- 旧版三合一（状态+服务中+完成）→ 拆分为独立的三个页面
- 旧版缺少 "重复当前状态" → 补齐

---

## 7. 盲人服务中页

### 页面名称
盲人服务中页

### 页面目标
`in_progress` 状态中展示服务信息和求助入口。

### 适用角色
盲人跑者

### 页面入口
订单状态变为 `in_progress` 时自动跳转 / 盲人首页点击进行中订单

### 页面主要内容
- 页面标题："服务进行中"
- 志愿者信息卡片（昵称 + 联系电话，可点击拨打）
- 服务进度信息：开始时间 / 已进行时长
- "一键求助" 大按钮（红色醒目，最小高度 64pt）
- "重复当前状态" 按钮

### 主要按钮
| 按钮 | 行为 |
|------|------|
| 志愿者电话 | 点击 → 系统拨号 |
| "一键求助" | DangerConfirmDialog（固定文案） → 确认 → emergency |
| "重复当前状态" | TTS 重新播报当前状态 |

### 表单字段
无

### 状态展示
- in_progress：显示志愿者信息 + 服务已开始时长的计时器
- 每 5 秒轮询 `GET /api/orders/{id}`，检测 completed / emergency

### 错误状态
- 网络错误 → 保留当前 UI，静默重试
- 拨号失败 → "无法拨打电话"

### 空状态
不适用

### TTS 播报文案
- 进入页："服务已开始，祝您跑步愉快。志愿者：" + 昵称
- in_progress → completed（轮询变化）："服务已完成，感谢使用助盲跑"
- in_progress → emergency（轮询变化）："已进入求助状态，请保持冷静"

### VoiceOver 建议
| 元素 | accessibilityLabel | accessibilityHint |
|------|--------------------|-------------------|
| 志愿者电话按钮 | "拨打志愿者电话 " + 完整号码 | — |
| "一键求助" | "一键求助，遇到紧急情况时点击" | "确认后将标记为异常状态" |
| "重复当前状态" | "重复当前状态" | — |
| 计时器 | "服务已进行 " + N + " 分钟" | — |

### SwiftUI 布局建议
```
VStack(spacing: 0) {
    ScrollView {
        VStack(spacing: 24) {
            // 标题
            Text("服务进行中").font(.largeTitle)
            
            // 计时器
            Text(elapsedTime).font(.title2).monospacedDigit()
            
            // 志愿者信息
            VolunteerInfoCard(volunteer: volunteer, showPhone: true)
            
            Spacer().frame(height: 40)
            
            // 紧急求助
            Button("一键求助") { showEmergencyConfirm = true }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .frame(minHeight: 64)
        }
        .padding()
    }
    
    RepeatStatusButton(action: speakStatus)
}
.onAppear { startPolling() }
.onDisappear { stopPolling() }
```

### 旧 UI 可保留的部分
- 状态卡片 + 联系方式布局
- 轮询监听状态变化

### 旧 UI 必须修改的部分
- 旧版 `BlindActiveRunPage` 混合了多种状态 → 拆分为独立 in_progress 页
- 旧版缺少独立的紧急求助按钮 → 补齐
- 旧版缺少 "重复当前状态" → 补齐

---

## 8. 盲人完成/评分页

### 页面名称
盲人完成/评分页

### 页面目标
显示服务完成状态，提供可选的星级评分入口。

### 适用角色
盲人跑者

### 页面入口
订单状态变为 `completed` 时自动跳转

### 页面主要内容
- 完成图标/动画 + "服务已完成"
- 服务摘要卡片：
  - 志愿者昵称
  - 出发地点
  - 服务时长
- 星级评分区（1-5 颗星，点击选择，显示已选星数）
- 文字反馈输入框（选填，多行，带麦克风按钮）
- "提交评价" 按钮
- "跳过" 链接（不提交评价直接返回首页）

### 主要按钮
| 按钮 | 行为 |
|------|------|
| 星级按钮 | 点击第 N 颗星 → 选中 1-N 星 |
| 麦克风按钮 | 启动语音识别填入反馈 |
| "提交评价" | 提交评分 + 反馈 → Toast "感谢您的评价" → 返回盲人首页 |
| "跳过" | 直接返回盲人首页 |

### 表单字段
| 字段 | 类型 | 必填 | 语音输入 |
|------|------|------|----------|
| 星级评分 | 5 颗星点击 | 否 | — |
| 文字反馈 | 多行文本 | 否 | 是 |

### 状态展示
- 默认：5 颗空心星 + 空白反馈输入框
- 已选星级：前 N 颗星填充，后 5-N 颗空心
- 提交中：按钮显示 loading
- 提交成功：Toast "感谢您的评价" → 2 秒后自动返回首页

### 错误状态
- 评分提交失败 → Toast "提交失败，可稍后在服务记录中评价"
- 网络错误 → 保留已选评分状态，允许重试

### 空状态
不适用

### TTS 播报文案
- 进入页："服务已完成，感谢使用助盲跑。您可以为志愿者评分，评分不是必填项。"

### VoiceOver 建议
| 元素 | accessibilityLabel | accessibilityHint |
|------|--------------------|-------------------|
| 第 N 颗星 | "第 N 颗星" | "点击选中 1 到 N 颗星" |
| 已选评分 | "已选择 N 颗星" | — |
| 反馈输入框 | "评价反馈，选填" | "使用语音或键盘输入评价" |
| 麦克风按钮 | "语音输入评价" | — |
| "提交评价" | "提交评价" | — |
| "跳过" | "跳过评价，返回首页" | — |

### SwiftUI 布局建议
```
ScrollView {
    VStack(spacing: 24) {
        // 完成图标
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 64))
            .foregroundColor(.green)
        
        Text("服务已完成").font(.largeTitle)
        
        // 服务摘要
        VStack(alignment: .leading, spacing: 8) {
            Text("志愿者：\(volunteerName)").font(.headline)
            Text("出发地点：\(startLocation)").font(.subheadline)
            Text("服务时长：\(duration)").font(.subheadline)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        
        // 星级评分
        HStack(spacing: 12) {
            ForEach(1...5, id: \.self) { star in
                Button(action: { rating = star }) {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .font(.largeTitle)
                        .foregroundColor(star <= rating ? .yellow : .gray)
                }
            }
        }
        
        // 反馈输入
        TextField("写下您的评价（选填）", text: $feedback)
        
        // 操作按钮
        Button("提交评价") { submitRating() }
            .frame(minHeight: 64)
        Button("跳过") { dismissToHome() }
    }
    .padding()
}
```

### 旧 UI 可保留的部分
- 完成状态反馈
- 完成后返回首页的流程

### 旧 UI 必须修改的部分
- 旧版三档评价（好评/一般/差评）→ 替换为 1-5 星评分
- 旧版评价为强制 → 改为可选，增加 "跳过"
- 旧版缺少语音输入反馈 → 补齐麦克风按钮

---

## 9. 志愿者资料认证页

### 页面名称
志愿者资料认证页

### 页面目标
志愿者首次填写昵称并完成 Mock 认证，获得接单资格。

### 适用角色
志愿者

### 页面入口
角色选择页选择 "志愿者"（首次无认证资料时）/ 设置页 → 编辑资料

### 页面主要内容
- 标题："志愿者认证"
- 昵称输入框（必填）
- 手机号显示（自动填充登录手机号，只读）
- Mock 认证区域：
  - 提示文字："请完成以下认证步骤（Demo 版为模拟认证）"
  - "开始模拟认证" 按钮
  - 认证状态显示：not_submitted → 点击后 → pending → 1 秒后 → approved
  - 状态对应文案和图标
- "提交" 按钮（底部，最小 64pt）

### 主要按钮
| 按钮 | 条件 | 行为 |
|------|------|------|
| "开始模拟认证" | 昵称已填写 | 模拟认证流程：pending → approved（视觉反馈 1-2 秒） |
| "提交" | 昵称 + 认证完成 | 保存资料 → 进入志愿者首页 |

### 表单字段
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| 昵称 | 文本 | 是 | — |
| 手机号 | 只读文本 | — | 自动填充 |

### 状态展示
- not_submitted：提示完成认证
- pending：模拟认证进行中（spinner + "认证中..."）
- approved：绿色勾 + "认证通过"
- rejected：红色叉 + "认证未通过"（MVP Demo 不会出现此状态）

### 错误状态
- 昵称为空 → "请填写昵称"，提交按钮禁用
- 未完成认证 → 提示 "请先完成认证"，提交按钮禁用
- 网络错误 → "保存失败"

### 空状态
不适用

### TTS 播报文案
进入页："请填写志愿者资料并完成认证。认证为模拟流程，无需真实身份信息。"

### VoiceOver 建议
| 元素 | accessibilityLabel | accessibilityHint |
|------|--------------------|-------------------|
| 昵称输入框 | "昵称，必填" | — |
| 认证状态 | "认证状态：" + 当前状态中文 | — |
| "开始模拟认证" | "开始模拟认证" | "点击后自动完成模拟认证" |
| "提交" | "提交，保存资料" | — |

### SwiftUI 布局建议
```
Form {
    Section("基本信息") {
        TextField("昵称", text: $nickname)
        HStack {
            Text("手机号")
            Spacer()
            Text(phoneNumber).foregroundColor(.secondary)
        }
    }
    Section("志愿者认证") {
        Text("请完成以下认证步骤（Demo 版为模拟认证）")
            .font(.caption)
        HStack {
            Text("认证状态")
            Spacer()
            VerificationStatusBadge(status: verificationStatus)
        }
        if verificationStatus != .approved {
            Button("开始模拟认证") { startMockVerification() }
        }
    }
}
// 底部固定
VStack {
    Button("提交") { submit() }
        .buttonStyle(.borderedProminent)
        .frame(minHeight: 64)
        .disabled(!canSubmit)
}
.padding()
```

### 旧 UI 可保留的部分
- 资料摘要展示（从旧设置页/我的页抽象）

### 旧 UI 必须修改的部分
- 旧版认证散落在设置/我的页面 → 为独立首次流程页
- 旧版无 Mock 认证的视觉反馈流程 → 补齐状态变化动画
- **注意**：Mock 认证后 `isAvailable` 不自动开启，由志愿者首页可服务开关单独控制

---

## 10. 志愿者首页

### 页面名称
志愿者首页

### 页面目标
志愿者功能总览：查看附近订单、管理可服务状态、积分信息。

### 适用角色
志愿者

### 页面入口
认证完成 / 登录（已有认证资料）/ 服务完成返回 / 切换角色

### 页面主要内容
- **顶部用户信息栏**：昵称 + 积分余额（如 "350 积分"）
- **可服务开关**（Toggle，新志愿者默认关闭，需手动开启）
  - 开启：绿色 "可接单"
  - 关闭：灰色 "已关闭接单"
- **高德小地图**（上 1/3 区域）：显示当前位置 + 附近订单 marker
- **附近订单卡片列表**（前 3 个，按距离排序）：
  - 每张卡片：盲人昵称、距离、出发地点、预约时间
- "查看全部订单" 链接
- **底部标签栏**：首页 / 服务记录 / 积分商城 / 设置

### 主要按钮
| 按钮 | 行为 |
|------|------|
| 可服务开关 Toggle | 即时调用 API 更新状态 |
| 订单卡片 | 点击 → 进入订单详情页 |
| "查看全部订单" | 进入订单列表页 |
| 底部 Tab | 切换页面 |

### 表单字段
无（Toggle 是控件）

### 状态展示
- 可服务开：绿色 Toggle + "附近有 N 个可接订单" + 订单卡片显示距离
- 可服务关：灰色 Toggle + 订单仍可见（无距离数字）+ 接单按钮被禁用
- 定位不可用：地图灰色占位 + 订单无距离信息 + 接单按钮禁用 + 提示开启定位
- 定位正常但无订单：地图正常 + "暂无可用订单，请稍后再来"

### 错误状态
- 定位权限拒绝 → "需要开启定位权限才能查看距离和接单" + "去设置" 按钮
- 订单加载失败 → "加载失败，下拉重试"
- 网络错误 → 保留上次缓存数据

### 空状态
无可用订单 → 空状态插图 + "暂无可用订单，请稍后再来"

### TTS 播报文案
进入页："欢迎来到志愿者中心。可服务状态：" + 开/关 + "。附近有 " + N + " 个可接订单。"

### VoiceOver 建议
| 元素 | accessibilityLabel | accessibilityHint |
|------|--------------------|-------------------|
| 可服务开关 | "可服务开关，" + 当前状态 | "关闭后其他用户看不到你的接单状态，但不影响当前订单" |
| 订单卡片 | "盲人：" + 昵称 + "，距离：" + 距离 + "，" + 地点 + "，" + 时间 | "点击查看订单详情" |
| 积分余额 | "当前积分：" + 数字 + "分" | — |
| "查看全部订单" | "查看全部订单" | — |

### SwiftUI 布局建议
```
VStack(spacing: 0) {
    // 用户信息 + 可服务开关
    HStack {
        VStack(alignment: .leading) {
            Text(nickname).font(.headline)
            Text("\(points) 积分").font(.subheadline)
        }
        Spacer()
        Toggle("可服务", isOn: $isAvailable)
            .labelsHidden()
    }
    .padding(.horizontal)
    
    // 地图
    AMapContainer(location: currentLocation, markers: orderMarkers)
        .frame(height: UIScreen.main.bounds.height / 3)
    
    // 附近订单
    ScrollView {
        VStack(spacing: 12) {
            ForEach(nearbyOrders.prefix(3)) { order in
                OrderCardView(order: order, showDistance: locationAuthorized)
            }
            NavigationLink("查看全部订单") { OrderListView() }
        }
        .padding()
    }
    
    // 底部 TabBar
    TabBar(selectedTab: $selectedTab)
}
```

### 旧 UI 可保留的部分
- 地图 + 底部列表的空间模型
- 可服务开关放在首页首屏
- 定位失败状态文案

### 旧 UI 必须修改的部分
- 旧版 WebSocket 实时派单概念 → 改为静态加载
- 旧版可服务开关文案 "推送" → 改为 "可接单"
- 旧版接单前可能出现盲人电话 → 确保隐藏
- 旧版缺积分展示 → 补齐
- **注意**：可服务开关仅影响接新单，不影响当前已接订单

---

## 11. 志愿者订单列表页

### 页面名称
志愿者订单列表页

### 页面目标
展示所有 `matching` 状态可接订单，按距离排序。

### 适用角色
志愿者

### 页面入口
志愿者首页 → "查看全部订单" / 底部标签栏

### 页面主要内容
- 标题："可接订单"
- 顶部可服务开关（快速切换，无需回首页）
- 刷新提示
- 订单列表（List，支持下拉刷新）：
  - 每项卡片：盲人昵称、距离（定位可用时）、出发地点、预约时间、备注预览
  - 按距离从近到远排序
- 空状态（无订单时）

### 主要按钮
| 按钮 | 行为 |
|------|------|
| 可服务开关 | 即时切换 |
| 订单卡片 | 点击 → 进入订单详情页 |
| 下拉刷新 | 重新拉取列表 |

### 表单字段
无

### 状态展示
- 加载中：骨架屏 / spinner
- 加载完成：订单列表
- 某个订单被接走：下次刷新时从列表中移除
- 定位可用：显示距离数字
- 定位不可用：隐藏距离，接单按钮禁用
- 可服务关：订单可见但接单按钮禁用

### 错误状态
- 网络错误 → "加载失败，下拉重试"
- 定位权限拒绝 → "需要定位权限" 提示 + 距离隐藏 + 接单禁用

### 空状态
无 matching 订单 → 空状态插图 + "暂无可用订单" + "下拉刷新" 提示

### TTS 播报文案
（此页面非盲人端，TTS 不强制；但建议为 VoiceOver 完整做无障碍）
进入页："可接订单列表，共 " + N + " 个订单。"

### VoiceOver 建议
| 元素 | accessibilityLabel | accessibilityHint |
|------|--------------------|-------------------|
| 订单卡片 | "盲人：" + 昵称 + "，距离：" + 距离 + "，地点：" + 出发地点 + "，时间：" + 预约时间 | "点击查看详情" |
| 可服务开关 | "可服务开关" | — |
| 下拉刷新 | — | "下拉刷新订单列表" |

### SwiftUI 布局建议
```
VStack(spacing: 0) {
    // 顶部可服务开关
    HStack {
        Text("可服务")
        Toggle("", isOn: $isAvailable)
    }
    .padding(.horizontal)
    
    // 订单列表
    List {
        ForEach(orders) { order in
            NavigationLink(destination: OrderDetailView(orderId: order.id)) {
                OrderCardView(order: order, showDistance: locationAuthorized)
            }
        }
    }
    .refreshable { await loadOrders() }
    .overlay {
        if orders.isEmpty {
            ContentUnavailableView("暂无可用订单", systemImage: "figure.run", description: Text("下拉刷新试试"))
        }
    }
}
```

### 旧 UI 可保留的部分
- 地图 + 底部列表布局方向的视觉参考（此页为纯列表，地图已在首页）
- 下拉刷新

### 旧 UI 必须修改的部分
- 旧版接单在列表卡片内直接操作 → 新版本必须点击进入详情页再接单
- 旧版可能展示盲人电话 → 确保隐藏
- 旧版缺少可服务开关的快速切换

---

## 12. 志愿者订单详情页

### 页面名称
志愿者订单详情页

### 页面目标
展示订单完整信息，提供接单操作（接单前）/ 执行操作（接单后）。

### 适用角色
志愿者

### 页面入口
订单列表页 → 点击订单卡片

### 页面主要内容（接单前）
- **订单信息区**：
  - 出发地点
  - 预约时间
  - 目的地/路线（如有）
  - 预计时长（如有）
  - 预计距离（如有）
  - 配速偏好（如有）
  - 是否需要同性志愿者（如有）
  - 备注（如有）
- **盲人非敏感信息**：昵称（**不含**联系电话、紧急联系人）
- **高德地图**：显示出发地点 marker、当前志愿者位置、距离数值
- **"接单" 按钮**（底部固定，绿色醒目，最小 64pt）

### 页面主要内容（接单后）
- 订单信息同上
- **盲人完整信息**：昵称 + 联系电话（可点击拨打）
- "查看地图" 按钮（显示高德地图出发点、当前位置、距离，不做路线导航）
- "我已到达" 按钮
- "取消订单" 按钮
- "一键求助" 按钮

### 主要按钮
| 按钮 | 可见条件 | 行为 |
|------|----------|------|
| "接单" | 接单前 | 确认弹窗 → `POST /api/orders/{id}/accept` → 成功切换接单后 UI |
| "查看地图" | 接单后 | 显示出发点位置、当前位置和距离信息 |
| "我已到达" | 接单后（状态为 accepted） | `POST /api/orders/{id}/arrive` → 状态变 arrived |
| "取消订单" | 接单后（状态为 accepted / arrived） | CancelReasonSheet → cancelled |
| "一键求助" | 接单后（状态为 accepted / arrived） | DangerConfirmDialog → emergency |

### 表单字段
无（取消时弹出 CancelReasonSheet）

### 状态展示
- 加载中：骨架屏
- 接单前：完整订单信息 + 隐藏电话 + "接单" 按钮
- 接单后：显示电话 + "查看地图" + "我已到达" + 危险操作
- 接单中：按钮 loading

### 错误状态
- 接单失败（ORDER_ALREADY_ACCEPTED）→ Toast "该订单已被其他志愿者接单" → 返回列表
- 接单失败（网络）→ "接单失败，请重试"
- 地图显示失败 → "无法显示地图，请重试"

### 空状态
不适用

### TTS 播报文案
（非盲人端，TTS 不强制）

### VoiceOver 建议
| 元素 | accessibilityLabel | accessibilityHint |
|------|--------------------|-------------------|
| "接单" | "接单" | "确认接单后将显示盲人联系方式" |
| 盲人电话（接单后） | "拨打盲人电话 " + 号码 | — |
| "查看地图" | "查看出发点位置" | "显示出发点、当前位置和距离" |
| "我已到达" | "我已到达约定地点" | — |
| "取消订单" | "取消订单" | "需要选择取消原因并确认" |
| "一键求助" | "一键求助" | "确认后将标记为异常状态" |

### SwiftUI 布局建议
```
ScrollView {
    VStack(spacing: 16) {
        // 订单信息
        OrderInfoSection(order: order)
        
        // 地图
        AMapContainer(location: currentLocation, markers: [orderMarker])
            .frame(height: 200)
        if locationAuthorized {
            Text("距离出发点：\(distance)").font(.subheadline)
        }
        
        // 盲人信息
        BlindRunnerInfoCard(runner: order.blindRunner, showPhone: isAccepted)
        
        // 操作区
        if !isAccepted {
            LargePrimaryButton("接单") { showAcceptConfirm = true }
                .frame(minHeight: 64)
        } else {
            VStack(spacing: 12) {
                Button("查看地图") { showMapDetail = true }
                    .frame(minHeight: 52)
                Button("我已到达") { arrive() }
                    .frame(minHeight: 52)
                Button("取消订单", role: .destructive) { showCancelSheet = true }
                Button("一键求助", role: .destructive) { showEmergencyConfirm = true }
                    .frame(minHeight: 64)
            }
        }
    }
    .padding()
}
```

### 旧 UI 可保留的部分
- 接单后显示电话的隐私分级
- 地图展示出发点

### 旧 UI 必须修改的部分
- 旧版在列表卡片内直接接单 → 改为独立详情页再接单
- 旧版 "导航" → 改为 "查看地图"（不做路线导航）
- 旧版缺接单确认弹窗 → 补齐
- 旧版缺取消原因选择 → 补齐 CancelReasonSheet

---

## 13. 志愿者服务中页

### 页面名称
志愿者服务中页

### 页面目标
志愿者管理 accepted / arrived / in_progress 各阶段的订单执行。

### 适用角色
志愿者

### 页面入口
接单成功后进入（accepted 状态）/ 从首页或列表点击当前订单

### 页面主要内容
- **状态指示区**：
  - accepted：绿色 + "已接单，请前往约定地点"
  - arrived：蓝色 + "已到达，等待盲人确认开始服务"
  - in_progress：绿色 + "服务进行中"
- **盲人信息卡片**：昵称 + 联系电话（可点击拨打）
- **订单信息**：出发地点、预约时间
- **高德小地图**：出发地点 marker
- **底部操作区**（根据状态变化）：
  - accepted："我已到达" + "取消订单" + "一键求助"
  - arrived："等待盲人确认开始..." + "一键求助"
  - in_progress："结束服务" + "一键求助"

### 主要按钮
| 按钮 | 可见状态 | 行为 |
|------|----------|------|
| "我已到达" | accepted | `POST /api/orders/{id}/arrive` → arrived |
| "取消订单" | accepted / arrived | CancelReasonSheet → cancelled |
| "结束服务" | in_progress | DangerConfirmDialog（可选服务总结） → completed |
| "一键求助" | accepted / arrived / in_progress | DangerConfirmDialog → emergency |
| 盲人电话 | 始终（接单后） | 系统拨号 |

### 表单字段
服务总结输入框（选填，结束服务时弹出，多行文本）

### 状态展示
- accepted：显示 "我已到达" 按钮
- arrived：等待盲人确认提示（非按钮操作），显示求助按钮
- in_progress：显示 "结束服务" 按钮
- 每 5 秒轮询（监听盲人确认开始、紧急求助）

### 错误状态
- 网络错误 → 保留当前 UI，静默重试
- 结束服务失败 → Toast "操作失败，请重试"
- 到达标记失败 → Toast "操作失败"

### 空状态
不适用

### TTS 播报文案
（非盲人端，TTS 不强制）
进入 in_progress 时："服务已开始"（可选播报）

### VoiceOver 建议
| 元素 | accessibilityLabel | accessibilityHint |
|------|--------------------|-------------------|
| "我已到达" | "我已到达约定地点" | — |
| "结束服务" | "结束服务" | "需要使用二次确认" |
| "取消订单" | "取消订单" | "需要选择取消原因并确认" |
| "一键求助" | "一键求助" | "确认后将标记为异常状态" |
| 盲人电话 | "拨打盲人电话 " + 号码 | — |

### SwiftUI 布局建议
```
VStack(spacing: 0) {
    ScrollView {
        VStack(spacing: 16) {
            // 状态指示
            StatusBanner(status: order.status)
            
            // 地图
            AMapContainer(location: currentLocation, markers: [orderMarker])
                .frame(height: 200)
            
            // 盲人信息
            BlindRunnerInfoCard(runner: order.blindRunner, showPhone: true)
            
            // 订单信息
            OrderInfoSection(order: order)
        }
        .padding()
    }
    
    // 底部操作栏（根据状态变化）
    VStack(spacing: 12) {
        if order.status == .accepted {
            LargePrimaryButton("我已到达") { arrive() }
            Button("取消订单", role: .destructive) { showCancelSheet = true }
        } else if order.status == .arrived {
            Text("等待盲人确认开始服务...").foregroundColor(.secondary)
        } else if order.status == .inProgress {
            LargePrimaryButton("结束服务") { showCompleteConfirm = true }
        }
        Button("一键求助", role: .destructive) { showEmergencyConfirm = true }
            .frame(minHeight: 64)
    }
    .padding()
}
.onAppear { startPolling() }
.onDisappear { stopPolling() }
```

### 旧 UI 可保留的部分
- 地图全屏背景 + 底部操作面板
- 接单后才展示电话
- 完成结算反馈

### 旧 UI 必须修改的部分
- 旧动作链 `inProgress → driverEnRoute → driverArrived → completed` → 替换为 `accepted → arrived → in_progress → completed`
- 旧版缺少等待盲人确认开始的状态（arrived） → 补齐
- 旧版 "我已出发" 动作 → 删除（不在当前状态机中）
- 旧版结束服务缺少二次确认和可选服务总结 → 补齐
- 旧版结算积分 `+50` → 改为 `+100`

---

## 14. 志愿者服务记录页

### 页面名称
志愿者服务记录页

### 页面目标
展示志愿者的历史服务记录（已完成/已取消）。

### 适用角色
志愿者

### 页面入口
志愿者首页底部标签栏 → "服务记录"

### 页面主要内容
- 标题："服务记录"
- 订单列表（按时间倒序）：
  - 每项卡片：服务时间、盲人昵称、出发地点、状态标签、获得积分
- 状态标签颜色：已完成 - 绿色，已取消 - 灰色

### 主要按钮
| 按钮 | 行为 |
|------|------|
| 记录卡片 | 点击 → 只读订单详情 |
| 下拉刷新 | 重新加载 |
| "去接单"（空状态） | 跳转订单列表页 |

### 表单字段
无

### 状态展示
- 加载中：骨架屏
- 有记录：按时间倒序列表
- 每项显示 `+100 积分`（已完成）或 `—`（已取消）

### 错误状态
- 网络错误 → "加载失败，下拉重试"

### 空状态
无服务记录 → 空状态插图 + "暂无服务记录" + "去接单" 按钮（跳转订单列表页，最小 64pt）

### TTS 播报文案
（非盲人端，TTS 不强制）

### VoiceOver 建议
| 元素 | accessibilityLabel | accessibilityHint |
|------|--------------------|-------------------|
| 每条记录 | "时间：" + 时间 + "，盲人：" + 昵称 + "，地点：" + 出发地点 + "，状态：" + 状态 + "，积分：" + 积分 | — |
| "去接单" 按钮 | "去接单" | "点击查看可接订单" |

### SwiftUI 布局建议
```
List {
    ForEach(serviceRecords) { record in
        NavigationLink(destination: OrderDetailView(orderId: record.orderId, readOnly: true)) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(record.date).font(.headline)
                    Spacer()
                    StatusBadge(status: record.status)
                }
                Text("盲人：\(record.blindRunnerName)").font(.subheadline)
                Text("地点：\(record.startLocation)").font(.caption)
                if record.status == .completed {
                    Text("+\(record.points) 积分").font(.caption).foregroundColor(.green)
                }
            }
        }
    }
}
.refreshable { await loadRecords() }
.overlay {
    if serviceRecords.isEmpty {
        ContentUnavailableView("暂无服务记录", systemImage: "clock", description: Text("完成服务后记录将显示在这里"))
        // "去接单" 按钮
    }
}
```

### 旧 UI 可保留的部分
- 简洁倒序记录卡片
- 历史 Tab 独立页面

### 旧 UI 必须修改的部分
- 旧版积分显示 `+50` → 改为 `+100`
- 旧版空状态缺少 "去接单" 按钮 → 补齐
- 旧版缺只读详情入口 → 补齐

---

## 15. 志愿者积分/商城占位页

### 页面名称
积分商城（占位页）

### 页面目标
展示积分余额和积分商城占位信息（MVP 不做真实兑换）。

### 适用角色
志愿者

### 页面入口
志愿者首页底部标签栏 → "积分商城"

### 页面主要内容
- 积分余额大数字（如 "0 积分"）
- 积分获取规则："每完成一次服务 +100 积分"
- "积分商城即将上线，敬请期待" 占位区域
  - 插图/图标
  - 占位文字
- 几个假商品卡片（仅供展示，"敬请期待" 标记）：
  - 运动腰包
  - 运动水壶
  - 运动毛巾
  - 跑步腰灯

### 主要按钮
无实际交互按钮（假商品卡片不可点击）

### 表单字段
无

### 状态展示
- 积分余额从后端读取
- 假商品固定展示

### 错误状态
- 积分加载失败 → 显示 "--"

### 空状态
积分余额始终显示（可能为 0），无空状态

### TTS 播报文案
（非盲人端，TTS 不强制）

### VoiceOver 建议
| 元素 | accessibilityLabel | accessibilityHint |
|------|--------------------|-------------------|
| 积分余额 | "当前积分：" + 数字 + "分" | — |
| 假商品卡片 | 商品名 + "，敬请期待" | — |

### SwiftUI 布局建议
```
ScrollView {
    VStack(spacing: 24) {
        // 积分余额
        VStack {
            Text("\(points)")
                .font(.system(size: 48, weight: .bold))
            Text("积分")
                .font(.headline)
            Text("每完成一次服务 +100 积分")
                .font(.caption).foregroundColor(.secondary)
        }
        .padding()
        
        // 商品占位
        Text("积分商城即将上线，敬请期待")
            .font(.headline)
        
        LazyVGrid(columns: [.init(), .init()], spacing: 16) {
            ForEach(placeholderProducts) { product in
                VStack {
                    Image(systemName: product.icon)
                        .font(.largeTitle)
                    Text(product.name).font(.caption)
                    Text("敬请期待").font(.caption2).foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
    }
    .padding()
}
```

### 旧 UI 可保留的部分
- 积分余额大数字展示样式
- 商品网格布局（仅视觉参考）

### 旧 UI 必须修改的部分
- 旧版有 "兑换" 按钮 → 删除，不提供任何可点击的兑换操作
- 旧版固定余额 `1,250 分` → 从后端读取真实余额
- 商品卡片不可交互（仅是视觉占位）

---

## 16. 设置页

### 页面名称
设置页

### 页面目标
提供个人资料、角色切换、API 环境、关于、退出登录入口。

### 适用角色
盲人跑者、志愿者（通用）

### 页面入口
盲人首页 / 志愿者首页 → 设置入口

### 页面主要内容
- **用户信息摘要**（顶部）：昵称、手机号、当前角色
- **菜单列表**：
  - 个人资料 → 进入对应角色资料编辑页
  - 切换角色 → 角色选择页（检查活跃订单）
  - API 环境 → 选择器（Mock / 本地后端 / 生产后端）
  - 关于 → App 名称、版本号、Build 号
  - 退出登录 → 红色文字，底部独立，二次确认

### 主要按钮
| 按钮 | 行为 |
|------|------|
| 个人资料 | 跳转对应角色资料编辑页（复用盲人资料页/志愿者认证页） |
| 切换角色 | 检查活跃订单 → 角色选择页 |
| API 环境 | 选择器即时切换 |
| 关于 | 展示版本信息 |
| 退出登录 | DangerConfirmDialog → 清除 token → 登录页 |

### 表单字段
无（纯菜单 + API 环境选择器）

### 状态展示
- 当前角色标签：盲人跑者 / 志愿者
- 当前 API 环境标签：Mock / 本地 / 生产

### 错误状态
- 退出登录失败 → "退出失败，请重试"
- 切换角色被拦截 → 弹窗 "您有进行中的订单，无法切换角色"

### 空状态
不适用

### TTS 播报文案
进入页："设置页面。当前角色：" + 角色名

### VoiceOver 建议
| 元素 | accessibilityLabel | accessibilityHint |
|------|--------------------|-------------------|
| 退出登录 | "退出登录" | "退出后需要重新登录，需要二次确认" |
| 切换角色 | "切换角色" | — |
| API 环境 | "API 环境，" + 当前环境 | — |

### SwiftUI 布局建议
```
List {
    // 用户信息
    Section {
        HStack {
            Text(nickname).font(.headline)
            Spacer()
            Text(phoneNumber).foregroundColor(.secondary)
        }
        HStack {
            Text("当前角色")
            Spacer()
            Text(currentRoleLabel).foregroundColor(.secondary)
        }
    }
    
    // 菜单
    Section {
        NavigationLink("个人资料") { ProfileEditView() }
        Button("切换角色") { checkAndSwitchRole() }
        Picker("API 环境", selection: $apiEnvironment) {
            Text("Mock").tag("mock")
            Text("本地后端").tag("local")
            Text("生产后端").tag("production")
        }
        NavigationLink("关于") { AboutView() }
    }
    
    // 退出登录
    Section {
        Button("退出登录", role: .destructive) { showLogoutConfirm = true }
    }
}
```

### 旧 UI 可保留的部分
- 双角色设置入口思路

### 旧 UI 必须修改的部分
- 旧版退出无二次确认 → 补齐
- 旧版缺少 API 环境切换 → 补齐
- 旧版缺少角色切换拦截提示 → 补齐
- 旧版盲人资料和志愿者认证散落在此 → 剥离为独立页，设置页仅提供入口

---

## 共享组件规格

### LargePrimaryButton
```swift
// 盲人端主操作按钮
// 最小高度 64pt
// 高对比度背景色（如 Color.blue 或 Color.accentColor）
// 大号字体（.title3 或以上）
// accessibilityLabel 和 accessibilityHint 必须设置
```

### StatusCard
```swift
// 订单状态卡片
// 包含：大号状态图标/动画 + 状态中文 + 一行辅助说明
// 背景：圆角卡片， muted 背景色
// 7 个状态各自有对应颜色和文案
```

### DangerConfirmDialog
```swift
// 危险操作确认弹窗
// 使用 .alert 或自定义 sheet
// 取消订单："确认取消订单？取消后无法恢复。"
// 紧急求助：固定文案 "是否确认进入求助状态？确认后，本次服务将标记为异常，系统会记录当前订单状态。"
// 结束服务："确认结束本次服务？"
// 退出登录："确认退出登录？退出后需要重新登录。"
// 必须有两个按钮："取消"（取消操作）和 "确认"（执行操作）
```

### CancelReasonSheet
```swift
// 取消原因选择
// 5 个固定选项：时间不合适、地点填写错误、临时有事、联系不上对方、其他
// Picker 或 ActionSheet 形式
// 选择后确认 → 调用取消 API
```

### RepeatStatusButton
```swift
// 重复当前状态按钮
// 每个盲人端关键页面的固定底部元素
// accessibilityLabel: "重复当前状态"
```

### AMapContainer
```swift
// 高德地图 UIViewRepresentable 桥接
// 入参：centerCoordinate, markers, showsUserLocation
// 不接受导航请求
// 错误时显示灰色占位
```

---

## 状态与中文文案对照表

| 状态 | 盲人端文案 | 志愿者端文案 | 图标/颜色 |
|------|------------|-------------|-----------|
| `matching` | 匹配中，等待志愿者接单 | 可接订单 | 橙色旋转 |
| `accepted` | 志愿者已接单，正在赶来 | 已接单，请前往约定地点 | 绿色勾 |
| `arrived` | 志愿者已到达，请确认开始服务 | 已到达，等待盲人确认 | 蓝色铃铛 |
| `in_progress` | 服务已开始，请注意安全 | 服务进行中 | 绿色播放 |
| `completed` | 服务已完成，感谢使用助盲跑 | 服务完成，+100 积分 | 绿色对勾 |
| `cancelled` | 本次预约已取消 | 订单已取消 | 灰色叉 |
| `emergency` | 已进入求助状态 | 已进入求助状态 | 红色感叹号 |

---

## 紧急求助固定文案

```
是否确认进入求助状态？确认后，本次服务将标记为异常，系统会记录当前订单状态。
```

---

## 不迁移清单

以下旧 Flutter UI / 行为明确不迁移：

- Flutter Widget / Riverpod / go_router 架构
- WebSocket 实时派单 / 重连状态 / 连接状态 UI
- "AI 语音助手" 入口和气泡
- "现在出发" "明天上午" "今天晚上" 自然语言时间选择
- `pendingMatch` `pendingAccept` `driverEnRoute` `driverArrived` `rematching` `noVolunteer` 状态和对应 UI
- "我已出发" 动作按钮
- 接单前展示盲人电话
- 三档评价（好评/一般/差评）
- `+50` 积分显示
- 商城 "兑换" 按钮
- 没有二次确认的取消/退出/结束
- 旧 API 路径和参数名
