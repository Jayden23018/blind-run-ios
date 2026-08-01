# AidRun Accessibility and Voice Guidelines

本文档定义 AidRun iOS 上线版客户端的无障碍、TTS 和语音输入规则。盲人端体验优先级高于视觉装饰，所有交互必须服务于真实可用的安全订单闭环。

## 1. Principles

- 盲人端语音优先，屏幕辅助。
- 交互保持极简，减少层级、复杂表单和并列选择。
- 关键操作使用大按钮，最小高度 64pt。
- 支持系统深色 / 浅色模式，但优先保证可读性、对比度和按钮清晰度。
- VoiceOver、TTS、“重复当前状态”按钮同时存在，互不替代。

## 2. Required TTS Nodes

Use iOS native `AVSpeechSynthesizer` for TTS.

必须播报：

- 进入盲人首页
- 下单前置条件缺失时的第一个可执行阻断原因（实名未通过时先播报实名这一档，其次才是「请先添加紧急联系人并设置主联系人」，顺序与后端 `OrderCreationService` 一致）
- 紧急联系人新增 / 编辑 / 删除 / 设为主联系人成功后的结果与当前联系人数量或主联系人
- 紧急联系人数量达到 5 个上限、以及只剩 1 个不可删除的限制说明
- 实名认证状态变化与下一步动作（未通过时必须说明无法预约，并给出「设置 → 实名认证」这条走得通的下一步；不得暗示未实名也能下单）
- 订单提交成功
- 系统派单中
- 志愿者派单定位暂不可用时，可见文本与 TTS 均使用“定位暂不可用，可能无法收到派单”，并提供检查定位权限、等待设备获取位置的辅助提示。
- 志愿者已接单
- 志愿者已到达
- 服务已开始
- 服务已完成
- 求助已发出 / 求助未发出（盲人端 `IN_PROGRESS`；每次求助状态变化都要播报，见第 6 节）
- 错误提示

Implementation guidance:

- Use one shared `SpeechService`.
- ViewModels decide what to speak when state changes.
- Avoid repeated speech spam during polling by remembering the last spoken order status.
- Guided booking may speak on explicit step changes, submission, blocking errors, and "重复当前状态"; it must not speak long summaries after every text edit or every `DatePicker` adjustment.
- Provide a “重复当前状态” button on each key blind runner page.

## 3. VoiceOver Requirements

Every key control must include:

- `accessibilityLabel`
- `accessibilityHint`
- Correct accessibility traits, such as button, header, selected, disabled

Required coverage:

- Login phone input and code input
- Role switch controls
- Blind runner home status text
- Create booking fields
- Location permission prompt
- Submit booking button
- Cancel order button
- Blind-runner one-tap SOS button (`IN_PROGRESS` only): minimum 64pt, `accessibilityLabel` "一键求助，遇到紧急情况时点击", and a hint stating that a second confirmation is required and the current location will be reported
- Repeat current status button
- Volunteer availability switch
- Available order rows
- Accept, en-route, arrived, start-service, complete, and cancel (the volunteer has no SOS action in any status)
- Rating controls

## 4. Blind Runner UI Rules

- Prefer one primary action per screen.
- Primary actions use clear text, high contrast, and large tap targets.
- Avoid dense tables on blind runner screens.
- Use confirmation dialogs for dangerous actions.
- Status pages must state current order state in plain language.
- Error messages must be shown visually and spoken with TTS.
- Blind-runner maps are auxiliary: current state, next action, and "重复当前状态" must appear before map content in visual and VoiceOver traversal order.
- Map-equivalent text must be available outside the map. If a demo fallback coordinate is used or the address cannot be resolved, the UI and speech must say so plainly.
- Raw latitude and longitude must not be normal user-facing text or normal VoiceOver output on blind-runner home, booking, or order status screens.

## 4a. Guided Booking Repeat Status

The blind-runner booking flow uses these repeat-status rules:

- Start point step: speak location source, selected address or unresolved/fallback state, and whether the user can keep the current location or search a 高德地点.
- Appointment step: speak the selected `DatePicker` time and whether it is at least 30 minutes in the future.
- Optional needs step: speak only filled optional fields; omit empty route notes, duration, pace, route preference, guide-dog flag, and special notes.
- Review step: speak start point, appointment time, filled optional needs, and any blocking reason before submission.
- Search result feedback announces result count and first place name, and result rows read place name/address only.

## 5. Speech Input

Use iOS native Speech framework for:

