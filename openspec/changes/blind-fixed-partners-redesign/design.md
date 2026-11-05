## Context

见 proposal.md。现状：`BlindFavoriteVolunteersView`（`blindRun/Shared/PartnerListViews.swift`）一人一张卡，卡下挂收藏 / 取消和举报 / 拉黑按钮；取消只在对方已退出时确认（`PartnerStreakCopy.removeFavoriteConfirmation` 对没退出的返回 nil）。陪跑员端 #697 已有列表 + 详情页的写法（`VolunteerPartnersView`、`VolunteerPartnerDetailView`），本次不改它们。定稿：`docs/ui/mockups/blind-partners-20261105/partners-final.png`。

## Goals / Non-Goals

**Goals:**
- 照定稿做列表与详情页，复用 #744 的分组卡（`GroupedCard`、`GroupedCardDivider`、`GroupedCardFootnote`、`SettingsChevron`）和陪跑员端的 `PartnerStreakCells`、`KeyedPartnerRow`、`CounterpartSafetyActions(.groupedRows)`。
- 盲人端每个可点区 ≥ 64pt。

**Non-Goals:**
- 不改按钮组件（#749 在改），主按钮用现有 `PrimaryButton`。
- 不改陪跑员端文件；不改接口与 Mock。

## Decisions

1. **详情页只拿列表传进来的那一行，动作交回列表做**（同陪跑员端）。列表是唯一的数据源；成功后详情页关掉，结果上屏在列表顶部并播报。失败时详情页把原因写在按钮下面（列表那一侧已经播报过，详情页不再念第二遍）。备选「详情页自己调接口」会有两份状态，否决。
2. **`removeFavoriteConfirmation` 改成恒返回确认**：没退出的一档给一段短文案（标题「取消固定搭档？」、确认「取消固定搭档」、次要「保留固定搭档」）；已退出的一档原样保留。返回值从 Optional 改成非 Optional，调用方不再有「不弹窗」分支。
3. **举报 / 不再匹配复用 `CounterpartSafetyActions(.groupedRows)`**，给它加一个行高参数（默认 56，陪跑员端不变），盲人端传 64。备选「盲人端用 `.buttons` 描边按钮」与定稿的蓝字行不符，否决。
4. **连续周数卡盲人端单写一份**：陪跑员那份是 `private` 且带进页长出动效，交接书要求盲人端不加页面自己动的动效。格子计数复用 `PartnerStreakCells`。卡名「连续一起跑」、规则「每周至少一起跑一次，就多记一周。」。
5. **头像**：浅色底 + 同色系字（定稿），颜色只为区分相邻两人，读屏隐藏；退出的人用灰。
6. 新文案放新文件 `PartnerStreakCopy+Blind.swift`，不往已 460 行的 `PartnerStreaks.swift` 里堆。

## Risks / Trade-offs

- [`.groupedRows` 加参数波及陪跑员端] → 默认值保持 56，陪跑员端调用点不改。
- [拉黑后已推开的详情页] → 列表行用 `KeyedPartnerRow`（按 userId 作身份），行消失时详情页随之退出；UI 用例守「状态不串到下一位」。
- [Mock 里两个人同叫「王*」] → Mock 数据不在本次范围，UI 用例按标识找行，不按名字。
