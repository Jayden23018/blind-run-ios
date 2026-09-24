## 1. Map

- [x] 1.1 `AMapContainer`: route styles (outline / pace gradient / highlight), drawn markers (kilometre, start/end, rest, bubble), fit padding
- [x] 1.2 `RunRecordPresentation`: pace fractions and colours, route geometry (dedupe, kilometre points, split segments, start/end merge), text formatting

## 2. Detail page

- [x] 2.1 `VolunteerRunRecordViewModel`: load, GENERATING re-read loop, error/retry
- [x] 2.2 `VolunteerRunRecordView`: map + card (header, distance, 3+3 stats, service row, pace chart with `AXChartDescriptor`, splits with highlight, timeline + SOS line, read-only messages), all §6.4 states
- [x] 2.3 Entry points: records-tab volunteer row, `CompletedTrackSummaryView` link on the three volunteer pages; remove `VolunteerOrderDetailLoader`
- [x] 2.4 Mock record: ~3 km loop, pace samples, splits, a rest stop, full events

## 3. Tests and validation

- [x] 3.1 Unit tests for presentation logic and view model states
- [x] 3.2 Update the volunteer smoke UI test; add a screenshot test (light, dark, largest text)
- [x] 3.3 Real-device run of the covering suites, real pass/fail counts
- [x] 3.4 Append stage-4 decisions to `DECISIONS.md`
- [ ] 3.5 Archive only after `enable-live-escort-location-and-track-summary` is archived (leave this box open until then)
