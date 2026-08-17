# 视障人群 App 功能全景与无障碍合规基线

**核实日期**：2026-08-12（所有联网结论均为该日核实）
**调研问题**：市面上与 AidRun 定位相近的产品各自做了哪些功能？一个面向盲人的 App「必须」有哪些能力和适配？这些要求的强制性来自哪里？
**为什么开这一轮**：`INDEX.md` 里已有两份报告分别覆盖「语音预约的交互标准」（20260805）和「首页/接单后页面的视觉规格」（20260808），两份都是**单页面级**的。功能全景、竞品功能集、合规基线这三段表里没有，属于缺失段落。

> 本报告只做外部事实收集。落到 AidRun 自身的差距判断在
> [`docs/review/blind-app-full-review-20260812.md`](../review/blind-app-full-review-20260812.md)。

---

## 1. 对标产品分三类，不是一类

把「盲人 App」当成一个品类会得出错误的功能清单。实际上是三种商业与关系模型，功能集彼此不可移植：

| | 即时视觉协助 | 长期配对陪跑 | 无障碍派单出行 |
|---|---|---|---|
| 代表 | Be My Eyes、Aira、Envision、小艾帮帮、云瞳志愿者 | United In Stride、Achilles International | 滴滴「盲人无障碍出行服务」 |
| 关系 | 一次性、匿名、可随时挂断 | 长期、实名、反复线下见面 | 一次性、实名、平台担保 |
| 匹配 | 抢单（先到先得） | 用户自主筛选 + 主动联系 | 系统派单 |
| 风险面 | 隐私（视频流） | **人身安全**（线下独处） | 拒载、找不到人 |
| **AidRun 落在哪** | — | 风险面在这里 | 匹配机制在这里 |

**AidRun 是一个跨类产品**：它用第三类的系统派单机制，去承载第二类的人身安全风险面。这是本次调研最重要的一条结论 —— 后面所有「别人有我们没有」的判断都要先过这一关，不能照抄。

---

## 2. 逐类的功能集

### 2.1 即时视觉协助

**Be My Eyes**（免费）

- 盲人 ↔ 明眼志愿者实时视频呼叫，免费
- 企业客服层：Hilton 于 2024-10 接入（客人可直接联系酒店员工调空调、找设施）；Tesco 于 2025-10 在英国启动 6 个月试点（购物协助直连店员）
- AI 层「Be My AI」：2023-03 被 OpenAI 选为 GPT-4 视觉能力的旗舰演示
- 硬件：2024-11 Meta 在 Ray-Ban 智能眼镜加入盲人模式，内置 Be My Eyes 的「Call a Volunteer」，第一视角视频串给明眼人

**Aira**（付费）：训练过的专业视觉解译员，AI 做物体识别与情境数据，**判断类决策始终有人在环**。定位是高风险场景（陌生机场、就医、突发绕行）。

**Envision**：OCR + 计算机视觉为主（手写体、屏幕、场景、人脸），有「加一位信任的亲友作为你的眼睛」功能，自带 AI 助手 Ally。Envision Glasses 单次充电续航约 16 小时，售价报道区间 $1,899–$3,499，保险覆盖不一致。

**国内**：小艾帮帮、云瞳志愿者为用户量较大的两款。截至 2022 年报道，小艾帮帮注册盲人 10,306 人、志愿者 134,256 人，**志愿者∶盲人 ≈ 13∶1**，志愿者接求助电话是**抢单制**。

> 这一类可借鉴的只有两件事：**公益积分/激励解决志愿者留存**，以及**企业侧接入**（把「某个愿意帮忙的陌生人」换成「某个有职务身份的人」，责任链更清晰）。视频协助本身与陪跑无关。

### 2.2 长期配对陪跑 —— 与 AidRun 最近的一类

**United In Stride**（美国，视障跑者 ↔ 明眼陪跑员一对一匹配平台）

功能集：

- **注册档案**：邮编位置、活动偏好、作为陪跑员或与陪跑员共跑的**经验**；须成为会员才能搜索与联系他人
- **四维筛选**：① 找谁（陪跑员 / 视障运动员 / 两者）② 搜索半径 + 目标邮编 ③ 活动类型（步行 / 跑步 / 两者）④ 可选的配速区间与距离能力
- **活动类型已扩展**至徒步、双人协力自行车（tandem）、铁人三项；协力车用户需标注是否**自带**协力车

