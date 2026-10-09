## 1. 订单页头卡着色

- [x] 1.1 `BlindOrderHero` 加 `tint`，按步骤映射状态色；匹配为白卡
- [x] 1.2 `BlindOrderFlowView.heroCard` 按 `tint` 选样式、文字色、绳子主题；警示改白字加图标
- [x] 1.3 单测：每一步的 `tint` 映射，匹配为 `nil`

## 2. 跑步中 / 已完成

- [x] 2.1 `BlindActiveRunView` 加 `onHero` 前景色开关
- [x] 2.2 `runCard` 改为彩色头卡（青绿 / 绿）+ 并肩绳 + 三个数字，定位新鲜度在彩色底上可读
- [x] 2.3 删除跑者端节奏按钮与 `RunnerRhythm.swift`，同步删除相关单测 / UI 用例

## 3. 标签栏与返回

- [x] 3.1 订单页隐藏标签栏；跑步中 / 已完成恢复返回箭头；更新那段注释

## 4. 陪跑员端节奏卡

- [x] 4.1 删除 `VolunteerRhythmCard`、到达提醒与耳机播报节奏分支，同步测试

## 5. 其余界面

- [x] 5.1 `RopeView` 弹簧阻尼 0.85 → 0.6
- [x] 5.2 首页订单卡加约好态引导绳，读屏仍一站
- [x] 5.3 星火：去掉在线志愿者数，概要与读屏用「N 对跑友正在同行」，0 对时的退路
- [x] 5.4 语音预约屏去掉屏上长提示，改短标题；长提示进主按钮读屏提示
- [x] 5.5 完成页评价图标换跑步小人，读屏为文字档位

## 6. 验收

- [x] 6.1 `build-for-testing` 通过
- [ ] 6.2 真机跑覆盖 suite（`FlowDesignSystemTests` 等单测 + 订单页 / 星火 / 预约相关 UI 用例 + `AccessibilityAuditTests`），`failed=0` 且 `passed>0`
- [ ] 6.3 `ScreenTourTests` 截图 + 零上下文评委连续两轮 ≥8 分（最多 6 轮）
- [ ] 6.4 文档：`design-direction.md` 例外段、`mockups/INDEX.md`、`openspec/specs` 归档
