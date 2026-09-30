# blind-vision-profile Specification

## Purpose
定义盲人视力状况在档案更新请求里如何表达同意、拒绝与未被问过，以及志愿者如何看到「未提供」，避免把「用户没说」伪造成「用户说了」或覆盖已存数据。
## Requirements
### Requirement: 明确拒绝时显式传 NOT_SPECIFIED

用户在视力状况单独同意页明确拒绝后，档案更新请求 MUST 携带 `visionLevel = NOT_SPECIFIED`，且 MUST NOT 携带 `hasGuideDog`。

#### Scenario: 用户拒绝
- **WHEN** 用户在同意页选择不同意并保存资料
- **THEN** 请求体 `visionLevel` 为 `NOT_SPECIFIED`，不含 `hasGuideDog`

### Requirement: 未被问过时不带键

用户没有拒绝也没有同意（例如新设备本机没有同意记录）时，请求 MUST NOT 携带 `visionLevel` 与 `hasGuideDog`，使后端保留原值。

#### Scenario: 从没被问过
- **WHEN** 用户未进入同意页就保存资料
- **THEN** 请求体不含 `visionLevel` 与 `hasGuideDog`

### Requirement: 存量 NOT_SPECIFIED 回读为「不填」

档案里已有 `visionLevel = NOT_SPECIFIED` 时，资料页 MUST 将其显示为「不填」，保存时 MUST NOT 重发该键。

#### Scenario: 回读存量档案
- **WHEN** 已有档案 `visionLevel` 为 `NOT_SPECIFIED` 并进入资料页
- **THEN** 视力状况选择为「不填」，保存请求不含 `visionLevel`

### Requirement: 志愿者侧不展示「未提供」

跑者视力状况为 `NOT_SPECIFIED` 时，志愿者侧 MUST 显示「请当面与跑者确认」，MUST NOT 显示「未提供」。

#### Scenario: 志愿者查看
- **WHEN** 订单的 `visionLevel` 为 `NOT_SPECIFIED`
- **THEN** 视力情况一行的值为「请当面与跑者确认」

