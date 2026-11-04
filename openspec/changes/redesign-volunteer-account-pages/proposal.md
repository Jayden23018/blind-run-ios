## Why

陪跑员「我的」下面的三个子页还是旧样子：个人资料是一张表单加底部「提交」，我的积分是一块灰卡加按天分组的明细，资质证书是标题、状态卡和三颗大按钮。负责人 2026-11-04 批准了定稿（`docs/ui/mockups/volunteer-account-pages-20261104/`），要求三页照健康 App / 钱包的版式重做（issue #700）。「我的」页本身等 #697 合并后另做，不在这次变更里。

## What Changes

- 个人资料（从「我的」进入）：改成只读的资料页 —— 头像、姓名、「姓名 / 手机号 / 实名认证」一组行，组下灰字说明这些只显示、不能改。**不再有昵称输入框和「提交」按钮**：后端 #826 M8 规定 `name` 必须等于实名核验的身份证姓名，改成别的一律 400，这个输入框实际改不了任何东西。注册时填的陪跑经历三项后端不返回，不画。
- 未通过审核的陪跑员落地的认证页（根路由 `volunteerProfile`）行为不变，只把视图改名为 `VolunteerCertificationGateView`，与新的资料页分开。
- 我的积分：余额卡（大数字 + 「本月 +N · 共 N 笔」）→「最新记录」一张卡，每笔一行（图标、原因与日期、加减分）→ 页脚灰字放两条合规文案（一字不改）。本月小结由客户端按已加载的流水算，算不全（还有更早的页没加载、或有时间解析不出的流水）就不显示。不再按天分组。
- 资质证书：顶部一张证书卡表示状态（未提交 = 虚线空卡、审核中 = 灰卡、已通过 = 蓝卡、未通过 = 红卡，卡上都写状态文字），下面一句标题 + 说明；拍照 / 相册 / 文件三种来源做成带图标的行；「重新获取状态」与「重复当前状态」降为一组行，审核中也能重新获取状态。上传按钮在选好文件后出现。上传与状态逻辑不变。

## Capabilities

### New Capabilities
- `volunteer-account-pages`: 陪跑员「我的」下个人资料、我的积分、资质证书三页显示什么、数据从哪来、能做什么。

### Modified Capabilities

（无）

## Impact

- 代码：`blindRun/Volunteer/VolunteerModule.swift`、`blindRun/ContentView.swift`（根路由改用改名后的认证页）、`blindRun/Volunteer/VolunteerPoints.swift`、`blindRun/Volunteer/VolunteerPointsView.swift`、`blindRun/Volunteer/VolunteerCertificateUploadView.swift`，新文件 `VolunteerAccountProfileView.swift`、`VolunteerAccountPagesStyle.swift`。
- 接口：全部是现有接口（`GET /api/volunteer/points`、`GET /api/volunteer/verification/status`、`POST /api/volunteer/verification`）；个人资料页不发请求，读 `AppState` 已有的资料、当前用户与注册状态。不改后端。
- 不碰：`VolunteerOrderFlowViews.swift`（#697 在改）、`AppColors.swift`（#696 在改）。
