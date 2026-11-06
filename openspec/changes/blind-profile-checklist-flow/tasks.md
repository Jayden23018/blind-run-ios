## 1. Phrases

- [ ] 1.1 Add `BlindProfilePhrases.swift`: phrase lists, join, read-back, length check
- [ ] 1.2 Add `BlindProfilePhrasesTests` (round trip, unknown text kept, exclusive option, length limits, empty text)

## 2. Cards and flow

- [ ] 2.1 Add `BlindProfileChecklistCards.swift`: five cards, titles, status lines, set / not set
- [ ] 2.2 Add `BlindProfileQuestionFlow.swift`: consent, single, multi and supplement screens; focus on question; disabled hint; discard alert
- [ ] 2.3 Add `saveCard` and decline-and-save to `BlindRunnerProfileViewModel`
- [ ] 2.4 Replace the profile page body with the checklist; focus the saved card

## 3. Clean-up and tests

- [ ] 3.1 Remove `BlindProfileChoicePage.swift` and unused components; keep the nickname edit page
- [ ] 3.2 Update UI and audit tests to the new identifiers
- [ ] 3.3 `build-for-testing` passes; spec coverage passes

## 4. Close

- [ ] 4.1 Replace the draft with the final image; set the INDEX row to Current
- [ ] 4.2 Archive this change
