# 接单前通话之后：见面安排单、改约确认、等待界面 —— 同类产品与 iOS 技术调研

- 日期：2026-10-15（所有来源的核实日期同此）
- 问题：盲人与陪跑员在 `PENDING_INTRO_CALL` 通完电话后，怎么把电话里说好的时间、地点、见面点、穿着落进系统；改时间地点要不要对方确认；通话前后的等待界面怎么做；iOS 能感知到通话的哪些状态
- 增量说明：通话通道、隐私号不可用、通话磨合的学术依据见后端仓库 `docs/research/intro-call-matching-20260821.md`，本文不重复
- 配套：现状审查 `docs/review/intro-call-current-state-20261015.md`；设计 `docs/design/2026-10-15-intro-call-meetup-plan-design.md`
- 证据标记：🟢 读到官方原文；🟡 只有搜索摘要或论坛转述，没读到原文

## 1. 聊完之后谁录入见面细节

**结论：没有一个市面产品有「聊完电话后一方填结构化见面确认单」这一步。** 最接近的是「提议卡 + 对方点接受」。所以这张单的字段没有行业标准可抄。

| 产品 | 做法 | 来源 |
|---|---|---|
| Rover Meet & Greet | 先聊，再由发起方建一张只有日期、时间、地点（加一条留言）的提议，对方同意才生效；见面后没有第二张表。官方建议觉得不合适就直说（与本项目「无声拒绝」相反） | 🟢 https://support.rover.com/hc/en-us/articles/206355333-How-do-I-create-a-Meet-Greet- ；https://support.rover.com/hc/en-us/articles/202838464-What-are-the-best-practices-for-Meet-Greets |
| United In Stride（视障跑者配对） | 站内只有发消息；要求双方约定开始时间、集合地点、路线、结束时间四项，但只是行为约定，不是表单 | 🟢 http://www.unitedinstride.com/resources/uis-best-practices/ |
| Care.com 面试 | 家长发起视频面试，保姆只能接受或拒绝；线下见面细节在消息里谈 | 🟡 https://help.care.com/caregivers/s/article/Video-interviews-a-guide-for-caregivers?language=en_US |
| Upwork offer | 面试后发结构化 offer，对方可「请求修改」或接受；接受后条款不能再改 | 🟢 https://support.upwork.com/hc/en-us/articles/34262508186899-How-to-request-changes-to-an-offer |
| 陪诊平台（青蝌康护） | 接单后由陪诊师自己和客户确认时间地点，没有结构化确认单 | 🟢 https://www.ph.qkcare.cn/document/12.html |

没查到：TaskRabbit 聊后确认字段、Wag、Sittercity、Achilles International（固定地点周训，无逐次约见）。Be My Eyes、Aira 是即时视觉协助，没有约见这一步，不适用。

## 2. 一方提议修改、另一方确认才生效

**结论：所有产品都把「改约提议」做成独立于原约的东西。拒绝或超时，原约原样保持。** 差别在超时、次数限制、是否重新校验。

| 产品 | 做法 | 来源 |
|---|---|---|
| Airbnb 改约请求 | 对方拒绝或没回应，原预订不变；已发请求不能编辑，只能撤回重发；同一预订同时只能有一个请求；每天 3 次、总共 10 次；接受后价格重算。**改约请求没有超时**（反面教材：会无限挂着） | 🟢 https://www.airbnb.com/help/article/50 、/913 、/1504 |
| Airbnb 新预订请求 | 房东 24 小时内不回，请求作废 | 🟢 https://www.airbnb.com/help/article/315 |
| Booking.com | 民宿方发改日期请求，客人 24 小时内接受；期间新日期被临时占住；超时原预订不变 | 🟢 https://partner.booking.com/en-us/help/reservations/manage/making-changes-booking-made-your-property |
| Upwork offer | 发起人修改重发会重置 7 天计时；**只能接受最新版本**；对方正在操作时不能修改 | 🟢 同第 1 节 Upwork 页 |
| TaskRabbit | 24 小时内开始的任务改期要双方同意；不允许频繁改期；禁止「改期后再取消」躲取消费 | 🟢 https://support.taskrabbit.com/hc/en-us/articles/46260435128091-Schedule-Availability-Reschedule-Policy |
| BlaBlaCar | 有人订座后车主不能随意改行程，要改先和乘客商量，不同意就取消重发 | 🟡 https://www.blablacar.co.uk/faq/question/how-do-i-change-my-ride-offer-before-and-after-a-booking-is-made |
| Calendly | 改期直接生效，没有提议态 | 🟡 |
| 滴滴预约单改上车点 | 没查到官方规则 | 查不到 |

