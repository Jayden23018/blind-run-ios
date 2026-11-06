# Tasks

## 1. 紧急联系人

- [x] 1.1 新文件 `EmergencyContactAddConfirmPage.swift`：选人后的确认页（姓名、尾号、首位时说明会成为主联系人、短信告知、底部「添加」、「换一位联系人」）。
- [x] 1.2 `EmergencyContactFormView.swift`：新增态去掉关系行与主联系人开关，去掉表单内的「从通讯录选择」；「取消 / 保存」从工具栏挪成返回与底部按钮。
- [x] 1.3 `EmergencyContactsView.swift`：新增、编辑从弹出层改成推进一页；通讯录选人后号码有效进确认页，无效进手动表单并带上已选的值。

## 2. 添加常用地点

- [x] 2.1 新文件 `BlindFavoritePlaceAddPage.swift`：使用当前定位、搜索（`VoiceTextField` + `PlaceSearchProviding`）、最近跑过的地点（`myOrders` 里已完成订单的起点，去重，最多 5 个）。
- [x] 2.2 `BlindRunnerHomeView.swift`：`.addFavoritePlace` 改进新页；选中后回首页并朗读结果。

## 3. 收尾

- [x] 3.1 `xcodebuild build-for-testing` 通过（2026-11-06，`** TEST BUILD SUCCEEDED **`）。负责人 11-05 定不跑测试，单测与 UI 测试只编译、未执行。
- [ ] 3.2 `docs/ui/mockups/INDEX.md` 那一行写实现落点与偏差。
