# TestFlight 送审前的外部规则增量（相对 08-14 那份）

调研日期：2026-09-27
起因：准备拿到付费开发者账号后立即上 TestFlight 外部测试。08-14 的
[`beta-distribution-and-launch-gates-20260814.md`](./beta-distribution-and-launch-gates-20260814.md)
（人数上限 / 90 天 / 首建必审 / 5.1.1 内测就生效 / 备案边界）**复核触发条件均未触发，结论照用，本文不重复**；
只补这 6 周里新出现或当时没查的规则。代码侧现状见
[`../review/testflight-readiness-20260927.md`](../review/testflight-readiness-20260927.md)。

> 全部经 `WebSearch` / `WebFetch` 转述取得，未逐字取原文的已标注。

---

## 1. 上传用的 Xcode / SDK 下限 —— 本机满足

- **2026-04-28 起**，上传 App Store Connect 的 iOS App 必须用 **Xcode 26 + iOS 26 SDK** 或更新版本构建
  （[Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/)、
  [Submitting](https://developer.apple.com/app-store/submitting/)）。
- **下一道：2027-04**，要求 iOS 27 SDK，且部署目标 ≥ iOS 15（同上 Submitting 页）。我们是 iOS 16，不受影响。
- 本机 `xcodebuild -version` = **Xcode 26.2 (17C52)**，archive 产物 `DTSDKName = iphoneos26.2` ⇒ 满足。

## 2. 年龄分级问卷改版 —— 建 App 记录时要答

- 2025-07-24 起新增 13+ / 16+ / 18+ 三档，问卷新增必答题：应用内控制、能力、**医疗或健康话题**、暴力题材
  （[Updated age ratings](https://developer.apple.com/news/?id=ks775ehf)）。
- 2026-01-31 截止后，不答完的 App **不能提交更新**（[论坛最终提醒](https://developer.apple.com/forums/thread/810295)）。
  新 App 在首次提交时就得答完。
- 2026-07 又加了**社交媒体能力**题（[news tlur8uvi](https://developer.apple.com/news/?id=tlur8uvi)），无截止日。
- ⇒ 对本项目：「医疗或健康话题」一题要按实情答（视力状况、导盲犬属残障身份信息；
  跑后记录采集步数/步频/爬升）；陪跑员与跑者之间**只有电话、没有平台内消息**（见 `docs/pre-launch-checklist.md` §B2），
  社交媒体题大概率答「否」—— 以答题当天的 App 行为为准。

## 3. 无障碍营养标签（Accessibility Nutrition Labels）—— 目前自愿，但对我们是加分项

- 目前**自愿填写**，Apple 明说「将来提交新 App 和更新时会要求」，**未公布日期**
  （[Overview](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels/)）。
- 声明支持某项功能的判据：**用户能用该功能完成 App 的全部常见任务**。按设备分别声明。
  受 Guideline 2.3（元数据准确）约束，夸大会被要求修改。
- **只能给「已有 App Store 上线版本」的设备发布标签** ⇒ **TestFlight 阶段填不了**，这条是上架时的事。
- 不填时产品页照样显示无障碍区块，写着「未表明支持」。对一个助盲 App 这是最容易被看见的空白。

## 4. TestFlight 外部测试的 Test Information

来源：[Provide test information](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information/)、
[TestFlight test information 词条](https://developer.apple.com/help/glossary/testflight-test-information/)

- **必填**：Beta App Description（测试员在邀请里看到）+ Beta App Review Information（联系人、**演示账号**、审核备注）。
- 审核备注 ≤ **4000 字符**，且弹窗写明**不要把演示账号写进备注**，账号放专用字段。
- Feedback Email 同时是邀请邮件的 reply-to 地址。
- 隐私政策 URL：Test Information 页的字段清单里**没查到**它是必填项；但 Guideline 5.1.1 要求所有 App 在
  ASC 元数据与 App 内都有隐私政策链接，且 TestFlight 构建受同一套审核指南约束 ⇒ **按必填准备**。

## 5. TestFlight 包拿到的是**生产环境** APNs token

- TestFlight 构建一律是生产环境推送，没有办法上传一个走开发环境的 TestFlight 包
  （[论坛 751440](https://developer.apple.com/forums/thread/751440)、[论坛 19993](https://developer.apple.com/forums/thread/19993)）。
- 生产 token 发到 `api.sandbox.push.apple.com` 会得到 `BadDeviceToken`，反之亦然。
- 2026-08 的新坑：生产端返回 **403 `BadEnvironmentKeyInToken`**，是 `.p8` key 在开发者后台被限定成仅沙盒环境，
  不是 token 的问题（[论坛 689857 一带的讨论](https://developer.apple.com/forums/thread/689857)，转述）。
- ⇒ 后端 `application.properties` 里 `apns.production=true` 与 TestFlight 匹配；但同一套后端
  **收不了 Xcode 直装包的 token**。两者只能按上报环境分开存，或接受「真机调试收不到推送」。

## 6. 中国大陆备案 × TestFlight —— 仍无一手依据，但证据变了方向

- 对口的 Apple 帮助页 `view-mainland-china-compliance-information` **本轮再抓仍然 404**（08-14 那次也是）。
- **新证据（间接）**：Monal IM 2024-03 被中国区下架时，Apple 通知原文逐字写着
  "The TestFlight version of this app will also be unavailable for external and internal testing in China
  and all public TestFlight links will no longer be functional."
  （[monal-im.org](https://monal-im.org/post/00010-ios-banned/)）
  ⇒ **TestFlight 在中国大陆的可用性至少在某些情形下跟着中国区上架状态走**。
  那次下架的理由是网信办要求，不是缺备案，所以**不能直接推出「没备案就装不了」**。
- 中文社区能查到的只有「国区 Apple ID 装 TestFlight 报『所请求的 App 不可用』」一类零散帖子，
  没有一条把原因坐实为备案。
- ⇒ 08-14「大概率不卡」的判断**降级为「不确定」**。拿到账号后有一个**零成本的一手验法**：
  先传一个包走**内部测试**（不过审），账号持有人用**国区 Apple ID** 装一次；装得上再送外部审核。

## 7. 没查到 / 未核实

- 「后续构建可能免全审」的触发边界（08-14 已列，仍未查到）
- TestFlight App 自身的 VoiceOver 可用性（08-14 已列，只能实测）
- 无障碍营养标签变成强制的日期

## 复核触发条件

- Apple 公布下一次 SDK 下限（预计 2027-04 的 iOS 27）或提前
- 无障碍营养标签公布强制日期
- Apple 帮助页 `view-mainland-china-compliance-information` 恢复可访问，或出现「TestFlight 校验备案号」的一手表述
- 年龄分级问卷再加必答题
