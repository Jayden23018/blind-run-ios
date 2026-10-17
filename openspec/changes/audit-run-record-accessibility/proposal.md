## Why

HANDOFF §7 lists nine accessibility acceptance checks for the post-run record. Stages 3–6 built the four screens (records tab on both sides, volunteer detail, runner detail with messages) and each left audit items open. Stage 7 of `~/Downloads/run-record-handoff/DECISIONS.md` walks the nine checks screen by screen and fixes what fails.

The walk found gaps where the screens say less than the prototype's `data-vo`, or where colour carries meaning with nothing else beside it:

- The volunteer detail's navigation title is the masked name ("和陈*一起跑"). VoiceOver reads it as "陈星号".
- The route map is coloured by pace, but no legend says so. The prototype has a "快 ▬ 慢" legend on the map, and its spoken description says "颜色表示配速，蓝色快，黄色慢，第3公里最快". Ours says neither.
- The pace chart's spoken summary leaves out where the runner rested. The prototype includes it ("2.6公里处休息").
- The volunteer's send button does not say who will hear the message. The prototype does.

## What Changes

- Volunteer detail: the navigation title is read without mask markers (the screen still shows `陈*`).
- Volunteer detail: the map's spoken description adds what the colours mean and which kilometre was fastest, when there is one.
- Both details: when the route is coloured by pace, the map shows a "快 ▬ 慢" legend. VoiceOver skips the legend (the description already covers it).
- Volunteer detail: the pace chart's spoken summary adds each rest as "X 公里处休息".
- Volunteer detail: the send button gets the hint "X在这条跑步记录里可以听到这句话", the same sentence as the stage-6 confirmation.
- Records tab: find out why the Dynamic Type audit flags the "未完成的预约" rows. Fix it if it is real. If it is a false positive, write that down and leave it. No allow-list, no capped text sizes.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `volunteer-run-record-detail`: new requirements for the pace legend and for spoken text carrying the prototype's information.
- `runner-run-record-detail`: new requirement for the pace legend on the map.
  ⚠️ Both capabilities are still unarchived deltas. **Archive after `add-volunteer-run-record-detail`, `add-runner-run-record-detail` and `add-run-record-messages`.**

## Impact

- iOS UI: `Volunteer/VolunteerRunRecordView.swift` (title, map description, chart summary, send hint, legend in `RunRecordRouteMap`), `Shared/RunRecordHistoryView.swift` only if the Dynamic Type finding is real.
- UI tests: `AccessibilityAuditTests` gets sweeps for masked names and `6'15"` style pace on the four screens.
- Backend contract: none.
