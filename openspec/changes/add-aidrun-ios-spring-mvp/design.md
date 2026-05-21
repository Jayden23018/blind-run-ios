## Context

AidRun MVP v0.3 is a public-service demo product for blind runners and volunteers. The first version must show a complete appointment-based service loop, not production completeness. The implementation target is Swift native iOS and a Spring Boot backend running locally or on LAN for demo. Existing broader ideas are superseded by this frozen MVP scope.

## Goals / Non-Goals

**Goals:**

- Demonstrate blind runner booking to volunteer completion with real map, real location, phone login, JWT, VoiceOver, TTS, and large-button blind runner UX.
- Use Spring Boot REST APIs, H2 demo database, Swagger/OpenAPI, startup seed data, and no WebSocket.
- Support iOS API environment switching: Mock, Local Backend, and future Production.
- Preserve admin review fields without building a real admin backend.

**Non-Goals:**

- Android, full admin backend, real SMS, real identity verification, real admin review operations, WebSocket, real-time track sharing, route navigation, app chat, AI assistant, instant call, payments, inventory, complex risk control, fall detection, electronic fence, and group activity registration.

## Decisions

- Use a single `User` account with `roles` and `activeRole`; both roles share one JWT. First login may return no `activeRole` until the app role-selection step saves one. The backend blocks role switching when the user has an order in `accepted`, `arrived`, `in_progress`, or `emergency`.
- Merge login and registration. The demo verification code is `123456`; invalid codes return `INVALID_VERIFICATION_CODE`.
- Model one service as one `RunOrder`. Normal lifecycle is `matching -> accepted -> arrived -> in_progress -> completed`.
- Volunteers actively accept orders. The backend only returns `matching` orders; iOS sorts by distance using current volunteer location and order start coordinates.
- Use optimistic or transactional backend status checks so only the first volunteer can update a `matching` order to `accepted`; later attempts return `ORDER_ALREADY_ACCEPTED`.
- Blind runner order status pages poll order details every 5 seconds while waiting or in active service states.
- High-risk actions use confirmation dialogs: cancel, emergency, service completion, and logout.
- Use iOS native `AVSpeechSynthesizer` for TTS and Speech framework for text-field speech input. Do not add a global assistant.
- Store AMap keys in ignored local config and commit only an example config. Provide default demo coordinates to stabilize simulator demos.

## Risks / Trade-offs

- UserDefaults token storage is acceptable only for MVP; a real release must migrate token storage to Keychain.
- H2 and seed data optimize demo speed but require PostgreSQL migration before production use.
- Polling is simpler than WebSocket and fits the MVP, but it is less real-time and may show status changes up to 5 seconds late.
- iOS-side distance sorting avoids backend geo complexity, but available-order distance depends on current location permission and device coordinates.
- Mock certification makes the volunteer flow demonstrable but is not real identity verification.
