# AGENTS.md

Project-level rules for all AI coding agents working on AidRun / 助盲跑.

Do not treat this file as product brainstorming. It is the highest-priority working contract for agents in this repository.

**Repository boundary:** This is the AidRun native iOS frontend code repository. It does not contain, maintain, build, or deploy backend code. The backend is an external service, and the current real integration endpoint is `http://47.114.113.171`. Agents must not add server source code, database configuration, server build scripts, or a locally runnable backend to this repository unless the repository boundary is explicitly changed by the project owner in a separate change.

## 1. Project Source of Truth

When sources conflict, follow this priority order:

1. `AGENTS.md`
2. `plan.md`
3. `docs/01-product-requirements.md`
4. `docs/02-mvp-scope.md`
5. `docs/03-user-stories.md`
6. `docs/04-user-flows-and-state-machine.md`
7. `docs/05-page-specs.md`
8. `docs/06-data-model.md`
9. `docs/08-ios-architecture.md`
10. `docs/09-accessibility-and-voice-guidelines.md`
11. `docs/10-ai-coding-tasks.md`
12. OpenSpec changes under `openspec/changes/`
13. Legacy Flutter code can be used only as UI or behavior reference. It is not a source of truth.

The API contract is no longer maintained in this repository. Since 2026-07-28 the single source is the backend repository (`/Users/mac/Downloads/demo`): `docs/api_spec.yaml` for REST and `docs/websocket-protocol.md` for WebSocket. See section 7 and `docs/07-api-contract-MOVED.md`. The former local files are archived as `docs/_archive-*.bak` and contain known errors; do not read or copy them.

If legacy Flutter code, old documents, and the current docs/OpenSpec conflict, follow the current docs/OpenSpec and this file.

## 2. Production Direction

The current direction is a production-ready iOS client backed by the external cloud service:

- iOS native app only in this repository.
- Swift, SwiftUI first, UIKit bridging only when needed.
- iOS 16+.
- SwiftUI + MVVM.
- The backend is an external cloud service outside this repository.
- Every real HTTP request currently uses `http://47.114.113.171`.
- Every real WebSocket connection currently uses `ws://47.114.113.171`.
- REST API + WebSocket provide notifications, dispatch, status updates, and location reporting.
- JWT Bearer Auth.
- Phone login uses `POST /api/auth/send-code` and `POST /api/auth/verify-code`; long-lived test accounts may continue to use fixed verification code `000000` for release validation.
- Use 高德地图 (AMap) and real device location.
- TTS uses `AVSpeechSynthesizer`.
- STT uses iOS `Speech` framework.
- Mock remains an offline frontend test facility and is never sufficient for release sign-off.
- Release validation must run on the real devices named `111` and `iPad Pro (2)`.

The old MVP forbidden list has been removed. Features such as production SMS, identity verification, administrator tooling, route navigation, payments, and richer safety capabilities are no longer globally forbidden. They must still be introduced through explicit requirements, API contracts, implementation plans, and acceptance tests before code is added.

## 3. Release Priority

Priority order for the current iOS release:

1. Blind runner booking -> volunteer accept -> complete order against the real backend
2. Phone login + JWT
3. 高德地图 + real location on device
4. VoiceOver accessibility optimization
5. TTS voice announcements
6. Voice input
7. Volunteer availability, dispatch, and WebSocket behavior
8. Safety/emergency backend contract; the current release hides the in-app emergency entry until a dedicated safety change enables it
9. Star rating and points display
10. Production hardening items in `plan.md`

## 4. Scope Change Rules

- Implement one coherent module at a time.
- Do not silently expand scope.
- Do not rewrite the whole project at once.
- New production capabilities must have docs, API contract impact, test plan, and release risk recorded.
- Backend-owned capabilities are validated from iOS and scripts in this repository; backend implementation belongs outside this repository.
- If a requested capability requires backend changes, write `需要人工确认` with the missing API/behavior and keep the iOS implementation behind a clear contract.

## 5. Roles and Login Rules

- Current in-app roles:
  - `BLIND`
  - `VOLUNTEER`
- Do not build a separate administrator app role inside the iOS app unless a new product requirement adds it.
- Two-step phone login: POST `/api/auth/send-code` then POST `/api/auth/verify-code`.
- First login with a phone number automatically creates the account.
- Current test login uses fixed verification code `000000`.
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

Forbidden legacy order vocabulary:

