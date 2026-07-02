# AidRun iOS Architecture

本文档定义“助盲跑 / AidRun”iOS 上线版客户端工程架构。若存在旧文档，以 `AGENTS.md` 和 `plan.md` 为准：Swift 原生 iOS、SwiftUI + MVVM、真实地图、真实定位、手机号登录 + JWT、无障碍与语音优先。

## 1. Platform

- Language: Swift
- UI: SwiftUI first, UIKit bridge only when needed for 高德地图 SDK or system APIs
- Minimum OS: iOS 16+
- Architecture: SwiftUI + MVVM
- Networking: `URLSession`
- Token storage: currently `UserDefaults`; production hardening should migrate to Keychain
- Map: 高德地图 iOS SDK
- Location: CoreLocation + 高德地图定位能力 as needed
- Voice: `AVSpeechSynthesizer`
- Speech input: iOS Speech framework

## 2. Module Layout

Suggested source groups:

- `Core`: App environment, dependency container, shared models, app state
- `Auth`: phone login, JWT persistence, auth session
- `Role`: active role switch and role guard rules
- `BlindRunner`: blind runner home, profile, booking, order status
- `Volunteer`: volunteer home dispatch workbench, availability, WebSocket dispatch prompts, active orders, service records, points
- `Orders`: order DTOs, order state machine helpers, polling
- `Map`: AMap bridge, current location, markers, distance calculation, external map app navigation launchers
- `Voice`: TTS, repeat current status, speech input helpers
- `Safety`: emergency confirmation and cancellation confirmation flows
- `Profile`: blind runner and volunteer profile forms

## 3. MVVM Pattern

Views should remain thin:

- SwiftUI `View` renders state and forwards user intent.
- `ViewModel` owns loading state, validation state, API calls, polling, and TTS triggers.
- `Service` objects wrap API and platform capability boundaries.
- DTOs mirror OpenAPI schemas; domain helpers handle display text and state transitions.

Recommended examples:

- `AuthViewModel`: phone and code login.
- `BlindBookingViewModel`: location permission, default start coordinate, booking form validation, create order.
- `BlindOrderStatusViewModel`: WebSocket status events, 5-second polling fallback, status TTS, cancel, completed/rating UI, emergency placeholder.
- `VolunteerHomeViewModel`: availability, current location, dispatch summary, readiness reasons, temporary points, active/recent orders, WebSocket dispatch.
- `VolunteerOrderDetailViewModel`: WebSocket location pre-report before accept, respond accept/decline, en-route, arrived, strict IN_PROGRESS finish gate, cancel, emergency placeholder.
- `VolunteerInServiceViewModel`: active order polling, en-route/arrived/finish actions, strict IN_PROGRESS finish gate, service-completion refresh.

## 4. API Environment Switch

Development keeps Mock for deterministic UI/XCTest coverage. Every networked run uses the single external cloud service. Mock is not release evidence.

| Environment | Purpose |
| --- | --- |
| `mock` | Local fake data for UI and flow debugging |
| `demoCloud` | Current demo cloud backend at `http://47.114.113.171` |

| Build channel | Scheme / configuration | Allowed environment | Environment UI |
| --- | --- | --- | --- |
| Development | `blindRun-Dev` / `Debug` | `mock`, `demoCloud` | Visible |
| Demo | `blindRun-Demo` / `DemoRelease` | `demoCloud` only | Hidden |
| Production | `blindRun-Prod` / `Release` | `demoCloud` only | Hidden |

Implementation guidance:

- Define `APIEnvironment` with `baseURL` and display name.
- Use one `APIClient` protocol so Mock and real implementations share call sites.
- In Debug development builds, expose a small environment selector in settings or launch configuration.
- Unknown persisted environment values are ignored and the build channel default is used.
- Every build uses the shared Info plist with an ATS exception scoped to `47.114.113.171`.
- Do not add a configurable alternative real-server URL without an explicit environment strategy change.
- Use WebSocket for cloud dispatch, status notifications, and location updates; retain REST polling as the disconnected fallback.

