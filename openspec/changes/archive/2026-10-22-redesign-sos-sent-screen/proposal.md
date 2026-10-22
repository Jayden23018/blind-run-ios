## Why

Issue Jayden23018/blind-run-ios#506. The blind runner's sent-request screen (screen 3b, `EmergencyCountdownView`) stacks four equal full-width buttons under the title and the status line: call 120, call 110, call the emergency contact, cancel the request. Nothing shows which one matters. The project owner reviewed it on 2026-10-22: too many buttons, not good-looking, not easy to use.

External research (`docs/research/sos-sent-screen-patterns-20261022.md`): no shipped safety product shows more than three actions after an alert is sent; contacts are notified by the system, not dialled one by one from that screen; the emergency call is one clear primary button; cancelling is a deliberate act, never an equal-weight button.

## What Changes

Approved by the project owner on 2026-10-22 (mockup https://claude.ai/artifact/2bRSSR12ygXETEjMygVdCK):

- One primary action: 「拨打120」 with the line 「急救电话」.
- 110 and the primary contact move behind one outline button 「打 110 或紧急联系人」. It opens the existing `emergencyCallOptionsDialog` with a new context whose message is 「求助已经发出。你也可以自己打电话，请选择要拨打的号码。」
- 「撤销求助」 becomes a quiet text button 「误触了？撤销求助」 at the bottom. The hit area stays 64 pt and the confirmation dialog stays.
- Under the title: 「10:02 发出 · 3 分钟前」. Under 1 minute: 「刚刚」. From 1 hour: 「N 小时 M 分钟前」. It refreshes every minute.
- After a merged re-trigger: a two-row timeline 「发出求助」 / 「又按了一次，并入这一条」, hidden from VoiceOver (the body sentence already says it).
- Not-sent state: 「拨打120」 → 「再发一次求助」 → 「打 110 或紧急联系人」. No cancel. Existing words kept.
- The shared reminder `EmergencySafetyCopy.emergencyCallReminder` becomes 「若情况危急请立即拨打120或110。」 everywhere (owner chose app-wide).

## Capabilities

### Modified Capabilities

- `blind-runner-voice-first-experience`: new requirement for the sent-request screen; the merged re-trigger copy now ends with 「拨打120或110」.

## Impact

- `Safety/EmergencyCountdownView.swift`, `Safety/EmergencyCoordinator.swift`, `Safety/SafetyModule.swift`, `Core/DesignSystem/PrimaryButton.swift`.
- Pure moves to keep the SwiftLint ratchet green: `ActiveEmergencyEvent` / `VolunteerEmergencyAlert` → `Safety/EmergencyEventModels.swift`; `EmergencyCallContext` → `Safety/EmergencyCallContext.swift`.
- `ActiveEmergencyEvent` gains `sentAt` and `lastMergedAt` (local data only, nothing persisted, no API change).
- The countdown state and its screen do not change.