安全设计（对国内同类产品最有借鉴价值的一段）：

- 配对双方**出发前**先讨论安全流程、建立清晰沟通约定
- **不要在平台上填过多个人信息**，完全信任前住址保持私密
- **见面前先交换电话号码** —— 既为事先沟通引导技巧与行程，也为一方迟到/临时取消时能联系上
- 最初几次**约在公共场所**，直到建立信任
- 每次跑步应有明确计划：**开始时间、集合地点、路线、结束时间**
- 若视障运动员有亲友接送，尽量把对方介绍给陪跑员

**关系模型的关键数字**：每位盲人跑者需要**不少于 6–8 名**固定的志愿陪跑员，才能享受户外跑步的自由。这意味着**池子深度比单次撮合更关键**。

**2026 年运营变化**：Achilles International 自 2026-05-28 起接管运营 United In Stride。新老会员都需通过其在线平台 Rosterfy 完成 Achilles 注册流程，**含背景审查（background check）**；服务对象从视障扩展到所有残障运动员。

### 2.3 无障碍派单出行 —— 滴滴「盲人无障碍出行服务」

2023-07 全国上线。功能点逐条：

- **身份认证入口**：App「我的 → 无障碍服务认证」，完成后享**优先派单**
- **司机端三节点提醒**：在「接单」「到达上车点」「即将到达」三个节点，用**语音播报 + 短信**提醒司机主动联系并寻找盲人乘客，并在上下车环节提供必要协助
- **司机端弹窗**：每次派到单，司机端弹出「此订单乘客为盲人」
- **激励闭环**：完成服务的司机点亮「无障碍勋章」，已点亮的司机后续接到无障碍订单的**概率增加**
- **读屏适配**：2015 年起系统推进 App 信息无障碍，设无障碍专项工作组长期维护
- **导盲犬服务**：2021 年首期上线，解决导盲犬被当作大型犬拒载；带动 **285 万**司机主动完成无障碍服务认证
- **专线**：视障热线 4008109760；老年人电话叫车热线 4006881700

**关怀版**（2021-01 上线小程序，主要面向老年人，非视障线）：预存 **10 个**常用地址（住址、超市、亲属学校、子女住址、医院），有需求时点选常用地址即可完成叫车；「一键叫车」「电话叫车」。

用户实际反馈的收益是三条：不用反复解释自己是盲人、不会找不到车、订单不被取消。

---

## 3. 陪跑这件事本身的领域知识

这一段不是 App 功能，但**直接决定 App 该采集什么、该播报什么**。

**引导方式是运动员的选择**，不是平台的默认值：肘部引导（elbow lead）、牵引绳（tether）、自由跑（running free）三选一。

牵引绳的具体约束：

- 长度要够摆臂、又要短到能响应方向变化
- **手指勾住而非缠在手腕上** —— 一方摔倒时双方都能松手
- 比赛规则**禁止把手绑在一起**，且要求陪跑员与运动员的手之间**至少 5 cm（2 英寸）**
- 材质权衡：绳抓握好但长距离会磨伤；织带舒适但会伸长；硬杆限制自然摆臂

**陪跑员站位**：略靠前、偏一侧 —— 先发现障碍，同时给运动员留出自然步幅空间。

**要口头报出的路况**：湿滑桥面、缝隙、水坑、坑洞、自行车、婴儿车。

**可见性装备**：印有「BLIND」「GUIDE」字样的反光背心，在集体起跑和有车流/自行车/行人的路段尤其重要。

**已被文献记录的障碍**：

- 牵引绳限制自然步幅与摆臂、造成不适，打断节奏并削弱自主性 —— 强化了「陪跑员定速定向」的单向依赖
- **口头提示在户外噪音下失效** —— 语音引导要求持续注意力和清晰的环境声学，户外并非总能满足
- 陪跑员的能力会成为视障运动员的成绩天花板，马拉松这类长距离需要多次换人
- 多数健身房、体育设施、田径场未按视障用户设计

**技术方向**（都还在研究阶段，不是可采购的方案）：

- RunPacer：智能手表振动触觉系统，目标是**对称共跑**而非单向引导 —— 节律性触觉提示能强化动作规律性、支持双方自发同步
- BLINDTRACK（欧盟 FP7）：定位系统 + 触觉腰带，实现 400 m 跑道上的无人陪同跑；6 名视障志愿者试用后表示希望在训练中使用

