## Why

ICP 备案已通过。工信部信管〔2023〕105 号第二条第（八）项要求 App 在显著位置标明备案编号，并在编号下方链接备案系统网址。国家网信办 2026-05-13 公告要求已上线的生成式 AI 功能公示模型名称和备案号。「关于」页目前没有这些内容，还显示「助盲跑 MVP」「iOS SwiftUI Demo」。

## What Changes

- 「关于」页显示 App 名称和版本号，取代 MVP / Demo 字样。
- 「关于」页显示完整 App 备案编号，编号下方放可点击的备案系统网址。
- 「关于」页公示语音下单使用的大模型名称和大模型备案号。
- 编号在读屏里逐字念，网址是读屏可激活的链接。

不改服务器地址（#621）。不做公安联网备案编号，那个号还没有。

## Capabilities

### New Capabilities

- `app-filing-disclosure`：「关于」页的 App 身份、备案编号和大模型公示。

### Modified Capabilities

无。

## Impact

- `blindRun/Core/AboutAppSections.swift`（新增）、`blindRun/Volunteer/VolunteerOrderFlowViews.swift` 的 `AboutAidRunView`。
- 不涉及后端契约。
- 换模型或换厂商时要同步大模型公示，见 `docs/research/llm-filing-disclosure-20261031.md`。
