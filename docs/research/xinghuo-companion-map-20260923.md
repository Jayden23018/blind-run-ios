# 「星火同行」陪伴地图 MVP → iOS 落地前的调研与差距核对（2026-09-23）

输入：项目负责人给的单文件 HTML 原型 `~/Downloads/星火同行 · 助盲跑陪伴地图 MVP.html`（本地实测点过跑者视角全流程）。
它和 09-11 / 09-13 / 09-21 那条「一束光地图」线（PR #174，全国、城市级聚合、夜光卫星底图）**不是同一个产品**：
这份是**以「你」为中心的 2 公里局部地图 + 即时请求陪跑 + 声音化**。本篇只补那几份没覆盖的三段：
声音化、「身边有人」怎么展示、即时匹配。隐私与合规结论直接沿用 09-13 / 09-21，不重搜。

## 1. 原型里每一块，数据从哪来（契约取自后端 `origin/main` 2d169f1，2026-09-21；本轮 `git fetch` 失败，未拉到更新的提交）

| 原型元素 | 契约里有没有 | 依据 |
|---|---|---|
| 金星「沿光线向你走来」 | ✅ 有，且是**精确坐标、只给已匹配那一对** | WS `VOLUNTEER_LOCATION_UPDATE`，`DRIVER_EN_ROUTE` / `DRIVER_ARRIVED` / `IN_PROGRESS` 三态推送（`websocket-protocol.md:90-112`）；REST 兜底 `GET /api/blind/volunteer-location` |
| 今日足迹（自己这次的路线） | ✅ 有 | `GET /api/orders/{id}/track`；iOS 已有 `CompletedTrackSummaryView` / `OrderRouteReplayView` |
| 「已通过陪跑员认证」 | ✅ 有 | `/api/volunteer/verification`、`/api/volunteer/training/*` |
| 深色底图 | ✅ 一行 | 高德 `MAMapTypeStandardNight`（09-13 报告已核头文件） |
| 志愿者视角「N 位跑者在等待」 | ⚠️ 只有列表不带坐标 | `GET /api/orders/available` → `AvailableOrderResponse` 只有 `startAddress` + `distanceKm`，**刻意不给坐标**（spec 注释：起点+终点+时间=可跟踪行踪） |
| 「你身边 2 公里内 56 位志愿者，最近在东边 200 米」 | ❌ 无 | spec 搜 `nearby` / `在线志愿者` / `grid` / `模糊` 全 0 命中；志愿者位置只存在 Redis、TTL 30 秒 |
| 顶栏全局统计（在线数 / 同行中 / 今日公里） | ❌ 无 | 09-21 已实测 `distribution|aggregat|/stats` 0 命中 |
| 「请求陪跑 → 约 3 分钟到你身边」 | ❌ 与产品规则冲突 | AGENTS §5：下单距开跑 ≥30 分钟（`APPOINTMENT_TOO_SOON`），「没有『现在就跑』」；陌生人之间还有 `PENDING_INTRO_CALL` 通话磨合 |
| 「一位志愿者在华侨城附近亮了起来」 | ❌ 且已被判为隐私通道 | 09-13 报告：增量为 1 的实时点亮 = Sweeney 时序攻击，k 取多少都失效 |

iOS 侧现状：接驳阶段盲人端**实际看不到地图**，只念/显示距离文字。

> 🔄 **同日订正**：初稿写的是「盲人端全仓没有一处渲染地图」，**那是错的** —— 当时只搜了 `AMapContainer(`，而盲人端全走包装层 `MapViewWrapper(`：订单页有 `peerMapSection`（`BlindOrderStatusView.swift:2552`，180pt、志愿者一枚紫色大头针），完成页有轨迹地图（`CompletedTrackSummaryView` → `TrackRouteMap`）。「接驳阶段看不到」这个结论仍然成立，但原因不同：09-16 四步骨架上线后，`peerMapSection` 只挂在只读退路 `trackingContent` 里，而那条退路只在未知态与终态渲染。教训与记忆 `synonym-mismatch-fakes-a-missing-feature` 同类：**断言「没有」前要搜包装层与同义符号。**

## 2. 声音化（「听见星光」）—— 外面怎么做

