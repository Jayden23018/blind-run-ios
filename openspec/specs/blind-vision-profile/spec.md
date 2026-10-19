# blind-vision-profile Specification

## Purpose
定义盲人视力状况在档案更新请求里如何表达同意、拒绝与未被问过，以及志愿者如何看到「未提供」，避免把「用户没说」伪造成「用户说了」或覆盖已存数据。
## Requirements
### Requirement: 明确拒绝时显式传 NOT_SPECIFIED

用户在视力状况单独同意页明确拒绝后，或撤回已给的同意后，档案更新请求 MUST 携带 `visionLevel = NOT_SPECIFIED` 与 `guideDog = NOT_SPECIFIED`，且 MUST NOT 携带 `hasGuideDog`。

#### Scenario: 用户拒绝
- **WHEN** 用户在同意页选择不同意并保存资料
- **THEN** 请求体 `visionLevel` 与 `guideDog` 都是 `NOT_SPECIFIED`，不含 `hasGuideDog`

#### Scenario: 用户撤回同意
- **WHEN** 用户已同意并选过「有导盲犬」，然后按「撤回同意」
- **THEN** 请求体 `visionLevel` 与 `guideDog` 都是 `NOT_SPECIFIED`，不含 `hasGuideDog`

### Requirement: 未被问过时不带键

用户没有拒绝也没有同意（例如新设备本机没有同意记录）时，请求 MUST NOT 携带 `visionLevel`、`guideDog` 与 `hasGuideDog`，使后端保留原值。

#### Scenario: 从没被问过
- **WHEN** 用户未进入同意页就保存资料
- **THEN** 请求体不含 `visionLevel`、`guideDog` 与 `hasGuideDog`

### Requirement: 存量 NOT_SPECIFIED 回读为「不填」

档案里已有 `visionLevel = NOT_SPECIFIED` 时，资料页 MUST 将其显示为「不填」，保存时 MUST NOT 重发该键。

#### Scenario: 回读存量档案
- **WHEN** 已有档案 `visionLevel` 为 `NOT_SPECIFIED` 并进入资料页
- **THEN** 视力状况选择为「不填」，保存请求不含 `visionLevel`

### Requirement: 志愿者侧不展示「未提供」

跑者视力状况为 `NOT_SPECIFIED`、而引导方式给了值时，志愿者侧 MUST 在视力情况一行显示「请当面与跑者确认」，MUST NOT 显示「未提供」。视力与引导方式都未提供时按「陪跑员端两项都未提供时合成一句」处理。

#### Scenario: 志愿者查看
- **WHEN** 订单的 `visionLevel` 为 `NOT_SPECIFIED`，`tetherPreference` 为 `TETHER_ROPE`
- **THEN** 视力情况一行的值为「请当面与跑者确认」

### Requirement: 导盲犬三选一

同意后，资料页 MUST 让用户在「有 / 没有 / 不说」三项中选一项，并按选项发 `guideDog = YES / NO / NOT_SPECIFIED`。读档案时 MUST 以 `guideDog` 为准；档案是「未提供」时 MUST 选中「不说」，保存时 MUST 原样发 `NOT_SPECIFIED`，MUST NOT 改写成 `NO`。读屏 MUST 念出当前选中项，可点区域高度 MUST 不小于 64pt。

#### Scenario: 未提供原样带回
- **WHEN** 档案 `guideDog` 为 `NOT_SPECIFIED`，用户已同意，没碰导盲犬那一项就保存
- **THEN** 请求体 `guideDog` 为 `NOT_SPECIFIED`

#### Scenario: 选「没有」
- **WHEN** 用户已同意并选「没有」后保存
- **THEN** 请求体 `guideDog` 为 `NO`

### Requirement: 牵引方式可以撤回

档案里已有牵引方式，用户在资料页改选「还没决定」后保存时，请求 MUST 携带 `tetherPreference = NOT_SPECIFIED`。档案本来就没填或是 `NOT_SPECIFIED` 时，选「还没决定」MUST NOT 携带该键。

#### Scenario: 从牵引绳改回还没决定
- **WHEN** 档案 `tetherPreference` 为 `TETHER_ROPE`，用户改选「还没决定」并保存
- **THEN** 请求体 `tetherPreference` 为 `NOT_SPECIFIED`

### Requirement: 陪跑员端两项都未提供时合成一句

已接单的陪跑员查看订单时，跑者的视力状况与牵引方式都缺失或都是 `NOT_SPECIFIED`，陪跑要求 MUST 只显示一句「跑者没有填写，出发前请当面问清楚怎么带」，MUST NOT 显示两行「请当面与跑者确认」。邀请卡上跑者那行小字在这种情况下 MUST NOT 出现「请当面与跑者确认」。

#### Scenario: 订单页两项都未提供
- **WHEN** 已接单订单的 `visionLevel` 与 `tetherPreference` 都是 `NOT_SPECIFIED`
- **THEN** 陪跑要求只有导盲犬（如有）与「跑者没有填写，出发前请当面问清楚怎么带」

#### Scenario: 邀请卡两项都未提供
- **WHEN** 邀请的 `visionLevel` 与 `tetherPreference` 都是 `NOT_SPECIFIED`
- **THEN** 跑者行小字不含「请当面与跑者确认」

### Requirement: 下单页把未决定的牵引方式当作没填

档案 `tetherPreference` 为 `NOT_SPECIFIED` 时，下单页 MUST 显示「还没填『希望怎么被引导』」那条提示。

#### Scenario: 新账号下单
- **WHEN** 档案 `tetherPreference` 为 `NOT_SPECIFIED`，用户打开下单页的更多选项
- **THEN** 引导方式提示出现