- Start location text description
- Destination / route description
- Remarks
- Volunteer service summary if useful

Rules:

- Do not build a global AI assistant.
- Do not parse natural-language time as a core feature.
- Appointment time remains `DatePicker`.
- If speech input fails, show an error and allow keyboard input.
- Request microphone and speech recognition permission only when the user starts voice input.
- Start-place search speech input automatically runs POI search after recognition finishes with non-empty text.
- While start-place recognition is active, expose the search action as "语音识别中" to VoiceOver and keep manual search disabled.
- Search result feedback must announce the result count and first place name; result rows read place name and address, not raw latitude/longitude.
- Every speech-input stop path must stop recording, deactivate the record session, restore `.playback` + `.spokenAudio`, and reactivate playback before stop/completion/search-result TTS. Playback follows the current system route and must not force the built-in speaker.
- If playback restoration fails, keep recognized text, POI search, visible errors, VoiceOver announcements, and keyboard fallback available; record diagnostics and do not retry in a speech loop.
- Real-device acceptance must cover manual stop, final recognition, silence timeout, recognition error, five consecutive sessions, and speaker/Bluetooth route changes.

## 6. Dangerous Actions

These actions require a second confirmation:

- Cancel order
- Delete an emergency contact
- Blind-runner one-tap SOS
- Volunteer complete service
- Logout

Emergency-contact and identity screens additionally require:

- Contact rows announce name, relationship when present, masked phone, primary state, and available actions. Never read the full phone number aloud or expose it through accessibility values.
- Delete is blocked, with a spoken explanation, when only one contact remains; deleting the current primary requires promoting another contact first.
- The identity-card number must never appear in TTS output, accessibility values after submission, logs, or test screenshots.

Emergency confirmation copy must be, verbatim:

> 是否确认进入求助状态？确认后，本次服务将标记为异常，系统会记录当前订单状态。

Cancelling that confirmation sends nothing at all.

Emergency UI rules:

- The SOS entry appears only on blind-runner UI while the canonical order status is `IN_PROGRESS`. It never appears on volunteer UI in any status.
- Without a fresh real GCJ-02 sample the request is not sent. The app must say so both visibly and audibly — "求助未发出：当前无法获取你的位置。请在设置中允许定位后重试，或直接拨打110。" — and never upload a mock or demo coordinate.
- Every non-submitted outcome (no location, network failure, 429 cooldown, 403 `NOT_ORDER_PARTICIPANT`, 400 `BAD_REQUEST`) leads with 未发出 and points at 110.
- **The app must never claim an emergency SMS was delivered or that a contact has been reached.** The backend pushes `EMERGENCY_CONTACT_NOTIFIED` synchronously inside the trigger transaction (`service/EmergencyService.java:370-373`) while the SMS is sent afterwards via `@TransactionalEventListener(AFTER_COMMIT)` + `@Async` (`service/EmergencyContactNotifier.java:60-62`), and a send failure is broadcast only to CS (`:126-135`), never corrected back to the blind runner. iOS therefore substitutes its own progressive-tense copy: "系统正在联系你的紧急联系人，尚未确认对方是否收到。若情况危急请立即拨打110。" The string 联系人已收到短信 must not appear anywhere as shipped copy.
- Auto-call, auto-SMS from the app, or real administrator notification would each require explicit user authorization, a backend contract, and compliance review.

## 7. Status Copy

Use short, direct Chinese copy.

Recommended status announcements:

- `PENDING_MATCH`: “订单提交成功，系统正在为你派单。”
- `PENDING_ACCEPT`: “志愿者已接单。请在{预约时间}前往或等待在出发地点：{出发地点}。志愿者出发后会继续通知你。”
- `DRIVER_EN_ROUTE`: “志愿者已出发，正在前往出发地点。”
- `DRIVER_ARRIVED`: “志愿者已到达，请等待志愿者开始服务。”
- `IN_PROGRESS`: “服务已开始，请注意安全。”
- `COMPLETED`: “服务已完成，感谢使用助盲跑。”
- `CANCELLED`: “本次预约已取消。”
- `NO_VOLUNTEER`: “暂时没有可用志愿者。”

SOS copy is separate from order-status copy and is owned by `EmergencySafetyCopy` (`blindRun/Safety/SafetyModule.swift`). Every line is progressive-tense and ends with “若情况危急请立即拨打110。”:

