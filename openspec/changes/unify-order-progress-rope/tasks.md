## 1. 配色

- [x] 1.1 `FlowPalette` 加 `stateMatching` / `stateCalling` / `stateCalled`，进 `FlowDesignSystemTests.heroStates`（`stateCalling` / `stateCalled` 已于 #446 删除，见视觉稿 v2）

## 2. 进度绳

- [x] 2.1 `RopeGeometry` 改为刻度几何：四个等距刻度、「我」在左逐格前进、对方在右
- [x] 2.2 `RopeView` 画刻度与刻度文字（两端各一套名字），汇合态改画并肩插图
- [x] 2.3 `RopeTogetherIllustration` 接受头卡色与两侧称呼
- [x] 2.4 读屏标签补「接下来：…」
- [x] 2.5 单测：刻度位置、「我」的停靠点、读屏标签

## 3. 订单页

- [x] 3.1 盲人端匹配中、陪跑员端邀请改灰蓝；汇合头卡居中
- [x] 3.2 盲人端汇合页加「打电话给<姓氏>」（底部按钮区第三个版位）
- [x] 3.3 单测：头卡色映射、打电话按钮的出现条件
- [ ] 3.4 真机：相关单测 + `ScreenTourTests` 截图目视
