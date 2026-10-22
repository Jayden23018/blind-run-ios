## Why

Backend PR Jayden23018/blind-run-backend#841 (#825 M5), handoff issue Jayden23018/blind-run-backend#843. When the same runner already has a sent, unresolved emergency from the last 30 minutes, `POST /api/emergency/trigger` no longer creates a new event. It merges into the open one: it updates the location, alerts customer service again and returns the **same** `eventId`. The family SMS is not sent again. The returned `status` is the open event's status (never `COUNTDOWN`), and `countdownEndsAt` can be a past, non-null instant (the backend never clears it).

iOS already renders by `status`, so no countdown starts. Two gaps remain:

1. The copy cannot tell a merge from a new request. The runner hears the same sentence as the first time and can think a second request went out, or that the family got another SMS.
2. Screen 3b is presented when `activeEvent.eventID` changes (`EmergencyRecoveryPresentation`). A merge keeps the id, so after "返回跑步" a second press shows no full screen: only one line on the run page and the announcement.

## What Changes

- When a trigger response carries the same `eventId` as the local `activeEvent`, the coordinator enters a new state `mergedIntoOpenEvent(status)`. Screen and VoiceOver say (approved by the project owner on 2026-10-22):
  「这次没有新建求助：你上一次的求助还在处理中，已更新你的位置，系统正在再次提醒客服跟进。若情况危急请立即拨打110。」
  The copy does not mention the family SMS: when the open event is still `PENDING` the backend notifies the contacts for the first time on this merge.
- The coordinator counts merged re-triggers in `mergedRetriggerCount`. Screen 3b is presented again when it changes, the same as on the first press. The screen layout does not change.
- Screen title stays 「求助已发出」. Later realtime updates replace the merged copy with the status copy, as before.

## Capabilities

### Modified Capabilities

- `blind-runner-voice-first-experience`: new requirement for a re-trigger merged into the open event.

## Impact

- `Safety/EmergencyCoordinator.swift`, `Safety/EmergencyCountdownView.swift`, `Safety/SafetyModule.swift` (one line), new `Safety/EmergencyMergedRetriggerCopy.swift`.
- Tests: new `EmergencyMergedRetriggerTests`. Four helpers in `EmergencySOSTests` lose `private` so the new file can reuse them.
- `.swiftlint-baseline.json`: the two length entries of `EmergencyCoordinator.swift` are frozen at the new size (owner approved 2026-10-22; split tracked in Jayden23018/blind-run-ios#502).
- No API change. No backend change.
