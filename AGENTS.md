# AGENTS.md

Project-level rules for all AI coding agents working on AidRun / 助盲跑 MVP.

Do not treat this file as product brainstorming. It is the highest-priority working contract for agents in this repository.

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
12. `openspec/changes/add-aidrun-ios-spring-mvp/`
13. Legacy Flutter code can be used only as UI or behavior reference. It is not a source of truth.

If legacy Flutter code, old documents, and the current docs/OpenSpec conflict, follow the current docs/OpenSpec and this file.

## 2. Frozen MVP Direction

The current frozen direction is:

- iOS only. Do not build Android.
- Native Swift iOS.
- SwiftUI first, with UIKit bridging only when needed.
- iOS 16+.
- SwiftUI + MVVM.
- Backend uses Spring Boot.
- Demo database uses H2.
- Later database target is PostgreSQL.
- REST API only.
- JWT Bearer Auth.
- Phone login with fixed verification code `123456`.
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
- WebSocket
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
  - `blind_runner`
  - `volunteer`
- Do not build a separate administrator app role.
- First login with a phone number automatically creates the account.
- During the demo phase, every phone number uses fixed verification code `123456`.
- Successful login returns a JWT `accessToken`.
- One account may have both blind runner and volunteer identities.
- Use `activeRole` to switch the current role.
- If the user has an order in `accepted`, `arrived`, `in_progress`, or `emergency`, role switching is blocked.
- First login may return no `activeRole`; the app should route to role selection.

## 6. Order State Machine

Order status may use only:

- `matching`
- `accepted`
- `arrived`
- `in_progress`
- `completed`
- `cancelled`
- `emergency`

Forbidden order statuses:

- `submitted`
- `contacted`
- `expired`

Normal flow:

```text
matching -> accepted -> arrived -> in_progress -> completed
```

Cancellation flow:

```text
matching / accepted / arrived -> cancelled
```

Cancellation rules:

- Cancellation is allowed only in `matching`, `accepted`, or `arrived` before `in_progress`.
- `cancelledBy` must be recorded as `blind_runner` or `volunteer`.
- Cancel reason must use one of these fixed options: 时间不合适, 地点填写错误, 临时有事, 联系不上对方, 其他.

Emergency flow:

```text
accepted / arrived / in_progress -> emergency
```

Service start:

- Volunteer taps "我已到达".
- Order enters `arrived`.
- Blind runner sees "确认开始服务".
- After blind runner confirmation, order enters `in_progress`.

Service completion:

- Volunteer taps "结束服务".
- Volunteer may optionally enter a service summary.
- Order enters `completed`.
- Volunteer earns +100 points.
- Blind runner may optionally submit a star rating.

Concurrent accept:

- Only orders with `status = matching` can be accepted.
- The first volunteer who successfully updates the order to `accepted` gets the order.
- Later accept requests return `ORDER_ALREADY_ACCEPTED`.

Booking time constraint:

- A booking must be scheduled at least 30 minutes after the current time.
- Creating a booking with a start time less than 30 minutes away must return `APPOINTMENT_TOO_SOON`.

Terminal state rules:

- `completed`, `cancelled`, and `emergency` are terminal for MVP.
- MVP does not restore an order from `emergency` to a previous state.
- `in_progress` cannot be ordinarily cancelled; it can only enter `emergency` or `completed`.

## 7. Backend Rules

Backend rules:

- Use Spring Boot.
- Use H2 for demo.
- PostgreSQL later.
- REST only.
- No WebSocket.
- Swagger / OpenAPI is required.
- Use JWT Bearer Auth.
- Seed test data is required.
- Seed data must include at least 1 blind runner with complete profile and emergency contact, 1 approved and available volunteer, several `matching` orders, and completed records for demo history/points.
- MVP order lists are not paginated.
- Blind runner order detail polls every 5 seconds.
- Use a unified error response structure.
- Order status transition endpoints use `POST /api/orders/{orderId}/{action}`.

Backend modules:

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
- Support Mock / Local Backend / Production Backend environment switching.
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
- Ask blind runner to confirm service start
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
- Show one-tap emergency for orders in `accepted`, `arrived`, or `in_progress`.
- Emergency action must require second confirmation.
- After confirmation, the order enters `emergency`.
- MVP does not support restoring from `emergency` to the previous state.

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
- Do backend state transitions have tests?
- Does `openspec validate` pass?

## 15. Required Validation Commands

Recommended OpenSpec validation:

```bash
openspec validate <change-id> --strict --no-interactive
```

For the current MVP change:

```bash
openspec validate add-aidrun-ios-spring-mvp --strict --no-interactive
```

Backend validation:

```bash
./gradlew test
```

Or, if the backend uses Maven:

```bash
./mvnw test
```

iOS build validation:

```bash
xcodebuild -scheme <AppScheme> -destination 'platform=iOS Simulator,name=iPhone 15' build
```

If iOS tests exist:

```bash
xcodebuild test -scheme <AppScheme> -destination 'platform=iOS Simulator,name=iPhone 15'
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
