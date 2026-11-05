# Tasks

## 1. 判定

- [x] 1.1 新增 `VolunteerAvailabilityStatus.resolve`，覆盖每种不可派单原因
- [x] 1.2 新增 `VolunteerReadinessProgress.resolve`，五步状态、标题、去处
- [x] 1.3 判定单测，并做验红

## 2. 界面

- [x] 2.1 新增总进度页，首页可进
- [x] 2.2 注册结束页接总进度，去掉「注册完成」「无需课程或答题」
- [x] 2.3 证书页写清一束光证书与没有证书的去处，文案集中一处
- [x] 2.4 证书页、进度页显示被拒原因；重填身份信息页显示实名被拒原因
- [x] 2.5 滑块四态诚实显示；接单主页胶囊同一判据

## 3. 文档与测试基线

- [x] 3.1 更新 `docs/05-page-specs.md`、`docs/06-data-model.md`、`docs/user-manual.md`
- [x] 3.2 UI 用例基线：`AIDRUN_MOCK_VOLUNTEER_TRAINING_COMPLETED`

## 4. 后端依赖

- [x] 4.1 后端 issue：保存并返回证书被拒原因（blind-run-backend#906）
- [x] 4.2 后端 issue：审核通过补推送（blind-run-backend#907）

## 5. 验证

- [x] 5.1 `build-for-testing`
- [ ] 5.2 真机跑覆盖本次改动的单测与 UI 用例
      —— 2026-11-05 归档时未执行，转 #658
- [ ] 5.3 真机截图，VoiceOver 朗读顺序走一遍
      —— 2026-11-05 归档时未执行，转 #658
