## Context

`BlindRunnerProfileView` was one form with a bottom Save bar. Three places push it: the account page, onboarding (to be removed by #781) and the booking hint "去个人资料填写". `BlindRunnerProfileViewModel` builds the whole request (`makeProfileUpdateRequest`) and owns the vision consent rules. The consent rules are pinned by unit tests and must not change.

Mockup: `docs/ui/mockups/blind-profile-edit-20261105/profile-final.png`.

## Goals / Non-Goals

**Goals:**
- One overview page for every entry; one row = one change = one save.
- Keep the consent rules, identifiers and spoken labels. The request body changes in two places only: empty `name` is left out, and "无偏好" is sent as `NO_PREFERENCE`.

**Non-Goals:**
- No change to the emergency contacts page, button components (#749) or the privacy page (#754).
- No new endpoint. The empty-`name` rule needs backend#926.

## Decisions

1. **One mode, no parameter.** The first plan had a `.form` mode for onboarding and booking. The owner then approved #781 (no profile gate after login), so that mode was dropped and every entry pushes `BlindRunnerProfileView()`.
2. **Save-and-revert lives in the view model.** New `saveChange(savedLabel:requiresNickname:revert:) async -> Bool`. The caller writes the new value into the view model first, then calls it. It runs the same validation as `submit()`. On failure it calls `revert` and reports the error. `saveProfile` returns success and takes the saved text, so the `submit()` path (privacy page retry) keeps "资料已保存。".
3. **The choice page binds to the view model field.** A generic `BlindProfileChoicePage` takes a `Binding`, the choices and a footnote. It keeps no copy of the value, so the overview row and the check mark always show the same value. Rows are disabled while a save runs, so two requests cannot race.
4. **The text edit page keeps a local draft.** The profile field changes only when Save is pressed. On failure the field goes back to the old value, and the draft stays on screen.
5. **Identifiers move to the overview rows.** `blindProfileTetherPreferencePicker`, `blindProfileVisionLevelPicker` and `blindProfileGuideDogMenu` go on the overview rows, with the current value as `accessibilityValue`. Existing tests that measure the row height and read the value keep working. The emergency-contact row keeps the label "管理紧急联系人" and puts the summary in the value.
6. **Withdrawal retry text.** The overview has no Save button, so `withdrawalRetryButtonTitle` is the withdraw row title, the same way the privacy page does it.
7. **Nickname may be empty.** An empty nickname is left out of the request (backend#926). A non-empty one must be 2–50 UTF-16 units, the backend `@Size`. The nickname edit page also rejects empty.
8. **No false "已保存".** A key left out of the request keeps the server value. So "无偏好" is sent as `NO_PREFERENCE` (left out only when the stored value is unreadable and untouched), and the vision page has no "不填" choice; clearing vision uses the withdraw row.
9. **Withdraw retry row.** After a failed withdrawal the two rows are hidden, but the withdraw row stays and calls `submit()`, so the error text "再点一次「撤回这两项的同意」" points at a row that exists.

## Risks / Trade-offs

- A declined vision consent is only sent with the next save of any row. This is the old rule ("本次明确拒绝" is sent on the next save); it is not a new leak.
- The overview shows the server state only. If a save fails and the revert runs, the user hears the error and sees the old value. There is no silent unsaved state.
