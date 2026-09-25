## Why

Backend issues Jayden23018/blind-run-backend#388 ② ③ (PR #279). `POST /api/emergency/trigger` accepts `useCountdown`: the event is stored as `COUNTDOWN`, nothing is sent during the window, and the server turns it into a real request at `countdownEndsAt` (+ grace). If the phone dies, crashes or is killed during those seconds, the request still goes out. Withdrawing inside the window returns `CANCELLED`. In that case no SMS, no volunteer push and no CS alert were ever produced, and the backend also releases the 60 s cooldown.

iOS counted 3 s on the client and only then called trigger. The reasons written down for that (trigger-then-cancel alarms the family twice and locks the cooldown) no longer hold. iOS already answered on #388: follow `countdownEndsAt` instead of counting from 3, and read `CANCELLED` as "已撤回。求助没有发出，没有通知任何人。".

## What Changes

- The long-press / accessibility-action / confirmed-tap path locates first, then sends `trigger` with `useCountdown: true`. Without a fresh real coordinate nothing is sent, as before, and the user now hears it at once instead of after a 3 s countdown.
- `COUNTDOWN` + `countdownEndsAt` → count down to that instant (display capped at 10 s against clock skew): sound, haptic and "N 秒后发出，现在取消还来得及" every second. At the deadline, say only "求助已记录，系统正在处理" (no delivery claim), then ask `/api/emergency/active` after a grace period.
- `countdownEndsAt` null (server did not take the countdown) → treated as sent immediately. No client-side counting.
- Cancel during the countdown calls `PUT /api/emergency/{id}/cancel`:
  - `CANCELLED` → "已撤回。求助没有发出，没有通知任何人。"
  - `FALSE_ALARM` (fired before the request arrived) → existing owner-cancel copy
  - failure → "撤回没有成功……求助可能已经发出" and the event is kept so "撤销求助" and 120/110 stay available.
- Reconnect / cold start reading one's own `COUNTDOWN` event with a future deadline resumes the countdown instead of claiming "sent".
- `EmergencyEventStatus` gains `COUNTDOWN` and `CANCELLED` (terminal), matching backend `EmergencyStatus`.
- Volunteer-initiated SOS and the home SOS bar keep the immediate trigger.

## Capabilities

### Modified Capabilities

- `blind-runner-voice-first-experience`: new requirement for the server-timed SOS countdown.

## Impact

- `Safety/EmergencyCoordinator.swift`, `Safety/EmergencyCountdownView.swift`, `Safety/SafetyModule.swift`, `Core/Models/OrderModels.swift`, `BlindRunner/BlindOrderStatusView.swift`, `Core/MockAPIClient.swift`.
- Behaviour visible to the runner: pressing and holding now registers the request on the server at once. Logging out during the countdown no longer stops it (it is the runner's own request).
