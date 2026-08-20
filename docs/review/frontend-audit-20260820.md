# 前端审计 2026-08-20：传输安全、位置真实性、跑中突发、双方互信

范围：`blindRun/` iOS 前端全仓（不含后端；后端由另一路并行审计）。
方法：读代码 + 对撞后端契约 `demo/docs/api_spec.yaml` + 两条平台事实联网核实
（见 `docs/research/ios-location-pause-and-ats-20260820.md`）。

**与前三份 review 的关系**：`docs/review/INDEX.md` 里三份已有报告的结论**本轮不重复**。
本报告只收它们没覆盖的问题。三份报告仍未修的老问题（隐私号、横屏 iPad、平台内消息、
转子 / Switch Control 等）不在这里重列。

## 0. 先说三条「查过了，不是问题」——防止下一轮重新提

| 疑点 | 结论 |
|---|---|
| `BackendCoordinateNormalizer.normalize(...) ?? 原坐标` 在 4 处调用点静默降级，会不会用未转换的 WGS-84 当 GCJ-02？ | **不是问题**。`normalize` 只在 `sample.isValid == false`（经纬度越界）时返回 `nil`（`blindRun/Map/CoordinateSystem.swift:37-38`），此时兜底用的是同一个本来就无效的坐标，不存在"该转没转" |
| `Info.plist` 里没有 `NSLocationWhenInUseUsageDescription`，而代码只调 `requestWhenInUseAuthorization()` | **不是问题**。该键在 `blindRun.xcodeproj/project.pbxproj:536,572,754` 以 `INFOPLIST_KEY_` 形式提供，构建时合并 |
| `LiveEscortHealthState` 算出来了但没人订阅？ | **有人订阅**。`blindRun/ContentView.swift:397-421`：`onReceive` 播报 + 底部横幅，且有跨订阅重放闸 |

---

## F1 · P0 · 明文 HTTP/WS + JWT 放在 URL query + 24 小时不刷新 = 同一个 WiFi 能拿走整个账号

**事实链**

- `blindRun/Core/EnvironmentConfig.swift:110`：`static let baseURL = URL(string: "http://47.114.113.171")!`
- `blindRun/Info.plist:16-28`：对该 IP 开 `NSExceptionAllowsInsecureHTTPLoads`
- `blindRun/Core/WebSocketService.swift:225-233`：
  ```swift
  components.scheme = baseURL.scheme == "https" ? "wss" : "ws"
  components.queryItems = [URLQueryItem(name: "token", value: token)]
  ```
- 全仓无 `URLSessionDelegate` / `SecTrust` / pinning（本轮全仓搜索，0 命中）
- 后端 `docs/api_spec.yaml:2262-2263` 提到 token 的自然有效期是 **24 小时**；
  前端全仓无 `refreshToken` / `/auth/refresh`（0 命中）

**为什么这条排第一**：与"一般 App 走明文"不同，这条链上跑的是——盲人的实时 GCJ-02 坐标、
双方手机号、紧急联系人、求助事件、身份证核验流程的入口。同一段公共 WiFi 上的旁观者
抓一次包就拿到一个**还能用 24 小时**的 Bearer token；拿到之后可以读订单详情（含盲人姓名电话）、
读实时位置、以受害者身份触发或（若是盲人 token）撤销求助。JWT 放在 URL query 里更糟：
它会进 Nginx access log、进任何中间代理的日志，而不像 header 那样至少不被默认记录。

**前端能独立做的**（后端上 TLS 之前的缓解，不是替代）
1. WS 鉴权从 query 换成 `Sec-WebSocket-Protocol` 子协议或连接后首帧 AUTH —— 需要后端配合，
   **已列入 handoff 提问**。
2. `NSExceptionAllowsInsecureHTTPLoads` 保留但补 `NSExceptionMinimumTLSVersion` 预案，
   并在提交材料里准备理由 —— 注意 Apple 举的合格理由是"**别人**管的服务器不支持 TLS"，
   "我们自己的服务器还没配"不在其列（见调研报告 §2）。
3. **把这条列为发布阻断项**：内测（TestFlight 外部）首个构建要过 App Review。

**不建议**：自签证书 + pinning。那是把一个可验证的问题换成一个更难排查的问题。

---

