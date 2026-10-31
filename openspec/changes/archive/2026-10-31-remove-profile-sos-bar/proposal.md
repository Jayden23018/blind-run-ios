## Why

The red emergency bar sits on every level of the blind runner's profile tab. It covers the Save button on the profile page by 56 of 64 points, so a tap on Save lands on the emergency call. The project owner decided on 2026-10-30 that no page shows a persistent bar.

## What Changes

- Remove the persistent bar and `BlindHomeSOSBar`.
- Add one emergency row to the profile list.
- During an active run, send the row and the Magic Tap gesture to the order page, because cloud SOS results only show there.
- Keep local dialing on the current page in all other states.

## Capabilities

### New Capabilities

- `blind-profile-emergency-entry`: Defines the blind runner's emergency entry on the profile tab.

### Modified Capabilities

None.

## Impact

- iOS: `BlindRunnerTabView`, `BlindRunnerHomeView`, `BlindOrderStatusView`, `BlindRunnerSettingsView`, `SafetyModule`, help copy.
- Docs: `docs/05-page-specs.md`, `docs/ui/design-direction.md`, skill `aidrun-order-and-sos`.
- Backend and API contract: no change.
