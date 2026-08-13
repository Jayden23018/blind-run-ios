# 联网调研工具链：现状实测与选型

**日期**：2026-08-13
**问题**：现有联网搜索/抓取配置能不能覆盖三类调研（竞品技术路线 / 医学论文 / 政策文件汇报）？该不该加新工具？什么时候派 subagent、什么时候自己抓？
**方法**：本机配置审计 + 对三类场景的真实目标页做实测（不采信厂商基准）

---

## 0. 一句话结论

**不缺工具，缺的是「原文通道」和「免费额度」**。当前 Firecrawl 是 keyless 层且**今天已撞满限流**；补两个零成本的免费 key（Jina、Firecrawl）＋ 把 HN Algolia 固化成常规通道，三个场景就全覆盖。**暂不需要 Exa / Tavily** —— 独立基准显示前四名质量差在噪声内，真正的差距在延迟与价格，而你的瓶颈不在搜索质量。

---

## 1. 配置实况（2026-08-13 审计）

| 通道 | 位置 | 状态 |
|---|---|---|
| `WebSearch` | 内置 | 可用，~320 tok/次，**US-only** |
| `WebFetch` | 内置 | 可用，~400 tok/次，**小模型转述，非原文** |
| `firecrawl_scrape` / `_search` / `_parse` | `~/.claude.json` user 作用域，HTTP `https://mcp.firecrawl.dev/v2/mcp` | **keyless**，今日额度已耗尽 |
| `firecrawl_crawl` / `_map` / `_agent` / `_research_*` | — | **不存在**（keyless 层不暴露） |
| Claude Browser（内置浏览器） | 内置 MCP | 可用，但 **reddit.com 被策略拦截** |
| claude-in-chrome | 内置 MCP | 可用（带真实登录态），未在本轮使用 |

环境变量中**没有任何**搜索/抓取类 API key（`FIRECRAWL_*` / `EXA_*` / `TAVILY_*` / `JINA_*` / `BRAVE_*` 全部未设置）。

### 1.1 Firecrawl keyless 已触发注册条件

实测调用 `firecrawl_scrape` 的原样返回：

```
The free daily limit for this network has been reached; try again in about 57114 seconds.
```

57114 秒 ≈ **15.9 小时**。项目记忆 `firecrawl-mcp-setup` 写的触发条件是「撞到 429 才需要去注册」—— **该条件已经到了**。

---

## 2. 三类场景的实测结果

### 2.1 竞品技术路线 / 论坛真实评价

**厂商软文污染极严重。** 四次 `WebSearch` 返回的 30 余条结果里，`firecrawl.dev/blog`、`nimbleway.com/blog`、`fastcrw.com/blog`、`crawlforge.dev/blog`、`use-apify.com/blog` 全是**被比较方自己写的对比文**，且各自排第一。相对独立的只有 AIMultiple 一份。

**HN Algolia API 是识破软文的唯一通道**，免 key、免 OAuth、返回原始评论 JSON：

```bash
curl -s -G "https://hn.algolia.com/api/v1/search" \
  --data-urlencode "query=firecrawl" \
  --data-urlencode "tags=comment" \
  --data-urlencode "hitsPerPage=30"
```

实测拿到的、**任何转述都不会保留**的信息：

- **Firecrawl 在买软文**。HN 用户 `vikp`（2026-07-03）与 `john_strinlai` 同时指出，一篇标题为「Please stop the AI confidence theater」的文章正文骂完 AI 炒作后，紧接着是 `This post is sponsored by Firecrawl.` —— 这解释了为什么搜索结果里 Firecrawl 的内容密度异常高。
- **真实用户的架构是「并联 + 融合」而非选一个**。`verdverm` 在 2026-06-16 / 06-27 / 07-20 / 08-11 四条独立评论里反复描述同一套：`Exa + Tavily + 自建 SearXNG 并行打，再用启发式或 agent 去重融合`。
- **Jina Reader 是被当免费首选层用的**。`simonw`（2025-09-29）给的方法是 `r.jina.ai` 前缀；一个 Show HN 项目的抓取链是 `Jina Reader → Firecrawl → cheerio` 三级降级。
- **token 成本量级**：`chonghaoju`（2026-07-11）在「One Wikipedia page costs your AI agent 68,000 tokens」帖下指出，用 Jina Reader 或 Trafilatura 转 markdown 后同一页降到 **3–5k**。
- Kagi 的 extract API 被 `jemmyw` 评为比 Firecrawl 更省钱（2026-08-04）。

