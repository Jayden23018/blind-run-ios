## 1. 文案与确认

- [x] 1.1 `removeFavoriteConfirmation` 改为每次都返回确认（没退出的一档用短文案，已退出的一档原样），单测改为守「每次都确认」
- [x] 1.2 新增盲人端列表 / 详情页文案（说明卡、组名、行说明、读屏整句、详情页各行）

## 2. 列表页

- [x] 2.1 `BlindFavoriteVolunteersView` 改成说明卡 + 两组一人一行，整行进详情页，空态改说明卡
- [x] 2.2 页面标题改「固定搭档」，藏标签栏

## 3. 详情页

- [x] 3.1 新增 `BlindPartnerDetailView`：头像、名字、日期、连续周数卡、一起跑完次数
- [x] 3.2 举报 / 不再匹配复用 `CounterpartSafetyActions(.groupedRows)`，行高 64pt
- [x] 3.3 「取消固定搭档」红字组 + 每次确认；未收藏的人放 64pt「设为固定搭档」

## 4. 验证

- [x] 4.1 改 `testBlockingAPartnerRemovesTheRowWithoutLeakingStateToTheNext` 为进详情页操作；新增列表与详情页 UI 用例和无障碍审计
- [x] 4.2 真机跑覆盖改动的用例，`passed=N failed=0`
- [x] 4.3 真机截图（亮 / 暗 / AX5），`aidrun-visual-verdict` 对照定稿 ≥ 90 分
- [x] 4.4 定稿图放 `docs/ui/mockups/blind-partners-20261105/`，INDEX 加一行
