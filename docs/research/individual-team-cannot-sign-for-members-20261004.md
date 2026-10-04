# 个人类型开发者账号能不能让成员在 Xcode 里签名？（2026-10-04）

## 背景

#308（2026-10-03）把 `DEVELOPMENT_TEAM` 与 bundle id 换成 `QW8R457UHN` / `com.culiu-tech.aidrun1*`。
`QW8R457UHN` 是 Yu Wu 的**个人类型（Individual）**开发者账号，他在 App Store Connect 里把另一位开发者设为 Admin。
之后那位开发者的 Mac 上 `scripts/device-test.sh` 一条用例都起不来：

```
error: No Account for Team "QW8R457UHN". Add a new account in Accounts settings ...
error: No profiles for 'com.culiu-tech.aidrun1' were found ...
```

Xcode 图形界面 Signing & Capabilities 的 Team 栏同样是红字 `Unknown Name (QW8R457UHN)`。登录、重插 USB、关沙箱均无变化。

## 结论

**不能。** 个人类型账号加进来的人，不论角色（含 Admin），只有 App Store Connect 权限，没有开发权限，Xcode 的团队列表里看不到这个团队。不是配置错误，是账号类型的限制。

## 来源（2026-10-04 核实）

1. App Store Connect Help — [Overview of accounts and roles](https://developer.apple.com/help/app-store-connect/manage-your-team/overview-of-accounts-and-roles/)：
   > Individuals enrolled in the Apple Developer Program can give up to 50 additional users access to their content in App Store Connect. These users receive access to App Store Connect but aren't part of the Apple Developer Program team. They won't receive access to other membership resources or benefits.

   > Organizations enrolled in the Apple Developer Program can add an unlimited number of members to their team. All users receive access to App Store Connect and all other membership resources and benefits.
2. Apple Developer Forums [thread 755912](https://developer.apple.com/forums/thread/755912)（DTS 工程师）：
   > an Individual team can add multiple members but that don't get development privileges.
3. 同帖区分三种团队：Personal Team（未加入任何团队的 Apple ID 自带）/ Individual team / Organization team。

## 出路（待负责人选）

| 方案 | 代价 |
|---|---|
| A. 账号主人本人在自己的 Mac 上跑真机测试与上传 | 其他开发者没法本地真机跑测 |
| B. 升级为组织账号，把开发者加进开发团队 | 需要法人实体与邓白氏码 |
| C. 本地调试改用各自的免费个人团队：把 pbxproj 里写死的 4 个 bundle id 改成「前缀变量 + 后缀」，`LocalConfig.xcconfig` 覆盖前缀 | 要改 pbxproj（行级冻结只禁 `DEVELOPMENT_TEAM`，bundle id 可改）；免费团队 profile 7 天过期、拿不到推送 token |

⛔ 不考虑共用账号主人的 Apple ID 登录：等于共享凭据。
