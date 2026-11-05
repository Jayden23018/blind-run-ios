## Why

陪跑员「我的」还是一张二十来行的设置列表：常用入口（培训、空闲时间、证书、搭档、积分、邀请）和只读信息、账户操作混在一起，往下翻才找得到。负责人 2026-11-04 批准定稿 `docs/ui/mockups/volunteer-settings-20261104/settings-final.png`（照 Apple 健康 App 版式，只学版式，图标和颜色用自己的），issue #700 剩下的就是这一页。

## What Changes

- 「我的」顶部换成头像卡（名字 +「个人资料、实名与账户」），点进**新的账户页**。
- 账户页：头像、名字、当前角色；「个人资料」行，「实名认证」「资质审核」两行只读状态；「隐私」组（隐私与授权、已拉黑的人）；最底「退出登录」「删除账户」和一句「删除账户会永久停用，需要再次确认。」。
- 「我的」中部「类别」：六个两列彩色方块 —— 陪跑培训、空闲时间、资质证书、固定搭档、我的积分、邀请好友（原「我的邀请码」）。读屏念「名称，按钮」；AX3 及以上字号改单列。
- 「我的」下部列表：服务成就（第一行，带「N 次 · 时长」，原顶部累计卡）、联系客服、我的工单、通知、使用帮助、关于；调试包的 API 环境放最后。
- 现有入口一个不少，所有 `accessibilityIdentifier` 原样保留。首页头像进来的同一页标题仍叫「设置」、不显示服务成就行（与原来不显示累计卡一致）。
- 盲人端「我的」不变。

## Capabilities

### New Capabilities
- `volunteer-settings-tab`: 陪跑员「我的」与账户页上各入口放在哪、念什么、大字号下怎么排。

### Modified Capabilities
- `profile-tab-summary`: 陪跑员这一侧的累计卡改成列表第一行「服务成就」。

## Impact

- 代码：`blindRun/Volunteer/VolunteerOrderFlowViews.swift`（删掉 `VolunteerSettingsView`）、新文件 `VolunteerSettingsView.swift`、`VolunteerAccountView.swift`；`VolunteerProfileAchievementsCard.swift` 改成列表行。
- 测试：进退出登录 / 删除账户 / 个人资料 / 隐私与授权 / 已拉黑的人的 UI 用例多一跳（先点头像卡）。
- 接口：不改。不碰 `AppColors.swift` 以外的共享样式；不碰首页 `VolunteerProfileFirstScreenView*.swift`。
