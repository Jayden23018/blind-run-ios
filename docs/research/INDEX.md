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
| 2026-08-13 | 现有联网搜索/抓取配置能不能覆盖竞品调研 / 医学论文 / 政策文件汇报三类场景？该不该加 Exa、Tavily？什么时候派 subagent 抓、什么时候自己抓？ | **不缺工具，缺免费额度和原文通道**。Firecrawl 是 keyless 层且**本轮实测已撞满当日配额**（`free daily limit for this network has been reached`，约 15.9h 恢复）—— 记忆 `firecrawl-mcp-setup` 写的注册触发条件已到。三场景各自的通道已实测钉死：竞品评价走 **HN Algolia API**（免 key，返回原始评论，是识破厂商软文的唯一途径 —— 实测发现 Firecrawl 在买软文）；论文**不要抓网页**，OpenAlex / Europe PMC / PubMed E-utilities 免 key 实测全 200，Semantic Scholar 无 key 已 429；政策文件 **gov.cn 直连即可**（200 / 0.17s），`r.jina.ai` 转 markdown 再省 64%。**Exa / Tavily 暂不上** —— 独立基准（AIMultiple）显示前四名质量差在噪声内，差 20× 的是延迟。Reddit 三条路全堵（`.json` 403 / 内置浏览器策略拦 / firecrawl 限流），要用得注册官方 OAuth（免费 100 QPM）。subagent 判据改为**按输出物切而非按任务大小切**：要结论就派，要原话/数字/字段就自己抓（原文经过 subagent 已经是转述，进程边界决定，prompt 修不了）。**§8 追加**：`WebSearch` 要定向搜某站必须用 `allowed_domains` **参数**，写进查询串的 `site:` 不生效且会静默退化成 SEO 软文（本报告第一轮据此误判内置搜索没能力）；`reddit.com` 是 Anthropic user agent 层硬屏蔽（400 硬错误）；`s.jina.ai`≠`r.jina.ai`，前者无 key 直接 401，免费 key 解锁的是整个 search 端点；**Exa 不买** —— 其 ToS §4.2(a) 逐字禁止 download/copy/reproduce 任何经服务获得的信息（仅允许浏览器临时缓存），与本仓库「调研必须落盘归档」直接冲突，§1(c) 另授予永久不可撤销许可且 query 用于训练模型（Firecrawl/Perplexity/Linkup/Tavily 条款同样贪，Jina Reader 暴露面不同因为给它的是 URL 不是研究问题） | Firecrawl 或 Jina 改免费层额度；Reddit 改 Data API 政策；gov.cn 加反爬或改站点结构；Exa 改 ToS §4.2；出现有独立第三方基准支撑的新搜索 API | [web-research-toolchain-20260813.md](./web-research-toolchain-20260813.md) |
| 2026-08-13 | 「行程实时分享给紧急联系人」与「志愿者激励体系」，同类产品的 UI 与架构怎么做？iOS 侧有哪些平台约束？ | 实时分享在 Strava Beacon 与 Uber 上是**同一套架构**：服务端发 token + 免登录只读页，客户端只负责把链接塞进**预填短信由用户手动点发送**，有效期绑行程生命周期而非固定 TTL，联系人上限 3–5 人 ⇒ **实时分享必须先有后端契约，纯前端最多做到静态行程告知短信**；激励可抄「按服务量分层（25/50/100/250/500）+ 徽章视觉差 + 进度常驻可见」，要避开排行榜竞争且必须可退出；⚠️ `MFMessageComposeViewController` 的 `.sent` **不保证送达**、预填可被用户改、系统 composer 是 out-of-process 无法注入无障碍标签（播报只能自己在回调里做）。缺口：服务时长**证书**生成没搜到可用材料 | 后端上线分享令牌/只读轨迹契约；Apple 改 MessageUI 行为或提供新的分享 API；对标产品（Strava Beacon / Uber Share My Trip）改架构 | [live-trip-sharing-and-volunteer-incentives-20260813.md](./live-trip-sharing-and-volunteer-incentives-20260813.md) |
