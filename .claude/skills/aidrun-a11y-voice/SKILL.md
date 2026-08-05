---
name: aidrun-a11y-voice
description: AidRun 无障碍、语音、地图与定位的硬规则 —— VoiceOver 遍历顺序、64pt 触达、「重复当前状态」按钮、TTS 覆盖点、GCJ-02 单点转换、后台定位限制、二次确认。改动盲人端 UI、语音输入/播报、高德地图或位置上报时读。
---

# AidRun 无障碍 / 语音 / 定位规则

从 `AGENTS.md` 第 9 节与第 10 节的无障碍部分拆出。**这是一个盲人 App，这些不是加分项，是功能本身。**

## 无障碍硬性要求

- 盲人端所有流程必须支持 VoiceOver。
- 关键按钮、输入框、状态文本必须有 `accessibilityLabel` / `accessibilityHint`。
- 盲人端关键主按钮高度 **≥ 64pt**。
- **每个关键盲人页面必须有「重复当前状态」按钮**。它不冗余：系统的 Speak Screen 读不到一次性的 `announcement`。可以降视觉权重，但不能删。
- 视觉顺序与 VoiceOver 遍历顺序可以解耦，技术支点是 `accessibilitySortPriority`。地图可以视觉上铺满上半屏，但**读屏遍历顺序必须操作优先**，且地图不得可交互、不得承载任何必要信息。

## 危险操作必须二次确认

取消订单、完成服务、退出登录、以及任何求助/紧急动作。

求助确认文案在 `AGENTS.md` 第 10 节**逐字锁定**，不要改写、不要"优化"。

## TTS 覆盖点

必须覆盖：进入盲人首页、下单提交、匹配中、志愿者已接单、志愿者已到达、服务开始、服务完成、错误提示、以及求助动作。

TTS 用 `AVSpeechSynthesizer`，STT 用 iOS `Speech` 框架。

## 语音下单

- 首步是 **`.freeform`**：整句说完 → 读回整单 → 说「确认」提交。
  ❌ 不是 `.confirmDefaults`（先念默认值再逐项追问）—— 默认值对首次下单用户几乎总是错的，先听一遍必错的默认值比直接说一句慢。
- 整句解析走 `POST /api/orders/voice/parse`。
- `isAffirmative(_:)` 是本地保守白名单（整串匹配，19 条肯定词，**刻意不收「嗯」**），用在 `.confirm` 轮。
- `SpeechInputService.clearRecognitionStartState` 清空 `completionHandler` 前必须先送出一次 `.error` 终局完成，否则授权被拒时向导会无限静默等待。
- `SpeechInputService.isSpeechPathUnavailable` 让向导跳过无意义的三轮重问。

播报时间前先过 `String.backendLocalDate`：后端 `LocalDateTime` 取自 `now()` 时**带小数秒**（`2026-08-04T11:40:42.644571`），解析不出会把 ISO 原串念给盲人。带时区偏移的串不截，退回 ISO8601 分支。

## 高德地图与定位

- 用高德地图，显示地图、当前位置、订单标记。
- iOS 自己算志愿者到订单起点的距离；志愿者订单列表按距离排序。
- 志愿者派单依赖其最新的 WebSocket `LOCATION_UPDATE`。
- 盲人下单默认以当前位置为起点。
- 高德 key 只能来自本地配置文件。**不要硬编码，不要提交真实 key。** 提供示例配置文件说明需要哪些 key。
- 位置权限被拒时：阻断下单、阻断志愿者接单，并给出前往设置的引导。

### 坐标系（踩过的坑）

`CLLocationManager` 采样是 **WGS-84**，必须在集中的后端边界**恰好转换一次**为 **GCJ-02**。所有文档化的入站订单、REST 兜底、WebSocket 对端、轨迹坐标一律按 GCJ-02 处理。转两次和不转一样错。

### 位置上报

- 拥有 `DRIVER_EN_ROUTE` / `DRIVER_ARRIVED` / `IN_PROGRESS` 会话期间，双方每 5 秒上报最新有效真实位置。
- **Mock / demo 坐标绝不允许上传到云端。**
- 增强后台定位只允许在 `IN_PROGRESS` 期间，必须有告知，且订单/会话一旦不再符合条件必须立即停止。
- 完成后的总结用**盲人端**轨迹作为「本次路线」。志愿者轨迹在通过版本化的评估策略前，不得产出任何异常结论。

## 相关

- 求助 / SOS 的状态与文案红线在 `AGENTS.md` 第 10 节（常驻，不在本 skill）。
- 错误播报的文案选择见 skill `aidrun-error-codes`。
