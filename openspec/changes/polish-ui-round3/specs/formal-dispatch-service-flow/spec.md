## ADDED Requirements

### Requirement: Runner completion page has one filled button
On the runner's completed order page, the bottom 「完成」 button SHALL be the only filled button. The review section's 「提交评价」 and the post-review 「返回首页」 SHALL be outlined secondary buttons that keep the full width and the 64pt minimum height.

#### Scenario: Runner reaches the completed page
- **WHEN** the order is `COMPLETED` and the review has not been submitted
- **THEN** 「提交评价」 SHALL be outlined and 「完成」 SHALL remain the single filled button