## F2 · P0 · 「对方位置是 15 秒内的」这句话不成立——新鲜度测的是转发时刻，不是采样时刻

**事实链**

1. 发送端取样本**不判年龄**，注释明说是故意的：
   `blindRun/Map/LocationService.swift:265-272`
   ```swift
   /// 同行会话按固定 cadence 复用最近一次真实设备样本；静止不等于定位失效。
   /// 只有权限撤销或 Core Location 明确报告失败时才暂停发送。
   func latestEscortBackendSample() -> LocatedCoordinate? {
       guard isAuthorized, locationError == nil, let sample = latestDeviceSample else { return nil }
   ```
   （对照：求助路径的 `latestBackendSample(now:freshness:)` **有** 15 秒新鲜度闸，`:259-263`）
2. 发送端每 5 秒无条件重发一次：
   `blindRun/Core/LiveEscortSessionCoordinator.swift:30`（`reportInterval = 5`）、`:247-257`
3. 上行报文**没有采样时间字段**：
   `blindRun/Core/Models/WebSocketModels.swift:28-38`，`WSLocationUpdateMessage` 只有 `type/lat/lng`
4. 接收端拿到的 `timestamp` 是**服务端转发时打的**：
   `blindRun/Core/AppRealtimeCoordinator.swift:616,627` → `timestampMilliseconds: message.timestamp`
5. 接收端就拿这个时间戳判新鲜：
   `blindRun/Core/LiveEscortSessionCoordinator.swift:143-156`，`peerFreshness = 15`

**后果**：GPS 卡住（隧道、地库、商场、iOS 自动暂停，见 F3）时，Core Location 常常**不报错**，
只是不再送新样本。于是发送端每 5 秒把同一个陈旧坐标重发一次，服务端每次打上当前时间，
接收端每次都判定"这是 15 秒内的新位置"。志愿者看到的地图点在动（其实是同一个点），
盲人端的"距出发地点约 XX 米"也一直在给一个已经过期的数字。

**两端都不会告警**：`refreshHealth`（`:259-277`）只在 `latestEscortBackendSample() == nil` 时进
`.waitingForLocation`，而陈旧样本永远不是 nil，健康状态会一直停在 `.active`。

**修法（按成本排序）**
- 客户端先自救（不需要后端）：给 `latestEscortBackendSample()` 加一个样本年龄出参，
  超过阈值（建议 60 秒，明显大于 `distanceFilter` 触发间隔，避免正常静止时误报）就
  ① 把 `healthState` 打成 `.waitingForLocation`（播报已经接好了）
  ② 停止重发或改发一个带"陈旧"标记的心跳。
- 对齐要后端补 `capturedAt`：`WSLocationUpdateMessage` 加采样时间、透传给对端 —— **写 handoff**。
- 回归用例：构造"样本停更 90 秒"→ 断言 `healthState == .waitingForLocation`
  且不再产生 `escort-location-send` 的 `finished` 事件。
  测试接缝已有（`LiveEscortSessionCoordinator.init(reportInterval:sendLocation:)`）。

---

## F3 · P0 · 志愿者赶来 / 双方碰头这两个阶段，iOS 可能已经把定位悄悄关了

`blindRun/Map/LocationService.swift:245-257`：

```swift
func setEscortBackgroundMode(enabled: Bool) {
    guard isEscortBackgroundModeEnabled != enabled else { return }   // ← 初值 false
    ...
    locationManager.pausesLocationUpdatesAutomatically = !enabled
```

`isEscortBackgroundModeEnabled` 初值是 `false`，所以**第一次以 `enabled: false` 调用时整段被 guard 掉**，
`pausesLocationUpdatesAutomatically` 保持 CoreLocation 的默认值 `true`。
而 `evaluateSession`（`LiveEscortSessionCoordinator.swift:210`）只在 `IN_PROGRESS` 传 `true`：

```swift
let needsBackground = activeStatus == .inProgress
locationService?.setEscortBackgroundMode(enabled: needsBackground)
```

即 `DRIVER_EN_ROUTE` / `DRIVER_ARRIVED` 全程开着自动暂停。

Apple 文档原文（2026-08-20 核实，见调研报告 §1）：

