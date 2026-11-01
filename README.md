# 助盲跑 AidRun iOS 客户端

AidRun helps blind and low-vision runners book a sighted volunteer guide, and supports the run itself with live location, voice feedback and VoiceOver. This repository holds the native iOS client, written in SwiftUI. The backend and the Android client live in private repositories and talk to this app through an API, so this repository alone does not run the full service. The project is pre-launch: testing is by invitation, and no blind or low-vision runner has completed a full order with it yet. The project's own code is licensed under Apache-2.0; third-party SDKs are excluded, see [许可证](#许可证).

## 帮助谁

视障人士跑步时，需要有视力的陪跑员在身边。助盲跑让双方在手机上完成预约和配对。

- 盲人和低视力跑者：用语音或读屏软件预约陪跑员，跑步时听到状态播报。
- 陪跑志愿者：通过实名、活体认证和审核后，自己决定什么时候接单。
- 助盲跑团：成员可以分别注册成跑者或陪跑员。App 目前只有这两种角色，没有跑团管理功能。

## 主要功能

跑者端：

- 用语音或表单下单，全流程支持 VoiceOver，关键状态有语音播报。
- 用语音询问当前订单状态。
- 实名认证和紧急联系人管理，两项都是下单的前提。
- 把行程分享给家人，跑后查看运动记录。

陪跑员端：

- 手动打开接单开关，收到派单后响应。
- 部分订单先由双方通话磨合，再确认配对。
- 记录出发、到达、开始和结束。
- 积分、成就、固定搭档和邀请码。

两端共用：

- 陪跑中互相看到实时位置，距离过远或信号丢失时收到提示，并在锁屏显示实时活动。
- 跑步进行中（`IN_PROGRESS`），双方都可以发起求助。App 记录事件并同步客服，订单状态不变。
- 其他阶段只提供本地拨号（紧急联系人、120、110），App 不代为发送求助。

## 当前状态

项目处于上线前阶段，邀请试用。还没有真实视障用户完整跑过一单。

下面是 2026-11-01 在提交 `fddbcf2e` 上的静态统计，不代表最近一次测试结果：

| 项目 | 数量 |
|---|---|
| `blindRun/` Swift 文件 | 259 个，84,574 行 |
| 单元测试函数 | 2,310 个 |
| UI 测试函数 | 181 个 |

上线前还要完成的事项记在[上线前检查单](docs/pre-launch-checklist.md)里。

## 架构

本仓库只有 iOS 客户端。后端和安卓客户端在私有仓库里，后端通过 REST 和 WebSocket 与本 App 通信。这些仓库没有公开，所以外部读者看不到接口契约的原文。

| 目录 | 内容 |
|---|---|
| `blindRun/` | 主 App，SwiftUI + MVVM，最低 iOS 16 |
| `blindRunWidget/` | 灵动岛与锁屏实时活动 |
| `Packages/AidRunAPI/` | 由后端 OpenAPI 契约生成的客户端代码 |
| `blindRunTests/`、`blindRunUITests/` | 单元测试和 UI 测试 |
| `Vendor/AliyunCloudAuth/` | 阿里云实人认证 SDK 的 podspec 和来源说明。SDK 本身闭源，`pod install` 时下载 |
| `openspec/` | 功能变更的提案与任务记录 |
| `docs/` | 需求、设计、调研和审查记录 |

网络请求集中在 `APIClient`，登录状态集中在 `AppState`，新代码使用 async/await。语音播报用 `AVSpeechSynthesizer`，语音识别用 iOS `Speech` 框架，地图和定位用高德 SDK。服务端地址写在代码里，App 内不能修改。

Debug 构建可以切到 Mock 模式。Mock 的数据都在 App 进程内，不发网络请求，不需要账号。

## 构建

