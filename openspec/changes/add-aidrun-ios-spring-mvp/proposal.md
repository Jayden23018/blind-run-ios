## Why

AidRun needs a 3-day demonstrable MVP that replaces earlier broad direction with a frozen Swift native iOS + Spring Boot implementation path. The MVP must prove the public-service order loop for blind runners and volunteers: booking, accepting, arrival, blind runner confirmation, service completion, safety emergency state, real map/location, phone login with JWT, and accessible voice-first blind runner interaction.

## What Changes

- Define the MVP product and engineering contract for SwiftUI iOS, Spring Boot, H2 demo data, REST API, JWT Bearer Auth, Swagger/OpenAPI, 高德地图, real location, TTS, Speech input, and VoiceOver support.
- Add documentation for data models, API contract, iOS architecture, accessibility/voice rules, and AI coding tasks under `docs/`.
- Add OpenSpec capability specs for auth, role switching, booking, volunteer order flow, order lifecycle, AMap/location, accessibility/voice UI, emergency safety, volunteer points, and backend API contract.
- Keep administrator review fields for later expansion while intentionally excluding a full admin backend and real review operations.

## Capabilities

### New Capabilities

- `auth-phone-login`: Phone login with fixed MVP verification code, automatic registration, and JWT access token.
- `role-switching`: Shared-account active role switching with active-order blocking.
- `blind-runner-booking`: Blind runner profile completion and appointment booking.
- `volunteer-order-flow`: Volunteer profile, Mock certification, availability, order list, accept, arrival, and completion flow.
- `order-status-lifecycle`: Order state machine, cancellation, polling, rating, and completion rules.
- `amap-location`: 高德地图 display, real location, markers, distance calculation, and demo fallback coordinates.
- `accessibility-voice-ui`: VoiceOver, TTS, speech input, large-button blind runner UI, and repeat-status behavior.
- `safety-basic-emergency`: Emergency contact requirement and one-tap emergency state.
- `volunteer-points`: Volunteer service records, +100 completion points, and placeholder points shop.
- `backend-api-contract`: Spring Boot REST contract with JWT, H2 demo data, Swagger/OpenAPI, and MVP error codes.

### Modified Capabilities

- None.

## Impact

- Adds documentation-only MVP contract files under `docs/`.
- Adds a new OpenSpec change under `openspec/changes/add-aidrun-ios-spring-mvp/`.
- Does not implement iOS or backend business code in this change.
- Does not add Android, WebSocket, real SMS, real identity verification, full admin backend, real-time tracks, AI assistant, route navigation, instant call, in-app chat, payment, inventory, geofencing, fall detection, or group activity registration.
