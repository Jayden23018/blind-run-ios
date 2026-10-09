## Context

- 现有求助闸门只看「坐标是否真实、是否 15 秒内」（`LocationService.latestBackendSample`）。模糊位置的样本同样来自
  `CLLocationManager`，能原样穿过这道闸。
- SDK 事实（iOS 26.2 SDK 头文件，2026-10-09 核对）：
  - `CLAccuracyAuthorizationReducedAccuracy`：「horizontalAccuracy on the order of about 5km」，系统把位置 snap 到区域代表点，样本最旧可能 20 分钟。
  - `requestTemporaryFullAccuracyAuthorization(withPurposeKey:)`：用途键必须在 `NSLocationTemporaryUsageDescriptionDictionary` 里；
    前台期间不过期；开着后台定位指示器的持续定位会话期间也不过期。App 在后台时系统可能不弹。
  - `locationManagerDidChangeAuthorization` 在 `accuracyAuthorization` 变化时也回调。
- 仓库已有阈值：陪跑员端 `VolunteerRunTip.weakAccuracyMeters = 50`（`VolunteerRunningCompanion.swift:213`）。盲人端沿用 50 米。
- 下单页已有「定位被拒 → 可听可见的降级告知，不拦截」先例（`BlindBookingViewModel.locationDegradationNotice`）。
- 项目负责人 2026-10-09 拍板：精确位置关闭时云端求助**不发**（按无定位处理）；下单**不用**当前位置，改走搜索。

## Goals / Non-Goals

**Goals:**
- 盲人端识别精确位置关闭，在求助、下单、陪跑三处各自给出可听可见的告知。
- 区分「精确位置关闭」（坐标是假点 → 拦）与「精确授权但精度差于 50 米」（坐标有误差 → 照用并说明）。
- 精确位置关闭时，在需要的时刻申请临时精确位置。

**Non-Goals:**
- 不改求助请求体与后端契约（不加精度字段）。
- 不改陪跑员端（求助取坐标、健康提示、临时精确位置都不动）。
- 不停发陪跑中的同行位置：陪跑员端的方位盘本来就按 `accuracyM` 放宽扇形。
- 语音下单向导的就近消歧坐标（`latestBackendSample(freshness: 300)`）不拦：它只用于 50 公里半径消歧，5 公里误差不改变结果。

## Decisions

1. **判定集中在 `LocationService`**：发布 `accuracyAuthorization`，提供 `isPreciseLocationOff`（已授权且为 reduced）和
   `requestTemporaryPreciseLocation(for:)`。DEBUG 接缝 `simulatePreciseLocationOffForTesting(_:)` 与请求记录，单测不碰硬件。
   UI 测试的演示定位视为精确位置开启，保持现有 UI 用例不变。
2. **阈值放在 `LocationAccuracyPolicy.weakAccuracyMeters = 50`**（`blindRun/Map/`），不直接引用陪跑员端的提示条常量；
   用一条单测钉住两者相等。陪跑员端那个常量不改（避开 PR #370 正在改的同一文件）。
3. **求助拦截放在 `EmergencyCoordinator.freshEmergencyCoordinate(using:)`**：它是盲人端唯一的取坐标入口。
   精确位置关闭时直接返回 nil，不等 5 秒。失败原因走新增的 `LocationError.preciseLocationOff`，由
   `EmergencyCoordinator.locationFailureReason(using:)` 统一产出，盲人端三个调用点改用它。
   `LocationService.locationError` 从不取这个值 —— 它只是求助文案的分岔依据，不进陪跑会话的闸门。
   - 求助时**不**弹临时精确位置申请：系统弹窗会和「求助未发出」的播报抢读屏焦点，而跑步开始时已经申请过一次。
4. **误差说明挂在协调器上**：`trigger` 记下所发坐标的精度（差于 50 米才记），`statusMessage` 在「已发出或即将发出」
   的状态后面附加说明。所有界面渲染点与协调器内的首句播报改读 `statusMessage`；每秒倒数那句不加，避免每秒重复。
5. **下单页**：`locationDegradationNotice(isDenied:isPreciseLocationOff:)` 增加一档，视图把两种告知共用同一个渲染函数、
   按钮按档位不同。`resolvedStartPlace` 在精确位置关闭时不返回设备来源的地点；`refreshCurrentLocation` 清空当前位置解析结果，
   **不**自动申请临时精确位置（进页时语音向导正在开场，系统框会抢读屏焦点），只由告知里的按钮申请。
   精度差于 50 米时把那次解析所用样本的精度存下来，卡片显示提示，由提示的 `onAppear` 念一次（语音态下表单不渲染，天然避开向导开场）。
6. **陪跑健康**：`LiveEscortHealthState` 新增 `.preciseLocationOff`，只在盲人角色、已授权之后判定，优先于网络与样本档位
   （模糊位置下样本可能 20 分钟才来一个，否则会被「位置暂时不可用」盖住真正的原因）。
   申请时机照「运动与健身」权限的先例：出发去会合时申请一次，系统框不在起跑那一刻抢读屏焦点；
   那时还没开后台定位指示器，临时授权在 App 进后台后可能过期，所以进 `IN_PROGRESS` 时若仍关着再申请一次（按「订单 + 阶段」去重）。

## Risks / Trade-offs

- 拒绝了临时精确位置的用户，在本单陪跑中无法发出云端求助 → 健康横幅全程可见可听，求助失败文案给出 110 / 120，
  本地拨号兜底按钮由 `isFailure` 驱动照常出现。这是负责人拍板接受的取舍。
- 临时申请的弹窗可能不出现（App 在后台、系统自行决定）→ 告知文案写「如果弹出提示……」，同时给「去设置」入口。
- 无法在单测里驱动真实的 `CLLocationManager` 授权变化 → 真机手动走一遍（设置里关掉精确位置后进下单页与跑步页），结果写进 PR。
