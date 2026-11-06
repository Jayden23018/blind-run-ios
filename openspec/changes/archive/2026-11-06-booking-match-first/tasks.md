## 1. Models

- [x] 1.1 `CreateOrderRequest` gains optional `timeFlexible` and `preferredStartTime`; order / invite responses decode them with missing keys meaning not flexible
- [x] 1.2 `IntroCallPlanRequest` / plan view gain `pacePreference`, `hasGuideDogThisRun`, `specialNotes`

## 2. Blind-runner booking page

- [x] 2.1 Slot model: 7 dates, three slots, lead-time clipping, optional 30-minute start times, default selection
- [x] 2.2 Booking page view per mockup v4 (start point, date row, slots, times, primary action) with VoiceOver labels
- [x] 2.3 Home booking action opens the new page; gates (launch scope, track consent) still wrap it
- [x] 2.4 Waiting-for-match copy shows the window and preferred time

## 3. Volunteer and plan

- [x] 3.1 Invitation copy shows the window and preferred time for time-flexible orders
- [x] 3.2 Meetup plan form: exact start time required on time-flexible orders; pace, guide dog, notes fields
- [x] 3.3 Runner plan review reads pace, guide dog, notes in fixed order with previous values

## 4. Verification

- [x] 4.1 `build-for-testing` compiles (owner 2026-11-05: compile only, no test run)
- [x] 4.2 Spec coverage script passes against backend origin/main after #932 merges
