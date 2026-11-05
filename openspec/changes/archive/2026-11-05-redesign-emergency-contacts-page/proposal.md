## Why

The emergency contacts page and its add / edit form were never redesigned (#746). The owner said on 2026-11-05 that the page is ugly and asked for a redesign that follows Apple apps, and that blind users can add a contact straight from Contacts.

The contact picker (`ContactPhonePicker`) already exists, but it sits inside the add form. The user must open the form first and then tap "从通讯录选择". The relationship field is free text, so a blind user must type it.

The same-function reference is Apple Health › Medical ID › Emergency Contacts. Apple's steps (support.apple.com/105072): tap "Add Emergency Contact", tap a contact, then add their relationship.

## What Changes

- The list page uses a grouped layout like Medical ID and Contacts. Each contact row shows a monogram avatar, the name, a primary marker, the relationship and the masked phone.
- The add section has two rows. "从通讯录添加" opens the system contact picker directly. "手动输入" opens an empty form.
- After a pick, the add form opens with the name and phone filled in. The user only chooses the relationship and saves.
- The relationship is chosen from a preset list with a checkmark. A custom value is still possible.
- The form uses labelled rows (label on the left, value on the right).
- No change to: the SMS notice copy, the confirmation alerts, the primary-contact rules, validation, error copy, the 64pt touch target, and the backend contract.

## Capabilities

### New Capabilities
- `emergency-contacts-page`: layout and add flow of the blind runner's emergency contacts page.

### Modified Capabilities
None.

## Impact

- `blindRun/Profile/EmergencyContactsView.swift`, `EmergencyContactFormView.swift`, new `EmergencyContactRelationship.swift` and `EmergencyContactRows.swift`.
- UI test helpers that tap "新增紧急联系人" or type the relationship.
- No API change. No new permission: `CNContactPickerViewController` runs out of process and needs no Contacts permission.
