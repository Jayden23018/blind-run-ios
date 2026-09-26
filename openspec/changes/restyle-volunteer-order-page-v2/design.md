## Context

See proposal.md for motivation. Constraints that shape the approach:

- The repository already has an order-flow design system (`FlowPalette` / `FlowMetrics` / `FlowFonts` / `FlowComponents` / `OrderFlowScaffold`) with light, dark and increased-contrast values; `docs/ui/design-direction.md` §2 forbids a second palette.
- The volunteer order page already exists as `VolunteerOrderFlowPage` driven by the pure factory `VolunteerOrderFlowPresentation.make(order:)` / `make(dispatch:)`. `IN_PROGRESS` uses `VolunteerInServiceView` and is out of scope.
- Hand-written models are the runtime source; `Packages/AidRunAPI` is a drift detector only.
- Backend time strings are zone-less local times, parsed by `String.backendTimestamp`.
- XCTest runs only on a physical device; CI is build-for-testing plus spec validation.

## Goals / Non-Goals

**Goals:** reuse the Flow system and the presentation factory; keep phase derivation a pure function of `(order, now)` so it is unit-testable; make every state previewable from `OrderDetailResponse.preview(...)`.

**Non-Goals:** Live Activity, runner-side ring/TTS/message UI, invite-stage API (SPEC #393), in-app map.

## Decisions

1. **Extend Flow, don't add `ZColor`.** Handoff hex values become new `FlowPalette` tokens with dark variants; existing tokens whose value already matches are reused (`accent`=blue, `cta`=yellow, `helpBackground`/`helpText`). `navy` changes to `#1B2657`. Alternative (verbatim `ZColor`) rejected: light-only and a second source of truth.
2. **New v2 components live in one new file** `FlowV2Components.swift`; `PrimaryButton` (blind side) and `FlowActionButton` stay untouched so the blind side does not move.
3. **Phase is derived, not stored.** `VolunteerOrderPhase.resolve(order:now:)` maps status + `primaryActionUnlockAt` + `earliestEndWaitAt` + `eta.late`. The view re-evaluates it with `TimelineView(.periodic(by: 1))` only while a time boundary is pending; `scenePhase == .active` triggers a detail refetch. Alternative (local timers stored in the view model) rejected: drifts after backgrounding, the backend note explicitly says to refetch.
4. **Open enum for `distanceBucket`**, closed enum for the request-side `QuickMessageCode` (backend note §3.2 / §4).
5. **Help routing** `VolunteerOrderSOSMode.resolve(status:)`: `.inProgress` → existing cloud flow, everything else → local call sheet. Mirrors `BlindHomeSOSMode.resolve` so the rule "never call emergency/trigger outside IN_PROGRESS" has one judge per side.
6. **Rope geometry is data.** `RopeGeometry(state:)` returns avatar x positions, rope endpoints, sag, dash and decorations in the 342×56 coordinate space; `RopeShape` only animates those numbers. Unit tests cover geometry and clamping without rendering.
7. **Direction wording** is a pure function `DirectionSector.describe(relativeDegrees:previous:)` with ±5° hysteresis; the dial uses heading from `CLLocationManager` and the runner location from `BLIND_LOCATION_UPDATE`.
8. **Design-rule exceptions** (hero numbers capped at AX2, looping effects, two-column secondary buttons collapsing at AX sizes) are scoped to the volunteer order page and recorded in `design-direction.md`.

## Risks / Trade-offs

- [`Flow.navy` change touches the blind home] → list call sites in PR 1 and compare previews before/after.
- [Heading unavailable indoors / permission denied] → dial falls back to the `UNKNOWN` look; wording from bucket only.
- [WS and refetch race] → WS merges only `eta` / `meet` into the current order when `orderId` matches; a full refetch always wins.
- [Device-only tests] → keep logic in pure functions so the unit suites are small and fast on device.

## Migration Plan

Four stacked PRs (tokens → rope → data → states). Each is independently revertible; the page keeps the v3 look until PR 4 lands.
