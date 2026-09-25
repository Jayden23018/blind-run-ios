## Why

Backend issue Jayden23018/blind-run-backend#306 (2026-09-18): `NEW_ORDER` and `GET /api/orders/available` now both carry `visionLevel`, `tetherPreference`, `chatPreference`, `routePreference` and `completedTogetherCount`. The last one is the "有合作经验，已经一起跑过几次" requirement. iOS decoded none of them from the push and only the first two from `/available`, so the invite card depended on a second request that is not guaranteed to contain the order (the list only covers 10 km, while serial dispatch widens to 20 km, backend #368).

## What Changes

- Decode the five fields on `WSNewOrder` (plus `expectedDurationMinutes`, which the push carries since #357) and the three new ones on `AvailableOrderResponse`. All enums stay `String?` (open enums).
- The invite card's runner row is built from the push when it carries any of these fields. Legacy pushes still fall back to `/available`.
- Runner line: vision, tether, chat ("喜欢聊天" / "偏好安静") and route ("想跑公园步道" …). `NO_PREFERENCE` and unrecognised chat or route values add nothing. A missing key adds nothing: no default is invented, and "不知道" must never become "全盲".
- Right-hand tag from `completedTogetherCount`: `0` → "第一次一起跑", N → "一起跑过 N 次", missing → no tag.
- Not in this change: the masked `blindName` in the avatar (#357), and showing the count after acceptance (iOS answered "先不要" on #306 ④).

## Capabilities

### Modified Capabilities

- `system-dispatch-flow`: new requirement for the runner row on the invite card.

## Impact

- `Core/Models/WebSocketModels.swift`, `Core/Models/OrderModels.swift`, `Volunteer/VolunteerInviteQueue.swift`, `Volunteer/VolunteerInviteSheet.swift`, `Volunteer/VolunteerHomeView.swift`.
