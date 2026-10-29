## ADDED Requirements

### Requirement: Invite APNs lock-screen actions
The app SHALL register the `INVITE` category with `ACCEPT_INVITE` and `DECLINE_INVITE`, and the `INVITE_INTRO_CALL` category with only `DECLINE_INVITE`. Both actions SHALL require authentication and SHALL bring the app to the foreground. The app SHALL reply only to the matching invite (same `inviteId`, otherwise same `expiresAt`) that is still awaiting a reply in the current account's queue, through the same call as the invite card's button.

#### Scenario: Accept from the lock screen
- **WHEN** the volunteer taps "接下这次陪跑" on an invite notification
- **THEN** after the invite is in the in-app queue the app SHALL open that invite card and respond through the same call as the card's accept button
- **AND** when the next pending-invites snapshot does not contain the invite, the app SHALL say "这个邀请已失效，不需要再回复了"

#### Scenario: Decline from the lock screen
- **WHEN** the volunteer taps "这次去不了" on an invite notification and the invite is in the queue
- **THEN** the app SHALL decline it through the card's decline call, with the same 5-second undo

#### Scenario: Notification for an older invite of the same order
- **WHEN** the queue holds a newer invite for the same order with a different `expiresAt`
- **THEN** the lock-screen action SHALL NOT reply to the newer invite

#### Scenario: Stale notifications are removed
- **WHEN** an invite is withdrawn, replied to in the app, or missing from a snapshot it predates
- **THEN** the delivered notifications for that invite SHALL be removed, and those of a newer invite for the same order SHALL stay

#### Scenario: New invite APNs while the app is in the foreground
- **WHEN** a `NEW_ORDER` APNs arrives while the app is in the foreground
- **THEN** the system banner SHALL NOT be shown and nothing SHALL be spoken for it
- **AND** the app SHALL reconcile the pending-invites list so the invite appears once in the app

### Requirement: Consecutive declines follow the backend count
The availability prompt SHALL use `consecutiveDeclineCount` from `GET /api/volunteer/pending-invites`. The client SHALL remember the count at which it last asked and SHALL ask again only after the count rises by 3 more; when the backend count drops below that value, the remembered value SHALL reset.

#### Scenario: Asking again
- **WHEN** the prompt was shown at count 3 and the backend later reports 5
- **THEN** the prompt SHALL NOT be shown
- **AND** when the backend reports 6 the prompt SHALL be shown
