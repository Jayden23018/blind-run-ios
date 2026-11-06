## Why

负责人 2026-11-06 自己用盲人端走了一遍，原话：「是有很多的表单要填，盲人不可能去填这么多的表单和信息」（#807）。
逐页盘点后，真正要填很多项的二级页只有两处：

- 从通讯录添加紧急联系人：选完人还要面对 6 个控件（换人、姓名、手机号、关系、主联系人开关、右上角保存）。
- 首页「默认出发地点 › 添加常用地点」：进的是整张约跑表单。

个人资料页由 #784 改成先看后改，不在本变更。评价、取消、留言、举报、工单只有 0–1 项必填，不改。

## What Changes

- 从通讯录选人后进一页「确认添加」：姓名、尾号、短信告知，底部一个「添加」。号码不是 11 位手机号时改进手动表单。
- 新增时不再有「关系」和「设为主联系人」：第一位自动是主联系人，其余在编辑页设；关系在编辑页补。
- 手动输入只剩姓名、手机号；新增、编辑都从弹出层改成推进一页，「保存 / 添加」在底部，返回 = 不保存。
- 首页「添加常用地点」改成独立一页：顶部「使用当前定位」，中间搜索（苹果语音），下面是最近跑过的地点（取自已完成订单的起点）。点一行 = 收藏并设为默认出发地点。

不改后端契约：新增联系人仍走 `POST /api/users/{userId}/emergency-contacts`（姓名、手机号必填），最近地点用现有 `GET /api/orders/mine`。

## Impact

- `blindRun/Profile/EmergencyContactsView.swift`、`EmergencyContactFormView.swift`、`EmergencyContactFormCopy.swift`，新文件 `EmergencyContactAddConfirmPage.swift`。
- 新文件 `blindRun/BlindRunner/BlindFavoritePlaceAddPage.swift`；`BlindRunnerHomeView.swift` 的 `.addFavoritePlace` 去向。
- #805 的约跑前补联系人门页复用 `EmergencyContactAddConfirmPage`。