- `submitted`
- `contacted`
- `expired`
- `matching` (use `PENDING_MATCH`)
- `accepted` (use `PENDING_ACCEPT`)
- `arrived` (use `DRIVER_ARRIVED`)
- `emergency` (emergency is a separate event via POST `/api/emergency/trigger`)

Normal flow:

```text
PENDING_MATCH -> PENDING_ACCEPT -> DRIVER_EN_ROUTE -> DRIVER_ARRIVED -> IN_PROGRESS -> COMPLETED
```

Cancellation flow:

```text
PENDING_MATCH / PENDING_ACCEPT -> CANCELLED (blind runner token)
PENDING_ACCEPT / DRIVER_EN_ROUTE / DRIVER_ARRIVED / IN_PROGRESS -> REMATCHING (volunteer token)
REMATCHING -> CANCELLED (blind runner token only)
```

Emergency flow:

```text
DRIVER_EN_ROUTE / DRIVER_ARRIVED / IN_PROGRESS -> (no in-app emergency entry in the current release)
```

- Cancellation endpoint: POST `/api/orders/{orderId}/cancel` (no request body needed).
- Blind runners may cancel only `PENDING_MATCH`, `PENDING_ACCEPT`, and `REMATCHING`; they must not be shown a cancel action in `IN_PROGRESS`.
- Volunteers may cancel active non-terminal accepted service states `PENDING_ACCEPT`, `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, and `IN_PROGRESS`; `PENDING_MATCH`, `REMATCHING`, and terminal states are not volunteer-cancellable.
- `REMATCHING` is entered after an accepted volunteer cancels; the blind runner may then cancel the rematching order with their own token. A volunteer token must not be used for this cancellation because that volunteer is no longer a participant in the order.
- Emergency endpoint contract: POST `/api/emergency/trigger` with `EmergencyTriggerRequest(orderId, gpsLat, gpsLng)`.
- The current iOS release must not show the emergency entry or imply a rescue workflow has been triggered.
- Backend contract probes may call `/api/emergency/trigger`, but iOS UI enablement requires a later safety change covering GPS submission, notification, failure copy, compliance language, and acceptance tests.
- Emergency is not an order status; if the endpoint is used in a later safety change, the order lifecycle status remains unchanged.
- Volunteer responds with accept: POST `/api/orders/{id}/respond` with `OrderRespondRequest(action = ACCEPT)`.
- Volunteer responds with decline: POST `/api/orders/{id}/respond` with `OrderRespondRequest(action = DECLINE)`.
- Volunteer en route: POST `/api/orders/{id}/en-route`.
- Volunteer arrives: POST `/api/orders/{id}/arrived`.
- Volunteer starts service: POST `/api/orders/{id}/start-service`.
- Volunteer finishes: POST `/api/orders/{id}/finish`.
- Creating a booking with a start time less than 30 minutes away must return `APPOINTMENT_TOO_SOON`.

## 7. External API Contract Rules

- Do not add or maintain backend implementation code in this repository.
- The canonical HTTP API contract is `docs/api_spec.yaml` in the backend repository (`/Users/mac/Downloads/demo`), not a file in this repository.
- The canonical WebSocket contract is `docs/websocket-protocol.md` in the same backend repository.
- Mount it with `claude --add-dir /Users/mac/Downloads/demo` when contract work is needed. When the contract document itself is wrong, fix it in the backend repository; never keep a second copy here. Questions that need a backend decision go in `demo/docs/handoff.md` under 「待后端确认」.
- The archived local copies `docs/_archive-*.bak` have known errors and must not be read or copied.
- The current real HTTP base URL is `http://47.114.113.171`.
- The current real WebSocket origin is `ws://47.114.113.171`.
- Do not add local or placeholder real-server addresses.
- REST API + WebSocket for real-time notifications.
- Use JWT Bearer Auth.
- Order lists use paginated responses (PagedOrderResponse).
- Blind runner order detail polls every 5 seconds as WebSocket fallback.
- Use a unified error response structure.
- Order status transition endpoints use `POST /api/orders/{orderId}/{action}`.
- WebSocket endpoints: `/ws/blind?token={jwt}` and `/ws/volunteer?token={jwt}`.
- REST polling remains as fallback when WebSocket is disconnected.

Required error codes:

