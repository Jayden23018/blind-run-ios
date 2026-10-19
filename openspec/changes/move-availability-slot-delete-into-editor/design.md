## Context

见 proposal.md。页面原本是 `List` + `Section(header:footer:)`，删除靠 `ForEach.onDelete`，编辑页是 sheet 里的 `Form`。保存是 view model 的全量 `save()`，增删改都先改 `slots` 再整体 PUT。

## Goals / Non-Goals

**Goals:**
- 整页审计（亮 / 暗、默认 / 最大字号）真机转绿，不加白名单。
- 删除仍可用，且对读屏用户比左滑更好找。

**Non-Goals:**
- 不改编辑页的 `Form`（它没有报同类误报）。
- 不改保存语义（仍是整体 PUT）与接口。

## Decisions

- **容器用常驻 `ScrollView` + `LazyVStack` 以外的普通 `VStack`**：`List` 与懒加载容器都会让屏外元素离开无障碍树，审计放大字号时找不到它们就判「改不了字号」。普通 `VStack` 全部常驻。替代方案「保留 `List`、带红合入」被负责人否掉（审计常红等于没有门禁）。
- **分组卡片自己画**：组标题、白卡（行间分隔线）、页脚，颜色只用 `AppColors.Flow.page` / `surface`、`FlowSeparator`、`AppColors.textSecondary` 等已有 token 与组件，不新增颜色。
- **删除按钮放编辑页底部、确认用 `.alert`**：与 `EmergencyContactsView` 删除联系人一致（标题「确认删除…」、destructive 的「确认删除」+「取消」、一句说明）。按钮只在编辑已有一段时出现（新增时 `deletion == nil`）。
- **「日期」推出的列表页同样用常驻 `ScrollView`**：它也是本变更里自己画的页面，用 `List` 会撞上同一类审计误报。
- **view model 按 `id` 删除**：`remove(id:)` 取代 `remove(at:)`（后者只服务 `onDelete`，换容器后没有调用方，一并删掉）。
- **读屏标签用原来那段的描述**：删除的是保存过的那段，不是编辑中的草稿，所以标签取打开编辑页时的那段（「删除这一段，周六，07:00 – 09:00」；以看得见的字开头，语音控制才找得到）。

## Risks / Trade-offs

- [行很多时 `VStack` 全量渲染] → 一个人的空闲时段通常个位数，30 天窗口的一次性时段最多也就几十行，不构成性能问题。
- [左滑删除的肌肉记忆失效] → 编辑页底部的删除按钮在点开任意一段时都看得见；读屏用户原本就要找转子动作，现在少一步。
- [二级页底部被标签栏盖住] → 页面已 `.toolbar(.hidden, for: .tabBar)`，换容器后保留；UI 用例滚到最后一行断言可点。
