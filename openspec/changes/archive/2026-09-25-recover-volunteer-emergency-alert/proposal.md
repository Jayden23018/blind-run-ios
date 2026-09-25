## Why

Backend issue Jayden23018/blind-run-backend#387 ② and ④ (PR #279, 2026-09-15):

- `GET /api/emergency/active` is now open to volunteers and returns the event of the runner they are escorting. iOS still only called it for the blind role (`AppState.catchUpMissedNotifications`, comment "仅盲人有该端点权限" was stale), so a volunteer whose app was killed never got the "对方正在求助" full-screen alert back — WS `EMERGENCY_*` envelopes carry no `eventId`, the notification catch-up cannot rebuild it.
- On a true cold start the recovery may not run at all for either role: the WS first connection does not emit a recovery signal (only reconnects do), and the foreground catch-up can run before the session is restored.
- `EMERGENCY_VOLUNTEER_ALERT` now carries `distanceMeters` + `distanceBand`. iOS showed the distance only from the device's own fix, so the line was empty in the seconds after a lock-screen push wakes the phone with a cold GPS — the most common arrival case.

## What Changes

- Volunteer sessions call `GET /api/emergency/active` on reconnect, on foreground and once after the cold-start session restore. An open event becomes the volunteer alert (message `EmergencySafetyCopy.volunteerAlertNotice`, elapsed time counted from `triggeredAt`, clamped to not be in the future). It never touches the volunteer's own `activeEvent` / SOS state.
- `COUNTDOWN` events are treated as "nothing open" on the volunteer side (the help request has not been sent yet). `volunteerConfirmedAt` non-null restores the alert as acknowledged (no full screen). No open event clears a stale local alert; a failed request leaves the current alert unchanged.
- The recovered alert has no coordinate (the endpoint never returns raw coordinates), so the place line says it cannot be located — no invented address.
- Distance line: device fix first; otherwise the server's `distanceMeters`, only when `distanceBand` is `NEARBY` / `CLOSE` / `FAR`. `UNKNOWN`, unrecognised or missing band → no distance line. Always shown as a band, never as a number.
- Blind role: behaviour unchanged, except that the cold-start recovery now also runs after session restore.

## Capabilities

### Modified Capabilities

- `global-realtime-notification-handling`: new requirement for volunteer-side emergency alert recovery and the distance fallback.

## Impact

- `blindRun/Core/AppState.swift` (`recoverActiveEmergency`), `blindRun/Safety/EmergencyCoordinator.swift` (`refreshVolunteerAlert`, `VolunteerEmergencyAlert.distanceText`), `blindRun/Core/Models/OrderModels.swift`, `blindRun/Core/Models/WebSocketModels.swift`, `blindRun/Core/AppRealtimeCoordinator.swift`, `blindRun/Safety/VolunteerEscortViews.swift`.
- Backend contract consumed as-is (`api_spec.yaml` `/api/emergency/active`, `websocket-protocol.md` EMERGENCY_VOLUNTEER_ALERT).
- Not in this change: #387 ① (`/location/address`) and #388 ③ (server countdown).