- **Microsoft Soundscape**（2018–2023，现由开源后继 VoiceVista 延续）是最接近的先例：3D 音频让地点「从它所在的方向发声」，
  **前提是戴立体声耳机**，用的是合成双耳音频（binaural），朝向靠手机指南针、后期靠 AirPods 头部追踪。
  它的按需按钮「Around Me」一次只念 **4 个**点、「Ahead of Me」**5 个** —— 不是把所有东西同时放出来。
  来源：[AFB AccessWorld](https://afb.org/aw/19/8/15067)、[Microsoft Research 功能页](https://www.microsoft.com/en-us/research/product/soundscape/features/)、[Perkins](https://www.perkins.org/resource/microsoft-soundscape-app-being-discontinued/)
- **「越近音越高 + 左右声道表方向」这套映射在文献里是常见组合**（PLOS One 2021 手机摄像头导航辅助：频率与距离负相关、双耳差表方向；
  Oh/Kane/Findlater 的手势教学研究里 pitch + stereo panning 胜出）。但**这些研究基本都用耳机**。
  来源：[PLOS One 2021](https://journals.plos.org/plosone/article?id=10.1371%2Fjournal.pone.0237344)、[Sound of Vision](https://www.academia.edu/28424536/Sound_of_Vision_Spatial_Audio_Output_and_Sonification_Approaches)
- **没找到**：①手机外放时声像定位还有多少效果的研究；②连续提示音与 VoiceOver 语音同时出现时的可辨识度研究。
  两项只能自己真机验。（「外放时左右声道基本分不出」是**推断**，未找到出处。）
- 多个声源同时响的辨识问题有专门文献（McGookin & Brewster 2004, concurrent earcons）⇒ 原型「每位志愿者一个音」在 48 人时会糊成一片，
  Soundscape 的做法是**按需、限量、依次**。
- 语音在嘈杂户外不可靠、且外放会泄露用户隐私（[PMC8749676](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8749676/)）—— 与 AGENTS §8「VoiceOver 外放 = 广播」同一件事。

## 3. 「身边有人」的展示 —— Uber 先例

Uber 下单前地图上的车：官方口径是**只显示最近 8 辆**、有延迟、且「为保护司机安全，某些情况下**在叫车前不显示单车的具体位置**」；
2015 年研究者曾指其不准甚至是「视觉效果」，Uber 否认造假。
来源：[CNN 2015](https://money.cnn.com/2015/07/29/technology/uber-phantom-drivers/index.html)、[Gizmodo 2015](https://gizmodo.com/uber-is-faking-us-out-with-ghost-cabs-on-its-passenge-1720576619)（均为 2015–2017 年资料，现状未核）
⇒ 连 Uber 对**司机**都在「匹配前不给精确点」上留了口子；我们原型给的是**视障跑者**的点位给所有志愿者看，敏感度更高。
与 09-13 结论一致：聚合必须在服务端，客户端不拿明细坐标。

## 4. 即时匹配 —— 同类怎么做

United In Stride（北美最大的视障跑者–引导员对接平台，2015 起）：**目录搜索 + 站内私信，自己约时间，不自动配对，没有即时派单**。
筛选项：身份 / 邮编半径 / 走或跑 / 配速区间 / 距离。首次搭档建议先短跑一次并做基础引导培训。
来源：[United In Stride FAQ](https://www.unitedinstride.com/faqs)、[Best Practices](http://www.unitedinstride.com/resources/uis-best-practices/)
⇒ 没找到任何做「即时叫一位陌生引导员 3 分钟到」的助盲跑产品。这与本仓库 ≥30 分钟 + 通话磨合的规则方向一致。

## 5. 未做

- 盲人用户对「绝对方位（东边）」vs「相对方位（右前方 / 几点钟方向）」的偏好 —— 未查。
- 高德 `standardNight` 叠自定义 annotation 的低视力对比度 —— 未量化。
- 本地志愿者真实在线密度（决定「56 位」这种画面在现阶段是否会常态为 0）—— 需要后端数据，不是联网能查的。

## 6. 讨论结果（2026-09-23，项目负责人拍板）

- 保持预约制（≥30 分钟 + 通话磨合），不做即时叫人。
- 星火**单独做一个 tab**（两端第 4 个标签页），不进订单页 —— 订单页对盲人没用、志愿者只想看自己那一单。
- 地图全 App 跟随系统明暗（高德 `standardNight`），金色用 `AppColors.warning`，不新增颜色。
- 「听见星光」一期只做语音摘要；声音化以后做，且只在戴耳机时。
- 志愿者能看到跑者的**模糊聚集片区**；动态只播汇总，不带地点、不实时。
- 一期纯 iOS、演示数据仅调试版可见；聚合接口排进二期。**替代「一束光地图」**（PR #174 关闭）。
- 志愿者之间互相联系约跑：单独立项。
- 落地见 OpenSpec 变更 `add-xinghuo-companion-map`。
