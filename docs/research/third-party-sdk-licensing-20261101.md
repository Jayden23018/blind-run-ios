# 闭源 SDK 能否放在公开仓库（2026-11-01）

**问题**：本仓库公开，`Vendor/AliyunCloudAuth/` 里放着阿里云实人认证 SDK 的二进制。这样做是否被条款允许？高德 SDK 呢？

**结论**：

- **阿里云：未查到明确允许公开托管的条款。** 现行协议的知识产权条款反而写明，未经明示同意不得复制和传播。这里不下法律结论，要由阿里云答复。
- **高德：不涉及。** 本仓库不含高德 SDK 的二进制，由 CocoaPods 在本地下载。

## 阿里云：查到了什么

全部是 2026-11-01 读的官方原文。

| 来源 | 内容 |
|---|---|
| [阿里云产品服务协议](https://terms.aliyun.com/legal-agreement/terms/suit_bu1_ali_cloud/suit_bu1_ali_cloud201802281451_77479.html)，版本更新 2026-10-14，生效 2026-10-21 | §10.1：一方提供的软件等，除权利人明示同意外，另一方「无权复制、传播、转让、许可或提供他人使用」 |
| 同上 | §8.3：不得让产品服务受开源软件许可协议约束。这一条影响本仓库选许可证时的写法：许可证不能覆盖 `Vendor/` |
| 同上 | §65「实人认证」只讲信息保护义务，没有讲 SDK 的分发 |
| [2018 版通用协议的存档页](https://help.aliyun.com/zh/iot-edge/support/alibaba-cloud-terms-of-service) | 旧版的软件许可条款允许把 SDK 复制进产品并随产品传播，同时禁止在信息网络上传播。**这是 2018 年的版本，现行协议里搜不到这段话，不能作为现行依据** |
| [SDK 发布记录](https://help.aliyun.com/zh/id-verification/financial-grade-id-verification/product-overview/sdk-release-notes) | 官方提供公开下载链接，要求使用最新版并遵守合规说明。没有讲再分发 |
| [合规说明](https://help.aliyun.com/zh/id-verification/financial-grade-id-verification/security-and-compliance/compliance-description) | 只讲个人信息告知和权限配置 |
| 仓库内 | `Vendor/` 目录没有许可证文件。`AliyunCloudAuth.podspec` 的 license 字段写的是 `Commercial` |

## 看过但不适用的条款

- [Alibaba Cloud Software License Agreement](https://help.aliyun.com/en/document_detail/161926.html)：它定义的软件是 AliOS Things、Link Voice 等物联网软件，不含实人认证 SDK。
- 2019 年的《云盾实人认证服务协议》PDF：版本过旧，且其中的 SDK 协议讲的是离线授权认证 SDK，不是本仓库用的这一个。

## 高德

[高德地图开放平台服务协议](https://lbs.amap.com/pages/terms/)（更新于 2025-12-03）：

- §4.5：Key 不得披露给第三方。本仓库的 Key 只放在被忽略的 `LocalConfig.xcconfig` 里。
- §4.12.7：除协议明确许可外，不得传播本服务及相关内容。本仓库不存放 SDK 二进制，不触及这一条。
- §3.2：法人或非法人组织用于商业目的要先购买技术服务许可。这是运营层面的事，与仓库是否公开无关。

## 没有做的事

- 没有问阿里云工单。这要用负责人的账号。
- 没有请律师判断。

## 建议

二选一，由负责人决定：

1. 提工单问阿里云，拿到书面答复后写进 `THIRD_PARTY_NOTICES.md`。
2. 把二进制移出仓库，在 `pod install` 前按 `SOURCE.md` 的官方地址和 MD5 下载。这样以后不再分发，但 git 历史里的旧文件还在。

## 决定（2026-11-01）

负责人选第 2 条。实际做法是 `AliyunCloudAuth.podspec` 调用 `scripts/fetch-aliyun-cloudauth.sh`，下载后校验 SHA-256，见 #636。没有改写 git 历史，所以旧提交里的二进制仍然公开可取。这部分风险没有消除。
