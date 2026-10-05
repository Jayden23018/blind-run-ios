## ADDED Requirements

### Requirement: Disabled send-code button stays readable
The login page's disabled 「获取验证码」 button SHALL render its label with at least 4.5:1 contrast against its background in both light and dark appearance.

#### Scenario: Phone number not yet valid
- **WHEN** the phone number field does not hold a valid number
- **THEN** 「获取验证码」 SHALL be disabled and its label SHALL be `textSecondary` on `systemGray5`