> After a pause occurs, it's your responsibility to restart location services again…
> **For apps that have in-use authorization, a pause to location updates ends access to location
> changes until the app launches again and is able to restart those updates.**

本 App 只申请 in-use（全仓无 `requestAlwaysAuthorization`），且**没有实现**
`locationManagerDidPauseLocationUpdates(_:)`（全仓 0 命中）。所以：志愿者在路上等红灯、
或到了集合点站着等人——正是"位置不变"的典型场景——iOS 判定可以暂停，之后**到 App 重启为止**
都不再有新位置，而 App 完全不知道，还在按 F2 那条路每 5 秒重发最后一个坐标。

**这是 F2 最常见的触发器，且发生在最不能出事的阶段**：盲人正在原地等一个据说"已到达"的人。

**修法**：`setEscortBackgroundMode` 里把 `pausesLocationUpdatesAutomatically = false` 提到
guard 之前无条件设置（或在 `init` 里就设成 `false`）；同时实现 `didPause` 回调，
在里面 `startUpdating()` 并把健康状态打成 `.waitingForLocation`。
两处改动都在同一个文件，**总计不到 10 行**。

---

## F4 · P1 · 登出从不解绑 APNs token —— 上一个人的求助推送会在这台手机上被念出来

- 前端只有注册，没有解绑：全仓 `"/api/devices/apns"` 的调用点只有
  `blindRun/Core/PushNotificationsManager.swift:107` 一处 `post`；**0 处 `delete`**。
- `performLocalSessionCleanup()`（`blindRun/Core/AppState.swift:612-637`）清了 token、userId、
  角色、补读游标……**没有**解绑设备推送。
- 后端契约把这件事写得很直白（`demo/docs/api_spec.yaml:2775-2792`）：
  > 设备上登出、但没有别人再登录时，token 仍绑在旧 userId 上……
  > **token 删不掉，洞照样在。这一条读代码看不出来，请写进登出流程的注释。**

**后果**：后端只对 `priority=HIGH` 补发 APNs——也就是求助、走散告警、到达、取消预警这几类。
设备转手 / 借用 / 换人登录后，上一个账号的这些推送继续投递到这台手机，
而 `PushNotificationsManager.userNotificationCenter(_:willPresent:)`（`:121-128`）
**会直接把内容朗读出来**。

**修法**：`performLocalSessionCleanup` 之前（token 还在时）调一次
`DELETE /api/devices/apns`，失败不阻断登出但要留诊断事件；同时清 `lastReportedScope` 与 `pendingToken`。
契约说该接口幂等、失败可安全重试。

---

## F5 · P1 · 常用出发地点（通常就是家庭住址）明文落 UserDefaults，且登出不清

`blindRun/BlindRunner/FavoritePlaceStore.swift:24,105-108`：

```swift
private static let storageKey = "aidrun.favorite-start-places.v1"
...
private func persist() {
    guard let data = try? JSONEncoder().encode(places) else { return }
    defaults.set(data, forKey: Self.storageKey)
}
```

存的是 `ResolvedPlace`：`title` + `addressText` + 经纬度（5 位小数 ≈ 1 米）。
`UserDefaults` 是 App 容器里的明文 plist，**进 iTunes/iCloud 备份**，无 data protection class。

两个问题叠在一起：
1. 与本仓库自己的既定标准冲突。同一个仓库里，身份证号写着"只在内存中短暂存在，不写入
   `UserDefaults`、Keychain 或任何日志"（`blindRun/Profile/BlindIdentityVerificationView.swift:25`），
   证书文件写着"不落 UserDefaults/Keychain"（`VolunteerCertificateUploadView.swift:22`）。
   而一个视障用户的常去地点集合，泄露价值不比身份证号低——它直接是"这个人什么时候会在哪"。
2. **登出不清除**。`performLocalSessionCleanup` 的 `removeObject` 清单（`AppState.swift:629-636`）
   里没有这个 key，`FavoritePlaceStore` 也不在任何会话生命周期里。换账号登录后，
   上一个人的常用地址原样还在。

**修法**：① 把这份数据搬到 Keychain（`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`，
它不需要锁屏可读）或加密后落文件并设 `.completeUnlessOpen`；② 无论选哪种，
`performLocalSessionCleanup` 里必须清掉。②比①急。

---

