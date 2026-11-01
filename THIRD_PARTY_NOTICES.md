# 第三方组件说明

本仓库的许可证只覆盖项目自己的代码和文档，不覆盖下面列出的第三方组件。每个组件都受它自己的条款约束。

This repository's license covers only the project's own code and documents. It does not cover the third-party components below.

## 闭源 SDK

下面这些是闭源商业 SDK，**不是开源软件**。使用它们要先接受厂商的条款，并申请厂商的账号或 Key。

### 阿里云金融级实人认证 SDK

| 项目 | 内容 |
|---|---|
| 位置 | **不存放在本仓库里**。`pod install` 时从阿里云官方地址下载到 [`Vendor/AliyunCloudAuth/2.3.50/`](Vendor/AliyunCloudAuth/2.3.50/SOURCE.md)，并校验 SHA-256 |
| 版本 | `2.3.50`，只含 ID_PRO 人脸认证所需的子集 |
| 来源与校验值 | 见 [`SOURCE.md`](Vendor/AliyunCloudAuth/2.3.50/SOURCE.md) |
| 用途 | 陪跑员注册时的活体认证 |
| 权利人 | 阿里云。[发布记录页](https://help.aliyun.com/zh/id-verification/financial-grade-id-verification/product-overview/sdk-release-notes)写明的开发者是杭州阿里云智能科技有限公司 |
| 条款 | [阿里云产品服务协议](https://terms.aliyun.com/legal-agreement/terms/suit_bu1_ali_cloud/suit_bu1_ali_cloud201802281451_77479.html)、[金融级实人认证隐私权政策](https://terms.aliyun.com/legal-agreement/terms/suit_bu1_ali_cloud/suit_bu1_ali_cloud202107281509_18386.html) |

⚠️ **本仓库不分发这份 SDK。** 2026-11-01 查阅官方页面，没有查到明确允许公开托管这些二进制的条款，所以改成构建时下载（#636）。下载和使用它要遵守上面的阿里云条款。本仓库早期提交的 git 历史里还留着这些文件，它们不属于开源范围，也不受本仓库许可证覆盖。详情见 [调研记录](docs/research/third-party-sdk-licensing-20261101.md)。

### 高德地图 iOS SDK

| 组件 | 版本（`Podfile.lock`） |
|---|---|
| `AMap3DMap-NO-IDFA` | `11.1.200` |
| `AMapLocation-NO-IDFA` | `2.11.1` |
| `AMapSearch-NO-IDFA` | `9.7.5` |
| `AMapFoundation-NO-IDFA` | `1.8.7`（前三者的依赖） |

- 本仓库**不含**这些 SDK 的二进制。`pod install` 时由 CocoaPods 下载到被忽略的 `Pods/` 目录。
- 权利人是高德。条款见[高德地图开放平台服务协议](https://lbs.amap.com/pages/terms/)。企业或商业用途还要看[技术服务使用许可协议](https://lbs.amap.com/pages/authorization)。
- 高德 Key 要自己申请，不能提交到仓库。

## 开源依赖

这些依赖由 Swift Package Manager 下载，不存放在本仓库里。

### 随 App 分发

| 组件 | 版本 | 许可证 |
|---|---|---|
| [swift-openapi-runtime](https://github.com/apple/swift-openapi-runtime) | `1.12.0` | Apache-2.0 |
| [swift-openapi-urlsession](https://github.com/apple/swift-openapi-urlsession) | `1.3.1` | Apache-2.0 |
| [swift-http-types](https://github.com/apple/swift-http-types) | `1.6.0` | Apache-2.0 |
| [swift-collections](https://github.com/apple/swift-collections) | `1.6.0` | Apache-2.0 |

### 只在开发时用来生成代码（`scripts/openapi/`）

| 组件 | 版本 | 许可证 |
|---|---|---|
| [swift-openapi-generator](https://github.com/apple/swift-openapi-generator) | `1.13.0` | Apache-2.0 |
| [swift-algorithms](https://github.com/apple/swift-algorithms) | `1.2.1` | Apache-2.0 |
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | `1.8.2` | Apache-2.0 |
| [swift-numerics](https://github.com/apple/swift-numerics) | `1.1.1` | Apache-2.0 |
| [OpenAPIKit](https://github.com/mattpolzin/OpenAPIKit) | `6.2.0` | MIT |
| [Yams](https://github.com/jpsim/Yams) | `6.2.2` | MIT |

## 随仓库存放的第三方文档

| 组件 | 位置 | 许可证 |
|---|---|---|
| swiftui-pro（Paul Hudson） | [`.claude/skills/swiftui-pro/`](.claude/skills/swiftui-pro/LICENSE) | MIT，许可证文件在该目录内 |
