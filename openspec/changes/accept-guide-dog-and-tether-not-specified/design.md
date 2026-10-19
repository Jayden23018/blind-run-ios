## Context

见 proposal.md「Why」。现状：`BlindProfileResponse` / `BlindProfileUpdateRequest` 是手写模型，偏好类字段一律接成 `String?`、只在展示层转枚举，所以新取值不会让解码失败。后端 #800 已部署（2026-10-19 核对线上 `/v3/api-docs`，两个 schema 都有 `guideDog`）。

## Goals / Non-Goals

**Goals:** 导盲犬三态端到端可表达、可撤回；牵引方式可撤回；陪跑员端与下单页认 `NOT_SPECIFIED`。

**Non-Goals:** 不改契约；不回填已被旧版存成 `NO` 的老用户；不改视力状况与牵引方式两个菜单的样式（它们的可点高度另议）；不动订单级 `hasGuideDogThisRun`（本来就是三态）。

## Decisions

1. **请求只发 `guideDog`，删掉 `hasGuideDog`。** 契约写明两者都带时以 `guideDog` 为准，而线上已是新后端；再带旧键只会多一条要维护的分支。备选「同时带旧键兼容旧后端」被否：没有旧后端要兼容。
2. **响应 `guideDog` 接成 `String?`，展示层转 `GuideDogStatus`。** 与 `visionLevel` / `tetherPreference` 同一个做法，后端以后加值不会让整份档案解码失败。缺键时退回读 `hasGuideDog`：`true` 当「有」，其余当「认不出」。
3. **认不出的取值保存时不带键。** 资料页把它显示为「不说」，但用户没改就保存时不发 `guideDog`，免得把一个这个版本不认识的值覆盖成 `NOT_SPECIFIED`。用户改过就照选的发。
4. **导盲犬选择用 `Menu` 包 `Picker`，自定义整行标签。** 标签内部 `frame(minHeight: 64)` 保证可点区，`accessibilityValue` 念当前选项。备选：分段控件（AX5 截断、高度固定约 32pt）、三行单选按钮（多两次划动）、照搬上方 `Picker(.menu)`（可点区只有文字高度，见记忆 `button-frame-outside-label-does-not-grow-hit-area`）。
5. **牵引方式撤回看「回读基线」。** 进页面时记下档案里认得出的牵引方式；选「还没决定」且基线有值 ⇒ 发 `NOT_SPECIFIED`；基线为空 ⇒ 不带键。
6. **陪跑员端「两项都未提供」的判据只有一处**：缺失、空白或 `NOT_SPECIFIED` 都算未提供。只在两项**都**未提供时合并成一句；只有一项未提供时那一行照旧显示「请当面与跑者确认」（既有要求「志愿者侧不展示『未提供』」不变）。

## Risks / Trade-offs

- [老用户已被存成 `NO`] → 区分不出，界面显示「没有」，用户可以自己改成「不说」。写进 PR 交接。
- [菜单交互在 UI 测试里要先点开再选] → 单测覆盖请求体；真机 UI 用例只验可点高度与读屏值。
- [撤回文案变化] → 「已撤回。视力状况和导盲犬已改成不提供……」与安卓 #91 不再逐字一致，需在 PR 里说明。
