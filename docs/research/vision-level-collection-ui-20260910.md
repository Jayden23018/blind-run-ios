# 视力状况 / 引导方式的采集界面怎么做

调研日期：2026-09-10
档位：**B**（两个明确子问题 + 一个事实核对），两个 subagent + 主会话自己抓表单原文
起因：后端 2026-09-10 投来 CG-2（`demo/docs/research/compliance-gap-20260910.md`）——
`visionLevel` / `hasGuideDog` 已确证为 PIPL 第二十八条的敏感个人信息，收集前需要单独同意。
核查 iOS 代码时发现更硬的事：**这两个字段（以及 `tetherPreference`）根本没有采集入口**，
`blindRun/Profile/ProfileModule.swift:65-74` 三个字段写死传 `nil`，值全部来自后端建档默认值
`TOTAL_BLIND` ⇒ **今天低视力用户在档案里一律被记成全盲**。

先按 §12 整份读过 `INDEX.md`。表里没有这一段；最近的邻居是
[`face-verify-decline-alternative-path-ux-20260908.md`](./face-verify-decline-alternative-path-ux-20260908.md)，
它的三条结论**本次直接复用、不重查**：拒绝入口必须与主路径同屏同级整行铺满 · 拒绝后不许劝返 ·
不得自编审核时长 SLA。

---

## 一句话结论

**两档够用（不用向后端提枚举扩展），问法用功能性自述而非医学分级，
而真正该收的字段不止 `visionLevel` —— `tetherPreference`（引导方式）不敏感、
必须拆到单独同意门之外，它是「拒绝了仍然能用」这件事唯一的支点。**

---

## 1. 同类产品怎么问「视力状况」

### 1.1 United In Stride 注册表单原文 —— 本次最值钱的一条

United In Stride 是美国的视障跑者↔陪跑员配对平台（现已并入 Achilles International）。
现网注册页在平台迁移期间关闭，**表单原文取自 Wayback 存档**，逐字粘贴 Gravity Forms 字段：

```
LEGEND: Member Type(Required)
  ○ Visually Impaired
  ○ Guide

LEGEND: How would you characterize your vision?(Required)
  ○ Visually Impaired (B2/B3 – Some vision)
  ○ Totally Blind (B1 – No vision)

LEGEND: What is your level of experience with a guide?(Required)
  ○ New: No experience running or walking with a guide.
  ○ Novice: Limited experience walking or running with a guide but has experience
    engaging in regular fitness activities.
  ○ Intermediate: Regularly walk or run with a guide. Comfortable training new guides
    based on your own preferences.
  ○ Advanced: Very experienced walking or running with guides. …
```

