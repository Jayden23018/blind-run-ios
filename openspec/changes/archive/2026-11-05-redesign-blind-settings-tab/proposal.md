## Why

盲人端「我的」还是一张十几行的设置列表：昵称、角色两行只读信息，紧急呼叫，然后个人资料、搭档、邀请码、拉黑、客服、工单、隐私、实名、帮助、关于、通知、退出、删除排成一长串。负责人 2026-11-05 要求「和陪跑员完全一致」，批准 v1 稿（`docs/ui/mockups/blind-profile-20261105/blind-profile-final.png`）。陪跑员「我的」已由 #712 照健康 App 版式改完，本变更让盲人端用同一套组件（issue #711）。

## What Changes

- 「我的」顶部的昵称、角色两行换成头像卡（名字 +「个人资料、实名与账户」），点进**新的盲人账户页**。
- **「我的」不再有紧急呼叫行**（负责人 2026-11-05 追加决定：「盲人的“我的”界面不需要一个常驻的求助按钮」，追问后选「整行删掉」）。已知后果：非陪跑时 App 内没有可见的紧急拨号入口；读屏用户仍有标签栏容器上的 Magic Tap，陪跑中仍有订单页的「求助与安全」。`BlindProfileEmergencyRow`、`BlindSettingsEmergencyEntry` 及只给它用的分流与文案一起删除。
- 「类别」：四个两列彩色方块 —— 固定搭档、邀请好友（原「我的邀请码」）、使用帮助、联系客服。读屏念「名称，按钮」；AX3 及以上字号改单列。
- 列表：我的工单、通知、关于；调试包的 API 环境放最后。行高不低于 64pt。
- 账户页：头像、名字、「视障跑者」；个人资料、实名认证（带当前状态，可点进实名页）；「隐私」组（隐私与授权、已拉黑的人）；退出登录、删除账户和一句「删除账户会永久停用，需要再次确认。」。退出与两步删除的二次确认原样保留。
- 除紧急呼叫行外，现有入口一个不少，所有 `accessibilityIdentifier` 原样保留。从引导页进来的同一页标题仍叫「设置」。
- 陪跑员端用到的通用组件（方块、行、箭头、头像、分组卡）挪到 `blindRun/Shared/` 并改中性名字，陪跑员端外观与行为不变。

## Capabilities

### New Capabilities
- `blind-settings-tab`: 盲人端「我的」与账户页上各入口放在哪、读屏念什么、大字号下怎么排。

### Modified Capabilities
- `blind-profile-emergency-entry`: 删除「我的」列表里的紧急入口这条要求（#605 加的）；「不放常驻红条」与 Magic Tap 两条不变。

## Impact

- 代码：`blindRun/BlindRunner/BlindRunnerSettingsView.swift`（改版式）、新文件 `BlindAccountView.swift`；新文件 `blindRun/Shared/SettingsTileComponents.swift`、`GroupedCardStyle.swift`（由陪跑员两个文件里挪出来）；陪跑员端改用新名字；`AccountSafetySettingsRows` 不再有调用方，删除；`blindRun/Safety/BlindProfileEmergencyEntry.swift` 只留全屏手势那条链路；`BlindRunnerTabView.swift` 的「我的」不再传紧急入口（容器上的 Magic Tap 与拨号单不动）；`SafetyModule.swift` 删掉只给那一行用的读屏提示。
- 测试：「我的」紧急行的两条点击用例换成「陪跑中、不陪跑都没有这一行」；标签栏用例改断言没有这一行。盲人侧进个人资料 / 退出登录 / 删除账户 / 隐私与授权 / 已拉黑的人的 UI 用例多一跳（先点头像卡）。新增盲人「我的」与账户页审计用例、方块单测。
- 接口：不改。