## 3. 现场认人

**结论：对视障一方，给「对方怎么找到我」比给「我怎么看到对方」有用。** 颜色和穿着描述主要服务明眼一方。

- Uber 上车备注可发「我穿红色外套」，司机端可朗读。🟢 https://www.uber.com/us/en/ride/how-it-works/pickup-messages/ —— 服务明眼乘客，对盲人没帮助。
- Uber 视障自我标识：司机在接单后和到达上车点时收到「乘客是视障」的提示。🟢 https://www.uber.com/us/en/newsroom/rider-self-id/
- 滴滴盲人无障碍出行：司机在接单、到达、即将到达三个时点收到语音和短信，被要求主动联系并寻找盲人乘客。🟢 https://m.yicai.com/news/101818017.html
- 黑暗跑团（青年报）：视障跑者难以分辨陪跑员长相，建议多发语音，熟悉声音后见面能互相「听见」。🟢 https://www.why.com.cn/wx/article/2025/01/05/17359596771187137393.html （单篇媒体报道，不是实验）
- United In Stride 没写双方怎么认出对方。🟢 https://www.unitedinstride.com/resources/guiding-101/

## 4. 等待与超时

- 成熟产品只给「单一超时 + 状态文案」，提议类超时多为 24 小时（Airbnb 新预订、Booking）或 7 天（Upwork），Airbnb 改约不设超时。
- 没有任何产品提供「对方是否拒绝」的信号 —— 因为它们的拒绝都是明着说的。**「无声拒绝」没有先例可抄。**
- 电话类撮合的通话窗口时长，没有产品公开。

## 5. 反面证据

- Airbnb 房东论坛：客人先改约缩短住期，再按新条件全额取消。🟢 https://airhostsforum.com/t/be-weary-of-the-reservation-change-cancellation-scam/50866 （单帖轶事）—— 启示：改约会改变后续规则（取消条件、闸门时刻），要防借改约绕规则。
- 「聊后填表负担大 / 被砍掉」：**没找到任何证据**。原因是几乎没有产品有这种表。不能当作「已证明有负担」，也不能当作「没有负担」。

## 6. iOS 能否感知 `tel:` 拨出的电话

**结论：有条件能，只能当辅助信号。拿不到号码；App 在后台基本收不到回调；大陆审核态度不明。**

- `CXCall` 只有 `uuid / isOutgoing / hasConnected / hasEnded / isOnHold`，没有号码。🟢 https://developer.apple.com/documentation/callkit/cxcall
- 任何 App 都能建 `CXCallObserver` 观察系统通话，iOS 10+。🟢 https://developer.apple.com/documentation/callkit/cxcallobserver
- 打开 `tel:` 后 App 进后台，回调基本收不到，回前台才补。🟡 https://developer.apple.com/forums/thread/660619 、/664342 、/803375
- iOS 17+ 开实时语音信箱时，来电被拒也可能报 `hasConnected = true`。🟡 https://developer.apple.com/forums/thread/748868 、/766395
- 2018 年苹果审核邮件（媒体转载）：工信部要求中国区 App 停用 CallKit 功能，未区分 `CXProvider` 与 `CXCallObserver`。🟡 https://technews.tw/2018/05/14/apple-app-callkit-prohibited-in-cn/ 。只用 `CXCallObserver` 的 App 现在会不会被拒，**查不到可靠资料**。
- ⚠️ 本仓库**已经**在用 `CXCallObserver`（`blindRun/Voice/AnnouncementQueue.swift:150`，通话中暂停播报）。上面的审核风险已经存在，不是新引入的。
- `tel:` 在 iOS 10.3+ 会先弹拨号确认框。🟢 https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/PhoneLinks/PhoneLinks.html 。`telprompt:` 未公开，不用。
- scenePhase 顺序（按官方 inactive 定义推断，**需真机日志验证**）：确认框弹出 `active → inactive`；点取消 `inactive → active`；点拨打 `inactive → background`；打完回来 `background → inactive → active`。⇒ 只有「从后台回到前台」才代表「可能打完电话回来了」。