> **调研缺口（诚实标注）**：天气（雨、高温、结冰、弱光）作为独立变量，本轮检索**没有找到**针对视障跑者的研究。若产品要做天气门槛或天气播报，需要单独一轮。

---

## 4. 合规基线：强制性从哪来

### 4.1 国内

- **GB/T 37668-2019**《信息技术 互联网内容无障碍可访问性技术要求与测试方法》：2019-08-30 颁布，**2020-03-01 实施**。中国「互联网盲道」首个国家标准。TC28 归口、TC28SC35 执行。
- **App 层面目前没有独立的 GB/T 国标编号**。实际依据是 GB/T 37668-2019 **加上**《移动互联网应用（APP）适老化通用设计规范》。《移动互联网应用程序适老化技术规范》仍在待出台清单里 —— 见工信部《促进数字技术适老化高质量发展工作方案》，该方案要求推动 20 项以上急需标准出台，目标是到 2025 年底标准规范体系更健全。
- **评测与标识机制**：改造完成后向中国互联网协会 / 中国信通院申请评测，依据《互联网应用适老化及无障碍水平评测体系》；通过后授予**信息无障碍标识，有效期两年**，工信部对最新版本抽查以决定延续或撤销，**两年一检**，评测结果纳入企业信用评价体系。
- 上位法：《无障碍环境建设法》。

> ⚠️ 与 20260805 那轮的订正呼应：那轮报告曾误引 `YD/T 4211-2023` 当无障碍标准（它实际是域名隐私标准）。本轮同样要防止引错 —— **「App 无障碍国标」这个东西目前不存在**，写合规声明时不要凭印象编一个编号。

### 4.2 国际（若考虑出海，或作为工程基线）

- WCAG 2.0 已于 2012 年成为 **ISO/IEC 40500:2012**，并被欧洲标准 **EN 301 549** 引用
- 欧盟《无障碍法案》（EAA）自 **2025-06-28** 起可执行：面向消费者的数字产品须满足 EN 301 549 / **WCAG 2.2 AA**，违规罚款报道可达 €1M，部分成员国可禁售
- 等级选择：A 级不足以满足法律要求，**AA 是被 ADA、Section 508、EAA 共同引用的实际标准**

### 4.3 可直接当验收项的量化阈值

| 检查项 | 阈值 | 出处 |
|---|---|---|
| 正文文字对比度 | ≥ 4.5:1 | WCAG 1.4.3 |
| 大号文字对比度 | ≥ 3:1 | WCAG 1.4.3 |
| UI 部件 / 边框 / 图标对比度 | ≥ 3:1 | WCAG 1.4.11 |
| 颜色不得作为唯一指示 | 需配图标或文字 | WCAG 1.4.1 |
| 文字放大 200% 不裁切 | 200% | WCAG 1.4.4 |
| 触达区域 | ≥ 44×44 pt（iOS） | WCAG 2.5.5 / 2.5.8 |
| 横竖屏 | **两种都要支持** | WCAG 1.3.4 |
| 标签名包含可见文字 | Voice Control「显示名称」可验 | WCAG 2.5.3 |

### 4.4 Apple 侧的具体要求

- App Store Connect 有官方的 **VoiceOver 评估准则**：能用鼠标或触摸手势点击/拖动的东西，都应当能用 VoiceOver 操作
- **iOS 18 起** App Store 商品页展示 **Accessibility Nutrition Labels**
- 焦点管理：内容变化后要用 `UIAccessibility.post(notification: .screenChanged)` 把 VoiceOver 焦点移到新内容；动态内容用 announcement 通知
- **自定义控件是最大盲区**：UIKit / SwiftUI 标准控件自带无障碍，自定义视图在辅助技术看来是空白，须置 `isAccessibilityElement` 并给本地化的 `accessibilityLabel`
- **自定义转子**（rotor）：让用户按标题、链接或自定义分节跳转
- **触觉**：用户在**看不见屏幕时最依赖触觉**；要用系统定义的触觉模式以免造成混淆；必须在真机上测
- 尊重系统开关：Reduce Motion、Increase Contrast、Bold Text、Button Shapes
- 自定义手势必须提供替代触发方式
- 表单是风险最高的区域；错误恢复路径（密码错、验证码过期、网络失败、权限被拒）必须逐条验证

