# 内测怎么发出去：TestFlight 规则、中国大陆备案边界、以及哪些是「上架才卡」哪些是「内测就卡」

调研日期：2026-08-14
起因：产品即将内测，要发给盲人用户试用。需要确定分发通道的硬规则，以及合规门槛在哪一步才真正生效。
配套：拍摄与剪辑规格见 [`demo-video-production-20260814.md`](./demo-video-production-20260814.md)（本轮不重复）。
代码侧的缺口清单不在本文件 —— 见 [`../pre-launch-checklist.md`](../pre-launch-checklist.md)（§13 分工：research 记外面的事实，checklist 记我们的状态）。

---

## 0. 一句话结论

**内测通道本身不卡备案，卡的是 Beta App Review 和「必须有隐私政策」。**
ICP / App 备案是**中国区 App Store 正式上架**的门槛，不是 TestFlight 的门槛 ——
但这条我**没拿到 Apple 的一手明文**（两个候选官方页均 404），只有搜索转述与反面证据，
**按「未核实」对待，决策前找 Apple Developer Support 书面确认**。

真正会在内测第一天就绊住的是另外两件事，且都已在本仓库确证（非推测）：
线上 `GET /api/misc/legal-links` 返回 `privacyPolicyUrl: null`，以及 iOS 端没有账号注销入口。

---

## 1. TestFlight 硬规则

来源：[TestFlight overview — App Store Connect Help](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)（2026-08-14 经 WebFetch 取回）

| 项 | 值 |
|---|---|
| 内部测试员上限 | **100** 名 App Store Connect 用户 |
| 外部测试员上限 | **10,000** 人 |
| 构建版本有效期 | **90 天**，到期后测试员不再可用 |
| 首个构建 | **必须**送 App Review（按 App Review Guidelines 审） |
| 后续构建 | 「Subsequent builds may not require a full review」 |
| 邀请方式 | 邮件邀请 / 公开链接（可设 1–10,000 的人数上限与筛选条件） |
| 托管 Apple 账户 | 不能用于测试（Apple School/Business Manager 保留域名创建的除外）|

> ⚠️ 上表经 WebFetch 的小模型转述，未逐字取原文。100 / 10,000 / 90 天这三个数多方一致，
> 可放心用；「后续构建可能免审」这条的边界（改了什么会重新触发全审）**没查到明确规则**。

### TestFlight 是不是上架的前置？**不是。**