## F6 · P1 · 24 小时 token + 无刷新 + 任何一个 401 立刻硬登出，对「服务进行中」零保护

- `blindRun/Core/APIClient.swift:362`：`case 401: throw APIError.unauthorized`
- `blindRun/Core/AppState.swift:651-656`：`handleAuthenticatedAPIError` 见到 `.unauthorized`
  就 `expireSession()` → `clearSession()`（断 WS、清 token、清角色、清紧急联系人）
- 该函数在**24 个调用点**被调用，其中包括盲人订单详情页的 5 秒轮询
  （`BlindOrderStatusView.swift:181,222,311,374,426,450`）
- 无 refresh：全仓 `refreshToken` / `/auth/refresh` 0 命中；后端也只在切角色时重签一枚新 token

**后果**：陪跑进行中若命中一次 401（token 到点、后端重启、Nginx 抖一下——2026-08-16 那次
308 重定向事故就制造过一批伪 401），盲人当场被踢回登录页：求助入口、位置共享、订单状态
**同时消失**，而他正在户外、看不见屏幕、需要重新走一遍短信验证码流程。

**修法（前端可独立做）**：`handleAuthenticatedAPIError` 增加一条判据——
当 `liveEscortCoordinator.isSessionEligible`（即订单在 `DRIVER_EN_ROUTE`…`IN_PROGRESS`）时，
第一次 401 不清会话，改为：保留页面 + 播报"连接需要重新验证，正在重试"+ 重试一次；
连续两次才 `expireSession()`。这不放松安全（token 真失效时第二次照样 401），
只是不再让一次抖动毁掉现场。**根因修法是后端加 refresh token —— 写 handoff。**

---

## F7 · P1 · 云端求助失败后，没有一个能按的「拨110」

`blindRun/Safety/SafetyModule.swift:256-276`（`BlindHomeSOSBar`）失败时只渲染一段文字：

```swift
if mode == .cloudTrigger, let message = coordinator.state.message {
    EmergencyStatusNotice(message: message, isFailure: coordinator.state.isFailure)
}
```

而文案是 `"求助未发出：\(detail)。请重试，或直接拨打110。"`（`SafetyModule.swift:44-47`）。

同一个文件里，非进行中状态的本地拨号分支做得很完整——弹窗、拨 110、拨主联系人、
没有唯一主联系人时的提示（`:140-158`）。**恰恰是最危险的分支（进行中 + 求助发不出去）
没有接上那套已经写好的 UI。**

最坏时序：等定位 5 秒（`EmergencyCoordinator.locationWaitTimeout`）+ 请求超时 15 秒
（`APIClient.swift:245`）= 盲人按下按钮后最长 20 秒才听到"求助未发出"，
然后要自己退出 App、盲操作找到电话、拨 110。

**修法**：`state.isFailure`（含 `.unsentNoLocation` / `.failed` / `.cooldown`）时，
在 notice 下面复用已有的本地拨号弹窗入口。不新增文案、不新增逻辑，接一个已有的 action。
**这是本报告里性价比最高的一条。**

---

## F8 · P1 · 信息是单向的：志愿者知道盲人是谁，盲人只知道一串号码

对撞 `OrderDetailResponse`（`blindRun/Core/Models/OrderModels.swift:302-331`）：

| 志愿者能看到盲人的 | 盲人能看到志愿者的 |
|---|---|
| `blindName` 姓名（接单后）、`blindPhone` 手机号、配速偏好、是否有导盲犬、沟通偏好、接单后的自由文本备注 | `volunteerPhone` 手机号，**没有了** |

**契约里根本没有 `volunteerName` 字段**（全仓 + 契约核实）。评分、服务次数、实名认证状态、
资质证书审核结果，全部只在志愿者**自己**的成就页/设置页可见
（`VolunteerHomeView.swift:1515`、`VolunteerAchievements.swift`），盲人端一个都拿不到。

**这对"信任度"的影响是结构性的**：一个陌生人走过来说"我是来陪你跑步的志愿者"，
看不见的人手上**没有任何可核验的信息**——不知道对方姓名，不知道对方通过没通过审核，
不知道对方带过几次。（前三份 review 里 §6.2-#28 记过"志愿者过往评价对盲人不可见"，
但没指出**连名字都没有**这件事，也没给零后端依赖的兜底方案。）