**测试方法学**：Xcode Accessibility Inspector + Accessibility Audit（可扫对比度、过小触达、缺失标签），Settings 面板可在不改设备设置的前提下模拟 Dynamic Type 与 Reduce Motion。**自动化只能覆盖约 30% 的问题**，其余需要真实用户；自动化工具无法评价「这个按钮标签在上下文里说不说得通」这类主观标准。成本对照：早期介入的无障碍审计约占开发预算 0.5–2%，事后返工则是 10–20%。

---

## 5. 一句话结论

同类产品分三类且功能不可互抄；AidRun 用「派单出行」的匹配机制承载「长期配对陪跑」的人身安全风险面，是个跨类产品，缺口判断必须按风险面（第 2.2 类）而不是按匹配机制（第 2.3 类）来对。可直接照搬的具体机制只有三处：滴滴的**司机端三节点提醒 + 「此订单乘客为盲人」弹窗 + 无障碍勋章激励**、United In Stride 的**出发前四要素约定（开始时间/集合点/路线/结束时间）与一对多储备池**、以及关怀版的**预存常用地址**。合规上要记住：**面向 App 的无障碍国标目前不存在**，实际依据是 GB/T 37668-2019 + 适老化通用设计规范，标识两年一检。

---

## 来源

均为 2026-08-12 核实。

- [United In Stride](https://www.unitedinstride.com/) · [About](https://www.unitedinstride.com/about/) · [Best Practices](http://www.unitedinstride.com/resources/uis-best-practices/)
- [Achilles International — United in Stride](https://www.achillesinternational.org/uis) · [运营交接公告](https://www.achillesinternational.org/blog/unitedinstride)
- [Be My Eyes（Wikipedia）](https://en.wikipedia.org/wiki/Be_My_Eyes)
- [平台联结盲人与志愿者 拨视频电话「精准」求助（中国网，2022-08）](http://guoqing.china.com.cn/2022-08/16/content_78373685.htm)
- [滴滴「盲人无障碍出行服务」全国上线（新华网，2023-07）](http://www.news.cn/tech/20230725/5cc7b73c2ddb412980f30f8998b0abe8/c.html) · [新京报报道](https://m.bjnews.com.cn/detail/1690283552129991.html) · [21 经济网](http://www.21jingji.com/article/20230725/herald/68867762ae10627aa01e9a50643ec19c.html)
- [滴滴上线「一键叫车」，无障碍出行服务覆盖全国 74 城（新浪财经，2021-04）](https://finance.sina.com.cn/chanjing/cyxw/2021-04-30/doc-ikmyaawc2650605.shtml)
- [Sight Scotland — 陪跑引导入门](https://sightscotland.org.uk/articles/information-and-advice/introduction-guided-running-people-visual-impairment)
- [Achilles Nashville — 引导视障运动员的要点](https://achillesnashville.org/tips-for-guiding-a-blind-or-visually-impaired-vi-athlete/)
- [APH ConnectCenter — Running if Blind or Low Vision](https://aphconnectcenter.org/visionaware/recreation-and-leisure/sports-and-excercise/running/)
- [Running blind: the sensory practices of visually impaired runners（Taylor & Francis）](https://www.tandfonline.com/doi/full/10.1080/2159676X.2023.2284704)
- [Exploring the Experiences of Runners with Visual Impairments and Sighted Guides（PMC）](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9566171/)
- [RunPacer（arXiv）](https://arxiv.org/pdf/2507.04241) · [BLINDTRACK（CORDIS）](https://cordis.europa.eu/article/id/170254-advanced-guiding-technology-for-visually-impaired-athletes-to-run-alone)
- [GB/T 37668-2019 标准详情（全国标准信息公共服务平台）](https://std.samr.gov.cn/gb/search/gbDetailed?id=91890A0DA54C80C6E05397BE0A0A065D) · [W3C 中文博客：新国标助力中国信息无障碍建设](https://www.w3.org/zh-hans/blog/2020/updated-chinese-accessibility-standard/)
- [工信部办公厅关于进一步抓好互联网应用适老化及无障碍改造专项行动实施工作的通知](https://www.beijing.gov.cn/zhengce/zhengcefagui/qtwj/202204/t20220413_2675218.html)
- [《促进数字技术适老化高质量发展工作方案》（工信部）](http://wza.isc.org.cn/jszc/gzdt/20240724/3523.html)
- [Apple: Building accessible apps](https://developer.apple.com/accessibility/index.html) · [App Store Connect: VoiceOver 评估准则](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/voiceover-accessibility-evaluation-criteria/)
