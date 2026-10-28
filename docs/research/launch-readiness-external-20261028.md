# 上线前外部规则补查：紧急推送能力、09-27 之后的审核与备案变化、同类产品怎么做真实用户测试（2026-10-28）

**为什么查**：负责人 2026-10-28 要求「判断能不能上线给真实用户」。#201 卡在 Time Sensitive 推送能力上；09-27 之后 Apple 改过审核指南；仓库里没有「视障 App 上线前怎么测」的记录。

**怎么查的**：一个调研 subagent 先整份读 `INDEX.md`，按复核触发条件判旧结论，只补缺口。WebSearch 中英文各 2 种以上说法，打开官方页原文；Apple 文档部分经 DocC JSON 取原文，WWDC21 10091 用 curl 取文字稿。查阅日期全部 2026-10-28。

**沿用的旧结论（触发条件未触发）**：TestFlight 硬规则与备案边界（08-14 `beta-distribution-and-launch-gates-20260814.md`）；SDK 下限、年龄分级、营养标签自愿、生产 APNs（09-27 `testflight-readiness-delta-20260927.md`）；隐私告知（10-01、10-07）；同类产品功能面（08-12）。

## 结论

1. **紧急推送先用 Time Sensitive，不要把 TestFlight 卡在 Critical Alerts 上。**
   - Time Sensitive（`com.apple.developer.usernotifications.time-sensitive`）是普通 capability，在开发者后台勾选、Xcode 加 capability 即可，**不需要 Apple 审批**。能突破定时摘要和专注模式，**不能**突破静音开关。HIG 要求只用于「正在发生或一小时内」的事。
   - Critical Alerts 要 Apple 批准的 entitlement，才能突破静音与专注；申请表需 Account Holder 登录（`developer.apple.com/contact/request/notifications-critical-alerts-entitlement/` 实测 302 到登录页），Apple 没有公开审核口径，HIG 称这类通知「极少见」。
   - 同类：Life360 的 SOS 提醒确认走 Critical Alert；Noonlight、bSafe、Apple「查找」未找到公开说明。
   - 对本 App：#201 剩下的只有「在开发者后台给 App ID 勾选 Time Sensitive」这一步（需要账号权限，不是代码）。Critical 可由 Account Holder 并行申请，申请文案要如实写成「信息性警报，不代表救援已派出」（AGENTS §6）。
2. **09-27 之后没有阻止送审的新规，但有三件事要做。**
   - 审核指南 2026-10-16 更新，新增 **2.5.19**（禁止隐藏、休眠或未说明的功能）：审核备注要说明 Mock、Demo、功能开关。→ 已写进 `docs/testflight/test-information.md` §2.2。
   - 2026-10-13 开发者协议更新，需 Account Holder 登录接受。
   - 2027-04 起新提交需含 iPhone Duo 截图（ASC 发布说明 10-05、10-15）。
   - TestFlight 规则未变；同一版本的后续构建「可能」免完整审核（补上 08-14 报告里「免审边界未查到」的一半）。
   - 备案：找到 Apple 一手页（ASC「App Information」参考页的 Availability in China mainland 一节，MIIT 要求部分 App 有 ICP 备案号）。**订正旧报告**：08-14、09-27 报的「官方页 404」是网址写错，正确网址是 `…/manage-compliance-information/view-china-mainland-compliance-information`。「TestFlight 校验备案号」仍无一手依据。
   - 国家网络安全通报中心 2026-10-26 通报 84 款 App（二手：新浪转 IT 之家），十类问题可当自查清单：首次运行未经同意、隐私政策未逐一列第三方 SDK（45 款，最多）、未单独同意即向第三方提供、注销删除、撤回同意等。
3. **同类产品都是先小范围、再放大。**
   - Be My Eyes：2014-11 只在丹麦区上架，少数用户 beta；到 150 名盲人 + 400 名志愿者后 2015-01-15 全球发布；早期反馈来自志愿者邮件（AFB 评测 `afb.org/aw/16/2/15488`）。
   - Aira、Lookout：试用名单、限定设备 / 国家 / 语言首发、客服渠道收反馈。Seeing AI 的封闭测试未找到。
   - 小红书 TalkBack 适配（Android 官方开发者故事）：自动扫描 → 内部规范 → 按模块测 → 全角色集成测 → 内部问题清完才请外部视障用户做完整测试。
   - 公开可用的验收清单：Apple 无障碍营养标签评估标准（VoiceOver：只靠读屏、无需他人协助完成全部常见任务；Larger Text：至少 200% 或系统最大字号；对比度约 4.5:1 等）。
   - 对本 App：`docs/pre-launch-checklist.md` §D「首轮 3–5 人、电话 / 微信语音反馈、不让测试者真按 SOS」方向一致；再加两条——先内部全角色走一遍再请视障测试者，营养标签评估标准直接当真机验收清单。

## 来源（核实日期均为 2026-10-28）

| 结论 | 来源 |
|---|---|
| Critical entitlement 键名与申请入口 | developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.usernotifications.critical-alerts |
| 中断级别含义 | developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel |
| Time Sensitive 与 Critical 的区别、使用限制 | developer.apple.com/design/human-interface-guidelines/managing-notifications（发送 Critical：「you must get an entitlement to send one」） |
| 配置 Time Sensitive | developer.apple.com/videos/play/wwdc2021/10091/ |
| Life360 SOS 走 Critical | support.life360.com/hc/en-us/articles/23053474049687-SOS-Alerts |
| 审核指南更新与 2.5.19 | developer.apple.com/app-store/review/guidelines/（Last Updated 2026-10-16）、developer.apple.com/news/?id=92th7e5i |
| 开发者协议更新 | developer.apple.com/news/?id=17mwd36z |
| iPhone Duo 截图要求 | developer.apple.com/help/app-store-connect/release-notes/ |
| ICP 备案号一手页 | developer.apple.com/help/app-store-connect/reference/app-information/app-information |
| 84 款 App 通报（二手） | finance.sina.com.cn/tech/digi/2026-10-26/doc-iniwpmtv9319360.shtml |
| Be My Eyes 分阶段上线 | afb.org/aw/16/2/15488 |
| Lookout 首发范围 | blog.google/company-news/outreach-and-initiatives/accessibility/lookout-discover-your-surroundings-help-ai/ |
| 小红书 TalkBack 适配流程 | developer.android.com/stories/apps/xiaohongshu |
| 营养标签评估标准 | developer.apple.com/help/app-store-connect/manage-app-accessibility/ |

## 查不到或受限

- Critical Alerts 申请表字段：要登录开发者账号，未读到。
- Noonlight、bSafe、Apple「查找」用哪种中断级别：换 4 种说法未找到。
- 「没有 capability 时系统会忽略 time-sensitive」只有第三方说法；要在 TestFlight 真机上看「设置 → 通知 → 助盲跑」里有没有「时间敏感通知」开关来核实。
- 盲协、残联牵头招募 App 测试者的具体流程：未找到。
- 「京东到家盲人体验官」「饿了么视障内测」只在搜索摘要里出现，追两次没找到原文，不采用。
