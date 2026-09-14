# 「一束光地图」技术架构与位置隐私（第三部分）

**日期**：2026-09-13 · **范围**：补齐原始需求里的 D（技术架构）与 F（位置隐私）

> **本系列三份，分工不重复**：
> 1. [community-starlight-map-20260911.md](./community-starlight-map-20260911.md) —— **能不能做**（合规门槛、隐私红线、技术选型、规模前提）
> 2. [light-map-visual-directions-20260911.md](./light-map-visual-directions-20260911.md) —— **做成什么样**（3 个视觉方向 × 12 维度、视觉参考板）
> 3. 本篇 —— **技术细节与隐私方案**
>
> ⚠️ 前两份文件名里的 `20260911` 是落盘时的笔误，三份实际都完成于 2026-09-13。

---

## 0. 本轮推翻了上一轮的两个结论

| 上一轮写的 | 实际 |
|---|---|
| 建议 `k=5`（并自认没有出处） | 🔴 **错的方向**。`k=5` 只在低风险、单一属性、大基数数据集里被引为下限，我们三个前提**全不满足**。按「污名化/高敏感」这一档应取 **k≥20** |
| 把「新用户点亮动画」当成纯粹的视觉设计 | 🔴 **它是一个隐私泄露通道**。Sweeney 2002 的时序攻击直接命中：增量为 1 时 k-匿名当场失效 |

另外还纠正了一条对 SDK 能力的转述错误（见 §1.2）。

---

## 1. D：技术架构

### 1.1 三家未调研 SDK 的结论

#### Mapbox —— **直接出局，不需要进一步评估**

无中国测绘资质，曾经的中国合规版 `Mapbox.cn` 约 2022 年下线。

> 「Mapbox始终没有拿到测绘资质，其地图也无法获得审图号，2022年下半年Mapbox黯然离开」

