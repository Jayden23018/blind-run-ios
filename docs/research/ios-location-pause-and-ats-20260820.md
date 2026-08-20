# CoreLocation 自动暂停 与 ATS 明文例外：两条平台事实

核实日期：2026-08-20
起因：`docs/review/frontend-audit-20260820.md` 的 F2 / F3 / F1 三条结论依赖这两个平台事实，
不能凭印象写。

---

## 1. `pausesLocationUpdatesAutomatically`：默认开、暂停后不自动恢复、in-use 授权下暂停即断

来源：Apple Developer Documentation，
`CLLocationManager.pausesLocationUpdatesAutomatically`
（<https://developer.apple.com/documentation/corelocation/cllocationmanager/pauseslocationupdatesautomatically>，
经 `developer.apple.com/tutorials/data/...json` 取原文，2026-08-20 核实）

原文（关键三句，逐字）：

> After a pause occurs, it's your responsibility to restart location services again when you
> determine that they're needed. Core Location calls the [`locationManagerDidPauseLocationUpdates`]
> method of your location manager's delegate to let you know that a pause has occurred.

> For apps that have in-use authorization, a pause to location updates ends access to location
> changes until the app launches again and is able to restart those updates.

> To prevent location updates from stopping entirely, consider disabling this property and changing
> location accuracy to [reduced] when your app moves to the background.

默认值：文档写 "On supported platforms the default value of this property is `true`；otherwise the
default value is `false` and is immutable."（iOS 属于 supported，即**默认开**）

配套的 delegate 文档
（<https://developer.apple.com/documentation/corelocation/cllocationmanagerdelegate/locationmanagerdidpauselocationupdates(_:)>）
再确认一遍："After a pause occurs, it is your responsibility to restart location services again at
an appropriate time."

**对 AidRun 的含义**：本 App 只申请 `requestWhenInUseAuthorization()`（全仓无
`requestAlwaysAuthorization`），所以命中的正是"in-use 授权下暂停即断到下次启动"那一句。
而 `LocationService.setEscortBackgroundMode` 只在 `IN_PROGRESS` 把这个属性关掉，
`DRIVER_EN_ROUTE` / `DRIVER_ARRIVED`（志愿者赶来、双方碰头）两个阶段保持系统默认的开启态，
且全仓未实现 `locationManagerDidPauseLocationUpdates`。

## 2. ATS 明文例外：不是自动拒审，但会触发人工审查并要求书面理由

来源：
- Apple, *Preventing Insecure Network Connections* / `NSExceptionAllowsInsecureHTTPLoads`
  文档（<https://developer.apple.com/documentation/bundleresources/information-property-list/nsexceptionallowsinsecurehttploads>）：
  把该键设为 `YES` **triggers App Store review**；Apple 举的合格理由示例是
  "connect to a server managed by another entity that does not support secure connections"。
- Apple Developer Forums，DTS（Quinn）多次重申：官方指引只有 *Provide Justification for
  Exceptions* 一节，具体尺度是 App Review 政策问题，Apple 未公开细则
  （<https://developer.apple.com/forums/thread/762911>）。
- NowSecure ATS 指南（<https://www.nowsecure.com/blog/2017/08/31/security-analysts-guide-nsapptransportsecurity-nsallowsarbitraryloads-app-transport-security-ats-exceptions/>）：
  例外应尽量收窄到具体域名，而不是全局 `NSAllowsArbitraryLoads`。
- OWASP MASTG，iOS ATS 知识条目
  （<https://mas.owasp.org/MASTG/knowledge/ios/MASVS-NETWORK/MASTG-KNOW-0071/>）。

**结论**：AidRun 现在的写法（只对 `47.114.113.171` 开 `NSExceptionAllowsInsecureHTTPLoads`，
未开全局 `NSAllowsArbitraryLoads`）已经是收窄写法，**不构成自动拒审**，但：
① 提交时要准备理由，而"服务器是我们自己的、只是还没配 TLS"**不在** Apple 举的合格理由里
（合格理由针对的是"别人管的服务器不支持 TLS"）；
② 真正的问题不在审核，在传输本身——见 review 的 F1。

**未查到**：2025–2026 年有无针对"自有服务器明文"的新硬性拒审规则。搜到的
2025/2026 审核变化（AI 同意条款、年龄分级、Xcode 26 SDK 强制）都与 ATS 无关。
把"会不会因此被拒"当成未定论处理，不要在文档里写死。