来源：[Apple Developer Forums 694703](https://developer.apple.com/forums/thread/694703)（含 Apple 员工回帖）·
[Submitting — App Store](https://developer.apple.com/app-store/submitting/)

- **上架不需要先过 TestFlight**。构建传到 App Store Connect 之后就在可发布池里，
  不管有没有发给测试员，直接选中提交 App Review 即可。TestFlight 与上架**从同一个构建池取包**，是两条并列的分发路径，不是先后关系。
- ⚠️ **反直觉的一条**：TestFlight 外部测试的 Beta App Review 与 App Store 的 App Review
  **是相互独立的两道**。App Store 过审**不等于**外部测试自动获准，反之亦然。
  ⇒ **先走外部 TestFlight 再上架 = 过两次审，不是一次。**
- 内部测试（≤100 名 App Store Connect 团队成员）**完全不过审**，上传即测。

⇒ 决策含义：**如果目标只是上架，TestFlight 纯属多余的一道等待。**
只有当「需要外部真实用户的反馈」这件事本身值钱时，才值得付这道额外审核的成本 ——
对 AidRun 这种承诺人身安全、且目标用户是视障者的产品，它值。但要清楚代价是多一次审核周期。

**外部测试的额外必填项**：与外部测试员共享前，**Beta App Description** 与
**Beta App Review Information** 是必填的。本项目的含义 —— 审核员拿不到验证码就进不去，
必须在 Beta App Review Information 里给**演示账号**（本仓库 `docs/test-accounts.md` 的
预置号 + 固定验证码 `000000`）。

**内部 vs 外部的实际差异**：内部测试上传即可测，不过审核；外部测试要过 Beta App Review。
⇒ **第一批盲人测试者如果 ≤100 人且愿意各自注册一个 App Store Connect 用户，
可以完全绕开 Beta App Review。** 但这对盲人是很重的一步（要收邮箱、要对方接受 ASC 邀请），
实践中不划算，除非只发给团队内部几个人做首轮。

---

## 2. 中国大陆备案：门槛在哪一步

来源：[MIIT ICP 备案要求（阿里云帮助中心转述）](https://help.aliyun.com/zh/icp-filing/basic-icp-service/product-overview/icp-filing-requirements-for-a-regular-website) ·
[Apple Developer Forums 743051](https://developer.apple.com/forums/thread/743051) ·
[Adjustments to the China storefront — Apple Developer News](https://developer.apple.com/news/?id=dadukodv)

已确认的时间线与口径：

- **2023-09-01 起**：工信部要求所有新 App 在中国境内应用商店上架前完成备案，
  不限于 App Store，安卓与小程序商店同样适用。
- **2024-04-01 起**：无 ICP 备案号的 App **无法发布更新**并面临强制下架。境外开发者同样适用。
- 备案与**服务器所在地**绑定：服务器在中国大陆的，必须通过接入商备案；资源在香港等大陆以外节点的不需要。
- ICP 备案成功后 30 天内还要办**公安备案**。
- 中国大陆主体另有身份披露要求（《反电信网络诈骗法》《网络安全法》），
  Apple 会在产品页自动展示中文公司名与统一社会信用代码（USCI）。

**TestFlight 这一环**：搜索结果里**没有任何 Apple 官方文档**说 TestFlight 提交要校验备案号。
两个看起来最对口的 Apple 帮助页（`enter-app-information-for-china-mainland`、
`view-mainland-china-compliance-information`）本轮抓取**均返回 404**，
说明 URL 已变更或页面已下线，**我没能取到一手依据**。

⇒ **结论按「大概率不卡、但未证实」处理**：
可以按不需要备案来排内测计划，但**不要把它写进对导师的承诺里**，
且**正式上架前备案是确定要办的**，办理周期以周计，应当现在就并行启动。

> 这是本仓库记忆 `endpoint-exists-is-not-endpoint-usable` 的同类情形：
> 「搜索结果没说要」不等于「规则说不要」。缺一手来源就明写缺。

### 对本项目的直接推论

后端当前是 **`http://47.114.113.171` 裸 IP 直连，没有域名**。
ICP 备案是**绑域名**的，裸 IP 无从备案。所以上架路径上有一串强制前置：

```
买域名 → 域名 ICP 备案（服务器在阿里云大陆节点，走阿里云接入商）
       → 公安备案（备案后 30 天内）
       → 配 HTTPS 证书 → App 改走 https://域名 → 去掉 ATS 例外
       → App 备案拿到号 → 填进 App Store Connect → 才能上架中国区
```

这条链条**不影响内测**（TestFlight 走 IP 也能跑），但它是上架的关键路径，
且每一步都有外部等待时间。**现在不启动，上架时就是它卡着。**

---

## 3. 哪些是「上架才卡」，哪些是「内测就卡」

把 Apple 审核指南与国内法规按**生效时点**重排 —— 这是本轮最有用的一张表：

| 项 | 内测（TestFlight 外部）| 中国区上架 | 依据 |
|---|---|---|---|
| Beta App Review（首个构建）| **卡** | — | TestFlight overview |
| 演示账号（审核员要能登进去）| **卡** | 卡 | Beta App Review Information 必填 |
| 应用内可找到隐私政策 | **卡** | 卡 | App Review 5.1.1；且首个构建就要过 App Review |
| 应用内账号注销入口 | **卡** | 卡 | App Review 5.1.1(v)；PIPL 第 47 条 |
| 敏感个人信息单独同意（身份证号、行踪轨迹）| **卡** | 卡 | PIPL 第 29 条；给真实用户用就适用 |
| 付费开发者账号（$99/年）| **卡** | 卡 | TestFlight 需 App Store Connect 访问权 |
| ICP 备案 / App 备案 | 大概率不卡（**未证实**）| **卡** | 工信部 2023-09-01 / 2024-04-01 |
| HTTPS（去掉明文 HTTP）| 不卡审核，但**卡安全** | 实质卡 | ATS 例外需理由；真实用户数据走明文是事故 |
| 出口合规声明 `ITSAppUsesNonExemptEncryption` | 每次上传手填 | 同 | 缺该键则每个构建都要手动回答 |

**「内测就卡」这一列是本轮的核心产出**：很多人以为内测是「先随便发，上架前再补合规」，
实际上**首个构建就要过 App Review**，于是 5.1.1 这一整组（隐私政策、账号注销、数据收集披露）
在内测第一天就已经生效。

---

## 4. 给盲人做内测：通道本身的无障碍

**没查到**：TestFlight App 自身对 VoiceOver 的适配质量、兑换码流程对盲人的可用性，
本轮没有找到可靠的一手材料（既没有 Apple 的无障碍声明，也没有可信的用户实测报告）。

⇒ **必须自己实测**：找一台干净设备，开 VoiceOver，全程不看屏幕走一遍
「收到邀请邮件 → 装 TestFlight → 兑换 → 装 App → 首次启动」。
这一段任何一步卡住，内测就发不出去，**而它完全不在我们的代码里，改不了**，
只能靠一份「陪同安装说明」或电话协助来绕。

同类风险：邀请邮件本身是 Apple 发的英文/中文模板，我们无法改文案。

---

## 5. 招募与知情同意

拍摄用的知情同意规则已在 [`demo-video-production-20260814.md`](./demo-video-production-20260814.md) §6 写过
（**口头宣读 + 录像记录**替代签字、成片本人过目、可撤回），内测同意沿用同一套，
但**多两条**因为内测收的是真实数据而不是影像：

- 内测要收集的是**手机号 + 身份证号 + 实时位置轨迹 + 紧急联系人的手机号**。
  其中身份证号与行踪轨迹是 PIPL 第 28 条的**敏感个人信息**，第 29 条要求**单独同意**，
  不能混在一揽子用户协议里勾一次了事。
- **紧急联系人是第三方**。用户填进来的是别人的手机号，那个人没同意过。
  同类产品的通行做法是首次添加时给对方发一条告知短信（后端已有
  `contact-added` 模板 `SMS_505950033`），内测前要确认它真的在发。

未找到：国内针对「视障用户参与产品内测」的伦理审查或行业规范。
若学校/导师侧要走伦理审查（IRB 类），这是另一条路径，不在本轮范围。

---

## 6. 没查到 / 未核实

- **TestFlight 是否校验 ICP 备案号**：两个 Apple 官方页 404，无一手依据（见 §2）。
- **「后续构建免全审」的触发边界**：改哪些东西会重新触发完整 Beta App Review，未查到规则。
- **TestFlight App 自身的 VoiceOver 可用性**：无可靠来源，只能实测（见 §4）。
- **视障用户内测的国内伦理规范**：未找到。
- 微信生态分发（小程序 / 企业微信）作为 TestFlight 替代通道的可行性：本轮未查。

---

## 复核触发条件

- Apple 改 TestFlight 的人数上限、90 天有效期，或改「首个构建必审」的规则
- Apple 在 TestFlight 提交环节开始校验中国大陆备案号（**这条一旦发生，§2 的结论直接反转**）
- 工信部调整 App 备案的适用范围或时间要求
- 后端从裸 IP 迁到域名 + HTTPS（§2 那条链条随之作废）
- App Review Guidelines 5.1.1 的账号删除或隐私政策要求变化
- PIPL 对敏感个人信息「单独同意」的执行口径变化
