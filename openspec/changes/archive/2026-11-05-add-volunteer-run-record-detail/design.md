## Context

Data: `RunRecordResponse` (contract `demo/docs/api_spec.yaml` `getRunRecord`). Route, distance, pace, splits, pace samples and stops come from the runner's track; steps, cadence and climb come from the requesting phone (D3). `GENERATING` → re-read in 1–2 s; `INSUFFICIENT_TRACK` and >90-day records have `track == nil`.

Map: AMap 3D SDK 11.1.200 (D2). API facts in `docs/research/amap-gradient-polyline-and-outline-20260924.md`.

## Decisions

- **Outline**: AMap polylines have no border property, so the outline is a second, wider `MAPolyline` underneath. Colour near-black `#1C1C1E` in both appearances (project owner). Contrast of the pace colours against it: fast 3.81 (light value) / 5.71 (dark value), mid 8.04, slow 11.17.
- **Pace colour**: fraction = (pace − p5) / (p95 − p5) over `paceSamples`, clamped to 0…1; 0…0.5 interpolates fast→mid, 0.5…1 mid→slow. Each track point takes the nearest sample by distance. Fractions are quantised to 8 levels and a `drawStyleIndexes` entry is placed only where the level changes (SDK: index points are never simplified, keep them few). Consecutive duplicate points are removed before building the line (SDK requirement).
- **Start/end merge**: when first and last track points are within 50 m, one "起终点" marker.
- **Highlight**: tapping a split adds a wide tactile-yellow band under the pace line for that kilometre (interpolated ends) plus a bubble "第3公里 5'58\"", and scrolls back to the top.
- **Layout**: map pinned behind a `ScrollView` whose first ~55% is a transparent spacer; the spacer carries the map's accessibility description, so the map itself is `isDecorative`. The map fits the route with bottom padding equal to the covered part. No parallax / nav-bar morph (polish, not listed in the task).
- **GENERATING**: `.task` loop re-reads every 2 s until the status changes or the page disappears.
- **Entry scope**: only volunteer entries move to the new page; the runner's link keeps `OrderRouteReplayView` until stage 5, which deletes it.

## Risks

- Map rendering (gradient, outline, markers) is only visible in a build with an AMap key; UI-test builds show the placeholder.
- Archive order: this change's MODIFIED delta targets a capability that only exists once `enable-live-escort-location-and-track-summary` is archived.
