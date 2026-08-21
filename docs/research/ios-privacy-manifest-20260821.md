# 主 App 隐私清单：静态库怎么算、reason code 谁能填

- 日期：2026-08-21
- 触发：ITMS-91053 上传阻断（后端仓库 `docs/review/appstore-readiness-review-20260817.md` §1 A-2）
- 核实方式：Apple 官方文档原文（经 `r.jina.ai` 与 developer.apple.com 的 JSON 后端取原文，
  非搜索转述）+ 本仓库二进制实测

---

## 0. 一句话结论

**第三方 SDK 是静态库时，它用到的 required reason API 必须由「主 App 的」清单声明，
但不能照抄该 SDK 自己的 reason code** —— 其中一部分 Apple 明写「仅限第三方 SDK 声明」，
抄进主 App 清单会把 ITMS-91053 换成 ITMS-91055。

---

## 1. 清单放在哪，谁的算谁的

Apple *Privacy manifest files* 原文：

> Apps and third-party SDKs — distributed as XCFrameworks, Swift packages, or Xcode projects —
> can contain a privacy manifest file, named `PrivacyInfo.xcprivacy`.

> If you distribute your third-party SDK as a static library, use the support for static frameworks
> in Xcode 15 or later to bundle resources, including the privacy manifest file.

⇒ App bundle **根目录**那份 `PrivacyInfo.xcprivacy` 就是**主 App 自己的**清单槽位。
第三方 SDK 的清单应当在它自己的 framework / resource bundle 里，不该平铺到根目录。

CocoaPods 侧的对应关系（本仓库实测）：`s.resources` 是**平铺**复制到 App bundle 根目录，
`s.resource_bundles` 才是放进独立 `.bundle`。把 `PrivacyInfo.xcprivacy` 写进 `s.resources`
= 让 SDK 的清单冒充主 App 的清单。

## 2. 静态库：清单进不了 bundle，声明责任落到主 App

`Vendor/AliyunCloudAuth/2.3.50/Frameworks/` 下 10 个 framework，`file` 全部显示
`ar archive` ⇒ 全是**静态库**。静态库不会被 embed 进 App bundle，所以它们各自内嵌的
5 份 `PrivacyInfo.xcprivacy`（`APPSecuritySDK` / `BioAuthEngine` / `DTFIdentityManager` /
`DTFUtility` / `faceguard`）**一份都进不了产物**。

实测（`find <app> -name '*.xcprivacy'`）：构建产物里 `*.xcprivacy` **只有 1 个**，就是根目录那份。

而静态库的代码被链进主二进制，Apple 的扫描器把这些 API 引用算在主 App 的 binary 头上 ——
ITMS-91053 的邮件正文也是这么写的（"Your app's code in the '[App Name]' file references…"）。

本仓库实测符号（`nm` + `strings`，arm64 slice）：

| 类别 | 命中符号 | 所在 framework |
|---|---|---|
| DiskSpace | `statfs` `fstatfs` `NSFileSystemFreeSize` `NSFileSystemSize` | APPSecuritySDK, DTFUtility, faceguard |
| FileTimestamp | `attributesOfItemAtPath` `NSFileCreationDate` `stat`/`fstat`/`lstat` | 9 个 framework 中多个 |
| SystemBootTime | `systemUptime` | APPSecuritySDK, faceguard |
| UserDefaults | `NSUserDefaults` | 5 个 |

并在构建产物里确认这些代码确实链进来了：`blindRun.debug.dylib` 含 `Toyger` 4186 处、
`APPSecuritySDK` 135 处、`BioAuthEngine` 200 处、`AliyunFaceAuthFacade` 113 处、`DTFIdentityManager` 61 处。

⇒ **主 App 清单必须声明 DiskSpace 与 FileTimestamp**，哪怕我们自己的 Swift 代码一处都没用。

## 3. ⚠️ 不能照抄 vendor 的 reason code（本轮最容易踩的一条）

阿里云 roll-up 清单里的 6 个 code，逐条对 Apple 原文核过：

