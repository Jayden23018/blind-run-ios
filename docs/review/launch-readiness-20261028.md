# 上线就绪复核：能不能给真实用户用（2026-10-28）

- 对象：iOS `origin/main` `7d9255c2`（2026-10-22）；后端只读 `origin/main` `0c349fae`（2026-10-27）。
- 方法：① 逐条复核 2026-10-08 上线检查单里全部 ❌ 21 条与 ❓ 7 条（检查单原件 `audit/checklist.md`、`audit/report.md` 在主 checkout 里**未入库**）；② 两端界面静态审查 8 项（颜色、字体、按钮、可点区、读屏标签、用词、空 / 加载 / 失败态、导航）；③ 外部规则补查，见 `docs/research/launch-readiness-external-20261028.md`。
- 限制：全部是读代码与文档的判断。**真机这天离线**（`devicectl` 里 iPhone 与 iPad 都是 `unavailable`），对比度、可点区高度、AX 档截断都没量过。

## 0. 结论

**现在还不能给真实用户用。** 10-08 的 7 条「必须修」里 4 条已修（续期、语音大模型同意、高德隐私开关、中文本地化），2 条部分修（公开仓库凭证、精确位置关闭），1 条只能真人做（送审录屏）。复核又找出 6 条没有 issue 的缺口和 33 条影响盲人 / 低视力用户的界面问题，都已立 issue。

上线前必须清掉的：

| # | 阻断项 | 谁能做 | 跟踪 |
|---|---|---|---|
| 1 | 没有举报与拉黑（审核指南 1.2；陪跑撮合陌生人也需要「不再匹配此人」） | 后端先定接口，再 iOS | backend#880、#524 |
| 2 | 陪跑员出发后切外部导航，位置共享中断且无提示 | iOS | #523 |
| 3 | 界面 A 档 33 条：系统样式按钮对比度 4.02:1、盲人端 19 处可点区 < 64pt、4 处失败不播报、称呼与语音同义词不一致 | iOS | #527 |
| 4 | 精确位置关闭时还有三处上传模糊坐标 | iOS（会话在做） | #407 |
| 5 | 持续定位不停、登出失败后推送仍绑旧账号 | iOS（会话在做） | #425、#459 |
| 6 | 公开仓库历史里有生产固定验证码号码；仓库仍 PUBLIC；生产 admin 是否已改密两份后端文档说法相反 | 负责人 / 后端 | backend#823、backend#833 |
| 7 | Time Sensitive 推送能力未勾选（紧急推送在专注模式下会被压住） | 负责人（开发者后台） | #201 |
| 8 | 送审两机录屏、ASC 账号与年龄分级 / 隐私标签 / 营养标签填写、开发者协议（10-13 更新）接受 | 负责人 | #377 |
| 9 | 隐私审核 5 个 PR 的真机手动验收（VoiceOver、系统设置、截图） | 负责人（要人拿手机） | #410 |
| 10 | 单测与 UI 测试：本轮所有改动都要在真机上跑 | 要真机在线 | — |

应修但不阻断首轮小范围 TestFlight 的：推送权限启动即弹（#521）、证书错误只说「检查网络」（#522）、WebSocket 凭证在 URL 里（backend#881 → #525）、没有强制更新（backend#882 → #526，**首个公开版本必须带上**，否则第一批用户永远收不到）。

## 1. 10-08 检查单 28 条的现状

汇总：已修 8 / 部分修 5 / 仍未修 8 / 只能真人或负责人 7。10-08 之后主线合了 76 个提交（第 603 → 679 个）。

