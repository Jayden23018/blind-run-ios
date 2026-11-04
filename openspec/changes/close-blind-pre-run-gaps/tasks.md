## 1. Records and rating

- [ ] 1.1 B-5: add「待进行的预约」section and its announcement; ask `/api/orders/mine` for 50 per page
- [ ] 1.2 B-30: rating starts unselected; refuse submit with a spoken reason

## 2. Spoken cues

- [ ] 2.1 B-26: waiting status every 3 minutes on the order page, lowest tier
- [ ] 2.2 F-16: low battery warning once per order
- [ ] 2.3 F-14: start-place privacy line on the form and once in the voice readback

## 3. Reminders

- [ ] 3.1 B-18: local start reminder 1 hour before, rebuilt on home active-order change
- [ ] 3.2 B-18: 「加入日历」on iOS 17+ through EKEventEditViewController

## 4. Verification

- [ ] 4.1 Unit tests for the pure logic; device run of the changed test methods
- [ ] 4.2 B-13: record the VoiceOver device check in the PR handoff
