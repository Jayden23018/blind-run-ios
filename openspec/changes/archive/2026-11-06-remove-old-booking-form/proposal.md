## Why

The project owner decided on 2026-11-06 to delete the old four-step booking form and the voice booking screen, and keep only the slot-based booking page (Jayden23018/blind-run-ios#806, #810). The voice booking logic stays: the owner may add a voice screen back later. Some current requirements still describe the deleted form: its steps, its pace picker, and how a rejection moves the form back to a step.

## What Changes

- Delete the old booking form and voice booking screen (`BlindBookingView` and its extensions) and the view model members only they used: step navigation, the auxiliary map, place search, the appointment fine-adjusters and the zero-input line.
- Keep `VoiceOrderWizard`, `VoiceOrderService`, the voice models, their tests and the corpus gates.
- Keep the view model logic that current requirements still ask the booking page for (precise-location notice and temporary request, low-accuracy check, launch-scope notices, privacy reminder). The slot page does not show them yet; that gap is tracked in Jayden23018/blind-run-ios#813.
- Rename the home route `.voiceBooking` to `.booking`.
- Requirement text: drop the form-only wording (steps, picker, return-to-step). Behaviour that the booking page must still have is unchanged.

## Capabilities

### Modified Capabilities
- `booking-launch-scope`: a launch-scope rejection keeps the runner on the booking page instead of moving a form step.
- `blind-runner-extra-needs`: the profile default pace appears in the review items; the picker title clause is removed.
- `formal-dispatch-service-flow`: the booking gate refers to the booking page instead of the guided form.
- `blind-runner-voice-first-experience`: step-based feedback wording is removed.

## Impact

- iOS only: `blindRun/BlindRunner/`, `blindRunTests/`, `blindRunUITests/`. No API change.
- Tests: owner decision 2026-11-05, compile only (`build-for-testing`).