| 编号 | 一句话问题 | 现在 | 证据 | 跟踪 |
|---|---|---|---|---|
| A1 / M7 | 缺两机录屏、审核账号 | 只能真人 | `docs/testflight/test-information.md` 录屏仍是 `<VIDEO_URL>` 占位；账号后端已建 | #377 |
| A3 | 新 Bundle ID 后高德 key、APNs topic 要跟着换 | 只能负责人 | Bundle ID 10-20 换为 `com.culiu-tech.blindrun`（#492 / PR #493）；`blindRun/blindRun.entitlements` 只有 `aps-environment` | #201、backend#830 |
| A6 | 审核备注没写「不替代 110/120」 | 本轮已修 | `test-information.md` §2.2 HELP / SOS 段 | #377 |
| A7 | 相机用途说明漏证书拍照 | 已修 | `blindRun/Info.plist:17`（PR #388） | — |
| A9 | 高德数据分析默认开、回退页占位 | 已修（线上政策正文没核） | `blindRun/Map/AMapManager.swift:108-109`（PR #365，真机 17/0） | — |
| A11 | 没有举报 / 拉黑 | 仍未修 | `blindRun/` 搜「举报」「拉黑」「不再匹配」0 处；契约无端点 | backend#880、#524 |
| A18 | ASC 年龄分级、隐私标签、营养标签 | 只能负责人 | 仓库无记录 | #377 |
| A19 | 推送权限启动即弹 | 仍未修 | `blindRun/blindRunApp.swift:113` → `:161` → `PushNotificationsManager.swift:58` | #521 |
| B3 | 同意前就向高德声明已同意 | 已修 | `AMapManager.swift:68`（PR #429，真机 21/0） | — |
| B4 / M5 | 高德两项扩展默认开 | 已修 | `AMapManager.swift:108-109`（PR #365，验红 0/1） | — |
| B5 | 行踪轨迹单独同意；视力同意撤回 | 部分修 | PR #415（168/0）、#364（35/0）已合；法务判断无结论；AX5 与首次引导态转人工 | #410 |
| B6 / M3 | 精确位置关闭 | 部分修 | 求助、下单已拦（PR #380，28/0）；陪跑员代发求助、同行上报、语音消歧三处待改 | #407、#410 |
| B9 | 备案链未开始 | 只能负责人 | `docs/pre-launch-checklist.md:250-254` 五项未勾 | — |
| B10 / M4 | 语音转写发大模型无同意 | 已修 | `ConsentGatedVoiceOrderService`（`VoiceOrderService.swift:69`，PR #394，157/0） | 撤回入口 #393 |
| C1 | Keychain 无 ThisDeviceOnly | 已修 | `KeychainTokenStore.swift:37`（PR #389，14/0） | — |
| C4 + G5 / M1 | 公开仓库生产凭证 | 部分修 | 主线文件已清（PR #379）；本轮又清掉 `plan.md` 残留的一个联调号；历史未改写、仓库仍 PUBLIC | backend#823 |
| C6 / E11 | 证书出错只说「检查网络」 | 仍未修 | `blindRun/Core/APIClient.swift:111-112` | #522 |
| C7 / M2 | 登录凭证 24 小时无续期 | 已修 | PR #461（187/0）、#382、#439；后端 7 天 + 30 天 refresh 10-13 部署。残留：没有 access 真过期的端到端真机验证 | #459 |
| C8 | WebSocket token 在 URL | 仍未修 | `WebSocketService.swift:276`；契约 `websocket-protocol.md:14` | backend#881、#525 |
| C12 | 没有强制更新 | 仍未修 | 全仓 0 处 | backend#882、#526 |
| D5 | VoiceOver 开着时播报可能念两遍 | 只能人耳 | `blindRun/Voice/SpeechService.swift:125/131` 自注未验 | #410 |
| D15 | 全量无障碍审计 | 部分修 | 10-12 审计 43/4；之后有 Stop 钩子拦「改视图没跑审计」；志愿者「我的」7 条对比度 | #515、#247 |
| D16 / M6 | 没有中文本地化 | 已修 | `project.pbxproj:345` `developmentRegion = "zh-Hans"`（PR #378） | 定位弹窗截图 #410 |
| D17 | 低视力通道整页目视验收 | 只能真人 | 10-08 后无验收记录 | #527、#515 |
| E13 | 切外部导航后位置共享中断 | 仍未修 | `LiveEscortSessionCoordinator.swift:380` 只在跑步中开后台定位 | #523 |
| G4 | 哪些在途 PR / 变更进首包 | 只能负责人 | 开着的 PR 6 个、未归档 OpenSpec 30 个 | #402 |

## 2. 界面静态审查（8 项）

