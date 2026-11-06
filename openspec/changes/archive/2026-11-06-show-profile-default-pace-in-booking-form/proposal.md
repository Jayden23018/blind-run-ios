## Why

Issue #797. The blind runner sets a default pace in the profile (`BlindProfileResponse.defaultPace`).
The booking form ignores it: the pace picker always starts at "无偏好", and the review step says nothing about pace.
The order is still correct, because the backend falls back to the profile default when the request carries no pace (`api_spec.yaml`: "下单时不传即回落档案默认配速").
But the runner cannot hear which pace will be used, so they pick it again or assume none applies.

Copying the default into `pacePreference` is not the fix.
The review step and its spoken summary read `pacePreference`, so a copied value sounds like a value the runner chose for this run.
The repository already clears voice-filled slots on "重说" for this exact reason.

## What Changes

- When the profile has a default pace and the runner has not picked one, the form shows that default with its source.
  - The picker's unset option is titled "资料里的默认：轻松" instead of "无偏好".
  - The review list and its spoken summary include "配速偏好：轻松，资料里的默认".
- The create-order request does not change: an unset pace still sends no `pacePreference`, so the backend fallback stays the single source of the effective value.
- The voice read-back does not change. It still names only values extracted from the utterance.

## Impact

- `blindRun/BlindRunner/BlindBookingViewModel+Summaries.swift`: profile default pace, picker titles, review item.
- `blindRun/BlindRunner/BlindBookingView+StepSections.swift`: picker uses the new titles.
- Test `blindRunTests/BlindBookingTests.swift`.
- No contract change.
