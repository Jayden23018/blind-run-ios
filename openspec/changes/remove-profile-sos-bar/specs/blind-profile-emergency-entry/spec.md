## ADDED Requirements

### Requirement: No persistent emergency bar on the profile tab
The blind runner's profile tab SHALL NOT show a persistent emergency bar on any page.

#### Scenario: Save stays reachable on the profile page
- **WHEN** the runner opens the profile page from the profile tab
- **THEN** the Save button does not overlap any emergency control and a tap on it does not open the dial sheet

### Requirement: Emergency row in the profile list
The profile list SHALL show one emergency row, and its mode SHALL come from `BlindHomeSOSMode.resolve`.

#### Scenario: No active run
- **WHEN** the mode is `localCall` or `localCallSessionExpired`
- **THEN** the row is titled 紧急呼叫 and opens the local dial sheet without calling any emergency endpoint

#### Scenario: Active run
- **WHEN** the mode is `cloudTrigger`
- **THEN** the row is titled 求助与安全 and opens the safety hub on the order page

### Requirement: Magic Tap during an active run
Magic Tap SHALL take the runner to the order page during an active run, because cloud SOS results only show there.

#### Scenario: Gesture from another tab
- **WHEN** the mode is `cloudTrigger` and the runner performs Magic Tap on a tab
- **THEN** the order page opens and shows the locked confirmation text

#### Scenario: Order not loaded yet
- **WHEN** the order page has not loaded the order at the moment the request arrives
- **THEN** the safety hub opens instead of a confirmation that would do nothing
