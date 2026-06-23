# AGENTS.md

Project-level rules for all AI coding agents working on AidRun / 助盲跑 MVP.

Do not treat this file as product brainstorming. It is the highest-priority working contract for agents in this repository.

**Repository boundary:** This is the AidRun native iOS frontend code repository only. It does not contain, maintain, build, or deploy backend code. The backend is an external service, and the only real integration endpoint is `http://47.114.113.171`. Agents must not add server source code, database configuration, server build scripts, or a locally runnable backend to this repository.

## 1. Project Source of Truth

When sources conflict, follow this priority order:

1. `AGENTS.md`
2. `docs/01-product-requirements.md`
3. `docs/02-mvp-scope.md`
4. `docs/03-user-stories.md`
5. `docs/04-user-flows-and-state-machine.md`
6. `docs/05-page-specs.md`
7. `docs/06-data-model.md`
8. `docs/07-api-contract.openapi.yaml`
9. `docs/08-ios-architecture.md`
10. `docs/09-accessibility-and-voice-guidelines.md`
11. `docs/10-ai-coding-tasks.md`
12. `openspec/changes/remove-local-backend-use-cloud-only/`
13. Legacy Flutter code can be used only as UI or behavior reference. It is not a source of truth.

If legacy Flutter code, old documents, and the current docs/OpenSpec conflict, follow the current docs/OpenSpec and this file.

## 2. Frozen MVP Direction

The current frozen direction is:

- iOS only. Do not build Android.
- Native Swift iOS.
- SwiftUI first, with UIKit bridging only when needed.
- iOS 16+.
- SwiftUI + MVVM.
- The backend is an external cloud service outside this repository.
- Every real HTTP request uses `http://47.114.113.171`.
- Every real WebSocket connection uses `ws://47.114.113.171`.
- REST API + WebSocket provide real-time notifications.
- JWT Bearer Auth.
- Phone login with fixed verification code `000000`.
- Do not integrate real SMS.
- Use 高德地图 (AMap) and real location.
- TTS uses `AVSpeechSynthesizer`.
- STT uses iOS `Speech` framework.
- OpenSpec first, one small PR per module.
- The target is a demonstrable MVP within 3 days, not a production-complete system.

## 3. MVP Priority

Priority order:

1. Blind runner booking -> volunteer accept -> complete order
2. Phone login + JWT
3. 高德地图 + location
4. VoiceOver accessibility optimization
5. TTS voice announcements
6. Voice input
7. Points shop placeholder
8. Star rating

Priority string: `CABFDEGH`

## 4. Hard Scope Rules

Do not add these non-MVP features:

- Android
- Flutter as the current implementation stack
- Full administrator backend
- Real SMS service
- Real identity verification
- Real administrator review backend
- Real-time track sharing
- Automatic phone calls
- Automatic SMS
- AI assistant
- Complex natural-language time parsing
- Route navigation
- Full points shop
- Payment
- Inventory
- In-app chat
- Virtual phone numbers
- Complex risk control
- Fall detection
- Geofencing
- Instant call
- Multi-person activity signup

If an agent believes any item above is needed, it must write `需要人工确认` with the reason and must not implement it directly.

## 5. Roles and Login Rules

- The first version has only two in-app roles:
  - `BLIND`
  - `VOLUNTEER`