来源三条，互相印证（第一条本轮 curl 403，是知乎反爬非死链，故另补两条可达来源）：
- https://zhuanlan.zhihu.com/p/563180219 [中]（上述引文出处，反爬）
- [Does Mapbox work in China? — Chinafy](https://www.chinafy.com/blog/does-mapbox-work-in-china) [中]（200）：Mapbox 在中国大陆加载慢或不完整，且不为中国大陆用户提供支持/注册；历史上的中国合规版仅覆盖 Streets / Light / Dark 三种经典样式，**不含现在的 Mapbox Standard**
- [running_page issue #812](https://github.com/yihong0618/running_page/issues/812) [中]（200）：独立开发者报告，标题原文「Mapbox is not available in mainland China」

技术上它其实是四家里最强的（见 §1.3 的 `updateGeoJSONSourceFeatures`），但合规上不可用，**技术优势不构成理由**。

#### MapLibre —— 引擎可用，数据源是问题

- **BSD-2-Clause**，商用无限制、无 MAU 计费（[LICENSE](https://github.com/maplibre/maplibre-native/blob/main/LICENSE.md) [高]）
- 引擎本身不含地图数据，**不构成「互联网地图服务」**，因此不存在自身资质问题 —— 但**接入的瓦片源必须合规**
- 🚩 **关键缺口**：高德/腾讯官方是否允许第三方渲染引擎直接消费其矢量瓦片，**本轮没有找到任何官方许可条款**。这不是「大概可以」，是必须走商务书面确认的事
- 内置聚合（`MLNShapeSource.h` 官方头文件）：

```objc
FOUNDATION_EXTERN MLN_EXPORT const MLNShapeSourceOption MLNShapeSourceOptionClustered;
FOUNDATION_EXTERN MLN_EXPORT const MLNShapeSourceOption MLNShapeSourceOptionClusterRadius;
FOUNDATION_EXTERN MLN_EXPORT const MLNShapeSourceOption MLNShapeSourceOptionClusterMinPoints;
```

- 有 `setFeatureState(featureID:state:)`，可以不重建 source 就改单点视觉 —— 这是高德没有的能力
- 但 `MLNShapeSource.shape` 是整体覆盖式，**没有** Mapbox v10 那种逐 feature 增量更新

#### 腾讯地图 —— 唯一值得记下的备选

- **有互联网地图服务甲级测绘资质**（2010 年首批 31 家之一）[来源](https://www.isc.org.cn/article/11203.html) [中]
- 🔑 **有现成的「微信深色模式同款地图」模板，免费开放给所有开发者** [来源](https://cloud.tencent.com/developer/article/1616759) [中]
- **SDK 展示无调用上限**（与 Mapbox 的 MAU 计费完全不同）[来源](https://lbs.qq.com/FAQ/iossdk_faq.html) [高]
  > 「目前腾讯手机地图SDK没有单日调用上限的限制」
- 聚合走 `QMUClusterManager`（`TencentMapUtils` 工具包），增删是增量的，但改配置后要手动 `refreshCluster`
- ❓ **信息缺口**：没找到腾讯对「单点颜色/透明度能否独立动态更新」的任何说明，既无肯定也无否定

### 1.2 🚩 订正一条转述错误：高德 iOS 有内置夜间底图

上一轮的调研转述说「必须先在高德自定义地图平台后台设计并发布样式」。**这对自定义样式成立，但不是获得深色底图的唯一路径。**

本机 SDK 头文件（`Pods/AMap3DMap-NO-IDFA/MAMapKit.framework/Headers/MAMapView.h`）原文：

```objc
MAMapTypeStandard = 0,  ///< 普通地图   Standard Map
MAMapTypeSatellite,     ///< 卫星地图   Satellite Map
MAMapTypeStandardNight, ///< 夜间视图   Night View
MAMapTypeNavi,          ///< 导航视图   Navigation View
MAMapTypeBus,           ///< 公交视图   Transit View
MAMapTypeNaviNight      ///< 导航夜间视图   Navigation Night View
```

⇒ **一行 `mapView.mapType = .standardNight` 就有深色底图**，不需要注册自定义样式平台、不需要 `styleId` 或 `.data` 文件。自定义样式（`MAMapCustomStyleOptions`，属性为 `styleData` / `styleId` / `styleTextureData` / `styleExtraData`）是**进阶选项**，只在内置夜间观感不满足时才需要。

> 教训与本仓库已有的一条同型（记忆 `tts-rate-follows-voiceover`）：**版本敏感的 API 事实以本机 SDK 头文件为准，不要采信网络转述。**

### 1.3 图层能力矩阵

| 能力 | 高德 | Mapbox | MapLibre | 腾讯 |
|---|---|---|---|---|
| GeoJSON 数据源 | ❌ 走 `MAMultiPointOverlay` 专用对象 | ✅ `GeoJSONSource` | ✅ `MLNShapeSource` | ❌ 走 `QPointAnnotation` |
| 内置 clustering | ❌ 仅官方 Demo 示例代码 | ✅ | ✅ | ✅ `QMUClusterManager` |
| 逐点数据驱动着色 | ❌ | ✅ 表达式驱动 | ✅ 同上 | ⚠️ 只能靠换 icon |
| glow 原语 | ❌ 自绘 icon | ✅ `circle-blur` / `icon-halo-*` | ✅ 同上 | ❌ 自绘 icon |
| 逐点动画 | ❌ | ✅ `feature-state` + Transitionable | ✅ `setFeatureState` | ❓ 未找到说明 |
| realtime 增量更新 | ❌ **只能全量重建** | ✅ `updateGeoJSONSourceFeatures` | ⚠️ 整体替换 `shape` | ⚠️ 增量增删，改配置需重聚合 |
| 中国大陆合规 | ✅ | ❌ **出局** | ❓ 取决于瓦片源 | ✅ |

### 1.4 高德海量点的硬约束（本机头文件原文，已自行核实）

`MAMultiPointOverlay.h`：

```objc
///点对象集合（注意：MAMultiPointItem属性不支持动态更新）
@property (nonatomic, readonly) NSArray<MAMultiPointItem *> *items;
```

🚩 **比此前记录的更严格**：`items` 是 `readonly` —— 不只是单个 item 的属性改不了，**整个数组都换不了**，只能重建 overlay。

`MAMultiPointOverlayRenderer.h`：

```objc
///海量点渲染renderer（since 5.1.0）。 注意：为了保证渲染效率，纹理不受alpha参数影响，如果需要设置透明度，请更换icon。
@property (nonatomic, strong) UIImage *icon;
@property (nonatomic, assign) CGSize pointSize;
@property (nonatomic, assign) CGPoint anchor;
```

⇒ renderer 只有**一个** `icon`，所以**志愿者与视障跑者必须拆成两个 overlay**。

意外收获 —— 海量点**支持点击**：

```objc
- (void)multiPointOverlayRenderer:(MAMultiPointOverlayRenderer *)renderer didItemTapped:(MAMultiPointItem *)item;
```

### 1.5 性能与流量：实测数据（本轮自算，非检索）

原始需求问的是「10k / 100k / 1M 用户的性能、内存、网络」。**在服务端聚合的前提下，这三档的客户端表现完全一样** —— 因为客户端拿到的点数由行政区划数决定，与注册用户数无关。

**全国县级行政区 = 2842 个**（省级 34 / 地级 333）。从民政部官方行政区划代码表逐条解析统计，不是引用的二手数字。
来源：https://www.mca.gov.cn/mzsj/xzqh/2023/202301xzqh.html [高]

流量实测（构造 2733 条真实区县名 + 计数的 JSON，实际 gzip 压缩测量）：

| 下发方式 | 原始 | gzip |
|---|---|---|
| **区县聚合（2842 点，与用户数无关）** | 189 KB | **57 KB** |
| 不聚合 · 10k 用户 | 0.3 MB | 0.1 MB |
| 不聚合 · 100k 用户 | 3.1 MB | 0.8 MB |
| 不聚合 · 1M 用户 | 30.8 MB | **8.3 MB** |

**结论**：
- 聚合后流量**恒定约 57 KB**，1M 用户与 40 用户没有区别
- 不聚合在 100k 就已不可接受（0.8 MB），1M 是 8.3 MB —— 且这还只是坐标，不含任何其他字段
- 渲染点数上限 2842，**远低于高德海量点官方背书的 10 万**
- 内存：2842 个 `MAMultiPointItem` 约 285 KB 量级，可忽略

顺带一个实用结论：**字段名用完整拼写 vs 缩写，gzip 后只差 4 KB**（61 vs 57）—— 不值得为省流量牺牲契约可读性。

⚠️ **本节没有验证的**：高德海量点在真机上渲染 2842 个点的实际帧率与功耗。CI 跑不了 XCTest（模拟器通道因高德无 arm64-sim slice 永久不可用），这一条只能真机实测，**本轮未做**。

### 1.6 技术推荐：不换 SDK

**继续用高德**，理由按权重：

1. 渲染点数上限 2842，高德海量点（10 万）绰绰有余 —— **Mapbox/MapLibre 的技术优势在我们的量级上体现不出来**
2. 深色底图一行代码（§1.2），不需要样式平台
3. 换 SDK 要动**冻结文件 `Podfile`**（AGENTS §9），且要重做定位、逆地理编码、POI 搜索、轨迹回放四块已有集成
4. 点亮动画的限制有解法：**分层** —— 海量点图层画静态聚合点（两个 overlay 分色），刚点亮的那一个用单独的 `MAPointAnnotation`，动画只发生在它身上

**留一个备选**：若内置夜间视图的观感不够，且高德自定义样式平台也调不出想要的效果，腾讯的「微信深色模式同款地图」免费模板是唯一值得重新评估 SDK 的理由 —— 但那时要重新算迁移成本。

---

## 2. F：位置隐私

### 2.1 `k=5` 是错的，且找不到可以照抄的权威数字

**Sweeney 2002 原始论文从未推荐任何 k 值**（全文只用 k=2 做教学示例）：

> **Definition 3. k-anonymity** — Let RT(A1,...,An) be a table and QIRT be the quasi-identifier associated with it. RT is said to satisfy k-anonymity if and only if each sequence of values in RT[QIRT] appears with at least k occurrences in RT[QIRT].

[k-Anonymity: A Model for Protecting Privacy](https://www.eng.auburn.edu/~xqin/courses/comp7370/k-anonymity-2002.pdf) [高]

各国官方实际用过的阈值差异极大 —— **不存在跨场景通用常数**：

| 出处 | 阈值 | 置信度 |
|---|---|---|
| HIPAA Safe Harbor 45 CFR §164.514(b)(2) | **20,000 人**（地理单元） | [高] |
| 英国 ONS「10-5 规则」 | **10**（可按敏感度上调） | [高] |
| 美国 Census FSRDC | **3**（加权前最小单元格） | [高] |
| 美国 CPS 公共文件（2022 起） | **250,000 人** | [高] |
| GB/T 35273-2020 | 🔴 **全文无任何量化数字** | [高]（负向结论） |
| GB/T 37964-2019 | 同样只给模型不给推荐 K 值 | [中，非逐字] |

**推荐 k ≥ 20**，依据是「污名化/高度敏感信息」对应可接受重识别风险 0.05 = 1/20，而我们的场景是**视障身份 + 位置双重敏感 + 极低基数**，属于应当上调的那一类。

⚠️ **诚实标注**：0.05 这个阈值常被归到 El Emam & Dankar (2008, JAMIA) 名下，但本轮**未拿到论文可读全文逐字核对**。**不要在对外文档里把 k=20 写成「论文明确规定」**，只能说是行业普遍引用的推论值。

### 2.2 🔴 HIPAA 那条规则的真正含义：低于阈值要**归并**，不是隐藏

> All geographic subdivisions smaller than a State … except for the initial three digits of a zip code if … (1) The geographic unit formed by combining all zip codes with the same three initial digits contains **more than 20,000 people**; and (2) The initial three digits of a zip code for all such geographic units containing **20,000 or fewer people** is changed to **000**.

[45 CFR §164.514](https://www.law.cornell.edu/cfr/text/45/164.514) [高]

关键在第 (2) 款：不达标的单元被**改写成更粗的粒度**，而不是被删掉。ONS 与 Census 的做法同构（粗粒度化 + 抑制，**不用噪声注入**）。

### 2.3 自适应粒度的量化效果（本轮自算）

模拟全国 2842 个区县的用户分布，对比两种策略在 k=20 下的表现：

| 用户数 | 固定区县：单元数 / **覆盖用户** | 自适应（县→市→省）：单元数 / **覆盖用户** |
|---|---|---|
| 400 | 0 / **0%** | 4 / 37.5% |
| 3,000 | 21 / **25.7%** | 58 / **100%** |
| 10,000 | 31 / **30.3%** | 217 / **100%** |
| 30,000 | 74 / **34.0%** | 403 / **100%** |
| 100,000 | 2115 / 87.7% | 2353 / 99.8% |
| 1,000,000 | 2842 / 100% | 2842 / 100% |

**固定在区县级时，3000 用户下有 74% 的人在地图上根本不存在；自适应粒度在同样规模下做到 100% 覆盖，且每个显示单元都满足 k≥20。**

⇒ **聚合粒度必须自适应，这比 k 取多少更优先。** 产品此前拍板的「放大到区县级」应理解为**终态上限**，不是固定粒度：某个区县人数不足时回退到市、再不足回退到省，而不是显示空白。

⚠️ 这是**模拟不是实测**：用城市规模当人口代理、尾部指数衰减。量级可信，具体百分比不可引用。且助盲跑真实用户会比模型**更集中**（只在有志愿者组织的城市），实际只会更差。

### 2.4 🔴 「新用户点亮动画」是一个隐私泄露通道

Sweeney 2002 §4.3 的时序攻击（temporal attack），原文：

> Data collections are dynamic. Tuples are added, changed, and removed constantly. As a result, releases of generalized data over time can be subject to a temporal inference attack. … Because there is no requirement that RTt respect RT0, linking the tables RT0 and RTt may reveal sensitive information and thereby compromise k-anonymity protection.

**命中我们的方式**：地图随新用户注册实时刷新时，攻击者对比前后两张快照，差集就是新用户所在的区域。**增量为 1 时，k 无论取多少都当场失效** —— 这不是实现缺陷，是这个交互的固有属性。

**可行的改法**（按保护强度排）：

1. **动画与真实注册解耦** —— 点亮动画播放的是「最近一段时间内的新增」的**匿名化重放**，位置从该单元内随机取，时间延迟且打散。用户感受不变，攻击者拿不到任何单个事件
2. **批量快照** —— 地图数据按固定周期（如每周）整体刷新，新旧快照之间不可逐点 diff
3. **只在自己注册的那一刻给自己看** —— 「你的光已经亮起来了」这个情绪时刻对**本人**最有价值，而给全体广播才是泄露源

第 3 条值得单独强调：**用户最想要的那个情绪，其实发生在注册者自己身上**。做成给自己看的一次性动画，既保住了全部情绪价值，又完全没有隐私代价。

### 2.5 模糊化算法对比

| 方案 | 已知攻击 | 适不适合我们 |
|---|---|---|
| **地理聚合** | 低基数退化成定位（Strava）；时序/差分攻击；边界效应 | ✅ 方向对，但**必须自适应粒度 + 抑制** |
| Location fuzzing / 加噪声 | **多次采样求平均可消掉噪声**；grid-snapping 越界瞬间暴露 | ❌ 我们的用户位置基本不变 = 无限次重复观测 |
| **Geo-indistinguishability** (Andrés 2013) | 🔴 **作者自己承认对重复观测无效** | ❌ 见下 |
| Privacy radius | 半径固定时可反复探测边界还原圆心 | ⚠️ 适合「隐藏我家附近」，不适合全国分布图 |

Geo-indistinguishability 论文原文（[arXiv:1212.1984](https://arxiv.org/abs/1212.1984) [高]）：

> Having two observations about the same point reduces the level of privacy, thus we cannot expect the combined mechanism to provide the same level of privacy. … then K can be shown to satisfy **nε-geo-indistinguishability, i.e. a level of privacy that scales linearly with n**. Due to this scalability issue, the technique of independently applying a mechanism to each point is only useful when the number of points is small.

⇒ 重复发布 n 次，隐私强度按 n 线性劣化。我们的场景是静态位置反复展示，n 趋于无穷。**加噪声这条路在我们这里是无效的**，正确的手段是聚合 + 归并 + 抑制。

### 2.6 架构红线：聚合必须在服务端

Tinder 2013 / Bumble 2021 的三边定位漏洞给出的行业原则（[Include Security 原始披露](https://blog.includesecurity.com/2014/02/how-i-was-able-to-track-the-location-of-any-tinder-user/) [高]）：

> developers "to never deal with high resolution measurements of distance or location in any sense on the client-side. These calculations should be done on the server-side..."

⇒ **客户端不得拿到用户明细坐标再本地聚合**。抓包即可还原。k 的判定、粒度的归并全部在服务端完成，客户端只接收聚合后的计数。这一条已写进 handoff 投给后端。

### 2.7 Strava 2018 之后其实没有修好

事件后 Strava 只做了三件事：默认排除 private 用户、要求路线有「一定数量」贡献者（未公开具体数字）、增加可选 Privacy Zone。**聚合机制本身没变**。

2023 年北卡州立大学研究者仍证明可用 Heatmap + 元数据反推真实住址。
[来源](https://support.strava.com/hc/en-us/articles/360015677851-Metro-and-Heatmap-Privacy-Controls) [高]

⇒ **反面教材**：靠打补丁救不了「聚合在低基数区域退化成定位」这个根因。根因是**粒度固定不变**。

### 2.8 一条值得抄的设计：把两个开关拆开

Snap Map 的 Ghost Mode 只控制「**是否可见**」，精度由系统级权限单独控制 —— 两个独立开关。

我们目前把两者耦合在「区县粒度」一个参数上。应当拆成：
- 用户可选「是否让我的存在计入这张地图」（默认值需产品决定）
- 粒度由服务端按 k 匿名自动决定，用户不可调

### 2.9 视障身份是不是敏感个人信息：两条腿都站得住

**第一条（位置本身）—— 确定成立**。PIPL 第二十八条原文：

> 敏感个人信息是一旦泄露或者非法使用，容易导致自然人的人格尊严受到侵害或者人身、财产安全受到危害的个人信息，包括生物识别、宗教信仰、特定身份、医疗健康、金融账户、**行踪轨迹**等信息

[网信办](https://www.cac.gov.cn/2021-08/20/c_1631050028355286.htm) [高]

GB/T 35273-2020 表 B.1 把「**行踪轨迹**」「**精准定位信息**」明文列入个人敏感信息举例 [高]。

**第二条（视障身份）—— 成立但依据较弱**。GB/T 35273 的「个人健康生理信息」举例聚焦疾病诊疗记录（病症、住院志、诊治情况），**不含「残疾」本身**；但《敏感个人信息识别指南》新增的「特定身份信息」类别把**残障人士身份信息**列为例子，理由是可能导致社会歧视。

⚠️ 这一条**只到转述层面**，openstd 不提供免费全文，本轮未拿到官方逐字原文。引用进对外法律文件前须购正式文本核实。

⇒ 不需要靠第二条勉强论证：**位置数据本身独立满足敏感认定**，而两者叠加展示（地图上区分两种光点）产生可反推的组合效应。

### 2.10 一个行业空白

本轮**没有找到任何同类产品对「残障用户位置」做过比普通用户更严格的技术处理**。一篇 W4A 2024 的研究指出，辅助技术类 App 的隐私政策普遍没有针对残障用户的专门条款，尽管使用者身份本身就暴露了残障状态。
来源：*Decoding the Privacy Policies of Assistive Technologies*, W4A 2024, DOI `10.1145/3677846.3677850`（`dl.acm.org` 与 `doi.org` 本轮 curl 均 403，ACM 对无 JS 客户端的已知反爬，非死链；需浏览器或机构访问）[中]

⇒ **不能假设「别人也这么做过」**，这块没有先例可抄。

---

## 3. 落到方案上

综合三份报告，若决定做，技术与隐私侧的具体形态：

| 项 | 结论 |
|---|---|
| 地图 SDK | 高德，不换 |
| 深色底图 | `mapView.mapType = .standardNight`（一行），不够再上自定义样式 |
| 静态点图层 | `MAMultiPointOverlay` × **2**（志愿者/视障跑者各一个，因为 renderer 只有一个 icon） |
| 点亮动画 | 单独的 `MAPointAnnotation`，**不进海量点图层** |
| 聚合位置 | **服务端**，客户端不得拿到明细坐标 |
| 聚合粒度 | **自适应**：区县 → 地级市 → 省，逐级归并直到满足 k |
| k 值 | **≥20**（不是上一轮的 5） |
| 不达标单元 | **归并到上级**，不是隐藏 |
| 刷新策略 | 批量快照（如每周），**不可逐点 diff** |
| 新用户动画 | **改成给注册者自己看的一次性动画**，不向全体广播 |
| 流量预期 | 约 57 KB（gzip），与用户规模无关 |

---

## 4. 反对意见

1. **如果产品坚持「新用户注册时全体可见地点亮」**，那么 §2.4 的三条改法都不接受，此时唯一诚实的做法是**承认这个功能会泄露新注册者的大致位置**，并在隐私政策里明示、且做成用户可退出（opt-out）。不要一边保留广播动画一边声称做了 k-匿名 —— 那是自相矛盾的。

2. **如果真实用户分布远比模型集中**（例如 90% 用户来自 5 个城市），那么 §2.3 的自适应粒度会大量回退到省级，地图上只有几个大光斑，视觉上接近失败。这种情况下应该**放弃全国视图**，只做「你周边」的局部视图 —— 而那个视图不需要中国地图，也就不需要审图号。

3. **如果 k 取 20 被认为过于保守**，需要注意：降 k 的收益是「地图上多几个点」，代价是「视障用户被定位的概率从 1/20 升到 1/k」。这个取舍**不应该由技术侧决定**，且降到 5 以下时 §2.3 的自适应机制基本失效（回退层级太浅）。

---

## 5. 未做 / 未核实

- 高德海量点渲染 2842 个点在**真机**上的帧率与功耗（CI 跑不了 XCTest，本轮无设备）
- 高德/腾讯是否允许第三方渲染引擎消费其矢量瓦片（决定 MapLibre 路线可行性，须商务书面确认）
- 腾讯 SDK 单点颜色/透明度能否独立动态更新（无官方肯定或否定）
- `GB/T 37964-2019` 与《敏感个人信息识别指南》的官方逐字原文（付费标准，只到转述层面）
- El Emam & Dankar (2008) 的 0.05 阈值逐字原文（未拿到可读全文）
- 中国国家统计局自己的小区域数据发布阈值（只查到英美两家）
- 原始需求 A（陪伴感的心理学依据）仍未做 —— 它是唯一能回答「这功能值不值得做」的一块