**Reddit 三条路全堵**（实测）：

| 路径 | 结果 |
|---|---|
| `https://www.reddit.com/...search.json` | **HTTP 403**，返回 `<title>Blocked</title>` |
| 内置浏览器 `preview_start` | `https://reddit.com is blocked by policy` |
| `firecrawl_scrape` | 当日额度已耗尽 |

官方通道是可行的：Reddit Data API 文档原文 ——「Clients must authenticate with a registered OAuth token. We can and will freely throttle or block unidentified Data API users.」免费层限速「**100 queries per minute (QPM) per OAuth client id**」，按 10 分钟窗口取平均以支持突发。

### 2.2 医学论文

**结论：不要抓网页，走结构化 API。** 实测（均为 keyless）：

| 源 | 端点 | 实测 |
|---|---|---|
| OpenAlex | `api.openalex.org/works?search=...&mailto=` | **200**，2.44s，52 KB |
| Europe PMC | `ebi.ac.uk/europepmc/webservices/rest/search` | **200**，1.62s |
| PubMed E-utilities | `eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi` | **200**，2.00s |
| Semantic Scholar | `api.semanticscholar.org/graph/v1/paper/search` | **429 Too Many Requests**（无 key 即被限） |

前三个足够做检索与筛选；Semantic Scholar 想用要申请 key。已装的 skill（`paper-search`、`arxiv`、`semantic-scholar`、`1dcb1c8b5808:search-lit`、`fulltext-retrieval`）已经封装了这些源，不需要重新造。

Firecrawl 的 `firecrawl_research_*`（独立论文摘要/全文索引）**需要认证才出现**，keyless 层拿不到。

### 2.3 政策文件

**中国政府网直连可抓，不需要任何付费工具**（实测）：

| 目标 | 方式 | 结果 |
|---|---|---|
| `https://www.gov.cn/zhengce/` | `curl` 直连 + 常规 UA | **200**，0.17s，36,489 字符 HTML |
| 同页 | `https://r.jina.ai/<url>` | **200**，6.07s，13,195 字符 markdown（**-64%**） |

注意 `gov.cn` 站内路径会变：`/zhengce/zhengceku/index.htm` 已 404 并被 JS 跳回首页，直接 `curl` 拿到的是 404 页而非报错，**必须核 `http_code` 和正文首行，不能只看「有返回」**。

政策 PDF 走 `firecrawl_parse`（`pdfOptions.maxPages` 可限页）或本地 `convert-documents-to-markdown` skill。给老板的汇报要引原话 ⇒ **这个场景必须原文，`WebFetch` 的转述不合格**。

---

## 3. 价格与限速（2026-08-13 官方页核实）

| 工具 | 免费层 | 关键数字 |
|---|---|---|
| **Jina Reader** (`r.jina.ai`) | 无 key 可用 | **20 RPM**（无 key）→ **500 RPM**（免费 key），来源：官方 rate-limit 页 |
| **Firecrawl** | 1,000 credits/月，2 并发，「Low rate limits」 | keyless 层另有更严的**每日**网络级配额（本轮实测撞满） |
| **Exa** | 创业/教育可申请 $1000 credits | 检索 $5–$15 / 1k requests；agent 档 $0.012–$1.00 / request |
| **Tavily** | 有免费层（页面为 JS 渲染，未取到确切数字） | 2026-02 被 Nebius 收购，品牌保留 |

**独立基准（AIMultiple，8 个搜索 API × 100 条真实查询 × 4000 条结果 LLM 评分）**：Brave 以 Agent Score 14.89 居首，但 Firecrawl / Exa / Parallel Search Pro 与之差距**在随机波动范围内**；唯一稳定结论是 Brave 比 Tavily 高约 1 分。**延迟差 20×**（669 ms ↔ 13.6 s）—— 质量拉不开时延迟才是决定项。

⚠️ Firecrawl 自称对 Exa 的 F1 优势（77.2% vs 69.2%）出自其**自建基准**，判定阈值是「取到期望正文的 ≥10%」，阈值极低；另一家 fastCRW 在同一公开数据集上给出的排名完全不同。**所有厂商自评一律降级为方向性参考。**

---

## 4. 转述 vs 原文：什么时候必须原文

**已有证据**（全局 `~/.claude/CLAUDE.md` 记录）：2026-08-11 实测阿里云 SendSms 文档，`WebFetch` 把 6 个请求参数讲成「四个 + 额外两个」，示例值全丢。