- Do not build a separate administrator app role.
- Two-step phone login: POST `/api/auth/send-code` then POST `/api/auth/verify-code`.
- First login with a phone number automatically creates the account.
- During the demo phase, every phone number uses fixed verification code `000000`.
- Successful login returns a JWT `token` (LoginResponse: token, userId, role).
- One account may have both blind runner and volunteer identities.
- Use POST `/api/user/role` to switch the current role (returns a new token).
- If the user has an order in `PENDING_ACCEPT`, `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, or `IN_PROGRESS`, role switching is blocked.
- First login may return no `role`; the app should route to role selection.

## 6. Order State Machine

Order status may use only:

- `PENDING_MATCH`
- `PENDING_ACCEPT`
- `IN_PROGRESS`
- `DRIVER_EN_ROUTE`
- `DRIVER_ARRIVED`
- `COMPLETED`
- `CANCELLED`
- `REMATCHING`
- `NO_VOLUNTEER`

Forbidden order statuses:

- `submitted`
- `contacted`
- `expired`
- `matching` (use `PENDING_MATCH`)
- `accepted` (use `PENDING_ACCEPT`)
- `arrived` (use `DRIVER_ARRIVED`)
- `emergency` (emergency is now a separate event via POST `/api/emergency/trigger`)

Normal flow:

```text
PENDING_MATCH -> PENDING_ACCEPT -> DRIVER_EN_ROUTE -> DRIVER_ARRIVED -> IN_PROGRESS -> COMPLETED
```

Cancellation flow:

```text
PENDING_MATCH / PENDING_ACCEPT / IN_PROGRESS -> CANCELLED
```

Cancellation rules:

- Cancellation is allowed in `PENDING_MATCH`, `PENDING_ACCEPT`, or `IN_PROGRESS`.
- Cancel endpoint: POST `/api/orders/{orderId}/cancel` (no request body needed).

Emergency flow:

```text
DRIVER_EN_ROUTE / DRIVER_ARRIVED / IN_PROGRESS -> (emergency event recorded)
```

- Emergency is a separate event system via POST `/api/emergency/trigger` with `EmergencyTriggerRequest(orderId, gpsLat, gpsLng)`.
- The order status itself is not changed to "emergency"; an emergency event is recorded alongside the order.

Service flow (volunteer actions):

- Volunteer accepts: POST `/api/orders/{id}/accept` -> status becomes `PENDING_ACCEPT`.
- Volunteer en route: POST `/api/orders/{id}/en-route` -> status becomes `DRIVER_EN_ROUTE`.
- Volunteer arrives: POST `/api/orders/{id}/arrived` -> status becomes `DRIVER_ARRIVED`.
- Service starts (no separate blind runner confirm step in MVP).
- Volunteer finishes: POST `/api/orders/{id}/finish` -> status becomes `COMPLETED`.

Service completion:

- Volunteer taps "结束服务".
- Volunteer may optionally enter a service summary.
- Order enters `COMPLETED`.
- Blind runner may optionally submit a star rating.

Concurrent accept:

- Only orders with `status = PENDING_MATCH` can be accepted.
- The first volunteer who successfully updates the order to `PENDING_ACCEPT` gets the order.
- Later accept requests return `ORDER_ALREADY_ACCEPTED`.

Booking time constraint:

- A booking must be scheduled at least 30 minutes after the current time.
- Creating a booking with a start time less than 30 minutes away must return `APPOINTMENT_TOO_SOON`.

Terminal state rules:

- `COMPLETED`, `CANCELLED`, and `NO_VOLUNTEER` are terminal for MVP.
- `IN_PROGRESS` can be cancelled or enter `COMPLETED`.

## 7. External API Contract Rules

External API rules for the iOS client:

- Do not add or maintain backend implementation code in this repository.
- `docs/07-api-contract.openapi.yaml` is the canonical HTTP API contract.
- `docs/websocket-protocol.md` is the canonical WebSocket contract.
- The only real HTTP base URL is `http://47.114.113.171`.
- The only real WebSocket origin is `ws://47.114.113.171`.
- Do not add configurable, local, staging, or placeholder real-server addresses.
- REST API + WebSocket for real-time notifications.
- Swagger / OpenAPI is required.
- Use JWT Bearer Auth.
- MVP order lists use paginated responses (PagedOrderResponse).
- Blind runner order detail polls every 5 seconds as WebSocket fallback.
- Use a unified error response structure.
- Order status transition endpoints use `POST /api/orders/{orderId}/{action}`.
- WebSocket endpoints: `/ws/blind?token={jwt}` and `/ws/volunteer?token={jwt}`.
- WebSocket is used for real-time dispatch (NEW_ORDER), status change notifications, and location updates.
- REST polling remains as fallback when WebSocket is disconnected.

External API domains consumed by iOS:

- `auth`
- `user`
- `profile`
- `order`
- `location`
- `safety`
- `volunteer`

Required error codes:

- `INVALID_VERIFICATION_CODE`
- `PROFILE_INCOMPLETE`
- `LOCATION_PERMISSION_REQUIRED`
- `ORDER_NOT_FOUND`
- `ORDER_ALREADY_ACCEPTED`
- `INVALID_ORDER_STATUS`
- `ACTIVE_ORDER_ROLE_SWITCH_BLOCKED`
- `VOLUNTEER_NOT_AVAILABLE`
- `VOLUNTEER_NOT_APPROVED`
- `APPOINTMENT_TOO_SOON`

## 8. iOS Rules

iOS rules:

- Native Swift.
- SwiftUI + MVVM.
- iOS 16+.
- Use `URLSession`.
- Centralize network requests in `APIClient`.
- Centralize token, `currentUser`, and `activeRole` in `AppState`.
- MVP token may be temporarily stored in `UserDefaults`, but code must comment that production must migrate to Keychain.
- Development supports Mock / Demo Cloud switching; Demo and Production builds are locked to Demo Cloud.
- Mock is an in-process frontend test facility and must not perform network requests.
- All non-Mock clients use `http://47.114.113.171`; the address is not configurable.
- Views only handle rendering and interaction. Do not pile business logic into Views.
- ViewModels own state and API calls.
- 高德地图 keys may only come from local config files. Do not hardcode keys. Do not commit real keys.
- Provide an example config file that documents required keys.

iOS modules:

- `Core`
- `Auth`
- `Role`
- `BlindRunner`
- `Volunteer`
- `Orders`
- `Map`
- `Voice`
- `Safety`
- `Profile`
- `WebSocket`

## 9. AMap and Location Rules

Map and location rules:

- Use 高德地图.
- Display the map.
- Display current location.
- Display order location marker.
- iOS calculates the distance from volunteer to order start point.
- Volunteer order list sorts by distance.
- MVP does not do route navigation.
- MVP does not do real-time track sharing.
- Blind runner booking defaults to current location as the start point.
- User may manually add a text location description.
- If the user denies location permission:
  - Blind runner cannot create a booking.
  - Volunteer can still browse the order list, but distance values are hidden and distance-based sorting is unavailable. Accepting orders is also blocked.
  - The app shows guidance to enable location permission in Settings.