## 5. APIClient

`APIClient` responsibilities:

- Build `URLRequest` with method, path, query, JSON body.
- Attach `Authorization: Bearer <accessToken>` for protected endpoints.
- Decode success DTOs and error envelopes.
- Map backend error codes to user-facing messages and TTS error prompts.
- Keep retry behavior simple; complex offline queues require a separate reliability design.

Token persistence:

- Current implementation reads/writes access token from `UserDefaults`.
- Store only the JWT and minimal active environment setting.
- Add code comments and docs noting Keychain migration before real user release.

## 6. Auth and Role State

Login:

- Phone login and registration are merged.
- Demo verification code is always `000000`.
- On success, backend returns JWT access token and current user; first login may have no `activeRole`, so the app routes to role selection.

Role switching:

- A single JWT is shared across roles.
- Switching only changes `activeRole`.
- If backend returns `ACTIVE_ORDER_ROLE_SWITCH_BLOCKED`, show and speak a clear explanation.

## 7. Map and Location

Current requirements:

- Show real map.
- Show current location.
- Show order start marker.
- Calculate volunteer-to-start distance on iOS.

Location permission:

- Booking and accepting system dispatches require location permission.
- If denied, blind runner cannot create booking.
- If denied, volunteer cannot receive or accept system dispatches that depend on latest location.
- Show permission guidance, and use TTS for blind runner error prompts.

Demo fallback:

- Keep default test coordinates in app code or debug config so simulator demos do not fail completely.
- Fallback is for demo stability only; UI must still explain real location permission is required.

AMap keys:

- Store real keys in local config such as `LocalConfig.xcconfig` or local plist.
- Add local config to `.gitignore`.
- Commit an example config file that lists required key names but contains no secrets.

## 8. Polling

Blind runner order status pages must poll order details every 5 seconds while status is:

- `PENDING_MATCH`
- `PENDING_ACCEPT`
- `DRIVER_EN_ROUTE`
- `DRIVER_ARRIVED`
- `IN_PROGRESS`

Stop polling when:

- Order reaches `COMPLETED`, `CANCELLED`, or `NO_VOLUNTEER`.
- View disappears.
- User logs out.

## 9. Accessibility and Voice Integration

- Blind runner pages use large, simple controls with primary button height at least 64pt.
- Every key button, input, and status text needs `accessibilityLabel` and `accessibilityHint`.
- Main flow nodes call TTS through a shared `SpeechService`.
- Every key blind runner page has a “重复当前状态” button.
- Dangerous actions require confirmation: cancel order, emergency, complete service, logout.
- Emergency controls are placeholder-only for this change; production emergency recording must be re-enabled by a dedicated safety change.

## 10. Demo Acceptance Flow

The iOS app must support a two-device demo:

1. Blind runner logs in and completes profile.
2. Blind runner creates booking with current location and appointment at least 30 minutes later.
3. Volunteer logs in, completes identity verification and administrator review, then turns availability on.
4. Volunteer sees available order sorted by distance and accepts it.
5. Blind runner polling shows `PENDING_ACCEPT`.
6. Volunteer marks `DRIVER_EN_ROUTE`, then `DRIVER_ARRIVED`.
7. Cloud status reaches `IN_PROGRESS`.
8. Volunteer completes service with optional summary; iOS must not call `/api/orders/{id}/finish` before `IN_PROGRESS`.
9. Blind runner sees `COMPLETED` and optional rating UI.

## 11. Roadmap Capabilities

Do not implement Android, real SMS, real identity verification, full admin backend, real-time track sharing, app chat, AI assistant, App 内路线规划, automatic calls, automatic SMS, complex risk control, fall detection, geofencing, instant call, payment, stock, or full points shop. WebSocket is in scope only for cloud contract real-time dispatch, status notifications, and location updates. 志愿者前往出发地点阶段允许通过 URL Scheme / MapKit 跳转外部地图 App 做步行导航，不涉及新增后端 API。
