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
- 进入求助状态
- 错误提示

Implementation guidance:

- Use one shared `SpeechService`.
- ViewModels decide what to speak when state changes.
- Avoid repeated speech spam during polling by remembering the last spoken order status.
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
- Emergency button
- Repeat current status button
- Volunteer availability switch
- Available order rows
- Accept, en-route, arrived, complete, cancel, emergency actions
- Rating controls

## 4. Blind Runner UI Rules

- Prefer one primary action per screen.
- Primary actions use clear text, high contrast, and large tap targets.
- Avoid dense tables on blind runner screens.
- Use confirmation dialogs for dangerous actions.
- Status pages must state current order state in plain language.
- Error messages must be shown visually and spoken with TTS.

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

## 6. Dangerous Actions

These actions require a second confirmation:

- Cancel order
- Enter emergency state
- Volunteer complete service
- Logout

Emergency confirmation copy must be:

> 是否确认进入求助状态？确认后，本次服务将标记为异常，系统会记录当前订单状态。

After emergency confirmation:

- The app records an emergency event through `POST /api/emergency/trigger`; the order status itself is not changed to emergency.
- TTS announces entry into emergency state.
- Current emergency flow does not restore the previous state.
- Auto-call, auto-SMS, or real administrator notification require explicit user authorization, backend contract, and compliance review.

## 7. Status Copy

Use short, direct Chinese copy.

Recommended status announcements:

- `PENDING_MATCH`: “订单提交成功，系统正在为你派单。”
- `PENDING_ACCEPT`: “志愿者已接单，请等待志愿者出发。”
- `DRIVER_EN_ROUTE`: “志愿者已出发，正在赶往您的位置。”
- `DRIVER_ARRIVED`: “志愿者已到达，请准备开始服务。”
- `IN_PROGRESS`: “服务已开始，请注意安全。”
- `COMPLETED`: “服务已完成，感谢使用助盲跑。”
- `CANCELLED`: “本次预约已取消。”
- `NO_VOLUNTEER`: “暂时没有可用志愿者。”
- emergency event: “已进入求助状态，系统已记录本次异常。”

## 8. Volunteer Accessibility

Volunteer UI should still be accessible, but it may be denser than blind runner UI:

- Availability switch must expose on/off state.
- Available order cells must read nickname, start location, appointment time, and distance.
- Contact phone appears only after accepting an order.
- Action buttons must reflect disabled states when volunteer is unavailable or not approved.

## 9. Acceptance Checklist

- Blind runner happy path can be completed with VoiceOver enabled.
- All required TTS nodes are spoken once at the correct status change.
- “重复当前状态” repeats the latest meaningful state.
- Location denial blocks booking and volunteer distance-based accepting.
- Dangerous actions show confirmation before backend mutation.
- Text and controls remain readable in light and dark mode.

## 10. Out of Scope

AI assistant, natural-language time parsing, automatic calls, automatic SMS, real administrator notification, route navigation, real-time track sharing, fall detection, and geofencing are roadmap capabilities. Do not add them without product requirements, safety rules, and acceptance tests.
