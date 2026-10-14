## Why

语音下单时，转写出来的文字由后端交给第三方大模型（阿里云通义千问）理解。后端隐私政策 v1.2 写了这一点，但 App 内的首启告知和内置隐私说明都没写，使用前也没有单独征求同意（Jayden23018/blind-run-ios#374，上线前审计 M4）。App Store 审核指南 5.1.2(i) 要求与第三方共享个人数据前清楚告知并事先取得明确许可，原文特意点了 "including with third-party AI"。

## What Changes

- 新增一个需要**单独同意**的目的：第一次用语音下单前弹一次全屏同意页，说清「你说的话会转成文字，发给阿里云通义千问理解」「不同意可以改用手动填写」。同意**按账号**记录。
- 没有同意时，`/api/orders/voice/parse` 一次也不发：在 `VoiceOrderServing` 外包一层闸门，所有调用点共用；视图层在启动向导前先问。
- 拒绝后下单页退到手动填写表单，并当场念出反馈，不卡死、不反复劝返。
- 首启告知加一句（`appLaunch` 的 `disclosureVersion` 3 → 4：新的接收方），首启摘要点名；内置隐私政策把「麦克风与语音内容」「第三方 SDK」两处各补一句。

## Capabilities

### New Capabilities
- `voice-order-third-party-llm-consent`: 语音下单把转写文字交给第三方大模型之前的告知与单独同意，以及拒绝后的手动填写出路。

### Modified Capabilities

## Impact

- 代码：`blindRun/Core/PrivacyConsent.swift`、`blindRun/Core/Models/LegalLinksModels.swift`、`blindRun/Core/Services/VoiceOrderService.swift`、`blindRun/Core/AppState.swift`、`blindRun/BlindRunner/BlindBookingView.swift`。
- 叠在 #365 上（同改 `PrivacyConsent.swift`、`LegalLinksModels.swift`、`appLaunch` 版本号，#365 把它升到 3，这里升到 4）。
- 老用户：`appLaunch` 版本 +1 ⇒ 下次冷启动重新看一次首启告知。v3 未随任何外部构建分发。
- 不改后端；后端契约、错误码不变。安卓没有对应 issue。
