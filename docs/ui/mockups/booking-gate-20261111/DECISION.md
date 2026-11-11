# 约跑页：精确位置关闭 + 开放范围提示（#813）

- 状态：**Current**（负责人 2026-11-12 批 v2，「可以，开始改」）。v1（大段说明卡 + 两个按钮，`booking-gate-v1.*`）负责人 2026-11-11 不同意，嫌丑、嫌长。
- v2（现行稿，`booking-gate.png` / `.html`）：点「开始找陪跑员」时直接弹系统权限框；拒绝后一个系统样式小提示（原因 + 选常用地点 / 去设置）；页面只加一行开放范围和卡底一行小字。
- 开放城市句子由后端 `launchScope.areaHint` 下发，稿里「深圳市」只是示例。
- 依据：`docs/research/precise-location-prompt-20261111.md`。
- 要同步改的规格：`openspec/specs/blind-precise-location-gate/spec.md`「精确位置关闭时下单不用当前位置作出发点」（原要求页面显示降级告知 + 两个入口）。
- 不在本稿：隐私提醒（后放）、50 米精度核对、重复当前状态、默认地点自动带入、缺项卡。
- 系统弹窗已在 iOS 26.2 模拟器真弹核对：`system-temp-precise-prompt-ios26.png`（标题、「不允许 / 允许一次」为系统原样）。
