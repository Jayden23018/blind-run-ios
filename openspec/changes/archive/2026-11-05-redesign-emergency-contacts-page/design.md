## Context

Reference: Apple Health › Medical ID › Emergency Contacts, on the owner's iPhone (iOS 27). Screenshots stay in the local design archive `~/Documents/aidrun-design-archive/2026-11-05-emergency-contacts/` because they show the owner's real Medical ID. They are not in the repository.

## Decisions

- **Picker from the list, not from the form.** `ContactPhonePicker` is attached to the "从通讯录添加" row. A pick sets the edit target to `.picked(ContactPhonePick)` and the form opens filled in. Apple's flow has the same order: pick first, then relationship.
- **Keep `List` with `.insetGrouped`.** It is the native look of Medical ID and Contacts, and it keeps Dynamic Type and VoiceOver behaviour that the audits already pass.
- **Monogram avatar is decoration.** It is hidden from VoiceOver. Its colour is the secondary grouped fill, so it does not add a new accent colour (design-direction §5).
- **Relationship presets are client-only.** The backend field is free text (max length unchanged). Presets: 家人、父母、配偶、子女、兄弟姐妹、朋友、同事、邻居. The mock seed uses "家人", so it is a preset. Any other stored value shows as custom.
- **Accessibility labels and identifiers stay.** The row label format and `emergencyContactPickFromContacts` are unchanged, so existing tests keep their meaning.

## Risks

- The out-of-process picker cannot be driven by XCUITest. The pick-to-form mapping is a pure function with unit tests. The picker presentation is checked by a device screenshot.
