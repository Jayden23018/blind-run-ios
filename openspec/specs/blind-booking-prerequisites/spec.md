# blind-booking-prerequisites Specification

## Purpose
TBD - created by archiving change remove-blind-identity-verification. Update Purpose after archive.
## Requirements
### Requirement: 视障跑者下单不需要实名认证
视障跑者下单前 SHALL 只需要满足：填了昵称；至少 1 位紧急联系人且恰好 1 位主联系人；选了出发地点；预约时间有效。App SHALL NOT 因实名状态拦截下单、语音下单或引导流程，也 SHALL NOT 提供视障跑者的实名认证入口。

#### Scenario: 新注册的视障跑者
- **WHEN** 视障跑者填完昵称和紧急联系人
- **THEN** 引导结束，直接进入首页，可以预约

#### Scenario: 后端仍返回 IDENTITY_NOT_VERIFIED
- **WHEN** 下单或语音解析收到 403 `IDENTITY_NOT_VERIFIED`
- **THEN** App 按普通失败播报，不跳转任何实名页面

