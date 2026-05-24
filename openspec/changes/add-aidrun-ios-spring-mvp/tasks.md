## 1. Backend Foundation and Auth

- [x] 1.1 Create Spring Boot project with Spring Web, validation, security/JWT, H2, and springdoc OpenAPI.
- [x] 1.2 Add H2 demo configuration, Swagger/OpenAPI exposure, and startup seed data.
- [ ] 1.3 Implement phone login / auto-registration with fixed verification code `123456`.
- [ ] 1.4 Protect all non-auth endpoints with JWT Bearer Auth.

## 2. User, Profile, and Role PR

- [ ] 2.1 Implement current user endpoint with user, blind runner profile, and volunteer profile.
- [ ] 2.2 Implement blind runner profile create/update with required emergency contact.
- [ ] 2.3 Implement volunteer profile create/update, Mock certification approve, and availability switch.
- [ ] 2.4 Implement active-role switching with active-order blocking.

## 3. Order Lifecycle PR

- [ ] 3.1 Implement appointment creation with profile, location, and 30-minute appointment guards.
- [ ] 3.2 Implement my orders, order detail, and available matching orders without pagination.
- [ ] 3.3 Implement accept, arrive, blind runner confirm-start, volunteer complete, cancel, emergency, and rating endpoints.
- [ ] 3.4 Add transactional protection for concurrent accept and scheduled no-volunteer cancellation.

## 4. Volunteer Records and Points PR

- [ ] 4.1 Award +100 points when a volunteer completes a service.
- [ ] 4.2 Implement volunteer service records.
- [ ] 4.3 Implement points balance, ledger, and placeholder shop items without exchange, inventory, or payment.

## 5. iOS Core and Auth PR

- [ ] 5.1 Create SwiftUI module groups: Core, Auth, Role, BlindRunner, Volunteer, Orders, Map, Voice, Safety, Profile.
- [ ] 5.2 Implement `APIClient` protocol, URLSession client, Mock client, DTOs, error mapping, and environment switch.
- [ ] 5.3 Implement phone login, UserDefaults token storage for MVP, session restore, logout confirmation, and later Keychain migration note.
- [ ] 5.4 Implement active-role switch UI and blocked-role-switch error handling.

## 6. iOS Blind Runner PR

- [x] 6.1 Implement blind runner profile form with nickname and emergency contact.
- [ ] 6.2 Implement blind runner home, booking form, DatePicker appointment selection, optional route fields, and location-required guard.
- [ ] 6.3 Implement order status screen with 5-second polling, repeat-status button, cancel, emergency, confirm-start, completion display, and optional rating.

## 7. iOS Volunteer PR

- [x] 7.1 Implement volunteer profile, Mock certification page, and availability switch.
- [ ] 7.2 Implement nearby available orders list with iOS-side distance sorting.
- [ ] 7.3 Implement volunteer order detail actions: accept, arrived, complete with optional summary, cancel, and emergency.
- [ ] 7.4 Implement service records, points balance, ledger, and placeholder shop pages.

## 8. iOS Map, Location, Voice, and Accessibility PR

- [ ] 8.1 Integrate 高德地图 with ignored local key config and committed example config.
- [ ] 8.2 Show map, current location, order marker, and demo fallback coordinates.
- [ ] 8.3 Implement TTS for all required state nodes and speech input for text fields.
- [ ] 8.4 Add VoiceOver labels/hints, large blind-runner buttons, high-contrast states, and confirmation dialogs for dangerous actions.

## 9. Demo Verification PR

- [ ] 9.1 Document LAN backend setup for simulator and real-device testing.
- [ ] 9.2 Run the two-device happy path: blind booking, volunteer accept, arrive, blind confirm start, volunteer complete, blind completed status.
- [ ] 9.3 Verify emergency path, cancellation path, location-denied path, and role-switch-blocked path.
- [ ] 9.4 Run `openspec validate add-aidrun-ios-spring-mvp --strict --no-interactive` and ensure no excluded features were added.