## 7. 读屏用户确认他人填写的信息

- WCAG 3.3.4（AA）：涉及法律承诺、金融交易、修改用户数据时，要能撤销、或已检查、或提交前可复核确认。🟢 https://www.w3.org/WAI/WCAG22/Understanding/error-prevention-legal-financial-data.html 。改见面时间地点影响人身安全，按它的精神做「复核 + 确认」—— 这是解释，不是硬性要求。
- WCAG 2.2.1：内容设定的时限要能延长，除非时限是必需的。🟢 https://www.w3.org/WAI/WCAG22/Understanding/timing-adjustable.html
- WCAG 4.1.3：等待和进度变化要能不抢焦点地被播报。🟢 https://www.w3.org/WAI/WCAG22/Understanding/status-messages.html
- **没找到专门针对读屏用户「读回确认」的研究。** 「逐项朗读 + 一个确认按钮、改过的项念新旧值」是推断，要真人测试。
- iOS 17+ 播报可设优先级（`accessibilitySpeechAnnouncementPriority`）；iOS 16 没有，要自己排队并监听 `announcementDidFinishNotification`。🟢 https://developer.apple.com/videos/play/wwdc2023/10036/
- 倒计时：常驻元素加 `updatesFrequently`，值静默更新，只在节点播报。🟢 https://developer.apple.com/documentation/swiftui/accessibilitytraits/updatesfrequently 。节点取值没有官方规范，第三方建议 5 分钟 / 1 分钟 / 30 秒。🟡 https://www.deque.com/blog/ios-updating-content/

## 8. 陪跑员侧表单

- SwiftUI `DatePicker` 没有分钟步长参数；`UIDatePicker.minuteInterval` 可设 5。🟢 https://developer.apple.com/documentation/uikit/uidatepicker/minuteinterval
- 高德 `AMapSearchAPI` 有输入提示、POI、逆地理编码。🟢 https://a.amap.com/lbs/static/unzip/iOS_Map_Doc/AMap_iOS_API_Doc_Search/interface_a_map_search_a_p_i.html （返回坐标系未在该页确认）
- 「服务方自述穿着」的字段设计：**没找到业界参考**。

## 9. 隐私

- 《个人信息保护法》第四条：能关联到特定自然人的信息是个人信息；第二十八条：行踪轨迹属敏感个人信息；第十九条：保存期限为实现目的所必要的最短时间，没有给天数。🟢 https://www.cac.gov.cn/2021-08/20/c_1631050028355286.htm
- 网信办 2026-01 问答：敏感类举的是「连续精准定位轨迹」。🟢 https://www.cac.gov.cn/2026-01/09/c_1769688003183197.htm 。单次集合点大概率不算连续轨迹，但没有官方明确答复。

## 对 AidRun 的结论

1. 「提议 → 对方确认才生效、拒绝或超时保持原约」是通用做法，可直接采用；超时不能学 Airbnb 不设。
2. 只能接受最新版本（Upwork），防止确认到过期版本。
3. 每次改动都重跑下单规则；TaskRabbit 与 Airbnb 论坛的教训是改约会被用来绕规则。
4. 认人信息给盲人的是「他会走过来、先报姓」，颜色描述主要给陪跑员和低视力跑者。
5. 「无声拒绝」没有先例，改约被拒和超时对陪跑员必须是同一句话。
6. 通话状态只当辅助信号；不扩大 `CXCallObserver` 用途；用「后台 → 前台」判断打完电话回来。
7. 字段设计、读回朗读格式、倒计时节点都没有权威依据，要在真机上找盲人用户试。

## 复核触发条件

- 苹果对 `CXCallObserver` 在中国区的审核口径有明确说法
- 有针对读屏用户「读回确认」的研究或 Apple 官方指南发布
- 阿里云或其他厂商的隐私号重新可申请（会改变整条通话链路）
