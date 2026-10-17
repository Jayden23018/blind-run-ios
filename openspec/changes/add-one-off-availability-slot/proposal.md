## Why

Backend #564 (issue blind-run-backend#410 / #566) lets a volunteer's availability carry an optional `date`, meaning "free only on this one day". iOS PR #357 (#353) only preserved such slots when it reads and re-saves them. A volunteer still cannot create one from the app. The project owner decided on 2026-10-17 that the availability page must offer it (iOS #455).

## What Changes

- The availability page ("我的 › 空闲时间") gets a second add entry, 「按日期添加」, next to the existing weekly 「添加空闲时间」.
- That entry opens the same slot editor. A date picker replaces the weekday picker. The picker lists today plus the next days of a fixed window, and never a past day.
- The weekday sent to the backend comes from the chosen date. The volunteer cannot edit it. The request shape is `{"dayOfWeek":"SATURDAY","date":"2026-10-03","startTime":"07:00:00","endTime":"09:00:00"}`.
- A new one-off slot is saved through the existing whole-profile `PUT /api/volunteer/profile`. All existing weekly and one-off slots go back unchanged.
- The list row and the dispatch-home summary use the #357 wording: 「仅 10月3日（周六）」 and 「10月3日早」.
- No "not free on this day" exception. A one-off slot only widens availability.

## Capabilities

### New Capabilities
- `volunteer-availability-schedule`: How the volunteer edits their weekly and one-off free time slots, and what the app sends to the backend for them.

### Modified Capabilities

## Impact

- Code: `blindRun/Volunteer/VolunteerAvailabilityScheduleView.swift` (entry, editor, date helpers). `ProfileModels.swift` is not expected to change.
- API: no contract change. Uses the existing optional `VolunteerAvailableTimeSlot.date` (backend `origin/main` `docs/api_spec.yaml`).
- Tests: `blindRunTests/VolunteerAvailabilityScheduleSaveTests.swift`, `blindRunUITests/AccessibilityAuditTests.swift`.