- Accepted, `PENDING` / unknown: “求助已记录，系统正在处理。”
- `VOLUNTEER_NOTIFIED`: “求助已记录，正在通知同行志愿者确认情况。”
- `CONTACT_NOTIFIED`: “系统正在联系你的紧急联系人，尚未确认对方是否收到。”
- Not sent, no location: “求助未发出：当前无法获取你的位置。请在设置中允许定位后重试，或直接拨打110。”

“重复当前状态” speaks the canonical order status first and then appends the latest SOS line — it never replaces the order status with the SOS line.

Lifecycle `APP_NOTIFICATION` text from backend templates should not be spoken directly while an active order is present. A validated structured status event should immediately use local order-status copy; REST detail/polling remains the fallback when an event is missed. Recently applied terminal-state semantics remain suppressed for 30 seconds after the active order is removed so a parallel template cannot announce the same completion twice. Volunteer distance copy should use "距出发地点约 X" and be calculated from the latest volunteer location to the order start coordinate.

Important blind-runner TTS should also post a VoiceOver announcement for users who rely on VoiceOver feedback. This includes search state, search results, errors, selected place, and "重复当前状态".

### 前台实时通知

- 共享前台 banner 的可见正文、合并 VoiceOver label 与 TTS 必须语义等价；不得把原始 payload、经纬度、内部去重 key 或模板占位符读给用户。
- `HIGH` 到达时立即停止/替换 `NORMAL` 的当前呈现；被抢占的普通通知可稍后继续。两个不同安全 `messageId` 即使文案相同也各播报一次。
- 关联且合法的 `ORDER_STATUS_CHANGED` 必须立即用客户端本地固定文案播报一次，不直接采用服务端 `ttsText`；相同 UUID 重发不得再次播报。
- 活动订单的生命周期 `APP_NOTIFICATION` 必须抑制直接 TTS；状态事件先到时，终态清除活动订单后的 30 秒内仍按目标状态语义抑制并行模板通知。REST 详情与五秒轮询只作为漏事件/断线降级播报来源。
- 跨页面通知由根视图呈现；页面导航、sheet 或订单页未挂载不能成为丢失通知的原因。

## 8. Volunteer Accessibility

Volunteer UI should still be accessible, but it may be denser than blind runner UI:

- Availability switch must expose on/off state.
- Available order cells must read nickname, start location, appointment time, and distance.
- Contact phone appears only after accepting an order.
- Action buttons must reflect disabled states when volunteer is unavailable or not approved.
- Volunteer dispatch and service maps should not expose raw coordinate readouts as normal text.

## 9. Acceptance Checklist

- Blind runner happy path can be completed with VoiceOver enabled.
- All required TTS nodes are spoken once at the correct status change.
- “重复当前状态” repeats the latest meaningful state.
- Location denial blocks booking and volunteer distance-based accepting.
- Dangerous actions show confirmation before backend mutation.
- Text and controls remain readable in light and dark mode.
- Foreground HIGH/NORMAL priority, lifecycle exactly-once speech, and navigation-independent delivery pass UI/accessibility tests.

## 10. Out of Scope

AI assistant, natural-language time parsing, automatic calls, automatic SMS, real administrator notification, route navigation, public real-time track sharing, fall detection, and geofencing are roadmap capabilities. Order-participant live peer markers and completed blind-track summaries are approved only under `enable-live-escort-location-and-track-summary`.
## 会话与账户操作无障碍要求

- 会话恢复必须提供可读的进度状态。
- 注销和删除的确认按钮需提供 VoiceOver 标签、提示、进行中状态及错误公告，并在请求中禁止重复提交。
- 429 提示必须朗读服务端消息和可重试时间；验证码按钮的可用状态应随权威倒计时更新。
- “仅退出本机”必须朗读远端 Token 撤销未确认的风险；账户删除成功或失败不得产生歧义。

## 实时同行与轨迹无障碍

- 同行 marker 只读“志愿者位置已更新”或“盲人跑者位置已更新”，不得朗读经纬度；超过 15 秒读“同行位置暂时不可用”。
- 后台定位开始、权限失效、设备位置过期和网络间断必须有可见文字与一次性 TTS，恢复时不得重复刷屏。
- `ESCORT_DISTANCE_ALERT` 与 `ESCORT_SIGNAL_LOST` 使用服务端安全文案，按 `messageId` 去重并作为 HIGH 抢占；不得说“已报警”或“救援已派出”。
- 完成总结先读“本次路线”及可用里程、时长、平均配速，再到辅助地图；“重复当前状态”必须复述相同摘要。
