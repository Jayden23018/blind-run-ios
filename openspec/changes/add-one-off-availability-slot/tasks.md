## 1. Date helpers and model

- [ ] 1.1 Add pure helpers: weekday for a `yyyy-MM-dd` date, and the list of selectable dates from today (30 days, named constant)
- [ ] 1.2 Draft slot: one-off default factory, a setter that changes date and weekday together, payload derives `dayOfWeek` from `date`

## 2. UI

- [ ] 2.1 Add 「按日期添加」 entry (≥ 64pt, hint, identifier) on the availability page
- [ ] 2.2 Editor: date picker for a new one-off slot (≥ 64pt, identifier); keep the read-only date row when editing an existing one

## 3. Tests

- [ ] 3.1 Unit tests: request body `dayOfWeek` matches `date`; no past dates selectable (incl. month/year rollover); adding keeps existing slots intact on save
- [ ] 3.2 Red check: break each guarded behavior on a committed baseline and see the matching test fail
- [ ] 3.3 UI test: entry opens the editor with a date picker, cancel adds nothing, done adds a 「仅 …」 row
- [ ] 3.4 Run the covering suites on the device; `passed=0` counts as failure