- Support Xcode simulated location.
- Support in-app default test coordinate fallback for demos.

## 10. Accessibility and Voice Rules

Accessibility rules:

- Blind runner flows must support VoiceOver.
- Key buttons, inputs, and status text must have `accessibilityLabel` / `accessibilityHint`.
- Key blind runner primary buttons must be at least 64pt high.
- Every key blind runner page must include a "重复当前状态" button.
- TTS uses `AVSpeechSynthesizer`.
- STT uses iOS `Speech` framework.
- Voice input is only for text fields such as location description, route notes, remarks, and summaries.
- If speech recognition fails, show an error and allow keyboard input.
- Time selection still uses `DatePicker`.
- Do not build complex natural-language time parsing.
- Do not build a global AI assistant.
- Dangerous actions must require second confirmation:
  - Cancel order
  - Enter emergency state
  - Complete service
  - Logout

TTS must cover:

- Entering blind runner home
- Order submitted successfully
- Matching
- Volunteer accepted
- Volunteer arrived
- Service started
- Service completed
- Enter emergency state
- Error prompts

## 11. Volunteer Rules

Volunteer rules:

- After volunteer Mock certification, `verificationStatus = approved`.
- In MVP, `adminReviewStatus = approved` is also automatic.
- Do not build real identity verification.
- Do not build a real administrator review backend.
- New volunteers default to `isAvailable = false`. The user must manually toggle availability on the volunteer home page to start accepting orders.
- When `isAvailable = false`, the volunteer may still view orders but cannot accept orders.
- Turning off availability does not affect the current order. It only prevents accepting new orders.
- Before accept, hide blind runner contact information, emergency contact, and sensitive health information.
- After accept, show the blind runner's full phone number.
- Do not build in-app chat.
- Do not build virtual phone numbers.

## 12. Safety Rules

Safety rules:

- Blind runners must provide emergency contact name and phone number.
- Emergency contacts are stored only. Do not notify them for real.
- Do not send SMS.
- Do not automatically call.
- Do not push real administrator notifications.
- Show one-tap emergency for orders in `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, or `IN_PROGRESS`.
- Emergency action must require second confirmation.
- After confirmation, the backend records an emergency event and keeps the order status unchanged.
- Emergency is not an order status, so there is no order-state restoration operation.

Emergency confirmation copy must be exactly:

```text
是否确认进入求助状态？确认后，本次服务将标记为异常，系统会记录当前订单状态。
```

## 13. Coding Workflow

All agents must follow this workflow:

1. Read `AGENTS.md` first.
2. Then read related docs and OpenSpec.
3. Implement only one module at a time.
4. Do not rewrite the whole project at once.
5. Use one small PR per module.
6. Confirm the corresponding spec before implementation.
7. Update necessary documentation after implementation.
8. Run tests after implementation.
9. After implementation, output the changed file list, test results, and unfinished items.
10. Do not silently expand scope.

## 14. Review Checklist

After completing each module, check:

- Does it comply with `docs/01-10`?
- Does it comply with OpenSpec?
- Does it violate any `AGENTS.md` forbidden item?
- Does it use the correct order statuses?
- Does it introduce Flutter as current implementation?
- Does it introduce Android?
- Does it introduce WebSocket?
- Does it introduce real SMS or real identity verification?
- Does it hardcode a 高德地图 key?
- Does it pile business logic into SwiftUI Views?
- Does it include accessibility labels/hints?
- Do dangerous actions require second confirmation?
- Do client models and ViewModels cover API responses and order-state behavior with tests?
- Does `openspec validate` pass?

## 15. Required Validation Commands

Recommended OpenSpec validation:

```bash
openspec validate <change-id> --strict --no-interactive
```

For the current MVP change:

```bash
openspec validate remove-local-backend-use-cloud-only --strict --no-interactive
```

iOS build validation:

```bash
xcodebuild -workspace blindRun.xcworkspace -scheme blindRun -destination 'generic/platform=iOS Simulator' build
```

If iOS tests exist:

```bash
xcodebuild test -workspace blindRun.xcworkspace -scheme blindRun -destination 'platform=iOS Simulator,name=iPhone 15'
```

## 16. Legacy Flutter Reference Rule

Legacy Flutter may be used only for:

- UI behavior reference
- Page flow reference
- Field reference
- AMap configuration lessons
- Bug lessons

Legacy Flutter must not be used for:

- Direct code migration
- Continuing Flutter architecture
- Overriding the native Swift direction
- Overriding OpenSpec
- Overriding `docs/01-10`

## 17. Output Requirements

After each agent task, output:

1. Created/modified file list.
2. Summary of the main `AGENTS.md` sections if this file changed.
3. Whether any docs/OpenSpec conflict with `AGENTS.md` was found.
4. Issues needing human confirmation.
5. Confirmation that no business code was started when the task is documentation-only.
