## 1. Code

- [x] 1.1 "Add favourite place" opens its own page, not the booking form (already true since #807; checked)
- [x] 1.2 Delete `BlindBookingView` and its extensions; move the shared model types to `BlindBookingModels.swift`
- [x] 1.3 Remove view model members used only by the form; keep the voice wizard slots and the logic still required by the booking page
- [x] 1.4 Rename the route `.voiceBooking` to `.booking`
- [x] 1.5 Keep the voice wizard, service, models, tests and the corpus gates

## 2. Tests

- [x] 2.1 Delete unit and UI tests that only covered the form; adapt the ones that cover behaviour that stays

## 3. Verification

- [x] 3.1 `build-for-testing` compiles (owner 2026-11-05: compile only, no test run)
