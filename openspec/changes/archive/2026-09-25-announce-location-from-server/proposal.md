## Why

Backend issue Jayden23018/blind-run-backend#387 ① (PR #279): `GET /api/orders/{id}/location/address` turns the runner's last reported coordinate into a sentence to read out, always returns 200, and carries `ageSeconds`. iOS answered "播报我的位置" only from the device fix plus a local reverse geocode, so a missing fix or a failed geocode ended in "暂时定位不到", even while the server still held a usable address or coordinate. The volunteer's full-screen alert had the same gap, and the alert restored after a cold start (`recover-volunteer-emergency-alert`) never has a coordinate at all.

## What Changes

- Blind "播报我的位置": say "正在定位" first, then use the device fix + local reverse geocode as before. If that yields nothing, ask the endpoint and read one of three sentences (`demo/docs/safety-hub-ui-spec.md` 屏 2): the address; "暂时查不到地址。你的坐标是北纬…、东经…。"; or the existing "暂时定位不到…110或120" sentence. If `ageSeconds` > 15, add "这是N秒前的位置。". A null age is not mentioned. If the request fails, read the "定位不到" sentence — never silence.
- The device stays first because it is current, while the server copy can be up to 30 s old and exists only in `DRIVER_EN_ROUTE` / `DRIVER_ARRIVED` / `IN_PROGRESS`, and the safety hub is also reachable earlier.
- Volunteer alert place line: if the alert has no coordinate or the local reverse geocode fails, show the server's address or coordinates (the runner's position) with the same age notice. With nothing to show, keep "暂时收不到他的位置".
- Mock returns `degraded` with no coordinate (no invented location).

## Capabilities

### Modified Capabilities

- `blind-runner-voice-first-experience`: new requirement for the server-backed location announcement.

## Impact

- `Core/Services/SafetyService.swift` (`orderLocationAddress`), `Core/Models/OrderModels.swift` (`OrderLocationAddressResponse`), `Safety/SafetyModule.swift` (copy), `BlindRunner/BlindOrderStatusView.swift`, `Safety/VolunteerEscortViews.swift`, `Volunteer/VolunteerOrderFlowViews.swift`, `Core/MockAPIClient.swift`.
