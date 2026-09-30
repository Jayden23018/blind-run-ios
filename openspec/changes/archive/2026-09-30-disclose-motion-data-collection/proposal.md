## Why

跑后运动记录（#189）已经在陪跑服务进行中采集步数、步频、爬升高度并随位置上传，但对用户的说法没跟上：

- 首启告知（`PrivacyConsentPurpose.appLaunch`）没提这三项；App 内置隐私政策全文（`LegalFallbackCopy`）
  只写了「位置信息与运动轨迹」，「你的选择」里也没有「运动与健身」权限。
- 线上隐私政策 v1.1 甚至写着「不收集健康与运动数据」。后端 #456 已升 v1.2，线上页 `blindrun-legal` 已发布
  （`f398269`，2026-09-30 复核），iOS 这一侧对不上就是同一个 App 里两种说法。

## What Changes

- 首启告知补一条独立焦点的运动数据说明（是什么、何时采、只给本人看、拒绝不影响陪跑）；
  删除账户那句补上跑步记录。
- **`appLaunch.disclosureVersion` 1 → 2。** 判据见 `PrivacyConsentPurpose.disclosureVersion` 文档注释：
  「新收集一类信息」必须 +1。这不是 PR #52 回退的那种「同一行为换个说法」——
  步数 / 步频 / 爬升是新的一类，旧同意没有覆盖。v1 从未对外分发（无 TestFlight / 上架构建），
  +1 不会拦住任何真实老用户。
- 内置隐私政策补运动数据、「运动与健身」权限的关闭说明、删除账户会删跑后记录；
  `testBuiltInPrivacyPolicyListsEveryCollectedItem` 加「运动与健身」「步数」。
- `PrivacyInfo.xcprivacy` 只补注释：CoreMotion 不在 required-reason API 类别里，无需新增条目；
  健身数据类型归 App Store Connect 隐私标签，不在清单里另写一份（原有立场，未变）。

**不做**：不写 `NSPrivacyCollectedDataTypes`（Apple 未要求，属 ASC 问卷一致性，见 PR 描述）；
不改 `NSMotionUsageDescription`（已与政策 2.5 节一致）；不动采集逻辑。

## Impact

- Affected specs: `auth-account-lifecycle`
- Affected code: `blindRun/Core/PrivacyConsent.swift`、`blindRun/Core/Models/LegalLinksModels.swift`、
  `blindRun/PrivacyInfo.xcprivacy`（仅注释）、`blindRunTests/PrivacyConsentTests.swift`
- 无后端契约改动。措辞来源：后端 `docs/legal/privacy-policy-draft.md` v1.2 的 2.5 / 第六 / 第七节。
- 发布风险：告知版本 +1 后，已同意过 v1 的设备下次冷启动会回到同意页；目前没有这样的外部设备。
