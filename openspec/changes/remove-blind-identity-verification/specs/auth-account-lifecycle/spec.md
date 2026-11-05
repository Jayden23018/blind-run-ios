## REMOVED Requirements

### Requirement: Sensitive personal information is consented to separately at its collection point
**Reason**: 视障跑者实名认证已取消（#767），原要求里「视障跑者首次提交实名」这个场景没有对象了。

**Migration**: 使用下面新增的「volunteer collection point」要求，志愿者部分的内容不变。

## ADDED Requirements

### Requirement: Sensitive personal information is consented to separately at the volunteer collection point
The app SHALL obtain a separate consent immediately before submitting an ID card number or entering face liveness verification, and SHALL NOT send the request without it (PIPL Art. 29). Accepting the launch disclosure SHALL NOT satisfy this requirement, because a general consent does not cover sensitive categories. Since 2026-11-05 (#767) blind runners have no identity verification, so the volunteer registration is the only ID card collection point.

#### Scenario: Volunteer submits registration step one for the first time
- **WHEN** the user activates submit on the volunteer basic-information step with no recorded consent for that purpose
- **THEN** the disclosure SHALL name both the ID card number and the face liveness check that follows, because the next screen starts it

#### Scenario: The same person submits again
- **WHEN** a user who has already consented for that purpose submits again
- **THEN** the request SHALL be sent without repeating the full disclosure, because a disclosure the user learns to skip stops being a disclosure

#### Scenario: A different account signs in on the same device
- **WHEN** identity verification is submitted under a different user id
- **THEN** the previous account's consent SHALL NOT apply, because consent is given by a person and shared devices are common for blind users

#### Scenario: Disclosure wording changes
- **WHEN** the disclosure text for a purpose is edited
- **THEN** consents recorded against the previous wording SHALL NOT be treated as consent to the new wording
