# 约跑页：精确位置关闭告知 + 开放范围提示（#813）

- 状态：**待确认**（负责人 2026-11-11 尚未批）。批准前不改 Swift。
- 稿：`booking-gate.png` / `booking-gate.html`。改前 / 改后 × 默认字号 / AX5，共 6 屏。
- 开放城市句子由后端 `launchScope.areaHint` 下发，稿里的「深圳市」只是示例；客户端不写死城市。
- 文案不新写：告知复用 `BlindBookingViewModel.preciseLocationOffNotice` / `locationDeniedNotice`。
- 不在本稿：隐私提醒（法律文案，后放）、50 米精度核对、重复当前状态、默认地点自动带入、缺项卡。
