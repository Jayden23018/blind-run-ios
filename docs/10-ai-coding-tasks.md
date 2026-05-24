# AidRun MVP v0.3 AI Coding Tasks

本文档把 3 天可演示 MVP 拆成适合 AI / 工程师执行的小任务。任务只覆盖 Swift iOS + Spring Boot 文档冻结范围，不扩展业务代码范围之外的功能。

## 1. Backend Tasks

### PR-BE-01 Spring Boot Skeleton and Swagger

- Create Spring Boot project with H2, Spring Web, validation, security/JWT, and springdoc OpenAPI.
- Add `/swagger-ui` and OpenAPI JSON.
- Add H2 console for local demo only.
- Seed demo users, profiles, orders, and completed records.

Acceptance:

- App starts locally.
- Swagger lists all MVP endpoints.
- Seed data is available after startup.

### PR-BE-02 Auth and User

- Implement `POST /api/auth/phone-login`.
- Accept fixed demo code `123456`.
- Auto-create user on first phone login.
- Return JWT access token and current user.
- Implement `GET /api/users/me`.

Acceptance:

- Invalid code returns `INVALID_VERIFICATION_CODE`.
- Protected endpoints require Bearer JWT.

### PR-BE-03 Profiles and Role Switching

- Implement blind runner profile create/update.
- Implement volunteer profile create/update.
- Implement Mock verification approve.
- Implement availability toggle.
- Implement active role switch guard.

Acceptance:

- Incomplete profile blocks relevant order actions with `PROFILE_INCOMPLETE`.
- Active order blocks role switch with `ACTIVE_ORDER_ROLE_SWITCH_BLOCKED`.

### PR-BE-04 Order Lifecycle

- Implement create booking with appointment at least 30 minutes later.
- Implement my orders and available orders.
- Implement accept with status guard and concurrency protection.
- Implement arrive, confirm start, complete, cancel, emergency, rating.
- Implement no-volunteer cancellation job or startup-safe scheduled check.

Acceptance:

- Happy path runs: `matching -> accepted -> arrived -> in_progress -> completed`.
- Second accept returns `ORDER_ALREADY_ACCEPTED`.
- Invalid transitions return `INVALID_ORDER_STATUS`.

### PR-BE-05 Volunteer Records and Points

- Award +100 points when service completes.
- Implement service records.
- Implement points summary and placeholder shop items.

Acceptance:

- Completed service creates ledger entry.
- Points shop is display-only.

## 2. iOS Core Tasks

### PR-IOS-01 Core App Shell

- Create SwiftUI module groups: Core, Auth, Role, BlindRunner, Volunteer, Orders, Map, Voice, Safety, Profile.
- Add app state, dependency container, environment switch, shared DTOs.
- Add `APIClient` protocol with Mock and URLSession implementations.

Acceptance:

- Mock mode can launch without backend.
- Local Backend mode can point to LAN Spring Boot URL.

### PR-IOS-02 Auth and Role

- Implement phone login UI with fixed code flow.
- Store JWT in UserDefaults for MVP.
- Add logout with confirmation.
- Add active role switch and backend error display.

Acceptance:

- Login persists session.
- Role switch is blocked when backend reports active order.

### PR-IOS-03 Blind Runner Flow

- Implement blind profile form with emergency contact.
- Implement blind home with repeat status button.
- Implement create booking form with location default, DatePicker, optional fields.
- Implement order status polling every 5 seconds.
- Implement confirm start, cancel, emergency, optional rating.

Acceptance:

- Blind runner demo path completes from booking to completed status.
- Required TTS nodes are spoken.

### PR-IOS-04 Volunteer Flow

- Implement volunteer profile and Mock verification page.
- Implement availability switch.
- Implement available orders list sorted by iOS-calculated distance.
- Implement order detail actions: accept, arrived, complete, cancel, emergency.
- Implement service records and points/shop placeholder pages.

Acceptance:

- Unavailable or unapproved volunteer cannot accept.
- Contact phone appears only after accept.

### PR-IOS-05 Map and Location

- Integrate AMap SDK.
- Load key from local config and provide example config.
- Show map, current location, and order marker.
- Handle permission denied states.
- Provide demo fallback coordinates.

Acceptance:

- Simulator and real device can demo map and location.
- Denied permission blocks booking and volunteer distance accepting.

### PR-IOS-06 Voice and Accessibility

- Implement shared TTS service.
- Implement speech input helper for text fields.
- Add VoiceOver labels and hints to key controls.
- Add confirmation dialogs for dangerous actions.
- Verify large button and contrast rules.

Acceptance:

- Happy path works with VoiceOver enabled.
- Error states are visible and spoken.

## 3. Demo and Integration Tasks

### PR-DEMO-01 Two-Device Demo Script

- Document local backend LAN setup.
- Document simulator and real-device configuration.
- Prepare two demo accounts.
- Record the happy path and emergency fallback path.

Acceptance:

- Demo can be run with one blind runner device and one volunteer device.

### PR-DEMO-02 Final Verification

- Run backend tests.
- Run iOS unit/UI smoke tests where practical.
- Validate OpenSpec.
- Verify OpenAPI contract matches implemented endpoints.

Acceptance:

- `openspec validate add-aidrun-ios-spring-mvp --strict --no-interactive` passes.
- No excluded features are introduced.

## 4. Explicit Non-Goals

Do not implement Android, full admin backend, real SMS, real identity verification, real admin review, WebSocket, real-time tracks, auto-call, auto-SMS, AI assistant, natural-language time parsing, route navigation, full points shop, payment, inventory, in-app chat, complex risk control, fall detection, geofencing, instant call, or group activity registration.
