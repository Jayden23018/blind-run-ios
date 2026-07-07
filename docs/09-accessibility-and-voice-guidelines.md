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
- 订单提交成功
- 系统派单中
- 志愿者已接单
- 志愿者已到达
- 服务已开始
- 服务已完成
- 当前 release 不显示求助入口；后续安全专项恢复时必须补求助播报
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
- Future re-enabled emergency button
- Repeat current status button
- Volunteer availability switch
- Available order rows
- Accept, en-route, arrived, start-service, complete, cancel, and any future re-enabled emergency actions
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

## 6. Dangerous Actions

These actions require a second confirmation:

- Cancel order
- Future re-enabled emergency action
- Volunteer complete service
- Logout

Emergency confirmation copy must be:

> 是否确认进入求助状态？确认后，本次服务将标记为异常，系统会记录当前订单状态。

For this release, emergency UI is hidden:

- The app does not show "紧急求助" or "一键求助" in blind-runner or volunteer service UI.
- The app does not call `POST /api/emergency/trigger`, does not submit GPS, and does not notify the other party from UI in this release.
- Scripts may probe the backend contract. Production emergency recording, auto-call, auto-SMS, or real administrator notification require explicit user authorization, backend contract, and compliance review.

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
- Future emergency copy must be added when the UI is re-enabled by a safety change.

Lifecycle `APP_NOTIFICATION` text from backend templates should not be spoken directly while an active order is present. Order lifecycle TTS should use local order-detail copy so test names or template placeholders are not announced. Volunteer distance copy should use "距出发地点约 X" and be calculated from the latest volunteer location to the order start coordinate.

Important blind-runner TTS should also post a VoiceOver announcement for users who rely on VoiceOver feedback. This includes search state, search results, errors, selected place, and "重复当前状态".

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

## 10. Out of Scope

AI assistant, natural-language time parsing, automatic calls, automatic SMS, real administrator notification, route navigation, real-time track sharing, fall detection, and geofencing are roadmap capabilities. Do not add them without product requirements, safety rules, and acceptance tests.