**修法**
- 后端补 `volunteerName`（接单后返回）→ **写 handoff**。这是根因。
- 在那之前，前端有一个**不需要任何后端改动**的兜底：**会合口令**。
  订单号两端都有，取后 4 位当口令，盲人端在 `DRIVER_ARRIVED` 的播报里念出来，
  志愿者端在"我已到达"按钮附近显示同一串。盲人问一句"报一下后四位"，
  就把"来的是不是接单那个人"变成可验证的。实现量约等于两处文案 + 一个取模函数。

---

## F9 · P1 · 「已到达」之后没有任何方位信息，而那正是最需要的一刻

- 到达文案只有一句：`"志愿者已到达约定地点，请等待志愿者开始服务。服务开始前不能结束订单。"`
  （`blindRun/Core/Models/OrderModels.swift:179-181`）
- 唯一的数字是 `volunteerDistanceToStartText`（`OrderDisplayHelpers.swift:433-436`）——
  算的是**志愿者距"出发地点"**，不是**志愿者距"你"**：
  ```swift
  let meters = DistanceCalculator.distance(from: volunteerCoordinate, to: startCoordinate)
  return "距出发地点约 \(DistanceCalculator.formattedDistance(meters))"
  ```
- 地图上的对方位置标记 `accessibilityHidden(true)`（`BlindOrderStatusView.swift:1128-1159`），
  纯视觉装饰
- 全仓无任何方位/朝向信息：`几点钟方向` / `衣着` / `挥手` / `CLHeading` 全部 0 命中

**后果**：陪跑没有车牌车型颜色（代码注释自己写了这句，`BlindOrderStatusView.swift:1164-1178`），
到达之后双方唯一的会合手段是打电话。而这一段本来是前端手里数据最全的地方——
两个 GCJ-02 坐标 + `CLLocationManager.heading`，够算出"志愿者在你前方偏右，约 15 米"。

**修法**：`DRIVER_ARRIVED` 时把距离口径换成"志愿者距**你当前位置**"，并加一句相对方位。
`CLHeading` 要开 `startUpdatingHeading()`（现在没开）。这条纯前端，不碰契约。
注意方位播报要跟着刷新且能被"重复当前状态"取到。

---

## F10 · P2 · 号码保护只做了一半：一端刻意不念，另外两处照样明文

`blindRun/BlindRunner/BlindOrderStatusView.swift:1196-1199` 记着一条明确的决定——
拨号按钮不念号码，因为 VoiceOver 外放会把号码广播给周围的人。

同一条理由在另外两处没有执行：

```
blindRun/BlindRunner/BlindRunnerHomeView.swift:933-936
if let volunteerPhone = order.volunteerPhone, !volunteerPhone.trimmed.isEmpty {
    Text("志愿者电话：\(volunteerPhone)")          // ← 盲人端首页，明文渲染
```

```
blindRun/Volunteer/VolunteerOrderFlowViews.swift:2869-2872
Label(phone, systemImage: "phone.fill")            // ← 号码作为可见文本
.accessibilityLabel("拨打盲人电话 \(phone)")        // ← 读屏念全号
```

而且志愿者端两个拨号点（`VolunteerOrderFlowViews.swift:2559,2865`）都是
`openURL(URL(string: "tel://\(phone)"))` 直出，**没有走 `EmergencyDialer`**，
也就没有那套 `#if DEBUG` 拨号拦截接缝——UI 测试里志愿者端误触会真的拨出去
（同类事故记忆：`snapshot-timeout-means-a-system-app-took-over`）。

**修法**：两处号码渲染改成掩码（`EmergencyContactsView.swift:434` 已经有 `maskedPhone` 可参照）；
志愿者端拨号统一走 `EmergencyDialer.telURL/dial`。

---

## F11 · P2 · 「志愿者迟到 / 失联 / 半路走了」客户端没有任何自己的判断

- 超时、走散、信号丢失全部依赖后端推送
  （`ORDER_OVERDUE` / `ESCORT_DISTANCE_ALERT` / `ESCORT_SIGNAL_LOST`，
  `AppRealtimeCoordinator.swift:712-716,736-754,877-908`），客户端只做优先级抬升和展示位。