[来源](https://web.archive.org/web/2024/https://www.unitedinstride.com/register/) [高，存档页 DOM 逐字读取]

🚩 **决定性的一点**：UIS **自己的赛事资源页列的是 B1/B2/B3 三档**
（[原文](http://www.unitedinstride.com/resources/races/)，[中]），
而**注册表单主动折成两档**。同一个组织，在「赛事分组」用三档、在「撮合陪跑」用两档 ——
说明档数是跟**用途**走的，不是跟标准走的。

其余观察（同一份表单）：
- 视力那一问是 **Required，没有「不愿透露」选项**
- **没有问导盲犬**（问的是 tandem bicycle）
- 是**分页表单**：第 1 页账号与联系方式，第 2 页才是视力与偏好，第 3 页 acknowledgment + 手打签名
- 「引导经验」被**单独问**，四档各带一句行为定义 —— 比视力等级更直接地描述「该怎么带这个人」

### 1.2 其余对标

| 对象 | 分几档 | 原文 |
|---|---|---|
| RNIB（英国官方 CVI） | **2 档** | "sight impaired (partially sighted)" / "severely sight impaired (blind)"。⚠️ 这不是自评表单，是**眼科医生填的医疗证明**。[来源](https://www.rnib.org.uk/your-eyes/navigating-sight-loss/registering-as-sight-impaired/) [高] |
| Be My Eyes | **不问分级** | 注册时唯一与视力相关的是二元角色选择（blind user / sighted volunteer），此后不再细分视力等级。[来源](https://www.bemyeyes.com/) [中，官网口径；原始注册帮助页在 Zendesk 反爬墙后，未能逐字核] |
| Guide Dogs UK | 无标准表单 | 「配对访谈」模式，工作人员综合 lifestyle、walking speed、the level of sight they have 判断。[来源](https://www.guidedogs.org.uk/getting-support/guide-dogs/matching-guide-dogs-to-owners/) [低] |

**未查到**：Achilles International 的 Rosterfy 报名表字段（登录墙）、中国黑暗跑团报名表的选项原文、
中国盲人协会的会员登记表模板。四个对标里**没有任何一个**提供「prefer not to say / 不愿透露」选项。

---

## 2. 标准分级有几档，两档够不够

| 标准 | 档数 | 出处 |
|---|---|---|
| 中国 GB/T 26341-2010《残疾人残疾分类和分级》 | **4 级**（一二级为盲、三四级为低视力；视野半径 <10° 不论视力均属盲） | [标准原文 PDF](http://files.anshan.gov.cn/files/ueditor/ASSCL/jsp/upload/file/20230815/1692067790671006554.pdf) [高] |
| 中国残疾人证 | 证面用汉字大写填等级（壹/贰/叁/肆），20 位编码含类别码 + 等级码 | [北京市残联](https://www.bdpf.org.cn/cms68/web1459/subject/n1/n1459/n1508/n1509/n1512/c68465/content.html) [高] |
| WHO ICD-11 | 六档，且**已弃用 "low vision" 作为独立类别名** | [ICD-11 block](https://www.findacode.com/icd-11/block-1103667651.html) [中] |
| IBSA/IPC（视障体育） | **3 档** B1/B2/B3，按 LogMAR 视力与视野判定，须由认证的 VI 国际分级员（眼科或验光医师）判定 | [IBSA for classifiers](https://ibsasport.org/anti-doping-and-classification/classification/for-classifiers/) [高] |

**判断**：三套标准都不是二分法，但它们的设计目的分别是**医学诊断 / 福利认定 / 赛事资格**，
都不是「陪跑志愿者该怎么准备」。而**没有任何一个撮合类产品把这些分级原样接进用户资料**
（UIS 折成两档、RNIB 本来就是两档、Be My Eyes 干脆不问）。

⇒ **对我们的用途，后端现有的 `TOTAL_BLIND` / `LOW_VISION` 两档够用，不提枚举扩展。**
更细的分级需要临床测量（LogMAR、视野度数），用户自评给不出，给出了也不可信。

---

## 3. 问法：功能性自述 vs 医学分级

**Washington Group Short Set**（WHO / 联合国残障统计国际标准）是功能性自评的代表范式：

> "Do you have difficulty seeing, even if wearing glasses?"
> 选项：No difficulty / Some difficulty / A lot of difficulty / Cannot do at all

其官方 FAQ 明确反对是非题：「a question with a Yes/No response option forces the person…
it is better to offer a range of responses」。这套问的是**自评功能受限程度，明确不是诊断分级**。
[来源](https://www.washingtongroup-disability.com/resources/frequently-asked-questions/) [高]

UIS 的措辞同向：**「How would you characterize your vision?」**——问你怎么描述自己，
不是问你几级残疾。

🔴 **最重要的一条，它改变了本次的设计范围**：一线引导技术材料一致主张
**直接问「你希望我怎么引导你」，而不是问分级再推导**。RNIB 官方引导指南逐字（本次自己开页面核过，
不是搜索摘要转述）：

> "there are no hard and fast rules on how to assist people with sight loss."
> "If you are going to guide them, **ask them how they like to be guided**."

[来源](https://www.rnib.org.uk/living-with-sight-loss/supporting-others/guiding-a-blind-or-partially-sighted-person/) [高]

理由是**分级到引导方式之间没有稳定的一一映射** —— 同是 B2，有人用绳、有人挽手臂，
还取决于当天路况、身高差与个人经验。

> ⚠️ 本条初稿引的是 NWADA 的 Human Guide Technique fact sheet，**URL 核验时实测真 404**
> （GET 也是 404，不是反爬），已换成 RNIB 官方页并逐字核过。留这行是因为那份 fact sheet
> 在搜索结果里仍被广泛引用，下次再撞到别再捡回来。

⇒ 本仓库**已经有这个字段**：`TetherPreference`（`blindRun/Core/Models/ProfileModels.swift:419`，
牵引绳 / 搀扶 / 仅语言引导），它和 `visionLevel` 一样从来没有采集入口。

---

## 4. 单独同意的 UI 形态（PIPL）

### 4.1 形态

法条本身**不规定形态**：PIPL 第二十九条只要求「取得个人的单独同意」。形态要求来自配套国标：

- GB/T 42574-2023《个人信息处理中告知和同意的实施指南》把告知分三级，
  单独同意所依托的「增强告知」要求「通常采用个人不可绕过的方式（如设置**专门界面或单独步骤**）」。
  [安全内参解读](https://www.secrss.com/articles/56017) [中，单一转述来源，**未取得国标原文逐字核对**]
- 同一份国标明确：「点击或勾选同意产品或服务的**个人信息保护政策**，
  **不构成**针对具体个人信息处理活动的单独同意」。[同上] [中]

⇒ **全屏页与模态弹窗都合规，唯独「隐私政策整体勾选框」这一种不构成单独同意。**
本仓库既有的 `ConsentDisclosureView`（全屏页 + 逐条告知 + 同意/拒绝**等大**按钮）在这一维度上是对的。

**默认勾选是历次通报的高频违规项**：2019 年四部门《App违法违规收集使用个人信息行为认定方法》
把「以默认选择同意隐私政策等非明示方式征求用户同意」列为「未经用户同意」
（[CAC 原文](https://www.cac.gov.cn/2019-12/27/c_1578986455686625.htm) [高]）；
2026-06-03 网信办通报 71 款 App 时仍在点名同一问题
（[通报转载](https://news.qq.com/rain/a/20260603A053IG00) [中]）。
⇒ 我们的两按钮形态天然无预选，**保持，不要改成勾选框**。

### 4.2 🚩 一条推理更正（本次调研纠正了主会话的错误前提）

PIPL 第十六条原文：

> 个人信息处理者不得以个人不同意处理其个人信息或者撤回同意为由，拒绝提供产品或者服务；
> **处理个人信息属于提供产品或者服务所必需的除外。**

[CAC 官网 PIPL 全文](https://www.cac.gov.cn/2021-08/20/c_1631050028355286.htm) [高]

**第十六条与第二十九条是独立的两层义务**：
- 即使 `visionLevel` 被认定为「提供本服务所必需」，App 因此**可以**在用户拒绝时拒绝下单，
  这**不违反**第十六条；
- 但**不能**因为「必需」就跳过单独同意 —— 第二十九条与第三十条依然成立，且必须在收集前完成。

⇒ 「拒绝 = 不能用 ⇒ 捆绑同意违规」这个担心**不成立**。

**但分层设计仍然更优，理由换成一条反向依据**：GB/T 42574-2023 给出的
「多字段一次性取得单独同意」豁免条件是——

> 针对同一个处理目的或同一业务功能同时处理多项个人信息字段，且**逐项拆分字段后无法达成
> 处理个人信息目的或无法实现该业务功能的**，就多项字段一并告知并一次性取得个人单独同意的，
> 不视为一揽子取得同意

[安全内参解读](https://www.secrss.com/articles/56017) [中]

我们**恰恰能拆**（拒绝视力状况，靠 `tetherPreference` 仍能完成引导）
⇒ **不能**把视力状况和引导方式打包成一次同意，必须拆开。

### 4.3 告知要素

PIPL 第十七条第一款四项 + 第三十条：

> 处理敏感个人信息的，除本法第十七条第一款规定的事项外，还应当向个人告知
> **处理敏感个人信息的必要性以及对个人权益的影响**

[CAC 官网](https://www.cac.gov.cn/2021-08/20/c_1631050028355286.htm) [高]

⚠️ **法条没有给出「必要性 / 对个人权益的影响」要写哪几项的清单**，只有原则性要求，没有格式化范本。

---

## 5. 共识 vs 争议

### 共识

1. 撮合类产品用**两档**，不接医学分级 —— UIS / RNIB / Be My Eyes 三方一致。
2. 问法用**功能性自述**，不用残疾等级 —— UIS 措辞 + Washington Group 官方 FAQ 一致。
3. 「隐私政策整体勾选框」不构成单独同意；默认勾选是明确的违规项 —— 国标与监管通报一致。
4. 引导方式该**直接问**，不该从视力分级推导 —— 一线引导材料一致。

### 争议 / 无定论

1. 🔴 **把敏感信息下发给「候选」志愿者（含最终未接单者），是否构成 PIPL 第二十三条意义上的
   「向第三方提供」？** 若构成，则要求逐一告知接收方的名称、联系方式、处理目的、处理方式与信息种类。
   类比场景（网约车平台向司机展示乘客信息）**学界有分歧、未见监管表态、未见权威裁判**。
   [学理分歧讨论](https://www.tsyzm.com/fileup/1004-2229/NEWS/20190708102349.pdf) [低]
   **这是法律意见，不是工程能拍的** —— 已投 `demo/docs/handoff.md` 待后端确认。
2. **「必需」的判定边界没有官方正面清单**。GB/T 41391-2022 给的是 39 种常见类型 App 的必要信息范围，
   「助盲/助残志愿服务」不在其中。[安全内参解读](https://www.secrss.com/articles/41731) [中]
   需要企业自行论证，通常落在 PIA 里（后端已建 `demo/docs/legal/pipia-20260910.md`）。
3. ⚠️ **「会被谁看到、什么阶段看到（含未接单者）」要写进同意界面** —— 这是对第三十条
   「对个人权益的影响」的**文义推导 + 后端点名要求**，**不是**查到的官方明确要求或范例。
   照做，但**不许在任何文档里把它升格成「法规要求」**。

---

## 6. 反对意见（什么情况下上面的建议是错的）

1. **如果产品后续要接入残联的补贴、赛事报名或保险核保**，「两档够用」立刻作废 ——
   那些场景要对接可核查的临床标准（GB/T 26341 的一至四级、或 IBSA 的 B1/B2/B3），
   自评的两档不被承认。届时要加的不是枚举值，而是**一个可上传残疾人证的字段**，
   与自评字段并存、语义不同（一个是自述，一个是凭证）。
2. **如果拆分后「引导方式」的填写率同样很低**，那么本次分层就只是把一个空字段换成了两个空字段，
   「拒绝了仍然能用」是纸面上的。判据是上线后 `tetherPreference != nil` 的比例 ——
   低于 `visionLevel` 的填写率就说明分层没有产生实际的降级路径，
   要回头考虑把引导方式做成下单流程里的一步（那会与「不打断语音下单」冲突，是个真取舍）。
3. **如果后端把 `visionLevel` 接进派单打分**，「不参与排序」这句同意文案立刻变成假话，
   而它同时出现在本次的两处告知里（同意屏第 2 条 + 派单算法说明页）。
   后端隐私政策 §四目前明确写着它不参与排序 —— 这条一变，两处文案与对应用例一起改。

---

## 7. 未查到 / 已知边界

- UIS 与 Achilles 现网（Rosterfy）注册表的字段 —— 登录墙；本文用的是 Wayback 存档的**迁移前**版本
- GB/T 42574-2023 与 GB/T 35273-2020 的**官方全文逐字原文** —— openstd.samr.gov.cn 只提供基本信息页，
  不提供免费全文。本文第 4 节引的国标条款**全部来自解读文章转述**，标 [中]，
  **要引进对外法律文件前必须购买正式文本核实**
- 网信办/工信部针对**助残/助盲类 App**、或「志愿者接单前看到求助者敏感信息」这一具体场景的
  通报案例 —— 试过「残障人士 敏感个人信息 单独同意 志愿者接单前」「残疾 志愿者 无障碍 通报」
  等多组词，只命中医疗健康类 App 通报等邻近但不对口的案例
- 中国黑暗跑团、中国盲人协会报名表的字段清单
- 四个对标产品是否提供「不愿透露」选项 —— **全部未查到**（不是「没有」，是没查到）

### URL 核验留痕（下次跑这条命令的人先看这里）

本文所有链接跑过 skill 要求的核验。**两个来源拒 `HEAD` 但 `GET` 返 200，是反爬不是死链，别删**：

| URL | HEAD | GET | 判定 |
|---|---|---|---|
| `news.qq.com/rain/a/20260603A053IG00` | 501 | 200（85 KB） | 反爬，保留 |
| `www.tsyzm.com/fileup/.../20190708102349.pdf` | 403 | 200（406 KB） | 反爬，保留 |
| `support.bemyeyes.com/hc/...` | 403 | 403（5.9 KB 壳页） | Zendesk 机器人墙，**已换成 `bemyeyes.com`** |
| `nwadacenter.org/.../Fact%20Sheet%20Human%20Guide%20Technique.pdf` | 404 | 404 | **真死链，已换成 RNIB 官方页** |

---

## 复核触发条件

- 后端给 `visionLevel` 加枚举值，或上线 `NOT_SPECIFIED`（届时「拒绝 = 不传字段」的降级写法要改）
- 后端把 `visionLevel` 接进派单打分（两处「不参与排序」的文案与用例同时作废）
- UIS 迁到 Achilles Rosterfy 后注册表改版（第 1 节的表单原文是迁移前的）
- GB/T 42574-2023 或 GB/T 35273-2020 出新版，或拿到官方全文（第 4 节全部转述可升级为原文）
- 网信办/工信部就「助残类 App 敏感信息下发给其他用户」发布通报或问答（争议 1 与 2 可能被直接答掉）
- 产品接入残联补贴 / 赛事报名 / 保险核保（反对意见 1 触发，两档作废）
