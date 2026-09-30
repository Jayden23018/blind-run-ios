# TestFlight 外部测试 · Test Information 草稿

> 起草 2026-09-27，基线 `origin/main` @ `b3b17ed`。对应 `pre-launch-checklist.md` §C0「写好 Beta App Description
> 与审核备注草稿」、§C0.5 第 7 步；依据 `review/testflight-readiness-20260927.md` §2 ⑤、
> `research/testflight-readiness-delta-20260927.md` §4（两份都在 PR #235）。
>
> **本文件是草稿源，填进 App Store Connect 时整段复制。** 改了功能 / 改了后端配置，先改这里再改 ASC。

## 0. 填表前还缺什么

| 项 | 状态 |
|---|---|
| 审核专用账号（盲人 + 陪跑员各一） | ⏳ 等后端 [blind-run-backend#454](https://github.com/Jayden23018/blind-run-backend/issues/454)。答复后填 §2.3 |
| 录屏链接 | ⏳ 按 §3 录完上传后替换 §2.2 里的 `<VIDEO_URL>` |
| 联系人姓名 / 电话 / 邮箱、Feedback Email | ⏳ 负责人定 |
| 时区问题 | 🟡 代码已修（formatter 固定按 `Asia/Shanghai` 生成与解析，见 §4 第 1 条，跟踪 [#236](https://github.com/Jayden23018/blind-run-ios/issues/236)），**但要等含该修复的构建上传后才对审核员生效**。在那之前，§2.2 里「把设备时区切到北京」那一段**仍要保留**；新构建上传并验过后可删 |
| 开跑同意闸 | 🔴 跑者端没有确认开始的按钮，陪跑员只能在开跑 + 15 分钟后开始（§4 第 5 条）。补上之前，§2.2 第 6 步与 §3 的等待段**必须保留** |
| iPad | 已定只支持 iPhone（2026-09-30，`TARGETED_DEVICE_FAMILY = 1`）。备注没提 iPad，不用改 |

## 1. Beta App Description

测试员在 TestFlight 邀请里看到这一段。**只写当期构建里真有的功能**（`pre-launch-checklist.md` §B1），
§B2 里的不写（隐私号中转、iPad / 横屏、固定搭档、用户侧客服入口）。

### 中文

```text
助盲跑是一款帮视障跑者预约志愿陪跑员的 App。跑者用语音或读屏说出出发地点和时间，系统就近派单给已实名、已审核的陪跑员；陪跑员接单后出发，双方能看到彼此位置，见面后一起跑步，跑完生成跑步记录。

整个 App 按 VoiceOver 设计，跑者端所有操作都能不看屏幕完成。

本轮想请你重点试这几件事：
1. 用 VoiceOver 走一遍：登录、预约陪跑、查看订单进度。哪里读不出来、顺序乱、按钮找不到，请告诉我们。
2. 语音预约：说出地点和时间，看识别和确认是否顺利。
3. 陪跑员出发后，跑者端能否及时听到「正在赶来」「已到达」等进度播报。
4. 跑步中的节奏提示、暂停，以及跑完后的跑步记录。
5. 紧急联系人的添加与管理。

请注意：
- 预约开始时间至少在 30 分钟以后，最远 7 天；晚上 22:00 到早上 05:00 之间不提供陪跑。
- 求助按钮只在陪跑进行中可用，会真实通知我们的客服并尝试联系你的紧急联系人，测试时请不要按。
- 这是测试版，请勿把它当作唯一的安全保障。

有问题请直接回复邀请邮件。
```

### English

```text
AidRun helps blind and low-vision runners book a volunteer running guide. The runner says where and when they want to run — by voice or with VoiceOver — and the app dispatches the request to nearby volunteers whose identity has been verified and approved. Once a volunteer accepts, both sides can see each other's location on the way, meet up, run together, and get a run record afterwards.

The whole app is designed for VoiceOver; everything on the runner side can be done without looking at the screen.

In this round we would especially like you to try:
1. Signing in, booking a run and following the order status with VoiceOver on. Tell us where something is not read out, the reading order is confusing, or a button is hard to find.
2. Voice booking: saying the place and time, and confirming them.
3. After the volunteer sets off, whether the runner hears progress updates such as "on the way" and "arrived" in time.
4. Pace cues and pausing during the run, and the run record afterwards.
5. Adding and managing emergency contacts.

Please note:
- A run must start at least 30 minutes from now and at most 7 days ahead. Runs are not available between 22:00 and 05:00.
- The help (SOS) button is only available during an active run. It alerts our support team for real and tries to reach your emergency contact, so please do not press it while testing.
- This is a beta. Do not rely on it as your only safety measure.

To report a problem, just reply to the invitation email.
```

## 2. Beta App Review Information

### 2.1 字段对照

| ASC 字段 | 填什么 |
|---|---|
| Sign-in required | 勾选 |
| User name | 审核跑者账号的手机号（§2.3） |
| Password | 固定验证码（§2.3） |
| Review Notes | §2.2 整段，≤ 4000 字符 |
| Contact | ⏳ |

ASC 的 Sign-in 字段只有一组用户名 + 密码，所以填**跑者**账号；陪跑员账号写不进专用字段。
⚠️ 检索说明要求账号不进备注（`research/testflight-readiness-delta-20260927.md` §4），
而核心流程必须两个账号。**陪跑员账号放哪里**等 #454 答复后与负责人一起定：
要么在备注里写陪跑员号码（只写号码、不写验证码，验证码与跑者相同），要么请审核员通过联系方式索取。
下面的草稿按「备注里只写 See Sign-in field」写，没有泄露任何号码。

### 2.2 Review Notes（英文，填进 ASC）

```text
AidRun (UI in Simplified Chinese) matches blind runners with volunteer running guides. The core flow needs TWO accounts on TWO iPhones: a Runner (books a run) and a Volunteer (accepts it).

VIDEO of the full two-device flow: <VIDEO_URL>

SIGN IN
Enter the phone number from the Sign-in field, tap the button to get a code, then enter the fixed code (also in the Sign-in field). No SMS is sent to these test numbers. Both accounts are already verified; no ID or face check will be asked.

BEFORE YOU START (both devices)
1. Set the time zone to Shanghai, China: Settings > General > Date & Time > turn off Set Automatically > Time Zone. Our server runs on China time; with a US time zone, bookings are rejected as "in the past". This is a known issue we are fixing.
2. Runs cannot overlap 22:00-05:00 China time, which is 07:00-14:00 US Pacific Daylight Time (06:00-13:00 PST after Nov 1). Please book from 13:30 PDT for a start at 14:00 or later.
3. Allow Location on both devices. Keep the two devices within 5 km of each other; volunteers are matched by distance to the start point.

STEPS (the whole flow takes about 50 minutes, mostly waiting for the start time)
1. Volunteer device: sign in, swipe the slider right to start taking orders, keep the app open in the foreground.
2. Runner device: sign in, tap "预约新的陪跑" (book a run). Start point: keep "当前位置" (current location); address search only covers mainland China. Start time: 30-35 minutes from now. Submit with "提交预约".
3. Volunteer device: an invitation appears, usually within a minute. Tap "接下这次陪跑" (accept).
4. The first order between two accounts has an "intro call" step. You do NOT need to call. Runner: tap "和这位志愿者通话确认", then "聊过了，合适". Volunteer: tap "合适，接这一单". Please do not dial any number shown; they are test numbers.
5. Volunteer: tap "我出发了" (on my way), then "我已到达集合点" (arrived). The runner device shows the volunteer's progress.
6. Volunteer: tap "开始跑步" (start run). In this build it is accepted from 15 minutes AFTER the planned start time; an earlier tap shows a "wait for the other side" message. The runner device then counts down and the run begins.
7. Volunteer: long-press "长按 2 秒，结束陪跑" (finish). Both devices show the completed run.

OUTSIDE MAINLAND CHINA
Maps and address search come from AMap (Gaode), a mainland-China provider. Outside China the map may show little detail and search returns no results. Matching and the order flow do not depend on them: coordinates are used as-is and matching is by distance.

PERMISSIONS
- Location (When In Use): sets the start point, matches nearby volunteers, and shares both people's positions from "on my way" until the run ends. Background location (UIBackgroundModes: location) is turned on ONLY while a run is in progress, because the blind runner's phone is locked in a pocket; the blue indicator is shown and it stops when the run ends. We never request Always.
- Microphone + Speech Recognition: blind users describe the place, route and notes by voice instead of typing. Only while the voice button is active.
- Motion & Fitness: steps, cadence and elevation gain, recorded only during an active run and shown in the run record. Optional; running works without it.
- Camera: volunteer identity liveness check at sign-up. The review accounts are already verified, so you will not see it.
- Notifications: new orders and order status.

HELP / SOS - PLEASE DO NOT TRIGGER
The help (SOS) button only sends an alert while a run is in progress. The alert goes to our real support staff, and the server tries to text the account's emergency contact. At any other time the help button only offers to dial the emergency contact or local emergency numbers (110/120). Please do not dial them either.
```

### 2.3 账号（⏳ 等 #454）

<!-- #454 答复后填：跑者号码 / 陪跑员号码 / 固定验证码是否长期开启 / 紧急联系人填的是谁的号 -->

## 3. 录屏脚本（两台手机）

给审核员看的是「两端怎么配合走完一单」，不是宣传片。画面按时间顺序拼两台手机（左右分屏或交替切），
**等待段直接剪掉，字幕注明「此处等待约 N 分钟」**。按钮名以 `origin/main` @ `b3b17ed` 的界面原文为准，
改版后先对一遍再拍。

**文案红线（AGENTS.md §6，字幕、旁白、画面都适用）**：
- 不说、不写「已通知家属」「联系人已收到短信」「短信已送达」，也不写任何意思相同的话
- 录屏**不触发求助**，也不演示拨号；求助入口只拍到它存在

### 3.1 拍摄前

| 项 | A = 陪跑员手机 | B = 跑者手机 |
|---|---|---|
| 账号 | 审核陪跑员账号（§2.3） | 审核跑者账号（§2.3） |
| 时区 | 设成上海（和审核备注要求一致，顺便验证这个写法走得通） | 同左 |
| 定位 | 允许；两台手机放在一起 | 同左 |
| 屏幕录制 | 控制中心开录屏，**关麦克风**（避免录进周围人声） | 同左 |
| 账号状态 | 没有进行中的单 | 没有未完成的单（最多 3 张，且时段冲突会被拒） |

开拍时刻：北京时间 05:00–21:00 之间（整段行程不能碰 22:00–05:00，含跑步时长）。

### 3.2 步骤

| # | 手机 | 操作 | 画面上应看到 |
|---|---|---|---|
| 1 | A | 登录：输入手机号 →「获取验证码」→ 输入固定验证码 →「登录」 | 陪跑员首页 |
| 2 | A | 滑块「向右滑动，开始接单」滑到底 | 滑块变为「接单中」。**之后 A 一直停在前台**，进后台超过 30 秒会收不到派单 |
| 3 | B | 同样登录 | 跑者首页 |
| 4 | B | 「预约新的陪跑」→ 出发点保留「当前位置」→「下一步：预约时间」→ 选 **30–35 分钟后** →「下一步：跑步需求」→「下一步：确认预约」→「提交预约」 | 「正在匹配陪跑员」 |
| 5 | A | 等派单弹出（一般 1 分钟内），点「接下这次陪跑」 | 进入通话磨合页 |
| 6 | B | 页面变为「有位志愿者想陪你跑」，点「和这位志愿者通话确认」→「聊过了，合适」 | **不点**「打电话给这位志愿者」 |
| 7 | A | 「合适，接这一单」 | 订单页进入「约好」态 |
| 8 | A | 「我出发了」 | B 显示「…正在赶来」 |
| 9 | A | 「我已到达集合点」 | B 显示「…已到达」 |
| — | | ✂️ **剪掉等待**：一直等到**计划开跑时刻 + 15 分钟**（原因见 §4 第 5 条）。字幕：「此处等待约 N 分钟」 | |
| 10 | A | 「开始跑步」 | B 播「准备开始」「握好引导绳」三秒倒计时，两端进入跑步中 |
| 11 | A、B | 各拍一下跑步中页面，镜头带过求助入口（A 右上角「求助与安全」、B 的「一键求助」）**但不点** | 字幕：「求助仅在跑步中可用，审核时请勿触发」 |
| 12 | A | 按住「长按 2 秒，结束陪跑」 | 两端都显示「服务已完成」 |
| 13 | B | 进入跑后记录（「这次跑步」），再回到评价区，可以点「跳过评价并返回首页」 | 结束录屏 |

步骤 10 如果在「开跑 + 15 分钟」之前点，A 会弹「还需要对方在手机上确认可以开始……」，
这段要剪掉。跑者端确认按钮补上之后，删掉这段等待，并同步改掉 §2.2 第 6 步。

### 3.3 拍完

- 两段录屏按上表顺序剪成一个视频，**时长控制在 5 分钟内**，上传到审核员打开链接就能看、不用登录的位置，把链接填进 §2.2 的 `<VIDEO_URL>`
- 回看一遍：画面里有没有露出真实手机号（通话磨合页会显示号码）、有没有露出紧急联系人信息。露了就打码

## 4. 起草时核实过的事实

每条都是改了就要回来改 §1–§3 的前提。

1. **时区**：`BlindBookingView.makeCreateOrderRequest`（`blindRun/BlindRunner/BlindBookingView.swift:930`）用
   `DateFormatter.aidRunBackendLocalDateTime`（`blindRun/Core/Models/OrderDisplayHelpers.swift:1084`）格式化，
   该 formatter 原先**没设 `timeZone`** ⇒ 用设备时区；后端把无偏移的本地时间按 `Asia/Shanghai` 解释
   （后端 `DemoApplication.java:51`，契约 `OpenApiConfig` 时间约定）。美西设备比北京慢 15 小时，
   选「40 分钟后」在后端看来是十几小时前 ⇒ 400。**已修（#236）**：formatter 现在固定 `Asia/Shanghai`，
   夜间窗口也按北京钟点判，用例见 `blindRunTests/BackendTimeZoneTests.swift`。含此修复的构建上传前，
   仍靠「切设备时区到北京」规避。
2. **下单限制**（契约 `POST /api/orders` 描述，`docs/api_spec.yaml` 约 1420–1440 行）：≥ 30 分钟后、≤ 7 天、
   时长 ≤ 300 分钟、整段不碰 `[22:00, 05:00)`、最多 3 张未完成、与已有单时段冲突拒绝；
   跑者须已实名且至少 1 个紧急联系人。
3. **派单**：第 1/2/3 轮半径 5 / 10 / 20 km（后端 `application.properties` `app.dispatch.round*-distance-km`）；
   陪跑员位置在 Redis 只留 30 秒，断线或 App 进后台超过 30 秒就收不到派单（后端 `docs/test-accounts.md` §4.7）。
4. **通话磨合**：`app.intro-call.enabled=true`，两人没磨合过、且离开跑还塞得下 20 分钟窗口时必须先走这一步；
   两个表态按钮不要求先拨号（`VolunteerIntroCallView` / `BlindIntroCallView` 的按钮只受提交中状态禁用）。
5. **开跑时间闸**：「已出发」最早开跑前 60 分钟，「开始陪跑」最早开跑前 15 分钟
   （后端 `app.order.en-route-earliest-minutes` / `start-service-earliest-minutes`）。
   开跑前 > 240 分钟被接单会进 `SCHEDULED_CONFIRMED`，多一步临期确认 ⇒ 备注里写 30–35 分钟。
   🔴 **还有一道同意闸，而跑者端没有按钮去过它**：陪跑员调 `/start-service` 时，跑者没确认过
   （`blindStartConfirmedAt == null`）就回 409 `BLIND_CONFIRMATION_PENDING`，直到 `plannedStartTime + 15 分钟`
   才放行（后端 `OrderLifecycleService.startService` 约 221–250 行，`app.order.blind-confirm-grace-minutes=15`）。
   后端已经允许跑者自己调 `/start-service`（等同确认 + 开始），但 iOS 跑者端没有「开始跑步」按钮，
   全仓也没有调 `/confirm-start` 的地方；`BlindOrderStatusView.swift:956` 的注释仍写着「盲人 token 调不动」，
   已过期 ⇒ 当前构建里陪跑员最早在**开跑 + 15 分钟**才能开始，下单到开跑至少等 45 分钟。
   跟踪在 [blind-run-backend#307](https://github.com/Jayden23018/blind-run-backend/issues/307)
   （iOS 09-24 答复：等后端下发 `earliestServiceStartAt` 等字段后一起接 `confirm-start`）。
6. **结束**：`/finish` 没有时间闸；陪跑员在界面上长按 2 秒（`VolunteerOrderFlowViews.swift` 约 3119–3141 行）。
7. **境外坐标**：`BackendCoordinateNormalizer.wgs84ToGCJ02` 在中国境外原样返回（`blindRun/Map/CoordinateSystem.swift`），
   契约对起点经纬度只有 ±90 / ±180 的范围校验 ⇒ 境外能下单、能按距离派单。
   ⚠️ **高德底图在境外实际显示成什么没有实测**，备注里的措辞因此只说「可能细节很少」。
8. **后台定位**：只申请 When In Use（`LocationService.requestPermission`）；`allowsBackgroundLocationUpdates`
   只在 `IN_PROGRESS` 打开（`LiveEscortSessionCoordinator.evaluateSession`）。位置共享从 `DRIVER_EN_ROUTE` 起（`isSessionEligible`）。
9. **运动数据**：只在 `IN_PROGRESS` 记录（`LiveEscortSessionCoordinator.syncMotionRecording`），两个角色都记。
10. **权限文案**：`blindRun/Info.plist` 与 pbxproj 的 `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription`；
   App 没有 `.lproj`，界面只有简体中文。