**本轮新增证据**：Firecrawl 赞助软文这件事，只存在于 HN 评论的原文里。任何「总结这个页面讲了什么」式的转述都会把它当作噪声丢掉 —— 而它恰恰是判断「这份对比可不可信」的唯一依据。

**判据（按输出物定，不按任务大小定）**：

| 你的产出里会出现什么 | 通道 |
|---|---|
| 引号里的原话、可核对的数字、API 字段名/枚举/必填性、政策原句 | **必须原文**：`curl` + `r.jina.ai`，或 `firecrawl_scrape` |
| 「别家大概怎么做的」「有哪些流派」 | 转述够用：`WebFetch`（~400 tok，差 20×） |
| 只要 URL 列表 | `WebSearch`（~320 tok） |

---

## 5. subagent 的边界（本轮亲测后的修订判据）

原判据「定位/摘要/读日志外包」在调研场景下**不够用**，因为它按「任务类型」切，而调研的关键变量是**「我要的是结论还是原文」**。

**架构性事实**：subagent 的返回值是一段文字。原文只要经过 subagent，就**已经是转述了** —— 这是进程边界决定的，不是把 prompt 写得再死（「原样粘贴」「不要总结」）能消除的。写死格式契约能降低失真率，不能降到零。

| 情形 | 做法 |
|---|---|
| 「X 在哪实现的」「谁调用了 Y」「这 20 篇里哪几篇值得读」 | **派** —— 要的就是结论 |
| 读已经跑完的日志、大文件摘要 | **派** |
| 互相独立的多个模块 | **并行派** |
| 要引用的原话、要核对的数字、API 契约字段 | **自己抓** —— 见上面架构性事实 |
| 混合场景（本轮就是） | **两段式**：subagent 只负责*筛*（返回 URL + 一句话为什么值得读），原文自己 `curl` |

本轮全程未派 subagent：目标页只有 8 个、路径已知，写 prompt 的成本大于自己抓的成本。

---

## 6. 建议动作（按性价比排序）

1. **注册 Jina 免费 key** —— 零成本，20 RPM → 500 RPM，解掉最常撞的限流。这是当前性价比最高的一步。
2. **注册 Firecrawl 免费层**（1000 credits/月，无需信用卡）—— 你今天已经撞满 keyless 配额。拿到 `fc-` key 后按记忆 `firecrawl-mcp-setup` 的方式换成本地 stdio + env，**不要**用 HTTP transport 的 headers。
3. **把 HN Algolia 固化成常规通道** —— 免 key、免 OAuth、返回原始评论。这是论坛真实评价唯一稳定的免费入口。
4. **暂不上 Exa / Tavily** —— 前四名质量差在噪声内，你的瓶颈是原文获取与落盘纪律，不是搜索质量。真需要时先要 Exa 的教育额度。
5. **Reddit 按需再打通** —— 需要 Reddit 才注册 OAuth（免费 100 QPM）；不常用就用 `WebSearch` + `site:reddit.com` 拿转述。

---

## 7. 被否掉的方案（留档，避免重跑）

- **Exa / Tavily 现在就上** —— 否。独立基准显示与现有方案差距在噪声内，增加 key 管理成本换不到可测的收益。
- **Reddit `.json` 免 key 抓取** —— 否。实测 403，Reddit 官方明确「will freely throttle or block unidentified Data API users」，这不是限速而是策略。
- **内置浏览器抓 Reddit** —— 否。`reddit.com is blocked by policy`。
- **靠 `WebFetch` 做政策文件汇报** —— 否。转述会丢原话，而汇报要求引用可核对。
- **给 subagent 写「原样粘贴不要转述」的格式契约来拿原文** —— 部分有效但不可依赖，理由见 §5 架构性事实。

---

## 8. 追加：Exa 的搜索会比内置 `WebSearch` 更好吗？（同日，问题独立成节）

### 8.1 先纠正本报告自己的一个错

§2.1 原写「四次 `WebSearch` 返回的全是厂商软文」「HN Algolia 是唯一通道」—— **那是操作失误，不是工具缺陷**。

`WebSearch` 有 `allowed_domains` **参数**，而第一轮把 `site:news.ycombinator.com` 写进了**查询串**。查询串里的 `site:` 不生效，于是返回一堆 SEO 软文，工具还自己解释「I didn't find Hacker News discussion threads」—— 看起来像工具没能力，实则是参数没用对。

改用参数后重测，一次命中 10 条真实 HN 帖，其中 `item?id=47942777` 标题正是「Tavily, Exa, Firecrawl, Perplexity, and Linkup are all tools for agents to search the web」—— 第一轮完全没找到。