- 而后端消息要么走 WS（断网就没有），要么走 APNs——**APNs 授权被拒是静默的**：
  ```swift
  // blindRun/Core/PushNotificationsManager.swift:57-64
  UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
      guard granted else { return }
  ```
  拒绝之后没有任何提示、没有留痕、没有二次引导，用户永远不知道兜底通道是关的。

**后果**：三个条件同时成立（WS 断 + 推送没授权 + 后端事件发不出来）时，盲人会一直等下去，
App 一句话都不会说。而前端手里其实有 `plannedStart`、`plannedEnd` 和当前状态——
**本地定时判断是唯一在断网时还能起作用的那条路**。

**修法**：加一个纯本地的逾期判断（约定开始时间 + N 分钟仍未到 `DRIVER_ARRIVED` → 播报 +
给出"打电话 / 取消重派"两个动作）。它与后端 `ORDER_OVERDUE` 不冲突：后端到了就以后端为准，
去重按 `messageId`。另外 `requestAuthorization` 的 `granted == false` 至少要记一条诊断事件，
并在安全相关页面提示一次"离线提醒已关闭"。

---

## F12 · P2 · 四处「失败了但谁也不知道」

| 位置 | 现象 |
|---|---|
| `blindRun/Core/KeychainTokenStore.swift:48-56` | `SecItemAdd` / `SecItemDelete` 的 `OSStatus` 直接 `_ =` 丢弃。写失败（例如设备开机后从未解锁，`AfterFirstUnlock` 不可写）时登录看起来成功，token 只在内存里，下次冷启动莫名"登录已过期" |
| `blindRun/Core/APIClient.swift:382-470` | `upload` 与普通请求共用 `timeoutIntervalForResource = 20`（`:246`），而证书上传上限 5 MB（`VolunteerCertificateUploadView.swift:120`）——弱网需要持续 2 Mbps 才不超时；且 `upload` 路径**一条 `recordDiagnostic` 都没有**，最容易超时的路径反而没有诊断留痕，用户只看到"网络连接失败，请检查网络设置" |
| `blindRun/Safety/SafetyModule.swift:41-42` | `locationUnavailable` 把所有定位失败都说成权限问题（"请在设置中允许定位后重试"）。而 `LocationService.locationError` 明明区分了 `.permissionDenied` 和 `.locationUnavailable`（`LocationService.swift:7-11`）——室内拿不到 GPS 时，让盲人在紧急状态下去翻设置是把时间花在错的地方 |
| `blindRun/BlindRunner/BlindOrderStatusView.swift:1405-1419` | `shareRunPlanBySMS` 的前两个 guard 失败都 `speakError` 播报，第三个（`RunPlanShareMessage.compose` 返回 nil）直接 `return`——盲人点了"分享行程"，没有任何声音 |

另附一条影响面较小但方向相同的：`blindRun/Volunteer/VolunteerHomeView.swift:205`
用 `try?` 吞掉已接订单的拉取失败，网络抖一下志愿者首页的订单就"消失"了，无提示。

---

## 待后端确认（本轮新增，**尚未**投递到 `demo/docs/handoff.md`）

> 本轮按要求不动后端仓库（另有并行会话在审计后端），所以这五条只落在这里。
> 谁先拿到后端仓库的写权限，把它们按 `AGENTS.md` §10-8 的格式追加到「待后端确认」。


1. `WSLocationUpdateMessage` 能否加 `capturedAt`（采样时刻），并由服务端原样透传给对端？—— F2 的根因修法
2. WS 鉴权能否从 URL query 移到 `Sec-WebSocket-Protocol` 或连接后首帧？—— F1 缓解
3. 接单后的 `OrderDetailResponse` 能否补 `volunteerName`（以及可选的服务次数 / 评分）？—— F8 根因
4. 有没有 refresh token 的计划？24 小时硬过期 + 401 即登出对"服务进行中"是安全事故 —— F6
5. `47.114.113.171` 上 TLS 的排期 —— F1

## 复核触发条件

后端上 TLS / 加 refresh token / 补 `capturedAt` 或 `volunteerName` 任一落地；
`LocationService` 或 `LiveEscortSessionCoordinator` 有改动；登出流程有改动；
iOS 大版本改 CoreLocation 暂停语义。
