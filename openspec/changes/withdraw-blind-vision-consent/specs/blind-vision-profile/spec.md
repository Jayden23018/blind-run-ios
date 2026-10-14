## MODIFIED Requirements

### Requirement: 明确拒绝时显式传 NOT_SPECIFIED

用户在视力状况单独同意页明确拒绝后，档案更新请求 MUST 携带 `visionLevel = NOT_SPECIFIED` 与 `hasGuideDog = false`。

#### Scenario: 用户拒绝
- **WHEN** 用户在同意页选择不同意并保存资料
- **THEN** 请求体 `visionLevel` 为 `NOT_SPECIFIED`，`hasGuideDog` 为 `false`

## ADDED Requirements

### Requirement: 撤回视力同意

已同意时，资料页视力区块 SHALL 提供「撤回同意，不再提供这两项」。按下后 SHALL 立即收起两项并整表单保存一次，请求携带 `visionLevel = NOT_SPECIFIED` 与 `hasGuideDog = false`。本机同意记录 MUST 只在这次保存成功后删除，成功后 SHALL 上屏并朗读「已撤回。视力状况和导盲犬已从你的资料里清掉，以后想填可以再点「填写视力状况」。」。保存失败时 MUST NOT 删除同意记录，SHALL 提示「撤回还没有保存成功，请再点一次「保存」。」（首次引导态为「完成」），之后的保存仍按撤回发送。撤回待保存时用户重新同意，那次撤回 SHALL 作废。保存进行中 MUST NOT 能打开同意页。

#### Scenario: 撤回成功
- **WHEN** 已同意的用户按「撤回同意，不再提供这两项」且保存成功
- **THEN** 请求体 `visionLevel` 为 `NOT_SPECIFIED`、`hasGuideDog` 为 `false`，本机同意记录被删除，页面显示并朗读撤回成功那一句

#### Scenario: 撤回保存失败
- **WHEN** 撤回那次保存失败
- **THEN** 本机同意记录仍在，页面提示再按一次保存，下一次保存仍携带 `NOT_SPECIFIED` 与 `false`

#### Scenario: 撤回待保存时重新同意
- **WHEN** 撤回保存失败后用户重新同意并选了视力状况
- **THEN** 下一次保存携带用户这次选的值，不再按撤回发送