- `INVALID_VERIFICATION_CODE`
- `PROFILE_INCOMPLETE`（历史条目；后端 `ErrorCode.java` 里没有这个码，真实后端永不返回。下单缺前置项现由下面两个专用 403 承担）
- `IDENTITY_NOT_VERIFIED`（403，`POST /api/orders`；排在 `EMERGENCY_CONTACT_REQUIRED` 之前）
- `EMERGENCY_CONTACT_REQUIRED`（403，`POST /api/orders`；取代此前复用的通用 `ORDER_PERMISSION_DENIED`）
- `LOCATION_PERMISSION_REQUIRED`
- `ORDER_NOT_FOUND`
- `ORDER_ALREADY_ACCEPTED`
- `INVALID_ORDER_STATUS`
- `ACTIVE_ORDER_ROLE_SWITCH_BLOCKED`
- `VOLUNTEER_NOT_AVAILABLE`
- `VOLUNTEER_NOT_APPROVED`
- `APPOINTMENT_TOO_SOON`

## 8. iOS Rules

- Native Swift.
- SwiftUI + MVVM.
- iOS 16+.
- Use `URLSession`.
- Centralize network requests in `APIClient`.
- Centralize token, `currentUser`, and `activeRole` in `AppState`.
- Token is stored in the Keychain (`blindRun/Core/KeychainTokenStore.swift`, `kSecAttrAccessibleAfterFirstUnlock` so background escort can read it while locked). Do not write the access token to `UserDefaults`; the only remaining `UserDefaults` access is the one-time migration of a legacy value in `restoreSession()`.
- Development supports Mock / Demo Cloud switching; Demo and Production builds are locked to Demo Cloud.
- Mock is an in-process frontend test facility and must not perform network requests.
- All non-Mock clients use `http://47.114.113.171`; the address is not configurable in the app.
- Views only handle rendering and interaction. ViewModels own state and API calls.
- 高德地图 keys may only come from local config files. Do not hardcode keys. Do not commit real keys.
- Provide an example config file that documents required keys.

## 9. AMap, Location, Accessibility, and Voice

