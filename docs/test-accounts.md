# 测试账号（已作废，只留获取方式）

本仓库是**公开**的，这里不记录任何手机号、验证码、用户名或密码。

- 测试账号、管理员账号与它们的前置条件，以后端仓库 `blind-run-backend` 的 `docs/test-accounts.md` 为准；账号与验证码**向后端负责人索取**。
- 拿到后只放进本机环境变量，不要写进本仓库的文档、脚本默认值、提交信息或 PR 描述。

各脚本读的环境变量（都没有默认值，缺了会在发请求前报错退出）：

| 脚本 | 环境变量 |
|------|----------|
| `scripts/admin-review-volunteer.mjs` | `AIDRUN_ADMIN_USERNAME`、`AIDRUN_ADMIN_PASSWORD`，外加 `AIDRUN_ADMIN_REVIEW_USER_ID` 或 `AIDRUN_ADMIN_REVIEW_PHONE` |
| `scripts/cloud-e2e.mjs` | `AIDRUN_E2E_VERIFICATION_CODE`、`AIDRUN_E2E_BLIND_PHONE`、`AIDRUN_E2E_VOLUNTEER_PHONE` |
| `scripts/capture-fixtures.mjs` | `AIDRUN_FIXTURE_BLIND_TOKEN` / `AIDRUN_FIXTURE_VOLUNTEER_TOKEN`（首选），或 `AIDRUN_FIXTURE_*_PHONE` + `AIDRUN_FIXTURE_CODE` |

> 2026-10-09 起本文件只保留获取方式（Jayden23018/blind-run-backend#641）。旧版本内容不要从 git 历史里抄回来。