| 项 | 发现 | A 档 | B 档 | 一句话 |
|---|---|---|---|---|
| 颜色 | 14 | 6 | 8 | `Assets.xcassets/AccentColor.colorset` 未定义颜色、无根 `.tint`，系统样式按钮落到系统蓝（`AppColors.swift:8-11` 量过 4.02:1，暗色 3.65:1，原记 3.38 是算错，#563）；登录页不可用态白字压 `systemGray4` |
| 字体 | 13 | 2 | 11 | 无 `Font.custom` 缺 `relativeTo`、无封顶、无无参 `.fixedSize()`；问题在登录页固定高 52 与语音回读地址 `lineLimit(1)` + `minimumScaleFactor(0.6)`（`BlindBookingView.swift:1613`） |
| 按钮 | 9 | 2 | 7 | 4 套共享组件，同一角色仍有 4–5 种外观；主按钮蓝（`PrimaryButton` 38 处）黄（`FlowActionButton` 12 处）并存；「重复当前状态」5 种外观 |
| 可点区 | 23 | 19 | 4 | 盲人端 19 处 < 64pt 或无 frame；守卫 `small-touch-target` 只认 `minHeight`，看不到 `.frame(height:)` / `.frame(width:height:)` |
| 读屏标签 | 0 | 0 | 0 | 16 个纯图标按钮全有标签；装饰图都被祖先容器覆盖 |
| 用词 | 13 | 0 | 13 | 陪跑一方 6 种叫法；盲人端同一旅程先听「志愿者」再看「陪跑员」；语音词表只认「联系志愿者」（`Voice/VoiceStatusQuery.swift:277`）——这一条对盲人是功能问题，#527 按 A 处理 |
| 空 / 加载 / 失败 | 11 | 4 | 7 | 主页面三态齐全；盲人端 4 处失败只显示文字、不播报（`ContentView.swift:276` 启动恢复失败页最要紧） |
| 导航 | 7 | 0 | 7 | 两个「个人资料」页无导航标题；同一订单 4 种页面标题；二级页只有 9 处隐藏标签栏 |

A 档逐条位置见 #527。**读屏通道做得扎实**（标签、遍历顺序、手势替代都有），主要短板在低视力视觉通道和触达尺寸，与 08-12、10-08 两次审查的判断一致。

### 查过了不是问题（防止下轮重提）

- 压在 token 底色上的 `.white` / `.black`、盲道黄底黑字（`AppColors.swift:144`，12.32:1）、跑步中页亮暗同值、星火夜空色板、widget 自带色板（widget target 编译不到 `AppColors`）。
- DEBUG 专用的 Mock 横幅、测试入口、模拟按钮、整个星火 tab（`BlindRunnerTabView.swift:62-69`）不进发布包。发布包只允许连云端（`EnvironmentConfig.swift:20-42`），已按审核指南 2.5.19 写进审核备注。
- `FlowMetrics.swift:239-268` 的 `Font.system(size:)` 配 `@ScaledMetric`，会随字号缩放；`EmergencyCountdownView.swift:218` 大数字 `accessibilityHidden`，倒计时靠声音与播报；`BlindActiveRunView.swift:55/100` 的 `minimumScaleFactor(0.7)` 是设计稿 §23 对 AX5 的要求。
- 导航栏图标「视觉 44 + `contentShape` 64」写法（`BlindOrderStatusView.swift:2388-2389`）；志愿者端 44/48pt（`design-direction.md` §6.1 例外表）。
- 本地拨号降级叫「紧急呼叫」是 AGENTS §6 明令。

## 3. 上线路径建议

1. 代码侧：清完第 0 节表里 1–5，以及 #521 #522 #526。
2. 负责人侧：#201 勾选 Time Sensitive、#377 录屏与 ASC 填写、接受 10-13 开发者协议、backend#823 的凭证处置、备案链。
3. 真机：本轮所有 PR 的覆盖 suite 跑到 `passed=N failed=0`；再按 Apple 无障碍营养标签评估标准（VoiceOver / Larger Text / 对比度）走一遍真机验收，结果写进 #410。
4. 首轮外部测试：照 Be My Eyes 的做法先小范围（`pre-launch-checklist.md` §D 的 3–5 人），内部全角色先走一遍再请视障测试者。

## 4. 没法确认的

- 线上证书状态与线上隐私政策正文（`openssl s_client` 超时）。
- 生产 admin 是否已改密、联调号是否还在生产名单（后端两份文档说法相反，见 backend#833）。
- 所有对比度、可点区高度、AX 档截断的数字：没有真机截图。