- Use 高德地图.
- Display the map, current location, and order markers.
- iOS calculates distance from volunteer to order start point.
- Volunteer order list sorts by distance.
- Volunteer dispatch depends on the volunteer's latest WebSocket `LOCATION_UPDATE`.
- Public track sharing and in-app route navigation remain roadmap items. The approved `enable-live-escort-location-and-track-summary` change permits order-participant-only live peer markers, five-second service location reporting, `IN_PROGRESS` background capture, and a completed blind-track summary.
- Blind runner booking defaults to current location as the start point.
- `CLLocationManager` device samples are WGS-84 and must be converted exactly once to GCJ-02 at the centralized backend boundary. All documented inbound order, REST fallback, WebSocket peer, and track coordinates are treated as GCJ-02.
- During an owned `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, or `IN_PROGRESS` session, both roles report the latest valid real location every 5 seconds; Mock/demo coordinates must never be uploaded to the cloud.
- Enhanced background location is allowed only during `IN_PROGRESS`, must be disclosed, and must stop immediately when the order/session becomes ineligible.
- Completed summaries use the blind-runner track as “本次路线”. Volunteer track data must not produce an abnormality conclusion until a versioned assessment policy is approved.
- If location permission is denied, block booking and block volunteer accept while showing Settings guidance.
- Blind runner flows must support VoiceOver.
- Key buttons, inputs, and status text must have `accessibilityLabel` / `accessibilityHint`.
- Key blind runner primary buttons must be at least 64pt high.
- Every key blind runner page must include a "重复当前状态" button.
- Dangerous actions must require second confirmation: cancel order, complete service, logout, and any future re-enabled emergency action.
- TTS must cover entering blind runner home, order submission, matching, volunteer accepted, volunteer arrived, service started, service completed, and error prompts. Future re-enabled emergency action must also have TTS coverage.

## 10. Volunteer and Safety Rules

- New volunteers default to `isAvailable = false`.
- The user must manually toggle availability on the volunteer home page to start accepting orders.
- Turning off availability does not affect the current order.
- Before accept, hide blind runner contact information, emergency contact, and sensitive health information.
- After accept, show the blind runner's full phone number.
- Blind runners must store between one and five emergency contacts, with exactly one contact marked primary. This is a hard booking prerequisite: `POST /api/orders` must be blocked until it is satisfied, because the backend's own `OrderCreationService` precondition is "the blind user has at least one emergency contact".
- Each contact carries name and phone number; relationship is optional. The backend returns the phone in plain text for the owning user (`EmergencyContactResponse.phone`, v1.5.0); masking for display is the iOS client's responsibility.
- Deleting the last remaining emergency contact is rejected by the backend and must also be blocked in the UI.
- Blind-runner real-name verification (`POST /api/blind/verify-identity`, `BlindProfileResponse.verifyStatus` with `NOT_VERIFIED` / `VERIFIED` / `FAILED`) is **guidance only in the current release**. It must be surfaced and spoken, but it must not block booking: `OrderCreationService` never reads `verifyStatus`, so a client-only block would be a false gate that any non-iOS caller bypasses. There is no pending/under-review state. If `demo/docs/handoff.md` Q1 (2026-07-29) is answered with a server-side `verifyStatus == VERIFIED` check, this becomes a hard gate and the returned error code is mapped then.
- The current release hides the emergency action in both blind-runner and volunteer UI.
- Backend `ESCORT_DISTANCE_ALERT` and `ESCORT_SIGNAL_LOST` notifications are high-priority informational safety warnings only. They do not mutate order status, enable emergency UI, or prove that rescue was dispatched.
- If emergency action is re-enabled in a later safety change, it must require second confirmation.
- If the backend emergency endpoint is used in a later safety change, it records an emergency event and keeps the order status unchanged.
- Real SMS, identity verification, and administrator review are backend-owned production capabilities now represented in the backend repository's `docs/api_spec.yaml`; iOS may consume those contracts without adding backend code to this repository.

Future emergency confirmation copy, if the action is re-enabled, must be exactly:

```text
是否确认进入求助状态？确认后，本次服务将标记为异常，系统会记录当前订单状态。
```

## 11. Coding Workflow

All agents must follow this workflow:

1. Read `AGENTS.md` first.
2. Then read related docs and OpenSpec.
3. Implement only one coherent module at a time.
4. Confirm the corresponding spec before implementation when behavior changes.
5. Update necessary documentation after implementation.
6. Run tests after implementation.
7. After implementation, output the changed file list, test results, docs/OpenSpec conflicts, and unfinished items.

## 12. Review Checklist

After completing each module, check:

- Does it comply with `AGENTS.md`, `plan.md`, and `docs/01-10`?
- Does it comply with OpenSpec?
- Does it use the correct order statuses?
- Does it introduce backend code into the iOS repository?
- Does it introduce Flutter as current implementation?
- Does it hardcode a 高德地图 key?
- Does it pile business logic into SwiftUI Views?
- Does it include accessibility labels/hints?
- Do dangerous actions require second confirmation?
- Do client models and ViewModels cover API responses and order-state behavior with tests?
- Does real-device validation on `111` and `iPad Pro (2)` cover any changed real integration path?
- Does `openspec validate` pass?

## 13. Required Validation Commands

Recommended OpenSpec validation:

```bash
openspec validate <change-id> --strict --no-interactive
```

For the current cloud-only change:

```bash
openspec validate remove-local-backend-use-cloud-only --strict --no-interactive
```

Maintained docs validation:

```bash
node scripts/validate-docs.mjs
```

Real-device iOS baseline validation:

```bash
xcodebuild test -workspace blindRun.xcworkspace -scheme blindRun -destination 'platform=iOS,name=111'
xcodebuild test -workspace blindRun.xcworkspace -scheme blindRun -destination 'platform=iOS,name=iPad Pro (2)'
```

Production-readiness validation:

```bash
AIDRUN_DEVICE_NAME=111 AIDRUN_RUN_REAL_AMAP=1 AIDRUN_RUN_CLOUD_UI=1 AIDRUN_RUN_CLOUD_E2E=1 scripts/production-readiness-check.sh
scripts/dual-device-validation.sh
```

## 14. Legacy Flutter Reference Rule

Legacy Flutter may be used only for UI behavior reference, page flow reference, field reference, AMap configuration lessons, and bug lessons.

Legacy Flutter must not be used for direct code migration, continuing Flutter architecture, overriding the native Swift direction, overriding OpenSpec, or overriding `docs/01-10`.

## 15. Output Requirements

After each agent task, output:

1. Created/modified file list.
2. Summary of the main `AGENTS.md` sections if this file changed.
3. Whether any docs/OpenSpec conflict with `AGENTS.md` was found.
4. Issues needing human confirmation.
5. Confirmation that no business code was started when the task is documentation-only.
