## Why

陪跑员注册第 1 步「基本信息与身份核验」是一整屏长表单：姓名、手机号、身份证号、跑步经验、陪跑开关、急救经验挤在一起，必填和选填混排，提交按钮在最底下，不滚到底看不到还差什么（`current/O-reg-step1.png`）。

负责人 2026-11-04 批准陪跑员端六个二级页照苹果同功能页重做（#699，定稿 `docs/ui/mockups/volunteer-identity-20261104/identity-final.png`）。这一页参考钱包「添加身份证」：先说明要做哪几步，再一屏只做一件事。

## What Changes

- 进入注册流程先看到说明页：三步一览（填姓名和身份证号 / 写几句陪跑经历 / 刷脸），主按钮「开始」，第二个按钮「不想刷脸？改为上传身份材料」。
- 原第 1 步拆成两屏：第 1 步「姓名和身份证号」（姓名、身份证号、手机号，必填），第 2 步「你的陪跑经历」（陪跑过、跑步经验、急救经验，选填，可跳过）。第 3 步是刷脸。
- 顶部「第 N 步，共 3 步」+ 三段进度条，替换原来的两圈步骤指示。
- 表单行改成分组卡片，字段名在左、输入在右。必填没填完时「下一步」不可点，按钮下面写「还差：xx」。
- **接口不变**：第 2 步点「下一步」（或「跳过」）时，照原样一次提交第 1、2 步的全部字段。提交前的身份证号与人脸单独同意层不改。
- 说明页第二个按钮接现有的「拒绝人脸 → 人工审核」路径：记下这个选择，照常填完第 1、2 步并提交；身份核验通过后直接调现有的拒绝人脸接口，落到现有的「已选择替代认证方式」页。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `direct-volunteer-registration`：「Volunteer registration uses two user-facing steps」改成说明页 + 三步（身份、经历、刷脸），并写明经历与身份同一次提交、说明页提供改走人工审核的入口。

## Impact

- 代码：`blindRun/Volunteer/VolunteerRegistrationFlowView.swift`（视图拆屏；ViewModel 加当前子页与「想走替代路径」两个状态）。
- 测试：`blindRunUITests/blindRunUITests.swift` 里按 `textFields` 下标填表的注册用例要按新屏改；新增注册各屏的无障碍审计用例；新增 ViewModel 单测。
- 接口：无变化。`POST /api/volunteer/registration/step1`、`/step3/face-verify/decline` 照旧。
- 文档：`docs/ui/mockups/volunteer-identity-20261104/`、`docs/ui/mockups/INDEX.md` 表尾一行。
