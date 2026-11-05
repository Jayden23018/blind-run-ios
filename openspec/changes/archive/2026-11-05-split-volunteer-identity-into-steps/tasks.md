## 1. ViewModel

- [x] 1.1 加 `basicInfoPage`（说明 / 身份 / 经历）与前进、后退、跳过方法；后端把人带回第 1 步时落到身份页
- [x] 1.2 加 `identityPageMissingFields`，第 1 步「下一步」只在它为空时可点
- [x] 1.3 加 `prefersAlternativeIdentityPath`；提交成功且状态到刷脸时直接调 `declineFaceVerify()`，不播活体提示
- [x] 1.4 单测：子页走向、还差字段、替代路径自动拒绝人脸且只打一次 decline

## 2. 视图

- [x] 2.1 说明页：图标、标题、三步列表、「开始」与「不想刷脸？改为上传身份材料」
- [x] 2.2 顶部「第 N 步，共 3 步」+ 三段进度条，第 2 步页内「上一步」「跳过」
- [x] 2.3 第 1、2 步分组卡片表单（左字段名右输入），底部固定按钮 + 「还差：xx」
- [x] 2.4 第 3 步刷脸：圆形图标、三条提示、「开始刷脸」，保留拒绝人脸整行按钮与原有状态提示
- [x] 2.5 同意层、活体调用、结束页不改

## 3. 测试与验收

- [x] 3.1 改 `testMockVolunteerLegacyTrainingCompletesWithoutTrainingAndReturnsHomeUnavailable` 按新屏填表
- [x] 3.2 新增注册各屏无障碍审计（亮 / 暗；陪跑员端不测 AX5，负责人 2026-11-05 定）并截图
- [x] 3.3 真机跑覆盖改动的用例与审计，`passed=N failed=0`（2026-11-05：首轮 23/24，修输入框后复跑审计与两条填表用例 3/3）
- [ ] 3.4 截图与定稿逐项对比（`aidrun-visual-verdict`），截图存本机 `impl/identity/`
      —— 2026-11-05 归档时未执行，转 #740
- [x] 3.5 定稿图进 `docs/ui/mockups/volunteer-identity-20261104/`，`INDEX.md` 表尾加一行
