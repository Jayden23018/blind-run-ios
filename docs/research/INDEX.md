# 调研索引

本仓库**所有**联网调研的唯一落脚点。规则只有三条：

1. **开搜前整份读这个文件**，不要 `ls | grep` —— `ls` 只匹配文件名，搜「地图」命中不了
   `amap-geocoding-20260801.md`；能搜到的词在下面「问题」和「一句话结论」两列里。
2. 已有结论还作不作数，看「复核触发条件」那列。**没触发就直接用，不要重跑。**
   触发了、或表里根本没有这个问题、或有但缺你要的那一段 —— 才开新一轮。
3. 调研完落盘到 `docs/research/{topic}-{YYYYMMDD}.md`，**并回写下面一行**。
   不回写等于没做：下次搜不到，同一份调研会被原样重跑一遍。

被否掉的方案同样留一行 —— 「试过 X 因为 Y 放弃」跟「选了 Z」一样值钱，且更容易被忘。

强制在 `scripts/hooks/research-log.mjs`：联网工具调用前把本文件灌回给模型（第 1 条），
停止前检查本轮联网过但 `docs/research/` 没动（第 3 条）。自测 `scripts/validate-research-log.mjs`。

| 日期 | 问题 | 一句话结论 | 复核触发条件 | 报告 |
|------|------|-----------|-------------|------|
| 2026-08-05 | 视障用户语音预约陪跑的界面与交互标准：决策点数、尾静音时长、确认词白名单、有订单时首页要不要被接管 | 减法方向对但论证支柱错；Magic Tap 不可依赖（iOS 26 起可整个关闭）；确认词白名单必须重做（Portland 事件证据链）；12 秒尾静音超 Nielsen 10 秒上限要改；订单卡应作第 1 个 VoiceOver 焦点而非整页接管；`YD/T 4211-2023` 引错了，它是域名隐私标准 | iOS 大版本改 VoiceOver 手势或 Magic Tap 语义；`Speech` 框架端点检测默认值变化；国标/行标出新版无障碍要求 | [blind-voice-booking-ia-20260805.md](./blind-voice-booking-ia-20260805.md) |
| 2026-08-12 | `dynamicTypeSize(...accessibility3)` 这样的封顶够不够 WCAG 1.4.4 的「放大 200% 不裁切」？ | **够** —— body 在 AX3 是 40pt / 默认 17pt ≈ **235%**，AX5 是 53pt ≈ 312%。此前 review 初稿凭印象写成「AX3 约 175%，够不到 200%」，是错的。封顶仍该去掉，但理由换成「AX4/AX5 正是低视力用户实际会设的档位」+「全仓只有一个组件封顶，同屏缩放不一致比两个极端都差」。附带：不同文本样式缩放速率不同（AX5 档 Body 比 Title 1 还大），不能拿一个样式的比例推另一个 | Apple 改 Dynamic Type 字号表或新增档位；WCAG 改 1.4.4 的倍数要求 | [dynamic-type-scale-20260812.md](./dynamic-type-scale-20260812.md) |
| 2026-08-12 | 市面同类盲人产品各做了哪些功能？一个盲人 App「必须」有哪些能力与适配，强制性从哪来？ | 同类产品分**三类**（即时视觉协助 / 长期配对陪跑 / 无障碍派单出行），功能集不可互抄；AidRun 是跨类产品 —— 用第三类的派单机制承载第二类的人身安全风险面，缺口要按第二类对；可直接照搬的只有滴滴的三节点提醒 + 勋章激励、UIS 的出发前四要素约定 + 一对多储备池（每人需 6–8 名固定陪跑员）、关怀版的预存常用地址；**面向 App 的无障碍国标目前不存在**，实际依据是 GB/T 37668-2019 + 《移动互联网应用（APP）适老化通用设计规范》，信息无障碍标识两年一检 | 工信部《移动互联网应用程序适老化技术规范》正式出台；WCAG 出新版或 EAA 执行口径变化；对标产品（滴滴无障碍出行 / United In Stride / Be My Eyes）发布重大功能改版 | [blind-app-feature-landscape-20260812.md](./blind-app-feature-landscape-20260812.md) |
| 2026-08-08 | 盲人端首页与接单后页面的视觉规格：主按钮多大、圆形还是圆角矩形、次级操作并排还是堆叠 | 全宽圆角矩形，主按钮占内容区约 75%（现状 `minHeight: 64` 差一个数量级）；圆形是错方向（同尺寸只有 π/4 ≈ 78.5% 可点面积）；次级操作一律整行铺满竖直堆叠，对标产品无一并排；接单后那页要从 7 个 section 减到一张头像加一个按钮 | `docs/ui/reference-screenshots/` 下的对标产品发布重大改版；我们改动首页或接单后页面的信息架构 | [blind-ui-visual-benchmark-20260808.md](./blind-ui-visual-benchmark-20260808.md) |
| 2026-08-14 | App 自己的 TTS 播报能不能跟随用户的 VoiceOver 语速？（review §5.6 / §6.1 #18 排进「要产品拍板」的那条） | **不需要拍板，平台已给答案**：读不到也不该读用户语速（无公开 API，且旁白与朗读内容是两个独立滑块），改设 `AVSpeechUtterance.prefersAssistiveTechnologySettings = true`，VoiceOver 在跑时系统用用户的音色与语速覆盖，没跑时才用我们的值 ⇒ `voice`/`rate` 两行必须保留。`API_AVAILABLE(ios(14.0))`，部署目标 16.0 **不需要 `#available`**；⚠️ WebSearch 转述成「iOS 16+」是错的，版本敏感 API 以本机 SDK 头文件为准。出厂值实测为 `false`（缺陷真实存在），但头文件写明查询属性反映不出用户设置 ⇒ **语速在进程里测不出来，单测只能断言开关，听感必须真机人耳验**。附带：`rate` 标度非线性、中点 0.5 不是 1.0。**未解决**：VoiceOver 开着时同一句同时走通告与合成器是否「念两遍」，仍需真机听 | Apple 改 `prefersAssistiveTechnologySettings` 语义或废弃它；本仓库部署目标降到 iOS 14 以下；两条播报通道（通告 + 合成器）的取舍被重新讨论 | [tts-rate-follows-voiceover-20260814.md](./tts-rate-follows-voiceover-20260814.md) |
| 2026-08-13 | 「行程实时分享给紧急联系人」与「志愿者激励体系」，同类产品的 UI 与架构怎么做？iOS 侧有哪些平台约束？ | 实时分享在 Strava Beacon 与 Uber 上是**同一套架构**：服务端发 token + 免登录只读页，客户端只负责把链接塞进**预填短信由用户手动点发送**，有效期绑行程生命周期而非固定 TTL，联系人上限 3–5 人 ⇒ **实时分享必须先有后端契约，纯前端最多做到静态行程告知短信**；激励可抄「按服务量分层（25/50/100/250/500）+ 徽章视觉差 + 进度常驻可见」，要避开排行榜竞争且必须可退出；⚠️ `MFMessageComposeViewController` 的 `.sent` **不保证送达**、预填可被用户改、系统 composer 是 out-of-process 无法注入无障碍标签（播报只能自己在回调里做）。缺口：服务时长**证书**生成没搜到可用材料 | 后端上线分享令牌/只读轨迹契约；Apple 改 MessageUI 行为或提供新的分享 API；对标产品（Strava Beacon / Uber Share My Trip）改架构 | [live-trip-sharing-and-volunteer-incentives-20260813.md](./live-trip-sharing-and-volunteer-incentives-20260813.md) |