| code | Apple 原文要点 | 主 App 能不能填 |
|---|---|---|
| `CA92.1` | 读写只对同 App Group 成员可见的 user defaults | ✅ 本 App 用的正是这条 |
| `1C8F.1` | "…**This reason may only be declared by third-party SDKs**" | ❌ 主 App 填 = ITMS-91055 |
| `35F9.1` | 计算 App 内事件的绝对时间戳 | ✅ |
| `7D9E.1` | "Declare this reason **if your app is a health research app**…" | ❌ AidRun 不是健康研究类 App |
| `85F4.1` | 写文件前检查空间是否足够 / 空间不足时删文件 | ✅ 活体检测落盘模型与临时帧 |
| `E174.1` | 磁盘信息用于用户**主动提交**的 bug 报告，且必须**显著展示** | ❌ 本 App 无此功能 |
| `3B52.1` | "…**This reason may only be declared by third-party SDKs**" | ❌ 主 App 填 = ITMS-91055 |
| `C617.1` | 用户经**文档选择器**显式授权的文件的元数据 | ❌ 本 App 无文档选择器 |
| `DDA9.1` | App 容器 / App Group 容器 / CloudKit 容器内文件的元数据 | ✅ SDK 读自己写在容器里的文件 |

⇒ 主 App 侧取 **`CA92.1` + `35F9.1` + `85F4.1` + `DDA9.1`**，各一条。

## 4. `NSPrivacyCollectedDataTypes` 的合法取值

Apple 只认 6 个 purpose 常量：
`…PurposeThirdPartyAdvertising` / `…PurposeDeveloperAdvertising` / `…PurposeAnalytics` /
`…PurposeProductPersonalization` / `…PurposeAppFunctionality` / `…PurposeOther`。

阿里云 roll-up 里那条写的是自由字符串 **`Protect Device Security`** —— 在 Apple 文档里
**0 命中**，不是合法取值。按语义它应归入 `…PurposeAppFunctionality`
（Apple 对该项的说明逐字含 "prevent fraud, implement security measures"）。

⇒ 那份文件被当成主 App 清单时，不只是「口径混淆」，它本身就是一份**取值非法**的主 App 清单。

主 App 自己的清单**刻意不写** `NSPrivacyCollectedDataTypes`：对外数据收集口径以
App Store Connect 隐私标签为准，两处写会漂移。但**标签那边要按阿里云的实际行为勾「设备 ID」**
（它自报 DeviceID 且 `Linked=true`）。

## 5. 被否掉的做法

- **改 Podfile 加 post_install 删资源** —— 不需要。冲突源在我们自己 vendored 的
  `AliyunCloudAuth.podspec`，Podfile 全程没动，`EXCLUDED_ARCHS` 由它的 post_install 照常重生成。
- **把 vendor 清单挪进 `s.resource_bundles`** —— 试过，可行但没必要：阿里云**不在** Apple
  「必须带清单与签名的 SDK 名单」里（后端 review 已 grep 过，`aliyun`/`alibaba` 0 命中），
  留着还得连带那条非法 purpose 取值一起进产物。直接不装。
- **把 vendor roll-up 整份合并进主 App 清单** —— 见 §3，会触发 ITMS-91055。

---

## 来源

- Apple, *Privacy manifest files* — https://developer.apple.com/documentation/bundleresources/privacy-manifest-files（2026-08-21 核实）
- Apple, *NSPrivacyAccessedAPITypeReasons* — https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons（2026-08-21 核实，取自 JSON 后端原文）
- Apple, *NSPrivacyCollectedDataTypePurposes* — https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatypepurposes（2026-08-21 核实）
- Antoine van der Lee, *Solve Missing API declaration (ITMS-91053)* — https://www.avanderlee.com/xcode/missing-api-declaration-required-reason-itms-91053/（二手，仅用于印证 ITMS-91053 邮件正文措辞）

> ⚠️ 抓取方式备忘：developer.apple.com 的文档正文是 JS 渲染的，`r.jina.ai` 只能拿到导航壳，
> reason code 一条都取不到（本轮首次尝试即如此，且**不报错**、只是内容缺失）。
> 正文在 `https://developer.apple.com/tutorials/data/documentation/<path>.json`，
> 且 reason code 藏在表格结构里，按 `"text":"…"` 顺序抽取才拿得到。
> Firecrawl keyless 本轮返回 `Unauthorized: Invalid token`（与记忆 `web-research-channel-routing` 一致）。