**⇒ 原本支持「考虑 Exa」的最强证据（内置搜索找不到论坛原文）不成立。** `WebSearch` + `allowed_domains` 就是精准的定向搜索。

### 8.2 `reddit.com` 是 user agent 层硬屏蔽

`allowed_domains: ["reddit.com"]` 返回的不是空结果，是 **HTTP 400 硬错误**，原文：

```
The following domains are not accessible to our user agent: ['reddit.com']
```

这和 §2.1 里 `.json` 403、内置浏览器 policy 拦、`r.jina.ai` 被 403 是同一件事的第四个面：Reddit 在**爬虫身份**层面拒绝所有非 OAuth 流量。**⇒ Reddit 官方 OAuth 不是「更好的选择」，是唯一选择**，脚本见 `~/.claude/scripts/reddit-search.sh`。

### 8.3 `s.jina.ai` 与 `r.jina.ai` 不是一个东西

| | 作用 | 免 key |
|---|---|---|
| `r.jina.ai` | Reader：一个 URL → markdown | ✅ 20 RPM |
| `s.jina.ai` | Search：一个问题 → 前 N 条结果**连正文一起返回** | ❌ 实测 `401 AuthenticationRequiredError` |

⇒ Jina 免费 key 的价值不止「20 RPM → 500 RPM」，而是**解锁整个 search 端点**。

### 8.4 Exa 真正会赢与会输的地方

**会赢**：① 语义检索（「论证 X 的论文」这类概念查询，`WebSearch` 是传统检索）；② 一步返回全文（`WebSearch` 只给 URL + 小模型转述）；③ 有自己的索引，不受 Anthropic user agent 屏蔽名单约束。

**会输**：① 索引偏「信息密集」内容（博客/论文/新闻/GitHub），长尾缺失；② 语义检索的固有失败模式 —— 概念相似但实际不相关；③ **中文内容基本没有**，政策场景补不上（而 `WebSearch` 同样 US-only，两者都不行）；④ HN 实测反馈：要产品数据「got back articles rather than structured data」，Tavily 与 Bing 同样。

### 8.5 决定性的一条：Exa 的条款与「调研必须落盘」直接冲突

**Exa 服务条款 §4.2(a) 原文**（2026-08-13 从 `exa.ai/assets/Exa_Labs_Terms_of_Service.pdf` 核）：

> You may not ... download, modify, copy, distribute, transmit, display, perform, reproduce, duplicate, publish, license, create derivative works from, or offer for sale any information contained on, or obtained from or through, the Services, **except for temporary files that are automatically cached by your web browser for display purposes**

本仓库 AGENTS.md §12 要求「调研完落盘 `docs/research/{topic}-{YYYYMMDD}.md`」并提交进 git —— 这在字面上**正是**该条禁止的 download / copy / reproduce。

**同条款 §1(c)**：用户授予 Exa 对 User Input 与 Output 的「nonexclusive, royalty-free, transferable, sub-licensable, worldwide, **perpetual and irrevocable** license to access, use, host, cache, store, reproduce, transmit, display, publish, distribute, and modify」。HN 用户 `lukewarm707`（2026-04-29）另引 Exa 条款：「Query Data is used to improve our products and technology, including by **training and fine-tuning models** that power our Services」。

⇒ 医学项目的未发表研究方向、给老板的调研选题（暴露关注点），都不该进这条管道。

**公平起见**：同一条 HN 评论逐字对比了五家，条款一样贪 —— Firecrawl（「worldwide, irrevocable, non-exclusive, royalty-free license ... You also grant to us the right to sub-license」）、Perplexity（「may retain, copy, distribute and otherwise use Search Data」）、Linkup、Tavily。**这不是 Exa 独有的缺陷，是「把研究问题发给搜索厂商」这个动作本身的代价。** `r.jina.ai` 暴露面不同：给它的是一个你已经选好的 URL，不是你的研究问题。

### 8.6 结论

**不买 Exa。** 理由不是它不好，是**它在真实瓶颈上没有增量，却在归档工作流上引入法务摩擦**。三个真实缺口它一个都补不上：中文搜索（Exa 没有）、Reddit（官方 OAuth 免费且干净）、语义找论文（OpenAlex / Semantic Scholar 的 related-works 免费且专业对口）。

**什么时候回头看**：确实开始做大量**英文语义检索**且 OpenAlex 相关工作推荐不够用时。那时先申请教育额度（$1000 credits），不要直接付费。
