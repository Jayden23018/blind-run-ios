## Context

Decisions in force: `~/Downloads/run-record-handoff/DECISIONS.md` D8 (palette), D9 (merge plan), D11 (64pt targets), D15 voided (tests scoped to the change). Project owner answers in this session (2026-09-24):

- Thumbnail: pure SwiftUI `Path`, not an AMap snapshot. AMap has no stand-alone snapshotter; both snapshot APIs need a displayed `MAMapView` (`docs/research/amap-snapshot-for-list-thumbnail-20260924.md`).
- Older months: month switcher, one month on screen at a time.
- PR is stacked on PR #189 (still open).

## Goals / Non-Goals

**Goals:** first production caller of `monthlyRecords`; both roles share one list structure; every state covered.

**Non-Goals:** new detail pages (stages 4–5), messages (stage 6), full section-7 accessibility walk (stage 7).

## Decisions

### One shared view, role-specific copy
HANDOFF 6.1 says both roles share the structure, and `docs/ui/design-direction.md` §5.2 says the ends differ only in density, hierarchy, and tone — no forked components. One `RunRecordHistoryViewModel` + `RunRecordHistoryView(role:)`; role changes copy, row density (runner: larger text, no thumbnail) and destinations.

### Two sources, loaded together
`monthlyRecords(year:month:)` for completed runs and `orders.myOrders()` for the unfinished group run concurrently. Either failing sets one error message with a retry; whatever did load stays on screen. Switching month reloads only the monthly part.

### Empty copy
- Month empty but the user has completed runs elsewhere → "X月没有跑步记录 / 陪跑记录" and the month switcher.
- No completed order at all in `/api/orders/mine` and the month is empty → HANDOFF 6.4 first-run copy: runner "完成第一次陪跑后，记录会出现在这里", volunteer "完成第一次陪跑后，记录会出现在这里。开启可服务状态后，系统会自动派单。" (keeps the existing volunteer hint).
- ponytail: `/api/orders/mine` is one page, so "never ran" is judged on that page.

### Null handling
`distanceM` nil → no distance text in the row and no "一共 X 公里" clause; `serviceMin` nil → no service clause; `partnerName` / `place` nil → that fragment is dropped from both the visible text and the spoken label. Nothing renders `0`.

### Names
Partner names arrive masked (`张*`). Visible text keeps the mask; accessibility labels use `unmaskedForSpeech` (VoiceOver must not read "星号").

### Thumbnail
Normalise the points into a square with a cosine-latitude correction on longitude, flip Y, keep aspect ratio. One point draws a dot; nil or empty draws the empty tile so rows stay aligned. Stroke `AppColors.paceFast`. The tile is `accessibilityHidden` — the row label already says everything.

### Palette (D8)
Measured with the WCAG formula (numbers pinned in `LowVisionChannelTests`):

| colour | light | dark | role | light on white | dark on #1C1C1E |
|---|---|---|---|---|---|
| tactileYellow | F7BE00 | F7BE00 | background under black text | black text 12.32:1 | same |
| ropeOrange | FF6A13 | FF6A13 | graphics / icon background | 2.87 ❌ | 5.93 |
| paceFast | 3558F0 | 5B7CFA | route stroke | 5.52 | 4.63 (3558F0 was 3.08) |
| paceMid | 19B3A6 | 19B3A6 | route gradient | 2.61 ❌ | 6.51 |
| paceSlow | F5B100 | F5B100 | route gradient | 1.88 ❌ | 9.05 |

Only `paceFast` needed a dark variant. The D8 light values of orange / mid / slow are below the 3:1 non-text threshold on white; they are the owner's values and are not changed here. Stage 4 draws them on a map with a white casing — the casing, not the page background, is what they must be judged against there.

### Month switcher layout
Full-width stacked rows under the summary, not two side-by-side buttons (`design-direction.md` §4: secondary actions stacked, never side by side). Each row ≥ 64pt (D11).

## Risks / Trade-offs

- The unfinished group is not month-filtered and only covers page one of `/api/orders/mine` — same limit as before this change.
- Mock groups by `createdAt` (it has no `finishedAt`), so month boundaries in Mock are approximate.