需要 macOS、Xcode 26、CocoaPods 和一个[高德开放平台](https://console.amap.com/)的 iOS Key。

```bash
git clone https://github.com/Jayden23018/blind-run-ios.git
cd blind-run-ios
cp LocalConfig.xcconfig.example LocalConfig.xcconfig
LANG=en_US.UTF-8 pod install
open blindRun.xcworkspace
```

`pod install` 会从阿里云官方地址下载实人认证 SDK（约 25 MB）。下载失败时安装也会失败，检查网络后重跑。

然后在 `LocalConfig.xcconfig` 里填写 `AMAP_API_KEY`。这个文件已被 git 忽略，不要提交真实 Key。没有配置 Key 时，地图位置显示占位视图。

高德 Key 绑定 Bundle ID。使用自己的 Key 时，要同时换成自己的签名团队和 Bundle ID，做法见[真机测试说明](.claude/skills/aidrun-device-test/SKILL.md)。

打开工程时要用 `.xcworkspace`，不要用 `.xcodeproj`。

## 测试

单元测试和 UI 测试只能在真机上跑。高德 SDK 没有 arm64 模拟器版本，所以模拟器不可用。GitHub 的 runner 只有模拟器，因此 CI 不跑任何 XCTest，只做编译门禁、规格校验和 SwiftLint（见 [`verify.yml`](.github/workflows/verify.yml)）。

```bash
scripts/device-test.sh -only-testing:blindRunTests/EmergencySOSTests
```

`Packages/AidRunAPI` 不依赖高德，可以在 Mac 上直接运行：

```bash
cd Packages/AidRunAPI
swift test
```

文档校验：

```bash
node scripts/validate-docs.mjs
```

接口契约校验要读取私有后端仓库。没有访问权限的 fork 上，这几步会给出警告并跳过。Mock 能支撑自动化测试，发布验收仍要在真机上连真实服务完成。

## 文档

| 文档 | 内容 |
|---|---|
| [iOS 客户端使用指南](docs/user-manual.md) | 跑者和陪跑员怎么使用 App |
| [技术与设计说明](docs/technical-design-overview.md) | 路由、并发、语音管线和无障碍实现 |
| [无障碍与语音规范](docs/09-accessibility-and-voice-guidelines.md) | VoiceOver、播报和交互要求 |
| [产品需求](docs/01-product-requirements.md) | 需求基线 |
| [术语表](GLOSSARY.md) | 领域词和代码名称的对照 |
| [工作约定](AGENTS.md) | 仓库的硬规则，包括订单状态和求助红线 |
| [调研索引](docs/research/INDEX.md)、[审查索引](docs/review/INDEX.md) | 历次调研和审查记录 |

部分文档写于 2026 年 8 月，细节可能落后于代码。以代码和 `AGENTS.md` 为准。

## 第三方依赖

高德地图 SDK 和阿里云实人认证 SDK 是闭源商业软件，不受本仓库许可证覆盖。开源依赖由 Swift Package Manager 下载。完整清单、版本和条款见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 贡献

欢迎提 issue 和 PR。动手前请看：

- 先开 issue 说明要改什么，一个 PR 只做一件事。
- 读 [`AGENTS.md`](AGENTS.md)。功能行为有变化时，要先在 `openspec/changes/` 下建变更。
- 改跑者端界面时，用 VoiceOver 走一遍，并保证关键按钮高度不低于 64pt。
- 提交信息格式是 `type: 描述`，例如 `fix: 修正到达播报`。
- 不要提交 Key、手机号、验证码或账号。测试账号写在环境变量里，变量名见 [`docs/test-accounts.md`](docs/test-accounts.md)。
- 发现安全问题时，公开 issue 里不要贴具体账号或号码。

## 许可证

本项目自己的代码和文档使用 [Apache License 2.0](LICENSE)。

第三方组件是例外，不受这份许可证覆盖：

- 阿里云实人认证 SDK 是闭源商业软件，`pod install` 时从阿里云官方地址下载，不存放在本仓库的当前版本里。
- 高德地图 SDK 是闭源商业软件，由 CocoaPods 下载，不存放在本仓库里。
- 开源依赖和 `.claude/skills/swiftui-pro/` 使用各自的许可证。

各组件的条款见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
