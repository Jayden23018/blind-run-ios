# volunteer-live-activity Specification

## Purpose
陪跑员锁屏实时活动：出发 / 汇合卡（推送优先、本地兜底）与陪跑员端跑步卡 v2，让陪跑员不解锁手机也能看到还有几分钟到、跑者在不在附近、跑了多远。
## Requirements
### Requirement: Departure card starts when the volunteer departs
The app SHALL start a `GuideRunAttributes` Live Activity when the volunteer's order enters `DRIVER_EN_ROUTE`, SHALL update it in place when the order enters `DRIVER_ARRIVED`, and SHALL end it immediately when the order leaves those two states. It SHALL coexist with the running card and SHALL NOT be merged into it.

#### Scenario: Pressing "我出发了"
- **WHEN** `POST /api/orders/{id}/en-route` succeeds and the order becomes `DRIVER_EN_ROUTE`
- **THEN** a departure card SHALL appear on the lock screen with the departed colour

#### Scenario: Run starts
- **WHEN** the order becomes `IN_PROGRESS`
- **THEN** the departure / meeting card SHALL end immediately and only the running card SHALL remain

#### Scenario: Unit and UI tests
- **WHEN** the app runs under XCTest or with any `AIDRUN_UI_TEST_*` launch environment
- **THEN** no real Live Activity SHALL be requested

### Requirement: Push token first, local updates as fallback
The app SHALL request the card with `pushType: .token` and upload each token as lowercase hex to `POST /api/devices/live-activity-token`. If the system rejects push-token activities, the app SHALL start the same card with no push type and SHALL update it locally from each new order snapshot while the order page is alive.

#### Scenario: No APNs capability
- **WHEN** `Activity.request(pushType: .token)` throws
- **THEN** the card SHALL still start, without a push token, and no token upload SHALL happen

### Requirement: Push payload decodes with the default decoder
`GuideRunAttributes.ContentState` SHALL decode the backend `content-state` with a default `JSONDecoder`: `arriveAt` as seconds since 2001-01-01, optional fields present as `null` or omitted, and unknown `phase` values falling back to `departed`.

#### Scenario: Backend sample
- **WHEN** the payload has `"arriveAt": 811465020`
- **THEN** the decoded date SHALL be 2026-09-19T06:57:00+08:00

### Requirement: Lock-screen card uses surname only and neutral wording
The card SHALL show the runner only by surname in short labels, SHALL use "跑者" in full sentences, SHALL NOT add "先生" or "女士", and SHALL NOT fall back to the masked name when the surname is unavailable.

#### Scenario: Surname not yet provided by the backend
- **WHEN** the order has `blindName = "李*"` and no surname field
- **THEN** the card SHALL show no name at all

### Requirement: Lock-screen actions on iOS 17
On iOS 17 and later the departed card SHALL offer "我快到了" and "再等我 5 分钟" (quick messages) and the arrived card SHALL offer "让跑者的手机响起来" (ring runner), each performed by a `LiveActivityIntent` in the app process without opening the app. On iOS 16 the card SHALL show no buttons.

#### Scenario: Ring from the lock screen
- **WHEN** the volunteer taps "让跑者的手机响起来" on the arrived card
- **THEN** the app SHALL call `POST /api/orders/{id}/ring-runner` with the stored login token

### Requirement: Volunteer running card v2
The volunteer-side running card SHALL use `stateRunning` as background (`statePaused` when paused), show "陪跑中 · {surname or 跑者}：{signal}" as the first line only when the rhythm signal is at most 5 minutes old (otherwise "陪跑中"; "已暂停" when paused), show distance with "/ target 公里", duration · pace, and an 8pt progress bar when a target exists. It SHALL NOT draw a turnaround marker and SHALL NOT contain any button. It SHALL keep updating locally. The runner-side card SHALL be unchanged.

#### Scenario: Stale rhythm signal
- **WHEN** the last rhythm signal is 5 minutes 10 seconds old
- **THEN** the first line SHALL read "陪跑中"

#### Scenario: Fresh rhythm signal
- **WHEN** the last rhythm signal is "OK" and 4 minutes 50 seconds old
- **THEN** the first line SHALL read "陪跑中 · 李：刚刚好" when the surname is 李

