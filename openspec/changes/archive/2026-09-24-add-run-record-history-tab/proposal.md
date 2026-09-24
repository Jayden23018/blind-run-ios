## Why

Stage 2 (`add-post-run-record`, PR #189) gave the app a typed monthly history (`RunRecordServing.monthlyRecords`, `GET /api/orders/mine/run-records`) but nothing calls it yet. Both roles' "记录" tab still lists raw orders from `GET /api/orders/mine` without distance, month totals, or a route shape, so a runner cannot tell how far they ran this month and a volunteer cannot recognise a run by its route. Stage 3 of the post-run record plan (`~/Downloads/run-record-handoff/DECISIONS.md` D9) rebuilds that tab on the new data.

## What Changes

- **Both roles' records tab is rebuilt** (D9 merge plan). The top part is the new list read from `RunRecordServing.monthlyRecords` (capability `post-run-record`, requirement "Monthly run history is read per role"): a month summary sentence, one row per completed run with its distance, and — volunteers only — a route thumbnail drawn from the backend's `thumbnail` points.
- One month is shown at a time, with full-width "上个月 / 下个月" rows to switch (project owner, 2026-09-24). "下个月" is not offered for the current month.
- Cancelled and no-volunteer orders keep coming from `GET /api/orders/mine` and move into a bottom group "未完成的预约" (not filtered by month).
- The runner's "已完成的跑步" VoiceOver rotor is kept; its entries now come from the month's completed runs.
- Titles become "跑步记录" (runner) / "陪跑记录" (volunteer). The volunteer profile's "我的服务记录" entry is renamed to match.
- States: loading skeleton read as one element, per-role empty copy, network error with a "重试" button; any `null` field hides its text instead of showing `0`.
- `AppColors` gains the D8 palette (tactile yellow, rope orange, pace fast/mid/slow) with dark variants, contrast-checked.
- DEBUG-only launch setting `AIDRUN_UI_TEST_COLOR_SCHEME` (`light` / `dark`) so UI tests can capture dark-mode screenshots on device.
- Row taps keep going to the existing order detail pages; the new detail pages are stages 4–5.

## Capabilities

### New Capabilities

- `run-record-history`: What each role's records tab shows, where the data comes from, and how every state (loading, empty, error, missing values) is presented.

### Modified Capabilities

None. `post-run-record` is consumed as-is; this change adds the first production caller of its monthly history and does not alter its requirements.

## Impact

- iOS UI: `BlindRunner/BlindRunHistoryView.swift` and `VolunteerServiceRecordsView` (in `Volunteer/VolunteerOrderFlowViews.swift`) are replaced by one shared `Shared/RunRecordHistoryView.swift`; callers in `BlindRunnerTabView`, `VolunteerTabView`, `VolunteerProfileFirstScreenView` updated.
- Design tokens: `Core/DesignSystem/AppColors.swift`.
- Mock: monthly history returns multi-point thumbnails; a UI-test-only seed adds a cancelled order so the bottom group can be screenshotted.
- Backend contract: consumed as-is (`demo/docs/api_spec.yaml` `getMyRunRecords`, `getMyOrders`). No contract change.
- Remaining uncalled service methods (`record`, `postMessage`) stay as they are for stages 4–6.
